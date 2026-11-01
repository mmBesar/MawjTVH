import 'package:flutter/painting.dart';

/// Two colours for a channel's card, derived from its name so every channel
/// keeps the same look without downloading any artwork. Most land in the
/// blue-violet range of the app; roughly one in five is a warm sunset.
List<Color> channelGradient(String seed, {required bool dark}) {
  var hash = 17;
  for (final unit in seed.codeUnits) {
    hash = (hash * 31 + unit) & 0x7fffffff;
  }
  final warm = hash % 5 == 0;
  final hue = warm ? 12.0 + (hash % 24) : 205.0 + (hash % 75);
  final first = HSLColor.fromAHSL(
    1,
    hue % 360,
    dark ? 0.62 : 0.70,
    dark ? 0.24 : 0.82,
  ).toColor();
  final second = HSLColor.fromAHSL(
    1,
    (hue + 28) % 360,
    dark ? 0.55 : 0.65,
    dark ? 0.10 : 0.70,
  ).toColor();
  return <Color>[first, second];
}
