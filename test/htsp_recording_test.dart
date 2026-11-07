import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:mawjtvh/data/htsp_connection.dart';
import 'package:mawjtvh/data/htsp_message.dart';
import 'package:mawjtvh/data/htsp_stream_proxy.dart';

/// A tiny HTSP server that only knows how to hand out one file.
Future<ServerSocket> _fakeServer(
  Uint8List file,
  List<String> opened,
  List<int> closed,
) async {
  final server = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
  server.listen((socket) {
    var pending = Uint8List(0);
    socket.listen((chunk) {
      pending = Uint8List.fromList(<int>[...pending, ...chunk]);
      var offset = 0;
      while (pending.length - offset >= 4) {
        final length =
            ByteData.sublistView(pending, offset, offset + 4).getUint32(0);
        if (pending.length - offset < 4 + length) {
          break;
        }
        final message = Htsmsg.decodeBody(
          Uint8List.sublistView(pending, offset + 4, offset + 4 + length),
        );
        offset += 4 + length;
        final reply = <String, Object?>{'seq': message['seq']};
        switch (message['method']) {
          case 'hello':
            reply['htspversion'] = 37;
            reply['servername'] = 'fake';
          case 'fileOpen':
            opened.add('${message['file']}');
            reply['id'] = 7;
            reply['size'] = file.length;
          case 'fileRead':
            final at = message['offset'] as int;
            final size = message['size'] as int;
            reply['data'] = Uint8List.sublistView(
              file,
              at,
              math.min(file.length, at + size),
            );
          case 'fileClose':
            closed.add(message['id'] as int);
        }
        socket.add(Htsmsg.encode(reply));
      }
      pending = Uint8List.fromList(pending.sublist(offset));
    });
  });
  return server;
}

Future<(HttpClientResponse, List<int>)> _get(
  HttpClient client,
  String url, {
  String? range,
}) async {
  final request = await client.getUrl(Uri.parse(url));
  if (range != null) {
    request.headers.set(HttpHeaders.rangeHeader, range);
  }
  final response = await request.close();
  final body = <int>[];
  await for (final part in response) {
    body.addAll(part);
  }
  return (response, body);
}

void main() {
  test('serves a recording over HTSP with byte ranges', () async {
    final file = Uint8List.fromList(
      List<int>.generate(600000, (i) => i % 251),
    );
    final opened = <String>[];
    final closed = <int>[];
    final server = await _fakeServer(file, opened, closed);
    final connection = await HtspConnection.open(
      host: '127.0.0.1',
      port: server.port,
    );
    final proxy = HtspStreamProxy(connection);
    await proxy.start();
    final client = HttpClient();
    try {
      final url = proxy.urlForRecording('12');

      final whole = await _get(client, url);
      expect(whole.$1.statusCode, HttpStatus.ok);
      expect(whole.$1.headers.value(HttpHeaders.acceptRangesHeader), 'bytes');
      expect(whole.$2, file);

      final middle = await _get(client, url, range: 'bytes=1000-1999');
      expect(middle.$1.statusCode, HttpStatus.partialContent);
      expect(
        middle.$1.headers.value(HttpHeaders.contentRangeHeader),
        'bytes 1000-1999/600000',
      );
      expect(middle.$2, file.sublist(1000, 2000));

      final tail = await _get(client, url, range: 'bytes=-100');
      expect(tail.$1.statusCode, HttpStatus.partialContent);
      expect(tail.$2, file.sublist(file.length - 100));

      final open = await _get(client, url, range: 'bytes=599000-');
      expect(open.$2, file.sublist(599000));

      final beyond = await _get(client, url, range: 'bytes=700000-');
      expect(beyond.$1.statusCode, HttpStatus.requestedRangeNotSatisfiable);

      // Five requests shared one open file on the server.
      expect(opened, <String>['dvr/12']);
      expect(closed, isEmpty);

      // A response that is still under way must not make leaving throw (it
      // used to, which stopped the player page from ever closing its player).
      final request = await client.getUrl(Uri.parse(url));
      final response = await request.close();
      final held = response.listen((_) {});
      held.pause();
      await Future<void>.delayed(const Duration(milliseconds: 50));

      // Leaving the recording closes the file at once.
      proxy.releaseRecording(12);
      await Future<void>.delayed(const Duration(milliseconds: 200));
      expect(closed, <int>[7]);
      await held.cancel();
    } finally {
      client.close(force: true);
      await proxy.close();
      await connection.close();
      await server.close();
    }
  });
}
