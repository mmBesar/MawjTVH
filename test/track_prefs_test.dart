import 'package:flutter_test/flutter_test.dart';
import 'package:mawjtvh/data/track_prefs.dart';

void main() {
  const tracks = <({String? language, String? title})>[
    (language: 'eng', title: 'Stereo'),
    (language: 'ara', title: 'Commentary'),
    (language: 'ara', title: ''),
  ];

  test('languages compare across spellings', () {
    expect(canonicalLanguage('fre'), canonicalLanguage('fra'));
    expect(canonicalLanguage('AR'), 'ara');
  });

  test('preferred language picks the first match', () {
    expect(pickTrack(tracks, preferred: 'ar'), 1);
    expect(pickTrack(tracks, preferred: 'deu'), isNull);
    expect(pickTrack(tracks), isNull);
  });

  test('remembered track wins and falls back to its language', () {
    expect(
      pickTrack(tracks, remembered: trackKey('ara', ''), preferred: 'eng'),
      2,
    );
    expect(
      pickTrack(tracks, remembered: trackKey('ara', 'Other'), preferred: 'eng'),
      1,
    );
    expect(pickTrack(tracks, remembered: trackKey('deu', ''), preferred: 'eng'), 0);
  });
}
