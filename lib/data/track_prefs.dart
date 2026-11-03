/// Choosing audio and subtitle tracks from what the user prefers and from
/// what they picked last time on the same channel.
library;

const Map<String, String> _canonical = <String, String>{
  'ar': 'ara',
  'en': 'eng',
  'fr': 'fra',
  'fre': 'fra',
  'de': 'deu',
  'ger': 'deu',
  'es': 'spa',
  'it': 'ita',
  'pt': 'por',
  'ru': 'rus',
  'tr': 'tur',
  'fa': 'fas',
  'per': 'fas',
  'nl': 'nld',
  'dut': 'nld',
  'el': 'ell',
  'gre': 'ell',
  'zh': 'zho',
  'chi': 'zho',
  'cs': 'ces',
  'cze': 'ces',
  'ro': 'ron',
  'rum': 'ron',
  'hi': 'hin',
  'ur': 'urd',
  'ku': 'kur',
  'he': 'heb',
  'ja': 'jpn',
  'ko': 'kor',
};

/// One three-letter spelling for every way a language code is written.
String canonicalLanguage(String? code) {
  final raw = (code ?? '').trim().toLowerCase();
  return _canonical[raw] ?? raw;
}

/// The text kept for a track so the same one can be found again later.
String trackKey(String? language, String? title) =>
    '${canonicalLanguage(language)}|${(title ?? '').trim().toLowerCase()}';

/// Index of the track to use, or null to leave the player's own choice.
///
/// A [remembered] key wins (same language and title, else same language);
/// otherwise the first track in the [preferred] language.
int? pickTrack(
  List<({String? language, String? title})> tracks, {
  String? remembered,
  String preferred = '',
}) {
  if (remembered != null && remembered.contains('|')) {
    final split = remembered.indexOf('|');
    final language = remembered.substring(0, split);
    final title = remembered.substring(split + 1);
    for (var i = 0; i < tracks.length; i++) {
      if (trackKey(tracks[i].language, tracks[i].title) == remembered) {
        return i;
      }
    }
    for (var i = 0; i < tracks.length; i++) {
      if (language.isNotEmpty &&
          canonicalLanguage(tracks[i].language) == language) {
        return i;
      }
    }
    if (title.isEmpty && language.isEmpty) {
      return null;
    }
  }
  final wanted = canonicalLanguage(preferred);
  if (wanted.isEmpty || wanted == 'off' || wanted == 'auto') {
    return null;
  }
  for (var i = 0; i < tracks.length; i++) {
    if (canonicalLanguage(tracks[i].language) == wanted) {
      return i;
    }
  }
  return null;
}
