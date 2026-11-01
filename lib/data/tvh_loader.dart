import 'package:flutter/foundation.dart';

import 'htsp_backend.dart';
import 'htsp_connection.dart';
import 'models.dart';
import 'tvh_address.dart';
import 'tvh_client.dart';
import 'tvh_models.dart';

class SourceLoadException implements Exception {
  SourceLoadException(this.message, {this.cause});

  final String message;
  final Object? cause;

  @override
  String toString() => message;
}

/// Everything needed to render one server at a given moment.
class SourceContent {
  const SourceContent({
    required this.playlist,
    required this.epg,
    required this.warnings,
    required this.loadedAt,
    required this.resolvedSource,
    this.permissions = const TvhPermissions(admin: false),
    this.serverInfo = const TvhServerInfo(),
    this.profiles = const <String>[],
    this.playlistFromCache = false,
    this.epgFromCache = false,
    this.htsp,
  });

  final Playlist playlist;
  final EpgData epg;
  final Set<LoadWarning> warnings;
  final DateTime loadedAt;

  /// The server as it really answers: the address may have moved from http to
  /// https or under a web root since it was typed.
  final SourceConfig resolvedSource;
  final TvhPermissions permissions;
  final TvhServerInfo serverInfo;

  /// Stream profile names the account may use.
  final List<String> profiles;
  final bool playlistFromCache;
  final bool epgFromCache;

  /// The live HTSP session when the server is used natively; the owner closes
  /// it.
  final HtspBackend? htsp;

  SourceContent copyWith({
    Playlist? playlist,
    EpgData? epg,
  }) {
    return SourceContent(
      playlist: playlist ?? this.playlist,
      epg: epg ?? this.epg,
      warnings: warnings,
      loadedAt: loadedAt,
      resolvedSource: resolvedSource,
      permissions: permissions,
      serverInfo: serverInfo,
      profiles: profiles,
      htsp: htsp,
    );
  }
}

typedef TvhClientFactory = TvhClient Function(SourceConfig source);

/// Loads channels, groups and the guide from a Tvheadend server.
class TvhLoader {
  TvhLoader({TvhClientFactory? clientFactory})
      : _factory = clientFactory ?? TvhClient.new;

  final TvhClientFactory _factory;

  Future<SourceContent> load(SourceConfig source, {int guideHours = 12}) async {
    final TvhClient client;
    try {
      client = _factory(source);
    } on TvhAddressException catch (error) {
      throw SourceLoadException(error.message, cause: error);
    }
    try {
      await client.followUpgrade();
      final permissions = await client.probe();

      var info = const TvhServerInfo();
      try {
        info = await client.serverInfo();
      } on TvhException {
        // Nice to have, never a reason to fail.
      }

      if (source.useHtsp) {
        return await _loadHtsp(
          source.copyWith(address: client.address.baseUrl),
          client,
          permissions,
          info,
          guideHours,
        );
      }

      final channelRows = await client.rawChannels();
      var tagRows = const <Map<String, dynamic>>[];
      try {
        tagRows = await client.rawTags();
      } on TvhException {
        // Groups are optional; the channels still list.
      }
      final channels = channelsFromJson(
        sourceId: source.id,
        channels: channelRows,
        tags: tagRows,
        client: client,
      );
      if (channels.isEmpty) {
        throw SourceLoadException(
          permissions.admin
              ? 'The server has no enabled channels yet.'
              : 'This account cannot see any channel. Ask the server\'s '
                  'administrator to give it access to channels.',
        );
      }

      final warnings = <LoadWarning>{};
      var epg = EpgData.empty();
      try {
        final horizon = DateTime.now().add(Duration(hours: guideHours + 2));
        final rows = await client.rawEvents(until: horizon);
        final grouped = client.groupEvents(rows);
        final known = <String>{for (final channel in channels) channel.id};
        grouped.removeWhere((uuid, _) => !known.contains(uuid));
        epg = EpgData.fromMap(grouped);
        if (epg.isEmpty) {
          warnings.add(LoadWarning.epgEmpty);
        }
      } on TvhException catch (error) {
        debugPrint('Guide load failed for ${source.name}: $error');
        warnings.add(LoadWarning.epgUnavailable);
      }

      final profiles = await client.streamProfiles();

      return SourceContent(
        playlist: Playlist(channels: channels),
        epg: epg,
        warnings: warnings,
        loadedAt: DateTime.now(),
        resolvedSource: source.copyWith(address: client.address.baseUrl),
        permissions: permissions,
        serverInfo: info,
        profiles: profiles,
      );
    } on SourceLoadException {
      rethrow;
    } on TvhException catch (error) {
      throw SourceLoadException(error.message, cause: error);
    } finally {
      client.close();
    }
  }

  Future<SourceContent> _loadHtsp(
    SourceConfig source,
    TvhClient client,
    TvhPermissions permissions,
    TvhServerInfo info,
    int guideHours,
  ) async {
    final HtspBackend backend;
    try {
      backend = await HtspBackend.open(source, guideHours: guideHours);
    } on HtspException catch (error) {
      throw SourceLoadException(
        'HTSP (port ${source.htspPort}): ${error.message}',
        cause: error,
      );
    }
    final channels = backend.channels();
    if (channels.isEmpty) {
      await backend.close();
      throw SourceLoadException(
        'The server sent no channels over HTSP. Check that this account is '
        'allowed to use HTSP and can see channels.',
      );
    }
    final epg = backend.guide();
    final profiles = await client.streamProfiles();
    return SourceContent(
      playlist: Playlist(channels: channels),
      epg: epg,
      warnings: epg.isEmpty ? <LoadWarning>{LoadWarning.epgEmpty} : <LoadWarning>{},
      loadedAt: DateTime.now(),
      resolvedSource: source,
      permissions: permissions,
      serverInfo: info,
      profiles: profiles,
      htsp: backend,
    );
  }

  /// Reloads only the guide, keeping the channels as they are. Used after a
  /// recording is scheduled, so the guide shows it without a full reload.
  Future<EpgData> loadGuide(
    SourceConfig source,
    List<Channel> channels, {
    int guideHours = 12,
  }) async {
    final client = _factory(source);
    try {
      final horizon = DateTime.now().add(Duration(hours: guideHours + 2));
      final rows = await client.rawEvents(until: horizon);
      final grouped = client.groupEvents(rows);
      final known = <String>{for (final channel in channels) channel.id};
      grouped.removeWhere((uuid, _) => !known.contains(uuid));
      return EpgData.fromMap(grouped);
    } on TvhException catch (error) {
      throw SourceLoadException(error.message, cause: error);
    } finally {
      client.close();
    }
  }

  /// Checks a candidate server without keeping anything.
  Future<SourceContent> probe(SourceConfig source) => load(source);
}
