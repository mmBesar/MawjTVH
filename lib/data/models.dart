import 'dart:math';

import '../core/catppuccin.dart';

/// A user-configured playlist/EPG pair. Every source keeps its own M3U and
/// XMLTV location, and its own TLS policy.
enum EndpointKind { url, file }

class SourceEndpoint {
  const SourceEndpoint({required this.value, this.kind = EndpointKind.url});

  final String value;
  final EndpointKind kind;

  bool get isFile => kind == EndpointKind.file;
  bool get isEmpty => value.trim().isEmpty;

  SourceEndpoint copyWith({String? value, EndpointKind? kind}) {
    return SourceEndpoint(
      value: value ?? this.value,
      kind: kind ?? this.kind,
    );
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
        'value': value,
        'kind': kind.name,
      };

  factory SourceEndpoint.fromJson(dynamic json) {
    if (json is String) {
      return SourceEndpoint(value: json);
    }
    if (json is Map) {
      final map = json.cast<String, dynamic>();
      final kindName = map['kind'] as String? ?? 'url';
      return SourceEndpoint(
        value: map['value'] as String? ?? '',
        kind: EndpointKind.values.firstWhere(
          (value) => value.name == kindName,
          orElse: () => EndpointKind.url,
        ),
      );
    }
    return const SourceEndpoint(value: '');
  }
}

class SourceConfig {
  const SourceConfig({
    required this.id,
    required this.name,
    required this.m3u,
    required this.epg,
    this.allowInsecureCerts = false,
  });

  final String id;
  final String name;
  final SourceEndpoint m3u;
  final SourceEndpoint epg;
  final bool allowInsecureCerts;

  SourceConfig copyWith({
    String? name,
    SourceEndpoint? m3u,
    SourceEndpoint? epg,
    bool? allowInsecureCerts,
  }) {
    return SourceConfig(
      id: id,
      name: name ?? this.name,
      m3u: m3u ?? this.m3u,
      epg: epg ?? this.epg,
      allowInsecureCerts: allowInsecureCerts ?? this.allowInsecureCerts,
    );
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
        'id': id,
        'name': name,
        'm3u': m3u.toJson(),
        'epg': epg.toJson(),
        'allowInsecureCerts': allowInsecureCerts,
      };

  factory SourceConfig.fromJson(Map<String, dynamic> json) {
    final rawId = (json['id'] as String?)?.trim() ?? '';
    final rawName = (json['name'] as String?)?.trim() ?? '';
    return SourceConfig(
      id: rawId.isEmpty ? generateSourceId() : rawId,
      name: rawName.isEmpty ? 'Source' : rawName,
      m3u: SourceEndpoint.fromJson(json['m3u']),
      epg: SourceEndpoint.fromJson(json['epg']),
      allowInsecureCerts: json['allowInsecureCerts'] as bool? ?? false,
    );
  }
}

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
  });

  /// Stable internal identity, unique per source.
  final String id;
  final String sourceId;
  final String name;
  final String number;
  final String url;
  final String tvgId;
  final String channelId;
  final String? logoUrl;
  final String? group;

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
  const Playlist({required this.channels, this.xmltvUrl});

  final List<Channel> channels;

  /// The `url-tvg` / `x-tvg-url` advertised by the M3U header, if any.
  final String? xmltvUrl;
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
    this.useMpvWindow = true,
    this.hwdec = 'auto-safe',
    this.videoOutput = 'auto',
    this.useMpvConfig = false,
    this.startFullscreen = false,
    this.mpvPath = '',
    this.autoRefreshMinutes = 360,
    this.guideHours = 12,
  });

  factory AppSettings.defaults() => const AppSettings(
        themeFamily: ThemeFamily.mawj,
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
      };

  factory AppSettings.fromJson(Map<String, dynamic> json) {
    return AppSettings(
      themeFamily: _enumByName(
        ThemeFamily.values,
        json['themeFamily'] as String?,
        ThemeFamily.mawj,
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
      useMpvWindow: json['useMpvWindow'] as bool? ?? true,
      hwdec: json['hwdec'] as String? ?? 'auto-safe',
      videoOutput: json['videoOutput'] as String? ?? 'auto',
      useMpvConfig: json['useMpvConfig'] as bool? ?? false,
      startFullscreen: json['startFullscreen'] as bool? ?? false,
      mpvPath: json['mpvPath'] as String? ?? '',
      autoRefreshMinutes: json['autoRefreshMinutes'] as int? ?? 360,
      guideHours: json['guideHours'] as int? ?? 12,
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
