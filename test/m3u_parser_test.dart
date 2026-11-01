import 'package:flutter_test/flutter_test.dart';
import 'package:mawjtvh/data/m3u_parser.dart';

void main() {
  const parser = M3uParser();

  test('parses channel attributes and resolves relative locations', () {
    const content = '''
#EXTM3U url-tvg="https://example.com/guide.xml" x-tvg-url="https://example.com/alt.xml"
#EXTINF:-1 tvg-id="one" tvg-chno="7" tvg-name="One" tvg-logo="logos/one.png" group-title="News, Live",One HD
streams/one.m3u8
#EXTGRP:Arabic
#EXTINF:-1,Two, The Sequel
https://example.com/two.m3u8
''';

    final result = parser.parse(
      content,
      sourceId: 'src',
      baseUri: Uri.parse('https://example.com/lists/main.m3u'),
    );

    expect(result.xmltvUrl, 'https://example.com/guide.xml');
    expect(result.channels, hasLength(2));

    final first = result.channels.first;
    expect(first.id, 'src|one');
    expect(first.name, 'One HD');
    expect(first.number, '7');
    expect(first.tvgId, 'one');
    expect(first.url, 'https://example.com/lists/streams/one.m3u8');
    expect(first.logoUrl, 'https://example.com/lists/logos/one.png');
    expect(first.group, 'News, Live');

    final second = result.channels[1];
    expect(second.name, 'The Sequel');
    expect(second.group, 'Arabic');
    expect(second.url, 'https://example.com/two.m3u8');
    expect(second.number, '2');
    expect(second.id, 'src|The Sequel');
  });

  test('keeps ids stable and unique, and reads ErsatzTV channel-number', () {
    const content = '''
#EXTM3U
#EXTINF:0 channel-id="1" channel-number="1.1" tvg-id="1.etv" tvg-name="A",A
http://example.com/a.m3u8
#EXTINF:0 channel-id="1" channel-number="2" tvg-id="1.etv" tvg-name="B",B
http://example.com/b.m3u8
''';

    final result = parser.parse(content, sourceId: 's');

    expect(result.channels.map((c) => c.id), <String>['s|1.etv', 's|1.etv#2']);
    expect(result.channels.first.number, '1.1');
  });

  test('falls back to the tvg-name and skips entries without a URL', () {
    const content = '''
#EXTM3U
#EXTINF:-1 tvg-name="Fallback Name","
#EXTINF:-1 tvg-id="skip",Skipped
#EXTINF:-1 tvg-name="News",News Channel
http://example.com/news
''';

    final result = parser.parse(content, sourceId: 's');

    expect(result.channels, hasLength(1));
    expect(result.channels.single.name, 'News Channel');
    expect(result.channels.single.number, '1');
  });

  test('lets group-title win over a leading #EXTGRP', () {
    const content = '''
#EXTM3U
#EXTGRP:Arabic
#EXTINF:-1 group-title="News",News One
https://example.com/news.m3u8
#EXTGRP:Kids
#EXTINF:-1,Cartoons
https://example.com/cartoons.m3u8
#EXTGRP:Docs
#EXTINF:-1,Documentaries
https://example.com/docs.m3u8
#EXTGRP:Music
#EXTINF:-1,Clips
https://example.com/clips.m3u8
''';

    final result = parser.parse(content, sourceId: 's');

    expect(result.channels, hasLength(4));
    expect(result.channels[0].group, 'News');
    expect(result.channels[1].group, 'Kids');
    expect(result.channels[2].group, 'Docs');
    expect(result.channels[3].group, 'Music');
  });

  test('applies #EXTGRP placed between #EXTINF and the URL', () {
    const content = '''
#EXTM3U
#EXTINF:-1,Sports
#EXTGRP:Sport
https://example.com/sport.m3u8
#EXTINF:-1 group-title="News",News
#EXTGRP:Ignored
https://example.com/news.m3u8
#EXTINF:-1,Next
https://example.com/next.m3u8
''';

    final result = parser.parse(content, sourceId: 's');

    expect(result.channels, hasLength(3));
    expect(result.channels[0].group, 'Sport');
    expect(result.channels[1].group, 'News');
    expect(result.channels[2].group, isNull);
  });

  test('keeps absolute URLs and quoted commas in the display name', () {
    const content = '''
#EXTM3U
#EXTINF:-1 tvg-logo="https://cdn.example.com/logo.png" group-title="Movies",Movies, Action
http://example.com/action
''';

    final result = parser.parse(
      content,
      sourceId: 's',
      baseUri: Uri.parse('http://example.com/list.m3u'),
    );

    expect(result.channels.single.name, 'Action');
    expect(result.channels.single.group, 'Movies');
    expect(result.channels.single.logoUrl, 'https://cdn.example.com/logo.png');
  });
}
