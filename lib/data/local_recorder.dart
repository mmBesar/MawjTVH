import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

/// A file saved by "record to this device".
class LocalRecordingFile {
  const LocalRecordingFile({
    required this.path,
    required this.name,
    required this.size,
    required this.modified,
  });

  final String path;
  final String name;
  final int size;
  final DateTime modified;
}

/// Where and how recordings made on this device are written. The stream
/// is copied as it is (see [StreamRecorder]), so nothing is re-encoded.
class LocalRecordings {
  const LocalRecordings._();

  static const String extension = '.ts';
  static const Set<String> _known = <String>{
    '.ts',
    '.mkv',
    '.mp4',
    '.m2ts',
    '.mpg',
    '.avi',
  };

  /// The folder to save in: the chosen one, else the app's own movies folder
  /// on Android, else `~/Videos/MawjTVH`.
  static Future<Directory> directory(String configured) async {
    final chosen = configured.trim();
    Directory dir;
    if (chosen.isNotEmpty) {
      dir = Directory(chosen);
    } else if (Platform.isAndroid) {
      final base = await getExternalStorageDirectory() ??
          await getApplicationDocumentsDirectory();
      dir = Directory('${base.path}${Platform.pathSeparator}MawjTVH');
    } else {
      final home = Platform.environment['HOME'] ?? '.';
      dir = Directory('$home${Platform.pathSeparator}Videos${Platform.pathSeparator}MawjTVH');
    }
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    return dir;
  }

  /// `News 24 - 2026-11-01 14.05.30.ts`: safe on every file system.
  static String fileName(String channelName, DateTime now) {
    String two(int n) => n.toString().padLeft(2, '0');
    final safe = channelName
        .replaceAll(RegExp(r'[\\/:*?"<>|\x00-\x1f]'), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
    final stamp = '${now.year}-${two(now.month)}-${two(now.day)} '
        '${two(now.hour)}.${two(now.minute)}.${two(now.second)}';
    return '${safe.isEmpty ? 'Recording' : safe} - $stamp$extension';
  }

  static Future<String> newPath(
    String configured,
    String channelName, [
    DateTime? now,
  ]) async {
    final dir = await directory(configured);
    return '${dir.path}${Platform.pathSeparator}'
        '${fileName(channelName, now ?? DateTime.now())}';
  }

  static Future<List<LocalRecordingFile>> list(String configured) async {
    final dir = await directory(configured);
    final files = <LocalRecordingFile>[];
    await for (final entity in dir.list()) {
      if (entity is! File) {
        continue;
      }
      final name = entity.uri.pathSegments.last;
      final dot = name.lastIndexOf('.');
      if (dot < 0 || !_known.contains(name.substring(dot).toLowerCase())) {
        continue;
      }
      final stat = await entity.stat();
      files.add(
        LocalRecordingFile(
          path: entity.path,
          name: name,
          size: stat.size,
          modified: stat.modified,
        ),
      );
    }
    files.sort((a, b) => b.modified.compareTo(a.modified));
    return files;
  }

  static Future<void> delete(String path) async {
    final file = File(path);
    if (await file.exists()) {
      await file.delete();
    }
  }
}

/// Copies a live stream into a file over its own HTTP connection.
///
/// This does not touch the player: mpv's `stream-record` fails on Android
/// (no file cache) and resets the connection on some desktop builds, so the
/// recorder simply opens a second subscription on the same channel. Tvheadend
/// shares the tuner between subscriptions, so this costs no extra tuner.
class StreamRecorder {
  StreamRecorder._(this.path, this._client, this._sink, this._done);

  final String path;
  final HttpClient _client;
  final IOSink _sink;
  final Future<void> _done;
  bool _stopped = false;

  /// Resolves when the stream ends or fails; completes with an error text
  /// when it stopped on its own rather than because [stop] was called.
  Future<void> get finished => _done;

  /// Starts copying [url] into [path]. Throws if the server refuses.
  static Future<StreamRecorder> start({
    required String url,
    required String path,
    required bool allowInsecure,
    void Function(String message)? onError,
  }) async {
    final uri = Uri.parse(url);
    final userInfo = uri.userInfo;
    final requestUri = userInfo.isEmpty
        ? uri
        : Uri(
            scheme: uri.scheme,
            host: uri.host,
            port: uri.hasPort ? uri.port : null,
            path: uri.path,
            query: uri.query.isEmpty ? null : uri.query,
          );
    final client = HttpClient()
      ..connectionTimeout = const Duration(seconds: 15)
      ..userAgent = 'MawjTVH/0.1.0';
    if (allowInsecure) {
      client.badCertificateCallback = (_, _, _) => true;
    }
    try {
      final request = await client.getUrl(requestUri);
      if (userInfo.isNotEmpty) {
        request.headers.set(
          HttpHeaders.authorizationHeader,
          'Basic ${base64Encode(utf8.encode(Uri.decodeComponent(userInfo)))}',
        );
      }
      final response = await request.close();
      if (response.statusCode != 200) {
        await response.drain<void>();
        throw HttpException('HTTP ${response.statusCode}', uri: requestUri);
      }
      final sink = File(path).openWrite();
      late final StreamRecorder recorder;
      final done = Completer<void>();
      response.listen(
        sink.add,
        onError: (Object error) {
          if (!recorder._stopped) {
            onError?.call('$error');
          }
          if (!done.isCompleted) {
            done.complete();
          }
        },
        onDone: () {
          if (!recorder._stopped) {
            onError?.call('Stream ended');
          }
          if (!done.isCompleted) {
            done.complete();
          }
        },
        cancelOnError: true,
      );
      recorder = StreamRecorder._(path, client, sink, done.future);
      return recorder;
    } catch (_) {
      client.close(force: true);
      rethrow;
    }
  }

  Future<void> stop() async {
    if (_stopped) {
      return;
    }
    _stopped = true;
    _client.close(force: true);
    try {
      await _sink.flush();
      await _sink.close();
    } catch (_) {
      // The file is already as complete as it will get.
    }
  }
}
