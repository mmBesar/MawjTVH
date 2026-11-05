import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/bidi.dart';
import '../../core/theme.dart';
import '../../data/models.dart';
import '../../l10n/strings.dart';
import '../../l10n/tvh_strings.dart';
import 'channel_logo.dart';
import 'stb_osd.dart';
import 'wheel_scroll.dart';

/// The channel list that slides over the picture: tags across the top, the
/// channels with what is on now below. Fully usable from the keyboard (arrows,
/// Enter, type to search) and the mouse (click, wheel, hover).
class StbChannelBrowser extends StatefulWidget {
  const StbChannelBrowser({
    super.key,
    required this.channels,
    required this.favorites,
    required this.groups,
    required this.initialGroup,
    required this.current,
    required this.now,
    required this.nowFor,
    required this.allowInsecure,
    required this.onTune,
    required this.onGroupChanged,
    required this.onClose,
  });

  final List<Channel> channels;
  final List<Channel> favorites;
  final List<String> groups;
  final String? initialGroup;
  final Channel current;
  final DateTime now;
  final Programme? Function(Channel channel) nowFor;
  final bool allowInsecure;
  final void Function(Channel channel) onTune;

  /// Called with the chosen tag, or null for "All".
  final void Function(String? group) onGroupChanged;
  final VoidCallback onClose;

  @override
  State<StbChannelBrowser> createState() => _StbChannelBrowserState();
}

class _StbChannelBrowserState extends State<StbChannelBrowser> {
  static const double _rowHeight = 68;

  final FocusNode _focus = FocusNode(debugLabel: 'stb-browser');
  final TextEditingController _search = TextEditingController();
  final ScrollController _scroll = ScrollController();
  final ScrollController _tabScroll = ScrollController();
  late final List<GlobalKey> _tabKeys;
  int _tab = 0;
  int _selected = 0;
  String _query = '';
  List<Channel> _visible = const <Channel>[];

  int get _tabCount => widget.groups.length + 2;

  @override
  void initState() {
    super.initState();
    _tabKeys = List<GlobalKey>.generate(_tabCount, (_) => GlobalKey());
    final group = widget.initialGroup;
    final index = group == null ? -1 : widget.groups.indexOf(group);
    _tab = index < 0 ? 0 : index + 2;
    _refresh(keepCurrent: true);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      // The player already holds the focus, so autofocus would be ignored.
      _focus.requestFocus();
      _centerSelection();
      _showTab();
    });
  }

  @override
  void dispose() {
    _focus.dispose();
    _search.dispose();
    _scroll.dispose();
    _tabScroll.dispose();
    super.dispose();
  }

  List<Channel> _base() {
    if (_tab == 0) {
      return widget.channels;
    }
    if (_tab == 1) {
      return widget.favorites;
    }
    final group = widget.groups[_tab - 2];
    return <Channel>[
      for (final channel in widget.channels)
        if (channel.group == group) channel,
    ];
  }

  void _refresh({bool keepCurrent = false}) {
    final query = _query.trim().toLowerCase();
    final base = _base();
    _visible = query.isEmpty
        ? base
        : <Channel>[
            for (final channel in base)
              if (channel.name.toLowerCase().contains(query) ||
                  channel.number.startsWith(query))
                channel,
          ];
    if (keepCurrent) {
      final index = _visible.indexWhere((c) => c.id == widget.current.id);
      _selected = index < 0 ? 0 : index;
    } else {
      _selected = _selected.clamp(0, _visible.isEmpty ? 0 : _visible.length - 1);
    }
  }

  void _centerSelection() {
    if (!_scroll.hasClients) {
      return;
    }
    final viewport = _scroll.position.viewportDimension;
    final target = _selected * _rowHeight - (viewport - _rowHeight) / 2;
    _scroll.jumpTo(target.clamp(0.0, _scroll.position.maxScrollExtent).toDouble());
  }

  void _keepSelectionVisible() {
    if (!_scroll.hasClients) {
      return;
    }
    final position = _scroll.position;
    final top = _selected * _rowHeight;
    final bottom = top + _rowHeight;
    if (top < position.pixels) {
      unawaited(_scroll.animateTo(
        top,
        duration: const Duration(milliseconds: 90),
        curve: Curves.easeOut,
      ));
    } else if (bottom > position.pixels + position.viewportDimension) {
      unawaited(_scroll.animateTo(
        bottom - position.viewportDimension,
        duration: const Duration(milliseconds: 90),
        curve: Curves.easeOut,
      ));
    }
  }

  void _showTab() {
    final tabContext = _tabKeys[_tab].currentContext;
    if (tabContext != null) {
      unawaited(Scrollable.ensureVisible(
        tabContext,
        duration: const Duration(milliseconds: 140),
        alignment: 0.5,
      ));
    }
  }

  void _move(int delta) {
    if (_visible.isEmpty) {
      return;
    }
    setState(() {
      _selected = (_selected + delta).clamp(0, _visible.length - 1);
    });
    _keepSelectionVisible();
  }

  void _setTab(int tab) {
    final next = tab.clamp(0, _tabCount - 1);
    if (next == _tab) {
      return;
    }
    setState(() {
      _tab = next;
      _selected = 0;
      _refresh();
    });
    if (next == 0) {
      widget.onGroupChanged(null);
    } else if (next >= 2) {
      widget.onGroupChanged(widget.groups[next - 2]);
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scroll.hasClients) {
        _scroll.jumpTo(0);
      }
      _showTab();
    });
  }

  void _setQuery(String query) {
    if (_search.text != query) {
      _search.text = query;
    }
    setState(() {
      _query = query;
      _selected = 0;
      _refresh();
    });
    if (_scroll.hasClients) {
      _scroll.jumpTo(0);
    }
  }

  void _tuneSelected() {
    if (_visible.isEmpty) {
      return;
    }
    widget.onTune(_visible[_selected]);
  }

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (event is KeyUpEvent) {
      return KeyEventResult.ignored;
    }
    final key = event.logicalKey;
    if (key == LogicalKeyboardKey.escape) {
      if (_query.isNotEmpty) {
        _setQuery('');
      } else {
        widget.onClose();
      }
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
      _move(8);
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.pageUp) {
      _move(-8);
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.home) {
      _move(-_visible.length);
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.end) {
      _move(_visible.length);
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.arrowRight) {
      _setTab(_tab + 1);
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.arrowLeft) {
      _setTab(_tab - 1);
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.enter ||
        key == LogicalKeyboardKey.numpadEnter) {
      _tuneSelected();
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.backspace) {
      if (_query.isNotEmpty) {
        _setQuery(_query.substring(0, _query.length - 1));
      }
      return KeyEventResult.handled;
    }
    final character = event.character;
    if (character != null &&
        character.isNotEmpty &&
        character.codeUnitAt(0) >= 32 &&
        character.codeUnitAt(0) != 127 &&
        !HardwareKeyboard.instance.isControlPressed &&
        !HardwareKeyboard.instance.isMetaPressed &&
        !HardwareKeyboard.instance.isAltPressed) {
      _setQuery(_query + character);
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  String _tabLabel(int index) {
    final strings = context.strings;
    if (index == 0) {
      return strings.stbAll;
    }
    if (index == 1) {
      return strings.stbFavorites;
    }
    return widget.groups[index - 2];
  }

  @override
  Widget build(BuildContext context) {
    final strings = context.strings;
    final colors = context.mawjColors;
    final size = MediaQuery.sizeOf(context);
    // Phones get a sheet from the bottom and a real search box; desktop gets
    // the side panel driven by keys.
    final compact = size.width < 720;
    return Focus(
      focusNode: _focus,
      onKeyEvent: compact ? null : _onKey,
      child: Stack(
        fit: StackFit.expand,
        children: <Widget>[
          Positioned.fill(
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: widget.onClose,
              child: const DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: AlignmentDirectional.centerStart,
                    end: AlignmentDirectional.centerEnd,
                    colors: <Color>[Color(0xB3000000), Color(0x00000000)],
                  ),
                ),
              ),
            ),
          ),
          Align(
            alignment: compact
                ? Alignment.bottomCenter
                : AlignmentDirectional.centerStart,
            child: Container(
              width: compact ? double.infinity : 500,
              height: compact ? size.height * 0.78 : null,
              margin: compact
                  ? const EdgeInsets.fromLTRB(8, 0, 8, 8)
                  : const EdgeInsets.fromLTRB(20, 56, 20, 20),
              decoration: stbPanelDecoration(colors.accent),
              child: Column(
                children: <Widget>[
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 16, 10, 6),
                    child: Row(
                      children: <Widget>[
                        Icon(Icons.live_tv_rounded, color: colors.accent, size: 22),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            strings.stbChannels.toUpperCase(),
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 16,
                              fontWeight: FontWeight.w800,
                              letterSpacing: 1.6,
                            ),
                          ),
                        ),
                        Text(
                          '${_visible.length}',
                          style: TextStyle(
                            color: Colors.white.withValues(alpha: 0.55),
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
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
                  SizedBox(
                    height: 42,
                    child: WheelScroll(
                      controller: _tabScroll,
                      builder: (context, controller) => SingleChildScrollView(
                      controller: controller,
                      scrollDirection: Axis.horizontal,
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: Row(
                        children: <Widget>[
                          for (var i = 0; i < _tabCount; i++)
                            Padding(
                              key: _tabKeys[i],
                              padding: const EdgeInsetsDirectional.only(end: 8),
                              child: _TabChip(
                                label: _tabLabel(i),
                                selected: i == _tab,
                                onTap: () => _setTab(i),
                              ),
                            ),
                        ],
                      ),
                    ),
                    ),
                  ),
                  Container(
                    margin: const EdgeInsets.fromLTRB(16, 8, 16, 6),
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.07),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Row(
                      children: <Widget>[
                        Icon(
                          Icons.search_rounded,
                          size: 18,
                          color: Colors.white.withValues(alpha: 0.55),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: compact
                              ? TextField(
                                  controller: _search,
                                  onChanged: _setQuery,
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 15,
                                  ),
                                  cursorColor: colors.accent,
                                  decoration: InputDecoration(
                                    isDense: true,
                                    border: InputBorder.none,
                                    enabledBorder: InputBorder.none,
                                    focusedBorder: InputBorder.none,
                                    filled: false,
                                    hintText: strings.stbSearch,
                                    hintStyle: TextStyle(
                                      color: Colors.white.withValues(alpha: 0.4),
                                    ),
                                  ),
                                )
                              : _query.isEmpty
                              ? Text(
                                  strings.stbSearch,
                                  style: TextStyle(
                                    color: Colors.white.withValues(alpha: 0.4),
                                    fontSize: 14,
                                  ),
                                )
                              : BidiText(
                                  _query,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 14,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                        ),
                        if (_query.isNotEmpty)
                          InkWell(
                            onTap: () => _setQuery(''),
                            child: const Icon(
                              Icons.close_rounded,
                              size: 16,
                              color: Colors.white54,
                            ),
                          ),
                      ],
                    ),
                  ),
                  Expanded(
                    child: _visible.isEmpty
                        ? Center(
                            child: Text(
                              strings.stbNoMatch,
                              style: TextStyle(
                                color: Colors.white.withValues(alpha: 0.55),
                                fontSize: 14,
                              ),
                            ),
                          )
                        : ListView.builder(
                            controller: _scroll,
                            itemExtent: _rowHeight,
                            padding: const EdgeInsets.symmetric(horizontal: 8),
                            itemCount: _visible.length,
                            itemBuilder: (context, index) {
                              final channel = _visible[index];
                              return _ChannelRow(
                                channel: channel,
                                programme: widget.nowFor(channel),
                                now: widget.now,
                                selected: index == _selected,
                                playing: channel.id == widget.current.id,
                                allowInsecure: widget.allowInsecure,
                                onHover: () {
                                  if (_selected != index) {
                                    setState(() => _selected = index);
                                  }
                                },
                                onTap: () => widget.onTune(channel),
                              );
                            },
                          ),
                  ),
                  if (!compact)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(18, 8, 18, 14),
                    child: Text(
                      strings.stbBrowserHint,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.45),
                        fontSize: 11.5,
                        height: 1.4,
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
}

class _TabChip extends StatelessWidget {
  const _TabChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.mawjColors;
    return Material(
      color: selected ? colors.accent : Colors.white.withValues(alpha: 0.09),
      borderRadius: BorderRadius.circular(999),
      child: InkWell(
        borderRadius: BorderRadius.circular(999),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          child: BidiText(
            label,
            maxLines: 1,
            style: TextStyle(
              color: selected ? const Color(0xFF0A111E) : Colors.white,
              fontSize: 13,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      ),
    );
  }
}

class _ChannelRow extends StatelessWidget {
  const _ChannelRow({
    required this.channel,
    required this.programme,
    required this.now,
    required this.selected,
    required this.playing,
    required this.allowInsecure,
    required this.onHover,
    required this.onTap,
  });

  final Channel channel;
  final Programme? programme;
  final DateTime now;
  final bool selected;
  final bool playing;
  final bool allowInsecure;
  final VoidCallback onHover;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.mawjColors;
    final programme = this.programme;
    return MouseRegion(
      onEnter: (_) => onHover(),
      child: GestureDetector(
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
                width: 42,
                child: Text(
                  channel.displayNumber,
                  style: TextStyle(
                    color: playing ? colors.accent : Colors.white70,
                    fontSize: 14,
                    fontWeight: FontWeight.w800,
                    fontFeatures: const <FontFeature>[
                      FontFeature.tabularFigures(),
                    ],
                  ),
                ),
              ),
              ChannelLogo(
                channel: channel,
                allowInsecure: allowInsecure,
                size: 40,
                radius: 10,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Row(
                      children: <Widget>[
                        Expanded(
                          child: BidiText(
                            channel.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 15,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                        if (playing)
                          Icon(Icons.play_arrow_rounded, size: 18, color: colors.accent),
                      ],
                    ),
                    if (programme != null) ...<Widget>[
                      const SizedBox(height: 1),
                      BidiText(
                        programme.displayTitle,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.62),
                          fontSize: 12,
                        ),
                      ),
                      const SizedBox(height: 4),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(99),
                        child: LinearProgressIndicator(
                          value: programme.progressAt(now),
                          minHeight: 3,
                          color: colors.accent,
                          backgroundColor: Colors.white.withValues(alpha: 0.14),
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
    );
  }
}

/// A cheat sheet of every key, opened with H, F1 or the keyboard button.
class StbHelpOverlay extends StatelessWidget {
  const StbHelpOverlay({super.key, required this.onClose});

  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    final strings = context.strings;
    final colors = context.mawjColors;
    final rows = strings.shortcutHelp;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onClose,
      child: ColoredBox(
        color: const Color(0xB3000000),
        child: Center(
          child: Container(
            constraints: const BoxConstraints(maxWidth: 760, maxHeight: 620),
            margin: const EdgeInsets.all(24),
            padding: const EdgeInsets.fromLTRB(28, 22, 28, 22),
            decoration: stbPanelDecoration(colors.accent),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Row(
                  children: <Widget>[
                    Icon(Icons.keyboard_alt_outlined, color: colors.accent),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        strings.stbHelpTitle.toUpperCase(),
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 17,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 1.6,
                        ),
                      ),
                    ),
                    IconButton(
                      tooltip: strings.close,
                      onPressed: onClose,
                      icon: const Icon(Icons.close_rounded, color: Colors.white70),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                Flexible(
                  child: SingleChildScrollView(
                    child: Column(
                      children: <Widget>[
                        for (final row in rows)
                          Padding(
                            padding: const EdgeInsets.symmetric(vertical: 5),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: <Widget>[
                                SizedBox(
                                  width: 220,
                                  child: Wrap(
                                    spacing: 6,
                                    runSpacing: 4,
                                    children: <Widget>[
                                      for (final key in row.$1.split(' '))
                                        Container(
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 8,
                                            vertical: 3,
                                          ),
                                          decoration: BoxDecoration(
                                            color: Colors.white.withValues(alpha: 0.10),
                                            borderRadius: BorderRadius.circular(7),
                                            border: Border.all(
                                              color: Colors.white.withValues(alpha: 0.14),
                                            ),
                                          ),
                                          child: Text(
                                            key,
                                            style: const TextStyle(
                                              color: Colors.white,
                                              fontSize: 12,
                                              fontWeight: FontWeight.w800,
                                            ),
                                          ),
                                        ),
                                    ],
                                  ),
                                ),
                                const SizedBox(width: 16),
                                Expanded(
                                  child: Text(
                                    row.$2,
                                    style: TextStyle(
                                      color: Colors.white.withValues(alpha: 0.85),
                                      fontSize: 14,
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
              ],
            ),
          ),
        ),
      ),
    );
  }
}
