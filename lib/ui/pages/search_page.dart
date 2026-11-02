import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/bidi.dart';
import '../../core/theme.dart';
import '../../data/app_state.dart';
import '../../data/models.dart';
import '../../l10n/strings.dart';
import '../../l10n/tvh_strings.dart';
import '../player_page.dart';
import '../widgets/channel_logo.dart';
import '../widgets/channel_row.dart';
import '../widgets/empty_state.dart';
import '../widgets/programme_poster.dart';
import '../widgets/programme_sheet.dart';
import 'channel_guide_page.dart';

/// What a search looks through. Each page opens the scope that fits it, so
/// there is no separate "search" tab to remember.
enum SearchScope { channels, programmes }

/// Finds channels by name, number or group, or programmes by title,
/// sub-title or category, depending on [scope].
class SearchPage extends StatefulWidget {
  const SearchPage({super.key, required this.scope});

  final SearchScope scope;

  static Future<void> open(BuildContext context, SearchScope scope) {
    return Navigator.of(context).push<void>(
      MaterialPageRoute<void>(builder: (context) => SearchPage(scope: scope)),
    );
  }

  @override
  State<SearchPage> createState() => _SearchPageState();
}

class _SearchPageState extends State<SearchPage> {
  final TextEditingController _controller = TextEditingController();
  final FocusNode _focus = FocusNode();
  String _query = '';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _focus.requestFocus();
      }
    });
  }

  @override
  void dispose() {
    _focus.dispose();
    _controller.dispose();
    super.dispose();
  }

  void _clear() {
    _controller.clear();
    setState(() => _query = '');
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final strings = context.strings;
    final colors = context.mawjColors;
    final theme = Theme.of(context);
    final query = _query.trim();
    final allowInsecure = state.activeSource?.allowInsecureCerts ?? false;
    final use24 = state.settings.use24HourTime;

    Widget body;
    if (query.isEmpty) {
      body = EmptyState(
        icon: Icons.search_rounded,
        title: strings.searchEmptyTitle,
        body: strings.searchEmptyBody,
      );
    } else {
      final channels = widget.scope == SearchScope.channels
          ? state.searchChannels(query)
          : const <Channel>[];
      final programmes = widget.scope == SearchScope.programmes
          ? state.searchProgrammes(query)
          : const <ProgrammeHit>[];
      if (channels.isEmpty && programmes.isEmpty) {
        body = EmptyState(
          icon: Icons.search_off_rounded,
          title: strings.noResultsTitle,
          body: strings.noResultsBody(query),
        );
      } else {
        body = ListView(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 120),
          children: <Widget>[
            if (channels.isNotEmpty) ...<Widget>[
              _SectionTitle(strings.channelsLabel),
              for (final channel in channels.take(40))
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: ChannelRow(
                    channel: channel,
                    programme: state.epg.nowFor(channel, state.now),
                    next: state.epg.nextFor(channel, state.now),
                    now: state.now,
                    allowInsecure: allowInsecure,
                    favorite: state.isFavorite(channel),
                    onTap: () => openPlayer(context, channel),
                    onOpenGuide: () => ChannelGuidePage.open(context, channel),
                    onToggleFavorite: () =>
                        unawaited(state.toggleFavorite(channel)),
                  ),
                ),
            ],
            if (programmes.isNotEmpty) ...<Widget>[
              _SectionTitle(strings.programmesLabel),
              for (final hit in programmes)
                _HitTile(
                  hit: hit,
                  now: state.now,
                  use24: use24,
                  allowInsecure: allowInsecure,
                ),
            ],
          ],
        );
      }
    }

    return Scaffold(
      appBar: AppBar(
        title: Text(
          widget.scope == SearchScope.channels
              ? strings.searchChannelsTitle
              : strings.searchGuideTitle,
        ),
      ),
      body: SafeArea(
      bottom: false,
      child: Column(
        children: <Widget>[
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 6, 16, 12),
            child: TextField(
              controller: _controller,
              focusNode: _focus,
              onChanged: (value) => setState(() => _query = value),
              textInputAction: TextInputAction.search,
              autocorrect: false,
              style: theme.textTheme.titleMedium,
              decoration: InputDecoration(
                hintText: strings.searchHint,
                prefixIcon: const Icon(Icons.search_rounded),
                suffixIcon: _query.isEmpty
                    ? null
                    : IconButton(
                        tooltip: strings.clearSearch,
                        onPressed: _clear,
                        icon: Icon(Icons.close_rounded, color: colors.subtext0),
                      ),
              ),
            ),
          ),
          Expanded(child: body),
        ],
      ),
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    final colors = context.mawjColors;
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 10, 4, 10),
      child: Text(
        text,
        style: Theme.of(context).textTheme.titleSmall?.copyWith(
              color: colors.subtext0,
              fontWeight: FontWeight.w700,
            ),
      ),
    );
  }
}

class _HitTile extends StatelessWidget {
  const _HitTile({
    required this.hit,
    required this.now,
    required this.use24,
    required this.allowInsecure,
  });

  final ProgrammeHit hit;
  final DateTime now;
  final bool use24;
  final bool allowInsecure;

  @override
  Widget build(BuildContext context) {
    final colors = context.mawjColors;
    final theme = Theme.of(context);
    final strings = context.strings;
    final programme = hit.programme;
    final live = programme.isLiveAt(now);
    final when = live
        ? strings.now
        : '${strings.formatDate(programme.start)} '
            '${strings.formatTime(programme.start, use24HourTime: use24)}';

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Material(
        color: colors.surface0.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(18),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: () => showProgrammeSheet(
            context,
            channel: hit.channel,
            programme: programme,
          ),
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              children: <Widget>[
                if (programme.iconUrl != null &&
                    programme.iconUrl!.trim().isNotEmpty)
                  ProgrammePoster(
                    programme: programme,
                    allowInsecure: allowInsecure,
                    width: 128,
                    height: 72,
                    radius: 12,
                  )
                else
                  ChannelLogo(
                    channel: hit.channel,
                    allowInsecure: allowInsecure,
                    size: 56,
                    radius: 14,
                  ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      BidiText(
                        programme.displayTitle,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      if (programme.subTitle != null)
                        BidiText(
                          programme.subTitle!,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: colors.subtext1,
                          ),
                        ),
                      const SizedBox(height: 2),
                      BidiText(
                        '${hit.channel.name} · $when',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: live ? colors.accent : colors.subtext0,
                          fontWeight: live ? FontWeight.w700 : FontWeight.w400,
                        ),
                      ),
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
