import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/platform.dart';
import '../../core/theme.dart';
import '../../data/app_state.dart';
import '../../data/models.dart';
import '../../l10n/strings.dart';
import '../player_page.dart';
import '../widgets/channel_row.dart';
import '../widgets/channel_tile.dart';
import '../widgets/empty_state.dart';
import 'channel_guide_page.dart';

/// Favorites on their own page, with what was watched last underneath.
class FavoritesPage extends StatelessWidget {
  const FavoritesPage({super.key});

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final strings = context.strings;
    final colors = context.mawjColors;
    final theme = Theme.of(context);
    final allowInsecure = state.activeSource?.allowInsecureCerts ?? false;
    final favorites = state.favorites;
    final favoriteIds = favorites.map((channel) => channel.id).toSet();
    final recents = state.recents
        .where((channel) => !favoriteIds.contains(channel.id))
        .toList(growable: false);

    Widget item(Channel channel) {
      final programme = state.epg.nowFor(channel, state.now);
      final next = state.epg.nextFor(channel, state.now);
      return ChannelRow(
        channel: channel,
        programme: programme,
        next: next,
        now: state.now,
        allowInsecure: allowInsecure,
        favorite: state.isFavorite(channel),
        onTap: () => openPlayer(context, channel),
        onOpenGuide: () => ChannelGuidePage.open(context, channel),
        onToggleFavorite: () => unawaited(state.toggleFavorite(channel)),
      );
    }

    Widget section(String title, List<Channel> channels) {
      return SliverMainAxisGroup(
        slivers: <Widget>[
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(4, 18, 4, 10),
              child: Text(
                title,
                style: theme.textTheme.titleSmall?.copyWith(
                  color: colors.subtext0,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ),
          if (kIsDesktop)
            SliverGrid.builder(
              gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                maxCrossAxisExtent: 320,
                mainAxisExtent: kChannelTileHeight,
                mainAxisSpacing: 16,
                crossAxisSpacing: 16,
              ),
              itemCount: channels.length,
              itemBuilder: (context, index) {
                final channel = channels[index];
                return ChannelTile(
                  channel: channel,
                  programme: state.epg.nowFor(channel, state.now),
                  next: state.epg.nextFor(channel, state.now),
                  now: state.now,
                  allowInsecure: allowInsecure,
                  favorite: state.isFavorite(channel),
                  onPlay: () => openPlayer(context, channel),
                  onOpenGuide: () => ChannelGuidePage.open(context, channel),
                  onToggleFavorite: () =>
                      unawaited(state.toggleFavorite(channel)),
                );
              },
            )
          else
            SliverList.separated(
              itemCount: channels.length,
              separatorBuilder: (context, index) => const SizedBox(height: 12),
              itemBuilder: (context, index) => item(channels[index]),
            ),
        ],
      );
    }

    return SafeArea(
      bottom: false,
      child: CustomScrollView(
        slivers: <Widget>[
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 14, 20, 4),
              child: Text(
                strings.favorites,
                style: theme.textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.w800,
                  letterSpacing: -0.3,
                ),
              ),
            ),
          ),
          if (favorites.isEmpty && recents.isEmpty)
            SliverFillRemaining(
              hasScrollBody: false,
              child: EmptyState(
                icon: Icons.star_outline_rounded,
                title: strings.noFavorites,
                body: strings.noFavoritesBody,
              ),
            )
          else
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 120),
              sliver: SliverMainAxisGroup(
                slivers: <Widget>[
                  if (favorites.isNotEmpty) section(strings.favorites, favorites),
                  if (recents.isNotEmpty)
                    section(strings.recentlyWatched, recents),
                ],
              ),
            ),
        ],
      ),
    );
  }
}
