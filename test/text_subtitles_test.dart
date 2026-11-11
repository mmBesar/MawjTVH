import 'package:flutter_test/flutter_test.dart';
import 'package:mawjtvh/data/text_subtitles.dart';

void main() {
  test('plain text is one span without a colour', () {
    final spans = parseSubtitleSpans('Hello\nthere\n\u0000');
    expect(spans, hasLength(1));
    expect(spans.first.text, 'Hello\nthere');
    expect(spans.first.color, isNull);
  });

  test('font tags give coloured runs', () {
    final spans = parseSubtitleSpans(
      'one <font color="#ffff00">two</font> three\n',
    );
    expect(spans.map((s) => s.text), <String>['one ', 'two', ' three']);
    expect(spans.map((s) => s.color), <int?>[null, 0xFFFFFF00, null]);
  });

  test('other tags are dropped and blank text gives nothing', () {
    expect(parseSubtitleSpans('<i>x</i>').single.text, 'x');
    expect(parseSubtitleSpans('\u0000'), isEmpty);
    expect(parseSubtitleSpans('  \n'), isEmpty);
  });
}
