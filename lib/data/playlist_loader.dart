// The cache directory parameter cannot use an initializing formal because
// named parameters cannot be private.
// ignore_for_file: prefer_initializing_formals
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'fetcher.dart';
import 'm3u_parser.dart';
import 'models.dart';
import 'xmltv_parser.dart';

class SourceLoadException implements Exception {
  SourceLoadException(this.message, {this.cause});

  final String message;
  final Object? cause;

  @override
  String toString() => message;
}

/// Everything needed to render one source at a given moment.
class SourceContent {
  const SourceContent({
    required this.playlist,
    required this.epg,
    required this.warnings,
    required this.loadedAt,
    this.xmltvLocation,
    this.playlistFromCache = false,
    this.epgFromCache = false,
  });

  final Playlist playlist;
  final EpgData epg;
  final Set<LoadWarning> warnings;
  final DateTime loadedAt;
  final String? xmltvLocation;
  final bool playlistFromCache;
  final bool epgFromCache;
}

/// Loads playlists and XMLTV, falling back to the last successful snapshot
/// when the network is unavailable. The cache is deliberately per-source so
/// switching sources never mixes channel ids or programme data.
class PlaylistLoader {
  PlaylistLoader({
    MawjFetcher? fetcher,
    Directory? cacheDirectory,
    this.xmltvParser = const XmltvParser(),
    this.cacheMaxAge = const Duration(days: 30),
  })  : _fetcher = fetcher ?? MawjFetcher(),
        _cacheDirectory = cacheDirectory;

  final MawjFetcher _fetcher;
  final XmltvParser xmltvParser;

  /// Cached data older than this is ignored.
  final Duration cacheMaxAge;

  Directory? _cacheDirectory;

  Future<SourceContent> load(
    SourceConfig source, {
    bool persist = true,
    bool useCache = true,
  }) async {
    final m3uLocation = source.m3u.value.trim();
    if (m3uLocation.isEmpty) {
      throw SourceLoadException('No playlist location is configured.');
    }

    final cache = useCache ? await _readCache(source) : null;
    final m3uBase = _baseUri(source.m3u);
    final warnings = <LoadWarning>{};

    Playlist playlist;
    try {
      final text = await _fetcher.fetchText(
        m3uLocation,
        allowInsecure: source.allowInsecureCerts,
      );
      final parsed = const M3uParser().parse(
        text,
        sourceId: source.id,
        baseUri: m3uBase,
      );
      if (parsed.channels.isEmpty) {
        throw SourceLoadException(
          'The playlist contains no channels. Check the URL or the file.',
        );
      }
      playlist = Playlist(
        channels: parsed.channels,
        xmltvUrl: parsed.xmltvUrl,
      );
    } catch (error) {
      if (cache != null && cache.playlist.channels.isNotEmpty) {
        return SourceContent(
          playlist: cache.playlist,
          epg: cache.epg,
          warnings: <LoadWarning>{
            ...warnings,
            LoadWarning.playlistFromCache,
            if (cache.epg.isEmpty) LoadWarning.epgUnavailable,
          },
          loadedAt: cache.savedAt,
          xmltvLocation: cache.xmltvLocation,
          playlistFromCache: true,
          epgFromCache: true,
        );
      }
      throw SourceLoadException(_describePlaylistError(error), cause: error);
    }

    final xmltvLocation = _resolveEpgLocation(source, playlist, m3uBase);
    EpgData epg = EpgData.empty();
    var epgFromCache = false;

    if (xmltvLocation == null) {
      warnings.add(LoadWarning.noEpgEndpoint);
    } else {
      try {
        final xml = await _fetcher.fetchText(
          xmltvLocation,
          allowInsecure: source.allowInsecureCerts,
        );
        final parsed = xmltvParser.parse(xml, playlist.channels);
        epg = parsed.epg;
        if (parsed.report.isNotEmpty) {
          debugPrint(
            'Guide for ${source.name}: ${parsed.matchedChannels}/'
            '${playlist.channels.length} channels have programmes.\n'
            '${parsed.report}',
          );
        }
        if (epg.isEmpty) {
          warnings.add(LoadWarning.epgEmpty);
        }
      } catch (error) {
        debugPrint('XMLTV load failed for ${source.name}: $error');
        if (cache != null && !cache.epg.isEmpty) {
          epg = cache.epg;
          epgFromCache = true;
          warnings.add(LoadWarning.epgFromCache);
        } else {
          warnings.add(LoadWarning.epgUnavailable);
        }
      }
    }

    final content = SourceContent(
      playlist: playlist,
      epg: epg,
      warnings: warnings,
      loadedAt: DateTime.now(),
      xmltvLocation: xmltvLocation,
      epgFromCache: epgFromCache,
    );

    if (persist) {
      await _writeCache(source, content);
    }
    return content;
  }

  /// Fetches and parses a candidate source without touching or trusting the
  /// cache. Used by the source editor's "Check" button.
  Future<SourceContent> probe(SourceConfig source) =>
      load(source, persist: false, useCache: false);

  String? _resolveEpgLocation(
    SourceConfig source,
    Playlist playlist,
    Uri? m3uBase,
  ) {
    if (!source.epg.isEmpty) {
      final value = source.epg.value.trim();
      // A local absolute path must not be resolved against a remote playlist
      // URL, or it would turn into an HTTP request for the wrong resource.
      if (source.epg.isFile) {
        if (m3uBase != null && m3uBase.scheme == 'file') {
          return _resolveLocation(value, m3uBase);
        }
        return value;
      }
      return _resolveLocation(value, m3uBase);
    }
    final advertised = playlist.xmltvUrl;
    if (advertised == null || advertised.trim().isEmpty) {
      return null;
    }
    return advertised.trim();
  }

  String _resolveLocation(String value, Uri? base) {
    final parsed = Uri.tryParse(value);
    if (parsed != null && parsed.hasScheme && parsed.scheme != 'file') {
      return value;
    }
    if (parsed != null && parsed.scheme == 'file') {
      return parsed.toFilePath();
    }
    if (base == null) {
      return value;
    }
    try {
      final resolved = base.resolve(value);
      return resolved.scheme == 'file' ? resolved.toFilePath() : resolved.toString();
    } on FormatException {
      return value;
    }
  }

  Uri? _baseUri(SourceEndpoint endpoint) {
    final value = endpoint.value.trim();
    if (value.isEmpty) {
      return null;
    }
    final parsed = Uri.tryParse(value);
    if (parsed != null && parsed.hasScheme) {
      return parsed;
    }
    if (endpoint.isFile) {
      try {
        return Uri.file(value);
      } on ArgumentError {
        return null;
      }
    }
    return null;
  }

  String _describePlaylistError(Object error) {
    if (error is SourceLoadException) {
      return error.message;
    }
    if (error is FetchException) {
      return error.message;
    }
    if (error is FormatException) {
      return 'The playlist could not be parsed: ${error.message}';
    }
    return 'The playlist could not be loaded: $error';
  }

  Future<File?> _cacheFile(SourceConfig source) async {
    try {
      final directory = _cacheDirectory ??=
          Directory(p.join((await getApplicationSupportDirectory()).path, 'cache'));
      if (!await directory.exists()) {
        await directory.create(recursive: true);
      }
      return File(p.join(directory.path, 'source_${_safeId(source.id)}.json'));
    } catch (error) {
      debugPrint('MawjTVH cache directory unavailable: $error');
      return null;
    }
  }

  Future<_CachedContent?> _readCache(SourceConfig source) async {
    final file = await _cacheFile(source);
    if (file == null || !await file.exists()) {
      return null;
    }
    try {
      final raw = await file.readAsString();
      final decoded = jsonDecode(raw);
      if (decoded is! Map) {
        return null;
      }
      final map = decoded.cast<String, dynamic>();
      if (map['version'] != 2 || map['signature'] != _signature(source)) {
        return null;
      }
      final savedAt = DateTime.tryParse(map['savedAt'] as String? ?? '');
      if (savedAt == null ||
          DateTime.now().difference(savedAt) > cacheMaxAge) {
        return null;
      }
      return _CachedContent.fromJson(map, savedAt);
    } catch (error) {
      debugPrint('Ignoring unreadable cache for ${source.name}: $error');
      return null;
    }
  }

  Future<void> _writeCache(SourceConfig source, SourceContent content) async {
    final file = await _cacheFile(source);
    if (file == null) {
      return;
    }
    try {
      final map = <String, dynamic>{
        'version': 2,
        'signature': _signature(source),
        'savedAt': content.loadedAt.toIso8601String(),
        'xmltvLocation': content.xmltvLocation,
        'playlist': content.playlist.channels
            .map(_channelToJson)
            .toList(growable: false),
        'epg': <String, dynamic>{
          for (final channel in content.playlist.channels)
            channel.id: content.epg
                .programmesFor(channel)
                .map(_programmeToJson)
                .toList(growable: false),
        },
      };
      final temporary = File('${file.path}.tmp');
      await temporary.writeAsString(jsonEncode(map), flush: true);
      await temporary.rename(file.path);
    } catch (error) {
      debugPrint('Could not write MawjTVH cache: $error');
    }
  }

  String _signature(SourceConfig source) {
    return '${source.m3u.value.trim()}\u0000${source.epg.value.trim()}';
  }

  String _safeId(String id) => id.replaceAll(RegExp(r'[^A-Za-z0-9_-]'), '_');

  static Map<String, dynamic> _channelToJson(Channel channel) {
    return <String, dynamic>{
      'id': channel.id,
      'sourceId': channel.sourceId,
      'name': channel.name,
      'number': channel.number,
      'url': channel.url,
      'tvgId': channel.tvgId,
      'channelId': channel.channelId,
      'logoUrl': channel.logoUrl,
      'group': channel.group,
    };
  }

  static Channel _channelFromJson(Map<String, dynamic> map) {
    return Channel(
      id: map['id'] as String? ?? '',
      sourceId: map['sourceId'] as String? ?? '',
      name: map['name'] as String? ?? '',
      number: map['number'] as String? ?? '',
      url: map['url'] as String? ?? '',
      tvgId: map['tvgId'] as String? ?? '',
      channelId: map['channelId'] as String? ?? '',
      logoUrl: map['logoUrl'] as String?,
      group: map['group'] as String?,
    );
  }

  static Map<String, dynamic> _programmeToJson(Programme programme) {
    return <String, dynamic>{
      'channelId': programme.channelId,
      'start': programme.start.toIso8601String(),
      'stop': programme.stop.toIso8601String(),
      'title': programme.title,
      'subTitle': programme.subTitle,
      'description': programme.description,
      'categories': programme.categories,
      'iconUrl': programme.iconUrl,
      'episode': programme.episode,
    };
  }

  static Programme? _programmeFromJson(Map<String, dynamic> map) {
    final start = DateTime.tryParse(map['start'] as String? ?? '');
    final stop = DateTime.tryParse(map['stop'] as String? ?? '');
    final title = map['title'] as String? ?? '';
    if (start == null || stop == null || title.isEmpty) {
      return null;
    }
    return Programme(
      channelId: map['channelId'] as String? ?? '',
      start: start,
      stop: stop,
      title: title,
      subTitle: map['subTitle'] as String?,
      description: map['description'] as String?,
      categories: (map['categories'] as List?)
              ?.whereType<String>()
              .toList(growable: false) ??
          const <String>[],
      iconUrl: map['iconUrl'] as String?,
      episode: map['episode'] as String?,
    );
  }
}

class _CachedContent {
  const _CachedContent({
    required this.playlist,
    required this.epg,
    required this.savedAt,
    this.xmltvLocation,
  });

  final Playlist playlist;
  final EpgData epg;
  final DateTime savedAt;
  final String? xmltvLocation;

  factory _CachedContent.fromJson(Map<String, dynamic> map, DateTime savedAt) {
    final channels = (map['playlist'] as List? ?? const <dynamic>[])
        .whereType<Map>()
        .map((item) => PlaylistLoader._channelFromJson(item.cast<String, dynamic>()))
        .where((channel) => channel.id.isNotEmpty && channel.url.isNotEmpty)
        .toList(growable: false);

    final byChannel = <String, List<Programme>>{};
    final epgJson = map['epg'];
    if (epgJson is Map) {
      for (final entry in epgJson.entries) {
        final key = entry.key.toString();
        final rawProgrammes = entry.value;
        if (rawProgrammes is! List) {
          continue;
        }
        final programmes = rawProgrammes
            .whereType<Map>()
            .map((item) => PlaylistLoader._programmeFromJson(
                  item.cast<String, dynamic>(),
                ))
            .whereType<Programme>()
            .toList(growable: false);
        if (programmes.isNotEmpty) {
          byChannel[key] = programmes;
        }
      }
    }

    return _CachedContent(
      playlist: Playlist(channels: channels),
      epg: EpgData.fromMap(byChannel),
      savedAt: savedAt,
      xmltvLocation: map['xmltvLocation'] as String?,
    );
  }
}
