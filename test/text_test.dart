import 'package:flutter_test/flutter_test.dart';
import 'package:mawjtvh/core/text.dart';

void main() {
  test('Arabic spelling variants and diacritics are merged for search', () {
    expect(normalizeForSearch('أخبار'), normalizeForSearch('اخبار'));
    expect(normalizeForSearch('قناة'), normalizeForSearch('قناه'));
    expect(normalizeForSearch('مُسَلْسَل'), normalizeForSearch('مسلسل'));
    expect(normalizeForSearch('NEWS'), 'news');
  });
}
