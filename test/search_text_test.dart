import 'package:flutter_test/flutter_test.dart';
import 'package:mawjtvh/core/text.dart';

bool exact(String haystack, String query) =>
    matchesAllTokens(foldForSearch(haystack), searchTokens(query));

bool similar(String haystack, String query) =>
    matchesSimilar(foldForSearch(haystack), searchTokens(query));

void main() {
  test('punctuation does not matter', () {
    expect(exact('Man. United v Chelsea', 'man united'), isTrue);
    expect(exact('Man United', 'Man. United'), isTrue);
    expect(exact("Mark's Kitchen", 'marks kitchen'), isTrue);
  });

  test('word order and case do not matter', () {
    expect(exact('Manchester United v Arsenal', 'ARSENAL united'), isTrue);
  });

  test('accents are dropped', () {
    expect(exact('Café Society', 'cafe'), isTrue);
  });

  test('combining marks are ignored', () {
    // "Cafe" followed by a combining acute accent.
    expect(exact('Cafe\u0301 Society', 'cafe society'), isTrue);
  });

  test('Arabic variants still merge', () {
    expect(exact('أخبار الصباح', 'اخبار'), isTrue);
  });

  test('every word has to be there', () {
    expect(exact('Man. United', 'man city'), isFalse);
  });

  test('small typos are forgiven only by the similar match', () {
    expect(exact('Manchester United', 'manchster'), isFalse);
    expect(similar('Manchester United', 'manchster'), isTrue);
    expect(similar('Manchester United', 'unitd'), isTrue);
    // Short words must be exact.
    expect(similar('The Cat', 'cot'), isFalse);
  });

  test('unrelated words do not match', () {
    expect(similar('Manchester United', 'liverpool'), isFalse);
  });
}
