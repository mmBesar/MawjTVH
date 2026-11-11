/// Text subtitles of a live channel.
///
/// Tvheadend reads a satellite channel's teletext subtitle pages and sends
/// each one as a `TEXTSUB` stream of UTF-8 text (with simple `<font color>`
/// tags). A transport stream has no standard way to carry that to the player,
/// so the stream proxy hands the lines to the app, which draws them.
library;

/// One text subtitle stream the server listed for a channel.
class TextSubtitleStream {
  const TextSubtitleStream({required this.index, required this.language});

  /// HTSP stream index.
  final int index;

  /// Three-letter language code, or an empty string.
  final String language;
}

/// A subtitle text to show now (an empty one clears the screen).
class TextSubtitleLine {
  const TextSubtitleLine({
    required this.channelId,
    required this.stream,
    required this.text,
  });

  final String channelId;
  final int stream;
  final String text;
}

/// A run of subtitle text in one colour (null: the default, white).
class SubtitleSpan {
  const SubtitleSpan(this.text, this.color);

  final String text;

  /// 0xAARRGGBB, or null.
  final int? color;
}

final RegExp _tag = RegExp(
  r'<(/?)font(?:\s+color="#([0-9a-fA-F]{6})")?\s*>|<[^>]*>',
);

/// Splits subtitle [text] into coloured runs; tags other than `<font>` are
/// dropped. Returns an empty list for blank text.
List<SubtitleSpan> parseSubtitleSpans(String text) {
  final clean = text.replaceAll('\u0000', '').trim();
  final spans = <SubtitleSpan>[];
  int? color;
  var last = 0;
  for (final match in _tag.allMatches(clean)) {
    if (match.start > last) {
      spans.add(SubtitleSpan(clean.substring(last, match.start), color));
    }
    last = match.end;
    final closing = match.group(1);
    if (closing == null) {
      continue; // some other tag
    }
    if (closing == '/') {
      color = null;
    } else {
      final hex = match.group(2);
      color = hex == null ? null : 0xFF000000 | int.parse(hex, radix: 16);
    }
  }
  if (last < clean.length) {
    spans.add(SubtitleSpan(clean.substring(last), color));
  }
  return spans.where((span) => span.text.isNotEmpty).toList(growable: false);
}
