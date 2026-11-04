import 'dart:async';

import 'package:dynamic_color/dynamic_color.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:provider/provider.dart';

import 'core/catppuccin.dart';
import 'core/theme.dart';
import 'core/ui_zoom.dart';
import 'data/app_state.dart';
import 'data/models.dart';
import 'l10n/strings.dart';
import 'ui/app_shell.dart';

class MawjScrollBehavior extends MaterialScrollBehavior {
  const MawjScrollBehavior();

  @override
  Set<PointerDeviceKind> get dragDevices => <PointerDeviceKind>{
        PointerDeviceKind.touch,
        PointerDeviceKind.mouse,
        PointerDeviceKind.trackpad,
        PointerDeviceKind.stylus,
      };
}

class MawjApp extends StatelessWidget {
  const MawjApp({super.key});

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final settings = state.settings;
    final family = settings.themeFamily;

    return DynamicColorBuilder(
      builder: (lightDynamic, darkDynamic) {
        final theme = buildMawjTVHTheme(
          family: family,
          accent: settings.accent,
          brightness: Brightness.light,
          dynamicScheme: family == ThemeFamily.system ? lightDynamic : null,
        );
        final darkTheme = buildMawjTVHTheme(
          family: family,
          accent: settings.accent,
          brightness: Brightness.dark,
          dynamicScheme: family == ThemeFamily.system ? darkDynamic : null,
        );

        final languageCode = settings.language.localeCode;
        return MaterialApp(
          title: 'MawjTVH',
          debugShowCheckedModeBanner: false,
          theme: theme,
          darkTheme: darkTheme,
          themeMode: family == ThemeFamily.system
              ? ThemeMode.system
              : (family.isDark! ? ThemeMode.dark : ThemeMode.light),
          themeAnimationDuration: const Duration(milliseconds: 220),
          locale: languageCode == null ? null : Locale(languageCode),
          supportedLocales: AppStrings.supportedLocales,
          localizationsDelegates: const <LocalizationsDelegate<dynamic>>[
            AppStringsDelegate(),
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          scrollBehavior: const MawjScrollBehavior(),
          builder: (context, child) {
            final media = MediaQuery.of(context);
            return CallbackShortcuts(
              bindings: uiZoomShortcuts(
                current: () => state.settings.uiScale,
                onChange: (scale) => unawaited(state.setUiScale(scale)),
              ),
              child: UiZoom(
                scale: effectiveUiScale(settings.uiScale),
                child: MediaQuery(
                  data: media.copyWith(
                    alwaysUse24HourFormat: settings.use24HourTime,
                  ),
                  child: child ?? const SizedBox.shrink(),
                ),
              ),
            );
          },
          home: const AppShell(),
        );
      },
    );
  }
}
