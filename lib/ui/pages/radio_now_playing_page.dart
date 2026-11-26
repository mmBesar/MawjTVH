import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/bidi.dart';
import '../../core/theme.dart';
import '../../data/app_state.dart';
import '../../data/radio_player.dart';
import '../../l10n/strings.dart';
import '../../l10n/tvh_strings.dart';
import '../widgets/audio_bars.dart';
import '../widgets/channel_logo.dart';
import '../widgets/wave.dart';
import 'channel_guide_page.dart';

/// The radio as an audio player: big logo, what is on, transport buttons,
/// volume and a sleep timer. Swipe down (or the arrow) to put it away; the
/// station keeps playing.
class RadioNowPlayingPage extends StatelessWidget {
  const RadioNowPlayingPage({super.key});

  /// Slides the page up from the mini player.
  static Future<void> open(BuildContext context) {
    return Navigator.of(context).push<void>(
      PageRouteBuilder<void>(
        pageBuilder: (context, animation, secondaryAnimation) =>
            const RadioNowPlayingPage(),
        transitionsBuilder: (context, animation, secondaryAnimation, child) {
          return SlideTransition(
            position: Tween<Offset>(
              begin: const Offset(0, 1),
              end: Offset.zero,
            ).animate(
              CurvedAnimation(parent: animation, curve: Curves.easeOutCubic),
            ),
            child: child,
          );
        },
        transitionDuration: const Duration(milliseconds: 300),
        reverseTransitionDuration: const Duration(milliseconds: 240),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final state = context.read<AppState>();
    final radio = state.radio;
    final colors = context.mawjColors;
    final theme = Theme.of(context);
    final strings = context.strings;

    return ListenableBuilder(
      listenable: Listenable.merge(<Listenable>[radio, state]),
      builder: (context, child) {
        final channel = radio.channel;
        if (channel == null) {
          // Stopped from the notification while this page was open.
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (context.mounted && Navigator.of(context).canPop()) {
              Navigator.of(context).pop();
            }
          });
          return const Scaffold(body: SizedBox.shrink());
        }
        final programme = state.epg.nowFor(channel, state.now);
        final next = state.epg.nextFor(channel, state.now);
        final allowInsecure = state.activeSource?.allowInsecureCerts ?? false;
        final use24 = state.settings.use24HourTime;
        final status = radio.error != null
            ? strings.radioFailed(radio.error!)
            : radio.buffering
                ? strings.radioConnecting
                : (radio.playing ? strings.live : strings.radioPaused);

        return Scaffold(
          body: GestureDetector(
            behavior: HitTestBehavior.translucent,
            onVerticalDragEnd: (details) {
              if ((details.primaryVelocity ?? 0) > 600) {
                Navigator.of(context).pop();
              }
            },
            child: SafeArea(
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 520),
                  child: ListView(
                    padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
                    children: <Widget>[
                      Row(
                        children: <Widget>[
                          IconButton(
                            tooltip: strings.minimise,
                            onPressed: () => Navigator.of(context).pop(),
                            icon: const Icon(
                              Icons.keyboard_arrow_down_rounded,
                              size: 32,
                            ),
                          ),
                          Expanded(
                            child: Text(
                              strings.radioNowPlaying,
                              textAlign: TextAlign.center,
                              style: theme.textTheme.labelLarge?.copyWith(
                                color: colors.subtext0,
                                letterSpacing: 0.4,
                              ),
                            ),
                          ),
                          IconButton(
                            tooltip: strings.stopRadio,
                            onPressed: () => unawaited(radio.stop()),
                            icon: const Icon(Icons.stop_rounded),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      Center(
                        child: ChannelLogo(
                          channel: channel,
                          allowInsecure: allowInsecure,
                          size: 220,
                          radius: 36,
                        ),
                      ),
                      const SizedBox(height: 28),
                      Center(
                        child: AudioBars(
                          playing: radio.playing && !radio.buffering,
                          color: colors.accent,
                          bars: 9,
                          height: 36,
                          barWidth: 5,
                          gap: 4,
                          animate: !state.settings.reduceMotion,
                        ),
                      ),
                      const SizedBox(height: 20),
                      BidiText(
                        channel.name,
                        textAlign: TextAlign.center,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.headlineSmall?.copyWith(
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        status,
                        textAlign: TextAlign.center,
                        style: theme.textTheme.labelLarge?.copyWith(
                          color: radio.error != null
                              ? theme.colorScheme.error
                              : colors.accent,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 16),
                      if (programme != null) ...<Widget>[
                        BidiText(
                          programme.displayTitle,
                          textAlign: TextAlign.center,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.titleMedium,
                        ),
                        const SizedBox(height: 4),
                        BidiText(
                          strings.formatRange(
                            programme.start,
                            programme.stop,
                            use24HourTime: use24,
                          ),
                          textAlign: TextAlign.center,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: colors.subtext0,
                          ),
                        ),
                        const SizedBox(height: 10),
                        WaveProgress(
                          progress: programme.progressAt(state.now),
                          color: colors.accent,
                          trackColor: colors.surface2,
                          height: 16,
                          animate: !state.settings.reduceMotion,
                        ),
                        if (next != null) ...<Widget>[
                          const SizedBox(height: 10),
                          BidiText(
                            '${strings.upNext}: ${next.title}',
                            textAlign: TextAlign.center,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: colors.subtext0,
                            ),
                          ),
                        ],
                      ] else
                        Text(
                          strings.noProgrammeInfo,
                          textAlign: TextAlign.center,
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: colors.subtext0,
                          ),
                        ),
                      const SizedBox(height: 28),
                      _Transport(radio: radio),
                      const SizedBox(height: 20),
                      Row(
                        children: <Widget>[
                          Icon(Icons.volume_down_rounded, color: colors.subtext0),
                          Expanded(
                            child: Slider(
                              value: radio.volume,
                              min: 0,
                              max: 100,
                              onChanged: (value) =>
                                  unawaited(radio.setVolume(value)),
                            ),
                          ),
                          Icon(Icons.volume_up_rounded, color: colors.subtext0),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: <Widget>[
                          _SleepButton(radio: radio, use24: use24),
                          const SizedBox(width: 12),
                          OutlinedButton.icon(
                            onPressed: () =>
                                ChannelGuidePage.open(context, channel),
                            icon: const Icon(Icons.calendar_month_rounded),
                            label: Text(strings.guide),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

class _Transport extends StatelessWidget {
  const _Transport({required this.radio});

  final RadioPlayer radio;

  @override
  Widget build(BuildContext context) {
    final colors = context.mawjColors;
    final theme = Theme.of(context);
    final strings = context.strings;
    final skip = radio.canSkip;
    final playing = radio.playing;
    final busy = radio.buffering;
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: <Widget>[
        IconButton(
          iconSize: 38,
          tooltip: strings.previousStation,
          onPressed: skip ? () => unawaited(radio.previous()) : null,
          icon: const Icon(Icons.skip_previous_rounded),
        ),
        const SizedBox(width: 12),
        SizedBox(
          width: 84,
          height: 84,
          child: Material(
            color: colors.accent,
            shape: const CircleBorder(),
            clipBehavior: Clip.antiAlias,
            child: InkWell(
              onTap: () => unawaited(radio.toggle()),
              child: Center(
                child: busy
                    ? SizedBox(
                        width: 34,
                        height: 34,
                        child: CircularProgressIndicator(
                          strokeWidth: 3,
                          color: theme.colorScheme.onPrimary,
                        ),
                      )
                    : Icon(
                        playing
                            ? Icons.pause_rounded
                            : Icons.play_arrow_rounded,
                        size: 48,
                        color: theme.colorScheme.onPrimary,
                      ),
              ),
            ),
          ),
        ),
        const SizedBox(width: 12),
        IconButton(
          iconSize: 38,
          tooltip: strings.nextStation,
          onPressed: skip ? () => unawaited(radio.next()) : null,
          icon: const Icon(Icons.skip_next_rounded),
        ),
      ],
    );
  }
}

class _SleepButton extends StatelessWidget {
  const _SleepButton({required this.radio, required this.use24});

  final RadioPlayer radio;
  final bool use24;

  @override
  Widget build(BuildContext context) {
    final strings = context.strings;
    final at = radio.sleepAt;
    return PopupMenuButton<int>(
      tooltip: strings.sleepTimer,
      onSelected: (minutes) {
        radio.sleepIn(minutes == 0 ? null : Duration(minutes: minutes));
      },
      itemBuilder: (context) => <PopupMenuEntry<int>>[
        for (final minutes in const <int>[15, 30, 45, 60, 90])
          PopupMenuItem<int>(
            value: minutes,
            child: Text(strings.sleepInMinutes(minutes)),
          ),
        if (at != null)
          PopupMenuItem<int>(value: 0, child: Text(strings.sleepTimerOff)),
      ],
      child: Chip(
        avatar: Icon(
          at == null ? Icons.bedtime_outlined : Icons.bedtime_rounded,
          size: 18,
        ),
        label: Text(
          at == null
              ? strings.sleepTimer
              : strings.sleepAtTime(_clock(at, use24)),
        ),
      ),
    );
  }

  static String _clock(DateTime time, bool use24) {
    final minute = time.minute.toString().padLeft(2, '0');
    if (use24) {
      return '${time.hour.toString().padLeft(2, '0')}:$minute';
    }
    final hour = time.hour % 12 == 0 ? 12 : time.hour % 12;
    return '$hour:$minute ${time.hour < 12 ? 'AM' : 'PM'}';
  }
}
