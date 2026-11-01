// The storage parameter cannot use an initializing formal because named
// parameters cannot be private.
// ignore_for_file: prefer_initializing_formals
import 'dart:async';

import 'package:flutter/foundation.dart';

import '../core/catppuccin.dart';
import '../core/text.dart';
import 'models.dart';
import 'storage.dart';
import 'tvh_client.dart';
import 'tvh_loader.dart';
import 'tvh_models.dart';

/// Central application state: persisted sources and settings, the currently
/// loaded channel/EPG snapshot, and a lightweight ticker so "now playing"
/// information stays current without reopening the guide.
class AppState extends ChangeNotifier {
  AppState({
    required StorageService storage,
    TvhLoader? loader,
  })  : _storage = storage,
        _loader = loader ?? TvhLoader();

  static Future<AppState> create({TvhLoader? loader}) async {
    final storage = await StorageService.create();
    final state = AppState(storage: storage, loader: loader);
    state._restore();
    return state;
  }

  final StorageService _storage;
  final TvhLoader _loader;
  Timer? _ticker;
  int _loadGeneration = 0;

  late AppSettings _settings;
  List<SourceConfig> _sources = <SourceConfig>[];
  SourceContent? _content;
  String? _error;
  Set<LoadWarning> _warnings = <LoadWarning>{};
  DateTime _now = DateTime.now();
  bool _loading = false;
  bool _restored = false;
  bool _initialLoadStarted = false;
  List<String> _favorites = <String>[];
  List<String> _recents = <String>[];
  Map<String, Channel> _channelById = const <String, Channel>{};
  List<String> _groups = const <String>[];

  AppSettings get settings => _settings;
  List<SourceConfig> get sources => List<SourceConfig>.unmodifiable(_sources);
  List<Channel> get channels =>
      _content?.playlist.channels ?? const <Channel>[];
  EpgData get epg => _content?.epg ?? EpgData.empty();
  SourceContent? get content => _content;
  DateTime get now => _now;
  bool get isLoading => _loading;
  bool get restored => _restored;
  bool get hasContent => _content != null;
  String? get error => _error;
  Set<LoadWarning> get warnings => Set<LoadWarning>.unmodifiable(_warnings);
  DateTime? get lastLoaded => _content?.loadedAt;

  /// Distinct group names in playlist order.
  List<String> get groups => _groups;

  List<Channel> get favorites => <Channel>[
        for (final id in _favorites)
          if (_channelById[id] != null) _channelById[id]!,
      ];

  /// Recently watched channels that still exist, newest first.
  List<Channel> get recents => <Channel>[
        for (final id in _recents)
          if (_channelById[id] != null) _channelById[id]!,
      ];

  bool isFavorite(Channel channel) => _favorites.contains(channel.id);

  SourceConfig? get activeSource {
    final id = _settings.activeSourceId;
    if (id == null) {
      return _sources.isEmpty ? null : _sources.first;
    }
    for (final source in _sources) {
      if (source.id == id) {
        return source;
      }
    }
    return _sources.isEmpty ? null : _sources.first;
  }

  void _restore() {
    _settings = _storage.loadSettings();
    _sources = _storage.loadSources();

    if (_sources.isEmpty) {
      _settings = _settings.copyWith(activeSourceId: null);
    } else if (activeSource == null) {
      _settings = _settings.copyWith(activeSourceId: _sources.first.id);
    } else if (_settings.activeSourceId != activeSource!.id) {
      _settings = _settings.copyWith(activeSourceId: activeSource!.id);
    }

    _loadUserLists();
    _restored = true;
    _ticker = Timer.periodic(const Duration(seconds: 30), (_) {
      _now = DateTime.now();
      notifyListeners();
      _maybeAutoRefresh();
    });
    notifyListeners();

    if (activeSource != null && !_initialLoadStarted) {
      _initialLoadStarted = true;
      unawaited(load());
    }
  }

  Future<void> load() async {
    final source = activeSource;
    if (source == null) {
      _content = null;
      _recordings = const <TvhRecording>[];
      _warnings = <LoadWarning>{};
      _error = null;
      _loading = false;
      notifyListeners();
      return;
    }

    final generation = ++_loadGeneration;
    _loading = true;
    _error = null;
    notifyListeners();

    try {
      final content = await _loader.load(
        source,
        guideHours: _settings.guideHours,
      );
      if (generation != _loadGeneration) {
        return;
      }
      _content = content;
      _indexChannels(content.playlist.channels);
      _warnings = content.warnings;
      _lastErrorMessage = null;
      _error = null;
      _now = DateTime.now();
    } catch (error) {
      if (generation != _loadGeneration) {
        return;
      }
      _lastErrorMessage = _messageFor(error);
      _error = _lastErrorMessage;
      if (_content == null || _content!.playlist.channels.isEmpty) {
        _warnings = <LoadWarning>{};
      }
    } finally {
      if (generation == _loadGeneration) {
        _loading = false;
        notifyListeners();
      }
    }
  }

  String? _lastErrorMessage;

  /// Returns the last error; kept separately from [error] so the UI can show
  /// it in a retry banner while continuing to display cached channels.
  String? get lastErrorMessage => _lastErrorMessage;

  Future<void> refresh() => load();

  void _loadUserLists() {
    final id = activeSource?.id;
    _favorites = id == null ? <String>[] : _storage.loadFavorites(id);
    _recents = id == null ? <String>[] : _storage.loadRecents(id);
  }

  void _indexChannels(List<Channel> channels) {
    _channelById = <String, Channel>{
      for (final channel in channels) channel.id: channel,
    };
    final seen = <String>{};
    _groups = <String>[
      for (final channel in channels)
        if (channel.group != null && seen.add(channel.group!)) channel.group!,
    ];
  }

  DateTime? _lastAutoRefresh;

  /// Reloads the playlist and guide once the chosen interval has passed, and
  /// never more often than every five minutes, even when loading fails.
  void _maybeAutoRefresh() {
    final minutes = _settings.autoRefreshMinutes;
    if (minutes <= 0 || _loading || activeSource == null) {
      return;
    }
    final last = lastLoaded;
    if (last == null || _now.difference(last) < Duration(minutes: minutes)) {
      return;
    }
    final attempt = _lastAutoRefresh;
    if (attempt != null &&
        _now.difference(attempt) < const Duration(minutes: 5)) {
      return;
    }
    _lastAutoRefresh = _now;
    unawaited(refresh());
  }

  Future<void> toggleFavorite(Channel channel) async {
    final sourceId = channel.sourceId;
    final next = <String>[..._favorites];
    if (!next.remove(channel.id)) {
      next.add(channel.id);
    }
    _favorites = next;
    notifyListeners();
    await _storage.saveFavorites(sourceId, next);
  }

  /// Remembers [channel] as the most recently watched one.
  Future<void> markWatched(Channel channel) async {
    final next = <String>[
      channel.id,
      ..._recents.where((id) => id != channel.id),
    ].take(12).toList(growable: false);
    _recents = next;
    notifyListeners();
    await _storage.saveRecents(channel.sourceId, next);
  }

  /// Channels whose name, number or group contains [query].
  List<Channel> searchChannels(String query) {
    final needle = normalizeForSearch(query);
    if (needle.isEmpty) {
      return const <Channel>[];
    }
    return channels.where((channel) {
      return normalizeForSearch(channel.name).contains(needle) ||
          channel.number == needle ||
          normalizeForSearch(channel.group ?? '').contains(needle);
    }).toList(growable: false);
  }

  /// Programmes still on or yet to start whose title, sub-title or category
  /// contains [query], soonest first.
  List<ProgrammeHit> searchProgrammes(String query, {int limit = 60}) {
    final needle = normalizeForSearch(query);
    if (needle.length < 2) {
      return const <ProgrammeHit>[];
    }
    final hits = <ProgrammeHit>[];
    for (final programme in epg.all) {
      if (!programme.stop.isAfter(_now)) {
        continue;
      }
      final channel = _channelById[programme.channelId];
      if (channel == null) {
        continue;
      }
      final haystack = normalizeForSearch(
        '${programme.title} ${programme.subTitle ?? ''} '
        '${programme.categories.join(' ')}',
      );
      if (haystack.contains(needle)) {
        hits.add(ProgrammeHit(channel: channel, programme: programme));
      }
    }
    hits.sort((a, b) => a.programme.start.compareTo(b.programme.start));
    return hits.length > limit ? hits.sublist(0, limit) : hits;
  }

  Future<void> selectSource(String sourceId) async {
    final exists = _sources.any((source) => source.id == sourceId);
    if (!exists) {
      return;
    }
    _settings = _settings.copyWith(activeSourceId: sourceId);
    _content = null;
    _recordings = const <TvhRecording>[];
    _warnings = <LoadWarning>{};
    _error = null;
    _loadUserLists();
    _indexChannels(const <Channel>[]);
    notifyListeners();
    unawaited(_storage.saveSettings(_settings));
    unawaited(load());
  }

  Future<void> addSource(SourceConfig source) async {
    _sources = <SourceConfig>[..._sources, source];
    _settings = _settings.copyWith(activeSourceId: source.id);
    await _storage.saveSources(_sources);
    await _storage.saveSettings(_settings);
    _content = null;
    _recordings = const <TvhRecording>[];
    _loadUserLists();
    _indexChannels(const <Channel>[]);
    notifyListeners();
    unawaited(load());
  }

  Future<void> updateSource(SourceConfig source) async {
    final index = _sources.indexWhere((item) => item.id == source.id);
    if (index < 0) {
      return;
    }
    final updated = <SourceConfig>[..._sources];
    updated[index] = source;
    _sources = updated;
    await _storage.saveSources(_sources);
    notifyListeners();
    if (activeSource?.id == source.id) {
      unawaited(load());
    }
  }

  Future<void> deleteSource(String sourceId) async {
    // Work this out before replacing the list: after that, [activeSource] would
    // already have fallen back to a different source.
    final wasActive = activeSource?.id == sourceId;
    final remaining =
        _sources.where((source) => source.id != sourceId).toList(growable: false);
    _sources = remaining;
    if (wasActive) {
      _settings = _settings.copyWith(
        activeSourceId: remaining.isEmpty ? null : remaining.first.id,
      );
      _content = null;
      _recordings = const <TvhRecording>[];
      _warnings = <LoadWarning>{};
      _error = null;
      _loadUserLists();
      _indexChannels(const <Channel>[]);
    }
    await _storage.saveSources(_sources);
    await _storage.saveSettings(_settings);
    notifyListeners();
    if (wasActive && remaining.isNotEmpty) {
      unawaited(load());
    }
  }

  Future<void> updateSettings(AppSettings settings) async {
    // Show the change first: the UI must not wait for the disk.
    _settings = settings;
    notifyListeners();
    try {
      await _storage.saveSettings(_settings);
    } catch (error) {
      debugPrint('Could not save settings: $error');
    }
  }

  Future<void> setThemeFamily(ThemeFamily family) {
    return updateSettings(_settings.copyWith(themeFamily: family));
  }

  Future<void> setAccent(ThemeAccent accent) {
    return updateSettings(_settings.copyWith(accent: accent));
  }

  Future<void> setLanguage(AppLanguage language) {
    return updateSettings(_settings.copyWith(language: language));
  }

  Future<void> setUse24HourTime(bool value) {
    return updateSettings(_settings.copyWith(use24HourTime: value));
  }

  Future<SourceContent> probe(SourceConfig source) => _loader.probe(source);

  // ---- Tvheadend specifics -------------------------------------------------

  /// What the server lets this account do, learned while loading.
  TvhPermissions get permissions =>
      _content?.permissions ?? const TvhPermissions(admin: false);

  bool get isAdmin => permissions.admin;
  TvhServerInfo get serverInfo => _content?.serverInfo ?? const TvhServerInfo();

  /// Stream profile names the account may use.
  List<String> get streamProfiles => _content?.profiles ?? const <String>[];

  /// The source as the server really answers (address moved to https...).
  SourceConfig? get liveSource => _content?.resolvedSource ?? activeSource;

  /// Runs [action] with a short-lived client for the active server.
  Future<T> withClient<T>(Future<T> Function(TvhClient client) action) async {
    final source = liveSource;
    if (source == null) {
      throw const TvhException('No server is selected.');
    }
    final client = TvhClient(source);
    try {
      return await action(client);
    } finally {
      client.close();
    }
  }

  List<TvhRecording> _recordings = const <TvhRecording>[];
  String? _recordingsError;
  bool _recordingsLoading = false;

  List<TvhRecording> get recordings => _recordings;
  String? get recordingsError => _recordingsError;
  bool get recordingsLoading => _recordingsLoading;

  Future<void> loadRecordings() async {
    if (activeSource == null || _recordingsLoading) {
      return;
    }
    _recordingsLoading = true;
    _recordingsError = null;
    notifyListeners();
    try {
      final all = await withClient((client) async {
        final upcoming = await client.recordings(RecordingKind.upcoming);
        final finished = await client.recordings(RecordingKind.finished);
        final failed = await client.recordings(RecordingKind.failed);
        return <TvhRecording>[...upcoming, ...finished, ...failed];
      });
      _recordings = all;
    } catch (error) {
      _recordingsError = _messageFor(error);
    } finally {
      _recordingsLoading = false;
      notifyListeners();
    }
  }

  /// Recording state of a programme, as the server last reported it.
  Future<void> recordProgramme(Programme programme, {bool series = false}) async {
    final id = programme.eventId;
    if (id == null) {
      throw const TvhException('This programme cannot be recorded.');
    }
    await withClient((client) {
      return series ? client.recordSeries(id) : client.recordEvent(id);
    });
    await _afterRecordingChange();
  }

  Future<void> recordChannelNow(Channel channel, int minutes) async {
    final title = epg.nowFor(channel, DateTime.now())?.title ?? channel.name;
    await withClient((client) => client.recordNow(channel.id, title, minutes));
    await _afterRecordingChange();
  }

  Future<void> stopRecording(TvhRecording recording) async {
    await withClient((client) => client.stopRecording(recording.uuid));
    await _afterRecordingChange();
  }

  Future<void> cancelRecording(TvhRecording recording) async {
    await withClient((client) => client.cancelRecording(recording.uuid));
    await _afterRecordingChange();
  }

  Future<void> removeRecording(TvhRecording recording) async {
    await withClient((client) => client.removeRecording(recording.uuid));
    await _afterRecordingChange();
  }

  Future<void> _afterRecordingChange() async {
    unawaited(loadRecordings());
    unawaited(_refreshGuideQuietly());
  }

  Future<void> _refreshGuideQuietly() async {
    final source = liveSource;
    final current = _content;
    if (source == null || current == null) {
      return;
    }
    try {
      final guide = await _loader.loadGuide(
        source,
        current.playlist.channels,
        guideHours: _settings.guideHours,
      );
      if (_content != current) {
        return;
      }
      _content = SourceContent(
        playlist: current.playlist,
        epg: guide,
        warnings: current.warnings,
        loadedAt: current.loadedAt,
        resolvedSource: current.resolvedSource,
        permissions: current.permissions,
        serverInfo: current.serverInfo,
        profiles: current.profiles,
      );
      notifyListeners();
    } catch (error) {
      debugPrint('Quiet guide refresh failed: $error');
    }
  }

  /// Signal of the stream being watched. Needs an administrator account on
  /// the server; for anyone else this is `null`.
  Future<TvhSignal?> signalFor(Channel channel) async {
    if (!isAdmin) {
      return null;
    }
    try {
      return await withClient((client) => client.signalFor(channel.name));
    } catch (_) {
      return null;
    }
  }

  /// Address of a finished recording's file, with the login in the URL.
  String? recordingUrl(TvhRecording recording) {
    final source = liveSource;
    if (source == null || !recording.hasFile) {
      return null;
    }
    final client = TvhClient(source);
    try {
      return client.recordingUrl(recording.uuid);
    } finally {
      client.close();
    }
  }

  String _messageFor(Object error) {
    if (error is SourceLoadException) {
      return error.message;
    }
    if (error is TvhException) {
      return error.message;
    }
    return error.toString();
  }

  @override
  void dispose() {
    _loadGeneration++;
    _ticker?.cancel();
    super.dispose();
  }
}
