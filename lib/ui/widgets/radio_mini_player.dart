import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/bidi.dart';
import '../../core/theme.dart';
import '../../data/app_state.dart';
import '../../l10n/strings.dart';
import '../../l10n/tvh_strings.dart';
import '../pages/radio_now_playing_page.dart';
import 'audio_bars.dart';
import 'channel_logo.dart';

/// The bar that appears above the navigation while a radio station is loaded:
/// station, what is on, play/pause and stop. It slides in and out, a tap opens
/// the full player, and a swipe down stops the radio.
class RadioMiniPlayer extends StatelessWidget {
  const RadioMiniPlayer({super.key});

  @override
  Widget build(BuildContext context) {
    final state = context.read<AppState>();
    final radio = state.radio;
    return ListenableBuilder(
      listenable: Listenable.merge(<Listenable>[radio, state]),
      builder: (context, child) {
        final channel = radio.channel;
        return AnimatedSwitcher(
          duration: const Duration(milliseconds: 260),
          switchInCurve: Curves.easeOutCubic,
          switchOutCurve: Curves.easeInCubic,
          transitionBuilder: (child, animation) => SlideTransition(
            position: Tween<Offset>(
              begin: const Offset(0, 1.2),
              end: Offset.zero,
            ).animate(animation),
            child: FadeTransition(opacity: animation, child: child),
          ),
          child: channel == null
              ? const SizedBox.shrink(key: ValueKey<String>('none'))
              : _Bar(
                  key: const ValueKey<String>('bar'),
                  state: state,
                ),
        );
      },
    );
  }
}

class _Bar extends StatelessWidget {
  const _Bar({super.key, required this.state});

  final AppState state;

  @override
  Widget build(BuildContext context) {
    final radio = state.radio;
    final channel = radio.channel;
    if (channel == null) {
      return const SizedBox.shrink();
    }
    final colors = context.mawjColors;
    final theme = Theme.of(context);
    final strings = context.strings;
    final programme = state.epg.nowFor(channel, state.now);
    final subtitle = radio.error != null
        ? strings.radioFailed(radio.error!)
        : radio.buffering
            ? strings.radioConnecting
            : (!radio.playing
                ? strings.radioPaused
                : (programme?.displayTitle ?? strings.live));
    final allowInsecure = state.activeSource?.allowInsecureCerts ?? false;

    return GestureDetector(
      onVerticalDragEnd: (details) {
        final velocity = details.primaryVelocity ?? 0;
        if (velocity > 500) {
          unawaited(radio.stop());
        } else if (velocity < -500) {
          unawaited(RadioNowPlayingPage.open(context));
        }
      },
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 560),
        child: Material(
          color: colors.surface1,
          elevation: 6,
          shadowColor: Colors.black.withValues(alpha: 0.4),
          borderRadius: BorderRadius.circular(22),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: () => unawaited(RadioNowPlayingPage.open(context)),
            child: Padding(
              padding: const EdgeInsetsDirectional.fromSTEB(10, 8, 6, 8),
              child: Row(
                children: <Widget>[
                  ChannelLogo(
                    channel: channel,
                    allowInsecure: allowInsecure,
                    size: 46,
                    radius: 12,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        BidiText(
                          channel.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.titleSmall?.copyWith(
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        const SizedBox(height: 2),
                        BidiText(
                          subtitle,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: radio.error != null
                                ? theme.colorScheme.error
                                : colors.subtext0,
                          ),
                        ),
                      ],
                    ),
                  ),
                  AudioBars(
                    playing: radio.playing && !radio.buffering,
                    color: colors.accent,
                    bars: 4,
                    height: 18,
                    barWidth: 3,
                    gap: 2,
                    animate: !state.settings.reduceMotion,
                  ),
                  const SizedBox(width: 4),
                  IconButton(
                    tooltip: radio.playing ? strings.pause : strings.play,
                    onPressed: () => unawaited(radio.toggle()),
                    icon: radio.buffering
                        ? const SizedBox(
                            width: 22,
                            height: 22,
                            child: CircularProgressIndicator(strokeWidth: 2.4),
                          )
                        : Icon(
                            radio.playing
                                ? Icons.pause_rounded
                                : Icons.play_arrow_rounded,
                            size: 30,
                          ),
                  ),
                  IconButton(
                    tooltip: strings.stopRadio,
                    onPressed: () => unawaited(radio.stop()),
                    icon: const Icon(Icons.close_rounded),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
