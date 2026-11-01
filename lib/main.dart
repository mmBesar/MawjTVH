import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart';
import 'package:provider/provider.dart';

import 'app.dart';
import 'data/app_state.dart';
import 'data/mpv_runtime.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  try {
    MediaKit.ensureInitialized();
  } catch (error) {
    debugPrint('media_kit initialisation failed: $error');
  }

  final state = await AppState.create();
  MpvRuntime.useCustomPath(state.settings.mpvPath);
  runApp(
    ChangeNotifierProvider<AppState>.value(
      value: state,
      child: const MawjApp(),
    ),
  );
}
