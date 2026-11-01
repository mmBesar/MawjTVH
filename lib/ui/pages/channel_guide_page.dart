import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/bidi.dart';
import '../../core/theme.dart';
import '../../data/app_state.dart';
import '../../data/models.dart';
import '../../l10n/strings.dart';
import '../player_page.dart';
import '../widgets/channel_logo.dart';
import '../widgets/empty_state.dart';
import '../widgets/programme_poster.dart';
import '../widgets/programme_sheet.dart';
import '../widgets/wave.dart';

/// The schedule of one channel: what is on now and everything after it, grouped
/// by day, with a wide thumbnail on every programme that has artwork.
class ChannelGuidePage extends StatelessWidget {
  const ChannelGuidePage({super.key, required this.channel});

  final Channel channel;

  static Future<void> open(BuildContext context, Channel channel) {
    return Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (context) => ChannelGuidePage(channel: channel),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final strings = context.strings;
    final colors = context.mawjColors;
    final theme = Theme.of(context);
    final now = state.now;
    final allowInsecure = state.activeSource?.allowInsecureCerts ?? false;
    final favorite = state.isFavorite(channel);

    // The programme on air and everything after it.
    final programmes = state.epg
        .programmesFor(channel)
        .where((programme) => programme.stop.isAfter(now))
        .toList(growable: false);

    final items = <Object>[];
    DateTime? lastDay;
    for (final programme in programmes) {
      final day = DateTime(
        programme.start.year,
        programme.start.month,
        programme.start.day,
      );
      if (lastDay == null || day != lastDay) {
        items.add(day);
        lastDay = day;
      }
      items.add(programme);
    }

    final today = DateTime(now.year, now.month, now.day);
    String dayLabel(DateTime day) {
      final difference = day.difference(today).inDays;
      if (difference <= 0) {
        return strings.today;
      }
      if (difference == 1) {
        return strings.tomorrow;
      }
      return strings.formatDate(day);
    }

    return Scaffold(
      backgroundColor: colors.base,
      appBar: AppBar(
        backgroundColor: colors.base,
        titleSpacing: 0,
        title: Row(
          children: <Widget>[
            InkWell(
              borderRadius: BorderRadius.circular(14),
              onTap: () => unawaited(openPlayer(context, channel)),
              child: ChannelLogo(
                channel: channel,
                allowInsecure: allowInsecure,
                size: 40,
                radius: 12,
              ),
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
                  Text(
                    strings.channelGuide,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: colors.subtext0,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        actions: <Widget>[
          IconButton(
            tooltip: favorite ? strings.removeFavorite : strings.addFavorite,
            onPressed: () => unawaited(state.toggleFavorite(channel)),
            icon: Icon(
              favorite ? Icons.star_rounded : Icons.star_outline_rounded,
              color: favorite ? colors.accent : colors.subtext0,
            ),
          ),
          Padding(
            padding: const EdgeInsetsDirectional.only(end: 12, start: 4),
            child: FilledButton.icon(
              onPressed: () => unawaited(openPlayer(context, channel)),
              icon: const Icon(Icons.play_arrow_rounded),
              label: Text(strings.watch),
            ),
          ),
        ],
      ),
      body: items.isEmpty
          ? EmptyState(
              icon: Icons.event_busy_rounded,
              title: strings.noUpcoming,
              body: strings.noProgrammeInfo,
            )
          : Align(
              alignment: Alignment.topCenter,
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 920),
                child: ListView.builder(
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 32),
                  itemCount: items.length,
                  itemBuilder: (context, index) {
                    final item = items[index];
                    if (item is DateTime) {
                      return Padding(
                        padding: const EdgeInsets.fromLTRB(4, 18, 4, 10),
                        child: Text(
                          dayLabel(item),
                          style: theme.textTheme.titleSmall?.copyWith(
                            color: colors.subtext0,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      );
                    }
                    return _ProgrammeCard(
                      channel: channel,
                      programme: item as Programme,
                      now: now,
                      allowInsecure: allowInsecure,
                      use24: state.settings.use24HourTime,
                    );
                  },
                ),
              ),
            ),
    );
  }
}

class _ProgrammeCard extends StatelessWidget {
  const _ProgrammeCard({
    required this.channel,
    required this.programme,
    required this.now,
    required this.allowInsecure,
    required this.use24,
  });

  final Channel channel;
  final Programme programme;
  final DateTime now;
  final bool allowInsecure;
  final bool use24;

  @override
  Widget build(BuildContext context) {
    final colors = context.mawjColors;
    final theme = Theme.of(context);
    final strings = context.strings;
    final live = programme.isLiveAt(now);
    final hasArt = programme.iconUrl != null && programme.iconUrl!.trim().isNotEmpty;

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Material(
        color: live
            ? colors.accent.withValues(alpha: 0.12)
            : colors.surface0.withValues(alpha: 0.55),
        borderRadius: BorderRadius.circular(20),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: () => showProgrammeSheet(
            context,
            channel: channel,
            programme: programme,
          ),
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                if (hasArt) ...<Widget>[
                  ProgrammePoster(
                    programme: programme,
                    allowInsecure: allowInsecure,
                    width: 176,
                    height: 99,
                    radius: 14,
                  ),
                  const SizedBox(width: 14),
                ],
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(
                        live
                            ? strings.now
                            : strings.formatRange(
                                programme.start,
                                programme.stop,
                                use24HourTime: use24,
                              ),
                        style: theme.textTheme.labelMedium?.copyWith(
                          color: live ? colors.accent : colors.subtext0,
                          fontWeight: FontWeight.w800,
                          fontFeatures: const <FontFeature>[
                            FontFeature.tabularFigures(),
                          ],
                        ),
                      ),
                      const SizedBox(height: 3),
                      BidiText(
                        programme.title,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      if (programme.subTitle != null) ...<Widget>[
                        const SizedBox(height: 2),
                        BidiText(
                          programme.subTitle!,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: colors.subtext0,
                          ),
                        ),
                      ],
                      if (live) ...<Widget>[
                        const SizedBox(height: 8),
                        WaveProgress(
                          progress: programme.progressAt(now),
                          color: colors.accent,
                          trackColor: colors.surface2,
                          height: 14,
                        ),
                      ] else if (programme.description != null) ...<Widget>[
                        const SizedBox(height: 6),
                        BidiText(
                          programme.description!,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: colors.subtext1,
                            height: 1.4,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
