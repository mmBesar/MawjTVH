import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mawjtvh/data/http_digest.dart';
import 'package:mawjtvh/data/tvh_client.dart';

String _md5(String text) => md5.convert(utf8.encode(text)).toString();

void main() {
  test('signs the example request from RFC 2617', () {
    final auth = DigestAuth(
      'Mufasa',
      'Circle Of Life',
      cnonce: () => '0a4f113b',
    )..accept(
        const DigestChallenge(
          realm: 'testrealm@host.com',
          nonce: 'dcd98b7102dd2f0e8b11d0f600bfb0c093',
          opaque: '5ccc069c403ebaf9f0171e9517f40e41',
          qop: 'auth',
        ),
      );
    final header = auth.authorization('GET', '/dir/index.html')!;
    expect(header, contains('response="6629fae49393a05397450978507c4ef1"'));
    expect(header, contains('nc=00000001'));
    expect(header, contains('cnonce="0a4f113b"'));
    expect(header, contains('opaque="5ccc069c403ebaf9f0171e9517f40e41"'));
    // The next request uses the next count.
    expect(auth.authorization('GET', '/x'), contains('nc=00000002'));
  });

  test('reads a Digest challenge among others', () {
    final challenge = DigestChallenge.pick(<String>[
      'Basic realm="tvheadend"',
      'Digest realm="tvheadend", qop="auth", nonce="abc123", opaque="xyz"',
    ])!;
    expect(challenge.realm, 'tvheadend');
    expect(challenge.nonce, 'abc123');
    expect(challenge.opaque, 'xyz');
    expect(challenge.qop, 'auth');
    expect(DigestChallenge.pick(<String>['Basic realm="x"']), isNull);
    expect(
      DigestChallenge.parse('Digest realm="a", nonce="n", algorithm=SHA-256'),
      isNull,
    );
  });

  test('the HTTP transport answers a Digest-only server and keeps going', () async {
    const user = 'viewer';
    const password = 'secret';
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    var requests = 0;
    final counts = <String>[];
    server.listen((request) async {
      requests++;
      final header = request.headers.value(HttpHeaders.authorizationHeader);
      var ok = false;
      if (header != null && header.startsWith('Digest ')) {
        final fields = <String, String>{};
        for (final match in RegExp(r'(\w+)=(?:"([^"]*)"|([^,\s]+))')
            .allMatches(header.substring(7))) {
          fields[match.group(1)!] = match.group(2) ?? match.group(3)!;
        }
        final ha1 = _md5('$user:tvh:$password');
        final ha2 = _md5('GET:${request.uri}');
        final expected = _md5(
          '$ha1:n1:${fields['nc']}:${fields['cnonce']}:auth:$ha2',
        );
        ok = fields['username'] == user &&
            fields['uri'] == request.uri.toString() &&
            fields['response'] == expected;
        counts.add(fields['nc'] ?? '');
      }
      if (ok) {
        request.response.write('hello');
      } else {
        request.response.statusCode = HttpStatus.unauthorized;
        request.response.headers.add(
          HttpHeaders.wwwAuthenticateHeader,
          'Digest realm="tvh", qop="auth", nonce="n1"',
        );
      }
      await request.response.close();
    });
    final transport = IoTvhTransport(
      allowInsecure: false,
      username: user,
      password: password,
    );
    try {
      final uri = Uri.parse('http://127.0.0.1:${server.port}/api/test?x=1');
      final first = await transport.send(
        'GET',
        uri,
        headers: <String, String>{
          HttpHeaders.authorizationHeader:
              'Basic ${base64Encode(utf8.encode('$user:$password'))}',
        },
      );
      expect(first.statusCode, 200);
      expect(first.body, 'hello');
      expect(requests, 2); // the challenge, then the signed request

      final second = await transport.send('GET', uri);
      expect(second.statusCode, 200);
      expect(requests, 3); // signed straight away this time
      expect(counts, <String>['00000001', '00000002']);
    } finally {
      transport.close();
      await server.close(force: true);
    }
  });
}
