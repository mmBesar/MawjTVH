import 'dart:async';
import 'dart:io' show Platform;
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:provider/provider.dart';
import 'package:screen_brightness/screen_brightness.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import '../core/app_info.dart';
import '../core/bidi.dart';
import '../core/network_image.dart';
import '../core/platform.dart';
import '../core/theme.dart';
import '../data/app_state.dart';
import '../data/local_recorder.dart';
import '../data/models.dart';
import '../data/mpv_runtime.dart';
import '../l10n/strings.dart';
import '../l10n/tvh_strings.dart';
import 'desktop_player_page.dart';
import 'widgets/channel_logo.dart';
import 'widgets/record_now_button.dart';
import 'widgets/signal_badge.dart';
import 'widgets/wave.dart';

/// Opens the player for [channel] with a short fade.
///
/// On desktop the channel plays in a separate native mpv window (when mpv is
/// available and the setting is on) and MawjTVH shows a "now playing" page;
/// everywhere else it plays inside the app.
Future<void> openPlayer(BuildContext context, Channel channel) async {
  final state = context.read<AppState>();
  final navigator = Navigator.of(context);
  Widget page = PlayerPage(channel: channel);
  if (kIsDesktop && state.settings.useMpvWindow) {
    MpvRuntime.useCustomPath(state.settings.mpvPath);
    final capabilities = await MpvRuntime.capabilities();
    if (capabilities != null) {
      page = NowPlayingPage(channel: channel, capabilities: capabilities);
    } else if (context.mounted) {
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
  double _osdValue = 0;

  @override
  void initState() {
    super.initState();
    _channel = widget.channel;
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
        enableHardwareAcceleration: !Platform.isLinux,
        width: Platform.isLinux ? _softwareStartWidth : null,
        height: Platform.isLinux ? _softwareStartHeight : null,
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
    await _stopLocalRecording(silent: true);
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

    try {
      await _setMpvProperty(
        'hwdec',
        Platform.isLinux ? _linuxHwdec() : 'auto-safe',
      );
      if (Platform.isLinux) {
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
      await _player.open(
        Media(
          _channel.url,
          httpHeaders: const <String, String>{'User-Agent': kMawjUserAgent},
        ),
        play: true,
      );
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
      );
      final recorder = await StreamRecorder.start(
        url: _channel.url,
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
      _recorder = recorder;
      if (mounted) {
        setState(() {});
      }
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
    setState(() => _channel = channel);
    _showControls();
    unawaited(_open());
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

  void _toggleMute() {
    unawaited(_player.setVolume(_volume <= 0.01 ? 100 : 0));
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
    _stallTimer?.cancel();
    _hideTimer?.cancel();
    _osdTimer?.cancel();
    _errorTimer?.cancel();
    final recorder = _recorder;
    _recorder = null;
    if (recorder != null) {
      unawaited(recorder.stop());
    }
    _errorSubscription?.cancel();
    _playingSubscription?.cancel();
    _bufferingSubscription?.cancel();
    _volumeSubscription?.cancel();
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
    unawaited(_player.dispose());
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
            if (_fullscreen) {
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
          const SingleActivator(LogicalKeyboardKey.arrowUp): () => _zap(-1),
          const SingleActivator(LogicalKeyboardKey.pageUp): () => _zap(-1),
          const SingleActivator(LogicalKeyboardKey.arrowDown): () => _zap(1),
          const SingleActivator(LogicalKeyboardKey.pageDown): () => _zap(1),
          const SingleActivator(LogicalKeyboardKey.keyI): () {
            unawaited(_showDiagnostics());
          },
        },
        child: Focus(
          autofocus: true,
          focusNode: _focusNode,
          child: _buildScaffold(context),
        ),
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

        if (immersive) {
          return Scaffold(
            backgroundColor: Colors.black,
            body: _videoLayer(state, immersive: true),
          );
        }

        return Scaffold(
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
      },
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
        return MouseRegion(
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
                _zap(velocity < 0 ? 1 : -1);
              }
            },
            child: Stack(
              fit: StackFit.expand,
              children: <Widget>[
                const ColoredBox(color: Colors.black),
                Video(
                  key: _videoKey,
                  controller: _controller,
                  controls: NoVideoControls,
                  fit: BoxFit.contain,
                ),
                if (dim > 0)
                  IgnorePointer(
                    child: ColoredBox(
                      color: Colors.black.withValues(alpha: dim),
                    ),
                  ),
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
                          Text(
                            strings.tuning,
                            style: const TextStyle(
                              color: Colors.white70,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                if (problem) _buildProblem(strings),
                _buildControls(state, immersive: immersive, constraints: constraints),
                if (_osdKind != null)
                  IgnorePointer(
                    child: _GestureOsd(
                      kind: _osdKind!,
                      value: _osdValue,
                      strings: strings,
                    ),
                  ),
              ],
            ),
          ),
        );
      },
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

    return IgnorePointer(
      ignoring: !_controlsVisible,
      child: AnimatedOpacity(
        opacity: _controlsVisible ? 1 : 0,
        duration: const Duration(milliseconds: 180),
        child: Stack(
          fit: StackFit.expand,
          children: <Widget>[
            // Top bar.
            Align(
              alignment: Alignment.topCenter,
              child: DecoratedBox(
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
                    18,
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
            ),
            // Centre transport.
            Center(
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  _RoundButton(
                    tooltip: strings.previousChannel,
                    icon: Icons.skip_previous_rounded,
                    size: 36,
                    onPressed: () => _zap(-1),
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
                    tooltip: strings.nextChannel,
                    icon: Icons.skip_next_rounded,
                    size: 36,
                    onPressed: () => _zap(1),
                  ),
                ],
              ),
            ),
            // Volume, bottom start.
            PositionedDirectional(
              bottom: 8 + padding.bottom + (showStrip ? 132 : 0),
              start: 8 + padding.left,
              child: StreamBuilder<double>(
                stream: _player.stream.volume,
                initialData: _player.state.volume,
                builder: (context, snapshot) {
                  final volume = snapshot.data ?? _player.state.volume;
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
            ),
            // Recording buttons, bottom end: the top bar is too crowded on a
            // phone held upright.
            if (!isSyntheticChannel(_channel))
              PositionedDirectional(
                bottom: 8 + padding.bottom + (showStrip ? 132 : 0),
                end: 8 + padding.right,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    RecordNowButton(channel: _channel),
                    const SizedBox(width: 8),
                    LocalRecordButton(
                      recording: _localRecording,
                      onPressed: () => unawaited(_toggleLocalRecording()),
                    ),
                  ],
                ),
              ),
            if (immersive)
              Align(
                alignment: Alignment.bottomCenter,
                child: DecoratedBox(
                  decoration: const BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.bottomCenter,
                      end: Alignment.topCenter,
                      colors: <Color>[Color(0xE6000000), Color(0x00000000)],
                    ),
                  ),
                  child: Padding(
                    padding: EdgeInsets.fromLTRB(
                      64 + padding.left,
                      28,
                      16 + padding.right,
                      8 + padding.bottom,
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        if (current != null) ...<Widget>[
                          BidiText(
                            current.title,
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
              current.title,
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
                          next.title,
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

enum _OsdKind { brightness, volume }

class _GestureOsd extends StatelessWidget {
  const _GestureOsd({
    required this.kind,
    required this.value,
    required this.strings,
  });

  final _OsdKind kind;
  final double value;
  final AppStrings strings;

  @override
  Widget build(BuildContext context) {
    final brightness = kind == _OsdKind.brightness;
    final percent = (value * 100).round();
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
