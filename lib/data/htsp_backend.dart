import 'dart:async';

import 'htsp_connection.dart';
import 'models.dart';
import 'tvh_address.dart';
import 'tvh_models.dart';

/// Channels, guide and recordings kept in step with the server over HTSP.
///
/// The server pushes every change, so nothing is polled. Identifiers are
/// HTSP's numeric ids, as strings: a channel's [Channel.id] is its channel id
/// and a recording's uuid is its DVR id.
class HtspBackend {
  HtspBackend._(this.source, this._address, this._connection);

  final SourceConfig source;
  final TvhAddress _address;
  final HtspConnection _connection;

  final Map<int, _HtspChannel> _channels = <int, _HtspChannel>{};
  final Map<int, _HtspTag> _tags = <int, _HtspTag>{};
  final Map<int, Map<String, Object?>> _events = <int, Map<String, Object?>>{};
  final Map<int, Map<String, Object?>> _dvr = <int, Map<String, Object?>>{};
  final StreamController<void> _changes = StreamController<void>.broadcast();
  final Completer<void> _synced = Completer<void>();
  StreamSubscription<Map<String, Object?>>? _subscription;
  Timer? _debounce;
  Timer? _horizon;
  int _guideHours = 12;
  bool _closed = false;

  /// Fires (debounced) whenever channels, guide or recordings changed.
  Stream<void> get changes => _changes.stream;

  /// Completes when the server's connection ends.
  Future<void> get closed => _connection.closed;

  bool get isClosed => _closed || _connection.isClosed;

  /// Connects, logs in and downloads everything; completes once the server
  /// says its initial sync is done (or after [syncTimeout]).
  static Future<HtspBackend> open(
    SourceConfig source, {
    required int guideHours,
    Duration syncTimeout = const Duration(seconds: 40),
  }) async {
    final address = TvhAddress.parse(source.address);
    final connection = await HtspConnection.open(
      host: address.host,
      port: source.htspPort,
      username: source.username,
      password: source.password,
    );
    final backend = HtspBackend._(source, address, connection)
      .._guideHours = guideHours;
    backend._subscription = connection.messages.listen(backend._onMessage);
    try {
      await backend._enable();
      await backend._synced.future.timeout(syncTimeout, onTimeout: () {});
    } catch (_) {
      await backend.close();
      rethrow;
    }
    backend._horizon = Timer.periodic(
      const Duration(minutes: 30),
      (_) => unawaited(backend._enable().catchError((Object _) {})),
    );
    return backend;
  }

  Future<void> _enable() async {
    final until = DateTime.now().add(Duration(hours: _guideHours + 3));
    await _connection.request('enableAsyncMetadata', <String, Object?>{
      'epg': 1,
      'epgMaxTime': until.millisecondsSinceEpoch ~/ 1000,
    });
  }

  Future<void> close() async {
    _closed = true;
    _horizon?.cancel();
    _debounce?.cancel();
    await _subscription?.cancel();
    await _connection.close();
    if (!_changes.isClosed) {
      await _changes.close();
    }
  }

  // ---- incoming messages ---------------------------------------------------

  void _onMessage(Map<String, Object?> message) {
    final method = message['method'];
    switch (method) {
      case 'channelAdd':
      case 'channelUpdate':
        final id = _int(message['channelId']);
        if (id != null) {
          _channels[id] = _HtspChannel.fromMessage(message);
        }
      case 'channelDelete':
        _channels.remove(_int(message['channelId']));
      case 'tagAdd':
      case 'tagUpdate':
        final id = _int(message['tagId']);
        if (id != null) {
          _tags[id] = _HtspTag(
            id: id,
            name: _string(message['tagName']),
            index: _int(message['tagIndex']) ?? 0,
          );
        }
      case 'tagDelete':
        _tags.remove(_int(message['tagId']));
      case 'eventAdd':
      case 'eventUpdate':
        final id = _int(message['eventId']);
        if (id != null) {
          _events[id] = message;
        }
      case 'eventDelete':
        _events.remove(_int(message['eventId']));
      case 'dvrEntryAdd':
      case 'dvrEntryUpdate':
        final id = _int(message['id']);
        if (id != null) {
          _dvr[id] = message;
        }
      case 'dvrEntryDelete':
        _dvr.remove(_int(message['id']));
      case 'initialSyncCompleted':
        if (!_synced.isCompleted) {
          _synced.complete();
        }
      default:
        return;
    }
    if (_synced.isCompleted) {
      _notify();
    }
  }

  void _notify() {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 600), () {
      if (!_closed && !_changes.isClosed) {
        _changes.add(null);
      }
    });
  }

  // ---- snapshots -----------------------------------------------------------

  String get _user => source.username;
  String get _pass => source.password;

  /// Enabled channels, sorted by number then name, with their group tags.
  List<Channel> channels() {
    final order = <_HtspTag>[..._tags.values]..sort((a, b) {
        final byIndex = a.index.compareTo(b.index);
        return byIndex != 0
            ? byIndex
            : a.name.toLowerCase().compareTo(b.name.toLowerCase());
      });
    final rank = <int, int>{
      for (var i = 0; i < order.length; i++) order[i].id: i,
    };
    final result = <Channel>[];
    for (final channel in _channels.values) {
      final known = channel.tags.where(rank.containsKey).toList()
        ..sort((a, b) => rank[a]!.compareTo(rank[b]!));
      final names = <String>[for (final id in known) _tags[id]!.name];
      result.add(
        Channel(
          id: '${channel.id}',
          sourceId: source.id,
          name: channel.name.isEmpty ? '${channel.id}' : channel.name,
          number: channel.number > 0 ? '${channel.number}' : '',
          url: _address.streamUrlById(
            channel.id,
            user: _user,
            pass: _pass,
            profile: source.profile,
          ),
          logoUrl: _address.imageUrl(channel.icon, user: _user, pass: _pass),
          group: names.isEmpty ? null : names.first,
          tags: names,
        ),
      );
    }
    result.sort((a, b) {
      final an = int.tryParse(a.number) ?? 0;
      final bn = int.tryParse(b.number) ?? 0;
      final aZero = an == 0 ? 1 : 0;
      final bZero = bn == 0 ? 1 : 0;
      if (aZero != bZero) {
        return aZero.compareTo(bZero);
      }
      if (an != bn) {
        return an.compareTo(bn);
      }
      return a.name.toLowerCase().compareTo(b.name.toLowerCase());
    });
    return result;
  }

  /// The guide, with each programme marked when the server records it.
  EpgData guide() {
    final cutoff = DateTime.now().subtract(const Duration(hours: 1));
    final byChannel = <String, List<Programme>>{};
    for (final event in _events.values) {
      final channelId = _int(event['channelId']);
      final eventId = _int(event['eventId']);
      final start = _int(event['start']);
      final stop = _int(event['stop']);
      if (channelId == null ||
          eventId == null ||
          start == null ||
          stop == null ||
          !_channels.containsKey(channelId)) {
        continue;
      }
      final end = DateTime.fromMillisecondsSinceEpoch(stop * 1000);
      if (end.isBefore(cutoff)) {
        continue;
      }
      final dvrId = _int(event['dvrId']);
      final dvr = dvrId == null ? null : _dvr[dvrId];
      final summary = _string(event['summary']);
      final description = _string(event['description']);
      final subtitle = _string(event['subtitle']);
      final season = _int(event['seasonNumber']);
      final episode = _int(event['episodeNumber']);
      final label = <String>[
        if (season != null && season > 0) 'S$season',
        if (episode != null && episode > 0) 'E$episode',
      ].join(' ');
      final categories = <String>[];
      final rawCategory = event['category'];
      if (rawCategory is List) {
        categories.addAll(rawCategory.whereType<String>());
      }
      final year = _int(event['year']);
      final facts = <String>[
        if (year != null && year > 0) '$year',
        ...categories,
      ].join(' · ');
      (byChannel['$channelId'] ??= <Programme>[]).add(
        Programme(
          channelId: '$channelId',
          start: DateTime.fromMillisecondsSinceEpoch(start * 1000),
          stop: end,
          title: _string(event['title']),
          subTitle: subtitle.isNotEmpty
              ? subtitle
              : (description.isNotEmpty && summary.isNotEmpty ? summary : null),
          description: description.isNotEmpty
              ? description
              : (summary.isNotEmpty ? summary : null),
          categories: categories,
          iconUrl: _address.imageUrl(
            _string(event['image']),
            user: _user,
            pass: _pass,
          ),
          episode: label.isEmpty ? null : label,
          eventId: eventId,
          dvrUuid: dvr == null ? null : '$dvrId',
          dvrState: dvr == null ? null : _string(dvr['state']),
          facts: facts.isEmpty ? null : facts,
        ),
      );
    }
    for (final list in byChannel.values) {
      list.sort((a, b) => a.start.compareTo(b.start));
    }
    return EpgData.fromMap(byChannel);
  }

  List<TvhRecording> recordings() {
    final result = <TvhRecording>[];
    for (final entry in _dvr.values) {
      final id = _int(entry['id']);
      if (id == null) {
        continue;
      }
      final state = _string(entry['state']);
      final error = _string(entry['error']);
      final channelId = _int(entry['channel']);
      final channel = channelId == null ? null : _channels[channelId];
      var size = 0;
      final files = entry['files'];
      if (files is List) {
        for (final file in files) {
          if (file is Map) {
            size += _int(file['size']) ?? 0;
          }
        }
      }
      if (size == 0 && (state == 'completed' || state == 'recording')) {
        // Older servers do not list file sizes; a nonzero value is enough to
        // mark the file as playable.
        size = files is List && files.isNotEmpty ? 1 : 0;
      }
      final subtitle = _string(entry['subtitle']);
      final description = _string(entry['description']);
      final summary = _string(entry['summary']);
      final image = _string(entry['image']);
      result.add(
        TvhRecording(
          uuid: '$id',
          channelUuid: channelId == null ? '' : '$channelId',
          channelName: channel?.name ?? _string(entry['channelName']),
          title: _string(entry['title']),
          subtitle: subtitle.isNotEmpty ? subtitle : summary,
          description: description,
          start: DateTime.fromMillisecondsSinceEpoch(
            (_int(entry['start']) ?? 0) * 1000,
          ),
          stop: DateTime.fromMillisecondsSinceEpoch(
            (_int(entry['stop']) ?? 0) * 1000,
          ),
          status: error.isNotEmpty ? error : state,
          schedStatus: state == 'completed' && error.isNotEmpty
              ? 'completedError'
              : state,
          fileSize: size,
          errors: error.isEmpty ? 0 : 1,
          imageSource: image.isEmpty
              ? null
              : _address.imageUrl(image, user: _user, pass: _pass),
        ),
      );
    }
    result.sort((a, b) => a.start.compareTo(b.start));
    return result;
  }

  /// Address of a recording's file.
  String recordingUrl(String dvrId) =>
      _address.dvrUrl(dvrId, user: _user, pass: _pass);

  // ---- actions -------------------------------------------------------------

  Future<void> recordEvent(int eventId) async {
    await _connection.request('addDvrEntry', <String, Object?>{
      'eventId': eventId,
    });
  }

  /// Records every showing of the programme's title on its channel.
  Future<void> recordSeries(Programme programme) async {
    final channel = int.tryParse(programme.channelId);
    await _connection.request('addAutorecEntry', <String, Object?>{
      'title': programme.title,
      if (channel != null) 'channelId': channel,
    });
  }

  Future<void> recordNow(String channelId, String title, int minutes) async {
    final channel = int.tryParse(channelId);
    if (channel == null) {
      throw HtspException('Unknown channel');
    }
    final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    await _connection.request('addDvrEntry', <String, Object?>{
      'channelId': channel,
      'start': now,
      'stop': now + minutes * 60,
      'title': title,
    });
  }

  Future<void> stopRecording(String id) => _byId('stopDvrEntry', id);
  Future<void> cancelRecording(String id) => _byId('cancelDvrEntry', id);
  Future<void> removeRecording(String id) => _byId('deleteDvrEntry', id);

  Future<void> _byId(String method, String id) async {
    final parsed = int.tryParse(id);
    if (parsed == null) {
      throw HtspException('Unknown recording');
    }
    await _connection.request(method, <String, Object?>{'id': parsed});
  }
}

class _HtspChannel {
  const _HtspChannel({
    required this.id,
    required this.name,
    required this.number,
    required this.icon,
    required this.tags,
  });

  factory _HtspChannel.fromMessage(Map<String, Object?> message) {
    final rawTags = message['tags'];
    return _HtspChannel(
      id: _int(message['channelId'])!,
      name: _string(message['channelName']),
      number: _int(message['channelNumber']) ?? 0,
      icon: _string(message['channelIcon']),
      tags: <int>[
        if (rawTags is List)
          for (final tag in rawTags)
            if (tag is int) tag,
      ],
    );
  }

  final int id;
  final String name;
  final int number;
  final String icon;
  final List<int> tags;
}

class _HtspTag {
  const _HtspTag({required this.id, required this.name, required this.index});

  final int id;
  final String name;
  final int index;
}

int? _int(Object? value) {
  if (value is int) {
    return value;
  }
  if (value is double) {
    return value.toInt();
  }
  if (value is bool) {
    return value ? 1 : 0;
  }
  return null;
}

String _string(Object? value) => value is String ? value : '';
