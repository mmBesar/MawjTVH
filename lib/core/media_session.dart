import 'dart:async';
import 'dart:io' show Platform;

import 'package:flutter/services.dart';

/// What the lock screen, the notification shade and headset buttons can ask
/// the radio to do.
enum MediaAction { play, pause, toggle, stop, next, previous }

/// Android media session: a foreground service with a media notification, so
/// audio keeps playing with the screen off or another app in front, and the
/// notification, lock screen and headset buttons control it. Other platforms
/// ignore every call.
class MediaSessionService {
  MediaSessionService._();

  static const MethodChannel _channel = MethodChannel('mawjtvh/media');
  static final StreamController<MediaAction> _actions =
      StreamController<MediaAction>.broadcast();
  static bool _ready = false;

  /// Buttons pressed outside the app.
  static Stream<MediaAction> get actions {
    _init();
    return _actions.stream;
  }

  static void _init() {
    if (_ready || !Platform.isAndroid) {
      return;
    }
    _ready = true;
    _channel.setMethodCallHandler((call) async {
      if (call.method == 'action') {
        for (final action in MediaAction.values) {
          if (action.name == call.arguments) {
            _actions.add(action);
          }
        }
      }
      return null;
    });
  }

  /// Shows (or refreshes) the notification and holds the app alive while
  /// [playing]; a paused session stays in the shade so it can be resumed.
  static Future<void> update({
    required String title,
    required String subtitle,
    required bool playing,
    required bool canSkip,
  }) async {
    if (!Platform.isAndroid) {
      return;
    }
    _init();
    try {
      await _channel.invokeMethod<void>('update', <String, Object>{
        'title': title,
        'subtitle': subtitle,
        'playing': playing,
        'canSkip': canSkip,
      });
    } on PlatformException {
      // Playing still works without the notification.
    } on MissingPluginException {
      // Not available on this build.
    }
  }

  /// Removes the notification and lets the app sleep again.
  static Future<void> stop() async {
    if (!Platform.isAndroid) {
      return;
    }
    _init();
    try {
      await _channel.invokeMethod<void>('stop');
    } on PlatformException {
      // Nothing to stop.
    } on MissingPluginException {
      // Not available on this build.
    }
  }
}
