import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/bidi.dart';
import '../../core/network_image.dart';
import '../../core/platform.dart';
import '../../core/theme.dart';
import '../../data/app_state.dart';
import '../../data/models.dart';
import '../../l10n/strings.dart';
import '../player_page.dart';
import '../widgets/channel_art.dart';
import '../widgets/channel_logo.dart';
import '../widgets/channel_row.dart';
import '../widgets/channel_tile.dart';
import '../widgets/empty_state.dart';
import '../widgets/error_banner.dart';
import '../widgets/source_switcher.dart';
import '../widgets/warnings_panel.dart';
import '../widgets/wave.dart';
import 'channel_guide_page.dart';
import 'search_page.dart';

/// The home screen: what is on now, then every channel.
class WatchPage extends StatefulWidget {
  const WatchPage({super.key, required this.onOpenSources});

  final VoidCallback onOpenSources;

  @override
  State<WatchPage> createState() => _WatchPageState();
}

class _WatchPageState extends State<WatchPage> {
  // Sentinels contain a NUL, which no group title can.
  static const String _all = '\u0000all';
  static const String _favorites = '\u0000fav';

  String _filter = _all;
  bool _favoritesActive = false;

  List<Channel> _heroChannels(AppState state) {
    final seen = <String>{};
    final result = <Channel>[];
    void add(Channel channel) {
      if (result.length < 8 && seen.add(channel.id)) {
        result.add(channel);
      }
    }

    state.recents.take(2).forEach(add);
    state.favorites.forEach(add);
    for (final channel in state.channels) {
      if (state.epg.nowFor(channel, state.now) != null) {
        add(channel);
      }
    }
    state.channels.forEach(add);
    return result;
  }

  List<Channel> _visible(AppState state) {
    if (_filter == _favorites) {
      return state.favorites;
    }
    return state.filteredChannels;
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final strings = context.strings;
    final colors = context.mawjColors;

    if (!state.restored) {
      return const SizedBox.shrink();
    }
    if (state.sources.isEmpty) {
      return _Welcome(onAdd: widget.onOpenSources);
    }

    // The group is shared with the Guide; favourites stay local to Watch.
    if (_favoritesActive && state.favorites.isEmpty) {
      _favoritesActive = false;
    }
    _filter = _favoritesActive ? _favorites : (state.groupFilter ?? _all);

    final channels = _visible(state);
    final loadingFirst = state.isLoading && state.channels.isEmpty;
    final allowInsecure = state.activeSource?.allowInsecureCerts ?? false;
    final hero = state.channels.isEmpty
        ? const <Channel>[]
        : _heroChannels(state);

    return RefreshIndicator(
      onRefresh: state.refresh,
      color: colors.accent,
      backgroundColor: colors.surface1,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final wide = constraints.maxWidth >= 760;
          final sidePadding = wide ? 24.0 : 16.0;
          return CustomScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            slivers: <Widget>[
              SliverToBoxAdapter(
                child: SafeArea(
                  bottom: false,
                  child: _Header(
                    sourceName: state.activeSource?.name ?? '',
                    loading: state.isLoading,
                    onRefresh: state.refresh,
                    onSearch: () => SearchPage.open(context, SearchScope.channels),
                    onOpenSources: () => showSourceSwitcher(
                      context,
                      onManage: widget.onOpenSources,
                    ),
                    padding: sidePadding,
                  ),
                ),
              ),
              if (state.error != null && state.channels.isEmpty)
                SliverToBoxAdapter(
                  child: ErrorBanner(
                    message: state.error!,
                    retryLabel: strings.retry,
                    onRetry: state.refresh,
                  ),
                ),
              SliverToBoxAdapter(
                child: WarningsPanel(warnings: state.warnings),
              ),
              if (hero.isNotEmpty)
                SliverToBoxAdapter(
                  child: _HeroStrip(
                    channels: hero,
                    state: state,
                    allowInsecure: allowInsecure,
                    padding: sidePadding,
                    cardWidth: wide
                        ? 440.0
                        : (constraints.maxWidth * 0.86)
                            .clamp(260.0, 440.0)
                            .toDouble(),
                  ),
                ),
              if (state.groups.isNotEmpty || state.favorites.isNotEmpty)
                SliverToBoxAdapter(
                  child: _FilterBar(
                    padding: sidePadding,
                    selected: _filter,
                    allKey: _all,
                    favoritesKey: _favorites,
                    groups: state.groups,
                    hasFavorites: state.favorites.isNotEmpty,
                    onSelected: (value) {
                      setState(() => _favoritesActive = value == _favorites);
                      if (value != _favorites) {
                        state.setGroupFilter(value == _all ? null : value);
                      }
                    },
                  ),
                ),
              if (loadingFirst)
                SliverPadding(
                  padding: EdgeInsets.symmetric(horizontal: sidePadding),
                  sliver: SliverList.builder(
                    itemCount: 6,
                    itemBuilder: (context, index) => const _Placeholder(),
                  ),
                )
              else if (state.channels.isEmpty)
                SliverFillRemaining(
                  hasScrollBody: false,
                  child: EmptyState(
                    icon: Icons.live_tv_rounded,
                    title: strings.noChannels,
                    body: state.error ?? strings.noChannelsBody,
                    actionLabel: strings.retry,
                    onAction: state.refresh,
                    secondaryLabel: strings.manageSources,
                    onSecondary: widget.onOpenSources,
                  ),
                )
              else if (channels.isEmpty)
                SliverFillRemaining(
                  hasScrollBody: false,
                  child: EmptyState(
                    icon: Icons.star_outline_rounded,
                    title: strings.noFavorites,
                    body: strings.noFavoritesBody,
                  ),
                )
              else if (wide && kIsDesktop)
                SliverPadding(
                  padding: EdgeInsets.fromLTRB(sidePadding, 4, sidePadding, 32),
                  sliver: SliverGrid.builder(
                    gridDelegate:
                        const SliverGridDelegateWithMaxCrossAxisExtent(
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
                        onOpenGuide: () =>
                            ChannelGuidePage.open(context, channel),
                        onToggleFavorite: () =>
                            unawaited(state.toggleFavorite(channel)),
                      );
                    },
                  ),
                )
              else if (wide)
                SliverPadding(
                  padding: EdgeInsets.fromLTRB(sidePadding, 4, sidePadding, 120),
                  sliver: SliverGrid.builder(
                    gridDelegate:
                        const SliverGridDelegateWithMaxCrossAxisExtent(
                      maxCrossAxisExtent: 460,
                      mainAxisExtent: kChannelRowHeight,
                      mainAxisSpacing: 12,
                      crossAxisSpacing: 12,
                    ),
                    itemCount: channels.length,
                    itemBuilder: (context, index) {
                      return _row(context, state, channels[index], allowInsecure);
                    },
                  ),
                )
              else
                SliverPadding(
                  padding: EdgeInsets.fromLTRB(sidePadding, 4, sidePadding, 120),
                  sliver: SliverFixedExtentList.builder(
                    itemExtent: kChannelRowHeight + 12,
                    itemCount: channels.length,
                    itemBuilder: (context, index) {
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: _row(
                          context,
                          state,
                          channels[index],
                          allowInsecure,
                        ),
                      );
                    },
                  ),
                ),
            ],
          );
        },
      ),
    );
  }

  Widget _row(
    BuildContext context,
    AppState state,
    Channel channel,
    bool allowInsecure,
  ) {
    return ChannelRow(
      channel: channel,
      programme: state.epg.nowFor(channel, state.now),
      next: state.epg.nextFor(channel, state.now),
      now: state.now,
      allowInsecure: allowInsecure,
      favorite: state.isFavorite(channel),
      onTap: () => openPlayer(context, channel),
      onOpenGuide: () => ChannelGuidePage.open(context, channel),
      onToggleFavorite: () => unawaited(state.toggleFavorite(channel)),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({
    required this.sourceName,
    required this.loading,
    required this.onRefresh,
    required this.onOpenSources,
    required this.onSearch,
    required this.padding,
  });

  final String sourceName;
  final bool loading;
  final Future<void> Function() onRefresh;
  final VoidCallback onOpenSources;
  final VoidCallback onSearch;
  final double padding;

  @override
  Widget build(BuildContext context) {
    final colors = context.mawjColors;
    final theme = Theme.of(context);
    final strings = context.strings;
    return Padding(
      padding: EdgeInsets.fromLTRB(padding, 12, padding - 8, 8),
      child: Row(
        children: <Widget>[
          ClipRRect(
            borderRadius: BorderRadius.circular(10),
            child: Image.asset(
              'assets/branding/mawjtvh_icon.png',
              width: 34,
              height: 34,
              filterQuality: FilterQuality.medium,
            ),
          ),
          const SizedBox(width: 10),
          Text(
            strings.appName,
            style: theme.textTheme.titleLarge?.copyWith(
              fontWeight: FontWeight.w800,
              letterSpacing: -0.4,
            ),
          ),
          const Spacer(),
          if (sourceName.isNotEmpty)
            Flexible(
              child: ActionChip(
                onPressed: onOpenSources,
                avatar: Icon(Icons.dns_rounded, size: 16, color: colors.accent),
                label: BidiText(
                  sourceName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                side: BorderSide(color: colors.surface1),
                backgroundColor: colors.surface0.withValues(alpha: 0.6),
              ),
            ),
          IconButton(
            tooltip: strings.searchChannels,
            onPressed: onSearch,
            icon: const Icon(Icons.search_rounded),
          ),
          IconButton(
            tooltip: strings.refresh,
            onPressed: loading ? null : () => unawaited(onRefresh()),
            icon: loading
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
    );
  }
}

class _HeroStrip extends StatelessWidget {
  const _HeroStrip({
    required this.channels,
    required this.state,
    required this.allowInsecure,
    required this.padding,
    required this.cardWidth,
  });

  final List<Channel> channels;
  final AppState state;
  final bool allowInsecure;
  final double padding;
  final double cardWidth;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 214,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: EdgeInsets.symmetric(horizontal: padding, vertical: 6),
        itemCount: channels.length,
        separatorBuilder: (context, index) => const SizedBox(width: 14),
        itemBuilder: (context, index) {
          final channel = channels[index];
          final resumed = state.recents.isNotEmpty &&
              state.recents.first.id == channel.id;
          return SizedBox(
            width: cardWidth,
            child: _HeroCard(
              channel: channel,
              programme: state.epg.nowFor(channel, state.now),
              next: state.epg.nextFor(channel, state.now),
              now: state.now,
              allowInsecure: allowInsecure,
              resume: resumed,
            ),
          );
        },
      ),
    );
  }
}

class _HeroCard extends StatelessWidget {
  const _HeroCard({
    required this.channel,
    required this.programme,
    required this.next,
    required this.now,
    required this.allowInsecure,
    required this.resume,
  });

  final Channel channel;
  final Programme? programme;
  final Programme? next;
  final DateTime now;
  final bool allowInsecure;
  final bool resume;

  @override
  Widget build(BuildContext context) {
    final colors = context.mawjColors;
    final theme = Theme.of(context);
    final strings = context.strings;
    final dark = Theme.of(context).brightness == Brightness.dark;
    final gradient = channelGradient(channel.name, dark: dark);
    final current = programme;
    // Artwork from the guide turns the card into a poster: dimmed picture,
    // white text. Without artwork the channel's own gradient is used.
    final settings = context.read<AppState>().settings;
    final art = settings.richVisuals ? current?.iconUrl?.trim() : null;
    final hasArt = art != null && art.isNotEmpty;
    final on = hasArt || dark ? Colors.white : const Color(0xFF0B1330);
    final use24 = context.read<AppState>().settings.use24HourTime;

    return Material(
      borderRadius: BorderRadius.circular(28),
      clipBehavior: Clip.antiAlias,
      color: gradient.last,
      child: Ink(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: AlignmentDirectional.topStart,
            end: AlignmentDirectional.bottomEnd,
            colors: gradient,
          ),
          image: hasArt
              ? DecorationImage(
                  image: ResizeImage(
                    MawjNetworkImage(art, allowInsecure: allowInsecure),
                    width: 900,
                    policy: ResizeImagePolicy.fit,
                  ),
                  fit: BoxFit.cover,
                  colorFilter: ColorFilter.mode(
                    Colors.black.withValues(alpha: 0.58),
                    BlendMode.darken,
                  ),
                  onError: (error, stackTrace) {},
                )
              : null,
        ),
        child: InkWell(
          onTap: () => openPlayer(context, channel),
          child: Padding(
            padding: const EdgeInsets.all(18),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Row(
                  children: <Widget>[
                    ChannelLogo(
                      channel: channel,
                      allowInsecure: allowInsecure,
                      size: 40,
                      radius: 12,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: BidiText(
                        channel.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.titleSmall?.copyWith(
                          color: on,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    if (resume)
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: on.withValues(alpha: 0.14),
                          borderRadius: BorderRadius.circular(999),
                        ),
                        child: Text(
                          strings.resume,
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: on,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                  ],
                ),
                const Spacer(),
                BidiText(
                  current?.title ?? strings.noProgrammeInfo,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.titleLarge?.copyWith(
                    color: on,
                    fontWeight: FontWeight.w800,
                    height: 1.15,
                  ),
                ),
                const SizedBox(height: 4),
                if (current != null)
                  BidiText(
                    strings.formatRange(
                      current.start,
                      current.stop,
                      use24HourTime: use24,
                    ),
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: on.withValues(alpha: 0.72),
                      fontFeatures: const <FontFeature>[
                        FontFeature.tabularFigures(),
                      ],
                    ),
                  )
                else if (next != null)
                  BidiText(
                    '${strings.upNext}: ${next!.title}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: on.withValues(alpha: 0.72),
                    ),
                  ),
                const SizedBox(height: 8),
                Row(
                  children: <Widget>[
                    Expanded(
                      child: current == null
                          ? const SizedBox(height: 18)
                          : WaveProgress(
                              progress: current.progressAt(now),
                              color: colors.accent,
                              trackColor: on.withValues(alpha: 0.25),
                              height: 18,
                              animate: !settings.reduceMotion,
                            ),
                    ),
                    const SizedBox(width: 12),
                    Container(
                      width: 42,
                      height: 42,
                      decoration: BoxDecoration(
                        color: colors.accent,
                        shape: BoxShape.circle,
                      ),
                      child: Icon(
                        Icons.play_arrow_rounded,
                        color: theme.colorScheme.onPrimary,
                        size: 28,
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
}

class _FilterBar extends StatelessWidget {
  const _FilterBar({
    required this.padding,
    required this.selected,
    required this.allKey,
    required this.favoritesKey,
    required this.groups,
    required this.hasFavorites,
    required this.onSelected,
  });

  final double padding;
  final String selected;
  final String allKey;
  final String favoritesKey;
  final List<String> groups;
  final bool hasFavorites;
  final ValueChanged<String> onSelected;

  @override
  Widget build(BuildContext context) {
    final strings = context.strings;
    final entries = <(String, String)>[
      (allKey, strings.allChannels),
      if (hasFavorites) (favoritesKey, strings.favorites),
      for (final group in groups) (group, group),
    ];
    return SizedBox(
      height: 56,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: EdgeInsets.symmetric(horizontal: padding, vertical: 10),
        itemCount: entries.length,
        separatorBuilder: (context, index) => const SizedBox(width: 8),
        itemBuilder: (context, index) {
          final entry = entries[index];
          return _Pill(
            label: entry.$2,
            selected: entry.$1 == selected,
            star: entry.$1 == favoritesKey,
            onTap: () => onSelected(entry.$1),
          );
        },
      ),
    );
  }
}

class _Pill extends StatelessWidget {
  const _Pill({
    required this.label,
    required this.selected,
    required this.star,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final bool star;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.mawjColors;
    final theme = Theme.of(context);
    final foreground =
        selected ? theme.colorScheme.onPrimary : colors.subtext1;
    return Material(
      color: selected ? colors.accent : colors.surface0.withValues(alpha: 0.7),
      borderRadius: BorderRadius.circular(999),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              if (star) ...<Widget>[
                Icon(Icons.star_rounded, size: 16, color: foreground),
                const SizedBox(width: 6),
              ],
              BidiText(
                label,
                maxLines: 1,
                style: theme.textTheme.labelLarge?.copyWith(
                  color: foreground,
                  fontWeight: selected ? FontWeight.w800 : FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Placeholder extends StatelessWidget {
  const _Placeholder();

  @override
  Widget build(BuildContext context) {
    final colors = context.mawjColors;
    return Container(
      height: kChannelRowHeight,
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: colors.surface0.withValues(alpha: 0.4),
        borderRadius: BorderRadius.circular(22),
      ),
    );
  }
}

class _Welcome extends StatelessWidget {
  const _Welcome({required this.onAdd});

  final VoidCallback onAdd;

  @override
  Widget build(BuildContext context) {
    final colors = context.mawjColors;
    final theme = Theme.of(context);
    final strings = context.strings;
    return SafeArea(
      child: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(32),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                WaveProgress(
                  progress: 0.62,
                  color: colors.accent,
                  trackColor: colors.surface2,
                  height: 56,
                  animate: true,
                ),
                const SizedBox(height: 32),
                Text(
                  strings.welcomeTitle,
                  textAlign: TextAlign.center,
                  style: theme.textTheme.headlineMedium?.copyWith(
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.5,
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  strings.welcomeBody,
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodyLarge?.copyWith(
                    color: colors.subtext0,
                    height: 1.5,
                  ),
                ),
                const SizedBox(height: 28),
                FilledButton.icon(
                  onPressed: onAdd,
                  icon: const Icon(Icons.add_rounded),
                  label: Text(strings.addSource),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
