import 'package:flutter_test/flutter_test.dart';
import 'package:mawjtvh/l10n/languages.dart';

void main() {
  test('codes that are not languages get readable names', () {
    expect(trackLanguageName('org', arabic: false), 'Original');
    expect(trackLanguageName('qaa', arabic: false), 'Original');
    expect(trackLanguageName('und', arabic: false), 'Unnamed');
    expect(trackLanguageName('mul', arabic: false), 'Multiple languages');
    expect(trackLanguageName('pol', arabic: false), 'Polish');
    expect(trackLanguageName('', arabic: false), '');
    expect(trackLanguageName(null, arabic: true), '');
  });
}
