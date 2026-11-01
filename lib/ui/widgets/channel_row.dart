import 'package:flutter/material.dart';

import '../../core/bidi.dart';
import '../../core/theme.dart';
import '../../data/models.dart';
import '../../l10n/strings.dart';
import 'channel_logo.dart';
import 'wave.dart';

/// Fixed height of [ChannelRow], so lists can use a fixed item extent.
const double kChannelRowHeight = 128;

/// One channel in a list: logo, name, what is on, and the wave showing how far
/// into it the channel is.
class ChannelRow extends StatelessWidget {
  const ChannelRow({
    super.key,
    required this.channel,
    required this.programme,
    required this.now,
    required this.allowInsecure,
    required this.favorite,
    required this.onTap,
    required this.onToggleFavorite,
    this.onOpenGuide,
    this.next,
  });

  final Channel channel;
  final Programme? programme;

  /// What follows [programme], shown under the progress wave.
  final Programme? next;
  final DateTime now;
  final bool allowInsecure;
  final bool favorite;
  /// Plays the channel (the logo).
  final VoidCallback onTap;
  final VoidCallback onToggleFavorite;

  /// Opens the channel's own guide (the name and programme). When null the
  /// whole row plays.
  final VoidCallback? onOpenGuide;

  @override
  Widget build(BuildContext context) {
    final colors = context.mawjColors;
    final theme = Theme.of(context);
    final strings = context.strings;
    final current = programme;

    return SizedBox(
      height: kChannelRowHeight,
      child: Material(
        color: colors.surface0.withValues(alpha: 0.62),
        borderRadius: BorderRadius.circular(22),
        clipBehavior: Clip.antiAlias,
        child: Padding(
            padding: const EdgeInsetsDirectional.fromSTEB(0, 0, 4, 0),
            child: Row(
              children: <Widget>[
                Tooltip(
                  message: strings.watchChannel,
                  child: InkWell(
                    onTap: onTap,
                    child: Padding(
                      padding: const EdgeInsetsDirectional.fromSTEB(12, 10, 12, 10),
                      child: Stack(
                        clipBehavior: Clip.none,
                        children: <Widget>[
                          ChannelLogo(
                            channel: channel,
                            allowInsecure: allowInsecure,
                            size: 60,
                            radius: 16,
                          ),
                          PositionedDirectional(
                            end: -4,
                            bottom: -4,
                            child: DecoratedBox(
                              decoration: BoxDecoration(
                                color: colors.accent,
                                shape: BoxShape.circle,
                                border: Border.all(
                                  color: colors.surface0,
                                  width: 2,
                                ),
                              ),
                              child: Padding(
                                padding: const EdgeInsets.all(3),
                                child: Icon(
                                  Icons.play_arrow_rounded,
                                  size: 14,
                                  color: theme.colorScheme.onPrimary,
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                Expanded(
                  child: InkWell(
                    onTap: onOpenGuide ?? onTap,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 10),
                      child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Row(
                        children: <Widget>[
                          Text(
                            channel.displayNumber,
                            style: theme.textTheme.labelMedium?.copyWith(
                              color: colors.accent,
                              fontWeight: FontWeight.w800,
                              fontFeatures: const <FontFeature>[
                                FontFeature.tabularFigures(),
                              ],
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: BidiText(
                              channel.name,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: theme.textTheme.titleSmall?.copyWith(
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 2),
                      if (current != null) ...<Widget>[
                        BidiText(
                          current.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: colors.text,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        if (current.subTitle != null)
                          BidiText(
                            current.subTitle!,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: colors.subtext0,
                            ),
                          ),
                        const SizedBox(height: 2),
                        WaveProgress(
                          progress: current.progressAt(now),
                          color: colors.accent,
                          trackColor: colors.surface2,
                          height: 14,
                        ),
                        if (next != null) ...<Widget>[
                          const SizedBox(height: 2),
                          BidiText(
                            next!.subTitle == null
                                ? '${strings.next} · ${next!.title}'
                                : '${strings.next} · ${next!.title} — ${next!.subTitle}',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: colors.overlay1,
                            ),
                          ),
                        ],
                      ] else
                        BidiText(
                          channel.group ?? strings.noProgrammeInfo,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: colors.overlay1,
                          ),
                        ),
                    ],
                  ),
                    ),
                  ),
                ),
                IconButton(
                  tooltip: favorite
                      ? strings.removeFavorite
                      : strings.addFavorite,
                  onPressed: onToggleFavorite,
                  icon: Icon(
                    favorite ? Icons.star_rounded : Icons.star_outline_rounded,
                    color: favorite ? colors.accent : colors.overlay1,
                  ),
                ),
              ],
            ),
          ),
      ),
    );
  }
}
