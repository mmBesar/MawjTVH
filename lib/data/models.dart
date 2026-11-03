import 'dart:math';

import '../core/catppuccin.dart';

/// A Tvheadend server the person has added: where it is, who they are on it,
/// and how its streams should be fetched.
class SourceConfig {
  const SourceConfig({
    required this.id,
    required this.name,
    required this.address,
    this.username = '',
    this.password = '',
    this.profile = '',
    this.allowInsecureCerts = false,
    this.useHtsp = false,
    this.htspPort = 9982,
    this.htspStream = true,
  });

  final String id;
  final String name;

  /// What the person typed: `10.0.0.5`, `tv.lan:9981`, `https://tv.example.com`
  /// or `https://example.com/tvh` (a web root). See `TvhAddress.parse`.
  final String address;
  final String username;
  final String password;

  /// Tvheadend stream profile (`pass`, `matroska`, a transcoder...). Empty
  /// means "pass", the unmodified stream.
  final String profile;
  final bool allowInsecureCerts;

  /// Talk to Tvheadend's native HTSP protocol for channels, guide and
  /// recordings (live updates, no polling). Streams still use HTTP.
  final bool useHtsp;
  final int htspPort;

  /// With HTSP on, also play live TV over HTSP (the app re-subscribes when
  /// the signal drops). Off plays the plain HTTP stream.
  final bool htspStream;

  SourceConfig copyWith({
    String? name,
    String? address,
    String? username,
    String? password,
    String? profile,
    bool? allowInsecureCerts,
    bool? useHtsp,
    int? htspPort,
    bool? htspStream,
  }) {
    return SourceConfig(
      id: id,
      name: name ?? this.name,
      address: address ?? this.address,
      username: username ?? this.username,
      password: password ?? this.password,
      profile: profile ?? this.profile,
      allowInsecureCerts: allowInsecureCerts ?? this.allowInsecureCerts,
      useHtsp: useHtsp ?? this.useHtsp,
      htspPort: htspPort ?? this.htspPort,
      htspStream: htspStream ?? this.htspStream,
    );
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
        'id': id,
        'name': name,
        'address': address,
        'username': username,
        'password': password,
        'profile': profile,
        'allowInsecureCerts': allowInsecureCerts,
        'useHtsp': useHtsp,
        'htspPort': htspPort,
        'htspStream': htspStream,
      };

  factory SourceConfig.fromJson(Map<String, dynamic> json) {
    final rawId = (json['id'] as String?)?.trim() ?? '';
    final rawName = (json['name'] as String?)?.trim() ?? '';
    return SourceConfig(
      id: rawId.isEmpty ? generateSourceId() : rawId,
      name: rawName.isEmpty ? 'Tvheadend' : rawName,
      address: (json['address'] as String?)?.trim() ?? '',
      username: json['username'] as String? ?? '',
      password: json['password'] as String? ?? '',
      profile: json['profile'] as String? ?? '',
      allowInsecureCerts: json['allowInsecureCerts'] as bool? ?? false,
      useHtsp: json['useHtsp'] as bool? ?? false,
      htspPort: (json['htspPort'] as num?)?.toInt() ?? 9982,
      htspStream: json['htspStream'] as bool? ?? true,
    );
  }
}

/// Which kind of channel Watch and Guide show.
enum MediaFilter { all, tv, radio }

class Channel {
  const Channel({
    required this.id,
    required this.sourceId,
    required this.name,
    required this.number,
    required this.url,
    this.tvgId = '',
    this.channelId = '',
    this.logoUrl,
    this.group,
    this.tags = const <String>[],
    this.isRadio = false,
  });

  /// Stable internal identity, unique per source (the Tvheadend channel uuid).
  final String id;
  final String sourceId;
  final String name;
  final String number;
  final String url;
  final String tvgId;
  final String channelId;
  final String? logoUrl;

  /// The first (lowest-indexed) channel tag, used as the channel's group.
  final String? group;

  /// Every channel tag name this channel belongs to.
  final List<String> tags;

  /// A radio station (audio only), by the server's service type or tag.
  final bool isRadio;

  String get displayNumber => number.isEmpty ? '—' : number;
}

class Programme {
  const Programme({
    required this.channelId,
    required this.start,
    required this.stop,
    required this.title,
    this.subTitle,
    this.description,
    this.categories = const <String>[],
    this.iconUrl,
    this.episode,
    this.eventId,
    this.dvrUuid,
    this.dvrState,
    this.facts,
    this.credits,
  });

  final String channelId;
  final DateTime start;
  final DateTime stop;
  final String title;
  final String? subTitle;
  final String? description;
  final List<String> categories;
  final String? iconUrl;
  final String? episode;

  /// Tvheadend's EPG event id, needed to schedule a recording.
  final int? eventId;

  /// Set when the server has this programme as a recording (any state).
  final String? dvrUuid;

  /// `scheduled`, `recording`, `completed`, `missed`... as the server says.
  final String? dvrState;

  /// One line of facts: year, categories, rating.
  final String? facts;

  /// One line of credits: directors, cast.
  final String? credits;

  /// Title with the episode label, e.g. `Foo · S01E05`, for lists.
  String get displayTitle =>
      episode == null || episode!.isEmpty ? title : '$title · $episode';

  bool get hasRecording => dvrUuid != null && dvrUuid!.isNotEmpty;

  bool isLiveAt(DateTime now) => !now.isBefore(start) && now.isBefore(stop);

  bool overlaps(DateTime windowStart, DateTime windowEnd) =>
      stop.isAfter(windowStart) && start.isBefore(windowEnd);

  double progressAt(DateTime now) {
    final total = stop.difference(start).inMilliseconds;
    if (total <= 0) {
      return 0;
    }
    return (now.difference(start).inMilliseconds / total).clamp(0.0, 1.0);
  }
}

/// A programme found by a guide search, with the channel that airs it.
class ProgrammeHit {
  const ProgrammeHit({required this.channel, required this.programme});

  final Channel channel;
  final Programme programme;
}

class Playlist {
  const Playlist({required this.channels});

  final List<Channel> channels;
}

class EpgData {
  EpgData._(this._byChannel, this.programmeCount);

  factory EpgData.empty() => EpgData._(const <String, List<Programme>>{}, 0);

  factory EpgData.fromMap(Map<String, List<Programme>> byChannel) {
    final frozen = <String, List<Programme>>{};
    var count = 0;
    for (final entry in byChannel.entries) {
      if (entry.value.isEmpty) {
        continue;
      }
      final programmes = List<Programme>.unmodifiable(entry.value);
      frozen[entry.key] = programmes;
      count += programmes.length;
    }
    return EpgData._(Map<String, List<Programme>>.unmodifiable(frozen), count);
  }

  final Map<String, List<Programme>> _byChannel;
  final int programmeCount;

  int get matchedChannels => _byChannel.length;
  bool get isEmpty => programmeCount == 0;

  /// Every programme of every channel, for searching the guide.
  Iterable<Programme> get all => _byChannel.values.expand((list) => list);

  List<Programme> programmesFor(Channel channel) =>
      _byChannel[channel.id] ?? const <Programme>[];

  Programme? nowFor(Channel channel, DateTime now) {
    for (final programme in programmesFor(channel)) {
      if (programme.isLiveAt(now)) {
        return programme;
      }
    }
    return null;
  }

  Programme? nextFor(Channel channel, DateTime now) {
    for (final programme in programmesFor(channel)) {
      if (programme.start.isAfter(now)) {
        return programme;
      }
    }
    return null;
  }

  List<Programme> forWindow(
    Channel channel,
    DateTime windowStart,
    DateTime windowEnd,
  ) {
    return programmesFor(channel)
        .where((programme) => programme.overlaps(windowStart, windowEnd))
        .toList(growable: false);
  }
}

enum LoadWarning {
  noEpgEndpoint,
  playlistFromCache,
  epgFromCache,
  epgUnavailable,
  epgEmpty,
}

enum AppLanguage { system, english, arabic }

extension AppLanguageX on AppLanguage {
  String? get localeCode => switch (this) {
        AppLanguage.system => null,
        AppLanguage.english => 'en',
        AppLanguage.arabic => 'ar',
      };
}

class AppSettings {
  const AppSettings({
    required this.themeFamily,
    required this.accent,
    required this.language,
    required this.use24HourTime,
    this.activeSourceId,
    this.useMpvWindow = false,
    this.hwdec = 'auto-safe',
    this.videoOutput = 'auto',
    this.useMpvConfig = true,
    this.startFullscreen = false,
    this.mpvPath = '',
    this.autoRefreshMinutes = 360,
    this.guideHours = 12,
    this.recordDir = '',
    this.richVisuals = true,
    this.reduceMotion = false,
    this.inAppRenderer = 'auto',
    this.lastGroup = '',
    this.preferredAudioLang = '',
    this.preferredSubtitleLang = 'off',
    this.rememberTracks = true,
    this.zapBanner = true,
  });

  factory AppSettings.defaults() => const AppSettings(
        themeFamily: ThemeFamily.studio,
        accent: ThemeAccent.peach,
        language: AppLanguage.system,
        use24HourTime: false,
      );

  final ThemeFamily themeFamily;
  final ThemeAccent accent;
  final AppLanguage language;
  final bool use24HourTime;
  final String? activeSourceId;

  /// Desktop only: play in a separate native mpv window (true) or inside
  /// the app with the built-in renderer (false).
  final bool useMpvWindow;

  /// mpv `--hwdec` value, picked from what the system reports.
  final String hwdec;

  /// mpv `--vo` value, or `auto` to leave mpv's default.
  final String videoOutput;

  /// Load the user's own `~/.config/mpv` configuration and scripts.
  final bool useMpvConfig;

  /// Open the mpv window fullscreen.
  final bool startFullscreen;

  /// Optional path to the mpv executable; empty means look in PATH.
  final String mpvPath;

  /// How often the playlist and guide reload by themselves; 0 turns it off.
  final int autoRefreshMinutes;

  /// How many hours the guide timeline spans (12 to 72).
  final int guideHours;

  /// Where "record to this device" saves; empty means the default folder.
  final String recordDir;

  /// Programme artwork on cards and other decorative visuals. Off keeps the
  /// plain gradient cards and loads fewer images.
  final bool richVisuals;

  /// Turns off decorative animation (the moving progress waves).
  final bool reduceMotion;

  /// Linux in-app video: `auto`, `gpu` or `cpu`.
  final String inAppRenderer;

  /// The channel group (tag) last chosen on Watch or Guide; empty means all.
  final String lastGroup;

  /// Language (ISO 639 code) picked by default for audio; empty keeps the
  /// stream's own default.
  final String preferredAudioLang;

  /// Language picked by default for subtitles; `off` keeps them disabled.
  final String preferredSubtitleLang;

  /// Reuse the audio and subtitle tracks last chosen on each channel.
  final bool rememberTracks;

  /// Desktop: show the channel banner when a channel opens.
  final bool zapBanner;

  AppSettings copyWith({
    ThemeFamily? themeFamily,
    ThemeAccent? accent,
    AppLanguage? language,
    bool? use24HourTime,
    Object? activeSourceId = _unset,
    bool? useMpvWindow,
    String? hwdec,
    String? videoOutput,
    bool? useMpvConfig,
    bool? startFullscreen,
    String? mpvPath,
    int? autoRefreshMinutes,
    int? guideHours,
    String? recordDir,
    bool? richVisuals,
    bool? reduceMotion,
    String? inAppRenderer,
    String? lastGroup,
    String? preferredAudioLang,
    String? preferredSubtitleLang,
    bool? rememberTracks,
    bool? zapBanner,
  }) {
    return AppSettings(
      themeFamily: themeFamily ?? this.themeFamily,
      accent: accent ?? this.accent,
      language: language ?? this.language,
      use24HourTime: use24HourTime ?? this.use24HourTime,
      activeSourceId: identical(activeSourceId, _unset)
          ? this.activeSourceId
          : activeSourceId as String?,
      useMpvWindow: useMpvWindow ?? this.useMpvWindow,
      hwdec: hwdec ?? this.hwdec,
      videoOutput: videoOutput ?? this.videoOutput,
      useMpvConfig: useMpvConfig ?? this.useMpvConfig,
      startFullscreen: startFullscreen ?? this.startFullscreen,
      mpvPath: mpvPath ?? this.mpvPath,
      autoRefreshMinutes: autoRefreshMinutes ?? this.autoRefreshMinutes,
      guideHours: guideHours ?? this.guideHours,
      recordDir: recordDir ?? this.recordDir,
      richVisuals: richVisuals ?? this.richVisuals,
      reduceMotion: reduceMotion ?? this.reduceMotion,
      inAppRenderer: inAppRenderer ?? this.inAppRenderer,
      lastGroup: lastGroup ?? this.lastGroup,
      preferredAudioLang: preferredAudioLang ?? this.preferredAudioLang,
      preferredSubtitleLang:
          preferredSubtitleLang ?? this.preferredSubtitleLang,
      rememberTracks: rememberTracks ?? this.rememberTracks,
      zapBanner: zapBanner ?? this.zapBanner,
    );
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
        'themeFamily': themeFamily.name,
        'accent': accent.name,
        'language': language.name,
        'use24HourTime': use24HourTime,
        'activeSourceId': activeSourceId,
        'useMpvWindow': useMpvWindow,
        'hwdec': hwdec,
        'videoOutput': videoOutput,
        'useMpvConfig': useMpvConfig,
        'startFullscreen': startFullscreen,
        'mpvPath': mpvPath,
        'autoRefreshMinutes': autoRefreshMinutes,
        'guideHours': guideHours,
        'recordDir': recordDir,
        'richVisuals': richVisuals,
        'reduceMotion': reduceMotion,
        'inAppRenderer': inAppRenderer,
        'lastGroup': lastGroup,
        'preferredAudioLang': preferredAudioLang,
        'preferredSubtitleLang': preferredSubtitleLang,
        'rememberTracks': rememberTracks,
        'zapBanner': zapBanner,
      };

  factory AppSettings.fromJson(Map<String, dynamic> json) {
    return AppSettings(
      themeFamily: _enumByName(
        ThemeFamily.values,
        json['themeFamily'] as String?,
        ThemeFamily.studio,
      ),
      accent: _enumByName(
        ThemeAccent.values,
        json['accent'] as String?,
        ThemeAccent.peach,
      ),
      language: _enumByName(
        AppLanguage.values,
        json['language'] as String?,
        AppLanguage.system,
      ),
      use24HourTime: json['use24HourTime'] as bool? ?? false,
      activeSourceId: json['activeSourceId'] as String?,
      useMpvWindow: json['useMpvWindow'] as bool? ?? false,
      hwdec: json['hwdec'] as String? ?? 'auto-safe',
      videoOutput: json['videoOutput'] as String? ?? 'auto',
      useMpvConfig: json['useMpvConfig'] as bool? ?? true,
      startFullscreen: json['startFullscreen'] as bool? ?? false,
      mpvPath: json['mpvPath'] as String? ?? '',
      autoRefreshMinutes: json['autoRefreshMinutes'] as int? ?? 360,
      guideHours: json['guideHours'] as int? ?? 12,
      recordDir: json['recordDir'] as String? ?? '',
      richVisuals: json['richVisuals'] as bool? ?? true,
      reduceMotion: json['reduceMotion'] as bool? ?? false,
      inAppRenderer: json['inAppRenderer'] as String? ?? 'auto',
      lastGroup: json['lastGroup'] as String? ?? '',
      preferredAudioLang: json['preferredAudioLang'] as String? ?? '',
      preferredSubtitleLang: json['preferredSubtitleLang'] as String? ?? 'off',
      rememberTracks: json['rememberTracks'] as bool? ?? true,
      zapBanner: json['zapBanner'] as bool? ?? true,
    );
  }
}

const Object _unset = Object();

T _enumByName<T extends Enum>(List<T> values, String? name, T fallback) {
  if (name == null) {
    return fallback;
  }
  for (final value in values) {
    if (value.name == name) {
      return value;
    }
  }
  return fallback;
}

String generateSourceId() {
  final random = Random.secure();
  final bytes = List<int>.generate(8, (_) => random.nextInt(256));
  final suffix = bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  return '${DateTime.now().millisecondsSinceEpoch.toRadixString(16)}$suffix';
}
