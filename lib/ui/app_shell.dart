import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../core/app_info.dart';
import '../core/platform.dart';
import '../core/theme.dart';
import '../data/app_state.dart';
import '../l10n/strings.dart';
import '../l10n/tvh_strings.dart';
import 'pages/favorites_page.dart';
import 'pages/guide_page.dart';
import 'pages/recordings_page.dart';
import 'pages/search_page.dart';
import 'pages/settings_page.dart';
import 'pages/sources_page.dart';
import 'pages/watch_page.dart';
import 'widgets/source_switcher.dart';

class AppShell extends StatefulWidget {
  const AppShell({super.key});

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  static const int _searchIndex = 4;
  int _index = 0;
  final ValueNotifier<int> _searchFocus = ValueNotifier<int>(0);
  final PageController _pageController = PageController();

  @override
  void initState() {
    super.initState();
    if (kIsDesktop) {
      HardwareKeyboard.instance.addHandler(_onKey);
    }
  }

  @override
  void dispose() {
    if (kIsDesktop) {
      HardwareKeyboard.instance.removeHandler(_onKey);
    }
    _searchFocus.dispose();
    _pageController.dispose();
    super.dispose();
  }

  void _goTo(int index) {
    setState(() => _index = index);
    if (!kIsDesktop && _pageController.hasClients) {
      unawaited(
        _pageController.animateToPage(
          index,
          duration: const Duration(milliseconds: 280),
          curve: Curves.easeOutCubic,
        ),
      );
    }
    if (index == _searchIndex) {
      _searchFocus.value++;
    }
  }

  /// The guide's timeline reports drags past its ends; they move the page
  /// view, so one swipe scrolls the timeline and, at its edge, changes page.
  void _edgeDrag(double overscroll) {
    if (!_pageController.hasClients) {
      return;
    }
    final rtl = Directionality.of(context) == TextDirection.rtl;
    final position = _pageController.position;
    final target = (position.pixels + (rtl ? -overscroll : overscroll))
        .clamp(position.minScrollExtent, position.maxScrollExtent)
        .toDouble();
    _pageController.jumpTo(target);
  }

  void _edgeDragEnd() {
    if (!_pageController.hasClients) {
      return;
    }
    final page = _pageController.page;
    if (page == null || page == page.roundToDouble()) {
      return;
    }
    unawaited(
      _pageController.animateToPage(
        page.round(),
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOutCubic,
      ),
    );
  }

  /// Ctrl+1..6 switch tab, Ctrl+F / Ctrl+K search, Ctrl+R refresh. This is a
  /// global handler so it works wherever keyboard focus happens to be, and
  /// stays quiet while another page (the player, a sheet) is on top.
  bool _onKey(KeyEvent event) {
    if (event is! KeyDownEvent || !mounted) {
      return false;
    }
    if (!HardwareKeyboard.instance.isControlPressed) {
      return false;
    }
    if (ModalRoute.of(context)?.isCurrent != true) {
      return false;
    }
    final key = event.logicalKey;
    final tabs = <LogicalKeyboardKey>[
      LogicalKeyboardKey.digit1,
      LogicalKeyboardKey.digit2,
      LogicalKeyboardKey.digit3,
      LogicalKeyboardKey.digit4,
      LogicalKeyboardKey.digit5,
      LogicalKeyboardKey.digit6,
    ];
    final tab = tabs.indexOf(key);
    if (tab >= 0) {
      _goTo(tab);
      return true;
    }
    if (key == LogicalKeyboardKey.keyF || key == LogicalKeyboardKey.keyK) {
      _goTo(_searchIndex);
      return true;
    }
    if (key == LogicalKeyboardKey.keyR) {
      unawaited(context.read<AppState>().refresh());
      return true;
    }
    return false;
  }

  void _openSources() {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (context) => Scaffold(
          appBar: AppBar(),
          body: const SourcesPage(),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final strings = context.strings;
    final colors = context.mawjColors;

    final pages = <Widget>[
      WatchPage(onOpenSources: _openSources),
      const FavoritesPage(),
      GuidePage(
        onOpenSources: _openSources,
        onEdgeDrag: kIsDesktop ? null : _edgeDrag,
        onEdgeDragEnd: kIsDesktop ? null : _edgeDragEnd,
      ),
      const RecordingsPage(),
      SearchPage(focusRequests: _searchFocus),
      SettingsPage(onOpenSources: _openSources),
    ];
    final labels = <String>[
      strings.watch,
      strings.favorites,
      strings.guide,
      strings.recordings,
      strings.search,
      strings.settings,
    ];
    const icons = <IconData>[
      Icons.live_tv_rounded,
      Icons.star_rounded,
      Icons.calendar_month_rounded,
      Icons.fiber_manual_record_rounded,
      Icons.search_rounded,
      Icons.tune_rounded,
    ];

    final content = Stack(
      fit: StackFit.expand,
      children: <Widget>[
        // A faint glow in one corner: the only decoration on the screen.
        PositionedDirectional(
          top: -140,
          end: -100,
          child: IgnorePointer(
            child: Container(
              width: 380,
              height: 380,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(
                  colors: <Color>[
                    colors.accent.withValues(alpha: 0.14),
                    colors.accent.withValues(alpha: 0),
                  ],
                ),
              ),
            ),
          ),
        ),
        if (kIsDesktop)
          IndexedStack(index: _index, children: pages)
        else
          PageView(
            controller: _pageController,
            physics: const ClampingScrollPhysics(),
            onPageChanged: (index) {
              if (index != _index) {
                setState(() => _index = index);
              }
            },
            children: <Widget>[
              for (final page in pages) _KeepAlive(child: page),
            ],
          ),
      ],
    );

    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth >= 900) {
          final compact = constraints.maxWidth < 1180;
          return Scaffold(
            body: Row(
              children: <Widget>[
                _Sidebar(
                  compact: compact,
                  labels: labels,
                  icons: icons,
                  selected: _index,
                  onSelected: _goTo,
                  onOpenSources: _openSources,
                ),
                Expanded(child: content),
              ],
            ),
          );
        }

        return Scaffold(
          body: Stack(
            children: <Widget>[
              Positioned.fill(child: content),
              Positioned(
                left: 0,
                right: 0,
                bottom: MediaQuery.viewPaddingOf(context).bottom + 14,
                child: Center(
                  child: _FloatingNav(
                    labels: labels,
                    icons: icons,
                    selected: _index,
                    onSelected: _goTo,
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

/// The phone navigation: a floating pill where only the selected item shows
/// its label.
class _FloatingNav extends StatelessWidget {
  const _FloatingNav({
    required this.labels,
    required this.icons,
    required this.selected,
    required this.onSelected,
  });

  final List<String> labels;
  final List<IconData> icons;
  final int selected;
  final ValueChanged<int> onSelected;

  @override
  Widget build(BuildContext context) {
    final colors = context.mawjColors;
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.all(6),
      decoration: BoxDecoration(
        color: colors.surface0.withValues(alpha: 0.96),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: colors.surface1),
        boxShadow: <BoxShadow>[
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.35),
            blurRadius: 24,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          for (var index = 0; index < labels.length; index++)
            _NavItem(
              label: labels[index],
              icon: icons[index],
              selected: index == selected,
              accent: colors.accent,
              onAccent: theme.colorScheme.onPrimary,
              idle: colors.subtext0,
              onTap: () => onSelected(index),
            ),
        ],
      ),
    );
  }
}

class _NavItem extends StatelessWidget {
  const _NavItem({
    required this.label,
    required this.icon,
    required this.selected,
    required this.accent,
    required this.onAccent,
    required this.idle,
    required this.onTap,
  });

  final String label;
  final IconData icon;
  final bool selected;
  final Color accent;
  final Color onAccent;
  final Color idle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      selected: selected,
      label: label,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeOutCubic,
          height: 48,
          padding: EdgeInsets.symmetric(horizontal: selected ? 18 : 14),
          decoration: BoxDecoration(
            color: selected ? accent : Colors.transparent,
            borderRadius: BorderRadius.circular(999),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Icon(icon, size: 24, color: selected ? onAccent : idle),
              AnimatedSize(
                duration: const Duration(milliseconds: 220),
                curve: Curves.easeOutCubic,
                child: selected
                    ? Padding(
                        padding: const EdgeInsetsDirectional.only(start: 8),
                        child: Text(
                          label,
                          maxLines: 1,
                          style: TextStyle(
                            color: onAccent,
                            fontWeight: FontWeight.w800,
                            fontSize: 14,
                          ),
                        ),
                      )
                    : const SizedBox.shrink(),
              ),
            ],
          ),
        ),
      ),
    );
  }
}


/// The desktop navigation: a fixed sidebar with the wordmark, the four
/// sections (with hover and keyboard hints), and the active source at the
/// bottom.
class _Sidebar extends StatelessWidget {
  const _Sidebar({
    required this.compact,
    required this.labels,
    required this.icons,
    required this.selected,
    required this.onSelected,
    required this.onOpenSources,
  });

  final bool compact;
  final List<String> labels;
  final List<IconData> icons;
  final int selected;
  final ValueChanged<int> onSelected;
  final VoidCallback onOpenSources;

  @override
  Widget build(BuildContext context) {
    final colors = context.mawjColors;
    final theme = Theme.of(context);
    final state = context.watch<AppState>();
    final sourceName = state.activeSource?.name ?? '';

    return Container(
      width: compact ? 76 : 244,
      decoration: BoxDecoration(
        color: colors.mantle,
        border: BorderDirectional(
          end: BorderSide(color: colors.surface0.withValues(alpha: 0.8)),
        ),
      ),
      padding: EdgeInsets.fromLTRB(compact ? 12 : 16, 20, compact ? 12 : 16, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Row(
            mainAxisAlignment:
                compact ? MainAxisAlignment.center : MainAxisAlignment.start,
            children: <Widget>[
              ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: Image.asset(
                  'assets/branding/mawjtvh_icon.png',
                  width: 40,
                  height: 40,
                ),
              ),
              if (!compact) ...<Widget>[
                const SizedBox(width: 12),
                Text(
                  'MawjTVH',
                  style: theme.textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.3,
                  ),
                ),
              ],
            ],
          ),
          const SizedBox(height: 28),
          for (var index = 0; index < labels.length; index++)
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: _SidebarItem(
                label: labels[index],
                icon: icons[index],
                hint: 'Ctrl+${index + 1}',
                selected: index == selected,
                compact: compact,
                onTap: () => onSelected(index),
              ),
            ),
          const Spacer(),
          if (sourceName.isNotEmpty)
            Tooltip(
              message: sourceName,
              child: InkWell(
                borderRadius: BorderRadius.circular(14),
                onTap: () => showSourceSwitcher(
                  context,
                  onManage: onOpenSources,
                ),
                child: Padding(
                  padding: const EdgeInsets.all(10),
                  child: Row(
                    mainAxisAlignment: compact
                        ? MainAxisAlignment.center
                        : MainAxisAlignment.start,
                    children: <Widget>[
                      Icon(Icons.dns_rounded, size: 20, color: colors.subtext0),
                      if (!compact) ...<Widget>[
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            sourceName,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.bodyMedium?.copyWith(
                              color: colors.subtext1,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ),
          if (!compact)
            Padding(
              padding: const EdgeInsets.fromLTRB(10, 6, 10, 0),
              child: Text(
                'v$kAppVersion',
                style: theme.textTheme.labelSmall?.copyWith(
                  color: colors.overlay0,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _SidebarItem extends StatefulWidget {
  const _SidebarItem({
    required this.label,
    required this.icon,
    required this.hint,
    required this.selected,
    required this.compact,
    required this.onTap,
  });

  final String label;
  final IconData icon;
  final String hint;
  final bool selected;
  final bool compact;
  final VoidCallback onTap;

  @override
  State<_SidebarItem> createState() => _SidebarItemState();
}

class _SidebarItemState extends State<_SidebarItem> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final colors = context.mawjColors;
    final theme = Theme.of(context);
    final selected = widget.selected;
    final background = selected
        ? colors.accent.withValues(alpha: 0.16)
        : (_hover ? colors.surface0 : Colors.transparent);
    final foreground = selected ? colors.accent : colors.subtext1;

    return Tooltip(
      message: '${widget.label}  ${widget.hint}',
      waitDuration: const Duration(milliseconds: 500),
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        onEnter: (_) => setState(() => _hover = true),
        onExit: (_) => setState(() => _hover = false),
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: widget.onTap,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 140),
            height: 46,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            decoration: BoxDecoration(
              color: background,
              borderRadius: BorderRadius.circular(14),
            ),
            child: Row(
              mainAxisAlignment: widget.compact
                  ? MainAxisAlignment.center
                  : MainAxisAlignment.start,
              children: <Widget>[
                Icon(widget.icon, size: 22, color: foreground),
                if (!widget.compact) ...<Widget>[
                  const SizedBox(width: 14),
                  Expanded(
                    child: Text(
                      widget.label,
                      maxLines: 1,
                      style: theme.textTheme.titleSmall?.copyWith(
                        color: foreground,
                        fontWeight: selected ? FontWeight.w800 : FontWeight.w600,
                      ),
                    ),
                  ),
                  if (_hover || selected)
                    Text(
                      widget.hint,
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: colors.overlay0,
                      ),
                    ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}


/// Keeps a page's state (scroll position, search text) while it is off screen
/// in the page view.
class _KeepAlive extends StatefulWidget {
  const _KeepAlive({required this.child});

  final Widget child;

  @override
  State<_KeepAlive> createState() => _KeepAliveState();
}

class _KeepAliveState extends State<_KeepAlive>
    with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return widget.child;
  }
}
