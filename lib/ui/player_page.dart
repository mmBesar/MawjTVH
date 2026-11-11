import 'dart:async';
import 'dart:io' show Platform;
import 'dart:math' as math;
import 'dart:ui' as ui show FrameTiming;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:provider/provider.dart';
import 'package:screen_brightness/screen_brightness.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import '../core/app_info.dart';
import '../core/bidi.dart';
import '../core/external_player.dart';
import '../core/network_image.dart';
import '../core/pip.dart';
import '../core/platform.dart';
import '../core/theme.dart';
import '../data/app_state.dart';
import '../data/local_recorder.dart';
import '../data/models.dart';
import '../data/mpv_runtime.dart';
import '../data/text_subtitles.dart';
import '../data/track_prefs.dart';
import '../l10n/strings.dart';
import '../l10n/tvh_strings.dart';
import 'desktop_player_page.dart';
import 'widgets/channel_logo.dart';
import 'widgets/record_actions.dart';
import 'widgets/record_now_button.dart';
import 'widgets/signal_badge.dart';
import 'widgets/stb_browser.dart';
import 'widgets/stb_epg.dart';
import 'widgets/stb_osd.dart';
import 'widgets/track_sheet.dart';
import 'widgets/wave.dart';

/// Opens the player for [channel] with a short fade.
///
/// On desktop the channel plays in a separate native mpv window (when mpv is
/// available and the setting is on) and MawjTVH shows a "now playing" page;
/// everywhere else it plays inside the app.
Future<void> openPlayer(BuildContext context, Channel channel) async {
  final state = context.read<AppState>();
  final navigator = Navigator.of(context);
  if (Platform.isAndroid) {
    final app = ExternalPlayerApp.byId(state.settings.androidPlayer);
    if (app != null && await _openExternal(context, state, channel, app)) {
      return;
    }
    if (!context.mounted) {
      return;
    }
  }
  Widget page = PlayerPage(channel: channel);
  final inMpv = kIsDesktop &&
      (state.settings.useMpvWindow ||
          (state.settings.recordingsInMpv && isSyntheticChannel(channel)));
  if (inMpv) {
    MpvRuntime.useCustomPath(state.settings.mpvPath);
    final capabilities = await MpvRuntime.capabilities();
    if (capabilities != null) {
      Duration? startAt;
      if (context.mounted) {
        final answer = await _askResumeDialog(context, channel);
        if (answer.cancel) {
          return;
        }
        startAt = answer.at;
      }
      page = NowPlayingPage(
        channel: channel,
        capabilities: capabilities,
        startAt: startAt,
      );
    } else if (state.settings.useMpvWindow && context.mounted) {
      ScaffoldMessenger.maybeOf(context)?.showSnackBar(
        SnackBar(
          content: Text(context.strings.mpvMissing),
          duration: const Duration(seconds: 8),
        ),
      );
    }
  }
  await navigator.push<void>(
    PageRouteBuilder<void>(
      pageBuilder: (context, animation, secondaryAnimation) => page,
      transitionsBuilder: (context, animation, secondaryAnimation, child) {
        return FadeTransition(
          opacity: CurvedAnimation(parent: animation, curve: Curves.easeOut),
          child: child,
        );
      },
      transitionDuration: const Duration(milliseconds: 220),
      reverseTransitionDuration: const Duration(milliseconds: 160),
    ),
  );
}

/// Hands [channel] to an external player on Android and waits until it is
/// closed. Returns false when the built-in player should take over (the app
/// is not installed, or the stream cannot be reached from another app).
Future<bool> _openExternal(
  BuildContext context,
  AppState state,
  Channel channel,
  ExternalPlayerApp app,
) async {
  // A file on this device has no address another app can read.
  if (channel.id.startsWith('${kRecordingIdPrefix}local:')) {
    return false;
  }
  final messenger = ScaffoldMessenger.maybeOf(context);
  final strings = context.strings;
  final recording = isSyntheticChannel(channel);
  Duration? startAt;
  if (recording) {
    final answer = await _askResumeDialog(context, channel);
    if (answer.cancel) {
      return true;
    }
    startAt = answer.at;
  }
  try {
    final ready = await state.prepareStream(channel);
    final result = await ExternalPlayer.play(
      app: app,
      url: ready.url,
      title: ready.name,
      start: startAt,
    );
    final position = result.position;
    if (recording && position != null) {
      state.savePosition(channel, position, result.duration ?? Duration.zero);
    }
    return true;
  } on ExternalPlayerMissing {
    messenger?.showSnackBar(
      SnackBar(
        content: Text(strings.externalPlayerMissing(app.label)),
        duration: const Duration(seconds: 8),
      ),
    );
    return false;
  } catch (error) {
    messenger?.showSnackBar(SnackBar(content: Text('$error')));
    return false;
  } finally {
    state.releaseStream(channel);
  }
}

/// Asks whether to continue a recording that was left part-way; used before
/// the mpv window opens. `cancel` means the person does not want to watch
/// after all; otherwise `at` is where to start (null: from the beginning).
Future<({bool cancel, Duration? at})> _askResumeDialog(
  BuildContext context,
  Channel channel,
) async {
  final at = context.read<AppState>().resumeFor(channel);
  if (at == null) {
    return (cancel: false, at: null);
  }
  final strings = context.strings;
  // 0 cancel, 1 start over, 2 resume. Escape or a tap outside counts as
  // cancel, since the dialog returns null then.
  final choice = await showDialog<int>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      icon: const Icon(Icons.history_rounded),
      title: Text(strings.resumeFrom(_formatClock(at))),
      content: Text(channel.name),
      actions: <Widget>[
        TextButton(
          onPressed: () => Navigator.of(dialogContext).pop(0),
          child: Text(strings.cancel),
        ),
        TextButton(
          onPressed: () => Navigator.of(dialogContext).pop(1),
          child: Text(strings.startOver),
        ),
        FilledButton(
          autofocus: true,
          onPressed: () => Navigator.of(dialogContext).pop(2),
          child: Text(strings.resumeAction),
        ),
      ],
    ),
  );
  if (choice == null || choice == 0) {
    return (cancel: true, at: null);
  }
  return (cancel: false, at: choice == 2 ? at : null);
}

class PlayerPage extends StatefulWidget {
  const PlayerPage({super.key, required this.channel});

  final Channel channel;

  @override
  State<PlayerPage> createState() => _PlayerPageState();
}

class _PlayerPageState extends State<PlayerPage> {
  // ---- Playback options, all pinned here ---------------------------------
  //
  // media_kit sets its own `demuxer-lavf-o`, including `strict=experimental`.
  // That switches on ffmpeg's unfinished HLS `EXT-X-MEDIA` handling, and an
  // HLS master that advertises a subtitle rendition (ErsatzTV publishes a
  // WebVTT one) then never produces a video packet. The same options without
  // the experimental flag make ffmpeg ignore the rendition and play.
  static final String _demuxerLavfOptions = <String>[
    'seg_max_retry=5',
    'allowed_extensions=ALL',
    'protocol_whitelist=[${const PlayerConfiguration().protocolWhitelist.join(',')}]',
  ].join(',');

  /// How long to wait for the first video frame before saying so.
  static const Duration _stallAfter = Duration(seconds: 25);

  /// Controls fade out after this long while a stream is playing.
  static const Duration _controlsTimeout = Duration(seconds: 4);

  /// The Linux software renderer works on the GTK main thread and costs
  /// pixels, so it renders at the size the pane can show, up to this cap.
  static const int _softwareMaxWidth = 1920;
  static const int _softwareMaxHeight = 1080;
  static const int _softwareStartWidth = 1280;
  static const int _softwareStartHeight = 720;

  static const MethodChannel _windowChannel = MethodChannel(
    'com.alexmercerind/media_kit_video',
  );

  static bool get _isDesktop =>
      Platform.isLinux || Platform.isWindows || Platform.isMacOS;

  /// `MAWJTVH_HWDEC=auto-copy-safe` lets Linux try GPU decoding while keeping
  /// the software renderer. The default is the safe CPU decoder.
  /// Linux in-app rendering: the GPU path is smooth; the CPU path is the
  /// safe fallback (an old Wayland/Mesa combination froze on GPU).
  static bool _gpuRenderer(String choice) {
    if (!Platform.isLinux) {
      return true;
    }
    // MAWJTVH_RENDERER=cpu is a way back if the window ever freezes.
    final forced = (Platform.environment['MAWJTVH_RENDERER'] ?? '').trim();
    final pick = forced.isNotEmpty ? forced : choice;
    return pick != 'cpu';
  }

  late final bool _gpu;

  static String _linuxHwdec() {
    try {
      final value = (Platform.environment['MAWJTVH_HWDEC'] ?? '').trim();
      return value.isEmpty ? 'no' : value;
    } catch (_) {
      return 'no';
    }
  }

  final GlobalKey _videoKey = GlobalKey();
  final FocusNode _focusNode = FocusNode();
  final List<String> _recentLogs = <String>[];

  late Channel _channel;
  late final Player _player;
  late final VideoController _controller;
  StreamSubscription<String>? _errorSubscription;
  StreamSubscription<bool>? _playingSubscription;
  StreamSubscription<VideoParams>? _videoParamsSubscription;
  StreamSubscription<bool>? _bufferingSubscription;
  StreamSubscription<double>? _volumeSubscription;
  StreamSubscription<PlayerLog>? _logSubscription;
  Timer? _stallTimer;
  Timer? _hideTimer;
  Timer? _osdTimer;
  Timer? _errorTimer;
  int _autoRetries = 0;
  StreamRecorder? _recorder;
  bool get _localRecording => _recorder != null;

  (int, int)? _softwareVideoSize;
  VideoParams? _videoParams;
  Size? _viewport;

  String? _error;
  bool _buffering = false;
  bool _hasVideo = false;
  bool _stalled = false;
  bool _playing = true;
  bool _fullscreen = false;
  bool _controlsVisible = true;

  bool _brightnessSupported = false;
  double _brightness = 1;
  double _volume = 100;
  bool _adjustingBrightness = true;
  _OsdKind? _osdKind;
  IconData? _osdIcon;
  String? _osdTitle;
  String? _osdSubtitle;
  bool _browserOpen = false;
  bool _helpOpen = false;
  bool _epgOpen = false;
  int _aspectMode = 0;
  bool _deinterlace = false;
  double _audioDelay = 0;
  String _digits = '';
  Timer? _digitTimer;
  String? _lastAudioId;
  String? _lastSubtitleId;
  bool _audioApplied = false;
  bool _subApplied = false;
  DateTime _ignoreTracksUntil = DateTime.fromMillisecondsSinceEpoch(0);

  // Text subtitles. Tvheadend turns a channel's teletext subtitle pages into
  // text streams that the player cannot read from the transport stream, so the
  // stream proxy hands them to the app and they are drawn here.
  List<TextSubtitleStream> _textStreams = const <TextSubtitleStream>[];
  int? _textSelected;
  bool _textPicked = false;
  List<SubtitleSpan> _textSpans = const <SubtitleSpan>[];
  Timer? _textClear;
  StreamSubscription<TextSubtitleLine>? _textSub;
  StreamSubscription<Tracks>? _tracksSubscription;
  StreamSubscription<Track>? _trackSubscription;
  late AppState _appState;
  bool _infoVisible = false;
  Timer? _infoTimer;

  // Resume: where a recording stopped last time, offered for a few seconds.
  Duration? _resumeOffer;
  Completer<Duration?>? _resumeChoice;
  bool _resumeCancelled = false;
  bool _offered = false;
  Duration? _resumeAt;
  Timer? _positionTimer;
  Map<String, String> _infoProps = const <String, String>{};
  double _osdValue = 0;

  @override
  void initState() {
    super.initState();
    _channel = widget.channel;
    _appState = context.read<AppState>();
    _textSub = _appState.textSubtitleLines.listen(_onTextLine);
    PipService.init();
    unawaited(PipService.autoEnter(_appState.settings.pipOnLeave));
    PipService.active.addListener(_onPip);
    _gpu = _gpuRenderer(_appState.settings.inAppRenderer);
    _player = Player(
      configuration: PlayerConfiguration(
        title: 'MawjTVH — ${_channel.name}',
        logLevel: MPVLogLevel.warn,
        bufferSize: 24 * 1024 * 1024,
      ),
    );
    _controller = VideoController(
      _player,
      configuration: VideoControllerConfiguration(
        // media_kit 2.0.1 renders Linux video through an isolated EGL context
        // that can stall on Wayland/Mesa and take the UI with it, so Linux
        // uses the CPU upload path. Android keeps the hardware path.
        enableHardwareAcceleration: _gpu,
        width: Platform.isLinux && !_gpu ? _softwareStartWidth : null,
        height: Platform.isLinux && !_gpu ? _softwareStartHeight : null,
      ),
    );
    _volume = _player.state.volume;

    _errorSubscription = _player.stream.error.listen((message) {
      if (!mounted || message.trim().isEmpty || _hasVideo) {
        // A late complaint while the picture is already moving is noise.
        return;
      }
      final text = message.trim();
      _errorTimer?.cancel();
      if (_autoRetries < 2) {
        // A tuner needs a few seconds to lock; the first try often fails
        // while the second works. Retry quietly before saying anything.
        _autoRetries++;
        _errorTimer = Timer(const Duration(seconds: 2), () {
          if (mounted && !_hasVideo) {
            unawaited(_open(auto: true));
          }
        });
        return;
      }
      _errorTimer = Timer(const Duration(seconds: 3), () {
        if (mounted && !_hasVideo) {
          setState(() => _error = text);
        }
      });
    });
    _playingSubscription = _player.stream.playing.listen((playing) {
      if (!mounted) {
        return;
      }
      _playing = playing;
      if (playing && _error != null) {
        setState(() => _error = null);
      }
      if (playing) {
        _scheduleHide();
      } else {
        _hideTimer?.cancel();
        if (!_controlsVisible) {
          setState(() => _controlsVisible = true);
        }
      }
    });
    _bufferingSubscription = _player.stream.buffering.listen((buffering) {
      if (mounted && _buffering != buffering) {
        setState(() => _buffering = buffering);
      }
    });
    _tracksSubscription = _player.stream.tracks.listen(_applyTracks);
    _trackSubscription = _player.stream.track.listen(_onTrackChanged);
    _volumeSubscription = _player.stream.volume.listen((volume) {
      _volume = volume;
    });
    _videoParamsSubscription = _player.stream.videoParams.listen((params) {
      _videoParams = params;
      final hasSize = (params.w ?? 0) > 0 && (params.h ?? 0) > 0;
      if (hasSize && mounted && !_hasVideo) {
        _stallTimer?.cancel();
        _errorTimer?.cancel();
        setState(() {
          _hasVideo = true;
          _stalled = false;
          _error = null;
        });
      }
      if (Platform.isLinux) {
        _applySoftwareSize();
      }
    });
    _logSubscription = _player.stream.log.listen(_onLog);

    unawaited(
      WakelockPlus.enable().catchError((Object error) {
        debugPrint('Could not enable the wakelock: $error');
      }),
    );
    unawaited(_initializeBrightness());
    unawaited(_open());
    _scheduleHide();
    _positionTimer = Timer.periodic(
      const Duration(seconds: 15),
      (_) => _rememberPosition(),
    );
    // Figures for the problem report: how Flutter's own frames and mpv's
    // dropped frames behave while this page is open.
    WidgetsBinding.instance.addTimingsCallback(_onFrameTimings);
    _statsTimer = Timer.periodic(
      const Duration(seconds: 5),
      (_) => unawaited(_sampleDrops()),
    );
  }

  Timer? _statsTimer;
  final List<int> _dropSamples = <int>[];
  int _uiFrames = 0;
  int _slowBuilds = 0;
  int _slowRasters = 0;
  int _worstBuildMs = 0;
  int _worstRasterMs = 0;

  void _onFrameTimings(List<ui.FrameTiming> timings) {
    for (final timing in timings) {
      _uiFrames++;
      final build = timing.buildDuration.inMilliseconds;
      final raster = timing.rasterDuration.inMilliseconds;
      if (build > 16) {
        _slowBuilds++;
      }
      if (raster > 16) {
        _slowRasters++;
      }
      _worstBuildMs = math.max(_worstBuildMs, build);
      _worstRasterMs = math.max(_worstRasterMs, raster);
    }
  }

  Future<void> _sampleDrops() async {
    final platform = _player.platform;
    if (platform is! NativePlayer || !_playing) {
      return;
    }
    try {
      final value = await platform.getProperty('frame-drop-count');
      final count = int.tryParse(value);
      if (count != null) {
        _dropSamples.add(count);
        if (_dropSamples.length > 40) {
          _dropSamples.removeAt(0);
        }
      }
    } catch (_) {
      // The report simply has fewer samples.
    }
  }

  /// Keeps where a recording has got to, so it can be resumed later.
  void _rememberPosition() {
    if (!_isVod || !_playing) {
      return;
    }
    try {
      _appState.savePosition(
        _channel,
        _player.state.position,
        _player.state.duration,
      );
    } catch (error) {
      debugPrint('Could not remember the position: $error');
    }
  }

  /// Asks whether to continue [at]; completes with the chosen position, or
  /// null for "start over".
  Future<Duration?> _askResume(Duration at) {
    final completer = Completer<Duration?>();
    _resumeChoice = completer;
    // May be called while the page is still being created, so the rebuild
    // waits for the first frame instead of calling setState right here.
    _resumeOffer = at;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        setState(() {});
      }
    });
    return completer.future;
  }

  /// The person changed their mind: leave without playing anything.
  void _cancelResume() {
    final completer = _resumeChoice;
    _resumeChoice = null;
    _resumeCancelled = true;
    if (mounted) {
      setState(() => _resumeOffer = null);
    }
    if (completer != null && !completer.isCompleted) {
      completer.complete(null);
    }
    if (mounted) {
      Navigator.of(context).pop();
    }
  }

  void _chooseResume(bool resume) {
    final at = _resumeOffer;
    final completer = _resumeChoice;
    _resumeChoice = null;
    setState(() => _resumeOffer = null);
    if (completer != null && !completer.isCompleted) {
      completer.complete(resume ? at : null);
    }
    _focusNode.requestFocus();
  }

  void _onLog(PlayerLog log) {
    final text = log.text.trim();
    if (text.isEmpty) {
      return;
    }
    _recentLogs.add('[${log.level}] ${log.prefix}: $text');
    if (_recentLogs.length > 40) {
      _recentLogs.removeAt(0);
    }
    if (log.level == 'error' || log.level == 'fatal') {
      debugPrint('mpv[${log.level}] ${log.prefix}: $text');
    }
  }

  // ---- Opening and switching channels ------------------------------------

  Future<void> _setMpvProperty(String name, String value) async {
    final platform = _player.platform;
    if (platform is NativePlayer) {
      await platform.setProperty(name, value);
    }
  }

  Future<void> _open({bool auto = false}) async {
    final state = context.read<AppState>();
    final allowInsecure = state.activeSource?.allowInsecureCerts ?? false;
    if (!auto) {
      _autoRetries = 0;
    }
    _errorTimer?.cancel();
    // A recording that was left part-way: ask before anything starts.
    Duration? resumeAt;
    if (!auto && !_offered && _isVod) {
      _offered = true;
      final at = context.read<AppState>().resumeFor(_channel);
      if (at != null) {
        resumeAt = await _askResume(at);
        if (!mounted || _resumeCancelled) {
          return;
        }
        _resumeAt = resumeAt;
      }
    }
    if (resumeAt == null && _isVod) {
      // A retry carries on from where playback had got to, or from the point
      // chosen in the resume prompt when it never got going.
      final position = _player.state.position;
      resumeAt = position > Duration.zero ? position : _resumeAt;
    }
    await _stopLocalRecording(silent: true);
    if (!mounted) {
      return;
    }
    _stallTimer?.cancel();
    setState(() {
      _error = null;
      _buffering = true;
      _hasVideo = false;
      _stalled = false;
    });
    _stallTimer = Timer(_stallAfter, () {
      if (mounted && !_hasVideo && _error == null) {
        setState(() => _stalled = true);
      }
    });
    unawaited(state.markWatched(_channel));
    _audioApplied = false;
    _subApplied = false;
    _lastAudioId = null;
    _lastSubtitleId = null;
    _textClear?.cancel();
    _textStreams = const <TextSubtitleStream>[];
    _textSelected = null;
    _textPicked = false;
    _textSpans = const <SubtitleSpan>[];
    if (!auto) {
      _flashBanner();
    }

    try {
      await _setMpvProperty(
        'hwdec',
        Platform.isLinux
            ? (_gpu ? _appState.settings.hwdec : _linuxHwdec())
            : 'auto-safe',
      );
      if (Platform.isLinux && !_gpu) {
        // Everything after decoding runs on the CPU: decode on all cores and
        // use the cheapest colour conversion and scaler.
        await _setMpvProperty('vd-lavc-threads', '0');
        await _setMpvProperty('vd-lavc-fast', 'yes');
        await _setMpvProperty('sws-scaler', 'fast-bilinear');
        await _setMpvProperty('sws-fast', 'yes');
        await _setMpvProperty('framedrop', 'vo');
      }
      await _setMpvProperty('keep-open', 'yes');
      await _setMpvProperty('network-timeout', '90');
      await _setMpvProperty('tls-verify', allowInsecure ? 'no' : 'yes');
      await _setMpvProperty('demuxer-lavf-o', _demuxerLavfOptions);
      if (_isVod) {
        // media_kit turns on a cache on disk, which has no size limit, so mpv
        // read the whole recording as fast as the server could send it (about
        // 14 MB/s). That traffic runs through this app's own stream proxy, on
        // the thread Flutter needs to show every video frame, and made the
        // picture drop frames. Keep the cache in memory and a short way
        // ahead, so the file is read at about the speed it is played.
        await _setMpvProperty('cache-on-disk', 'no');
        // media_kit turns this off; mpv's default lets the decoder skip the
        // frames before a seek target, which is what makes a jump quick.
        await _setMpvProperty('hr-seek-framedrop', 'yes');
        await _setMpvProperty('cache-secs', '30');
        await _setMpvProperty('demuxer-max-bytes', '50331648');
        await _setMpvProperty('demuxer-max-back-bytes', '8388608');
      }
      if (!mounted) {
        return;
      }
      // Reconnects first when the server session dropped, so the address is
      // always one that answers.
      _channel = await context.read<AppState>().prepareStream(_channel);
      if (!mounted) {
        return;
      }
      await _player.open(
        Media(
          _channel.url,
          httpHeaders: const <String, String>{'User-Agent': kMawjUserAgent},
          // Resuming starts the file at that point, as mpv's own --start
          // does. Seeking after opening it paused was followed by 25 to 60
          // seconds of heavy frame dropping.
          start: resumeAt,
        ),
      );
      if (!mounted) {
        // The page was closed while the stream was still opening.
        unawaited(_player.stop());
        return;
      }
      if (mounted) {
        setState(() => _buffering = false);
      }
    } catch (error) {
      if (mounted) {
        setState(() {
          _buffering = false;
          _error = error.toString();
        });
      }
    }
  }

  // ---- Recording to this device -------------------------------------------

  Future<void> _stopLocalRecording({bool silent = false}) async {
    final recorder = _recorder;
    if (recorder == null) {
      return;
    }
    _recorder = null;
    await recorder.stop();
    if (mounted) {
      setState(() {});
      if (!silent) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(context.strings.stopLocalRecording)),
        );
      }
    }
  }

  Future<void> _toggleLocalRecording() async {
    if (_localRecording) {
      await _stopLocalRecording();
      return;
    }
    final state = context.read<AppState>();
    final strings = context.strings;
    final messenger = ScaffoldMessenger.of(context);
    try {
      final path = await LocalRecordings.newPath(
        state.settings.recordDir,
        _channel.name,
        // The programme on air, when the guide knows it, goes in the name.
        title: state.epg.nowFor(_channel, DateTime.now())?.title,
      );
      final fresh = await state.prepareStream(_channel);
      final recorder = await StreamRecorder.start(
        url: fresh.url,
        path: path,
        allowInsecure: state.activeSource?.allowInsecureCerts ?? false,
        onError: (message) {
          if (_recorder != null && mounted) {
            _recorder = null;
            setState(() {});
            messenger.showSnackBar(SnackBar(content: Text(message)));
          }
        },
      );
      if (!mounted) {
        // The page was left while the recording was starting.
        unawaited(recorder.stop());
        return;
      }
      _recorder = recorder;
      setState(() {});
      messenger
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text(strings.localRecordingStarted(path))));
    } catch (error) {
      messenger.showSnackBar(SnackBar(content: Text('$error')));
    }
  }

  List<Channel> _zapList(AppState state) {
    final favorites = state.favorites;
    if (favorites.length > 1 && favorites.any((c) => c.id == _channel.id)) {
      return favorites;
    }
    return state.channels;
  }

  void _zap(int delta) {
    final list = _zapList(context.read<AppState>());
    if (list.length < 2) {
      return;
    }
    final current = list.indexWhere((channel) => channel.id == _channel.id);
    final from = current < 0 ? 0 : current;
    final next = ((from + delta) % list.length + list.length) % list.length;
    _switchTo(list[next]);
  }

  void _switchTo(Channel channel) {
    if (channel.id == _channel.id) {
      return;
    }
    final previous = _channel;
    setState(() => _channel = channel);
    _resetPicture();
    _showControls();
    // Free the tuner of the channel being left once the new one has taken
    // over the player, so the old stream is not cut under it.
    unawaited(_open().whenComplete(() => _appState.releaseStream(previous)));
  }

  // ---- Controls visibility -----------------------------------------------

  void _showControls() {
    if (!_controlsVisible && mounted) {
      setState(() => _controlsVisible = true);
    }
    _scheduleHide();
  }

  void _scheduleHide() {
    _hideTimer?.cancel();
    if (!_playing) {
      return;
    }
    _hideTimer = Timer(_controlsTimeout, () {
      if (mounted && _playing && _error == null && !_stalled) {
        setState(() => _controlsVisible = false);
      }
    });
  }

  void _toggleControls() {
    if (_browserOpen) {
      _closeBrowser();
      return;
    }
    if (_epgOpen) {
      _closeEpg();
      return;
    }
    if (_infoVisible && !_infoPinned) {
      // A click away from the banner dismisses it (unless it is pinned).
      _setInfo(false);
      return;
    }
    if (_controlsVisible) {
      _hideTimer?.cancel();
      setState(() => _controlsVisible = false);
    } else {
      _showControls();
    }
  }

  // ---- Fullscreen ---------------------------------------------------------

  Future<void> _toggleFullscreen() async {
    final next = !_fullscreen;
    setState(() => _fullscreen = next);
    if (_isDesktop) {
      await _setNativeFullscreen(next);
      return;
    }
    await _setSystemUi(immersive: next);
    await _setOrientation(landscape: next);
  }

  Future<void> _setNativeFullscreen(bool enter) async {
    try {
      await _windowChannel.invokeMethod<void>(
        enter ? 'Utils.EnterNativeFullscreen' : 'Utils.ExitNativeFullscreen',
      );
    } catch (error) {
      debugPrint('Could not change window fullscreen: $error');
    }
  }

  Future<void> _setSystemUi({required bool immersive}) async {
    try {
      await SystemChrome.setEnabledSystemUIMode(
        immersive ? SystemUiMode.immersiveSticky : SystemUiMode.edgeToEdge,
      );
    } catch (_) {
      // Desktop platforms have no system chrome to hide.
    }
  }

  Future<void> _setOrientation({required bool landscape}) async {
    try {
      await SystemChrome.setPreferredOrientations(
        landscape
            ? const <DeviceOrientation>[
                DeviceOrientation.landscapeLeft,
                DeviceOrientation.landscapeRight,
              ]
            : DeviceOrientation.values,
      );
    } catch (_) {
      // Desktop platforms do not rotate.
    }
  }

  // ---- Linux software texture size ----------------------------------------

  void _onViewport(Size logical, double pixelRatio) {
    if (!Platform.isLinux || logical.isEmpty) {
      return;
    }
    final next = Size(logical.width * pixelRatio, logical.height * pixelRatio);
    final current = _viewport;
    if (current != null &&
        (current.width - next.width).abs() < 64 &&
        (current.height - next.height).abs() < 36) {
      return;
    }
    _viewport = next;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _applySoftwareSize();
      }
    });
  }

  void _applySoftwareSize() {
    final params = _videoParams;
    if (params == null) {
      return;
    }
    final double width = (params.dw ?? params.w ?? 0).toDouble();
    final double height = (params.dh ?? params.h ?? 0).toDouble();
    if (width <= 0 || height <= 0) {
      return;
    }
    final box = _viewport ??
        const Size(_softwareMaxWidth * 1.0, _softwareMaxHeight * 1.0);
    final double scale = math.min(
      1.0,
      math.min(
        math.min(box.width / width, box.height / height),
        math.min(_softwareMaxWidth / width, _softwareMaxHeight / height),
      ),
    );
    final int targetWidth = (width * scale).round() & ~1;
    final int targetHeight = (height * scale).round() & ~1;
    if (targetWidth <= 0 || targetHeight <= 0) {
      return;
    }
    if (_softwareVideoSize == (targetWidth, targetHeight)) {
      return;
    }
    _softwareVideoSize = (targetWidth, targetHeight);
    unawaited(_controller.setSize(width: targetWidth, height: targetHeight));
  }

  // ---- Gestures -----------------------------------------------------------

  Future<void> _initializeBrightness() async {
    if (!Platform.isAndroid) {
      return;
    }
    try {
      final current = await ScreenBrightness().application;
      if (!mounted) {
        return;
      }
      setState(() {
        _brightnessSupported = true;
        if (current > 0) {
          _brightness = current.clamp(0.05, 1.0).toDouble();
        }
      });
    } catch (error) {
      debugPrint('Application brightness is unavailable: $error');
    }
  }

  Future<void> _applyBrightness(double value) async {
    if (!_brightnessSupported) {
      return;
    }
    try {
      await ScreenBrightness().setApplicationScreenBrightness(value);
    } catch (error) {
      debugPrint('Could not change application brightness: $error');
    }
  }

  void _startGesture(Offset position, double width) {
    _adjustingBrightness = position.dx < width / 2;
    _showOsd(
      _adjustingBrightness ? _OsdKind.brightness : _OsdKind.volume,
      _adjustingBrightness ? _brightness : _volume / 100,
    );
  }

  void _updateGesture(DragUpdateDetails details, double height) {
    final delta = -(details.primaryDelta ?? 0) / (height * 0.55);
    if (_adjustingBrightness) {
      final next = (_brightness + delta).clamp(0.05, 1.0).toDouble();
      setState(() => _brightness = next);
      unawaited(_applyBrightness(next));
      _showOsd(_OsdKind.brightness, next);
    } else {
      final next = (_volume + delta * 100).clamp(0.0, 100.0).toDouble();
      setState(() => _volume = next);
      unawaited(_player.setVolume(next));
      _showOsd(_OsdKind.volume, next / 100);
    }
  }

  void _showMessage(IconData icon, String title, [String? subtitle]) {
    _osdTimer?.cancel();
    setState(() {
      _osdKind = _OsdKind.message;
      _osdIcon = icon;
      _osdTitle = title;
      _osdSubtitle = subtitle;
    });
    _osdTimer = Timer(const Duration(milliseconds: 1800), () {
      if (mounted) {
        setState(() => _osdKind = null);
      }
    });
  }

  void _showOsd(_OsdKind kind, double value) {
    _osdTimer?.cancel();
    setState(() {
      _osdKind = kind;
      _osdValue = value.clamp(0.0, 1.0).toDouble();
    });
    _osdTimer = Timer(const Duration(milliseconds: 900), () {
      if (mounted) {
        setState(() => _osdKind = null);
      }
    });
  }

  void _adjustVolume(double delta) {
    final next = (_volume + delta).clamp(0.0, 100.0).toDouble();
    setState(() => _volume = next);
    unawaited(_player.setVolume(next));
    _showOsd(_OsdKind.volume, next / 100);
  }

  void _onScroll(PointerSignalEvent event) {
    if (!_browserOpen &&
        !_helpOpen &&
        event is PointerScrollEvent &&
        event.scrollDelta.dy != 0) {
      _adjustVolume(event.scrollDelta.dy < 0 ? 5 : -5);
    }
  }

  // ---- Channel browser, shortcuts and picture options -----------------------

  void _openBrowser() {
    if (_browserOpen) {
      return;
    }
    _hideTimer?.cancel();
    setState(() {
      _browserOpen = true;
      _helpOpen = false;
      _epgOpen = false;
    });
  }

  void _closeBrowser() {
    if (!_browserOpen) {
      return;
    }
    setState(() => _browserOpen = false);
    _focusNode.requestFocus();
    _scheduleHide();
  }

  void _tuneFromBrowser(Channel channel) {
    _closeBrowser();
    _switchTo(channel);
  }

  void _openEpg() {
    if (_epgOpen) {
      _closeEpg();
      return;
    }
    _hideTimer?.cancel();
    setState(() {
      _epgOpen = true;
      _browserOpen = false;
      _helpOpen = false;
    });
  }

  void _closeEpg() {
    if (!_epgOpen) {
      return;
    }
    setState(() => _epgOpen = false);
    _focusNode.requestFocus();
    _scheduleHide();
  }

  void _recordFromEpg(Programme programme, {bool series = false}) {
    final strings = context.strings;
    unawaited(
      runServerAction(
        context,
        action: () => _appState.recordProgramme(programme, series: series),
        success: strings.recordingScheduled,
        forbidden: strings.recordingsForbidden,
      ),
    );
  }

  void _toggleHelp() {
    setState(() {
      _helpOpen = !_helpOpen;
      _browserOpen = false;
      _epgOpen = false;
    });
    if (!_helpOpen) {
      _focusNode.requestFocus();
    }
  }

  static const List<double?> _aspectRatios = <double?>[
    null,
    16 / 9,
    4 / 3,
    21 / 9,
    null,
  ];

  /// The picture, reshaped for the chosen aspect ratio. `Auto` leaves it
  /// untouched; the others stretch the normally fitted picture to the shape.
  Widget _videoWithAspect(Size viewport) {
    final video = Video(
      key: _videoKey,
      controller: _controller,
      controls: NoVideoControls,
      fit: BoxFit.contain,
    );
    final params = _videoParams;
    final width = (params?.dw ?? params?.w ?? 0).toDouble();
    final height = (params?.dh ?? params?.h ?? 0).toDouble();
    if (_aspectMode == 0 ||
        width <= 0 ||
        height <= 0 ||
        viewport.width <= 0 ||
        viewport.height <= 0) {
      return video;
    }
    final native = width / height;
    // Size of the picture as BoxFit.contain draws it now.
    final double drawnWidth;
    final double drawnHeight;
    if (viewport.width / viewport.height > native) {
      drawnHeight = viewport.height;
      drawnWidth = viewport.height * native;
    } else {
      drawnWidth = viewport.width;
      drawnHeight = viewport.width / native;
    }
    final double scaleX;
    final double scaleY;
    if (_aspectMode == 4) {
      scaleX = scaleY = math.max(
        viewport.width / drawnWidth,
        viewport.height / drawnHeight,
      );
    } else {
      final target = _aspectRatios[_aspectMode]!;
      final double wantedWidth;
      final double wantedHeight;
      if (viewport.width / viewport.height > target) {
        wantedHeight = viewport.height;
        wantedWidth = viewport.height * target;
      } else {
        wantedWidth = viewport.width;
        wantedHeight = viewport.width / target;
      }
      scaleX = wantedWidth / drawnWidth;
      scaleY = wantedHeight / drawnHeight;
    }
    return ClipRect(
      child: Transform.scale(scaleX: scaleX, scaleY: scaleY, child: video),
    );
  }

  void _cycleAspect() {
    final next = (_aspectMode + 1) % _aspectRatios.length;
    setState(() => _aspectMode = next);
    final strings = context.strings;
    _showMessage(
      Icons.aspect_ratio_rounded,
      strings.aspectLabel,
      strings.aspectName(next),
    );
  }

  /// True while a recording (not live TV) is playing: it can be seeked.
  bool get _isVod => isSyntheticChannel(_channel);

  /// Jumps [seconds] forward (or back, when negative) in a recording.
  void _seekBy(int seconds) {
    final total = _player.state.duration;
    var target = _player.state.position + Duration(seconds: seconds);
    if (target < Duration.zero) {
      target = Duration.zero;
    }
    if (total > Duration.zero && target > total) {
      target = total;
    }
    unawaited(_player.seek(target));
    _showMessage(
      seconds > 0 ? Icons.fast_forward_rounded : Icons.fast_rewind_rounded,
      '${seconds > 0 ? '+' : '−'}${seconds.abs()} s',
      total > Duration.zero
          ? '${_formatClock(target)} / ${_formatClock(total)}'
          : _formatClock(target),
    );
    _showControls();
  }

  // Arrow keys: volume and channels on live TV; volume and seeking in a
  // recording.
  void _onUp() {
    if (_isVod) {
      _adjustVolume(5.0);
    } else {
      _zap(-1);
    }
  }

  void _onDown() {
    if (_isVod) {
      _adjustVolume(-5.0);
    } else {
      _zap(1);
    }
  }

  void _onLeft() {
    if (_isVod) {
      _seekBy(-10);
    } else {
      _adjustVolume(-5.0);
    }
  }

  void _onRight() {
    if (_isVod) {
      _seekBy(10);
    } else {
      _adjustVolume(5.0);
    }
  }

  void _onPageUp() {
    if (_isVod) {
      _seekBy(-300);
    } else {
      _zap(-1);
    }
  }

  void _onPageDown() {
    if (_isVod) {
      _seekBy(300);
    } else {
      _zap(1);
    }
  }

  /// Back to the stream's own picture: original aspect, no deinterlacing, no
  /// audio delay. Runs on every channel change; the X key does it on demand.
  void _resetPicture({bool announce = false}) {
    final changed = _aspectMode != 0 || _deinterlace || _audioDelay != 0;
    if (changed) {
      setState(() {
        _aspectMode = 0;
        _deinterlace = false;
        _audioDelay = 0;
      });
      unawaited(_setMpvProperty('deinterlace', 'no'));
      unawaited(_setMpvProperty('audio-delay', '0'));
    }
    if (announce) {
      final strings = context.strings;
      _showMessage(
        Icons.restart_alt_rounded,
        strings.resetPictureLabel,
        strings.resetPictureDone,
      );
    }
  }

  void _toggleDeinterlace() {
    final next = !_deinterlace;
    setState(() => _deinterlace = next);
    unawaited(_setMpvProperty('deinterlace', next ? 'yes' : 'no'));
    final strings = context.strings;
    _showMessage(
      Icons.blur_linear_rounded,
      strings.deinterlaceLabel,
      next ? strings.onWord : strings.offWord,
    );
  }

  void _nudgeAudioDelay(double seconds) {
    final next = ((_audioDelay + seconds) * 1000).round() / 1000;
    _audioDelay = next;
    unawaited(_setMpvProperty('audio-delay', next.toString()));
    final ms = (next * 1000).round();
    _showMessage(
      Icons.sync_rounded,
      context.strings.audioDelayLabel,
      '${ms > 0 ? '+' : ''}$ms ms',
    );
  }

  void _cycleAudio() {
    final strings = context.strings;
    final audio =
        _player.state.tracks.audio.where((t) => _realTrack(t.id)).toList();
    if (audio.length < 2) {
      _showMessage(
        Icons.audiotrack_rounded,
        strings.audioLabel,
        strings.noOtherTracks,
      );
      return;
    }
    _lastAudioId ??= _player.state.track.audio.id;
    final current =
        audio.indexWhere((t) => t.id == _player.state.track.audio.id);
    unawaited(_player.setAudioTrack(audio[(current + 1) % audio.length]));
  }

  void _cycleSubtitle() {
    final strings = context.strings;
    _refreshTextStreams();
    final subtitles =
        _player.state.tracks.subtitle.where((t) => _realTrack(t.id)).toList();
    final texts = _textStreams;
    if (subtitles.isEmpty && texts.isEmpty) {
      _showMessage(
        Icons.subtitles_off_rounded,
        strings.subtitleLabel,
        strings.noOtherTracks,
      );
      return;
    }
    _subApplied = true;
    _lastSubtitleId ??= _player.state.track.subtitle.id;
    final currentId = _player.state.track.subtitle.id;
    // The choices in order: the player's own tracks, then the text streams,
    // then off.
    var current = -1;
    final textIndex = texts.indexWhere((s) => s.index == _textSelected);
    if (_textSelected != null && textIndex >= 0) {
      current = subtitles.length + textIndex;
    } else if (currentId != 'no' && currentId != 'auto') {
      current = subtitles.indexWhere((t) => t.id == currentId);
    }
    final next = current + 1;
    if (next < subtitles.length) {
      _clearTextSelection();
      unawaited(_player.setSubtitleTrack(subtitles[next]));
    } else if (next < subtitles.length + texts.length) {
      _selectText(texts[next - subtitles.length].index);
    } else {
      if (_textSelected != null) {
        _selectText(null);
      }
      if (currentId != 'no') {
        unawaited(_player.setSubtitleTrack(SubtitleTrack.no()));
      }
    }
  }

  // ---- Text subtitles -----------------------------------------------------

  /// Reads which text subtitle streams the channel has, and on the first
  /// sight picks one by the preferred language (unless the player has real
  /// subtitle tracks of its own, which are handled by [_applyTracks]).
  void _refreshTextStreams() {
    if (!mounted || _isVod) {
      return;
    }
    final streams = _appState.textSubtitleStreams(_channel);
    var same = streams.length == _textStreams.length;
    for (var i = 0; same && i < streams.length; i++) {
      same = streams[i].index == _textStreams[i].index;
    }
    if (!same) {
      setState(() => _textStreams = streams);
    }
    if (_textPicked || streams.isEmpty) {
      return;
    }
    if (_player.state.tracks.subtitle.any((t) => _realTrack(t.id))) {
      return;
    }
    _textPicked = true;
    final settings = _appState.settings;
    final remembered = settings.rememberTracks
        ? _appState.rememberedTrack(_channel, audio: false)
        : null;
    final off = remembered == 'off' ||
        (remembered == null && settings.preferredSubtitleLang == 'off');
    if (off) {
      return;
    }
    final index = pickTrack(
      <({String? language, String? title})>[
        for (final s in streams) (language: s.language, title: null),
      ],
      remembered: remembered,
      preferred: settings.preferredSubtitleLang,
    );
    if (index != null) {
      setState(() => _textSelected = streams[index].index);
    }
  }

  void _clearTextSelection() {
    _textClear?.cancel();
    if (_textSelected != null || _textSpans.isNotEmpty) {
      setState(() {
        _textSelected = null;
        _textSpans = const <SubtitleSpan>[];
      });
    }
  }

  /// Chooses a text subtitle stream (null: none), turning the player's own
  /// subtitles off, and remembers the choice for the channel.
  void _selectText(int? index) {
    if (!mounted) {
      return;
    }
    final strings = context.strings;
    final remember = _appState.settings.rememberTracks;
    _textPicked = true;
    final had = _textSelected != null;
    _textClear?.cancel();
    setState(() {
      _textSelected = index;
      _textSpans = const <SubtitleSpan>[];
    });
    if (index == null) {
      if (had) {
        if (remember) {
          _appState.rememberTrack(_channel, audio: false, key: 'off');
        }
        _showMessage(
          Icons.subtitles_off_rounded,
          strings.subtitleLabel,
          strings.subtitlesOff,
        );
      }
      return;
    }
    if (_player.state.track.subtitle.id != 'no') {
      _subApplied = true;
      _lastSubtitleId = 'no';
      _ignoreTracksUntil = DateTime.now().add(const Duration(seconds: 2));
      unawaited(_player.setSubtitleTrack(SubtitleTrack.no()));
    }
    final position = _textStreams.indexWhere((s) => s.index == index);
    final language = position < 0 ? '' : _textStreams[position].language;
    if (remember) {
      _appState.rememberTrack(
        _channel,
        audio: false,
        key: trackKey(language, null),
      );
    }
    _showMessage(
      Icons.subtitles_rounded,
      strings.subtitleLabel,
      trackLabel(
        context,
        index: position < 0 ? 0 : position,
        language: language,
        title: null,
        codec: null,
      ),
    );
  }

  void _onTextLine(TextSubtitleLine line) {
    if (!mounted || _isVod || line.channelId != _channel.id) {
      return;
    }
    if (_textStreams.every((s) => s.index != line.stream)) {
      _refreshTextStreams();
    }
    if (line.stream != _textSelected) {
      return;
    }
    final spans = parseSubtitleSpans(line.text);
    _textClear?.cancel();
    if (spans.isNotEmpty) {
      // A subtitle is normally replaced or cleared by the next line; this is
      // only a safety net.
      _textClear = Timer(const Duration(seconds: 12), () {
        if (mounted) {
          setState(() => _textSpans = const <SubtitleSpan>[]);
        }
      });
    }
    setState(() => _textSpans = spans);
  }

  Widget _textSubtitleOverlay() {
    return Positioned(
      left: 24,
      right: 24,
      bottom: _isDesktop ? 72 : 56,
      child: IgnorePointer(
        child: Text.rich(
          TextSpan(
            children: <InlineSpan>[
              for (final span in _textSpans)
                TextSpan(
                  text: span.text,
                  style: TextStyle(
                    color: span.color == null ? Colors.white : Color(span.color!),
                  ),
                ),
            ],
          ),
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: _isDesktop ? 26 : 20,
            height: 1.25,
            fontWeight: FontWeight.w600,
            color: Colors.white,
            shadows: const <Shadow>[
              Shadow(blurRadius: 3, color: Colors.black, offset: Offset(1, 1)),
              Shadow(blurRadius: 3, color: Colors.black, offset: Offset(-1, -1)),
            ],
          ),
        ),
      ),
    );
  }

  void _openTrackSheet() {
    _refreshTextStreams();
    unawaited(
      showTrackSheet(
        context,
        _player,
        text: _textStreams,
        textSelected: _textSelected,
        onText: _selectText,
        languageOf: (audio, id, language) =>
            _langOf(audio: audio, id: id, language: language),
      ),
    );
  }

  /// Number keys build a channel number; it tunes after a short pause, or at
  /// once on Enter.
  void _digit(int value) {
    if (_digits.length >= 4) {
      return;
    }
    _digits += '$value';
    _showMessage(Icons.dialpad_rounded, '${context.strings.channelWord} $_digits');
    _digitTimer?.cancel();
    _digitTimer = Timer(const Duration(milliseconds: 1700), _commitDigits);
  }

  void _commitDigits() {
    _digitTimer?.cancel();
    final number = _digits;
    _digits = '';
    if (number.isEmpty || !mounted) {
      return;
    }
    final target = _appState.channels
        .where((channel) => channel.number == number)
        .toList();
    if (target.isEmpty) {
      _showMessage(
        Icons.dialpad_rounded,
        context.strings.noChannelNumber(number),
      );
      return;
    }
    _switchTo(target.first);
  }

  // ---- Default and remembered tracks -------------------------------------

  static bool _realTrack(String id) => id != 'auto' && id != 'no';

  /// Picks the audio and subtitle tracks once the stream's tracks are known:
  /// what was chosen last time on this channel, else the preferred language.
  void _applyTracks(Tracks tracks) {
    if (!mounted) {
      return;
    }
    _refreshTextStreams();
    final settings = _appState.settings;
    final remember = settings.rememberTracks;
    if (!_audioApplied) {
      final audio = tracks.audio.where((t) => _realTrack(t.id)).toList();
      if (audio.isNotEmpty) {
        _audioApplied = true;
        final index = pickTrack(
          <({String? language, String? title})>[
            for (final t in audio)
              (
                language: _langOf(audio: true, id: t.id, language: t.language),
                title: t.title,
              ),
          ],
          remembered:
              remember ? _appState.rememberedTrack(_channel, audio: true) : null,
          preferred: settings.preferredAudioLang,
        );
        if (index != null) {
          _lastAudioId = audio[index].id;
          if (audio[index].id != _player.state.track.audio.id) {
            _ignoreTracksUntil = DateTime.now().add(const Duration(seconds: 2));
            unawaited(_player.setAudioTrack(audio[index]));
          }
        } else {
          unawaited(_pinAudio(audio));
        }
      }
    }
    if (!_subApplied) {
      final rememberedSub =
          remember ? _appState.rememberedTrack(_channel, audio: false) : null;
      final off = rememberedSub == 'off' ||
          (rememberedSub == null && settings.preferredSubtitleLang == 'off');
      if (off) {
        _subApplied = true;
        _lastSubtitleId = 'no';
        if (_player.state.track.subtitle.id != 'no') {
          _ignoreTracksUntil = DateTime.now().add(const Duration(seconds: 2));
          unawaited(_player.setSubtitleTrack(SubtitleTrack.no()));
        }
      } else {
        final subs = tracks.subtitle.where((t) => _realTrack(t.id)).toList();
        if (subs.isNotEmpty) {
          final index = pickTrack(
            <({String? language, String? title})>[
              for (final t in subs)
                (
                  language:
                      _langOf(audio: false, id: t.id, language: t.language),
                  title: t.title,
                ),
            ],
            remembered: rememberedSub,
            preferred: settings.preferredSubtitleLang,
          );
          if (index != null) {
            _subApplied = true;
            _lastSubtitleId = subs[index].id;
            _ignoreTracksUntil = DateTime.now().add(const Duration(seconds: 2));
            unawaited(_player.setSubtitleTrack(subs[index]));
          } else {
            // Nothing matches the preference: show it as off rather than
            // leaving the menu with nothing ticked.
            _subApplied = true;
            _lastSubtitleId = 'no';
            if (_player.state.track.subtitle.id != 'no') {
              _ignoreTracksUntil =
                  DateTime.now().add(const Duration(seconds: 2));
              unawaited(_player.setSubtitleTrack(SubtitleTrack.no()));
            }
          }
        }
      }
    }
  }

  /// With no remembered or preferred language the player picks the audio
  /// track itself and reports it as "auto", so the menu showed nothing ticked
  /// and the first change the user made was not remembered. This asks which
  /// track it is really playing and selects that one explicitly.
  Future<void> _pinAudio(List<AudioTrack> audio) async {
    final platform = _player.platform;
    if (platform is! NativePlayer) {
      return;
    }
    try {
      final id = await platform.getProperty('current-tracks/audio/id');
      if (!mounted) {
        return;
      }
      final match = audio.where((t) => t.id == id).firstOrNull;
      if (match == null) {
        return;
      }
      _lastAudioId = match.id;
      if (_player.state.track.audio.id != match.id) {
        _ignoreTracksUntil = DateTime.now().add(const Duration(seconds: 2));
        await _player.setAudioTrack(match);
      }
    } catch (_) {
      // Not available in this libmpv build: the menu just shows no tick.
    }
  }

  /// The language of an audio or subtitle track. The player is not told a
  /// stream's language when the server calls it "und", so the server's own
  /// list (in the order the player numbers its tracks) fills the gap.
  String? _langOf({
    required bool audio,
    required String id,
    required String? language,
  }) {
    if (language != null && language.trim().isNotEmpty) {
      return language;
    }
    if (_isVod) {
      return language;
    }
    final list = _appState.serverTrackLanguages(_channel, audio: audio);
    final number = int.tryParse(id);
    if (number == null || number < 1 || number > list.length) {
      return language;
    }
    final served = list[number - 1];
    return served.isEmpty ? language : served;
  }

  // media_kit starts libmpv with subtitle drawing switched off (it leaves
  // text subtitles to its own Flutter view), which also hides the bitmap
  // subtitles broadcasts use (DVB subtitles). Bitmap tracks therefore need
  // mpv's drawing switched on; text tracks stay with the Flutter view.
  String _subVisibility = 'no';

  static const Set<String> _textSubtitleCodecs = <String>{
    'subrip',
    'srt',
    'ass',
    'ssa',
    'webvtt',
    'mov_text',
    'text',
    'microdvd',
    'subviewer',
    'subviewer1',
    'sami',
    'jacosub',
    'realtext',
    'vplayer',
    'mpl2',
    'pjs',
    'stl',
  };

  void _syncSubtitleVisibility(Track track) {
    final id = track.subtitle.id;
    var want = 'no';
    if (_realTrack(id)) {
      final selected = _player.state.tracks.subtitle
          .where((t) => t.id == id)
          .firstOrNull;
      final codec = (selected?.codec ?? track.subtitle.codec ?? '')
          .toLowerCase();
      want = _textSubtitleCodecs.contains(codec) ? 'no' : 'yes';
    }
    if (want != _subVisibility) {
      _subVisibility = want;
      unawaited(_setMpvProperty('sub-visibility', want));
    }
  }

  /// A change after the automatic pick is the user's: remember it, show it.
  void _onTrackChanged(Track track) {
    _syncSubtitleVisibility(track);
    if (!mounted ||
        !_audioApplied ||
        DateTime.now().isBefore(_ignoreTracksUntil)) {
      return;
    }
    final strings = context.strings;
    final tracks = _player.state.tracks;
    final remember = _appState.settings.rememberTracks;
    final audio = track.audio;
    if (_realTrack(audio.id) && audio.id != _lastAudioId) {
      final first = _lastAudioId == null;
      _lastAudioId = audio.id;
      if (!first) {
        if (remember) {
          _appState.rememberTrack(
            _channel,
            audio: true,
            key: trackKey(
              _langOf(audio: true, id: audio.id, language: audio.language),
              audio.title,
            ),
          );
        }
        final index = tracks.audio.where((t) => _realTrack(t.id)).toList().indexWhere((t) => t.id == audio.id);
        _showMessage(
          Icons.audiotrack_rounded,
          strings.audioLabel,
          trackLabel(
            context,
            index: index < 0 ? 0 : index,
            language:
                _langOf(audio: true, id: audio.id, language: audio.language),
            title: audio.title,
            codec: audio.codec,
          ),
        );
        return;
      }
    }
    final subtitle = track.subtitle;
    if (_subApplied && subtitle.id != _lastSubtitleId) {
      final first = _lastSubtitleId == null;
      _lastSubtitleId = subtitle.id;
      if (first) {
        return;
      }
      if (subtitle.id == 'no') {
        if (remember) {
          _appState.rememberTrack(_channel, audio: false, key: 'off');
        }
        _showMessage(Icons.subtitles_off_rounded, strings.subtitleLabel, strings.subtitlesOff);
      } else if (_realTrack(subtitle.id)) {
        if (remember) {
          _appState.rememberTrack(
            _channel,
            audio: false,
            key: trackKey(
              _langOf(
                audio: false,
                id: subtitle.id,
                language: subtitle.language,
              ),
              subtitle.title,
            ),
          );
        }
        final index = tracks.subtitle.where((t) => _realTrack(t.id)).toList().indexWhere((t) => t.id == subtitle.id);
        _showMessage(
          Icons.subtitles_rounded,
          strings.subtitleLabel,
          trackLabel(
            context,
            index: index < 0 ? 0 : index,
            language: _langOf(
              audio: false,
              id: subtitle.id,
              language: subtitle.language,
            ),
            title: subtitle.title,
            codec: subtitle.codec,
          ),
        );
      }
    }
  }

  // ---- Stream info (I) ----------------------------------------------------

  bool _infoPinned = false;
  Timer? _bannerTimer;

  Duration get _osdTime =>
      Duration(seconds: _appState.settings.osdSeconds.clamp(2, 120).toInt());

  void _onPip() {
    if (mounted) {
      setState(() {});
    }
  }

  void _setInfo(bool visible) {
    _infoTimer?.cancel();
    _bannerTimer?.cancel();
    if (!mounted) {
      return;
    }
    setState(() => _infoVisible = visible);
    if (visible) {
      unawaited(_refreshInfo());
      _infoTimer = Timer.periodic(
        const Duration(seconds: 1),
        (_) => unawaited(_refreshInfo()),
      );
      if (!_infoPinned) {
        _bannerTimer = Timer(_osdTime, () {
          if (mounted && !_infoPinned) {
            _setInfo(false);
          }
        });
      }
    } else {
      _infoPinned = false;
    }
  }

  /// `I`: show the banner for a while, or hide it now.
  void _toggleInfo() => _setInfo(!_infoVisible);

  /// `P` or the pin button: keep the banner on screen, or let it go again.
  void _togglePin() {
    if (!_infoVisible) {
      _infoPinned = true;
      _setInfo(true);
      return;
    }
    final pinned = !_infoPinned;
    setState(() => _infoPinned = pinned);
    _bannerTimer?.cancel();
    if (!pinned) {
      _bannerTimer = Timer(_osdTime, () {
        if (mounted && !_infoPinned) {
          _setInfo(false);
        }
      });
    }
  }

  /// Show the banner for a few seconds when a channel opens.
  void _flashBanner() {
    if (!kIsDesktop || !_appState.settings.zapBanner) {
      return;
    }
    _setInfo(true);
  }

  Future<void> _refreshInfo() async {
    final platform = _player.platform;
    if (platform is! NativePlayer) {
      return;
    }
    const names = <String>[
      'video-codec',
      'audio-codec-name',
      'hwdec-current',
      'estimated-vf-fps',
      'video-bitrate',
      'audio-bitrate',
      'audio-params/samplerate',
      'audio-params/hr-channels',
      'frame-drop-count',
    ];
    final values = <String, String>{};
    for (final name in names) {
      try {
        final value = await platform.getProperty(name);
        if (value.isNotEmpty) {
          values[name] = value;
        }
      } catch (_) {
        // Not available in this libmpv build.
      }
    }
    if (mounted && _infoVisible) {
      setState(() => _infoProps = values);
    }
  }

  void _toggleMute() {
    final target = _volume <= 0.01 ? 100.0 : 0.0;
    unawaited(_player.setVolume(target));
    _showOsd(_OsdKind.volume, target / 100);
    _showControls();
  }

  // ---- Diagnostics --------------------------------------------------------

  static String _redact(String url) {
    final uri = Uri.tryParse(url);
    if (uri == null || uri.host.isEmpty) {
      return '(not a URL)';
    }
    final query = uri.hasQuery
        ? uri.queryParameters.keys.map((key) => '$key=*').join('&')
        : '';
    final port = uri.hasPort ? ':${uri.port}' : '';
    return '${uri.scheme}://${uri.host}$port${uri.path}'
        '${query.isEmpty ? '' : '?$query'}';
  }

  Future<String> _diagnosticsText() async {
    final buffer = StringBuffer()
      ..writeln('MawjTVH $kAppVersion')
      ..writeln('${Platform.operatingSystem} ${Platform.operatingSystemVersion}')
      ..writeln('Channel: ${_channel.number} ${_channel.name}')
      ..writeln('URL: ${_redact(_channel.url)}')
      ..writeln('Has video: $_hasVideo, stalled: $_stalled, '
          'buffering: $_buffering, playing: $_playing')
      ..writeln('Error: ${_error ?? '-'}');
    final layout = _appState.streamLayoutFor(_channel);
    if (layout != null && layout.isNotEmpty) {
      buffer.writeln('Server streams: $layout');
    }
    final tracks = _player.state.tracks;
    buffer
      ..writeln('Player audio tracks: ${tracks.audio.map((t) => '${t.id}/${t.language ?? '-'}').join(', ')}')
      ..writeln('Player subtitle tracks: ${tracks.subtitle.map((t) => '${t.id}/${t.language ?? '-'}').join(', ')}')
      ..writeln('Selected subtitle: ${_player.state.track.subtitle.id}');
    if (_isVod) {
      final stats = _appState.recordingStats;
      if (stats != null && stats.isNotEmpty) {
        buffer.writeln(stats);
      }
    }

    buffer.writeln(
      'Flutter frames: $_uiFrames, build over 16 ms: $_slowBuilds, '
      'raster over 16 ms: $_slowRasters, worst build $_worstBuildMs ms, '
      'worst raster $_worstRasterMs ms',
    );
    if (_dropSamples.length > 1) {
      final steps = <int>[
        for (var i = 1; i < _dropSamples.length; i++)
          _dropSamples[i] - _dropSamples[i - 1],
      ];
      buffer.writeln('Dropped video frames per 5 s: ${steps.join(' ')}');
    }

    final platform = _player.platform;
    if (platform is NativePlayer) {
      const properties = <String>[
        'path',
        'idle-active',
        'core-idle',
        'paused-for-cache',
        'cache-buffering-state',
        'demuxer-cache-state/underrun',
        'track-list/count',
        'video-codec',
        'audio-codec-name',
        'video-params/w',
        'video-params/h',
        'hwdec-current',
        'video-params/pixelformat',
        'estimated-vf-fps',
        'container-fps',
        'frame-drop-count',
        'decoder-frame-drop-count',
        'vo-delayed-frame-count',
        'avsync',
        'demuxer-cache-duration',
        'cache-on-disk',
        'cache-secs',
        'seeking',
        'eof-reached',
        'time-pos',
      ];
      for (final property in properties) {
        try {
          final value = await platform.getProperty(property);
          buffer.writeln('$property = $value');
        } catch (_) {
          // Not available in this libmpv build.
        }
      }
    }
    if (_recentLogs.isNotEmpty) {
      buffer
        ..writeln()
        ..writeln('Recent mpv messages:')
        ..writeAll(_recentLogs, '\n')
        ..writeln();
    }
    return buffer.toString();
  }

  Future<void> _copyDiagnostics() async {
    final text = await _diagnosticsText();
    await Clipboard.setData(ClipboardData(text: text));
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(context.strings.copied)),
      );
    }
  }

  Future<void> _showDiagnostics() async {
    final text = await _diagnosticsText();
    if (!mounted) {
      return;
    }
    final strings = context.strings;
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      constraints: const BoxConstraints(maxWidth: 720),
      builder: (sheetContext) {
        return Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              Text(
                strings.diagnostics,
                style: Theme.of(sheetContext).textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
              ),
              const SizedBox(height: 12),
              Flexible(
                child: SingleChildScrollView(
                  child: SelectableText(
                    text,
                    textDirection: TextDirection.ltr,
                    style: const TextStyle(
                      fontFamily: 'monospace',
                      fontSize: 12,
                      height: 1.4,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              FilledButton.icon(
                onPressed: () async {
                  await Clipboard.setData(ClipboardData(text: text));
                  if (sheetContext.mounted) {
                    Navigator.of(sheetContext).pop();
                  }
                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text(strings.copied)),
                    );
                  }
                },
                icon: const Icon(Icons.copy_rounded),
                label: Text(strings.copyDiagnostics),
              ),
            ],
          ),
        );
      },
    );
  }

  // ---- Lifecycle ----------------------------------------------------------

  @override
  void dispose() {
    // Silence first, before anything else that could throw: stopping ends
    // playback at once, even if the player takes a while to shut down.
    _positionTimer?.cancel();
    _statsTimer?.cancel();
    _textClear?.cancel();
    unawaited(_textSub?.cancel());
    WidgetsBinding.instance.removeTimingsCallback(_onFrameTimings);
    final choice = _resumeChoice;
    if (choice != null && !choice.isCompleted) {
      choice.complete(null);
    }
    if (_isVod) {
      try {
        _appState.savePosition(
          _channel,
          _player.state.position,
          _player.state.duration,
        );
      } catch (error) {
        debugPrint('Could not remember the position: $error');
      }
    }
    final leaving = _channel;
    final appState = _appState;
    void release() {
      try {
        appState.releaseStream(leaving);
      } catch (error) {
        debugPrint('Could not release the stream: $error');
      }
    }

    final player = _player;
    unawaited(() async {
      try {
        await player.stop();
      } catch (_) {}
      try {
        await player.dispose();
      } catch (_) {}
    }());
    // Once, now: a second release after the player is gone could end a stream
    // the page has meanwhile opened again for the same channel or recording.
    release();
    _stallTimer?.cancel();
    _hideTimer?.cancel();
    _osdTimer?.cancel();
    _errorTimer?.cancel();
    PipService.active.removeListener(_onPip);
    unawaited(PipService.autoEnter(false));
    _infoTimer?.cancel();
    _bannerTimer?.cancel();
    _digitTimer?.cancel();
    final recorder = _recorder;
    _recorder = null;
    if (recorder != null) {
      unawaited(recorder.stop());
    }
    _errorSubscription?.cancel();
    _playingSubscription?.cancel();
    _bufferingSubscription?.cancel();
    _volumeSubscription?.cancel();
    _tracksSubscription?.cancel();
    _trackSubscription?.cancel();
    _videoParamsSubscription?.cancel();
    _logSubscription?.cancel();
    _focusNode.dispose();
    if (_brightnessSupported) {
      unawaited(
        ScreenBrightness()
            .resetApplicationScreenBrightness()
            .catchError((Object error) {
          debugPrint('Could not reset application brightness: $error');
        }),
      );
    }
    unawaited(
      WakelockPlus.disable().catchError((Object error) {
        debugPrint('Could not disable the wakelock: $error');
      }),
    );
    // Give the tuner back as soon as the player is gone, and once more after
    // the player has really closed its connection.
    if (_isDesktop) {
      if (_fullscreen) {
        unawaited(_setNativeFullscreen(false));
      }
    } else {
      unawaited(_setSystemUi(immersive: false));
      unawaited(_setOrientation(landscape: false));
    }
    super.dispose();
  }

  // ---- Build --------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: !_fullscreen,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop && _fullscreen) {
          unawaited(_toggleFullscreen());
        }
      },
      child: CallbackShortcuts(
        bindings: <ShortcutActivator, VoidCallback>{
          const SingleActivator(LogicalKeyboardKey.escape): () {
            if (_resumeOffer != null) {
              _cancelResume();
            } else if (_helpOpen) {
              _toggleHelp();
            } else if (_fullscreen) {
              unawaited(_toggleFullscreen());
            } else {
              Navigator.of(context).maybePop();
            }
          },
          const SingleActivator(LogicalKeyboardKey.keyF): () {
            unawaited(_toggleFullscreen());
          },
          const SingleActivator(LogicalKeyboardKey.f11): () {
            unawaited(_toggleFullscreen());
          },
          const SingleActivator(LogicalKeyboardKey.space): () {
            unawaited(_player.playOrPause());
          },
          const SingleActivator(LogicalKeyboardKey.keyM): _toggleMute,
          const SingleActivator(LogicalKeyboardKey.arrowUp): _onUp,
          const SingleActivator(LogicalKeyboardKey.pageUp): _onPageUp,
          const SingleActivator(LogicalKeyboardKey.arrowDown): _onDown,
          const SingleActivator(LogicalKeyboardKey.pageDown): _onPageDown,
          const SingleActivator(LogicalKeyboardKey.arrowRight, shift: true):
              () {
            if (_isVod) {
              _seekBy(60);
            }
          },
          const SingleActivator(LogicalKeyboardKey.arrowLeft, shift: true): () {
            if (_isVod) {
              _seekBy(-60);
            }
          },
          const SingleActivator(LogicalKeyboardKey.keyI): _toggleInfo,
          const SingleActivator(LogicalKeyboardKey.keyD): () {
            unawaited(_showDiagnostics());
          },
          const SingleActivator(LogicalKeyboardKey.keyC): _openBrowser,
          const SingleActivator(LogicalKeyboardKey.enter): () {
            if (_digits.isNotEmpty) {
              _commitDigits();
            } else {
              _openBrowser();
            }
          },
          const SingleActivator(LogicalKeyboardKey.numpadEnter): () {
            if (_digits.isNotEmpty) {
              _commitDigits();
            } else {
              _openBrowser();
            }
          },
          const SingleActivator(LogicalKeyboardKey.keyH): _toggleHelp,
          const SingleActivator(LogicalKeyboardKey.keyP): _togglePin,
          const SingleActivator(LogicalKeyboardKey.keyG): _openEpg,
          const SingleActivator(LogicalKeyboardKey.f1): _toggleHelp,
          const SingleActivator(LogicalKeyboardKey.keyS): () {
            _openTrackSheet();
          },
          const SingleActivator(LogicalKeyboardKey.keyA): _cycleAudio,
          const SingleActivator(LogicalKeyboardKey.keyJ): _cycleSubtitle,
          const SingleActivator(LogicalKeyboardKey.keyZ): _cycleAspect,
          const SingleActivator(LogicalKeyboardKey.keyT): _toggleDeinterlace,
          const SingleActivator(LogicalKeyboardKey.keyX): () =>
              _resetPicture(announce: true),
          const SingleActivator(LogicalKeyboardKey.keyR): () {
            unawaited(_toggleLocalRecording());
          },
          const SingleActivator(LogicalKeyboardKey.bracketLeft): () =>
              _nudgeAudioDelay(-0.05),
          const SingleActivator(LogicalKeyboardKey.bracketRight): () =>
              _nudgeAudioDelay(0.05),
          const SingleActivator(LogicalKeyboardKey.digit0): () => _digit(0),
          const SingleActivator(LogicalKeyboardKey.digit1): () => _digit(1),
          const SingleActivator(LogicalKeyboardKey.digit2): () => _digit(2),
          const SingleActivator(LogicalKeyboardKey.digit3): () => _digit(3),
          const SingleActivator(LogicalKeyboardKey.digit4): () => _digit(4),
          const SingleActivator(LogicalKeyboardKey.digit5): () => _digit(5),
          const SingleActivator(LogicalKeyboardKey.digit6): () => _digit(6),
          const SingleActivator(LogicalKeyboardKey.digit7): () => _digit(7),
          const SingleActivator(LogicalKeyboardKey.digit8): () => _digit(8),
          const SingleActivator(LogicalKeyboardKey.digit9): () => _digit(9),
          const SingleActivator(LogicalKeyboardKey.numpad0): () => _digit(0),
          const SingleActivator(LogicalKeyboardKey.numpad1): () => _digit(1),
          const SingleActivator(LogicalKeyboardKey.numpad2): () => _digit(2),
          const SingleActivator(LogicalKeyboardKey.numpad3): () => _digit(3),
          const SingleActivator(LogicalKeyboardKey.numpad4): () => _digit(4),
          const SingleActivator(LogicalKeyboardKey.numpad5): () => _digit(5),
          const SingleActivator(LogicalKeyboardKey.numpad6): () => _digit(6),
          const SingleActivator(LogicalKeyboardKey.numpad7): () => _digit(7),
          const SingleActivator(LogicalKeyboardKey.numpad8): () => _digit(8),
          const SingleActivator(LogicalKeyboardKey.numpad9): () => _digit(9),
          const SingleActivator(LogicalKeyboardKey.arrowRight): _onRight,
          const SingleActivator(LogicalKeyboardKey.arrowLeft): _onLeft,
          const SingleActivator(LogicalKeyboardKey.equal): () =>
              _adjustVolume(5),
          const SingleActivator(LogicalKeyboardKey.numpadAdd): () =>
              _adjustVolume(5),
          const SingleActivator(LogicalKeyboardKey.minus): () =>
              _adjustVolume(-5),
          const SingleActivator(LogicalKeyboardKey.numpadSubtract): () =>
              _adjustVolume(-5),
        },
        child: Focus(
          autofocus: true,
          focusNode: _focusNode,
          child: _buildScaffold(context),
        ),
      ),
    );
  }

  /// The channel browser and the guide sit above the whole screen, outside the
  /// picture's gesture detector, so touching them never changes volume or
  /// brightness, and in a small player window they cover the whole app.
  Widget _panels(AppState state) {
    final inset = _isDesktop ? 150.0 : 0.0;
    return Material(
      type: MaterialType.transparency,
      child: Stack(
        fit: StackFit.expand,
        children: <Widget>[
          if (_browserOpen)
            StbChannelBrowser(
              channels: state.channels,
              favorites: state.favorites,
              groups: state.groups,
              initialGroup: state.groupFilter,
              current: _channel,
              now: state.now,
              nowFor: (channel) => state.epg.nowFor(channel, state.now),
              allowInsecure: state.activeSource?.allowInsecureCerts ?? false,
              onTune: _tuneFromBrowser,
              onGroupChanged: state.setGroupFilter,
              onClose: _closeBrowser,
              bottomInset: inset,
            ),
          if (_epgOpen)
            StbEpgPanel(
              channel: _channel,
              programmes: <Programme>[
                for (final programme in state.epg.programmesFor(_channel))
                  if (programme.stop.isAfter(
                    state.now.subtract(const Duration(minutes: 30)),
                  ))
                    programme,
              ],
              now: state.now,
              use24: state.settings.use24HourTime,
              allowInsecure: state.activeSource?.allowInsecureCerts ?? false,
              canRecord: !isSyntheticChannel(_channel),
              onRecord: _recordFromEpg,
              onRecordSeries: (p) => _recordFromEpg(p, series: true),
              onClose: _closeEpg,
              bottomInset: inset,
            ),
        ],
      ),
    );
  }

  Widget _buildScaffold(BuildContext context) {
    final state = context.watch<AppState>();
    final colors = context.mawjColors;

    return LayoutBuilder(
      builder: (context, constraints) {
        final landscape = constraints.maxWidth > constraints.maxHeight;
        final wide = constraints.maxWidth >= 900;
        final immersive = landscape || wide || _fullscreen;

        final Widget base;
        if (immersive) {
          base = Scaffold(
            backgroundColor: Colors.black,
            body: _videoLayer(state, immersive: true),
          );
        } else {
          base = Scaffold(
            backgroundColor: colors.base,
            body: SafeArea(
              child: Column(
                children: <Widget>[
                  AspectRatio(
                    aspectRatio: 16 / 9,
                    child: _videoLayer(state, immersive: false),
                  ),
                  Expanded(child: PlayerInfoPanel(channel: _channel)),
                  PlayerChannelStrip(
                    channels: _zapList(state),
                    current: _channel,
                    allowInsecure:
                        state.activeSource?.allowInsecureCerts ?? false,
                    onSelected: _switchTo,
                  ),
                  const SizedBox(height: 8),
                ],
              ),
            ),
          );
        }
        return Stack(
          fit: StackFit.expand,
          children: <Widget>[
            base,
            if (_browserOpen || _epgOpen) _panels(state),
          ],
        );
      },
    );
  }

  Widget _infoBanner(AppState state) {
    final strings = context.strings;
    final use24 = state.settings.use24HourTime;
    final now = state.epg.nowFor(_channel, state.now);
    final next = state.epg.nextFor(_channel, state.now);
    final params = _videoParams;
    final width = params?.w ?? 0;
    final height = params?.h ?? 0;
    final props = _infoProps;

    String range(Programme programme) =>
        '${strings.formatTime(programme.start, use24HourTime: use24)} – '
        '${strings.formatTime(programme.stop, use24HourTime: use24)}';

    double? progress;
    if (now != null) {
      final total = now.stop.difference(now.start).inSeconds;
      if (total > 0) {
        progress = state.now.difference(now.start).inSeconds / total;
      }
    }

    final fps = double.tryParse(props['estimated-vf-fps'] ?? '');
    final channels = props['audio-params/hr-channels'];
    final decoder = props['hwdec-current'];
    final source = state.sourceInfoFor(_channel);
    final sourceText = <String>[
      if (source?['network'] != null) source!['network']!,
      if (source?['mux'] != null) source!['mux']!,
      if (source?['provider'] != null) source!['provider']!,
    ].join(' · ');
    final videoText = <String>[
      if (width > 0 && height > 0) '$width×$height',
      if (props['video-codec'] != null)
        props['video-codec']!.split(' ').first.toUpperCase(),
      if (fps != null && fps > 0) '${fps.round()} fps',
    ].join(' · ');
    final audioText = props['audio-codec-name'] == null
        ? ''
        : <String>[
            props['audio-codec-name']!.toUpperCase(),
            if (channels != null && channels.isNotEmpty) channels,
          ].join(' ');
    final rows = <StbInfoRow>[
      if (_channel.tags.isNotEmpty)
        StbInfoRow(Icons.sell_outlined, _channel.tags.take(4).join(', ')),
      if (sourceText.isNotEmpty)
        StbInfoRow(Icons.settings_input_antenna_rounded, sourceText),
      if (videoText.isNotEmpty) StbInfoRow(Icons.videocam_outlined, videoText),
      if (audioText.isNotEmpty)
        StbInfoRow(Icons.volume_up_outlined, audioText),
      if (decoder != null && decoder != 'no')
        StbInfoRow(Icons.memory_rounded, decoder),
      if (props['frame-drop-count'] != null &&
          props['frame-drop-count'] != '0')
        StbInfoRow(
          Icons.warning_amber_rounded,
          '${strings.infoDropped} ${props['frame-drop-count']}',
        ),
    ];

    final clock = state.now;
    return StbBanner(
      data: StbBannerData(
        logo: ChannelLogo(
          channel: _channel,
          allowInsecure: state.activeSource?.allowInsecureCerts ?? false,
          size: 92,
          radius: 18,
        ),
        number: _channel.displayNumber,
        name: _channel.name,
        clock: strings.formatTime(clock, use24HourTime: use24),
        nowLabel: strings.now,
        nextLabel: strings.next,
        nowTitle: now?.displayTitle,
        nowRange: now == null ? null : range(now),
        progress: progress,
        nowDescription: now?.description,
        nextTitle: next?.displayTitle,
        nextRange: next == null ? null : range(next),
        rows: rows,
        signal: SignalBadge(channel: _channel, meter: true),
        recording: _localRecording || state.activeRecordingFor(_channel) != null,
        pinned: _infoPinned,
        pinTooltip: _infoPinned ? strings.unpinOsd : strings.pinOsd,
        onPin: _togglePin,
        onClose: () => _setInfo(false),
      ),
    );
  }

  Widget _videoLayer(AppState state, {required bool immersive}) {
    final strings = context.strings;
    final colors = context.mawjColors;
    final problem = _error != null || _stalled;
    final tuning = !problem && (!_hasVideo || _buffering);
    final dim = _brightnessSupported ? 0.0 : (1 - _brightness) * 0.6;

    return LayoutBuilder(
      builder: (context, constraints) {
        _onViewport(
          Size(constraints.maxWidth, constraints.maxHeight),
          MediaQuery.devicePixelRatioOf(context),
        );
        return Listener(
          onPointerSignal: _isDesktop ? _onScroll : null,
          child: MouseRegion(
          onHover: (_) => _showControls(),
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: _toggleControls,
            onDoubleTap: () => unawaited(_toggleFullscreen()),
            onVerticalDragStart: (details) =>
                _startGesture(details.localPosition, constraints.maxWidth),
            onVerticalDragUpdate: (details) =>
                _updateGesture(details, constraints.maxHeight),
            onHorizontalDragEnd: (details) {
              final velocity = details.primaryVelocity ?? 0;
              if (velocity.abs() > 900) {
                if (_isVod) {
                  _seekBy(velocity < 0 ? 30 : -30);
                } else {
                  _zap(velocity < 0 ? 1 : -1);
                }
              }
            },
            child: Stack(
              fit: StackFit.expand,
              children: <Widget>[
                const ColoredBox(color: Colors.black),
                _videoWithAspect(
                  Size(constraints.maxWidth, constraints.maxHeight),
                ),
                if (dim > 0)
                  IgnorePointer(
                    child: ColoredBox(
                      color: Colors.black.withValues(alpha: dim),
                    ),
                  ),
                if (_textSelected != null && _textSpans.isNotEmpty)
                  _textSubtitleOverlay(),
                if (tuning)
                  Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: <Widget>[
                        SizedBox(
                          width: 150,
                          child: WaveProgress(
                            progress: 1,
                            color: colors.accent,
                            trackColor: Colors.white24,
                            height: 30,
                            animate: true,
                            forceAnimate: true,
                          ),
                        ),
                        if (!_hasVideo) ...<Widget>[
                          const SizedBox(height: 10),
                          Builder(
                            builder: (context) {
                              final issue = state.streamIssueFor(_channel);
                              return ConstrainedBox(
                                constraints: const BoxConstraints(maxWidth: 340),
                                child: Text(
                                  issue == null
                                      ? strings.tuning
                                      : strings.streamIssue(issue),
                                  textAlign: TextAlign.center,
                                  style: TextStyle(
                                    color: issue == null
                                        ? Colors.white70
                                        : colors.accent,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              );
                            },
                          ),
                        ],
                      ],
                    ),
                  ),
                if (problem) _buildProblem(strings),
                _buildControls(state, immersive: immersive, constraints: constraints),
                if (_infoVisible && _osdKind == null && !_browserOpen && !_epgOpen)
                  _infoBanner(state),
                if (kIsDesktop &&
                    !_infoVisible &&
                    (_localRecording || state.activeRecordingFor(_channel) != null))
                  const Align(
                    alignment: AlignmentDirectional.topEnd,
                    child: Padding(
                      padding: EdgeInsetsDirectional.only(top: 76, end: 20),
                      child: IgnorePointer(child: StbRecBadge()),
                    ),
                  ),
                if (_helpOpen) StbHelpOverlay(onClose: _toggleHelp),
                if (_osdKind != null)
                  IgnorePointer(
                    child: _GestureOsd(
                      kind: _osdKind!,
                      value: _osdValue,
                      strings: strings,
                      icon: _osdIcon,
                      title: _osdTitle,
                      subtitle: _osdSubtitle,
                    ),
                  ),
                if (_resumeOffer != null) _buildResumePrompt(strings),
              ],
            ),
          ),
          ),
        );
      },
    );
  }

  /// Shown before a recording starts when it was left part-way.
  Widget _buildResumePrompt(AppStrings strings) {
    final at = _resumeOffer!;
    return Positioned.fill(
      child: Material(
        color: Colors.black.withValues(alpha: 0.92),
        child: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 420),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    const Icon(Icons.history_rounded, size: 44, color: Colors.white70),
                    const SizedBox(height: 14),
                    Text(
                      strings.resumeFrom(_formatClock(at)),
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 22,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      _channel.name,
                      textAlign: TextAlign.center,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(color: Colors.white70, fontSize: 15),
                    ),
                    const SizedBox(height: 22),
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton.icon(
                        onPressed: () => _chooseResume(true),
                        icon: const Icon(Icons.play_arrow_rounded),
                        label: Text(strings.resumeAction),
                      ),
                    ),
                    const SizedBox(height: 10),
                    SizedBox(
                      width: double.infinity,
                      child: OutlinedButton(
                        onPressed: () => _chooseResume(false),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: Colors.white,
                          side: const BorderSide(color: Colors.white54),
                        ),
                        child: Text(strings.startOver),
                      ),
                    ),
                    const SizedBox(height: 4),
                    TextButton(
                      onPressed: _cancelResume,
                      child: Text(
                        strings.cancel,
                        style: const TextStyle(color: Colors.white70),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildProblem(AppStrings strings) {
    final stalledOnly = _error == null;
    return ColoredBox(
      color: Colors.black.withValues(alpha: 0.82),
      child: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 460),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Icon(
                  stalledOnly
                      ? Icons.hourglass_top_rounded
                      : Icons.error_outline_rounded,
                  color: Colors.white70,
                  size: 44,
                ),
                const SizedBox(height: 14),
                Text(
                  stalledOnly ? strings.stalledTitle : strings.playbackError,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 20,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  stalledOnly ? strings.stalledBody : strings.playbackErrorBody,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.72),
                    height: 1.5,
                  ),
                ),
                if (_error != null) ...<Widget>[
                  const SizedBox(height: 10),
                  BidiText(
                    _error!,
                    maxLines: 4,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.45),
                      fontSize: 11,
                    ),
                  ),
                ],
                const SizedBox(height: 18),
                Wrap(
                  alignment: WrapAlignment.center,
                  spacing: 10,
                  runSpacing: 10,
                  children: <Widget>[
                    FilledButton.icon(
                      onPressed: () => unawaited(_open()),
                      icon: const Icon(Icons.refresh_rounded),
                      label: Text(strings.playbackRetry),
                    ),
                    OutlinedButton.icon(
                      onPressed: () => unawaited(_copyDiagnostics()),
                      icon: const Icon(Icons.copy_rounded),
                      label: Text(strings.copyDiagnostics),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: Colors.white,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// Desktop layout: a slim title bar and one control bar along the bottom,
  /// like a desktop player, instead of the large touch buttons.
  Widget _desktopControls(AppState state, Programme? current) {
    final strings = context.strings;
    final colors = context.mawjColors;
    final favorite = state.isFavorite(_channel);
    final use24 = state.settings.use24HourTime;
    const white = Colors.white;

    Widget icon(
      IconData data,
      String tooltip,
      VoidCallback onPressed, {
      Color color = white,
    }) {
      return IconButton(
        tooltip: tooltip,
        onPressed: onPressed,
        icon: Icon(data, color: color),
        iconSize: 22,
        visualDensity: VisualDensity.compact,
        splashRadius: 20,
      );
    }

    final visible =
        (_controlsVisible || _browserOpen || _epgOpen) && !_helpOpen;
    final compact = MediaQuery.sizeOf(context).width < 980;
    return ExcludeFocus(
      child: IgnorePointer(
      ignoring: !visible,
      child: AnimatedOpacity(
        opacity: visible ? 1 : 0,
        duration: const Duration(milliseconds: 160),
        child: Stack(
          fit: StackFit.expand,
          children: <Widget>[
            Align(
              alignment: Alignment.topCenter,
              child: DecoratedBox(
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: <Color>[Color(0xB3000000), Color(0x00000000)],
                  ),
                ),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(12, 8, 12, 22),
                  child: Row(
                    children: <Widget>[
                      icon(Icons.arrow_back_rounded, strings.back, () {
                        if (_fullscreen) {
                          unawaited(_toggleFullscreen());
                        } else {
                          Navigator.of(context).maybePop();
                        }
                      }),
                      const SizedBox(width: 6),
                      Flexible(
                        child: BidiText(
                          '${_channel.displayNumber}  ${_channel.name}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: white,
                            fontWeight: FontWeight.w700,
                            fontSize: 15,
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Flexible(child: SignalBadge(channel: _channel)),
                    ],
                  ),
                ),
              ),
            ),
            Align(
              alignment: Alignment.bottomCenter,
              child: DecoratedBox(
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.bottomCenter,
                    end: Alignment.topCenter,
                    colors: <Color>[Color(0xCC000000), Color(0x00000000)],
                  ),
                ),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(12, 34, 12, 8),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: <Widget>[
                      if (current != null) ...<Widget>[
                        Row(
                          children: <Widget>[
                            Flexible(
                              child: BidiText(
                                current.displayTitle,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  color: white,
                                  fontWeight: FontWeight.w600,
                                  fontSize: 13,
                                ),
                              ),
                            ),
                            const SizedBox(width: 10),
                            Text(
                              strings.formatRange(
                                current.start,
                                current.stop,
                                use24HourTime: use24,
                              ),
                              style: TextStyle(
                                color: white.withValues(alpha: 0.7),
                                fontSize: 12,
                                fontFeatures: const <FontFeature>[
                                  FontFeature.tabularFigures(),
                                ],
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 6),
                        ClipRRect(
                          borderRadius: BorderRadius.circular(2),
                          child: LinearProgressIndicator(
                            value: current.progressAt(state.now),
                            minHeight: 3,
                            color: colors.accent,
                            backgroundColor: Colors.white24,
                          ),
                        ),
                        const SizedBox(height: 4),
                      ],
                      if (_isVod)
                        PlayerSeekBar(player: _player, onSeek: _showControls),
                      Row(
                        children: <Widget>[
                          icon(
                            _isVod
                                ? Icons.replay_10_rounded
                                : Icons.skip_previous_rounded,
                            _isVod
                                ? strings.seekBack10
                                : strings.previousChannel,
                            () {
                              if (_isVod) {
                                _seekBy(-10);
                              } else {
                                _zap(-1);
                              }
                            },
                          ),
                          icon(
                            _playing
                                ? Icons.pause_rounded
                                : Icons.play_arrow_rounded,
                            _playing ? strings.pause : strings.play,
                            () => unawaited(_player.playOrPause()),
                          ),
                          icon(
                            _isVod
                                ? Icons.forward_10_rounded
                                : Icons.skip_next_rounded,
                            _isVod ? strings.seekForward10 : strings.nextChannel,
                            () {
                              if (_isVod) {
                                _seekBy(10);
                              } else {
                                _zap(1);
                              }
                            },
                          ),
                          StreamBuilder<double>(
                            stream: _player.stream.volume,
                            initialData: _player.state.volume,
                            builder: (context, snapshot) {
                              final volume =
                                  snapshot.data ?? _player.state.volume;
                              return Row(
                                mainAxisSize: MainAxisSize.min,
                                children: <Widget>[
                                  icon(
                                    volume <= 0.01
                                        ? Icons.volume_off_rounded
                                        : Icons.volume_up_rounded,
                                    volume <= 0.01 ? strings.unmute : strings.mute,
                                    _toggleMute,
                                  ),
                                  SizedBox(
                                    width: 110,
                                    child: SliderTheme(
                                      data: SliderTheme.of(context).copyWith(
                                        trackHeight: 3,
                                        thumbShape: const RoundSliderThumbShape(
                                          enabledThumbRadius: 6,
                                        ),
                                        overlayShape:
                                            SliderComponentShape.noOverlay,
                                      ),
                                      child: Slider(
                                        value: volume.clamp(0.0, 100.0).toDouble(),
                                        max: 100,
                                        onChanged: (value) =>
                                            unawaited(_player.setVolume(value)),
                                      ),
                                    ),
                                  ),
                                ],
                              );
                            },
                          ),
                          const Spacer(),
                          icon(
                            favorite
                                ? Icons.star_rounded
                                : Icons.star_outline_rounded,
                            favorite ? strings.removeFavorite : strings.addFavorite,
                            () => unawaited(state.toggleFavorite(_channel)),
                            color: favorite ? colors.accent : white,
                          ),
                          if (!isSyntheticChannel(_channel)) ...<Widget>[
                            RecordNowButton(channel: _channel, plain: true),
                            LocalRecordButton(
                              recording: _localRecording,
                              plain: true,
                              onPressed: () =>
                                  unawaited(_toggleLocalRecording()),
                            ),
                          ],
                          icon(Icons.list_rounded, strings.channelListTooltip,
                              _openBrowser),
                          icon(Icons.subtitles_rounded, strings.audioAndSubtitles,
                              _openTrackSheet),
                          if (!compact) ...<Widget>[
                            icon(Icons.aspect_ratio_rounded, strings.aspectTooltip,
                                _cycleAspect),
                            icon(Icons.info_outline_rounded, strings.infoTooltip,
                                _toggleInfo),
                            icon(Icons.event_note_rounded, strings.stbEpg,
                                _openEpg),
                            icon(Icons.keyboard_alt_outlined, strings.helpTooltip,
                                _toggleHelp),
                          ],
                          icon(Icons.monitor_heart_outlined, strings.diagnostics,
                              () => unawaited(_showDiagnostics())),
                          icon(
                            _fullscreen
                                ? Icons.fullscreen_exit_rounded
                                : Icons.fullscreen_rounded,
                            _fullscreen
                                ? strings.exitFullScreen
                                : strings.fullScreen,
                            () => unawaited(_toggleFullscreen()),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
      ),
    );
  }

  Widget _buildControls(
    AppState state, {
    required bool immersive,
    required BoxConstraints constraints,
  }) {
    final strings = context.strings;
    final colors = context.mawjColors;
    final padding = immersive ? MediaQuery.paddingOf(context) : EdgeInsets.zero;
    final favorite = state.isFavorite(_channel);
    final showStrip = immersive && constraints.maxHeight >= 420;
    final allowInsecure = state.activeSource?.allowInsecureCerts ?? false;
    final current = state.epg.nowFor(_channel, state.now);

    if (kIsDesktop) {
      return _desktopControls(state, current);
    }

    if (PipService.active.value) {
      // The floating window shows only the picture.
      return const SizedBox.shrink();
    }
    final visible = _controlsVisible && !_browserOpen && !_epgOpen;
    return IgnorePointer(
      ignoring: !visible,
      child: AnimatedOpacity(
        opacity: visible ? 1 : 0,
        duration: const Duration(milliseconds: 180),
        child: Stack(
          fit: StackFit.expand,
          children: <Widget>[
            // The controls are laid out in rows (top bar, transport, action
            // buttons, now playing and channel strip) so nothing can sit on
            // top of anything else.
            Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                DecoratedBox(
                  decoration: const BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: <Color>[Color(0xCC000000), Color(0x00000000)],
                    ),
                  ),
                  child: Padding(
                    padding: EdgeInsets.fromLTRB(
                      8 + padding.left,
                      4 + padding.top,
                      8 + padding.right,
                      10,
                    ),
                    child: Row(
                      children: <Widget>[
                        _RoundButton(
                          tooltip: strings.back,
                          icon: Icons.arrow_back_rounded,
                          onPressed: () {
                            if (_fullscreen) {
                              unawaited(_toggleFullscreen());
                            } else {
                              Navigator.of(context).maybePop();
                            }
                          },
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: <Widget>[
                              BidiText(
                                _channel.name,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.w800,
                                  fontSize: 16,
                                ),
                              ),
                              Row(
                                children: <Widget>[
                                  Text(
                                    '${strings.channel} ${_channel.displayNumber}',
                                    style: TextStyle(
                                      color: Colors.white.withValues(alpha: 0.65),
                                      fontSize: 12,
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  Flexible(child: SignalBadge(channel: _channel)),
                                ],
                              ),
                            ],
                          ),
                        ),
                        if (constraints.maxWidth >= 560)
                          _RoundButton(
                            tooltip: strings.diagnostics,
                            icon: Icons.monitor_heart_outlined,
                            onPressed: () => unawaited(_showDiagnostics()),
                          ),
                        _RoundButton(
                          tooltip: _fullscreen
                              ? strings.exitFullScreen
                              : strings.fullScreen,
                          icon: _fullscreen
                              ? Icons.fullscreen_exit_rounded
                              : Icons.fullscreen_rounded,
                          onPressed: () => unawaited(_toggleFullscreen()),
                        ),
                      ],
                    ),
                  ),
                ),
                // Transport: shrinks to fit rather than overlapping.
                Expanded(
                  child: Center(
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: <Widget>[
                          _RoundButton(
                            tooltip: _isVod
                                ? strings.seekBack10
                                : strings.previousChannel,
                            icon: _isVod
                                ? Icons.replay_10_rounded
                                : Icons.skip_previous_rounded,
                            size: 36,
                            onPressed: () {
                              if (_isVod) {
                                _seekBy(-10);
                              } else {
                                _zap(-1);
                              }
                            },
                          ),
                          const SizedBox(width: 18),
                          _RoundButton(
                            tooltip: _playing ? strings.pause : strings.play,
                            icon: _playing
                                ? Icons.pause_rounded
                                : Icons.play_arrow_rounded,
                            size: 52,
                            filled: true,
                            onPressed: () {
                              unawaited(_player.playOrPause());
                              _showControls();
                            },
                          ),
                          const SizedBox(width: 18),
                          _RoundButton(
                            tooltip: _isVod
                                ? strings.seekForward10
                                : strings.nextChannel,
                            icon: _isVod
                                ? Icons.forward_10_rounded
                                : Icons.skip_next_rounded,
                            size: 36,
                            onPressed: () {
                              if (_isVod) {
                                _seekBy(10);
                              } else {
                                _zap(1);
                              }
                            },
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                if (_isVod)
                  Padding(
                    padding: EdgeInsets.fromLTRB(
                      12 + padding.left,
                      0,
                      12 + padding.right,
                      0,
                    ),
                    child: PlayerSeekBar(
                      player: _player,
                      onSeek: _showControls,
                    ),
                  ),
                // Action buttons: volume, channels, guide, tracks, favourite,
                // recording, floating window.
                Padding(
                  padding: EdgeInsets.fromLTRB(
                    8 + padding.left,
                    0,
                    8 + padding.right,
                    immersive ? 0 : 4,
                  ),
                  child: SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: ConstrainedBox(
                      constraints: BoxConstraints(
                        minWidth: math.max(
                          0.0,
                          constraints.maxWidth - 16 - padding.left - padding.right,
                        ),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: <Widget>[
                          StreamBuilder<double>(
                            stream: _player.stream.volume,
                            initialData: _player.state.volume,
                            builder: (context, snapshot) {
                              final volume =
                                  snapshot.data ?? _player.state.volume;
                              final muted = volume <= 0.01;
                              return _RoundButton(
                                tooltip: muted ? strings.unmute : strings.mute,
                                icon: muted
                                    ? Icons.volume_off_rounded
                                    : Icons.volume_up_rounded,
                                onPressed: _toggleMute,
                              );
                            },
                          ),
                          const SizedBox(width: 8),
                          _RoundButton(
                            tooltip: strings.stbChannels,
                            icon: Icons.list_rounded,
                            onPressed: _openBrowser,
                          ),
                          const SizedBox(width: 8),
                          _RoundButton(
                            tooltip: strings.stbEpg,
                            icon: Icons.event_note_rounded,
                            onPressed: _openEpg,
                          ),
                          const SizedBox(width: 8),
                          _RoundButton(
                            tooltip: strings.audioAndSubtitles,
                            icon: Icons.subtitles_rounded,
                            onPressed: _openTrackSheet,
                          ),
                          const SizedBox(width: 8),
                          _RoundButton(
                            tooltip: favorite
                                ? strings.removeFavorite
                                : strings.addFavorite,
                            icon: favorite
                                ? Icons.star_rounded
                                : Icons.star_outline_rounded,
                            color: favorite ? colors.accent : Colors.white,
                            onPressed: () =>
                                unawaited(state.toggleFavorite(_channel)),
                          ),
                          if (!isSyntheticChannel(_channel)) ...<Widget>[
                            const SizedBox(width: 8),
                            RecordNowButton(channel: _channel),
                            const SizedBox(width: 8),
                            LocalRecordButton(
                              recording: _localRecording,
                              onPressed: () =>
                                  unawaited(_toggleLocalRecording()),
                            ),
                          ],
                          if (Platform.isAndroid) ...<Widget>[
                            const SizedBox(width: 8),
                            _RoundButton(
                              tooltip: strings.pipButton,
                              icon: Icons.picture_in_picture_alt_rounded,
                              onPressed: () => unawaited(PipService.enter()),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                ),
                if (immersive)
                  DecoratedBox(
                    decoration: const BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.bottomCenter,
                        end: Alignment.topCenter,
                        colors: <Color>[Color(0xE6000000), Color(0x00000000)],
                      ),
                    ),
                    child: Padding(
                      padding: EdgeInsets.fromLTRB(
                        16 + padding.left,
                        12,
                        16 + padding.right,
                        8 + padding.bottom,
                      ),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: <Widget>[
                          if (current != null) ...<Widget>[
                            BidiText(
                              current.displayTitle,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.w700,
                                fontSize: 15,
                              ),
                            ),
                            const SizedBox(height: 2),
                            WaveProgress(
                              progress: current.progressAt(state.now),
                              color: colors.accent,
                              trackColor: Colors.white24,
                              height: 16,
                              animate: true,
                            ),
                          ],
                          if (showStrip)
                            PlayerChannelStrip(
                              channels: _zapList(state),
                              current: _channel,
                              allowInsecure: allowInsecure,
                              onSelected: _switchTo,
                              onDark: true,
                            ),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// Everything under the video in portrait: what is on and what comes next.
class PlayerInfoPanel extends StatelessWidget {
  const PlayerInfoPanel({super.key, required this.channel});

  final Channel channel;

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final strings = context.strings;
    final colors = context.mawjColors;
    final theme = Theme.of(context);
    final now = state.now;
    final current = state.epg.nowFor(channel, now);
    final next = state.epg.nextFor(channel, now);
    final use24 = state.settings.use24HourTime;
    final allowInsecure = state.activeSource?.allowInsecureCerts ?? false;
    final favorite = state.isFavorite(channel);

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              ChannelLogo(
                channel: channel,
                allowInsecure: allowInsecure,
                size: 48,
                radius: 14,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    BidiText(
                      channel.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    BidiText(
                      channel.group == null
                          ? '${strings.channel} ${channel.displayNumber}'
                          : '${strings.channel} ${channel.displayNumber} · ${channel.group}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: colors.subtext0,
                      ),
                    ),
                  ],
                ),
              ),
              IconButton(
                tooltip:
                    favorite ? strings.removeFavorite : strings.addFavorite,
                onPressed: () => unawaited(state.toggleFavorite(channel)),
                icon: Icon(
                  favorite ? Icons.star_rounded : Icons.star_outline_rounded,
                  color: favorite ? colors.accent : colors.subtext0,
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          if (current != null) ...<Widget>[
            BidiText(
              current.displayTitle,
              style: theme.textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.w800,
                height: 1.2,
              ),
            ),
            if (current.subTitle != null) ...<Widget>[
              const SizedBox(height: 4),
              BidiText(
                current.subTitle!,
                style: theme.textTheme.titleSmall?.copyWith(
                  color: colors.subtext0,
                ),
              ),
            ],
            const SizedBox(height: 10),
            WaveProgress(
              progress: current.progressAt(now),
              color: colors.accent,
              trackColor: colors.surface2,
              height: 18,
              animate: true,
            ),
            const SizedBox(height: 4),
            Row(
              children: <Widget>[
                Expanded(
                  child: Text(
                    strings.formatRange(
                      current.start,
                      current.stop,
                      use24HourTime: use24,
                    ),
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: colors.overlay1,
                      fontFeatures: const <FontFeature>[
                        FontFeature.tabularFigures(),
                      ],
                    ),
                  ),
                ),
                Text(
                  strings.minutesLeft(
                    current.stop.difference(now).inMinutes.clamp(0, 9999).toInt(),
                  ),
                  style: theme.textTheme.labelMedium?.copyWith(
                    color: colors.accent,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
            if (current.description != null) ...<Widget>[
              const SizedBox(height: 14),
              BidiText(
                current.description!,
                maxLines: 6,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: colors.subtext1,
                  height: 1.55,
                ),
              ),
            ],
          ] else
            Text(
              strings.noProgrammeInfo,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: colors.overlay0,
                fontStyle: FontStyle.italic,
              ),
            ),
          if (next != null) ...<Widget>[
            const SizedBox(height: 22),
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: colors.surface0.withValues(alpha: 0.6),
                borderRadius: BorderRadius.circular(18),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    strings.formatTime(next.start, use24HourTime: use24),
                    style: theme.textTheme.labelLarge?.copyWith(
                      color: colors.accent,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        BidiText(
                          next.displayTitle,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.bodyMedium?.copyWith(
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        if (next.subTitle != null)
                          BidiText(
                            next.subTitle!,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: colors.subtext0,
                            ),
                          ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// A row of channel logos for switching without leaving the player.
class PlayerChannelStrip extends StatefulWidget {
  const PlayerChannelStrip({
    super.key,
    required this.channels,
    required this.current,
    required this.allowInsecure,
    required this.onSelected,
    this.onDark = false,
  });

  final List<Channel> channels;
  final Channel current;
  final bool allowInsecure;
  final ValueChanged<Channel> onSelected;
  final bool onDark;

  @override
  State<PlayerChannelStrip> createState() => PlayerChannelStripState();
}

class PlayerChannelStripState extends State<PlayerChannelStrip> {
  static const double _itemWidth = 80;

  late final ScrollController _scroll;

  @override
  void initState() {
    super.initState();
    final index = widget.channels.indexWhere(
      (channel) => channel.id == widget.current.id,
    );
    _scroll = ScrollController(
      initialScrollOffset: math.max(0, (index < 0 ? 0 : index) * _itemWidth - 120),
    );
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (widget.channels.length < 2) {
      return const SizedBox(height: 4);
    }
    final colors = context.mawjColors;
    final theme = Theme.of(context);
    final labelColor = widget.onDark ? Colors.white70 : colors.subtext0;
    return SizedBox(
      height: 96,
      child: ListView.builder(
        controller: _scroll,
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        itemExtent: _itemWidth,
        itemCount: widget.channels.length,
        itemBuilder: (context, index) {
          final channel = widget.channels[index];
          final selected = channel.id == widget.current.id;
          return InkWell(
            borderRadius: BorderRadius.circular(16),
            onTap: () => widget.onSelected(channel),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 6),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: <Widget>[
                  DecoratedBox(
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(17),
                      border: Border.all(
                        color: selected ? colors.accent : Colors.transparent,
                        width: 2,
                      ),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.all(2),
                      child: ChannelLogo(
                        channel: channel,
                        allowInsecure: widget.allowInsecure,
                        size: 48,
                        radius: 14,
                      ),
                    ),
                  ),
                  const SizedBox(height: 4),
                  BidiText(
                    channel.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.center,
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: selected ? colors.accent : labelColor,
                      fontWeight: selected ? FontWeight.w800 : FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

enum _OsdKind { brightness, volume, message }

class _GestureOsd extends StatelessWidget {
  const _GestureOsd({
    required this.kind,
    required this.value,
    required this.strings,
    this.icon,
    this.title,
    this.subtitle,
  });

  final _OsdKind kind;
  final double value;
  final AppStrings strings;
  final IconData? icon;
  final String? title;
  final String? subtitle;

  @override
  Widget build(BuildContext context) {
    final brightness = kind == _OsdKind.brightness;
    final percent = (value * 100).round();
    if (kind == _OsdKind.message) {
      return StbMessageOsd(
        icon: icon ?? Icons.info_outline_rounded,
        title: title ?? '',
        subtitle: subtitle,
      );
    }
    if (kIsDesktop) {
      return StbValueOsd(
        icon: brightness
            ? Icons.brightness_6_rounded
            : (percent == 0
                ? Icons.volume_off_rounded
                : Icons.volume_up_rounded),
        label: brightness ? strings.brightness : strings.volume,
        value: value,
      );
    }
    return Center(
      child: Container(
        padding: const EdgeInsets.fromLTRB(18, 14, 18, 14),
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.68),
          borderRadius: BorderRadius.circular(18),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Row(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Icon(
                  brightness
                      ? Icons.brightness_6_rounded
                      : (percent == 0
                          ? Icons.volume_off_rounded
                          : Icons.volume_up_rounded),
                  color: Colors.white,
                  size: 20,
                ),
                const SizedBox(width: 8),
                Text(
                  brightness ? strings.brightness : strings.volume,
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.85),
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            SizedBox(
              width: 156,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(999),
                child: LinearProgressIndicator(
                  value: value,
                  minHeight: 5,
                  backgroundColor: Colors.white.withValues(alpha: 0.22),
                  color: Colors.white,
                ),
              ),
            ),
            const SizedBox(height: 6),
            Text(
              '$percent%',
              style: const TextStyle(
                color: Colors.white,
                fontSize: 13,
                fontWeight: FontWeight.w700,
                fontFeatures: <FontFeature>[FontFeature.tabularFigures()],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _RoundButton extends StatelessWidget {
  const _RoundButton({
    required this.tooltip,
    required this.icon,
    required this.onPressed,
    this.size = 24,
    this.filled = false,
    this.color = Colors.white,
  });

  final String tooltip;
  final IconData icon;
  final VoidCallback onPressed;
  final double size;
  final bool filled;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final accent = context.mawjColors.accent;
    return Material(
      color: filled ? accent : Colors.black.withValues(alpha: 0.45),
      shape: const CircleBorder(),
      clipBehavior: Clip.antiAlias,
      child: IconButton(
        tooltip: tooltip,
        onPressed: onPressed,
        iconSize: size,
        color: filled ? Theme.of(context).colorScheme.onPrimary : color,
        icon: Icon(icon),
      ),
    );
  }
}

/// 1:02:03 or 02:03.
String _formatClock(Duration value) {
  final total = value.inSeconds < 0 ? 0 : value.inSeconds;
  final hours = total ~/ 3600;
  final minutes = (total % 3600) ~/ 60;
  final seconds = total % 60;
  String two(int number) => number.toString().padLeft(2, '0');
  return hours > 0
      ? '$hours:${two(minutes)}:${two(seconds)}'
      : '${two(minutes)}:${two(seconds)}';
}

/// Position, a slider and the length of a recording. Drag or tap the slider
/// to jump anywhere in the file.
class PlayerSeekBar extends StatefulWidget {
  const PlayerSeekBar({super.key, required this.player, this.onSeek});

  final Player player;
  final VoidCallback? onSeek;

  @override
  State<PlayerSeekBar> createState() => _PlayerSeekBarState();
}

class _PlayerSeekBarState extends State<PlayerSeekBar> {
  /// Seconds while the thumb is being dragged, otherwise null.
  double? _drag;

  /// The position once per second. The player reports it for every frame,
  /// and redrawing the bar that often costs the video its smoothness.
  late final Stream<Duration> _positions = widget.player.stream.position
      .map((position) => Duration(seconds: position.inSeconds))
      .distinct();

  @override
  Widget build(BuildContext context) {
    const style = TextStyle(
      color: Colors.white,
      fontSize: 12,
      fontFeatures: <FontFeature>[FontFeature.tabularFigures()],
    );
    return StreamBuilder<Duration>(
      stream: widget.player.stream.duration,
      initialData: widget.player.state.duration,
      builder: (context, durationSnapshot) {
        final total = durationSnapshot.data ?? widget.player.state.duration;
        return StreamBuilder<Duration>(
          stream: _positions,
          initialData: Duration(seconds: widget.player.state.position.inSeconds),
          builder: (context, positionSnapshot) {
            final position =
                positionSnapshot.data ?? widget.player.state.position;
            final totalSeconds = total.inMilliseconds / 1000.0;
            final known = totalSeconds > 0;
            final seconds = _drag ?? position.inMilliseconds / 1000.0;
            return Row(
              children: <Widget>[
                Text(
                  _formatClock(Duration(milliseconds: (seconds * 1000).round())),
                  style: style,
                ),
                Expanded(
                  child: SliderTheme(
                    data: SliderTheme.of(context).copyWith(
                      trackHeight: 3,
                      thumbShape: const RoundSliderThumbShape(
                        enabledThumbRadius: 6,
                      ),
                      overlayShape: SliderComponentShape.noOverlay,
                    ),
                    child: Slider(
                      value: known
                          ? seconds.clamp(0.0, totalSeconds).toDouble()
                          : 0.0,
                      max: known ? totalSeconds : 1.0,
                      onChanged: known
                          ? (value) => setState(() => _drag = value)
                          : null,
                      onChangeEnd: known
                          ? (value) {
                              setState(() => _drag = null);
                              unawaited(
                                widget.player.seek(
                                  Duration(milliseconds: (value * 1000).round()),
                                ),
                              );
                              widget.onSeek?.call();
                            }
                          : null,
                    ),
                  ),
                ),
                Text(known ? _formatClock(total) : '--:--', style: style),
              ],
            );
          },
        );
      },
    );
  }
}
