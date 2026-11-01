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

/// Where and how recordings made on this device are written. The player
/// copies the stream it is playing into the file (mpv `stream-record`), so
/// nothing is re-encoded.
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
