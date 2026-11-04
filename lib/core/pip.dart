import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Android picture-in-picture: the video keeps playing in a small floating
/// window above other apps. Other platforms ignore every call.
class PipService {
  PipService._();

  static const MethodChannel _channel = MethodChannel('mawjtvh/pip');

  /// True while the app is shown as the floating window.
  static final ValueNotifier<bool> active = ValueNotifier<bool>(false);

  static bool _ready = false;

  static void init() {
    if (_ready || !Platform.isAndroid) {
      return;
    }
    _ready = true;
    _channel.setMethodCallHandler((call) async {
      if (call.method == 'pip') {
        active.value = call.arguments == true;
      }
      return null;
    });
  }

  /// Float the video now. Returns false when the device cannot.
  static Future<bool> enter() async {
    if (!Platform.isAndroid) {
      return false;
    }
    init();
    try {
      return await _channel.invokeMethod<bool>('enter') ?? false;
    } on PlatformException {
      return false;
    } on MissingPluginException {
      return false;
    }
  }

  /// Float automatically when the user leaves the app (home / recents).
  static Future<void> autoEnter(bool value) async {
    if (!Platform.isAndroid) {
      return;
    }
    init();
    try {
      await _channel.invokeMethod<void>('autoEnter', value);
    } on PlatformException {
      // Not available on this build.
    } on MissingPluginException {
      // Not available on this build.
    }
  }
}
