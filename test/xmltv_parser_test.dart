import 'package:flutter_test/flutter_test.dart';
import 'package:mawjtvh/data/models.dart';
import 'package:mawjtvh/data/xmltv_parser.dart';

void main() {
  const parser = XmltvParser();
  const channels = <Channel>[
    Channel(
      id: 'internal-one',
      sourceId: 'source',
      name: 'Arabic One',
      number: '1',
      url: 'https://example.com/one',
      tvgId: 'C1.tunarr.com',
      channelId: 'C1.tunarr.com',
    ),
    Channel(
      id: 'internal-two',
      sourceId: 'source',
      name: 'News Two',
      number: '2',
      url: 'https://example.com/two',
    ),
  ];

  test('parses programmes, sub-titles and matches tvg-id', () {
    const xml = '''
<?xml version="1.0" encoding="UTF-8"?>
<tv>
  <channel id="C1.tunarr.com">
    <display-name>Arabic One</display-name>
  </channel>
  <programme start="20261028142553 +0000" stop="20261028154453 +0000" channel="C1.tunarr.com">
    <title>وجهة نظر</title>
    <sub-title>حلقة 1</sub-title>
    <desc>وصف الحلقة</desc>
    <category>دراما</category>
    <category>كوميديا</category>
    <icon src="https://example.com/poster.jpg"/>
    <episode-num system="xmltv_ns">0.1.</episode-num>
  </programme>
  <programme start="20270101120000 +0000" stop="20270101130000 +0000" channel="C1.tunarr.com">
    <title>Outside the window</title>
  </programme>
</tv>
''';

    final result = parser.parse(
      xml,
      channels,
      now: DateTime.utc(2026, 10, 28, 14, 30),
    );
    final epg = result.epg;

    expect(result.matchedChannels, 1);
    expect(epg.programmeCount, 1);

    final programme = epg.programmesFor(channels.first).single;
    expect(programme.title, 'وجهة نظر');
    expect(programme.subTitle, 'حلقة 1');
    expect(programme.description, 'وصف الحلقة');
    expect(programme.categories, <String>['دراما', 'كوميديا']);
    expect(programme.iconUrl, 'https://example.com/poster.jpg');
    expect(programme.episode, 'S01E02');
    expect(programme.start.toUtc(), DateTime.utc(2026, 10, 28, 14, 25, 53));
    expect(programme.stop.toUtc(), DateTime.utc(2026, 10, 28, 15, 44, 53));
    expect(epg.nowFor(channels.first, DateTime.utc(2026, 10, 28, 14, 30)), isNotNull);
  });

  test('matches by display name when the playlist has no tvg-id', () {
    const xml = '''
<tv>
  <channel id="some.random.id">
    <display-name>News Two</display-name>
  </channel>
  <programme start="20261028140000 +0000" stop="20261028150000 +0000" channel="some.random.id">
    <title>Midday News</title>
  </programme>
</tv>
''';

    final result = parser.parse(
      xml,
      channels,
      now: DateTime.utc(2026, 10, 28, 14, 30),
    );

    expect(result.epg.programmesFor(channels[1]).single.title, 'Midday News');
    expect(result.unmatchedChannels, 0);
  });

  test('reports channels that cannot be matched', () {
    const xml = '''
<tv>
  <channel id="unknown"><display-name>Unknown</display-name></channel>
</tv>
''';

    final result = parser.parse(
      xml,
      channels,
      now: DateTime.utc(2026, 10, 28, 14, 30),
    );

    expect(result.epg.isEmpty, isTrue);
    expect(result.unmatchedChannels, 1);
  });

  test('does not match programmes with an empty channel attribute', () {
    const xml = '''
<tv>
  <programme start="20261028140000 +0000" stop="20261028150000 +0000">
    <title>No channel</title>
  </programme>
</tv>
''';

    final result = parser.parse(
      xml,
      channels,
      now: DateTime.utc(2026, 10, 28, 14, 30),
    );

    expect(result.epg.isEmpty, isTrue);
    expect(result.matchedChannels, 0);
  });

  test('falls back to the sub-title when a programme has no title', () {
    const xml = '''
<tv>
  <programme start="20261028140000 +0000" stop="20261028150000 +0000"
             channel="C1.tunarr.com">
    <sub-title>Placeholder block</sub-title>
  </programme>
</tv>
''';

    final result = parser.parse(
      xml,
      channels,
      now: DateTime.utc(2026, 10, 28, 14, 30),
    );

    expect(result.epg.programmesFor(channels[0]).single.title,
        'Placeholder block');
  });

  test('reports why a channel has no guide', () {
    const xml = '''
<tv>
  <programme start="20261028140000 +0000" stop="20261028150000 +0000"
             channel="C1.tunarr.com">
    <title>Kept</title>
  </programme>
  <programme start="20261028140000 +0000" stop="20261028150000 +0000"
             channel="unknown.id">
    <title>Orphan</title>
  </programme>
</tv>
''';

    final result = parser.parse(
      xml,
      channels,
      now: DateTime.utc(2026, 10, 28, 14, 30),
    );

    expect(result.report, contains('News Two'));
    expect(result.report, contains('unknown.id'));
    expect(result.report, isNot(contains('Arabic One')));
  });

  test('parses timezone offsets and rejects malformed timestamps', () {
    expect(
      parseXmltvTime('20261028170000 +0300')!.toUtc(),
      DateTime.utc(2026, 10, 28, 14),
    );
    expect(
      parseXmltvTime('20261028170000 -0430')!.toUtc(),
      DateTime.utc(2026, 10, 28, 21, 30),
    );
    expect(parseXmltvTime('2026-10-28 17:00'), isNull);
    expect(parseXmltvTime(null), isNull);
  });
}
