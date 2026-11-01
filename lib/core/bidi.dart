import 'package:flutter/widgets.dart';

/// Unicode isolate controls. Wrapping a user-provided run in FSI/PDI keeps
/// its internal direction from leaking into the surrounding UI (and vice
/// versa), which is what makes mixed Arabic/English EPG text predictable.
const String kFirstStrongIsolate = '\u2068';
const String kPopDirectionalIsolate = '\u2069';

/// Returns the base direction of [text] using the Unicode first-strong
/// heuristic, with an LTR fallback for text without letters (numbers, emoji).
TextDirection bidiDirectionOf(String text) {
  for (final rune in text.runes) {
    if (_isRightToLeft(rune)) {
      return TextDirection.rtl;
    }
    if (_isLeftToRightLetter(rune)) {
      return TextDirection.ltr;
    }
  }
  return TextDirection.ltr;
}

/// Wraps [text] in a first-strong isolate so the surrounding paragraph
/// direction cannot reorder it.
String bidiIsolate(String text) =>
    '$kFirstStrongIsolate$text$kPopDirectionalIsolate';

bool _isLeftToRightLetter(int rune) {
  return (rune >= 0x0041 && rune <= 0x005A) ||
      (rune >= 0x0061 && rune <= 0x007A) ||
      (rune >= 0x00C0 && rune <= 0x02AF) ||
      (rune >= 0x0370 && rune <= 0x052F) ||
      (rune >= 0x0531 && rune <= 0x058F) ||
      (rune >= 0x0900 && rune <= 0x1FFF) ||
      (rune >= 0x2C00 && rune <= 0xD7FF) ||
      (rune >= 0xF900 && rune <= 0xFAFF);
}

bool _isRightToLeft(int rune) {
  return (rune >= 0x0590 && rune <= 0x05FF) || // Hebrew
      (rune >= 0x0600 && rune <= 0x06FF) || // Arabic
      (rune >= 0x0700 && rune <= 0x074F) || // Syriac
      (rune >= 0x0750 && rune <= 0x077F) || // Arabic Supplement
      (rune >= 0x0780 && rune <= 0x07BF) || // Thaana
      (rune >= 0x07C0 && rune <= 0x07FF) || // NKo
      (rune >= 0x0800 && rune <= 0x083F) || // Samaritan
      (rune >= 0x0840 && rune <= 0x085F) || // Mandaic
      (rune >= 0x08A0 && rune <= 0x08FF) || // Arabic Extended-A
      (rune >= 0xFB1D && rune <= 0xFDFF) || // Hebrew/Arabic presentation
      (rune >= 0xFE70 && rune <= 0xFEFF) || // Arabic presentation forms-B
      (rune >= 0x10800 && rune <= 0x10FFF) || // Historic RTL scripts
      (rune >= 0x1E800 && rune <= 0x1EFFF); // Adlam and friends
}

/// A [Text] that decides its own base direction instead of inheriting the
/// interface direction. Use this for channel names, programme titles,
/// subtitles, descriptions and any other user/source supplied string.
class BidiText extends StatelessWidget {
  const BidiText(
    this.text, {
    super.key,
    this.style,
    this.maxLines,
    this.overflow,
    this.textAlign,
    this.softWrap = true,
    this.semanticsLabel,
  });

  final String text;
  final TextStyle? style;
  final int? maxLines;
  final TextOverflow? overflow;
  final TextAlign? textAlign;
  final bool softWrap;
  final String? semanticsLabel;

  @override
  Widget build(BuildContext context) {
    final direction = bidiDirectionOf(text);
    return Directionality(
      textDirection: direction,
      child: Text(
        bidiIsolate(text),
        style: style,
        maxLines: maxLines,
        overflow: overflow,
        softWrap: softWrap,
        textAlign: textAlign ?? TextAlign.start,
        semanticsLabel: semanticsLabel,
      ),
    );
  }
}
