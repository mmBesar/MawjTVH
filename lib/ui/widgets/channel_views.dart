import 'package:flutter/material.dart';

import '../../core/bidi.dart';
import '../../core/theme.dart';
import '../../data/models.dart';
import 'channel_logo.dart';

/// Height of [ChannelWallTile] and [ChannelCompactRow].
const double kChannelWallHeight = 196;
const double kChannelCompactHeight = 64;

/// A big-logo tile for the "wall" view: many channels at a glance.
class ChannelWallTile extends StatelessWidget {
  const ChannelWallTile({
    super.key,
    required this.channel,
    required this.programme,
    required this.now,
    required this.allowInsecure,
    required this.favorite,
    required this.onTap,
    required this.onToggleFavorite,
    this.onOpenGuide,
  });

  final Channel channel;
  final Programme? programme;
  final DateTime now;
  final bool allowInsecure;
  final bool favorite;
  final VoidCallback onTap;
  final VoidCallback onToggleFavorite;
  final VoidCallback? onOpenGuide;

  @override
  Widget build(BuildContext context) {
    final colors = context.mawjColors;
    final theme = Theme.of(context);
    final current = programme;
    return Material(
      color: colors.surface0.withValues(alpha: 0.62),
      borderRadius: BorderRadius.circular(22),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        onLongPress: onOpenGuide,
        onSecondaryTap: onOpenGuide,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
          child: Column(
            children: <Widget>[
              Row(
                children: <Widget>[
                  Text(
                    channel.displayNumber,
                    style: theme.textTheme.labelMedium?.copyWith(
                      color: colors.subtext0,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const Spacer(),
                  InkWell(
                    onTap: onToggleFavorite,
                    borderRadius: BorderRadius.circular(99),
                    child: Padding(
                      padding: const EdgeInsets.all(2),
                      child: Icon(
                        favorite
                            ? Icons.star_rounded
                            : Icons.star_outline_rounded,
                        size: 20,
                        color: favorite ? colors.accent : colors.overlay1,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              ChannelLogo(
                channel: channel,
                allowInsecure: allowInsecure,
                size: 72,
                radius: 18,
              ),
              const SizedBox(height: 10),
              BidiText(
                channel.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                style: theme.textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 2),
              if (current != null)
                BidiText(
                  current.displayTitle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: colors.subtext0,
                  ),
                ),
              const Spacer(),
              if (current != null)
                ClipRRect(
                  borderRadius: BorderRadius.circular(99),
                  child: LinearProgressIndicator(
                    value: current.progressAt(now),
                    minHeight: 4,
                    color: colors.accent,
                    backgroundColor: colors.surface2,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// A dense one-line row for the "compact" view.
class ChannelCompactRow extends StatelessWidget {
  const ChannelCompactRow({
    super.key,
    required this.channel,
    required this.programme,
    required this.now,
    required this.allowInsecure,
    required this.favorite,
    required this.onTap,
    required this.onToggleFavorite,
    this.onOpenGuide,
  });

  final Channel channel;
  final Programme? programme;
  final DateTime now;
  final bool allowInsecure;
  final bool favorite;
  final VoidCallback onTap;
  final VoidCallback onToggleFavorite;
  final VoidCallback? onOpenGuide;

  @override
  Widget build(BuildContext context) {
    final colors = context.mawjColors;
    final theme = Theme.of(context);
    final current = programme;
    return Material(
      color: colors.surface0.withValues(alpha: 0.55),
      borderRadius: BorderRadius.circular(14),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        onLongPress: onOpenGuide,
        onSecondaryTap: onOpenGuide,
        child: Stack(
          children: <Widget>[
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10),
              child: Row(
                children: <Widget>[
                  SizedBox(
                    width: 36,
                    child: Text(
                      channel.displayNumber,
                      style: theme.textTheme.labelMedium?.copyWith(
                        color: colors.subtext0,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                  ChannelLogo(
                    channel: channel,
                    allowInsecure: allowInsecure,
                    size: 38,
                    radius: 10,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
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
                        if (current != null)
                          BidiText(
                            current.displayTitle,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: colors.subtext0,
                            ),
                          ),
                      ],
                    ),
                  ),
                  InkWell(
                    onTap: onToggleFavorite,
                    borderRadius: BorderRadius.circular(99),
                    child: Padding(
                      padding: const EdgeInsets.all(4),
                      child: Icon(
                        favorite
                            ? Icons.star_rounded
                            : Icons.star_outline_rounded,
                        size: 20,
                        color: favorite ? colors.accent : colors.overlay1,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            if (current != null)
              Positioned(
                left: 0,
                right: 0,
                bottom: 0,
                child: LinearProgressIndicator(
                  value: current.progressAt(now),
                  minHeight: 2.5,
                  color: colors.accent,
                  backgroundColor: Colors.transparent,
                ),
              ),
          ],
        ),
      ),
    );
  }
}
