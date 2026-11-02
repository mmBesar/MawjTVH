import 'package:flutter/material.dart';

import 'catppuccin.dart';

const List<String> kFontFallback = <String>[
  'MawjArabic',
  'Noto Sans Arabic',
  'Noto Naskh Arabic',
  'DejaVu Sans',
  'Liberation Sans',
];

/// Theme values that are useful across widgets but do not map one-to-one onto
/// Material's [ColorScheme]. Keeping them in a [ThemeExtension] means the
/// Catppuccin palette stays exact, while system/dynamic colour still works.
@immutable
class MawjColors extends ThemeExtension<MawjColors> {
  const MawjColors({
    required this.base,
    required this.mantle,
    required this.crust,
    required this.surface0,
    required this.surface1,
    required this.surface2,
    required this.overlay0,
    required this.overlay1,
    required this.text,
    required this.subtext0,
    required this.subtext1,
    required this.accent,
    required this.accentSoft,
    required this.isAmoled,
  });

  final Color base;
  final Color mantle;
  final Color crust;
  final Color surface0;
  final Color surface1;
  final Color surface2;
  final Color overlay0;
  final Color overlay1;
  final Color text;
  final Color subtext0;
  final Color subtext1;
  final Color accent;
  final Color accentSoft;
  final bool isAmoled;

  factory MawjColors.fromPalette(
    CatppuccinPalette palette,
    ThemeAccent accent, {
    required bool amoled,
  }) {
    final accentColor = palette.accent(accent);
    return MawjColors(
      base: amoled ? Colors.black : palette.base,
      mantle: amoled ? const Color(0xFF070707) : palette.mantle,
      crust: amoled ? const Color(0xFF0C0C0C) : palette.crust,
      surface0: amoled ? const Color(0xFF111111) : palette.surface0,
      surface1: amoled ? const Color(0xFF1C1C1C) : palette.surface1,
      surface2: amoled ? const Color(0xFF262626) : palette.surface2,
      overlay0: palette.overlay0,
      overlay1: palette.overlay1,
      text: palette.text,
      subtext0: palette.subtext0,
      subtext1: palette.subtext1,
      accent: accentColor,
      accentSoft: accentColor.withValues(alpha: 0.16),
      isAmoled: amoled,
    );
  }

  factory MawjColors.fromScheme(ColorScheme scheme) {
    return MawjColors(
      base: scheme.surface,
      mantle: scheme.surfaceContainerLow,
      crust: scheme.surfaceContainerLowest,
      surface0: scheme.surfaceContainer,
      surface1: scheme.surfaceContainerHigh,
      surface2: scheme.surfaceContainerHighest,
      overlay0: scheme.outline,
      overlay1: scheme.outlineVariant,
      text: scheme.onSurface,
      subtext0: scheme.onSurfaceVariant,
      subtext1: scheme.onSurfaceVariant,
      accent: scheme.primary,
      accentSoft: scheme.primary.withValues(alpha: 0.16),
      isAmoled: false,
    );
  }

  @override
  MawjColors copyWith({
    Color? base,
    Color? mantle,
    Color? crust,
    Color? surface0,
    Color? surface1,
    Color? surface2,
    Color? overlay0,
    Color? overlay1,
    Color? text,
    Color? subtext0,
    Color? subtext1,
    Color? accent,
    Color? accentSoft,
    bool? isAmoled,
  }) {
    return MawjColors(
      base: base ?? this.base,
      mantle: mantle ?? this.mantle,
      crust: crust ?? this.crust,
      surface0: surface0 ?? this.surface0,
      surface1: surface1 ?? this.surface1,
      surface2: surface2 ?? this.surface2,
      overlay0: overlay0 ?? this.overlay0,
      overlay1: overlay1 ?? this.overlay1,
      text: text ?? this.text,
      subtext0: subtext0 ?? this.subtext0,
      subtext1: subtext1 ?? this.subtext1,
      accent: accent ?? this.accent,
      accentSoft: accentSoft ?? this.accentSoft,
      isAmoled: isAmoled ?? this.isAmoled,
    );
  }

  @override
  MawjColors lerp(ThemeExtension<MawjColors>? other, double t) {
    if (other is! MawjColors) {
      return this;
    }
    return MawjColors(
      base: Color.lerp(base, other.base, t)!,
      mantle: Color.lerp(mantle, other.mantle, t)!,
      crust: Color.lerp(crust, other.crust, t)!,
      surface0: Color.lerp(surface0, other.surface0, t)!,
      surface1: Color.lerp(surface1, other.surface1, t)!,
      surface2: Color.lerp(surface2, other.surface2, t)!,
      overlay0: Color.lerp(overlay0, other.overlay0, t)!,
      overlay1: Color.lerp(overlay1, other.overlay1, t)!,
      text: Color.lerp(text, other.text, t)!,
      subtext0: Color.lerp(subtext0, other.subtext0, t)!,
      subtext1: Color.lerp(subtext1, other.subtext1, t)!,
      accent: Color.lerp(accent, other.accent, t)!,
      accentSoft: Color.lerp(accentSoft, other.accentSoft, t)!,
      isAmoled: t < 0.5 ? isAmoled : other.isAmoled,
    );
  }
}

extension MawjThemeContext on BuildContext {
  MawjColors get mawjColors {
    final theme = Theme.of(this);
    return theme.extension<MawjColors>() ??
        MawjColors.fromScheme(theme.colorScheme);
  }
}

ThemeData buildMawjTVHTheme({
  required ThemeFamily family,
  required ThemeAccent accent,
  required Brightness brightness,
  ColorScheme? dynamicScheme,
}) {
  if (family == ThemeFamily.system && dynamicScheme != null) {
    final scheme = dynamicScheme.copyWith(surfaceTint: Colors.transparent);
    return _baseTheme(
      scheme: scheme,
      colors: MawjColors.fromScheme(scheme),
      background: scheme.surface,
    );
  }

  final resolvedFamily = family == ThemeFamily.system
      ? (brightness == Brightness.dark ? ThemeFamily.studio : ThemeFamily.daylight)
      : family;
  final amoled = resolvedFamily == ThemeFamily.amoled;
  final palette = paletteFor(resolvedFamily);
  final accentColor = palette.accent(accent);
  final onAccent = _onColor(accentColor);
  final background = amoled ? Colors.black : palette.base;

  final seed = ColorScheme.fromSeed(
    seedColor: accentColor,
    brightness: resolvedFamily.isDark == false
        ? Brightness.light
        : Brightness.dark,
  );

  final scheme = seed.copyWith(
    primary: accentColor,
    onPrimary: onAccent,
    primaryContainer: accentColor.withValues(alpha: amoled ? 0.24 : 0.16),
    onPrimaryContainer: palette.text,
    secondary: accentColor,
    onSecondary: onAccent,
    secondaryContainer: amoled ? const Color(0xFF1A1A1A) : palette.surface0,
    onSecondaryContainer: palette.text,
    surface: background,
    onSurface: palette.text,
    surfaceTint: Colors.transparent,
    surfaceContainerLowest: amoled ? Colors.black : palette.crust,
    surfaceContainerLow: amoled ? const Color(0xFF050505) : palette.mantle,
    surfaceContainer: amoled ? const Color(0xFF0A0A0A) : palette.base,
    surfaceContainerHigh: amoled ? const Color(0xFF111111) : palette.surface0,
    surfaceContainerHighest:
        amoled ? const Color(0xFF181818) : palette.surface1,
    onSurfaceVariant: palette.subtext0,
    outline: palette.overlay0,
    outlineVariant: palette.surface1,
    error: palette.accents[ThemeAccent.red]!,
    onError: _onColor(palette.accents[ThemeAccent.red]!),
  );

  return _baseTheme(
    scheme: scheme,
    colors: MawjColors.fromPalette(palette, accent, amoled: amoled),
    background: background,
  );
}

ThemeData _baseTheme({
  required ColorScheme scheme,
  required MawjColors colors,
  required Color background,
}) {
  final base = ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    scaffoldBackgroundColor: background,
    canvasColor: background,
    fontFamilyFallback: kFontFallback,
  );

  final inputBorder = OutlineInputBorder(
    borderRadius: BorderRadius.circular(12),
    borderSide: BorderSide(color: colors.surface1),
  );

  return base.copyWith(
    textTheme: base.textTheme.apply(
      bodyColor: colors.text,
      displayColor: colors.text,
    ),
    primaryTextTheme: base.primaryTextTheme.apply(
      bodyColor: colors.text,
      displayColor: colors.text,
    ),
    iconTheme: IconThemeData(color: colors.subtext0),
    dividerColor: colors.surface1,
    splashFactory: InkRipple.splashFactory,
    appBarTheme: AppBarTheme(
      backgroundColor: background,
      foregroundColor: colors.text,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      scrolledUnderElevation: 1,
      centerTitle: false,
    ),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: colors.mantle,
      indicatorColor: colors.accentSoft,
      elevation: 0,
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: colors.surface0,
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
      hintStyle: TextStyle(color: colors.overlay0),
      prefixIconColor: colors.overlay0,
      suffixIconColor: colors.subtext0,
      border: inputBorder,
      enabledBorder: inputBorder,
      focusedBorder: inputBorder.copyWith(
        borderSide: BorderSide(color: colors.accent, width: 1.6),
      ),
    ),
    snackBarTheme: SnackBarThemeData(
      backgroundColor: colors.surface2,
      contentTextStyle: TextStyle(color: colors.text),
      behavior: SnackBarBehavior.floating,
    ),
    extensions: <ThemeExtension<dynamic>>[colors],
  );
}

Color _onColor(Color color) =>
    color.computeLuminance() > 0.55 ? Colors.black : Colors.white;

Color previewColorFor(ThemeFamily family, ThemeAccent accent) {
  if (family == ThemeFamily.system) {
    return const Color(0xFFFF8A3D);
  }
  return paletteFor(family).accent(accent);
}
