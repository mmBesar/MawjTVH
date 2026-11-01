import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:mawjtvh/data/models.dart';
import 'package:mawjtvh/data/tvh_client.dart';
import 'package:mawjtvh/data/tvh_loader.dart';

class _Fake implements TvhTransport {
  _Fake(this.routes);

  final Map<String, TvhResponse Function(Uri uri)> routes;

  @override
  Future<TvhResponse> send(
    String method,
    Uri uri, {
    Map<String, String>? form,
    Map<String, String>? headers,
    Duration? timeout,
  }) async {
    final route = routes[uri.path];
    return route == null
        ? const TvhResponse(404, <int>[])
        : route(uri);
  }

  @override
  void close() {}
}

TvhResponse _json(Object body) => TvhResponse(200, utf8.encode(jsonEncode(body)));

void main() {
  const source = SourceConfig(
    id: 's1',
    name: 'Home',
    address: 'tv.lan',
    username: 'admin',
    password: 'pw',
  );

  Map<String, TvhResponse Function(Uri)> routes({
    List<Map<String, dynamic>>? channels,
    bool admin = true,
  }) {
    return <String, TvhResponse Function(Uri)>{
      '/api/serverinfo': (_) => _json(<String, Object>{
            'name': 'tvheadend',
            'sw_version': '4.3-test',
            'api_version': 19,
          }),
      '/api/config/capabilities': (_) => _json(<String>['linuxdvb']),
      '/api/config/load': (_) => admin
          ? _json(<String, Object>{'entries': <Object>[]})
          : const TvhResponse(403, <int>[]),
      '/api/channel/grid': (_) => _json(<String, Object>{
            'entries': channels ??
                <Map<String, dynamic>>[
                  <String, dynamic>{
                    'uuid': 'c1',
                    'name': 'News 24',
                    'number': 1,
                    'enabled': true,
                    'tags': <String>['t1'],
                  },
                  <String, dynamic>{
                    'uuid': 'c2',
                    'name': 'Movies',
                    'number': 2,
                    'enabled': true,
                    'tags': <String>[],
                  },
                ],
          }),
      '/api/channeltag/grid': (_) => _json(<String, Object>{
            'entries': <Object>[
              <String, Object>{'uuid': 't1', 'name': 'News', 'index': 1, 'enabled': true},
            ],
          }),
      '/api/epg/events/grid': (_) => _json(<String, Object>{
            'entries': <Object>[
              <String, Object>{
                'eventId': 1,
                'channelUuid': 'c1',
                'start': 1700000000,
                'stop': 1700003600,
                'title': 'Bulletin',
              },
              <String, Object>{
                'eventId': 2,
                'channelUuid': 'gone',
                'start': 1700000000,
                'stop': 1700003600,
                'title': 'Not ours',
              },
            ],
          }),
      '/api/profile/list': (_) => _json(<String, Object>{
            'entries': <Object>[
              <String, String>{'key': 'p1', 'val': 'pass'},
              <String, String>{'key': 'p2', 'val': 'matroska'},
            ],
          }),
    };
  }

  TvhLoader loader(Map<String, TvhResponse Function(Uri)> table) {
    return TvhLoader(
      clientFactory: (config) => TvhClient(config, transport: _Fake(table)),
    );
  }

  test('loads channels, groups, the guide and the account rights', () async {
    final content = await loader(routes()).load(source);
    expect(content.playlist.channels.map((c) => c.name), <String>['News 24', 'Movies']);
    expect(content.playlist.channels.first.group, 'News');
    expect(content.epg.programmeCount, 1);
    expect(content.permissions.admin, isTrue);
    expect(content.serverInfo.version, '4.3-test');
    expect(content.profiles, <String>['pass', 'matroska']);
    expect(content.resolvedSource.address, 'http://tv.lan:9981');
    expect(content.warnings, isEmpty);
  });

  test('programmes of channels the account cannot see are left out', () async {
    final content = await loader(routes()).load(source);
    final all = content.epg.all.map((p) => p.title).toList();
    expect(all, <String>['Bulletin']);
  });

  test('an account without channels is told what to do', () async {
    final table = routes(channels: <Map<String, dynamic>>[], admin: false);
    await expectLater(
      loader(table).load(source),
      throwsA(
        isA<SourceLoadException>().having(
          (e) => e.message,
          'message',
          contains('cannot see any channel'),
        ),
      ),
    );
  });

  test('a guide failure is a warning, not an error', () async {
    final table = routes();
    table['/api/epg/events/grid'] = (_) => const TvhResponse(500, <int>[]);
    final content = await loader(table).load(source);
    expect(content.warnings, contains(LoadWarning.epgUnavailable));
    expect(content.playlist.channels, isNotEmpty);
  });

  test('a bad address is reported as a load error', () async {
    await expectLater(
      loader(routes()).load(source.copyWith(address: 'ftp://nope')),
      throwsA(isA<SourceLoadException>()),
    );
  });
}
