// The storage parameter cannot use an initializing formal because named
// parameters cannot be private.
// ignore_for_file: prefer_initializing_formals
import 'dart:async';

import 'package:flutter/foundation.dart';

import '../core/catppuccin.dart';
import '../core/text.dart';
import 'htsp_backend.dart';
import 'htsp_connection.dart';
import 'models.dart';
import 'storage.dart';
import 'tvh_client.dart';
import 'tvh_loader.dart';
import 'tvh_models.dart';

/// Prefix of the synthetic channel id used to play a recording in the player.
const String kRecordingIdPrefix = 'rec:';

/// True for the made-up channels that play a recording or a local file.
bool isSyntheticChannel(Channel channel) =>
    channel.id.startsWith(kRecordingIdPrefix);

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
  Map<String, String> _tracks = <String, String>{};
  Map<String, int> _resume = <String, int>{};
  Map<String, Channel> _channelById = const <String, Channel>{};
  List<String> _groups = const <String>[];
  String? _groupFilter;
  bool _groupRestored = false;

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

  /// The channel group (Tvheadend tag) chosen on Watch or Guide, shared by
  /// both so they always show the same slice. Null means every channel.
  String? get groupFilter {
    if (!_groupRestored && _groups.isNotEmpty) {
      // Back to the group used last time, once the groups are known.
      _groupRestored = true;
      final saved = _settings.lastGroup;
      if (saved.isNotEmpty && _groups.contains(saved)) {
        _groupFilter = saved;
      }
    }
    return _groups.contains(_groupFilter) ? _groupFilter : null;
  }

  void setGroupFilter(String? group) {
    _groupRestored = true;
    if (_groupFilter == group) {
      return;
    }
    _groupFilter = group;
    notifyListeners();
    final saved = group ?? '';
    if (_settings.lastGroup != saved) {
      _settings = _settings.copyWith(lastGroup: saved);
      unawaited(_storage.saveSettings(_settings));
    }
  }

  MediaFilter _media = MediaFilter.all;

  MediaFilter get mediaFilter => hasRadio ? _media : MediaFilter.all;

  /// True when the server has radio stations.
  bool get hasRadio => channels.any((channel) => channel.isRadio);

  void setMediaFilter(MediaFilter value) {
    if (_media == value) {
      return;
    }
    _media = value;
    notifyListeners();
  }

  /// The channels of the chosen group and kind (everything when none is
  /// chosen).
  List<Channel> get filteredChannels {
    final group = groupFilter;
    final media = mediaFilter;
    if (group == null && media == MediaFilter.all) {
      return channels;
    }
    return channels.where((channel) {
      if (group != null && channel.group != group) {
        return false;
      }
      return switch (media) {
        MediaFilter.all => true,
        MediaFilter.tv => !channel.isRadio,
        MediaFilter.radio => channel.isRadio,
      };
    }).toList(growable: false);
  }

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
      // Keep the "recording now" dots honest without hammering the server.
      if (++_tick % 2 == 0 && _content != null) {
        unawaited(loadRecordings(quiet: true));
      }
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
      _detachHtsp();
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
        unawaited(content.htsp?.close());
        return;
      }
      _detachHtsp();
      _content = content;
      _attachHtsp(content.htsp);
      _indexChannels(content.playlist.channels);
      _warnings = content.warnings;
      _lastErrorMessage = null;
      _error = null;
      _now = DateTime.now();
      unawaited(loadRecordings(quiet: true));
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
    _tracks = id == null ? <String, String>{} : _storage.loadTracks(id);
    _resume = id == null ? <String, int>{} : _storage.loadResume(id);
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

  // ---- HTSP session --------------------------------------------------------

  HtspBackend? _htspSession;
  StreamSubscription<void>? _htspChanges;
  Timer? _htspRetry;
  int _htspFailures = 0;

  HtspBackend? get _htsp => _htspSession;

  /// Speed figures of the recording being played, for the problem report.
  String? get recordingStats => _htspSession?.recordingStats;

  final Map<String, String> _streamIssues = <String, String>{};

  /// Why the server cannot deliver [channel] right now (tuner busy, weak
  /// signal...), or null when nothing is wrong.
  String? streamIssueFor(Channel channel) => _streamIssues[channel.id];

  /// Frees the tuner when the player leaves [channel].
  void releaseStream(Channel channel) {
    _htspSession?.releaseStream(channel.id);
    _streamIssues.remove(channel.id);
  }

  /// Returns [channel] with a stream address that works right now. When the
  /// HTSP session has dropped, it reconnects first: the stream address belongs
  /// to the session, so the old one no longer answers.
  Future<Channel> prepareStream(Channel channel) async {
    final session = _htspSession;
    if (session != null && session.isClosed && !_disposed) {
      _htspRetry?.cancel();
      _htspRetry = null;
      await load();
    }
    if (channel.id.startsWith('${kRecordingIdPrefix}local:')) {
      return channel;
    }
    if (channel.id.startsWith(kRecordingIdPrefix)) {
      // A recording served over HTSP: its address belongs to the session too.
      final session = _htspSession;
      if (session != null && !session.isClosed) {
        return Channel(
          id: channel.id,
          sourceId: channel.sourceId,
          name: channel.name,
          number: channel.number,
          url: session.recordingUrl(channel.id.substring(kRecordingIdPrefix.length)),
          group: channel.group,
        );
      }
      return channel;
    }
    return _channelById[channel.id] ?? channel;
  }

  /// Network, mux and so on for the channel being watched (HTSP only).
  Map<String, String>? sourceInfoFor(Channel channel) =>
      _htspSession?.sourceInfoFor(channel.id);

  /// True while the native HTSP session is connected.
  bool get usesHtsp => _htspSession != null && !_htspSession!.isClosed;

  void _attachHtsp(HtspBackend? backend) {
    _htspSession = backend;
    if (backend == null) {
      return;
    }
    _htspFailures = 0;
    backend.streamStatusListener = (channelId, issue) {
      if (issue == null) {
        if (_streamIssues.remove(channelId) == null) {
          return;
        }
      } else if (_streamIssues[channelId] == issue) {
        return;
      } else {
        _streamIssues[channelId] = issue;
      }
      notifyListeners();
    };
    _htspChanges = backend.changes.listen((_) => _applyHtspChange(backend));
    unawaited(
      backend.closed.then((_) {
        if (!identical(_htspSession, backend) || _disposed) {
          return;
        }
        // Connection lost: reload (and so reconnect) with a growing delay.
        _htspFailures += 1;
        final seconds = (_htspFailures * 5).clamp(5, 60).toInt();
        _htspRetry?.cancel();
        _htspRetry = Timer(Duration(seconds: seconds), () {
          if (!_disposed && identical(_htspSession, backend)) {
            unawaited(load());
          }
        });
        notifyListeners();
      }),
    );
  }

  void _detachHtsp() {
    _htspRetry?.cancel();
    _htspRetry = null;
    unawaited(_htspChanges?.cancel());
    _htspChanges = null;
    final session = _htspSession;
    _htspSession = null;
    if (session != null) {
      unawaited(session.close());
    }
  }

  void _applyHtspChange(HtspBackend backend) {
    final current = _content;
    if (current == null || !identical(_htspSession, backend)) {
      return;
    }
    final channels = backend.channels();
    if (channels.isNotEmpty) {
      _content = current.copyWith(
        playlist: Playlist(channels: channels),
        epg: backend.guide(),
      );
      _indexChannels(channels);
    }
    _recordings = backend.recordings();
    _recordingsError = null;
    notifyListeners();
  }

  bool _disposed = false;

  DateTime? _lastAutoRefresh;

  /// Reloads the playlist and guide once the chosen interval has passed, and
  /// never more often than every five minutes, even when loading fails.
  void _maybeAutoRefresh() {
    final minutes = _settings.autoRefreshMinutes;
    if (minutes <= 0 || _loading || activeSource == null) {
      return;
    }
    final htsp = _htsp;
    if (htsp != null && !htsp.isClosed) {
      // The server pushes changes; there is nothing to poll.
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
    // A recording played through the player is not a channel to come back to.
    if (isSyntheticChannel(channel)) {
      return;
    }
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
    _detachHtsp();
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

  Future<void> setRichVisuals(bool value) =>
      updateSettings(_settings.copyWith(richVisuals: value));

  Future<void> setPreferredAudioLang(String value) =>
      updateSettings(_settings.copyWith(preferredAudioLang: value));

  Future<void> setPreferredSubtitleLang(String value) =>
      updateSettings(_settings.copyWith(preferredSubtitleLang: value));

  Future<void> setRememberTracks(bool value) =>
      updateSettings(_settings.copyWith(rememberTracks: value));

  Future<void> setOsdSeconds(int value) =>
      updateSettings(_settings.copyWith(osdSeconds: value));

  Future<void> setUiScale(double value) =>
      updateSettings(_settings.copyWith(uiScale: value));

  Future<void> setChannelView(String value) =>
      updateSettings(_settings.copyWith(channelView: value));

  Future<void> setGuideScale(double value) =>
      updateSettings(_settings.copyWith(guideScale: value));

  Future<void> setPipOnLeave(bool value) =>
      updateSettings(_settings.copyWith(pipOnLeave: value));

  Future<void> setZapBanner(bool value) =>
      updateSettings(_settings.copyWith(zapBanner: value));

  /// The audio (or subtitle) choice last made on [channel], as a track key.
  String? rememberedTrack(Channel channel, {required bool audio}) =>
      _tracks['${channel.id}.${audio ? 'a' : 's'}'];

  // ---- Resume ---------------------------------------------------------------

  /// Key of a recording in the local resume map.
  static String _resumeKeyOf(Channel channel) =>
      channel.id.substring(kRecordingIdPrefix.length);

  /// Where to offer to continue [channel] (a recording), or null.
  Duration? resumeFor(Channel channel) {
    if (!isSyntheticChannel(channel)) {
      return null;
    }
    final key = _resumeKeyOf(channel);
    var seconds = 0;
    for (final recording in _recordings) {
      if (recording.uuid == key) {
        seconds = recording.playPosition;
        break;
      }
    }
    if (seconds <= 0) {
      seconds = _resume[key] ?? 0;
    }
    return seconds > 0 ? Duration(seconds: seconds) : null;
  }

  /// Remembers where playback of [channel] stopped. Near the start nothing
  /// changes (so an unaccepted offer survives); near the end the recording
  /// counts as watched and the position is cleared.
  void savePosition(Channel channel, Duration position, Duration total) {
    if (!isSyntheticChannel(channel) || position < const Duration(seconds: 30)) {
      return;
    }
    var seconds = position.inSeconds;
    if (total > Duration.zero &&
        (total - position < const Duration(seconds: 60) ||
            position.inSeconds >= total.inSeconds * 0.95)) {
      seconds = 0;
    }
    final key = _resumeKeyOf(channel);
    final htsp = _htsp;
    if (htsp != null &&
        !htsp.isClosed &&
        !key.startsWith('local:') &&
        _recordings.any((recording) => recording.uuid == key)) {
      unawaited(() async {
        try {
          await htsp.setPlayPosition(key, seconds);
          _recordings = htsp.recordings();
          notifyListeners();
        } catch (error) {
          debugPrint('Could not save the play position: $error');
        }
      }());
      return;
    }
    if (seconds == 0) {
      _resume.remove(key);
    } else {
      _resume[key] = seconds;
      if (_resume.length > 400) {
        _resume.remove(_resume.keys.first);
      }
    }
    unawaited(_storage.saveResume(channel.sourceId, _resume));
  }

  void rememberTrack(Channel channel, {required bool audio, required String key}) {
    if (isSyntheticChannel(channel)) {
      return;
    }
    final name = '${channel.id}.${audio ? 'a' : 's'}';
    if (_tracks[name] == key) {
      return;
    }
    _tracks[name] = key;
    if (_tracks.length > 800) {
      _tracks.remove(_tracks.keys.first);
    }
    unawaited(_storage.saveTracks(channel.sourceId, _tracks));
  }

  Future<void> setReduceMotion(bool value) =>
      updateSettings(_settings.copyWith(reduceMotion: value));

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

  Channel? channelById(String id) => _channelById[id];

  /// Channels the server is recording right now.
  Set<String> get recordingChannelIds => <String>{
        for (final recording in _recordings)
          if (recording.isRecording && recording.channelUuid.isNotEmpty)
            recording.channelUuid,
      };

  /// The server recording that is running on [channel] right now, if any.
  TvhRecording? activeRecordingFor(Channel channel) {
    for (final recording in _recordings) {
      if (recording.isRecording && recording.channelUuid == channel.id) {
        return recording;
      }
    }
    return null;
  }

  bool isRecordingChannel(Channel channel) =>
      _recordings.any(
        (recording) =>
            recording.isRecording && recording.channelUuid == channel.id,
      );

  int _tick = 0;

  /// [quiet] is for background polling: no spinner and no error banner.
  Future<void> loadRecordings({bool quiet = false}) async {
    if (activeSource == null || _recordingsLoading) {
      return;
    }
    final htsp = _htsp;
    if (htsp != null && !htsp.isClosed) {
      _recordings = htsp.recordings();
      _recordingsError = null;
      notifyListeners();
      return;
    }
    _recordingsLoading = true;
    if (!quiet) {
      _recordingsError = null;
    }
    notifyListeners();
    try {
      final all = await withClient((client) async {
        final upcoming = await client.recordings(RecordingKind.upcoming);
        final finished = await client.recordings(RecordingKind.finished);
        final failed = await client.recordings(RecordingKind.failed);
        return <TvhRecording>[...upcoming, ...finished, ...failed];
      });
      _recordings = all;
      _recordingsError = null;
    } catch (error) {
      if (!quiet) {
        _recordingsError = _messageFor(error);
      }
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
    final htsp = _htsp;
    if (htsp != null && !htsp.isClosed) {
      await _htspAction(
        () => series ? htsp.recordSeries(programme) : htsp.recordEvent(id),
      );
      return;
    }
    await withClient((client) {
      return series ? client.recordSeries(id) : client.recordEvent(id);
    });
    await _afterRecordingChange();
  }

  Future<void> recordChannelNow(Channel channel, int minutes) async {
    final title = epg.nowFor(channel, DateTime.now())?.title ?? channel.name;
    final htsp = _htsp;
    if (htsp != null && !htsp.isClosed) {
      await _htspAction(() => htsp.recordNow(channel.id, title, minutes));
      return;
    }
    await withClient((client) => client.recordNow(channel.id, title, minutes));
    await _afterRecordingChange();
  }

  Future<void> stopRecording(TvhRecording recording) async {
    final htsp = _htsp;
    if (htsp != null && !htsp.isClosed) {
      await _htspAction(() => htsp.stopRecording(recording.uuid));
      return;
    }
    await withClient((client) => client.stopRecording(recording.uuid));
    await _afterRecordingChange();
  }

  Future<void> cancelRecording(TvhRecording recording) async {
    final htsp = _htsp;
    if (htsp != null && !htsp.isClosed) {
      await _htspAction(() => htsp.cancelRecording(recording.uuid));
      return;
    }
    await withClient((client) => client.cancelRecording(recording.uuid));
    await _afterRecordingChange();
  }

  Future<void> removeRecording(TvhRecording recording) async {
    final htsp = _htsp;
    if (htsp != null && !htsp.isClosed) {
      await _htspAction(() => htsp.removeRecording(recording.uuid));
      return;
    }
    await withClient((client) => client.removeRecording(recording.uuid));
    await _afterRecordingChange();
  }

  /// Runs an HTSP action; the server's push updates the lists afterwards.
  Future<void> _htspAction(Future<void> Function() action) async {
    try {
      await action();
    } on HtspException catch (error) {
      throw TvhException(error.message);
    }
  }

  Future<void> _afterRecordingChange() async {
    unawaited(loadRecordings());
    unawaited(_refreshGuideQuietly());
  }

  Future<void> _refreshGuideQuietly() async {
    final source = liveSource;
    final current = _content;
    if (source == null || current == null || usesHtsp) {
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
      _content = current.copyWith(epg: guide);
      notifyListeners();
    } catch (error) {
      debugPrint('Quiet guide refresh failed: $error');
    }
  }

  /// Signal of the stream being watched. Needs an administrator account on
  /// the server; for anyone else this is `null`.
  Future<TvhSignal?> signalFor(Channel channel) async {
    final htsp = _htsp;
    if (htsp != null && !htsp.isClosed) {
      return htsp.signalFor(channel.id);
    }
    if (!isAdmin) {
      return null;
    }
    try {
      return await withClient((client) => client.signalFor(channel.name));
    } catch (_) {
      return null;
    }
  }

  /// A synthetic channel that plays [recording] in the normal player.
  Channel? recordingAsChannel(TvhRecording recording) {
    final url = recordingUrl(recording);
    final source = liveSource;
    if (url == null || source == null) {
      return null;
    }
    return Channel(
      id: '$kRecordingIdPrefix${recording.uuid}',
      sourceId: source.id,
      name: recording.title,
      number: '',
      url: url,
      group: recordingsGroup,
    );
  }

  static const String recordingsGroup = 'Recordings';

  /// Address of a finished recording's file, with the login in the URL.
  String? recordingUrl(TvhRecording recording) {
    final source = liveSource;
    if (source == null || !recording.hasFile) {
      return null;
    }
    final session = _htspSession;
    if (session != null && !session.isClosed) {
      return session.recordingUrl(recording.uuid);
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
    _disposed = true;
    _loadGeneration++;
    _ticker?.cancel();
    _detachHtsp();
    super.dispose();
  }
}
