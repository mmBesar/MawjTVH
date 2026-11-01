import 'package:flutter_test/flutter_test.dart';
import 'package:mawjtvh/data/tvh_address.dart';

void main() {
  TvhAddress parse(String text) => TvhAddress.parse(text);

  test('a bare address uses the Tvheadend default port', () {
    final a = parse('10.0.0.5');
    expect(a.tls, isFalse);
    expect(a.host, '10.0.0.5');
    expect(a.port, 9981);
    expect(a.webroot, '');
    expect(parse('tv.lan:9999').port, 9999);
    expect(parse('  tv.lan  ').host, 'tv.lan');
  });

  test('an explicit scheme uses the standard ports', () {
    final a = parse('https://tv.example.com');
    expect(a.tls, isTrue);
    expect(a.port, 443);
    expect(a.baseUrl, 'https://tv.example.com');
    expect(parse('http://tv.example.com').port, 80);
    expect(parse('https://tv.example.com:8443/').baseUrl,
        'https://tv.example.com:8443');
  });

  test('a web root is kept without its trailing slash', () {
    final a = parse('https://example.com/tvh/');
    expect(a.webroot, '/tvh');
    expect(a.url('/api/x'), 'https://example.com/tvh/api/x');
  });

  test('bad input is refused with a message', () {
    expect(() => parse('  '), throwsA(isA<TvhAddressException>()));
    expect(() => parse('ftp://host'), throwsA(isA<TvhAddressException>()));
    expect(() => parse('http://'), throwsA(isA<TvhAddressException>()));
  });

  test('stream and recording URLs carry an encoded login', () {
    final a = parse('tv.lan');
    expect(
      a.streamUrl('abc123', user: 'bob', pass: 'p@ss'),
      'http://bob:p%40ss@tv.lan:9981/stream/channel/abc123',
    );
    expect(a.streamUrl('abc123'), 'http://tv.lan:9981/stream/channel/abc123');
    expect(
      a.streamUrl('abc123', profile: 'matroska'),
      'http://tv.lan:9981/stream/channel/abc123?profile=matroska',
    );
    expect(
      a.dvrUrl('r1', user: 'bob', pass: 'p@ss'),
      'http://bob:p%40ss@tv.lan:9981/dvrfile/r1',
    );
  });

  test('pct encodes non-ASCII text as UTF-8', () {
    expect(pct('abc-._~'), 'abc-._~');
    expect(pct('a b'), 'a%20b');
    expect(pct('é'), '%C3%A9');
  });

  test('pictures come through the typed address', () {
    final a = parse('https://tv.example.com');
    expect(a.imageUrl('imagecache/12'), 'https://tv.example.com/imagecache/12');
    expect(
      a.imageUrl('imagecache/12', user: 'u', pass: 'p'),
      'https://u:p@tv.example.com/imagecache/12',
    );
    // The server names an address that only works inside its own network.
    expect(
      a.imageUrl('http://tvh:9981/imagecache/12'),
      'https://tv.example.com/imagecache/12',
    );
    expect(
      a.imageUrl('https://pics.example.org/a.png', user: 'u', pass: 'p'),
      'https://pics.example.org/a.png',
    );
    expect(a.imageUrl('logo.png'), isNull);
    expect(a.imageUrl(null), isNull);
    expect(a.imageUrl(''), isNull);
  });

  test('redactUrl shows where a URL points and how it logs in', () {
    expect(
      redactUrl('http://bob:p%40ss@tv.lan:9981/stream/channel/abc'),
      'http://tv.lan:9981/stream/channel/abc (password)',
    );
    expect(
      redactUrl('http://tv.lan:9981/stream/channel/abc?profile=pass'),
      'http://tv.lan:9981/stream/channel/abc',
    );
    expect(
      redactUrl('https://t.example/tvh/stream/channel/a?auth=SECRET'),
      'https://t.example/tvh/stream/channel/a (code)',
    );
  });
}
