import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
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
    this.onStatus,
    this.onSource,
  });

  final HtspConnection _connection;
  final String profile;

  /// Called with each `signalStatus` of a watched channel, so the signal
  /// badge needs no subscription of its own.
  final void Function(String channelId, TvhSignal signal)? onSignal;

  /// Called with the server's reason when a channel cannot be delivered
  /// (`noFreeAdapter`, `badSignal`...), and with null once media flows.
  final void Function(String channelId, String? issue)? onStatus;

  /// Where the stream comes from (adapter, network, mux, provider, service),
  /// as the server reports it when a subscription starts.
  final void Function(String channelId, Map<String, String> info)? onSource;

  HttpServer? _server;
  int _nextSubscription = 100;

  /// How the last sizeable recording request went, for the problem report.
  String recordingStats = '';
  final Map<int, _Feed> _feeds = <int, _Feed>{};
  final Map<int, _RecordingFile> _files = <int, _RecordingFile>{};

  /// Binds the loopback server. Throws if it cannot.
  Future<void> start() async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    _server = server;
    // Idle connections are dropped quickly, so none is left behind.
    server.idleTimeout = const Duration(seconds: 10);
    server.listen(_handle, onError: (Object _) {});
  }

  bool get isRunning => _server != null;

  /// Ends the subscription for [channelId] now and frees its tuner.
  void release(int channelId) => _feeds[channelId]?.stop();

  /// Ends the connections to a recording and closes its file on the server.
  void releaseRecording(int dvrId) => _endRecording(this, dvrId);

  /// True while a player is watching [channelId] through this proxy.
  bool isActive(int channelId) => _feeds.containsKey(channelId);

  String urlFor(String channelId) =>
      'http://127.0.0.1:${_server!.port}/live/$channelId';

  /// Address of a recording's file, served over HTSP `fileOpen`/`fileRead`.
  String urlForRecording(String dvrId) =>
      'http://127.0.0.1:${_server!.port}/dvr/$dvrId';

  Future<void> close() async {
    final server = _server;
    _server = null;
    for (final feed in _feeds.values.toList()) {
      feed.stop();
    }
    for (final id in _files.keys.toList()) {
      _endRecording(this, id);
    }
    await server?.close(force: true);
  }

  Future<void> _handle(HttpRequest request) async {
    final parts = request.uri.pathSegments;
    if (parts.length == 2 && parts.first == 'dvr') {
      final dvrId = int.tryParse(parts[1]);
      if (dvrId != null) {
        await _serveRecording(this, request, dvrId);
        return;
      }
    }
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

const int _recordingChunk = 256 * 1024;

/// How many chunks are requested ahead of the one being written.
const int _recordingReadAhead = 4;

int? _number(Object? value) {
  if (value is int) {
    return value;
  }
  return value == null ? null : int.tryParse('$value');
}

/// One recording file opened on the server. Every player connection that asks
/// for the same recording shares this single handle, so the server sees one
/// open file however many HTTP connections the player makes.
class _RecordingFile {
  _RecordingFile(this.dvrId);

  final int dvrId;
  int? fileId;
  int size = 0;
  int users = 0;
  Future<void>? opening;
  Timer? closeTimer;
  final Set<HttpRequest> requests = <HttpRequest>{};
}

/// Gets the shared handle for [dvrId], opening the file the first time.
Future<_RecordingFile> _acquireRecording(
  HtspStreamProxy proxy,
  int dvrId,
) async {
  final file = proxy._files.putIfAbsent(dvrId, () => _RecordingFile(dvrId));
  file.closeTimer?.cancel();
  file.closeTimer = null;
  file.users++;
  try {
    final first = file.opening == null;
    file.opening ??= proxy._connection
        .request(
          'fileOpen',
          <String, Object?>{'file': 'dvr/$dvrId'},
          timeout: const Duration(seconds: 20),
        )
        .then<void>((opened) {
      file.fileId = _number(opened['id']);
      file.size = _number(opened['size']) ?? 0;
    });
    await file.opening;
    final id = file.fileId;
    if (id == null) {
      throw HtspException('The server did not open the recording');
    }
    if (!first) {
      // A recording still being made grows: ask for the size again.
      try {
        final stat = await proxy._connection.request(
          'fileStat',
          <String, Object?>{'id': id},
          timeout: const Duration(seconds: 10),
        );
        final size = _number(stat['size']);
        if (size != null && size > 0) {
          file.size = size;
        }
      } catch (_) {}
    }
    return file;
  } catch (_) {
    file.opening = null;
    _releaseRecording(proxy, file);
    rethrow;
  }
}

/// One user of the handle is done; the file closes a moment after the last
/// one (the player often reconnects straight away when it seeks).
void _releaseRecording(HtspStreamProxy proxy, _RecordingFile file) {
  if (file.users > 0) {
    file.users--;
  }
  if (file.users > 0 || !identical(proxy._files[file.dvrId], file)) {
    return;
  }
  file.closeTimer?.cancel();
  file.closeTimer = Timer(
    const Duration(seconds: 3),
    () => _closeRecording(proxy, file),
  );
}

void _closeRecording(HtspStreamProxy proxy, _RecordingFile file) {
  file.closeTimer?.cancel();
  file.closeTimer = null;
  if (identical(proxy._files[file.dvrId], file)) {
    proxy._files.remove(file.dvrId);
  }
  final id = file.fileId;
  file.fileId = null;
  if (id != null && !proxy._connection.isClosed) {
    unawaited(
      proxy._connection
          .request(
            'fileClose',
            <String, Object?>{'id': id},
            timeout: const Duration(seconds: 10),
          )
          .then<void>((_) {}, onError: (Object _) {}),
    );
  }
}

/// Serves a recording's file to the player, with byte ranges so it can seek.
/// The file is read from the server with HTSP, so an account needs no web
/// interface permission, only the right to watch recordings.
Future<void> _serveRecording(
  HtspStreamProxy proxy,
  HttpRequest request,
  int dvrId,
) async {
  final response = request.response;
  _RecordingFile? file;
  try {
    file = await _acquireRecording(proxy, dvrId);
    file.requests.add(request);
    final fileId = file.fileId;
    final size = file.size;
    if (fileId == null) {
      response.statusCode = HttpStatus.notFound;
      await response.close();
      return;
    }

    // Byte range: `bytes=a-b`, `bytes=a-` or `bytes=-n`.
    var start = 0;
    var end = size - 1;
    var partial = false;
    final range = request.headers.value(HttpHeaders.rangeHeader);
    if (range != null && range.startsWith('bytes=') && size > 0) {
      final spec = range.substring(6).split(',').first.trim();
      final dash = spec.indexOf('-');
      if (dash >= 0) {
        final from = int.tryParse(spec.substring(0, dash));
        final to = int.tryParse(spec.substring(dash + 1));
        if (from != null) {
          start = from;
          if (to != null) {
            end = math.min(to, size - 1);
          }
          partial = true;
        } else if (to != null) {
          start = math.max(0, size - to);
          partial = true;
        }
      }
      if (start >= size || start > end) {
        response.statusCode = HttpStatus.requestedRangeNotSatisfiable;
        response.headers.set(HttpHeaders.contentRangeHeader, 'bytes */$size');
        await response.close();
        return;
      }
    }
    final length = size == 0 ? 0 : end - start + 1;
    response
      ..statusCode = partial ? HttpStatus.partialContent : HttpStatus.ok
      ..bufferOutput = false
      // One request per connection: nothing is left open once it is done.
      ..headers.persistentConnection = false
      ..headers.contentType = ContentType.binary
      ..headers.set(HttpHeaders.acceptRangesHeader, 'bytes')
      ..headers.set(HttpHeaders.cacheControlHeader, 'no-store')
      ..headers.contentLength = length;
    if (partial) {
      response.headers.set(
        HttpHeaders.contentRangeHeader,
        'bytes $start-$end/$size',
      );
    }
    if (request.method == 'HEAD' || length == 0) {
      await response.close();
      return;
    }

    Future<Map<String, Object?>> read(int at, int length) {
      final reply = proxy._connection.request(
        'fileRead',
        <String, Object?>{'id': fileId, 'size': length, 'offset': at},
        timeout: const Duration(seconds: 30),
      );
      // Several reads are in flight at once; a failure of one that is still
      // waiting its turn must not be reported as unhandled.
      reply.ignore();
      return reply;
    }

    // Reads run a few chunks ahead of what has been written, so the round
    // trip to the server (large over a VPN or the internet) does not limit
    // the speed.
    final clock = Stopwatch()..start();
    var sent = 0;
    var slowestRead = 0;
    var slowestWrite = 0;
    var position = start;
    var requested = start;
    final queue = <({Future<Map<String, Object?>> reply, int length})>[];
    void fill() {
      while (queue.length < _recordingReadAhead && requested <= end) {
        final length = math.min(_recordingChunk, end - requested + 1);
        queue.add((reply: read(requested, length), length: length));
        requested += length;
      }
    }

    try {
      fill();
      while (queue.isNotEmpty) {
        final item = queue.removeAt(0);
        final waitedFrom = clock.elapsedMilliseconds;
        final reply = await item.reply;
        final waitedTo = clock.elapsedMilliseconds;
        final data = reply['data'];
        if (data is! Uint8List || data.isEmpty) {
          break;
        }
        position += data.length;
        if (data.length < item.length) {
          // A short read (a file still being written): the reads already
          // asked for are misplaced, so ask again from here.
          queue.clear();
          requested = position;
        }
        fill();
        response.add(data);
        await response.flush();
        final wroteTo = clock.elapsedMilliseconds;
        sent += data.length;
        slowestRead = math.max(slowestRead, waitedTo - waitedFrom);
        slowestWrite = math.max(slowestWrite, wroteTo - waitedTo);
        if (sent >= 1024 * 1024) {
          proxy.recordingStats =
              'Recording from the server: ${(sent / 1048576).toStringAsFixed(1)} MB '
              'in ${(wroteTo / 1000).toStringAsFixed(1)} s, '
              'slowest wait for the server $slowestRead ms, '
              'slowest hand-over to the player $slowestWrite ms';
        }
      }
    } finally {
      queue.clear();
    }
    await response.close();
  } catch (_) {
    // The player went away or the server refused the file.
    try {
      response.statusCode = HttpStatus.badGateway;
    } catch (_) {}
    try {
      await response.close();
    } catch (_) {}
  } finally {
    final used = file;
    if (used != null) {
      used.requests.remove(request);
      _releaseRecording(proxy, used);
    }
  }
}

/// The player has left [dvrId]: end its connections and close the file now.
void _endRecording(HtspStreamProxy proxy, int dvrId) {
  final file = proxy._files[dvrId];
  if (file == null) {
    return;
  }
  for (final request in file.requests.toList()) {
    // The response is already under way, so its socket cannot be detached
    // (that throws). Closing it short of its length makes the HttpServer
    // destroy the connection, which is what is wanted here.
    try {
      request.response.close().then<void>((_) {}, onError: (Object _) {});
    } catch (_) {}
  }
  file.requests.clear();
  _closeRecording(proxy, file);
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
    if (identical(proxy._feeds[channel], this)) {
      proxy._feeds.remove(channel);
    }
    for (final client in _clients.toList()) {
      client.close().catchError((Object _) {});
    }
    _clients.clear();
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
          final source = message['sourceinfo'];
          if (source is Map) {
            final info = <String, String>{};
            source.forEach((key, value) {
              if (key is String && value is String && value.isNotEmpty) {
                info[key] = value;
              }
            });
            if (info.isNotEmpty) {
              proxy.onSource?.call('$channel', info);
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
            if (!delivered) {
              proxy.onStatus?.call('$channel', null);
            }
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
        case 'subscriptionStatus':
          final issue = _issue(message);
          if (issue != null) {
            proxy.onStatus?.call('$channel', issue);
          }
        case 'subscriptionStop':
          final reason = _issue(message);
          if (reason != null) {
            proxy.onStatus?.call('$channel', reason);
          }
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

/// The server's reason for a stalled or stopped subscription, if it gave one.
String? _issue(Map<String, Object?> message) {
  final error = message['subscriptionError'];
  if (error is String && error.isNotEmpty) {
    return error;
  }
  final status = message['status'];
  if (status is String && status.isNotEmpty) {
    return status;
  }
  return null;
}
