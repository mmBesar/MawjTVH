import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/bidi.dart';
import '../../core/theme.dart';
import '../../data/models.dart';
import '../../l10n/strings.dart';
import '../../l10n/tvh_strings.dart';
import 'channel_logo.dart';
import 'stb_osd.dart';

/// The channel's own guide over the picture: what is on and what follows,
/// with the details of the highlighted programme and record buttons.
class StbEpgPanel extends StatefulWidget {
  const StbEpgPanel({
    super.key,
    required this.channel,
    required this.programmes,
    required this.now,
    required this.use24,
    required this.allowInsecure,
    required this.canRecord,
    required this.onRecord,
    required this.onRecordSeries,
    required this.onClose,
    this.bottomInset = 0,
  });

  /// Space kept free at the bottom (the desktop control bar).
  final double bottomInset;

  final Channel channel;

  /// In time order; the caller drops what ended long ago.
  final List<Programme> programmes;
  final DateTime now;
  final bool use24;
  final bool allowInsecure;
  final bool canRecord;
  final void Function(Programme programme) onRecord;
  final void Function(Programme programme) onRecordSeries;
  final VoidCallback onClose;

  @override
  State<StbEpgPanel> createState() => _StbEpgPanelState();
}

class _StbEpgPanelState extends State<StbEpgPanel> {
  static const double _rowHeight = 64;

  final FocusNode _focus = FocusNode(debugLabel: 'stb-epg');
  final ScrollController _scroll = ScrollController();
  int _selected = 0;

  @override
  void initState() {
    super.initState();
    final live = widget.programmes.indexWhere((p) => p.isLiveAt(widget.now));
    _selected = live < 0 ? 0 : live;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _focus.requestFocus();
      if (_scroll.hasClients) {
        final viewport = _scroll.position.viewportDimension;
        final target = _selected * _rowHeight - (viewport - _rowHeight) / 3;
        _scroll.jumpTo(
          target.clamp(0.0, _scroll.position.maxScrollExtent).toDouble(),
        );
      }
    });
  }

  @override
  void dispose() {
    _focus.dispose();
    _scroll.dispose();
    super.dispose();
  }

  Programme? get _current =>
      widget.programmes.isEmpty ? null : widget.programmes[_selected];

  void _move(int delta) {
    if (widget.programmes.isEmpty) {
      return;
    }
    setState(() {
      _selected = (_selected + delta).clamp(0, widget.programmes.length - 1);
    });
    if (!_scroll.hasClients) {
      return;
    }
    final position = _scroll.position;
    final top = _selected * _rowHeight;
    if (top < position.pixels) {
      unawaited(_scroll.animateTo(
        top,
        duration: const Duration(milliseconds: 90),
        curve: Curves.easeOut,
      ));
    } else if (top + _rowHeight > position.pixels + position.viewportDimension) {
      unawaited(_scroll.animateTo(
        top + _rowHeight - position.viewportDimension,
        duration: const Duration(milliseconds: 90),
        curve: Curves.easeOut,
      ));
    }
  }

  bool _recordable(Programme? programme) =>
      widget.canRecord &&
      programme != null &&
      programme.eventId != null &&
      !programme.hasRecording &&
      programme.stop.isAfter(widget.now);

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (event is KeyUpEvent) {
      return KeyEventResult.ignored;
    }
    final key = event.logicalKey;
    if (key == LogicalKeyboardKey.escape || key == LogicalKeyboardKey.keyG) {
      widget.onClose();
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.arrowDown) {
      _move(1);
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.arrowUp) {
      _move(-1);
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.pageDown) {
      _move(6);
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.pageUp) {
      _move(-6);
      return KeyEventResult.handled;
    }
    final programme = _current;
    if ((key == LogicalKeyboardKey.enter ||
            key == LogicalKeyboardKey.numpadEnter) &&
        _recordable(programme)) {
      widget.onRecord(programme!);
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.keyS && _recordable(programme)) {
      widget.onRecordSeries(programme!);
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    final strings = context.strings;
    final colors = context.mawjColors;
    final size = MediaQuery.sizeOf(context);
    final pad = MediaQuery.paddingOf(context);
    final compact = size.width < 720;
    // A phone on its side: full height, programmes and details side by side.
    final desktop = widget.bottomInset > 0;
    final short = !compact && !desktop && size.height < 520;
    final inset = short
        ? 0.0
        : widget.bottomInset.clamp(0.0, size.height * 0.25).toDouble();
    // As tall as the window allows, down to the control bar.
    final tallMargin = EdgeInsets.fromLTRB(20, 16, 20, 16 + inset);
    final tallHeight = math.max(200.0, size.height - tallMargin.vertical);
    final programme = _current;

    final programmeList = widget.programmes.isEmpty
        ? Center(
            child: Text(
              strings.noGuide,
              style: const TextStyle(color: Colors.white60, fontSize: 15),
            ),
          )
        : ListView.builder(
            controller: _scroll,
            itemExtent: _rowHeight,
            padding: const EdgeInsets.symmetric(horizontal: 8),
            itemCount: widget.programmes.length,
            itemBuilder: (context, index) {
              final item = widget.programmes[index];
              return _EpgRow(
                programme: item,
                now: widget.now,
                use24: widget.use24,
                selected: index == _selected,
                onTap: () => setState(() => _selected = index),
              );
            },
          );
    final details = programme == null
        ? const SizedBox.shrink()
        : _Details(
            programme: programme,
            now: widget.now,
            use24: widget.use24,
            canRecord: _recordable(programme),
            onRecord: () => widget.onRecord(programme),
            onRecordSeries: () => widget.onRecordSeries(programme),
          );

    final panel = Container(
      width: compact
          ? double.infinity
          : (short ? (size.width * 0.82).clamp(560.0, 920.0).toDouble() : 560),
      height: compact
          ? size.height * 0.78
          : (short ? null : tallHeight),
      margin: compact
          ? EdgeInsets.fromLTRB(8, 0, 8, 8 + pad.bottom)
          : short
              ? EdgeInsets.fromLTRB(
                  8,
                  8 + pad.top,
                  8 + pad.right,
                  8 + pad.bottom,
                )
              : tallMargin,
      decoration: stbPanelDecoration(colors.accent),
      child: Column(
        children: <Widget>[
          Padding(
            padding: short
                ? const EdgeInsets.fromLTRB(14, 6, 4, 2)
                : const EdgeInsets.fromLTRB(16, 14, 8, 8),
            child: Row(
              children: <Widget>[
                ChannelLogo(
                  channel: widget.channel,
                  allowInsecure: widget.allowInsecure,
                  size: short ? 30 : 40,
                  radius: 8,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(
                        strings.stbEpg.toUpperCase(),
                        style: TextStyle(
                          color: colors.accent,
                          fontSize: 12,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 1.6,
                        ),
                      ),
                      BidiText(
                        widget.channel.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 19,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  tooltip: strings.close,
                  onPressed: widget.onClose,
                  icon: const Icon(Icons.close_rounded, color: Colors.white70),
                ),
              ],
            ),
          ),
          if (short)
            Expanded(
              child: Row(
                children: <Widget>[
                  Expanded(flex: 5, child: programmeList),
                  Container(
                    width: 1,
                    color: Colors.white.withValues(alpha: 0.10),
                  ),
                  Expanded(flex: 6, child: details),
                ],
              ),
            )
          else ...<Widget>[
            Expanded(flex: 5, child: programmeList),
            Container(height: 1, color: Colors.white.withValues(alpha: 0.10)),
            Expanded(flex: 5, child: details),
          ],
          if (!compact && !short)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
              child: Text(
                strings.stbEpgHint,
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.45),
                  fontSize: 11.5,
                ),
              ),
            ),
        ],
      ),
    );

    return Focus(
      focusNode: _focus,
      onKeyEvent: _onKey,
      child: Stack(
        fit: StackFit.expand,
        children: <Widget>[
          Positioned.fill(
            bottom: inset,
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: widget.onClose,
              child: const ColoredBox(color: Colors.transparent),
            ),
          ),
          Align(
            alignment: compact
                ? Alignment.bottomCenter
                : AlignmentDirectional.centerEnd,
            child: panel,
          ),
        ],
      ),
    );
  }
}

class _EpgRow extends StatelessWidget {
  const _EpgRow({
    required this.programme,
    required this.now,
    required this.use24,
    required this.selected,
    required this.onTap,
  });

  final Programme programme;
  final DateTime now;
  final bool use24;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.mawjColors;
    final strings = context.strings;
    final live = programme.isLiveAt(now);
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 2),
        padding: const EdgeInsets.symmetric(horizontal: 10),
        decoration: BoxDecoration(
          color: selected
              ? colors.accent.withValues(alpha: 0.20)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: selected ? colors.accent : Colors.transparent,
            width: 1.4,
          ),
        ),
        child: Row(
          children: <Widget>[
            SizedBox(
              width: 82,
              child: Text(
                strings.formatTime(programme.start, use24HourTime: use24),
                style: TextStyle(
                  color: live ? colors.accent : Colors.white70,
                  fontSize: 15,
                  fontWeight: FontWeight.w800,
                  fontFeatures: const <FontFeature>[FontFeature.tabularFigures()],
                ),
              ),
            ),
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  BidiText(
                    programme.displayTitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  if (live) ...<Widget>[
                    const SizedBox(height: 5),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(99),
                      child: LinearProgressIndicator(
                        value: programme.progressAt(now),
                        minHeight: 3,
                        color: colors.accent,
                        backgroundColor: Colors.white.withValues(alpha: 0.14),
                      ),
                    ),
                  ] else if ((programme.subTitle ?? '').isNotEmpty)
                    BidiText(
                      programme.subTitle!,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.55),
                        fontSize: 12.5,
                      ),
                    ),
                ],
              ),
            ),
            if (programme.hasRecording)
              Padding(
                padding: const EdgeInsetsDirectional.only(start: 8),
                child: Icon(
                  Icons.fiber_manual_record_rounded,
                  size: 14,
                  color: programme.dvrState == 'recording'
                      ? const Color(0xFFE5484D)
                      : colors.accent,
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _Details extends StatelessWidget {
  const _Details({
    required this.programme,
    required this.now,
    required this.use24,
    required this.canRecord,
    required this.onRecord,
    required this.onRecordSeries,
  });

  final Programme programme;
  final DateTime now;
  final bool use24;
  final bool canRecord;
  final VoidCallback onRecord;
  final VoidCallback onRecordSeries;

  String? _series(AppStrings strings) {
    final parts = <String>[
      if (programme.season != null)
        programme.seasonCount != null
            ? strings.seasonOf(programme.season!, programme.seasonCount!)
            : strings.seasonN(programme.season!),
      if (programme.episodeNumber != null)
        programme.episodeCount != null
            ? strings.episodeOf(programme.episodeNumber!, programme.episodeCount!)
            : strings.episodeN(programme.episodeNumber!),
      if (programme.firstAired != null)
        strings.firstAiredOn(strings.formatDate(programme.firstAired!)),
    ];
    return parts.isEmpty ? null : parts.join(' · ');
  }

  static IconData _roleIcon(String role) {
    switch (role.toLowerCase()) {
      case 'director':
        return Icons.movie_creation_outlined;
      case 'presenter':
      case 'commentator':
      case 'guest':
        return Icons.mic_none_rounded;
      case 'writer':
        return Icons.edit_outlined;
      case 'producer':
        return Icons.business_center_outlined;
      case 'composer':
        return Icons.music_note_outlined;
      case 'actor':
        return Icons.theater_comedy_outlined;
      default:
        return Icons.person_outline_rounded;
    }
  }

  Widget _row(IconData icon, String text, {Color? color, double? size}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 5),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Padding(
            padding: const EdgeInsets.only(top: 1),
            child: Icon(icon, size: 17, color: Colors.white.withValues(alpha: 0.6)),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: BidiText(
              text,
              style: TextStyle(
                color: color ?? Colors.white.withValues(alpha: 0.82),
                fontSize: size ?? 13.5,
                height: 1.3,
              ),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final strings = context.strings;
    final colors = context.mawjColors;
    final minutes = programme.stop.difference(programme.start).inMinutes;
    final series = _series(strings);
    final credits = <(String, String)>[];
    final rawCredits = programme.credits;
    if (rawCredits != null) {
      for (final part in rawCredits.split(' · ')) {
        final colon = part.indexOf(': ');
        if (colon > 0) {
          credits.add((part.substring(0, colon), part.substring(colon + 2)));
        }
      }
    }
    final rating = programme.rating;
    final age = programme.ageRating;
    final categories = programme.categories.isNotEmpty
        ? programme.categories.join(' · ')
        : programme.genre;
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(18, 12, 18, 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          BidiText(
            programme.title,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 21,
              fontWeight: FontWeight.w800,
              height: 1.2,
            ),
          ),
          if ((programme.subTitle ?? '').isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 3),
              child: BidiText(
                programme.subTitle!,
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.75),
                  fontSize: 15,
                ),
              ),
            ),
          const SizedBox(height: 10),
          _row(
            Icons.schedule_rounded,
            strings.formatRange(programme.start, programme.stop, use24HourTime: use24),
            color: colors.accent,
          ),
          _row(Icons.calendar_today_rounded, strings.formatDate(programme.start)),
          _row(Icons.timelapse_rounded, '$minutes ${strings.minutesShort}'),
          if (programme.episode != null && programme.episode!.isNotEmpty)
            _row(Icons.video_library_outlined, programme.episode!),
          if (series != null) _row(Icons.layers_outlined, series),
          if (rating != null && rating > 0)
            _row(Icons.star_rounded, rating.toStringAsFixed(1)),
          if (age != null && age > 0) _row(Icons.shield_outlined, '$age+'),
          if (categories != null && categories.isNotEmpty)
            _row(Icons.category_outlined, categories),
          if (programme.year != null && programme.year! > 0)
            _row(Icons.event_note_outlined, '${programme.year}'),
          if (programme.badges.isNotEmpty) ...<Widget>[
            const SizedBox(height: 3),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: <Widget>[
                for (final badge in programme.badges)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.10),
                      borderRadius: BorderRadius.circular(7),
                    ),
                    child: Text(
                      badge,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 11.5,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
              ],
            ),
          ],
          if ((programme.description ?? '').isNotEmpty) ...<Widget>[
            const SizedBox(height: 10),
            BidiText(
              programme.description!,
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.82),
                fontSize: 14.5,
                height: 1.45,
              ),
            ),
          ],
          if (credits.isNotEmpty) ...<Widget>[
            const SizedBox(height: 10),
            for (final credit in credits)
              _row(_roleIcon(credit.$1), credit.$2),
          ],
          const SizedBox(height: 12),
          if (programme.hasRecording)
            Text(
              programme.dvrState == 'recording'
                  ? strings.recordingNow
                  : strings.scheduled,
              style: TextStyle(
                color: colors.accent,
                fontSize: 14,
                fontWeight: FontWeight.w800,
              ),
            )
          else if (canRecord)
            Wrap(
              spacing: 10,
              runSpacing: 8,
              children: <Widget>[
                FilledButton.icon(
                  onPressed: onRecord,
                  icon: const Icon(Icons.fiber_manual_record_rounded, size: 16),
                  label: Text(strings.record),
                ),
                OutlinedButton.icon(
                  onPressed: onRecordSeries,
                  icon: const Icon(Icons.repeat_rounded, size: 16),
                  label: Text(strings.recordSeries),
                ),
              ],
            ),
        ],
      ),
    );
  }
}
