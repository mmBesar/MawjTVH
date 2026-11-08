import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart' show debugPrint;
import 'package:path_provider/path_provider.dart';

import 'models.dart';

/// A small on-device memory of programmes that have already aired.
///
/// Tvheadend drops finished programmes from its guide soon after they end, so
/// "yesterday" would otherwise be empty. While the app runs it copies every
/// programme that has started into one file per calendar day; a day is read
/// back only when the guide shows it, so nothing but the viewed day (and the
/// one before it, for programmes that cross midnight) is held in memory.
///
/// Only the lines a guide row needs are kept: title, sub-title, a short
/// description and the episode label.
class GuideHistory {
  GuideHistory(this.sourceId);

  final String sourceId;

  static const int _maxDescription = 280;

  Directory? _folder;
  bool _folderTried = false;

  /// Calendar day (`20261108`) -> channel id -> programmes, for the days that
  /// were loaded or have new programmes waiting to be saved.
  final Map<String, Map<String, List<Programme>>> _days =
      <String, Map<String, List<Programme>>>{};
  final Set<String> _loaded = <String>{};
  final Set<String> _dirty = <String>{};
  final Set<String> _seen = <String>{};
  Set<String> _wanted = <String>{};

  static String dayKey(DateTime day) =>
      '${day.year.toString().padLeft(4, '0')}'
      '${day.month.toString().padLeft(2, '0')}'
      '${day.day.toString().padLeft(2, '0')}';

  Future<Directory?> _dir() async {
    if (_folderTried) {
      return _folder;
    }
    _folderTried = true;
    try {
      final base = await getApplicationSupportDirectory();
      final safe = sourceId.replaceAll(RegExp(r'[^A-Za-z0-9_-]'), '_');
      final dir = Directory('${base.path}/guide_history/$safe');
      await dir.create(recursive: true);
      _folder = dir;
    } catch (error) {
      debugPrint('Guide history has no folder: $error');
    }
    return _folder;
  }

  /// Notes the programmes that have started, so they can be shown later.
  /// Cheap to call often: a programme is taken in once.
  void capture(Iterable<Programme> programmes, DateTime now) {
    if (_seen.length > 40000) {
      _seen.clear();
    }
    for (final programme in programmes) {
      if (programme.start.isAfter(now) || programme.title.isEmpty) {
        continue;
      }
      final key =
          '${programme.channelId}|${programme.start.millisecondsSinceEpoch}';
      if (!_seen.add(key)) {
        continue;
      }
      final day = dayKey(programme.start);
      final byChannel = _days.putIfAbsent(day, () => <String, List<Programme>>{});
      final list = byChannel.putIfAbsent(
        programme.channelId,
        () => <Programme>[],
      );
      list.add(_slim(programme));
      _dirty.add(day);
    }
  }

  static Programme _slim(Programme p) {
    final description = p.description;
    return Programme(
      channelId: p.channelId,
      start: p.start,
      stop: p.stop,
      title: p.title,
      subTitle: p.subTitle,
      description: description != null && description.length > _maxDescription
          ? description.substring(0, _maxDescription)
          : description,
      episode: p.episode,
    );
  }

  /// Writes what is waiting to disk.
  Future<void> flush() async {
    if (_dirty.isEmpty) {
      return;
    }
    final dir = await _dir();
    if (dir == null) {
      return;
    }
    for (final day in _dirty.toList()) {
      try {
        // Merge with what an earlier run saved for the same day.
        await _load(day, dir);
        final byChannel = _days[day];
        if (byChannel == null) {
          continue;
        }
        final json = <String, Object?>{
          for (final entry in byChannel.entries)
            entry.key: <Object?>[
              for (final p in entry.value)
                <Object?>[
                  p.start.millisecondsSinceEpoch ~/ 1000,
                  p.stop.millisecondsSinceEpoch ~/ 1000,
                  p.title,
                  p.subTitle,
                  p.description,
                  p.episode,
                ],
            ],
        };
        final file = File('${dir.path}/$day.json');
        final temp = File('${dir.path}/$day.json.tmp');
        await temp.writeAsString(jsonEncode(json), flush: true);
        await temp.rename(file.path);
        _dirty.remove(day);
      } catch (error) {
        debugPrint('Guide history could not save $day: $error');
      }
    }
    _forget();
  }

  Future<void> _load(String day, Directory dir) async {
    if (_loaded.contains(day)) {
      return;
    }
    _loaded.add(day);
    final file = File('${dir.path}/$day.json');
    if (!await file.exists()) {
      return;
    }
    try {
      final decoded = jsonDecode(await file.readAsString());
      if (decoded is! Map) {
        return;
      }
      final byChannel =
          _days.putIfAbsent(day, () => <String, List<Programme>>{});
      for (final entry in decoded.entries) {
        final channelId = '${entry.key}';
        final rows = entry.value;
        if (rows is! List) {
          continue;
        }
        final list = byChannel.putIfAbsent(channelId, () => <Programme>[]);
        final known = <int>{
          for (final p in list) p.start.millisecondsSinceEpoch ~/ 1000,
        };
        for (final row in rows) {
          if (row is! List || row.length < 3) {
            continue;
          }
          final start = row[0];
          final stop = row[1];
          final title = row[2];
          if (start is! int || stop is! int || title is! String) {
            continue;
          }
          if (known.contains(start)) {
            continue;
          }
          list.add(
            Programme(
              channelId: channelId,
              start: DateTime.fromMillisecondsSinceEpoch(start * 1000),
              stop: DateTime.fromMillisecondsSinceEpoch(stop * 1000),
              title: title,
              subTitle: row.length > 3 && row[3] is String
                  ? row[3] as String
                  : null,
              description: row.length > 4 && row[4] is String
                  ? row[4] as String
                  : null,
              episode: row.length > 5 && row[5] is String
                  ? row[5] as String
                  : null,
            ),
          );
        }
      }
    } catch (error) {
      debugPrint('Guide history could not read $day: $error');
    }
  }

  /// Makes the days that cover [from] to [to] available to [forWindow].
  Future<void> prepare(DateTime from, DateTime to) async {
    final dir = await _dir();
    if (dir == null) {
      return;
    }
    final wanted = <String>{};
    var day = DateTime(from.year, from.month, from.day - 1);
    while (!day.isAfter(to)) {
      wanted.add(dayKey(day));
      day = DateTime(day.year, day.month, day.day + 1);
    }
    _wanted = wanted;
    for (final key in wanted) {
      await _load(key, dir);
    }
  }

  /// Drops days from memory that are saved and no longer being looked at.
  void _forget() {
    for (final day in _days.keys.toList()) {
      if (!_dirty.contains(day) && !_wanted.contains(day)) {
        _days.remove(day);
        _loaded.remove(day);
      }
    }
  }

  /// The remembered programmes of [channelId] that overlap the window. Call
  /// [prepare] for the window first.
  List<Programme> forWindow(String channelId, DateTime from, DateTime to) {
    final found = <Programme>[];
    for (final byChannel in _days.values) {
      final list = byChannel[channelId];
      if (list == null) {
        continue;
      }
      for (final programme in list) {
        if (programme.overlaps(from, to)) {
          found.add(programme);
        }
      }
    }
    found.sort((a, b) => a.start.compareTo(b.start));
    return found;
  }

  /// Deletes day files older than [daysBack] days.
  Future<void> prune(int daysBack) async {
    final dir = await _dir();
    if (dir == null) {
      return;
    }
    final now = DateTime.now();
    final oldest = dayKey(DateTime(now.year, now.month, now.day - daysBack));
    try {
      await for (final entity in dir.list()) {
        if (entity is! File) {
          continue;
        }
        final name = entity.uri.pathSegments.last;
        final match = RegExp(r'^(\d{8})\.json$').firstMatch(name);
        if (match != null && match.group(1)!.compareTo(oldest) < 0) {
          await entity.delete();
        }
      }
    } catch (error) {
      debugPrint('Guide history could not clean up: $error');
    }
  }

  /// Forgets everything saved for this source.
  Future<void> clear() async {
    _days.clear();
    _loaded.clear();
    _dirty.clear();
    _seen.clear();
    final dir = await _dir();
    if (dir == null) {
      return;
    }
    try {
      await for (final entity in dir.list()) {
        if (entity is File) {
          await entity.delete();
        }
      }
    } catch (error) {
      debugPrint('Guide history could not be cleared: $error');
    }
  }
}
