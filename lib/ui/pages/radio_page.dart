import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/bidi.dart';
import '../../core/theme.dart';
import '../../data/app_state.dart';
import '../../data/models.dart';
import '../../l10n/strings.dart';
import '../../l10n/tvh_strings.dart';
import '../widgets/audio_bars.dart';
import '../widgets/channel_views.dart';
import '../widgets/empty_state.dart';
import '../widgets/error_banner.dart';
import '../widgets/source_switcher.dart';
import 'channel_guide_page.dart';
import 'search_page.dart';

/// The Radio tab: every radio station of the server, played as audio by the
/// app-wide [RadioPlayer] (mini player above the navigation, Now Playing page,
/// notification on Android).
class RadioPage extends StatefulWidget {
  const RadioPage({super.key, required this.onOpenSources});

  final VoidCallback onOpenSources;

  @override
  State<RadioPage> createState() => _RadioPageState();
}

class _RadioPageState extends State<RadioPage> {
  bool _favoritesOnly = false;

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final strings = context.strings;
    final colors = context.mawjColors;
    final theme = Theme.of(context);

    if (!state.restored || state.sources.isEmpty) {
      return const SizedBox.shrink();
    }

    final all = state.radioChannels;
    final favorites = all.where(state.isFavorite).toList(growable: false);
    if (_favoritesOnly && favorites.isEmpty) {
      _favoritesOnly = false;
    }
    final stations = _favoritesOnly ? favorites : all;
    final allowInsecure = state.activeSource?.allowInsecureCerts ?? false;
    final loadingFirst = state.isLoading && state.channels.isEmpty;

    return RefreshIndicator(
      onRefresh: state.refresh,
      color: colors.accent,
      backgroundColor: colors.surface1,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final side = constraints.maxWidth >= 760 ? 24.0 : 16.0;
          return CustomScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            slivers: <Widget>[
              SliverToBoxAdapter(
                child: SafeArea(
                  bottom: false,
                  child: Padding(
                    padding: EdgeInsets.fromLTRB(side, 12, side - 8, 8),
                    child: Row(
                      children: <Widget>[
                        Icon(Icons.radio_rounded, color: colors.accent),
                        const SizedBox(width: 10),
                        Text(
                          strings.radioKind,
                          style: theme.textTheme.titleLarge?.copyWith(
                            fontWeight: FontWeight.w800,
                            letterSpacing: -0.4,
                          ),
                        ),
                        const Spacer(),
                        if (state.activeSource != null)
                          Flexible(
                            child: ActionChip(
                              onPressed: () => showSourceSwitcher(
                                context,
                                onManage: widget.onOpenSources,
                              ),
                              avatar: Icon(
                                Icons.dns_rounded,
                                size: 16,
                                color: colors.accent,
                              ),
                              label: BidiText(
                                state.activeSource!.name,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                              side: BorderSide(color: colors.surface1),
                              backgroundColor:
                                  colors.surface0.withValues(alpha: 0.6),
                            ),
                          ),
                        IconButton(
                          tooltip: strings.searchChannels,
                          onPressed: () =>
                              SearchPage.open(context, SearchScope.channels),
                          icon: const Icon(Icons.search_rounded),
                        ),
                        IconButton(
                          tooltip: strings.refresh,
                          onPressed:
                              state.isLoading ? null : () => unawaited(state.refresh()),
                          icon: const Icon(Icons.refresh_rounded),
                        ),
                      ],
                    ),
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
              if (favorites.isNotEmpty)
                SliverToBoxAdapter(
                  child: Padding(
                    padding: EdgeInsets.fromLTRB(side, 4, side, 8),
                    child: Row(
                      children: <Widget>[
                        ChoiceChip(
                          label: Text(strings.allChannels),
                          selected: !_favoritesOnly,
                          onSelected: (_) =>
                              setState(() => _favoritesOnly = false),
                        ),
                        const SizedBox(width: 8),
                        ChoiceChip(
                          avatar: const Icon(Icons.star_rounded, size: 16),
                          label: Text(strings.favorites),
                          selected: _favoritesOnly,
                          onSelected: (_) =>
                              setState(() => _favoritesOnly = true),
                        ),
                      ],
                    ),
                  ),
                ),
              if (loadingFirst)
                const SliverFillRemaining(
                  hasScrollBody: false,
                  child: Center(child: CircularProgressIndicator()),
                )
              else if (stations.isEmpty)
                SliverFillRemaining(
                  hasScrollBody: false,
                  child: EmptyState(
                    icon: Icons.radio_rounded,
                    title: strings.noRadio,
                    body: strings.noRadioBody,
                    actionLabel: strings.retry,
                    onAction: state.refresh,
                  ),
                )
              else
                // Room under the list for the mini player and the navigation.
                SliverPadding(
                  padding: EdgeInsets.fromLTRB(side, 4, side, 200),
                  sliver: SliverGrid.builder(
                    gridDelegate:
                        const SliverGridDelegateWithMaxCrossAxisExtent(
                      maxCrossAxisExtent: 440,
                      mainAxisExtent: kChannelCompactHeight,
                      mainAxisSpacing: 8,
                      crossAxisSpacing: 8,
                    ),
                    itemCount: stations.length,
                    itemBuilder: (context, index) {
                      final channel = stations[index];
                      return _Station(
                        channel: channel,
                        state: state,
                        allowInsecure: allowInsecure,
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
}

class _Station extends StatelessWidget {
  const _Station({
    required this.channel,
    required this.state,
    required this.allowInsecure,
  });

  final Channel channel;
  final AppState state;
  final bool allowInsecure;

  @override
  Widget build(BuildContext context) {
    final colors = context.mawjColors;
    final radio = state.radio;
    return ListenableBuilder(
      listenable: radio,
      builder: (context, child) {
        final current = radio.channel?.id == channel.id;
        final tile = ChannelCompactRow(
          channel: channel,
          programme: state.epg.nowFor(channel, state.now),
          now: state.now,
          allowInsecure: allowInsecure,
          favorite: state.isFavorite(channel),
          // Tapping the current station pauses or resumes it.
          onTap: () => unawaited(
            current ? radio.toggle() : radio.play(channel),
          ),
          onOpenGuide: () => ChannelGuidePage.open(context, channel),
          onToggleFavorite: () => unawaited(state.toggleFavorite(channel)),
        );
        if (!current) {
          return tile;
        }
        return Stack(
          children: <Widget>[
            Positioned.fill(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(color: colors.accent, width: 1.6),
                ),
              ),
            ),
            tile,
            PositionedDirectional(
              top: 6,
              end: 52,
              child: IgnorePointer(
                child: AudioBars(
                  playing: radio.playing && !radio.buffering,
                  color: colors.accent,
                  bars: 3,
                  height: 12,
                  barWidth: 3,
                  gap: 2,
                  animate: !state.settings.reduceMotion,
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}
