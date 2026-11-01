import 'package:flutter/material.dart';

import '../../core/bidi.dart';
import '../../core/theme.dart';
import '../../data/models.dart';
import '../../l10n/strings.dart';
import 'channel_art.dart';
import 'channel_logo.dart';
import 'programme_poster.dart';
import 'wave.dart';

/// Fixed height of [ChannelTile]; grids use it as their main-axis extent.
const double kChannelTileHeight = 332;

/// A desktop channel card: a wide thumbnail (the programme's artwork, or the
/// channel's colours and logo), then name, what is on and how far in it is.
/// Clicking the thumbnail plays; clicking the text opens the channel guide.
class ChannelTile extends StatefulWidget {
  const ChannelTile({
    super.key,
    required this.channel,
    required this.programme,
    required this.now,
    required this.allowInsecure,
    required this.favorite,
    required this.onPlay,
    required this.onOpenGuide,
    required this.onToggleFavorite,
    this.next,
  });

  final Channel channel;
  final Programme? programme;
  final Programme? next;
  final DateTime now;
  final bool allowInsecure;
  final bool favorite;
  final VoidCallback onPlay;
  final VoidCallback onOpenGuide;
  final VoidCallback onToggleFavorite;

  @override
  State<ChannelTile> createState() => _ChannelTileState();
}

class _ChannelTileState extends State<ChannelTile> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final colors = context.mawjColors;
    final theme = Theme.of(context);
    final strings = context.strings;
    final programme = widget.programme;
    final art = programme?.iconUrl;
    final hasArt = art != null && art.trim().isNotEmpty;
    final gradient = channelGradient(widget.channel.id, dark: true);

    return MouseRegion(
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 140),
        decoration: BoxDecoration(
          color: colors.surface0.withValues(alpha: _hover ? 0.95 : 0.62),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(
            color: _hover ? colors.accent.withValues(alpha: 0.7) : Colors.transparent,
            width: 1.5,
          ),
        ),
        clipBehavior: Clip.antiAlias,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Expanded(
              child: Tooltip(
                message: strings.watchChannel,
                waitDuration: const Duration(milliseconds: 600),
                child: InkWell(
                  onTap: widget.onPlay,
                  child: Stack(
                    fit: StackFit.expand,
                    children: <Widget>[
                      if (hasArt)
                        LayoutBuilder(
                          builder: (context, constraints) {
                            return ProgrammePoster(
                              programme: programme!,
                              allowInsecure: widget.allowInsecure,
                              width: constraints.maxWidth,
                              height: constraints.maxHeight,
                              radius: 0,
                            );
                          },
                        )
                      else
                        DecoratedBox(
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                              colors: gradient,
                            ),
                          ),
                          child: Center(
                            child: ChannelLogo(
                              channel: widget.channel,
                              allowInsecure: widget.allowInsecure,
                              size: 64,
                              radius: 18,
                            ),
                          ),
                        ),
                      if (hasArt)
                        PositionedDirectional(
                          start: 10,
                          bottom: 10,
                          child: ChannelLogo(
                            channel: widget.channel,
                            allowInsecure: widget.allowInsecure,
                            size: 36,
                            radius: 10,
                          ),
                        ),
                      Center(
                        child: AnimatedOpacity(
                          opacity: _hover ? 1 : 0,
                          duration: const Duration(milliseconds: 140),
                          child: DecoratedBox(
                            decoration: BoxDecoration(
                              color: colors.accent,
                              shape: BoxShape.circle,
                            ),
                            child: Padding(
                              padding: const EdgeInsets.all(10),
                              child: Icon(
                                Icons.play_arrow_rounded,
                                size: 30,
                                color: theme.colorScheme.onPrimary,
                              ),
                            ),
                          ),
                        ),
                      ),
                      PositionedDirectional(
                        top: 4,
                        end: 4,
                        child: IconButton(
                          tooltip: widget.favorite
                              ? strings.removeFavorite
                              : strings.addFavorite,
                          onPressed: widget.onToggleFavorite,
                          style: IconButton.styleFrom(
                            backgroundColor: Colors.black.withValues(alpha: 0.4),
                          ),
                          icon: Icon(
                            widget.favorite
                                ? Icons.star_rounded
                                : Icons.star_outline_rounded,
                            color: widget.favorite ? colors.accent : Colors.white,
                            size: 20,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            InkWell(
              onTap: widget.onOpenGuide,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(14, 10, 14, 12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Row(
                      children: <Widget>[
                        Text(
                          widget.channel.displayNumber,
                          style: theme.textTheme.labelMedium?.copyWith(
                            color: colors.accent,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: BidiText(
                            widget.channel.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.titleSmall?.copyWith(
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 2),
                    BidiText(
                      programme?.title ??
                          widget.channel.group ??
                          strings.noProgrammeInfo,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: colors.subtext1,
                      ),
                    ),
                    if (programme?.subTitle != null)
                      BidiText(
                        programme!.subTitle!,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: colors.subtext0,
                        ),
                      ),
                    const SizedBox(height: 4),
                    SizedBox(
                      height: 14,
                      child: programme == null
                          ? null
                          : WaveProgress(
                              progress: programme.progressAt(widget.now),
                              color: colors.accent,
                              trackColor: colors.surface2,
                              height: 14,
                            ),
                    ),
                    if (widget.next != null) ...<Widget>[
                      const SizedBox(height: 4),
                      BidiText(
                        widget.next!.subTitle == null
                            ? '${strings.next} · ${widget.next!.title}'
                            : '${strings.next} · ${widget.next!.title} — ${widget.next!.subTitle}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: colors.overlay1,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
