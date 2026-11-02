import 'package:flutter/material.dart';

/// MawjTVH's own deep-sea (dark) and foam (light) looks, the four upstream
/// Catppuccin flavours and a pure-black AMOLED mode.
enum ThemeFamily {
  system,
  studio,
  daylight,
  mawj,
  foam,
  latte,
  frappe,
  macchiato,
  mocha,
  amoled;

  String get label => switch (this) {
        ThemeFamily.system => 'System',
        ThemeFamily.studio => 'Studio',
        ThemeFamily.daylight => 'Daylight',
        ThemeFamily.mawj => 'Mawj',
        ThemeFamily.foam => 'Foam',
        ThemeFamily.latte => 'Latte',
        ThemeFamily.frappe => 'Frappé',
        ThemeFamily.macchiato => 'Macchiato',
        ThemeFamily.mocha => 'Mocha',
        ThemeFamily.amoled => 'AMOLED',
      };

  bool? get isDark => switch (this) {
        ThemeFamily.system => null,
        ThemeFamily.daylight => false,
        ThemeFamily.foam => false,
        ThemeFamily.latte => false,
        _ => true,
      };
}

/// Catppuccin's fourteen accent colours. The names are proper nouns and stay
/// the same in both interface languages.
enum ThemeAccent {
  rosewater('Rosewater'),
  flamingo('Flamingo'),
  pink('Pink'),
  mauve('Mauve'),
  red('Red'),
  maroon('Maroon'),
  peach('Peach'),
  yellow('Yellow'),
  green('Green'),
  teal('Teal'),
  sky('Sky'),
  sapphire('Sapphire'),
  blue('Blue'),
  lavender('Lavender');

  const ThemeAccent(this.label);

  final String label;
}

@immutable
class CatppuccinPalette {
  const CatppuccinPalette({
    required this.base,
    required this.mantle,
    required this.crust,
    required this.text,
    required this.subtext1,
    required this.subtext0,
    required this.overlay2,
    required this.overlay1,
    required this.overlay0,
    required this.surface2,
    required this.surface1,
    required this.surface0,
    required this.accents,
  });

  final Color base;
  final Color mantle;
  final Color crust;
  final Color text;
  final Color subtext1;
  final Color subtext0;
  final Color overlay2;
  final Color overlay1;
  final Color overlay0;
  final Color surface2;
  final Color surface1;
  final Color surface0;
  final Map<ThemeAccent, Color> accents;

  Color accent(ThemeAccent value) => accents[value] ?? accents[ThemeAccent.peach]!;
}

const Map<ThemeAccent, Color> _latteAccents = {
  ThemeAccent.rosewater: Color(0xFFDC8A78),
  ThemeAccent.flamingo: Color(0xFFDD7878),
  ThemeAccent.pink: Color(0xFFEA76CB),
  ThemeAccent.mauve: Color(0xFF8839EF),
  ThemeAccent.red: Color(0xFFD20F39),
  ThemeAccent.maroon: Color(0xFFE64553),
  ThemeAccent.peach: Color(0xFFFE640B),
  ThemeAccent.yellow: Color(0xFFDF8E1D),
  ThemeAccent.green: Color(0xFF40A02B),
  ThemeAccent.teal: Color(0xFF179299),
  ThemeAccent.sky: Color(0xFF04A5E5),
  ThemeAccent.sapphire: Color(0xFF209FB5),
  ThemeAccent.blue: Color(0xFF1E66F5),
  ThemeAccent.lavender: Color(0xFF7287FD),
};

const Map<ThemeAccent, Color> _frappeAccents = {
  ThemeAccent.rosewater: Color(0xFFF2D5CF),
  ThemeAccent.flamingo: Color(0xFFEEBEBE),
  ThemeAccent.pink: Color(0xFFF4B8E4),
  ThemeAccent.mauve: Color(0xFFCA9EE6),
  ThemeAccent.red: Color(0xFFE78284),
  ThemeAccent.maroon: Color(0xFFEA999C),
  ThemeAccent.peach: Color(0xFFEF9F76),
  ThemeAccent.yellow: Color(0xFFE5C890),
  ThemeAccent.green: Color(0xFFA6D189),
  ThemeAccent.teal: Color(0xFF81C8BE),
  ThemeAccent.sky: Color(0xFF99D1DB),
  ThemeAccent.sapphire: Color(0xFF85C1DC),
  ThemeAccent.blue: Color(0xFF8CAAEE),
  ThemeAccent.lavender: Color(0xFFBABBF1),
};

const Map<ThemeAccent, Color> _macchiatoAccents = {
  ThemeAccent.rosewater: Color(0xFFF4DBD6),
  ThemeAccent.flamingo: Color(0xFFF0C6C6),
  ThemeAccent.pink: Color(0xFFF5BDE6),
  ThemeAccent.mauve: Color(0xFFC6A0F6),
  ThemeAccent.red: Color(0xFFED8796),
  ThemeAccent.maroon: Color(0xFFEE99A0),
  ThemeAccent.peach: Color(0xFFF5A97F),
  ThemeAccent.yellow: Color(0xFFEED49F),
  ThemeAccent.green: Color(0xFFA6DA95),
  ThemeAccent.teal: Color(0xFF8BD5CA),
  ThemeAccent.sky: Color(0xFF91D7E3),
  ThemeAccent.sapphire: Color(0xFF7DC4E4),
  ThemeAccent.blue: Color(0xFF8AADF4),
  ThemeAccent.lavender: Color(0xFFB7BDF8),
};

const Map<ThemeAccent, Color> _mochaAccents = {
  ThemeAccent.rosewater: Color(0xFFF5E0DC),
  ThemeAccent.flamingo: Color(0xFFF2CDCD),
  ThemeAccent.pink: Color(0xFFF5C2E7),
  ThemeAccent.mauve: Color(0xFFCBA6F7),
  ThemeAccent.red: Color(0xFFF38BA8),
  ThemeAccent.maroon: Color(0xFFEBA0AC),
  ThemeAccent.peach: Color(0xFFFAB387),
  ThemeAccent.yellow: Color(0xFFF9E2AF),
  ThemeAccent.green: Color(0xFFA6E3A1),
  ThemeAccent.teal: Color(0xFF94E2D5),
  ThemeAccent.sky: Color(0xFF89DCEB),
  ThemeAccent.sapphire: Color(0xFF74C7EC),
  ThemeAccent.blue: Color(0xFF89B4FA),
  ThemeAccent.lavender: Color(0xFFB4BEFE),
};


/// Peach is MawjTVH's signature orange; the other accents follow Mocha.
const Map<ThemeAccent, Color> _mawjAccents = {
  ThemeAccent.rosewater: Color(0xFFF5E0DC),
  ThemeAccent.flamingo: Color(0xFFF2CDCD),
  ThemeAccent.pink: Color(0xFFF5C2E7),
  ThemeAccent.mauve: Color(0xFFCBA6F7),
  ThemeAccent.red: Color(0xFFFF6B81),
  ThemeAccent.maroon: Color(0xFFEBA0AC),
  ThemeAccent.peach: Color(0xFFFF8A3D),
  ThemeAccent.yellow: Color(0xFFFFD166),
  ThemeAccent.green: Color(0xFF6EE7A8),
  ThemeAccent.teal: Color(0xFF4FD1C5),
  ThemeAccent.sky: Color(0xFF7DD3FC),
  ThemeAccent.sapphire: Color(0xFF5AB0FF),
  ThemeAccent.blue: Color(0xFF7C9CFF),
  ThemeAccent.lavender: Color(0xFFB4BEFE),
};

const Map<ThemeAccent, Color> _foamAccents = {
  ThemeAccent.rosewater: Color(0xFFC96F5F),
  ThemeAccent.flamingo: Color(0xFFC85A5A),
  ThemeAccent.pink: Color(0xFFD1409F),
  ThemeAccent.mauve: Color(0xFF7B2FE0),
  ThemeAccent.red: Color(0xFFD1213F),
  ThemeAccent.maroon: Color(0xFFC63A47),
  ThemeAccent.peach: Color(0xFFE5560B),
  ThemeAccent.yellow: Color(0xFFB87400),
  ThemeAccent.green: Color(0xFF2E8B1F),
  ThemeAccent.teal: Color(0xFF0F7E86),
  ThemeAccent.sky: Color(0xFF0388C4),
  ThemeAccent.sapphire: Color(0xFF16899E),
  ThemeAccent.blue: Color(0xFF1B57E0),
  ThemeAccent.lavender: Color(0xFF5E73E6),
};

/// Studio accents: MawjTVH's own signature is a vivid broadcast green.
const Map<ThemeAccent, Color> _studioAccents = {
  ThemeAccent.rosewater: Color(0xFFF5E0DC),
  ThemeAccent.flamingo: Color(0xFFF2CDCD),
  ThemeAccent.pink: Color(0xFFF5C2E7),
  ThemeAccent.mauve: Color(0xFFCBA6F7),
  ThemeAccent.red: Color(0xFFFF6B6B),
  ThemeAccent.maroon: Color(0xFFEBA0AC),
  ThemeAccent.peach: Color(0xFFFF9F5A),
  ThemeAccent.yellow: Color(0xFFFFC857),
  ThemeAccent.green: Color(0xFF3DDC97),
  ThemeAccent.teal: Color(0xFF2BD4C0),
  ThemeAccent.sky: Color(0xFF7DD3FC),
  ThemeAccent.sapphire: Color(0xFF5AB0FF),
  ThemeAccent.blue: Color(0xFF7C9CFF),
  ThemeAccent.lavender: Color(0xFFB4BEFE),
};

const Map<ThemeAccent, Color> _daylightAccents = {
  ThemeAccent.rosewater: Color(0xFFC96F5F),
  ThemeAccent.flamingo: Color(0xFFC85A5A),
  ThemeAccent.pink: Color(0xFFD1409F),
  ThemeAccent.mauve: Color(0xFF7B2FE0),
  ThemeAccent.red: Color(0xFFD1213F),
  ThemeAccent.maroon: Color(0xFFC63A47),
  ThemeAccent.peach: Color(0xFFE5560B),
  ThemeAccent.yellow: Color(0xFFB87400),
  ThemeAccent.green: Color(0xFF0E9F6E),
  ThemeAccent.teal: Color(0xFF0B8F86),
  ThemeAccent.sky: Color(0xFF0388C4),
  ThemeAccent.sapphire: Color(0xFF16899E),
  ThemeAccent.blue: Color(0xFF1B57E0),
  ThemeAccent.lavender: Color(0xFF5E73E6),
};

/// Pine-black with a broadcast-green accent: the default look.
const CatppuccinPalette studioPalette = CatppuccinPalette(
  base: Color(0xFF0A100F),
  mantle: Color(0xFF070C0B),
  crust: Color(0xFF040706),
  text: Color(0xFFEAF5F0),
  subtext1: Color(0xFFC3D6CE),
  subtext0: Color(0xFF98B0A6),
  overlay2: Color(0xFF7E968C),
  overlay1: Color(0xFF668077),
  overlay0: Color(0xFF506760),
  surface2: Color(0xFF2A3F38),
  surface1: Color(0xFF1D2E29),
  surface0: Color(0xFF132019),
  accents: _studioAccents,
);

/// Warm paper light look to go with Studio.
const CatppuccinPalette daylightPalette = CatppuccinPalette(
  base: Color(0xFFFBF8F2),
  mantle: Color(0xFFF3EEE4),
  crust: Color(0xFFE8E1D3),
  text: Color(0xFF1B2B26),
  subtext1: Color(0xFF33463F),
  subtext0: Color(0xFF55685F),
  overlay2: Color(0xFF73867D),
  overlay1: Color(0xFF90A198),
  overlay0: Color(0xFFA9B8B0),
  surface2: Color(0xFFCFD8CF),
  surface1: Color(0xFFDFE5DC),
  surface0: Color(0xFFEBEEE6),
  accents: _daylightAccents,
);

/// Deep-sea blue: the original Mawj look.
const CatppuccinPalette mawjPalette = CatppuccinPalette(
  base: Color(0xFF070D20),
  mantle: Color(0xFF050A19),
  crust: Color(0xFF03060F),
  text: Color(0xFFF2F6FC),
  subtext1: Color(0xFFC9D3EA),
  subtext0: Color(0xFF9AA8CC),
  overlay2: Color(0xFF8391B8),
  overlay1: Color(0xFF6F7DA6),
  overlay0: Color(0xFF5B688F),
  surface2: Color(0xFF2B3C73),
  surface1: Color(0xFF1D2B58),
  surface0: Color(0xFF121D40),
  accents: _mawjAccents,
);

/// Light counterpart: white foam with navy text.
const CatppuccinPalette foamPalette = CatppuccinPalette(
  base: Color(0xFFF5F8FD),
  mantle: Color(0xFFEBF0F9),
  crust: Color(0xFFDFE6F3),
  text: Color(0xFF0B1330),
  subtext1: Color(0xFF263253),
  subtext0: Color(0xFF4A5778),
  overlay2: Color(0xFF68759A),
  overlay1: Color(0xFF8490B2),
  overlay0: Color(0xFF9CA7C4),
  surface2: Color(0xFFBBC6DE),
  surface1: Color(0xFFCFD8EA),
  surface0: Color(0xFFE1E8F5),
  accents: _foamAccents,
);

const CatppuccinPalette lattePalette = CatppuccinPalette(
  base: Color(0xFFEFF1F5),
  mantle: Color(0xFFE6E9EF),
  crust: Color(0xFFDCE0E8),
  text: Color(0xFF4C4F69),
  subtext1: Color(0xFF5C5F77),
  subtext0: Color(0xFF6C6F85),
  overlay2: Color(0xFF7C7F93),
  overlay1: Color(0xFF8C8FA1),
  overlay0: Color(0xFF9CA0B0),
  surface2: Color(0xFFACB0BE),
  surface1: Color(0xFFBCC0CC),
  surface0: Color(0xFFCCD0DA),
  accents: _latteAccents,
);

const CatppuccinPalette frappePalette = CatppuccinPalette(
  base: Color(0xFF303446),
  mantle: Color(0xFF292C3C),
  crust: Color(0xFF232634),
  text: Color(0xFFC6D0F5),
  subtext1: Color(0xFFB5BFE2),
  subtext0: Color(0xFFA5ADCE),
  overlay2: Color(0xFF949CBB),
  overlay1: Color(0xFF838BA7),
  overlay0: Color(0xFF737994),
  surface2: Color(0xFF626880),
  surface1: Color(0xFF51576D),
  surface0: Color(0xFF414559),
  accents: _frappeAccents,
);

const CatppuccinPalette macchiatoPalette = CatppuccinPalette(
  base: Color(0xFF24273A),
  mantle: Color(0xFF1E2030),
  crust: Color(0xFF181926),
  text: Color(0xFFCAD3F5),
  subtext1: Color(0xFFB8C0E0),
  subtext0: Color(0xFFA5ADCB),
  overlay2: Color(0xFF939AB7),
  overlay1: Color(0xFF8087A2),
  overlay0: Color(0xFF6E738D),
  surface2: Color(0xFF5B6078),
  surface1: Color(0xFF494D64),
  surface0: Color(0xFF363A4F),
  accents: _macchiatoAccents,
);

const CatppuccinPalette mochaPalette = CatppuccinPalette(
  base: Color(0xFF1E1E2E),
  mantle: Color(0xFF181825),
  crust: Color(0xFF11111B),
  text: Color(0xFFCDD6F4),
  subtext1: Color(0xFFBAC2DE),
  subtext0: Color(0xFFA6ADC8),
  overlay2: Color(0xFF9399B2),
  overlay1: Color(0xFF7F849C),
  overlay0: Color(0xFF6C7086),
  surface2: Color(0xFF585B70),
  surface1: Color(0xFF45475A),
  surface0: Color(0xFF313244),
  accents: _mochaAccents,
);

CatppuccinPalette paletteFor(ThemeFamily family) {
  return switch (family) {
    ThemeFamily.studio => studioPalette,
    ThemeFamily.daylight => daylightPalette,
    ThemeFamily.mawj => mawjPalette,
    ThemeFamily.foam => foamPalette,
    ThemeFamily.latte => lattePalette,
    ThemeFamily.frappe => frappePalette,
    ThemeFamily.macchiato => macchiatoPalette,
    ThemeFamily.amoled || ThemeFamily.mocha => mochaPalette,
    ThemeFamily.system => studioPalette,
  };
}
