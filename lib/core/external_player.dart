import 'package:flutter/services.dart';

/// The free players MawjTVH can hand a stream to on Android. Both are open
/// source, accept a start position, and report where they stopped.
enum ExternalPlayerApp {
  mpv('mpv', 'is.xyz.mpv', 'mpv'),
  vlc('vlc', 'org.videolan.vlc', 'VLC');

  const ExternalPlayerApp(this.id, this.androidPackage, this.label);

  /// What the setting stores.
  final String id;
  final String androidPackage;
  final String label;

  /// The player named by a stored setting; null for the built-in player.
  static ExternalPlayerApp? byId(String id) {
    for (final app in ExternalPlayerApp.values) {
      if (app.id == id) {
        return app;
      }
    }
    return null;
  }
}

/// Where the external player stopped, when it said so.
class ExternalPlayerResult {
  const ExternalPlayerResult({this.position, this.duration});

  final Duration? position;
  final Duration? duration;
}

/// The chosen player is not installed.
class ExternalPlayerMissing implements Exception {
  const ExternalPlayerMissing(this.app);

  final ExternalPlayerApp app;
}

/// Reads the reply of the Android side: whole milliseconds under `position`
/// and `duration`, either of which may be absent.
ExternalPlayerResult parseExternalPlayerResult(Map<String, Object?>? reply) {
  Duration? read(Object? value) {
    if (value is int && value >= 0) {
      return Duration(milliseconds: value);
    }
    return null;
  }

  if (reply == null) {
    return const ExternalPlayerResult();
  }
  return ExternalPlayerResult(
    position: read(reply['position']),
    duration: read(reply['duration']),
  );
}

/// Plays a stream in another app and waits until it is closed.
class ExternalPlayer {
  ExternalPlayer._();

  static const MethodChannel _channel = MethodChannel('mawjtvh/external_player');

  /// Opens [url] in [app], starting at [start] when given. Completes when the
  /// person leaves that player, with the position it reports (mpv and VLC
  /// both do when closed with Back).
  static Future<ExternalPlayerResult> play({
    required ExternalPlayerApp app,
    required String url,
    required String title,
    Duration? start,
  }) async {
    try {
      final reply = await _channel.invokeMapMethod<String, Object?>(
        'play',
        <String, Object?>{
          'package': app.androidPackage,
          'url': url,
          'title': title,
          'positionMs': start?.inMilliseconds ?? 0,
        },
      );
      return parseExternalPlayerResult(reply);
    } on PlatformException catch (error) {
      if (error.code == 'missing') {
        throw ExternalPlayerMissing(app);
      }
      rethrow;
    }
  }
}
