import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:mawjtvh/data/models.dart';
import 'package:mawjtvh/data/tvh_address.dart';
import 'package:mawjtvh/data/tvh_client.dart';
import 'package:mawjtvh/data/tvh_models.dart';

typedef Route = TvhResponse Function(String method, Uri uri);

TvhResponse jsonOk(Object body, {int status = 200}) =>
    TvhResponse(status, utf8.encode(jsonEncode(body)));

TvhResponse plain(int status, {String? location}) =>
    TvhResponse(status, const <int>[], location: location);

class FakeTransport implements TvhTransport {
  FakeTransport(this.routes);

  final Map<String, Route> routes;
  final List<String> log = <String>[];
  final List<Map<String, String>> sentHeaders = <Map<String, String>>[];
  final List<Map<String, String>?> sentForms = <Map<String, String>?>[];

  @override
  Future<TvhResponse> send(
    String method,
    Uri uri, {
    Map<String, String>? form,
    Map<String, String>? headers,
    Duration? timeout,
  }) async {
    log.add('$method ${uri.path}');
    sentHeaders.add(headers ?? const <String, String>{});
    sentForms.add(form);
    final route = routes[uri.path];
    if (route == null) {
      return plain(404);
    }
    return route(method, uri);
  }

  @override
  void close() {}
}

const SourceConfig kSource = SourceConfig(
  id: 's1',
  name: 'Home',
  address: 'tv.lan',
  username: 'bob',
  password: 'pw',
);

TvhClient clientWith(Map<String, Route> routes, {SourceConfig source = kSource}) =>
    TvhClient(source, transport: FakeTransport(routes));

void main() {
  group('permissions', () {
    test('an account without admin rights is a normal user', () async {
      final client = clientWith(<String, Route>{
        '/api/config/capabilities': (_, _) => jsonOk(<String>['linuxdvb']),
        '/api/config/load': (_, _) => plain(403),
      });
      final permissions = await client.probe();
      expect(permissions.admin, isFalse);
    });

    test('an admin account is detected', () async {
      final client = clientWith(<String, Route>{
        '/api/config/capabilities': (_, _) => jsonOk(<String>[]),
        '/api/config/load': (_, _) => jsonOk(<String, Object>{'entries': <Object>[]}),
      });
      expect((await client.probe()).admin, isTrue);
    });

    test('wrong credentials and wrong servers get clear messages', () async {
      final bad = clientWith(<String, Route>{
        '/api/config/capabilities': (_, _) => plain(401),
      });
      await expectLater(
        bad.probe(),
        throwsA(
          isA<TvhException>().having((e) => e.statusCode, 'status', 401),
        ),
      );
      final notTvh = clientWith(const <String, Route>{});
      await expectLater(
        notTvh.probe(),
        throwsA(
          isA<TvhException>().having(
            (e) => e.message,
            'message',
            contains('does not look like a Tvheadend server'),
          ),
        ),
      );
    });

    test('the login travels as a Basic header', () async {
      final transport = FakeTransport(<String, Route>{
        '/api/config/capabilities': (_, _) => jsonOk(<String>[]),
        '/api/config/load': (_, _) => plain(403),
      });
      await TvhClient(kSource, transport: transport).probe();
      final expected = 'Basic ${base64Encode(utf8.encode('bob:pw'))}';
      expect(transport.sentHeaders.first['authorization'], expected);
    });
  });

  group('redirects', () {
    test('a move to https on the same host is followed', () {
      final a = TvhAddress.parse('http://tv.example.com');
      final up = TvhClient.upgradedAddress(
        a,
        'https://tv.example.com/api/serverinfo',
        '/api/serverinfo',
      )!;
      expect(up.tls, isTrue);
      expect(up.port, 443);
      expect(up.webroot, '');
      final moved = TvhClient.upgradedAddress(
        a,
        'https://tv.example.com:8443/tvh/api/serverinfo',
        '/api/serverinfo',
      )!;
      expect(moved.port, 8443);
      expect(moved.webroot, '/tvh');
    });

    test('a redirect to another host or page is ignored', () {
      final a = TvhAddress.parse('http://tv.example.com');
      expect(
        TvhClient.upgradedAddress(a, 'https://evil.example.net/api/serverinfo', '/api/serverinfo'),
        isNull,
      );
      expect(
        TvhClient.upgradedAddress(a, 'https://tv.example.com/login', '/api/serverinfo'),
        isNull,
      );
      expect(TvhClient.upgradedAddress(a, null, '/api/serverinfo'), isNull);
    });

    test('followUpgrade switches the client to the address the server asks for', () async {
      final client = clientWith(<String, Route>{
        '/api/serverinfo': (_, _) =>
            plain(301, location: 'https://tv.lan/api/serverinfo'),
      });
      await client.followUpgrade();
      expect(client.address.baseUrl, 'https://tv.lan');
    });
  });

  group('channels', () {
    final tags = <Map<String, dynamic>>[
      <String, dynamic>{'uuid': 't-news', 'name': 'News', 'index': 1, 'enabled': true},
      <String, dynamic>{'uuid': 't-movies', 'name': 'Movies', 'index': 2, 'enabled': true},
    ];
    final channels = <Map<String, dynamic>>[
      <String, dynamic>{
        'uuid': 'c2',
        'name': 'B Movie',
        'number': 2,
        'enabled': true,
        'tags': <String>['t-movies'],
        'icon_public_url': 'imagecache/7',
      },
      <String, dynamic>{
        'uuid': 'c1',
        'name': 'News 24',
        'number': 1,
        'tags': <String>['t-movies', 't-news'],
      },
      <String, dynamic>{'uuid': 'c0', 'name': 'Disabled', 'number': 3, 'enabled': false},
      <String, dynamic>{'uuid': 'c9', 'name': 'No number', 'number': 0},
    ];

    test('are sorted by number, grouped by their first tag, and enabled only', () {
      final client = clientWith(const <String, Route>{});
      final result = channelsFromJson(
        sourceId: 's1',
        channels: channels,
        tags: tags,
        client: client,
      );
      expect(result.map((c) => c.id), <String>['c1', 'c2', 'c9']);
      expect(result.first.group, 'News');
      expect(result.first.tags, <String>['News', 'Movies']);
      expect(result.first.url, 'http://bob:pw@tv.lan:9981/stream/channel/c1');
      expect(result[1].logoUrl, 'http://bob:pw@tv.lan:9981/imagecache/7');
      expect(result.last.number, '');
    });

    test('a chosen stream profile ends up in the stream URL', () {
      final client = clientWith(
        const <String, Route>{},
        source: kSource.copyWith(profile: 'matroska'),
      );
      expect(
        client.streamUrl('c1'),
        'http://bob:pw@tv.lan:9981/stream/channel/c1?profile=matroska',
      );
    });
  });

  group('guide', () {
    test('an event becomes a programme with everything the server knows', () {
      final programme = programmeFromEvent(
        <String, dynamic>{
          'eventId': 5,
          'channelUuid': 'c1',
          'start': 1700000000,
          'stop': 1700003600,
          'title': 'News',
          'subtitle': 'Evening',
          'description': 'Long text',
          'summary': 'Short text',
          'category': <String>['News', ' '],
          'image': 'imagecache/9',
          'seasonNumber': 2,
          'episodeNumber': 5,
          'copyright_year': 2019,
          'ageRating': 12,
          'dvrUuid': 'd1',
          'dvrState': 'scheduled',
        },
        imageResolver: (source) => 'http://x/$source',
      )!;
      expect(programme.channelId, 'c1');
      expect(programme.title, 'News');
      expect(programme.subTitle, 'Evening');
      expect(programme.description, 'Long text');
      expect(programme.categories, <String>['News']);
      expect(programme.iconUrl, 'http://x/imagecache/9');
      expect(programme.episode, 'S02E05');
      expect(programme.facts, '2019 · News · 12+');
      expect(programme.eventId, 5);
      expect(programme.hasRecording, isTrue);
      expect(programme.dvrState, 'scheduled');
      expect(
        programme.stop.difference(programme.start),
        const Duration(hours: 1),
      );
    });

    test('a short summary stands in for a missing description', () {
      final programme = programmeFromEvent(<String, dynamic>{
        'channelUuid': 'c1',
        'start': 10,
        'stop': 20,
        'title': 'Film',
        'summary': 'Only a summary',
      })!;
      expect(programme.description, 'Only a summary');
      expect(programme.subTitle, isNull);
      expect(programme.hasRecording, isFalse);
    });

    test('events without a channel or a time span are dropped', () {
      expect(programmeFromEvent(<String, dynamic>{'start': 1, 'stop': 2}), isNull);
      expect(
        programmeFromEvent(<String, dynamic>{'channelUuid': 'c', 'start': 5, 'stop': 5}),
        isNull,
      );
    });

    test('episode, facts and credits lines', () {
      expect(episodeLabel('', 2, 5), 'S02E05');
      expect(episodeLabel('Ep. 7', 1, 1), 'Ep. 7');
      expect(episodeLabel('', null, 4), 'E4');
      expect(episodeLabel('', null, null), '');
      expect(
        factsLine(2019, <String>['Drama', 'Crime'], 75, 12),
        '2019 · Drama, Crime · ★ 7.5 · 12+',
      );
      expect(
        creditsLine(<String, dynamic>{
          'Jane Roe': 'director',
          'A B': 'actor',
          'C D': 'actor',
        }),
        'Director: Jane Roe  ·  Cast: A B, C D',
      );
      expect(creditsLine(null), '');
    });

    Map<String, Route> eventRoutes(List<Map<String, dynamic>> all) {
      return <String, Route>{
        '/api/epg/events/grid': (_, uri) {
          final start = int.parse(uri.queryParameters['start']!);
          final limit = int.parse(uri.queryParameters['limit']!);
          final end = (start + limit).clamp(0, all.length).toInt();
          return jsonOk(<String, Object>{
            'entries': all.sublist(start.clamp(0, all.length).toInt(), end),
            'total': all.length,
          });
        },
      };
    }

    List<Map<String, dynamic>> events(int count) => <Map<String, dynamic>>[
          for (var i = 0; i < count; i++)
            <String, dynamic>{
              'channelUuid': 'c1',
              'start': 1700000000 + i * 100,
              'stop': 1700000000 + i * 100 + 90,
              'title': 'E$i',
            },
        ];

    test('pages are read until the server has no more', () async {
      final transport = FakeTransport(eventRoutes(events(5)));
      final client = TvhClient(kSource, transport: transport);
      final rows = await client.rawEvents(
        until: DateTime.fromMillisecondsSinceEpoch(2000000000 * 1000),
        pageSize: 2,
      );
      expect(rows, hasLength(5));
      expect(transport.log.where((l) => l.contains('events/grid')), hasLength(3));
    });

    test('reading stops once a page reaches past the guide window', () async {
      final transport = FakeTransport(eventRoutes(events(10)));
      final client = TvhClient(kSource, transport: transport);
      final rows = await client.rawEvents(
        until: DateTime.fromMillisecondsSinceEpoch(1700000050 * 1000),
        pageSize: 2,
      );
      expect(rows, hasLength(2));
      expect(transport.log.where((l) => l.contains('events/grid')), hasLength(1));
    });

    test('events are grouped by channel and sorted', () {
      final client = clientWith(const <String, Route>{});
      final grouped = client.groupEvents(<Map<String, dynamic>>[
        <String, dynamic>{'channelUuid': 'a', 'start': 200, 'stop': 300, 'title': 'Second'},
        <String, dynamic>{'channelUuid': 'a', 'start': 100, 'stop': 200, 'title': 'First'},
        <String, dynamic>{'channelUuid': 'b', 'start': 100, 'stop': 200, 'title': 'Other'},
      ]);
      expect(grouped.keys, containsAll(<String>['a', 'b']));
      expect(grouped['a']!.map((p) => p.title), <String>['First', 'Second']);
    });
  });

  group('recordings', () {
    test('a DVR entry keeps its state and size', () {
      final recording = recordingFromJson(<String, dynamic>{
        'uuid': 'r1',
        'channel': 'c1',
        'channelname': 'News 24',
        'disp_title': 'Evening news',
        'start': 1700000000,
        'stop': 1700003600,
        'status': 'Running',
        'sched_status': 'recording',
        'filesize': 1048576,
        'errors': 0,
        'enabled': true,
      });
      expect(recording.isRecording, isTrue);
      expect(recording.isScheduled, isFalse);
      expect(recording.hasFile, isTrue);
      expect(recording.length, const Duration(hours: 1));
    });

    test('the default recording profile is the one with an empty name', () async {
      final client = clientWith(<String, Route>{
        '/api/dvr/config/grid': (_, _) => jsonOk(<String, Object>{
              'entries': <Object>[
                <String, String>{'uuid': 'other', 'name': 'Other'},
                <String, String>{'uuid': 'cfg-default', 'name': ''},
              ],
            }),
      });
      expect(await client.defaultDvrConfig(), 'cfg-default');
    });

    test('recording an event posts the profile and event id', () async {
      final transport = FakeTransport(<String, Route>{
        '/api/dvr/config/grid': (_, _) => jsonOk(<String, Object>{
              'entries': <Object>[
                <String, String>{'uuid': 'cfg-default', 'name': ''},
              ],
            }),
        '/api/dvr/entry/create_by_event': (_, _) => jsonOk(<String, Object>{}),
      });
      await TvhClient(kSource, transport: transport).recordEvent(42);
      expect(transport.log.last, 'POST /api/dvr/entry/create_by_event');
      expect(transport.sentForms.last, <String, String>{
        'config_uuid': 'cfg-default',
        'event_id': '42',
      });
    });

    test('a refusal is explained as an account right', () async {
      final client = clientWith(<String, Route>{
        '/api/dvr/entry/grid_upcoming': (_, _) => plain(403),
      });
      await expectLater(
        client.recordings(RecordingKind.upcoming),
        throwsA(
          isA<TvhException>()
              .having((e) => e.isForbidden, 'forbidden', isTrue)
              .having((e) => e.message, 'message', contains('not allowed')),
        ),
      );
    });
  });

  group('signal', () {
    test('relative and absolute scales are converted', () {
      const relative = TvhInputStatus(
        input: 'Tuner 1',
        stream: 'mux',
        subs: 1,
        signal: 32768,
        signalScale: 1,
        snr: 18500,
        snrScale: 2,
        unc: 0,
      );
      final signal = TvhSignal.fromInput(relative);
      expect(signal.signalPercent, closeTo(50, 0.1));
      expect(signal.snrPercent, isNull);
      expect(signal.snrDb, closeTo(18.5, 0.001));
      expect(signal.hasValues, isTrue);

      const none = TvhInputStatus(input: 'x', signalScale: 0, snrScale: 0, signal: 5);
      expect(TvhSignal.fromInput(none).hasValues, isFalse);
    });

    test('the tuner that serves the stream is picked', () {
      const idle = TvhInputStatus(input: 'A', subs: 0);
      const a = TvhInputStatus(input: 'Tuner A', subs: 1);
      const b = TvhInputStatus(input: 'Tuner B', subs: 2);
      const sub = TvhSubscription(
        title: 't',
        channel: 'News 24',
        service: 'Tuner B/DVB-S/11000/News 24',
        state: 'Running',
      );
      expect(TvhSignal.pickInput(<TvhInputStatus>[idle], sub), isNull);
      expect(TvhSignal.pickInput(<TvhInputStatus>[idle, a], sub), a);
      expect(TvhSignal.pickInput(<TvhInputStatus>[a, b], sub), b);
    });

    test('signalFor joins the tuner and the subscription', () async {
      final client = clientWith(<String, Route>{
        '/api/status/inputs': (_, _) => jsonOk(<String, Object>{
              'entries': <Object>[
                <String, Object>{
                  'input': 'Tuner A',
                  'stream': 'mux 1',
                  'subs': 1,
                  'signal': 65535,
                  'signal_scale': 1,
                  'snr': 65535,
                  'snr_scale': 1,
                },
              ],
            }),
        '/api/status/subscriptions': (_, _) => jsonOk(<String, Object>{
              'entries': <Object>[
                <String, Object>{
                  'channel': 'News 24',
                  'service': 'Tuner A/mux 1/News 24',
                  'state': 'Running',
                },
              ],
            }),
      });
      final signal = await client.signalFor('News 24');
      expect(signal, isNotNull);
      expect(signal!.snrPercent, closeTo(100, 0.01));
    });

    test('a normal user simply gets no signal numbers', () async {
      final client = clientWith(<String, Route>{
        '/api/status/inputs': (_, _) => plain(403),
      });
      expect(await client.signalFor('News 24'), isNull);
    });
  });
}
