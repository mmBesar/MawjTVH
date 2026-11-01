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
