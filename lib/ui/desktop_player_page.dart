import 'dart:async';
import 'dart:io' show Platform;
import 'dart:ui' show AppExitResponse;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../core/app_info.dart';
import '../core/bidi.dart';
import '../core/theme.dart';
import '../data/app_state.dart';
import '../data/local_recorder.dart';
import '../data/models.dart';
import '../data/mpv_runtime.dart';
import '../l10n/strings.dart';
import '../l10n/tvh_strings.dart';
import 'player_page.dart';
import 'widgets/channel_art.dart';
import 'widgets/channel_logo.dart';
import 'widgets/record_now_button.dart';
import 'widgets/signal_badge.dart';
import 'widgets/wave.dart';

enum _Phase { starting, playing, failed, closed }

/// The desktop player: the video plays in its own native mpv window (GPU
/// decoding, real fullscreen, mpv's own controls) and this page is the remote
/// control beside it: what is on, what is next, and quick channel switching.
class NowPlayingPage extends StatefulWidget {
  const NowPlayingPage({
    super.key,
    required this.channel,
    required this.capabilities,
  });

  final Channel channel;
  final MpvCapabilities capabilities;

  @override
  State<NowPlayingPage> createState() => _NowPlayingPageState();
}

class _NowPlayingPageState extends State<NowPlayingPage> {
  late Channel _channel;
  late AppState _appState;
  MpvSession? _session;
  AppLifecycleListener? _lifecycle;
  Timer? _decoderTimer;
  _Phase _phase = _Phase.starting;
  String? _decoder;
  int _generation = 0;
  MpvSession? _lastSession;
  DateTime _startedAt = DateTime.now();
  StreamRecorder? _recorder;
  bool get _localRecording => _recorder != null;

  @override
  void initState() {
    super.initState();
    _channel = widget.channel;
    _appState = context.read<AppState>();
    _lifecycle = AppLifecycleListener(
      onExitRequested: () async {
        _session?.kill();
        return AppExitResponse.exit;
      },
      onDetach: () => _session?.kill(),
    );
    unawaited(_start());
  }

  Future<void> _start() async {
    final state = context.read<AppState>();
    final settings = state.settings;
    final allowInsecure = state.activeSource?.allowInsecureCerts ?? false;
    final generation = ++_generation;
    _decoderTimer?.cancel();
    setState(() {
      _phase = _Phase.starting;
      _decoder = null;
      _startedAt = DateTime.now();
    });
    unawaited(state.markWatched(_channel));

    try {
      final session = await MpvRuntime.start(
        capabilities: widget.capabilities,
        url: _channel.url,
        title: 'MawjTVH · ${_channel.name}',
        hwdec: settings.hwdec,
        videoOutput: settings.videoOutput,
        allowInsecure: allowInsecure,
        useUserConfig: settings.useMpvConfig,
        fullscreen: settings.startFullscreen,
      );
      if (!mounted || generation != _generation) {
        session.kill();
        return;
      }
      _session = session;
      _lastSession = session;
      setState(() => _phase = _Phase.playing);
      _scheduleDecoderProbe(session, generation);
      unawaited(session.exitCode.then((code) => _onExit(session, code)));
    } catch (error) {
      debugPrint('Could not start mpv: $error');
      if (mounted && generation == _generation) {
        setState(() => _phase = _Phase.failed);
      }
    }
  }

  void _scheduleDecoderProbe(MpvSession session, int generation) {
    _decoderTimer?.cancel();
    _decoderTimer = Timer(const Duration(seconds: 4), () async {
      final value = await session.property('hwdec-current');
      if (!mounted || generation != _generation) {
        return;
      }
      setState(() => _decoder = (value is String) ? value : null);
    });
  }

  void _onExit(MpvSession session, int code) {
    if (!mounted || !identical(_session, session)) {
      return;
    }
    _decoderTimer?.cancel();
    _session = null;
    final quick = DateTime.now().difference(_startedAt) <
        const Duration(seconds: 6);
    if (code == 0 && !quick) {
      // The person closed the player window: go back to the list.
      Navigator.of(context).maybePop();
      return;
    }
    setState(() => _phase = code == 0 ? _Phase.closed : _Phase.failed);
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
    _switchTo(list[((from + delta) % list.length + list.length) % list.length]);
  }

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
    final session = _session;
    if (session == null || _phase != _Phase.playing) {
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

  Future<void> _switchTo(Channel channel) async {
    if (channel.id == _channel.id && _phase == _Phase.playing) {
      return;
    }
    await _stopLocalRecording(silent: true);
    if (!mounted) {
      return;
    }
    final previous = _channel;
    setState(() {
      _channel = channel;
      _decoder = null;
    });
    final session = _session;
    if (session != null && _phase == _Phase.playing) {
      unawaited(_appState.markWatched(channel));
      await session.load(channel.url, 'MawjTVH · ${channel.name}');
      if (mounted) {
        _scheduleDecoderProbe(session, _generation);
      }
    } else {
      await _start();
    }
    // The old channel's tuner is only needed until the new one has loaded.
    _appState.releaseStream(previous);
  }

  Future<void> _stop() async {
    _generation++;
    final session = _session;
    _session = null;
    await session?.stop();
    if (mounted) {
      Navigator.of(context).maybePop();
    }
  }

  String _diagnostics() {
    final buffer = StringBuffer()
      ..writeln('MawjTVH $kAppVersion')
      ..writeln('${Platform.operatingSystem} ${Platform.operatingSystemVersion}')
      ..writeln('mpv: ${widget.capabilities.path} (${widget.capabilities.version})')
      ..writeln('hwdecs: ${widget.capabilities.hwdecs.join(', ')}')
      ..writeln('Channel: ${_channel.number} ${_channel.name}')
      ..writeln('Decoder in use: ${_decoder ?? '-'}')
      ..writeln('Phase: ${_phase.name}');
    final session = _session ?? _lastSession;
    if (session != null) {
      buffer
        ..writeln('Arguments: ${session.arguments.join(' ')}')
        ..writeln()
        ..writeAll(session.log, '\n');
    }
    return buffer.toString();
  }

  Future<void> _copyDiagnostics() async {
    await Clipboard.setData(ClipboardData(text: _diagnostics()));
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(context.strings.copied)),
      );
    }
  }

  @override
  void dispose() {
    _generation++;
    _decoderTimer?.cancel();
    _lifecycle?.dispose();
    _appState.releaseStream(_channel);
    final recorder = _recorder;
    _recorder = null;
    if (recorder != null) {
      unawaited(recorder.stop());
    }
    final session = _session;
    _session = null;
    if (session != null) {
      unawaited(session.stop());
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final strings = context.strings;
    final colors = context.mawjColors;
    final theme = Theme.of(context);
    final favorite = state.isFavorite(_channel);
    final allowInsecure = state.activeSource?.allowInsecureCerts ?? false;
    final gradient = channelGradient(_channel.id, dark: true);

    final String status;
    final IconData statusIcon;
    switch (_phase) {
      case _Phase.starting:
        status = strings.startingPlayer;
        statusIcon = Icons.hourglass_top_rounded;
      case _Phase.playing:
        status = strings.playingInWindow;
        statusIcon = Icons.play_circle_rounded;
      case _Phase.closed:
        status = strings.playerClosed;
        statusIcon = Icons.stop_circle_rounded;
      case _Phase.failed:
        status = strings.playerFailed;
        statusIcon = Icons.error_outline_rounded;
    }

    final controls = Wrap(
      alignment: WrapAlignment.center,
      spacing: 10,
      runSpacing: 10,
      children: <Widget>[
        IconButton.filledTonal(
          tooltip: strings.previousChannel,
          onPressed: () => _zap(-1),
          icon: const Icon(Icons.skip_previous_rounded),
        ),
        if (_phase == _Phase.playing)
          IconButton.filled(
            tooltip: strings.pause,
            onPressed: () => unawaited(_session?.togglePause() ?? Future<void>.value()),
            icon: const Icon(Icons.pause_rounded),
          )
        else
          IconButton.filled(
            tooltip: strings.playbackRetry,
            onPressed: _phase == _Phase.starting ? null : () => unawaited(_start()),
            icon: const Icon(Icons.play_arrow_rounded),
          ),
        IconButton.filledTonal(
          tooltip: strings.nextChannel,
          onPressed: () => _zap(1),
          icon: const Icon(Icons.skip_next_rounded),
        ),
        IconButton.filledTonal(
          tooltip: strings.toggleFullscreen,
          onPressed: _phase == _Phase.playing
              ? () => unawaited(
                    _session?.command(const <Object>['cycle', 'fullscreen']) ??
                        Future<void>.value(),
                  )
              : null,
          icon: const Icon(Icons.fullscreen_rounded),
        ),
        IconButton.filledTonal(
          tooltip: favorite ? strings.removeFavorite : strings.addFavorite,
          onPressed: () => unawaited(state.toggleFavorite(_channel)),
          icon: Icon(
            favorite ? Icons.star_rounded : Icons.star_outline_rounded,
            color: favorite ? colors.accent : null,
          ),
        ),
        if (!isSyntheticChannel(_channel))
          RecordNowButton(channel: _channel, dark: false),
        if (!isSyntheticChannel(_channel))
          LocalRecordButton(
            recording: _localRecording,
            dark: false,
            onPressed: () => unawaited(_toggleLocalRecording()),
          ),
        IconButton.filledTonal(
          tooltip: strings.copyDiagnostics,
          onPressed: () => unawaited(_copyDiagnostics()),
          icon: const Icon(Icons.monitor_heart_outlined),
        ),
        IconButton.filledTonal(
          tooltip: strings.stopPlayback,
          onPressed: () => unawaited(_stop()),
          icon: const Icon(Icons.stop_rounded),
        ),
      ],
    );

    final left = Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: gradient,
        ),
      ),
      padding: const EdgeInsets.all(32),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: <Widget>[
          ChannelLogo(
            channel: _channel,
            allowInsecure: allowInsecure,
            size: 112,
            radius: 28,
          ),
          const SizedBox(height: 22),
          BidiText(
            _channel.name,
            maxLines: 2,
            textAlign: TextAlign.center,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.headlineSmall?.copyWith(
              fontWeight: FontWeight.w800,
              color: Colors.white,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            '${strings.channel} ${_channel.displayNumber}',
            style: theme.textTheme.bodyMedium?.copyWith(color: Colors.white70),
          ),
          const SizedBox(height: 10),
          SignalBadge(channel: _channel),
          const SizedBox(height: 22),
          SizedBox(
            width: 160,
            child: WaveProgress(
              progress: 1,
              color: Colors.white,
              trackColor: Colors.white24,
              height: 26,
              animate: _phase == _Phase.starting,
              forceAnimate: true,
            ),
          ),
          const SizedBox(height: 14),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Icon(statusIcon, size: 18, color: Colors.white),
              const SizedBox(width: 8),
              Text(
                status,
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
          if (_phase == _Phase.playing) ...<Widget>[
            const SizedBox(height: 6),
            Text(
              strings.decodingWith(
                _decoder == null || _decoder == 'no'
                    ? strings.softwareDecoding
                    : _decoder!,
              ),
              style: const TextStyle(color: Colors.white70, fontSize: 12),
            ),
          ],
          const SizedBox(height: 26),
          controls,
        ],
      ),
    );

    return CallbackShortcuts(
      bindings: <ShortcutActivator, VoidCallback>{
        const SingleActivator(LogicalKeyboardKey.escape): () =>
            Navigator.of(context).maybePop(),
        const SingleActivator(LogicalKeyboardKey.arrowUp): () => _zap(-1),
        const SingleActivator(LogicalKeyboardKey.pageUp): () => _zap(-1),
        const SingleActivator(LogicalKeyboardKey.arrowDown): () => _zap(1),
        const SingleActivator(LogicalKeyboardKey.pageDown): () => _zap(1),
        const SingleActivator(LogicalKeyboardKey.space): () =>
            unawaited(_session?.togglePause() ?? Future<void>.value()),
      },
      child: Focus(
        autofocus: true,
        child: Scaffold(
          backgroundColor: colors.base,
          appBar: AppBar(
            backgroundColor: colors.mantle,
            title: Text(strings.watch),
            actions: <Widget>[
              if (_phase == _Phase.failed)
                TextButton.icon(
                  onPressed: () => unawaited(_start()),
                  icon: const Icon(Icons.refresh_rounded),
                  label: Text(strings.playbackRetry),
                ),
              const SizedBox(width: 8),
            ],
          ),
          body: Row(
            children: <Widget>[
              SizedBox(width: 380, child: left),
              Expanded(
                child: Column(
                  children: <Widget>[
                    Expanded(child: PlayerInfoPanel(channel: _channel)),
                    PlayerChannelStrip(
                      channels: _zapList(state),
                      current: _channel,
                      allowInsecure: allowInsecure,
                      onSelected: (channel) => unawaited(_switchTo(channel)),
                    ),
                    const SizedBox(height: 8),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
