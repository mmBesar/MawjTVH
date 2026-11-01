import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import 'models.dart';

class StorageService {
  StorageService(this._prefs);

  static const String _settingsKey = 'mawjtvh.settings.v1';
  static const String _sourcesKey = 'mawjtvh.sources.v1';

  static const String _favoritesKey = 'mawjtvh.favorites.v1';
  static const String _recentsKey = 'mawjtvh.recents.v1';

  final SharedPreferences _prefs;

  static Future<StorageService> create() async {
    return StorageService(await SharedPreferences.getInstance());
  }

  AppSettings loadSettings() {
    final raw = _prefs.getString(_settingsKey);
    if (raw == null || raw.isEmpty) {
      return AppSettings.defaults();
    }
    try {
      final json = jsonDecode(raw);
      if (json is Map<String, dynamic>) {
        return AppSettings.fromJson(json);
      }
      if (json is Map) {
        return AppSettings.fromJson(json.cast<String, dynamic>());
      }
    } catch (_) {
      // Corrupt or outdated prefs should never prevent the app from starting.
    }
    return AppSettings.defaults();
  }

  Future<void> saveSettings(AppSettings settings) {
    return _prefs.setString(_settingsKey, jsonEncode(settings.toJson()));
  }

  List<SourceConfig> loadSources() {
    final raw = _prefs.getString(_sourcesKey);
    if (raw == null || raw.isEmpty) {
      return <SourceConfig>[];
    }
    try {
      final json = jsonDecode(raw);
      if (json is! List) {
        return <SourceConfig>[];
      }
      final sources = <SourceConfig>[];
      for (final item in json) {
        try {
          if (item is Map<String, dynamic>) {
            sources.add(SourceConfig.fromJson(item));
          } else if (item is Map) {
            sources.add(SourceConfig.fromJson(item.cast<String, dynamic>()));
          }
        } catch (_) {
          // Skip one malformed source instead of discarding all of them.
        }
      }
      return sources;
    } catch (_) {
      return <SourceConfig>[];
    }
  }

  Future<void> saveSources(List<SourceConfig> sources) {
    final encoded = jsonEncode(
      sources.map((source) => source.toJson()).toList(growable: false),
    );
    return _prefs.setString(_sourcesKey, encoded);
  }

  /// Favourite channel ids, in the order they were starred.
  List<String> loadFavorites(String sourceId) => _loadIdList(_favoritesKey, sourceId);

  Future<void> saveFavorites(String sourceId, List<String> ids) =>
      _saveIdList(_favoritesKey, sourceId, ids);

  /// Recently watched channel ids, newest first.
  List<String> loadRecents(String sourceId) => _loadIdList(_recentsKey, sourceId);

  Future<void> saveRecents(String sourceId, List<String> ids) =>
      _saveIdList(_recentsKey, sourceId, ids);

  List<String> _loadIdList(String key, String sourceId) {
    final raw = _prefs.getString(key);
    if (raw == null || raw.isEmpty) {
      return <String>[];
    }
    try {
      final json = jsonDecode(raw);
      if (json is Map) {
        final list = json[sourceId];
        if (list is List) {
          return list.whereType<String>().toList();
        }
      }
    } catch (_) {
      // A damaged list must not stop the app from starting.
    }
    return <String>[];
  }

  Future<void> _saveIdList(String key, String sourceId, List<String> ids) {
    Map<String, dynamic> all = <String, dynamic>{};
    final raw = _prefs.getString(key);
    if (raw != null && raw.isNotEmpty) {
      try {
        final json = jsonDecode(raw);
        if (json is Map) {
          all = json.cast<String, dynamic>();
        }
      } catch (_) {
        all = <String, dynamic>{};
      }
    }
    all[sourceId] = ids;
    return _prefs.setString(key, jsonEncode(all));
  }
}
