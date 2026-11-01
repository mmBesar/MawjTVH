import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mawjtvh/data/fetcher.dart';
import 'package:mawjtvh/data/models.dart';
import 'package:mawjtvh/data/playlist_loader.dart';

class _FakeFetcher extends MawjFetcher {
  _FakeFetcher(this.responses);

  final Map<String, String> responses;

  @override
  Future<String> fetchText(
    String location, {
    required bool allowInsecure,
  }) async {
    final response = responses[location];
    if (response == null) {
      throw const FetchException(
        'Offline in tests.',
        kind: FetchFailureKind.network,
      );
    }
    return response;
  }
}

void main() {
  test('falls back to cache but probe never trusts it', () async {
    final directory = await Directory.systemTemp.createTemp('mawjtvh-loader-');
    addTearDown(() => directory.delete(recursive: true));

    const m3u = 'https://example.com/channels.m3u';
    const source = SourceConfig(
      id: 'primary',
      name: 'Primary',
      m3u: SourceEndpoint(value: m3u),
      epg: SourceEndpoint(value: ''),
    );

    final online = PlaylistLoader(
      fetcher: _FakeFetcher(<String, String>{
        m3u: '''
#EXTM3U
#EXTINF:-1,One
https://example.com/one.m3u8
''',
      }),
      cacheDirectory: directory,
    );
    final fresh = await online.load(source);
    expect(fresh.playlist.channels.single.name, 'One');
    expect(fresh.playlistFromCache, isFalse);

    final offline = PlaylistLoader(
      fetcher: _FakeFetcher(<String, String>{}),
      cacheDirectory: directory,
    );
    final cached = await offline.load(source);
    expect(cached.playlist.channels.single.name, 'One');
    expect(cached.playlistFromCache, isTrue);

    await expectLater(
      offline.probe(source),
      throwsA(isA<SourceLoadException>()),
    );
  });
}
