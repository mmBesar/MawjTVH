import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/bidi.dart';
import '../../core/platform.dart';
import '../../core/theme.dart';
import '../../core/ui_zoom.dart';
import '../../data/app_state.dart';
import '../../data/models.dart';
import '../../l10n/strings.dart';
import '../../l10n/tvh_strings.dart';
import '../player_page.dart';
import '../widgets/channel_logo.dart';
import '../widgets/empty_state.dart';
import '../widgets/media_filter.dart';
import '../widgets/programme_sheet.dart';
import '../widgets/warnings_panel.dart';
import '../widgets/wheel_scroll.dart';
import 'channel_guide_page.dart';
import 'search_page.dart';

/// A twelve-hour timeline. The channel column stays put while the programmes
/// scroll sideways, and both scroll up and down together.
class GuidePage extends StatefulWidget {
  const GuidePage({
    super.key,
    required this.onOpenSources,
    this.onEdgeDrag,
    this.onEdgeDragEnd,
  });

  final VoidCallback onOpenSources;

  /// Called with the distance dragged past either end of the timeline, so the
  /// app can turn it into a page swipe. Null where pages do not swipe.
  final ValueChanged<double>? onEdgeDrag;
  final VoidCallback? onEdgeDragEnd;

  @override
  State<GuidePage> createState() => _GuidePageState();
}

class _GuidePageState extends State<GuidePage> {
  static const double _minZoom = 2.5;
  static const double _maxZoom = 48;
  static const double _rowHeight = 96;
  static const double _nameBand = 22;
  static const double _channelWidth = 80;
  static const double _headerHeight = 40;
  int _hours = 12;
  int get _spanMinutes => _hours * 60;
  static const double _bottomPadding = 110;

  final ScrollController _horizontal = ScrollController();
  final ScrollController _leftVertical = ScrollController();
  final ScrollController _rightVertical = ScrollController();

  /// Pixels per minute of the timeline; the slider changes it.
  double _zoom = 6.75;
  bool _syncing = false;
  bool _favoritesOnly = false;
  bool _scrolledToNow = false;
  late DateTime _windowStart;

  /// 0 is the running timeline; 1 is tomorrow, and so on. Any other day shows
  /// that calendar day from midnight to midnight.
  int _dayOffset = 0;

  @override
  void initState() {
    super.initState();
    _windowStart = _windowStartFor(DateTime.now());
    _leftVertical.addListener(() => _sync(_leftVertical, _rightVertical));
    _rightVertical.addListener(() => _sync(_rightVertical, _leftVertical));
  }

  @override
  void dispose() {
    _horizontal.dispose();
    _leftVertical.dispose();
    _rightVertical.dispose();
    super.dispose();
  }

  static DateTime _dayStart(DateTime now, int offset) =>
      DateTime(now.year, now.month, now.day + offset);

  void _selectDay(int offset, DateTime now) {
    if (offset == _dayOffset) {
      return;
    }
    setState(() {
      _dayOffset = offset;
      _windowStart =
          offset == 0 ? _windowStartFor(now) : _dayStart(now, offset);
      _scrolledToNow = false;
    });
  }

  /// One hour before the last half hour, so "now" has some history on its left.
  static DateTime _windowStartFor(DateTime now) {
    final floored = DateTime(
      now.year,
      now.month,
      now.day,
      now.hour,
      now.minute >= 30 ? 30 : 0,
    );
    return floored.subtract(const Duration(hours: 1));
  }

  void _sync(ScrollController from, ScrollController to) {
    if (_syncing || !from.hasClients || !to.hasClients) {
      return;
    }
    final target = from.offset
        .clamp(to.position.minScrollExtent, to.position.maxScrollExtent)
        .toDouble();
    if ((to.offset - target).abs() < 0.5) {
      return;
    }
    _syncing = true;
    to.jumpTo(target);
    _syncing = false;
  }

  /// Changes the zoom and keeps the minute at the left edge where it was.
  void _setZoom(double value) {
    final old = _zoom;
    final leftMinutes = _horizontal.hasClients ? _horizontal.offset / old : 0.0;
    setState(() => _zoom = value);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_horizontal.hasClients) {
        _horizontal.jumpTo(
          (leftMinutes * value)
              .clamp(0.0, _horizontal.position.maxScrollExtent)
              .toDouble(),
        );
      }
    });
  }

  double _nowOffset(DateTime now) {
    final minutes = now.difference(_windowStart).inSeconds / 60;
    return minutes * _zoom;
  }

  void _scrollToNow(DateTime now, {bool animate = false}) {
    if (!_horizontal.hasClients) {
      return;
    }
    final target = (_nowOffset(now) - 64)
        .clamp(0.0, _horizontal.position.maxScrollExtent)
        .toDouble();
    if (animate) {
      _horizontal.animateTo(
        target,
        duration: const Duration(milliseconds: 380),
        curve: Curves.easeOutCubic,
      );
    } else {
      _horizontal.jumpTo(target);
    }
  }

  @override
  Widget build(BuildContext context) {
    final chosen = context.select<AppState, double>(
      (state) => state.settings.guideScale,
    );
    // The timeline is dense; on a big desktop screen it gets its own extra
    // zoom on top of the interface zoom.
    final scale = chosen > 0 ? chosen : (kIsDesktop ? 1.2 : 1.0);
    return UiZoom(
      scale: scale,
      child: Builder(builder: _buildGuide),
    );
  }

  Widget _buildGuide(BuildContext context) {
    final state = context.watch<AppState>();
    final strings = context.strings;
    final colors = context.mawjColors;
    final theme = Theme.of(context);

    if (state.sources.isEmpty) {
      return EmptyState(
        icon: Icons.calendar_month_rounded,
        title: strings.noSources,
        body: strings.guideNoChannels,
        actionLabel: strings.addSource,
        onAction: widget.onOpenSources,
      );
    }

    if (_dayOffset >= state.guideDays) {
      _dayOffset = 0;
      _windowStart = _windowStartFor(state.now);
      _scrolledToNow = false;
    }
    _hours = _dayOffset == 0 ? state.settings.guideHours : 24;

    // Roll the window forward when the app has been open for most of it.
    if (_dayOffset == 0 &&
        state.now.isAfter(
          _windowStart.add(Duration(minutes: _spanMinutes - 90)),
        )) {
      _windowStart = _windowStartFor(state.now);
      _scrolledToNow = false;
    }

    final channels = _favoritesOnly && state.favorites.isNotEmpty
        ? state.favorites
        : state.filteredChannels;
    final windowEnd = _windowStart.add(Duration(minutes: _spanMinutes));
    final use24 = state.settings.use24HourTime;
    final allowInsecure = state.activeSource?.allowInsecureCerts ?? false;
    final gridWidth = _spanMinutes * _zoom;
    final nowX = _nowOffset(state.now);

    if (!_scrolledToNow) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted || !_horizontal.hasClients || _scrolledToNow) {
          return;
        }
        _scrolledToNow = true;
        if (_dayOffset == 0) {
          _scrollToNow(state.now);
        } else {
          _horizontal.jumpTo(0);
        }
      });
    }

    return SafeArea(
      bottom: false,
      child: Column(
        children: <Widget>[
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 12, 12, 8),
            child: Row(
              children: <Widget>[
                Expanded(
                  child: Text(
                    strings.guide,
                    style: theme.textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.w800,
                      letterSpacing: -0.3,
                    ),
                  ),
                ),
                IconButton(
                  tooltip: strings.searchGuideTitle,
                  onPressed: () =>
                      SearchPage.open(context, SearchScope.programmes),
                  icon: const Icon(Icons.search_rounded),
                ),
                IconButton(
                  tooltip: strings.guideFavoritesOnly,
                  isSelected: _favoritesOnly,
                  onPressed: state.favorites.isEmpty
                      ? null
                      : () => setState(() => _favoritesOnly = !_favoritesOnly),
                  icon: const Icon(Icons.star_outline_rounded),
                  selectedIcon: Icon(Icons.star_rounded, color: colors.accent),
                ),
                const SizedBox(width: 4),
                FilledButton.tonalIcon(
                  onPressed: () {
                    if (_dayOffset != 0) {
                      _selectDay(0, state.now);
                    } else {
                      _scrollToNow(state.now, animate: true);
                    }
                  },
                  icon: const Icon(Icons.my_location_rounded, size: 18),
                  label: Text(strings.guideNow),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 6),
            child: Row(
              children: <Widget>[
                Icon(Icons.zoom_out_rounded, size: 20, color: colors.subtext0),
                Expanded(
                  child: SliderTheme(
                    data: SliderTheme.of(context).copyWith(
                      trackHeight: 4,
                      activeTrackColor: colors.accent,
                      inactiveTrackColor: colors.surface2,
                      thumbColor: colors.accent,
                      overlayColor: colors.accent.withValues(alpha: 0.16),
                      thumbShape:
                          const RoundSliderThumbShape(enabledThumbRadius: 8),
                      trackShape: const RoundedRectSliderTrackShape(),
                    ),
                    child: Slider(
                      value: (math.log(_zoom / _minZoom) /
                              math.log(_maxZoom / _minZoom))
                          .clamp(0.0, 1.0)
                          .toDouble(),
                      onChanged: (t) => _setZoom(
                        _minZoom * math.pow(_maxZoom / _minZoom, t).toDouble(),
                      ),
                    ),
                  ),
                ),
                Icon(Icons.zoom_in_rounded, size: 20, color: colors.subtext0),
              ],
            ),
          ),
          if (state.guideDays > 1)
            SizedBox(
              height: 44,
              child: WheelScroll(builder: (context, controller) => ListView(
                controller: controller,
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 16),
                children: <Widget>[
                  for (var day = 0; day < state.guideDays; day++)
                    Padding(
                      padding: const EdgeInsetsDirectional.only(end: 8),
                      child: ChoiceChip(
                        label: Text(
                          day == 0
                              ? strings.today
                              : day == 1
                                  ? strings.tomorrow
                                  : strings.guideDayChip(
                                      _dayStart(state.now, day),
                                    ),
                        ),
                        selected: _dayOffset == day,
                        onSelected: (_) => _selectDay(day, state.now),
                      ),
                    ),
                ],
              )),
            ),
          const MediaFilterChips(
            padding: EdgeInsets.symmetric(horizontal: 16),
          ),
          if (state.groups.isNotEmpty)
            SizedBox(
              height: 44,
              child: WheelScroll(builder: (context, controller) => ListView(
                controller: controller,
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 16),
                children: <Widget>[
                  Padding(
                    padding: const EdgeInsetsDirectional.only(end: 8),
                    child: ChoiceChip(
                      label: Text(strings.allGroupsGuide),
                      selected: state.groupFilter == null,
                      onSelected: (_) => state.setGroupFilter(null),
                    ),
                  ),
                  for (final group in state.groups)
                    Padding(
                      padding: const EdgeInsetsDirectional.only(end: 8),
                      child: ChoiceChip(
                        label: BidiText(group),
                        selected: state.groupFilter == group,
                        onSelected: (_) => state.setGroupFilter(group),
                      ),
                    ),
                ],
              )),
            ),
          WarningsPanel(warnings: state.warnings),
          if (channels.isEmpty)
            Expanded(
              child: EmptyState(
                icon: Icons.calendar_month_rounded,
                title: strings.guideEmptyTitle,
                body: strings.guideNoChannels,
              ),
            )
          else
            Expanded(
              // Time always runs left to right, whatever the interface
              // language, so the timeline reads the same in Arabic.
              child: Directionality(
                textDirection: TextDirection.ltr,
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    SizedBox(
                      width: _channelWidth,
                      child: Column(
                        children: <Widget>[
                          const SizedBox(height: _headerHeight),
                          Expanded(
                            child: ListView.builder(
                              controller: _leftVertical,
                              itemExtent: _rowHeight,
                              padding: const EdgeInsets.only(
                                bottom: _bottomPadding,
                              ),
                              itemCount: channels.length,
                              itemBuilder: (context, index) {
                                return _ChannelCell(
                                  channel: channels[index],
                                  allowInsecure: allowInsecure,
                                );
                              },
                            ),
                          ),
                        ],
                      ),
                    ),
                    Expanded(
                      child: NotificationListener<ScrollNotification>(
                        onNotification: (notification) {
                          if (notification.depth != 0) {
                            return false;
                          }
                          if (notification is OverscrollNotification &&
                              notification.dragDetails != null) {
                            widget.onEdgeDrag?.call(notification.overscroll);
                          } else if (notification is ScrollEndNotification) {
                            widget.onEdgeDragEnd?.call();
                          }
                          return false;
                        },
                        child: SingleChildScrollView(
                        physics: const ClampingScrollPhysics(),
                        controller: _horizontal,
                        scrollDirection: Axis.horizontal,
                        child: SizedBox(
                          width: gridWidth,
                          child: Column(
                            children: <Widget>[
                              _TimeHeader(
                                start: _windowStart,
                                use24: use24,
                                nowX: nowX,
                                height: _headerHeight,
                                pxPerMinute: _zoom,
                                spanMinutes: _spanMinutes,
                              ),
                              Expanded(
                                child: Stack(
                                  children: <Widget>[
                                    ListView.builder(
                                      controller: _rightVertical,
                                      itemExtent: _rowHeight,
                                      padding: const EdgeInsets.only(
                                        bottom: _bottomPadding,
                                      ),
                                      itemCount: channels.length,
                                      itemBuilder: (context, index) {
                                        return _buildRow(
                                          context,
                                          state,
                                          channels[index],
                                          windowEnd,
                                          use24,
                                        );
                                      },
                                    ),
                                    if (nowX > 0 && nowX < gridWidth)
                                      Positioned(
                                        left: nowX - 1,
                                        top: 0,
                                        bottom: 0,
                                        width: 2,
                                        child: IgnorePointer(
                                          child: ColoredBox(
                                            color: colors.accent.withValues(
                                              alpha: 0.85,
                                            ),
                                          ),
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
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildRow(
    BuildContext context,
    AppState state,
    Channel channel,
    DateTime windowEnd,
    bool use24,
  ) {
    final colors = context.mawjColors;
    final strings = context.strings;
    // Only the rows that get built, that is the ones on screen, ask the
    // server for a day it has not pushed yet.
    state.ensureGuideEvents(channel, windowEnd);
    final programmes = state.epg.forWindow(channel, _windowStart, windowEnd);
    final blocks = <Widget>[];
    for (final programme in programmes) {
      final startMinutes =
          programme.start.difference(_windowStart).inSeconds / 60;
      final stopMinutes =
          programme.stop.difference(_windowStart).inSeconds / 60;
      final left = math.max(0.0, startMinutes) * _zoom;
      final right =
          math.min(_spanMinutes.toDouble(), stopMinutes) * _zoom;
      final width = right - left - 3;
      if (width < 8) {
        continue;
      }
      blocks.add(
        Positioned(
          left: left,
          width: width,
          top: _nameBand,
          bottom: 6,
          child: _Block(
            programme: programme,
            scroll: _horizontal,
            left: left,
            live: programme.isLiveAt(state.now),
            range: strings.formatRange(
              programme.start,
              programme.stop,
              use24HourTime: use24,
            ),
            onTap: () => showProgrammeSheet(
              context,
              channel: channel,
              programme: programme,
            ),
          ),
        ),
      );
    }
    return DecoratedBox(
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(color: colors.surface0.withValues(alpha: 0.5)),
        ),
      ),
      child: Stack(
        children: <Widget>[
          ...blocks,
          // The channel name rides along the left edge of the visible
          // timeline, so each row says whose it is wherever you scroll.
          AnimatedBuilder(
            animation: _horizontal,
            builder: (context, _) {
              final offset = _horizontal.hasClients ? _horizontal.offset : 0.0;
              return Positioned(
                left: offset + 8,
                top: 3,
                child: IgnorePointer(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 240),
                    child: BidiText(
                      channel.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.labelMedium?.copyWith(
                            color: colors.subtext0,
                            fontWeight: FontWeight.w700,
                          ),
                    ),
                  ),
                ),
              );
            },
          ),
        ],
      ),
    );
  }
}

class _TimeHeader extends StatelessWidget {
  const _TimeHeader({
    required this.start,
    required this.use24,
    required this.nowX,
    required this.height,
    required this.pxPerMinute,
    required this.spanMinutes,
  });

  final DateTime start;
  final bool use24;
  final double nowX;
  final double height;
  final double pxPerMinute;
  final int spanMinutes;

  @override
  Widget build(BuildContext context) {
    final colors = context.mawjColors;
    final theme = Theme.of(context);
    final strings = context.strings;
    // Label spacing follows the zoom: the smallest step that leaves room for
    // a time label.
    var step = 60;
    for (final candidate in const <int>[5, 10, 15, 30, 60]) {
      if (candidate * pxPerMinute >= 72) {
        step = candidate;
        break;
      }
    }
    return SizedBox(
      height: height,
      child: Stack(
        children: <Widget>[
          for (var slot = 0; slot < spanMinutes ~/ step; slot++)
            Positioned(
              left: slot * step * pxPerMinute + 8,
              top: 0,
              bottom: 0,
              child: Center(
                child: Text(
                  strings.formatTime(
                    start.add(Duration(minutes: slot * step)),
                    use24HourTime: use24,
                  ),
                  style: theme.textTheme.labelMedium?.copyWith(
                    color: (slot * step) % 30 == 0
                        ? colors.subtext1
                        : colors.overlay1,
                    fontWeight: (slot * step) % 30 == 0
                        ? FontWeight.w700
                        : FontWeight.w500,
                    fontFeatures: const <FontFeature>[
                      FontFeature.tabularFigures(),
                    ],
                  ),
                ),
              ),
            ),
          if (nowX > 0 && nowX < spanMinutes * pxPerMinute)
            Positioned(
              left: nowX - 5,
              bottom: 0,
              child: Container(
                width: 10,
                height: 10,
                decoration: BoxDecoration(
                  color: colors.accent,
                  shape: BoxShape.circle,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _ChannelCell extends StatelessWidget {
  const _ChannelCell({required this.channel, required this.allowInsecure});

  final Channel channel;
  final bool allowInsecure;

  @override
  Widget build(BuildContext context) {
    final colors = context.mawjColors;
    final theme = Theme.of(context);
    return InkWell(
      onTap: () => openPlayer(context, channel),
      onLongPress: () => ChannelGuidePage.open(context, channel),
      onSecondaryTap: () => ChannelGuidePage.open(context, channel),
      child: DecoratedBox(
        decoration: BoxDecoration(
          border: Border(
            bottom: BorderSide(color: colors.surface0.withValues(alpha: 0.5)),
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: <Widget>[
              Tooltip(
                message: channel.name,
                child: ChannelLogo(
                  channel: channel,
                  allowInsecure: allowInsecure,
                  size: 52,
                  radius: 14,
                ),
              ),
              if (channel.logoUrl == null || channel.logoUrl!.isEmpty) ...<Widget>[
                const SizedBox(height: 4),
                BidiText(
                  channel.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: colors.subtext1,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _Block extends StatelessWidget {
  const _Block({
    required this.programme,
    required this.scroll,
    required this.left,
    required this.live,
    required this.range,
    required this.onTap,
  });

  final Programme programme;

  /// The timeline's horizontal scroll, so the text can follow the viewport.
  final ScrollController scroll;

  /// Where this block starts on the timeline, in pixels.
  final double left;
  final bool live;
  final String range;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.mawjColors;
    final theme = Theme.of(context);
    return Material(
      color: live ? colors.accentSoft : colors.surface0.withValues(alpha: 0.75),
      borderRadius: BorderRadius.circular(14),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: DecoratedBox(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: live
                ? Border.all(color: colors.accent.withValues(alpha: 0.7))
                : null,
          ),
          child: LayoutBuilder(
            builder: (context, constraints) {
              if (constraints.maxWidth < 48) {
                return const SizedBox.shrink();
              }
              final roomy = constraints.maxWidth >= 120;
              final blockWidth = constraints.maxWidth;
              final inner = Padding(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: <Widget>[
                    BidiText(
                      programme.title,
                      maxLines: roomy ? 1 : 2,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: live ? colors.text : colors.subtext1,
                        fontWeight: FontWeight.w700,
                        height: 1.2,
                      ),
                    ),
                    if (roomy &&
                        (programme.episode != null || programme.subTitle != null))
                      BidiText(
                        <String>[
                          if (programme.episode != null) programme.episode!,
                          if (programme.subTitle != null) programme.subTitle!,
                        ].join(' · '),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: colors.subtext0,
                          height: 1.25,
                        ),
                      ),
                    if (roomy)
                      Text(
                        range,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: live ? colors.accent : colors.overlay1,
                          fontFeatures: const <FontFeature>[
                            FontFeature.tabularFigures(),
                          ],
                        ),
                      ),
                  ],
                ),
              );
              // A long programme can start far off-screen. Slide its text
              // along so it stays readable at whichever edge is visible.
              final content = AnimatedBuilder(
                animation: scroll,
                child: inner,
                builder: (context, child) {
                  var shiftLeft = 0.0;
                  var shiftRight = 0.0;
                  if (scroll.hasClients && scroll.position.hasViewportDimension) {
                    final offset = scroll.offset;
                    final view = scroll.position.viewportDimension;
                    final room = math.max(0.0, blockWidth - 90);
                    shiftLeft = (offset - left).clamp(0.0, room).toDouble();
                    shiftRight =
                        (left + blockWidth - (offset + view)).clamp(0.0, room).toDouble();
                    if (shiftLeft + shiftRight > room) {
                      shiftRight = math.max(0.0, room - shiftLeft);
                    }
                  }
                  return Padding(
                    padding: EdgeInsets.only(left: shiftLeft, right: shiftRight),
                    child: child,
                  );
                },
              );
              if (!programme.hasRecording) {
                return content;
              }
              return Stack(
                children: <Widget>[
                  content,
                  PositionedDirectional(
                    top: 7,
                    end: 7,
                    child: Container(
                      width: 9,
                      height: 9,
                      decoration: BoxDecoration(
                        color: programme.dvrState == 'recording'
                            ? const Color(0xFFED3B4B)
                            : colors.accent,
                        shape: BoxShape.circle,
                      ),
                    ),
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}
