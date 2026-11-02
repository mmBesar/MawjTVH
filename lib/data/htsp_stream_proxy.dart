import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'htsp_connection.dart';
import 'ts_muxer.dart';
import 'tvh_models.dart';

/// Plays live TV over HTSP by serving it to the player as an ordinary
/// transport stream on a loopback address.
///
/// The player only ever sees one never-ending stream. When the subscription
/// behind it stops (weak signal, a tuner switch, a dropped packet flow) the
/// proxy subscribes again and carries on with the same continuity counters and
/// shifted timestamps, so playback resumes instead of ending.
class HtspStreamProxy {
  HtspStreamProxy(
    this._connection, {
    this.profile = '',
    this.onSignal,
  });

  final HtspConnection _connection;
  final String profile;

  /// Called with each `signalStatus` of a watched channel, so the signal
  /// badge needs no subscription of its own.
  final void Function(String channelId, TvhSignal signal)? onSignal;

  HttpServer? _server;
  int _nextSubscription = 100;
  final Map<int, _Feed> _feeds = <int, _Feed>{};

  /// Binds the loopback server. Throws if it cannot.
  Future<void> start() async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    _server = server;
    server.listen(_handle, onError: (Object _) {});
  }

  bool get isRunning => _server != null;

  String urlFor(String channelId) =>
      'http://127.0.0.1:${_server!.port}/live/$channelId';

  Future<void> close() async {
    final server = _server;
    _server = null;
    for (final feed in _feeds.values.toList()) {
      feed.stop();
    }
    await server?.close(force: true);
  }

  Future<void> _handle(HttpRequest request) async {
    final parts = request.uri.pathSegments;
    final channel = parts.length == 2 && parts.first == 'live'
        ? int.tryParse(parts[1])
        : null;
    if (channel == null) {
      request.response.statusCode = HttpStatus.notFound;
      await request.response.close();
      return;
    }
    final response = request.response
      ..statusCode = HttpStatus.ok
      ..bufferOutput = false
      ..headers.contentType = ContentType('video', 'mp2t')
      ..headers.set(HttpHeaders.cacheControlHeader, 'no-store');
    final feed = _feeds.putIfAbsent(channel, () => _Feed(this, channel));
    feed.attach(response);
    try {
      await response.done;
    } catch (_) {
      // The player went away; nothing to report.
    } finally {
      feed.detach(response);
      try {
        await response.close();
      } catch (_) {}
    }
  }
}

/// One HTSP subscription per channel, shared by every player connection that
/// asks for the channel (mpv often opens a stream twice, and a local recording
/// opens it again), so the server sees a single subscription.
class _Feed {
  _Feed(this.proxy, this.channel);

  final HtspStreamProxy proxy;
  final int channel;
  final TsMuxer _mux = TsMuxer();
  final List<HttpResponse> _clients = <HttpResponse>[];

  bool _running = false;
  bool _stopped = false;
  Timer? _idle;
  Completer<void>? _current;
  bool _rebase = false;
  int _offset = 0;
  int _lastTs = 0;
  bool _haveTs = false;
  DateTime _lastWrite = DateTime.now();
  Timer? _keepAlive;

  HtspConnection get _connection => proxy._connection;

  void attach(HttpResponse response) {
    _idle?.cancel();
    _clients.add(response);
    if (_mux.isConfigured) {
      try {
        response.add(_mux.tables());
      } catch (_) {}
    }
    if (!_running && !_stopped) {
      _running = true;
      unawaited(run());
    }
  }

  void detach(HttpResponse response) {
    _clients.remove(response);
    if (_clients.isEmpty) {
      _idle?.cancel();
      _idle = Timer(const Duration(seconds: 4), () {
        if (_clients.isEmpty) {
          stop();
        }
      });
    }
  }

  void stop() {
    _stopped = true;
    _idle?.cancel();
    final current = _current;
    if (current != null && !current.isCompleted) {
      current.complete();
    }
    proxy._feeds.remove(channel);
  }

  Future<void> run() async {
    // Keep the players' connections busy while the signal is away.
    _keepAlive = Timer.periodic(const Duration(seconds: 1), (_) {
      if (_mux.isConfigured &&
          DateTime.now().difference(_lastWrite) > const Duration(milliseconds: 900)) {
        _write(_mux.tables());
      }
    });
    var failures = 0;
    try {
      while (!_stopped && !_connection.isClosed) {
        final delivered = await _subscribeOnce();
        if (_stopped) {
          break;
        }
        failures = delivered ? 0 : failures + 1;
        if (failures > 20) {
          // About 40 seconds of nothing at all: let the player report it.
          break;
        }
        _rebase = true;
        await Future<void>.delayed(const Duration(seconds: 2));
      }
    } finally {
      _keepAlive?.cancel();
      _running = false;
      stop();
      for (final client in _clients.toList()) {
        try {
          await client.close();
        } catch (_) {}
      }
    }
  }

  void _write(Uint8List bytes) {
    for (final client in _clients.toList()) {
      try {
        client.add(bytes);
      } catch (_) {
        _clients.remove(client);
      }
    }
    _lastWrite = DateTime.now();
  }

  /// One subscription; returns true if it delivered any media.
  Future<bool> _subscribeOnce() async {
    final id = proxy._nextSubscription++;
    final finished = Completer<void>();
    _current = finished;
    var delivered = false;
    var unit90k = true;
    Timer? watchdog;

    void finish() {
      if (!finished.isCompleted) {
        finished.complete();
      }
    }

    void arm(Duration timeout) {
      watchdog?.cancel();
      watchdog = Timer(timeout, finish);
    }

    final subscription = _connection.messages.listen((message) {
      if (message['subscriptionId'] != id) {
        return;
      }
      switch (message['method']) {
        case 'subscriptionStart':
          final streams = <TsStream>[];
          final raw = message['streams'];
          if (raw is List) {
            for (final item in raw) {
              if (item is Map) {
                final index = item['index'];
                final type = item['type'];
                if (index is int && type is String) {
                  final meta = item['meta'];
                  final language = item['language'];
                  streams.add(
                    TsStream(
                      index: index,
                      type: type,
                      meta: meta is Uint8List ? meta : null,
                      language: language is String ? language : '',
                      compositionId: item['composition_id'] is int
                          ? item['composition_id'] as int
                          : 0,
                      ancillaryId: item['ancillary_id'] is int
                          ? item['ancillary_id'] as int
                          : 0,
                    ),
                  );
                }
              }
            }
          }
          _mux.configure(streams);
          _write(_mux.tables());
          arm(const Duration(seconds: 12));
        case 'muxpkt':
          final payload = message['payload'];
          final stream = message['stream'];
          if (payload is! Uint8List || stream is! int) {
            return;
          }
          final frame = message['frametype'];
          var pts = message['pts'] is int ? message['pts'] as int : null;
          var dts = message['dts'] is int ? message['dts'] as int : null;
          if (!unit90k) {
            pts = pts == null ? null : pts * 9 ~/ 100;
            dts = dts == null ? null : dts * 9 ~/ 100;
          }
          final reference = dts ?? pts;
          if (reference == null) {
            return;
          }
          if (_rebase) {
            _offset = _haveTs ? _lastTs + 3600 - reference : 0;
            _rebase = false;
          }
          if (pts != null) {
            pts += _offset;
          }
          if (dts != null) {
            dts += _offset;
          }
          final shifted = reference + _offset;
          if (!_haveTs || shifted > _lastTs) {
            _lastTs = shifted;
            _haveTs = true;
          }
          if (_mux.tablesDue(shifted)) {
            _write(_mux.tables());
          }
          final bytes = _mux.packet(
            stream: stream,
            payload: payload,
            pts: pts,
            dts: dts,
            keyframe: frame == 73, // 'I'
          );
          if (bytes != null) {
            _write(bytes);
            delivered = true;
            arm(const Duration(seconds: 8));
          }
        case 'signalStatus':
          proxy.onSignal?.call(
            '$channel',
            TvhSignal(
              status: message['feStatus'] is String
                  ? message['feStatus'] as String
                  : '',
              snrPercent: _scale(message['feSNR']),
              signalPercent: _scale(message['feSignal']),
              ber: message['feBER'] is int ? message['feBER'] as int : null,
              unc: message['feUNC'] is int ? message['feUNC'] as int : null,
            ),
          );
        case 'subscriptionStop':
          finish();
      }
    });

    try {
      final reply = await _connection.request('subscribe', <String, Object?>{
        'channelId': channel,
        'subscriptionId': id,
        '90khz': 1,
        'queueDepth': 3000000,
        if (proxy.profile.trim().isNotEmpty) 'profile': proxy.profile.trim(),
      });
      unit90k = reply['90khz'] != 0;
      arm(const Duration(seconds: 15));
      await finished.future;
    } on HtspException {
      // Refused or connection trouble: the caller waits and retries.
    } finally {
      watchdog?.cancel();
      await subscription.cancel();
      if (!_connection.isClosed) {
        try {
          await _connection.request('unsubscribe', <String, Object?>{
            'subscriptionId': id,
          });
        } on HtspException {
          // Already gone.
        }
      }
    }
    return delivered;
  }
}

/// HTSP signal values arrive as 0..65535 on current servers and as plain
/// percentages on some; anything above 100 is taken as the long scale.
double? _scale(Object? value) {
  if (value is! num) {
    return null;
  }
  final number = value.toDouble();
  if (number > 100) {
    return (number / 65535.0 * 100.0).clamp(0.0, 100.0).toDouble();
  }
  return number.clamp(0.0, 100.0).toDouble();
}
