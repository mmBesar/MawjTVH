import 'dart:async';

import 'htsp_connection.dart';
import 'htsp_stream_proxy.dart';
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
  HtspStreamProxy? _proxy;

  /// Set by the owner to hear why a channel cannot be delivered.
  void Function(String channelId, String? issue)? streamStatusListener;
  final Map<String, ({TvhSignal signal, DateTime at})> _liveSignal =
      <String, ({TvhSignal signal, DateTime at})>{};
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
    if (source.htspStream) {
      final proxy = HtspStreamProxy(
        connection,
        profile: source.profile,
        onSignal: (channelId, signal) {
          backend._liveSignal[channelId] = (signal: signal, at: DateTime.now());
        },
        onStatus: (channelId, issue) =>
            backend.streamStatusListener?.call(channelId, issue),
        onSource: (channelId, info) => backend._sourceInfo[channelId] = info,
      );
      try {
        await proxy.start();
        backend._proxy = proxy;
      } catch (_) {
        // No loopback server: fall back to plain HTTP streams.
      }
    }
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

  /// Speed figures of the last recording served, for the problem report.
  String? get recordingStats => _proxy?.recordingStats;

  Future<void> close() async {
    _closed = true;
    _signalIdle?.cancel();
    _horizon?.cancel();
    _debounce?.cancel();
    await _proxy?.close();
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
          // An update may carry only what changed; keep the rest.
          _channels[id] = _HtspChannel.fromMessage(message, _channels[id]);
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
          _events[id] = <String, Object?>{...?_events[id], ...message};
        }
      case 'eventDelete':
        _events.remove(_int(message['eventId']));
      case 'dvrEntryAdd':
      case 'dvrEntryUpdate':
        final id = _int(message['id']);
        if (id != null) {
          _dvr[id] = <String, Object?>{...?_dvr[id], ...message};
        }
      case 'dvrEntryDelete':
        _dvr.remove(_int(message['id']));
      case 'signalStatus':
        if (_int(message['subscriptionId']) == _signalSub) {
          _signal = TvhSignal(
            status: _string(message['feStatus']),
            snrPercent: _percent(message['feSNR']),
            signalPercent: _percent(message['feSignal']),
            ber: _int(message['feBER']),
            unc: _int(message['feUNC']),
          );
          _signalAt = DateTime.now();
          final waiter = _signalWaiter;
          if (waiter != null && !waiter.isCompleted) {
            waiter.complete(_signal);
          }
        }
        return;
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

  /// Server name and version from the HTSP greeting.
  TvhServerInfo get serverInfo => TvhServerInfo(
        name: _string(_connection.server['servername']).isEmpty
            ? 'Tvheadend'
            : _string(_connection.server['servername']),
        version: _string(_connection.server['serverversion']),
      );

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
          url: _proxy?.urlFor('${channel.id}') ??
              _address.streamUrlById(
                channel.id,
                user: _user,
                pass: _pass,
                profile: source.profile,
              ),
          logoUrl: _address.imageUrl(channel.icon, user: _user, pass: _pass),
          group: names.isEmpty ? null : names.first,
          tags: names,
          isRadio: channel.radio || names.any(looksLikeRadioTag),
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
      final onscreen = _string(event['episodeOnscreen']);
      final season = _int(event['seasonNumber']);
      final episode = _int(event['episodeNumber']);
      final part = _int(event['partNumber']);
      final label = onscreen.isNotEmpty
          ? onscreen
          : <String>[
              if (season != null && season > 0)
                'S${season.toString().padLeft(2, '0')}',
              if (episode != null && episode > 0)
                'E${episode.toString().padLeft(2, '0')}',
              if (part != null && part > 0) 'P$part',
            ].join();
      final categories = <String>[];
      final rawCategory = event['category'];
      if (rawCategory is List) {
        categories.addAll(rawCategory.whereType<String>());
      }
      final year = _int(event['year']);
      final age = _int(event['ageRating']);
      final stars = _int(event['starRating']);
      final facts = <String>[
        if (year != null && year > 0) '$year',
        ...categories,
        if (age != null && age > 0) '$age+',
        if (stars != null && stars > 0) '★ ${(stars / 10).toStringAsFixed(1)}',
        if (event['hd'] == 1) 'HD',
        if (event['subtitled'] == 1) 'CC',
      ].join(' · ');
      final credits = _creditsLine(event['credits']);
      final genre = _genreName(_int(event['contentType']));
      if (categories.isEmpty && genre != null) {
        categories.add(genre);
      }
      final firstAired = _int(event['firstAired']);
      final badges = <String>[
        if (_flag(event, const <String>['new'])) 'NEW',
        if (_flag(event, const <String>['repeat'])) 'REPEAT',
        if (_flag(event, const <String>['premiere'])) 'PREMIERE',
        if (_flag(event, const <String>['hd'])) 'HD',
        if (_flag(event, const <String>['widescreen'])) '16:9',
        if (_flag(event, const <String>['subtitled'])) 'CC',
        if (_flag(event, const <String>['audiodesc', 'audioDesc'])) 'AD',
        if (_flag(event, const <String>['deafsigned', 'deafSigned'])) 'SIGNED',
      ];
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
          credits: credits,
          badges: badges,
          genre: genre,
          firstAired: firstAired == null || firstAired <= 0
              ? null
              : DateTime.fromMillisecondsSinceEpoch(firstAired * 1000),
          season: season != null && season > 0 ? season : null,
          episodeNumber: episode != null && episode > 0 ? episode : null,
          seasonCount: _positive(_int(event['seasonCount'])),
          episodeCount: _positive(_int(event['episodeCount'])),
          ageRating: age != null && age > 0 ? age : null,
          rating: stars != null && stars > 0 ? stars / 10 : null,
          year: year != null && year > 0 ? year : null,
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
          playPosition: _int(entry['playposition']) ?? 0,
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
  ///
  /// Over HTSP the file is read through the local proxy, so an account that
  /// has no web interface permission can still watch its recordings.
  String recordingUrl(String dvrId) =>
      _proxy?.urlForRecording(dvrId) ??
      _address.dvrUrl(dvrId, user: _user, pass: _pass);

  /// Frees the tuner of [channelId] as soon as the player leaves it.
  void releaseStream(String channelId) {
    const recording = 'rec:';
    if (channelId.startsWith(recording)) {
      // A recording read through the proxy: close its file on the server.
      final dvrId = int.tryParse(channelId.substring(recording.length));
      if (dvrId != null) {
        _proxy?.releaseRecording(dvrId);
      }
      return;
    }
    final id = int.tryParse(channelId);
    if (id != null) {
      _proxy?.release(id);
    }
    unawaited(_stopSignal());
  }

  // ---- signal --------------------------------------------------------------

  static const int _signalSubscription = 7001;
  int? _signalSub;
  String? _signalChannel;
  TvhSignal? _signal;
  DateTime? _signalAt;
  Completer<TvhSignal?>? _signalWaiter;
  Timer? _signalIdle;

  final Map<String, Map<String, String>> _sourceInfo =
      <String, Map<String, String>>{};

  /// Adapter, network, mux, provider and service the server last used for
  /// [channelId], or null before the channel has been tuned.
  Map<String, String>? sourceInfoFor(String channelId) => _sourceInfo[channelId];

  /// Signal of the tuner serving [channelId], read from a lightweight second
  /// subscription to the same channel (the server shares the tuner, so this
  /// needs no extra tuner and works for any account that may watch TV). The
  /// subscription closes by itself when nobody asks for 20 seconds.
  Future<TvhSignal?> signalFor(String channelId) async {
    final channel = int.tryParse(channelId);
    if (channel == null || isClosed) {
      return null;
    }
    final live = _liveSignal[channelId];
    if (live != null &&
        DateTime.now().difference(live.at) < const Duration(seconds: 6)) {
      // The stream proxy is already receiving this channel's signal.
      return live.signal;
    }
    if (_proxy != null) {
      // In HTSP stream mode the stream itself carries the signal. A second
      // subscription would hold another tuner slot, so never open one.
      return live?.signal;
    }
    _signalIdle?.cancel();
    _signalIdle = Timer(const Duration(seconds: 20), () {
      unawaited(_stopSignal());
    });
    if (_signalChannel == channelId && _signalSub != null) {
      final at = _signalAt;
      if (at != null && DateTime.now().difference(at) < const Duration(seconds: 10)) {
        return _signal;
      }
      return _awaitSignal();
    }
    await _stopSignal();
    _signalChannel = channelId;
    _signalSub = _signalSubscription;
    _signal = null;
    _signalAt = null;
    _signalWaiter = Completer<TvhSignal?>();
    try {
      await _connection.request('subscribe', <String, Object?>{
        'subscriptionId': _signalSubscription,
        'channelId': channel,
        // Only the status messages are wanted; ask the server to keep the
        // media queue tiny so almost no video is sent.
        'queueDepth': 1,
        'weight': 1,
      });
    } on HtspException {
      _signalSub = null;
      _signalChannel = null;
      return null;
    }
    return _awaitSignal();
  }

  Future<TvhSignal?> _awaitSignal() {
    var waiter = _signalWaiter;
    if (waiter == null || waiter.isCompleted) {
      waiter = _signalWaiter = Completer<TvhSignal?>();
    }
    return waiter.future.timeout(
      const Duration(seconds: 6),
      onTimeout: () => _signal,
    );
  }

  Future<void> _stopSignal() async {
    _signalIdle?.cancel();
    final sub = _signalSub;
    _signalSub = null;
    _signalChannel = null;
    if (sub != null && !isClosed) {
      try {
        await _connection.request('unsubscribe', <String, Object?>{
          'subscriptionId': sub,
        });
      } on HtspException {
        // Already gone.
      }
    }
  }

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
      'channelId': ?channel,
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

  /// Tells the server where playback of recording [id] stopped, in seconds.
  /// Other clients of the same account (Kodi, other MawjTVH devices) see it.
  Future<void> setPlayPosition(String id, int seconds) async {
    final parsed = int.tryParse(id);
    if (parsed == null) {
      return;
    }
    await _connection.request('updateDvrEntry', <String, Object?>{
      'id': parsed,
      'playposition': seconds,
    });
    final entry = _dvr[parsed];
    if (entry != null) {
      entry['playposition'] = seconds;
    }
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
    required this.radio,
  });

  factory _HtspChannel.fromMessage(
    Map<String, Object?> message, [
    _HtspChannel? previous,
  ]) {
    final rawTags = message['tags'];
    var radio = previous?.radio ?? false;
    final services = message['services'];
    if (services is List && services.isNotEmpty) {
      // Radio when every service of the channel is audio only.
      radio = services.every(
        (service) =>
            service is Map &&
            _string(service['type']).toLowerCase() == 'radio',
      );
    }
    return _HtspChannel(
      id: _int(message['channelId'])!,
      name: message.containsKey('channelName')
          ? _string(message['channelName'])
          : (previous?.name ?? ''),
      number: _int(message['channelNumber']) ?? previous?.number ?? 0,
      radio: radio,
      icon: message.containsKey('channelIcon')
          ? _string(message['channelIcon'])
          : (previous?.icon ?? ''),
      tags: rawTags is List
          ? <int>[
              for (final tag in rawTags)
                if (tag is int) tag,
            ]
          : (previous?.tags ?? const <int>[]),
    );
  }

  final int id;
  final String name;
  final int number;
  final String icon;
  final List<int> tags;
  final bool radio;
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

/// HTSP reports signal and SNR on a 0..65535 scale.
double? _percent(Object? value) {
  final number = _int(value);
  return number == null ? null : TvhSignal.relativeToPercent(number);
}

/// Tag names that mark radio stations ("Radio", "Radio channels", Arabic...).
bool looksLikeRadioTag(String name) {
  final lower = name.toLowerCase();
  return lower.contains('radio') ||
      name.contains('راديو') ||
      name.contains('إذاعة') ||
      name.contains('اذاعة');
}

/// `credits` is a map of name to role; group the names by role.
bool _flag(Map<String, Object?> event, List<String> names) {
  for (final name in names) {
    final value = event[name];
    if (value == 1 || value == true) {
      return true;
    }
  }
  return false;
}

int? _positive(int? value) => value != null && value > 0 ? value : null;

/// The broad genre of a DVB content code (its high nibble).
String? _genreName(int? contentType) {
  if (contentType == null || contentType <= 0) {
    return null;
  }
  switch (contentType >> 4) {
    case 0x1:
      return 'Movie / Drama';
    case 0x2:
      return 'News / Current affairs';
    case 0x3:
      return 'Show / Game show';
    case 0x4:
      return 'Sports';
    case 0x5:
      return "Children's / Youth";
    case 0x6:
      return 'Music / Dance';
    case 0x7:
      return 'Arts / Culture';
    case 0x8:
      return 'Social / Politics';
    case 0x9:
      return 'Education / Science';
    case 0xA:
      return 'Leisure / Hobbies';
    default:
      return null;
  }
}

String? _creditsLine(Object? raw) {
  if (raw is! Map || raw.isEmpty) {
    return null;
  }
  final byRole = <String, List<String>>{};
  raw.forEach((name, role) {
    if (name is String && name.isNotEmpty) {
      final key = role is String && role.isNotEmpty ? role : 'actor';
      (byRole[key] ??= <String>[]).add(name);
    }
  });
  if (byRole.isEmpty) {
    return null;
  }
  String title(String role) =>
      role.isEmpty ? role : role[0].toUpperCase() + role.substring(1);
  final order = <String>[
    'director',
    'presenter',
    'writer',
    'actor',
    ...byRole.keys.where(
      (r) => !<String>['director', 'presenter', 'writer', 'actor'].contains(r),
    ),
  ];
  return <String>[
    for (final role in order)
      if (byRole.containsKey(role))
        '${title(role)}: ${byRole[role]!.take(6).join(', ')}',
  ].join(' · ');
}
