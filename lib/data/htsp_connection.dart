import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';

import 'htsp_message.dart';

/// A request failed, or the connection broke.
class HtspException implements Exception {
  HtspException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// One HTSP session with a Tvheadend server (default port 9982).
///
/// Requests are answered by sequence number; everything else the server sends
/// (channels, events, recordings, signal) arrives on [messages].
class HtspConnection {
  HtspConnection._(this._socket);

  static const int defaultPort = 9982;
  static const int protocolVersion = 25;

  final Socket _socket;
  final HtspFramer _framer = HtspFramer();
  final Map<int, Completer<Map<String, Object?>>> _waiting =
      <int, Completer<Map<String, Object?>>>{};
  final StreamController<Map<String, Object?>> _messages =
      StreamController<Map<String, Object?>>.broadcast();
  final Completer<void> _closed = Completer<void>();
  int _seq = 0;
  bool _isClosed = false;

  /// What `hello` returned: servername, serverversion, htspversion...
  Map<String, Object?> server = const <String, Object?>{};

  /// Asynchronous messages (those carrying a `method`).
  Stream<Map<String, Object?>> get messages => _messages.stream;

  /// Completes when the connection ends for any reason.
  Future<void> get closed => _closed.future;

  bool get isClosed => _isClosed;

  /// Connects, says hello and logs in. [username] may be empty for servers
  /// that allow anonymous access.
  static Future<HtspConnection> open({
    required String host,
    int port = defaultPort,
    String username = '',
    String password = '',
    String clientName = 'MawjTVH',
    String clientVersion = '0.1.31',
    Duration timeout = const Duration(seconds: 12),
  }) async {
    final Socket socket;
    try {
      socket = await Socket.connect(host, port, timeout: timeout);
    } on SocketException catch (error) {
      throw HtspException('Cannot reach $host:$port (${error.message})');
    } on TimeoutException {
      throw HtspException('Timed out connecting to $host:$port');
    }
    socket.setOption(SocketOption.tcpNoDelay, true);
    final connection = HtspConnection._(socket);
    connection._listen();
    try {
      final hello = await connection.request(
        'hello',
        <String, Object?>{
          'htspversion': protocolVersion,
          'clientname': clientName,
          'clientversion': clientVersion,
        },
        timeout: timeout,
      );
      connection.server = hello;
      if (username.isNotEmpty) {
        final challenge = hello['challenge'];
        if (challenge is! Uint8List) {
          throw HtspException('The server sent no login challenge');
        }
        final digest = sha1.convert(<int>[
          ...utf8.encode(password),
          ...challenge,
        ]);
        final reply = await connection.request(
          'authenticate',
          <String, Object?>{
            'username': username,
            'digest': Uint8List.fromList(digest.bytes),
          },
          timeout: timeout,
        );
        if (reply['noaccess'] == 1 || reply['noaccess'] == true) {
          throw HtspException('The server refused this username or password');
        }
      }
      return connection;
    } catch (_) {
      await connection.close();
      rethrow;
    }
  }

  Timer? _heartbeat;

  void _startHeartbeat() {
    try {
      _socket.setOption(SocketOption.tcpNoDelay, true);
    } catch (_) {}
    _heartbeat = Timer.periodic(const Duration(seconds: 30), (timer) {
      if (_isClosed) {
        timer.cancel();
        return;
      }
      request(
        'getSysTime',
        const <String, Object?>{},
        timeout: const Duration(seconds: 15),
      ).then<void>((_) {}, onError: (Object _) {});
    });
  }

  void _listen() {
    _startHeartbeat();
    _socket.listen(
      (chunk) {
        try {
          for (final message in _framer.add(chunk)) {
            _dispatch(message);
          }
        } on HtspFormatException catch (error) {
          _fail(HtspException(error.toString()));
        }
      },
      onError: (Object error) => _fail(HtspException('$error')),
      onDone: () => _fail(HtspException('The server closed the connection')),
      cancelOnError: true,
    );
  }

  void _dispatch(Map<String, Object?> message) {
    final method = message['method'];
    if (method is String) {
      if (!_messages.isClosed) {
        _messages.add(message);
      }
      return;
    }
    final seq = message['seq'];
    if (seq is int) {
      final waiter = _waiting.remove(seq);
      if (waiter != null && !waiter.isCompleted) {
        final error = message['error'];
        if (error is String && error.isNotEmpty) {
          waiter.completeError(HtspException(error));
        } else {
          waiter.complete(message);
        }
      }
    }
  }

  void _fail(HtspException error) {
    if (_isClosed) {
      return;
    }
    _isClosed = true;
    _heartbeat?.cancel();
    for (final waiter in _waiting.values) {
      if (!waiter.isCompleted) {
        waiter.completeError(error);
      }
    }
    _waiting.clear();
    _socket.destroy();
    if (!_messages.isClosed) {
      _messages.close();
    }
    if (!_closed.isCompleted) {
      _closed.complete();
    }
  }

  /// Sends [method] and waits for its reply.
  Future<Map<String, Object?>> request(
    String method,
    Map<String, Object?> arguments, {
    Duration timeout = const Duration(seconds: 30),
  }) {
    if (_isClosed) {
      return Future<Map<String, Object?>>.error(
        HtspException('The connection is closed'),
      );
    }
    final seq = ++_seq;
    final completer = Completer<Map<String, Object?>>();
    _waiting[seq] = completer;
    try {
      _socket.add(
        Htsmsg.encode(<String, Object?>{
          ...arguments,
          'method': method,
          'seq': seq,
        }),
      );
    } catch (error) {
      _waiting.remove(seq);
      return Future<Map<String, Object?>>.error(HtspException('$error'));
    }
    return completer.future.timeout(
      timeout,
      onTimeout: () {
        _waiting.remove(seq);
        // A server that stops answering is a dead session. Closing it lets the
        // app reconnect instead of staying stuck until it is restarted.
        final error = HtspException('The server did not answer $method');
        _fail(error);
        throw error;
      },
    );
  }

  Future<void> close() async {
    _fail(HtspException('Closed'));
    await _closed.future;
  }
}
