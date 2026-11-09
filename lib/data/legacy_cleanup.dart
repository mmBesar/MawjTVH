import 'dart:io';

import 'package:flutter/foundation.dart' show debugPrint;
import 'package:path_provider/path_provider.dart';

/// Versions 0.1.24 and 0.1.25 kept a copy of past guide days on the device.
/// That was dropped (the guide shows only what the server offers); this
/// removes what those versions left behind.
Future<void> removeLeftoverGuideHistory() async {
  try {
    final base = await getApplicationSupportDirectory();
    final folder = Directory('${base.path}/guide_history');
    if (await folder.exists()) {
      await folder.delete(recursive: true);
    }
  } catch (error) {
    debugPrint('Could not remove old guide history: $error');
  }
}
