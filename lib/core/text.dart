/// Search-friendly form of [value]: lower case, without Arabic diacritics or
/// tatweel, with the common alef, yaa and taa-marbuta variants merged so that
/// "أخبار" finds "اخبار" and "قناة" finds "قناه".
String normalizeForSearch(String value) {
  final buffer = StringBuffer();
  for (final rune in value.toLowerCase().runes) {
    if ((rune >= 0x064B && rune <= 0x065F) || rune == 0x0640 || rune == 0x0670) {
      continue;
    }
    switch (rune) {
      case 0x0623: // أ
      case 0x0625: // إ
      case 0x0622: // آ
        buffer.writeCharCode(0x0627); // ا
      case 0x0649: // ى
        buffer.writeCharCode(0x064A); // ي
      case 0x0629: // ة
        buffer.writeCharCode(0x0647); // ه
      default:
        buffer.writeCharCode(rune);
    }
  }
  return buffer.toString().trim();
}

const Map<String, String> _accentGroups = <String, String>{
  'a': 'àáâãäåāăą',
  'c': 'çćč',
  'd': 'ď',
  'e': 'éèêëēėęě',
  'g': 'ğ',
  'i': 'ìíîïīįı',
  'l': 'ł',
  'n': 'ñńň',
  'o': 'òóôõöøōő',
  'r': 'ř',
  's': 'śşš',
  't': 'ť',
  'u': 'ùúûüūůűų',
  'y': 'ýÿ',
  'z': 'žźż',
};

final Map<String, String> _accentMap = <String, String>{
  for (final group in _accentGroups.entries)
    for (final char in group.value.split('')) char: group.key,
};

/// [normalizeForSearch] taken further for matching names the way people type
/// them: punctuation counts as a space ("Man. United" becomes "man united"),
/// apostrophes vanish ("Mark's" becomes "marks"), and Latin accents are
/// dropped ("Café" becomes "cafe").
String foldForSearch(String value) {
  final normalized = normalizeForSearch(value)
      .replaceAll(RegExp("['’ʼ`]"), '');
  final buffer = StringBuffer();
  for (final char in normalized.split('')) {
    buffer.write(_accentMap[char] ?? char);
  }
  return buffer
      .toString()
      // Combining marks (decomposed accents, Arabic vowel signs) vanish.
      .replaceAll(RegExp(r'\p{M}+', unicode: true), '')
      .replaceAll(RegExp(r'[^\p{L}\p{N}]+', unicode: true), ' ')
      .trim();
}

/// The words of a search, folded; the order they were typed in is ignored.
List<String> searchTokens(String query) {
  final folded = foldForSearch(query);
  if (folded.isEmpty) {
    return const <String>[];
  }
  return folded.split(' ');
}

/// True when every token of the search appears somewhere in [haystack]
/// (already folded with [foldForSearch]).
bool matchesAllTokens(String haystack, List<String> tokens) {
  if (tokens.isEmpty) {
    return false;
  }
  for (final token in tokens) {
    if (!haystack.contains(token)) {
      return false;
    }
  }
  return true;
}

/// A forgiving match for when the exact one finds nothing: each token may
/// differ from the start of some word by a letter or two ("manchster" still
/// finds "Manchester"). Short tokens must match exactly.
bool matchesSimilar(String haystack, List<String> tokens) {
  if (tokens.isEmpty) {
    return false;
  }
  final words = haystack.split(' ');
  for (final token in tokens) {
    final allowed = token.length >= 8 ? 2 : (token.length >= 4 ? 1 : 0);
    var found = false;
    for (final word in words) {
      if (word.startsWith(token) || word.contains(token)) {
        found = true;
        break;
      }
      if (allowed == 0) {
        continue;
      }
      final head = word.length > token.length
          ? word.substring(0, token.length)
          : word;
      if (_editDistance(token, head, allowed) <= allowed) {
        found = true;
        break;
      }
    }
    if (!found) {
      return false;
    }
  }
  return true;
}

/// Edit distance between [a] and [b], giving up (returning more than [limit])
/// once it cannot stay within it.
int _editDistance(String a, String b, int limit) {
  if ((a.length - b.length).abs() > limit) {
    return limit + 1;
  }
  var previous = List<int>.generate(b.length + 1, (i) => i);
  for (var i = 1; i <= a.length; i++) {
    final current = List<int>.filled(b.length + 1, 0);
    current[0] = i;
    var best = current[0];
    for (var j = 1; j <= b.length; j++) {
      final cost = a.codeUnitAt(i - 1) == b.codeUnitAt(j - 1) ? 0 : 1;
      var value = previous[j - 1] + cost;
      if (previous[j] + 1 < value) {
        value = previous[j] + 1;
      }
      if (current[j - 1] + 1 < value) {
        value = current[j - 1] + 1;
      }
      current[j] = value;
      if (value < best) {
        best = value;
      }
    }
    if (best > limit) {
      return limit + 1;
    }
    previous = current;
  }
  return previous[b.length];
}
