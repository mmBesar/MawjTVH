import 'package:flutter_test/flutter_test.dart';
import 'package:mawjtvh/data/local_recorder.dart';

void main() {
  test('the programme title joins the file name', () {
    final name = LocalRecordings.fileName(
      'News',
      DateTime(2026, 11, 1, 14, 5, 30),
      title: 'Evening: Report?',
    );
    expect(name, 'News - Evening Report - 2026-11-01 14.05.30.ts');
  });

  test('file names are safe and carry the time', () {
    final name = LocalRecordings.fileName(
      'News: 24/7?',
      DateTime(2026, 11, 1, 14, 5, 30),
    );
    expect(name, 'News 24 7 - 2026-11-01 14.05.30.ts');
  });

  test('an empty channel name still gives a usable name', () {
    expect(
      LocalRecordings.fileName('  ', DateTime(2026, 1, 2, 3, 4, 5)),
      'Recording - 2026-01-02 03.04.05.ts',
    );
  });

  test('Arabic names are kept', () {
    expect(
      LocalRecordings.fileName('قناة الأخبار', DateTime(2026, 1, 2, 3, 4, 5)),
      'قناة الأخبار - 2026-01-02 03.04.05.ts',
    );
  });
}
