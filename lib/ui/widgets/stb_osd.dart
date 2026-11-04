import 'package:flutter/material.dart';

import '../../core/bidi.dart';
import '../../core/theme.dart';

/// Set-top-box style on-screen displays for the desktop player: dark panels
/// in the lower third of the picture, big readable type, and a segmented
/// level bar. No blur or animation, so they cost nothing while video plays.

const Color _panelTop = Color(0xF2121C2E);
const Color _panelBottom = Color(0xF20A111E);

BoxDecoration _panel(Color accent) => BoxDecoration(
      gradient: const LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: <Color>[_panelTop, _panelBottom],
      ),
      borderRadius: BorderRadius.circular(22),
      border: Border.all(color: Colors.white.withValues(alpha: 0.10)),
      boxShadow: const <BoxShadow>[
        BoxShadow(color: Color(0x66000000), blurRadius: 24, offset: Offset(0, 8)),
      ],
    );

/// The dark glass look shared by every set-top-box panel.
BoxDecoration stbPanelDecoration(Color accent) => _panel(accent);

/// Width of an OSD panel for the space it has.
double _panelWidth(double available, double wanted) =>
    available <= 0 ? wanted : (available - 48).clamp(260.0, wanted).toDouble();

/// Volume or brightness: icon, name, big percentage and a segmented bar.
class StbValueOsd extends StatelessWidget {
  const StbValueOsd({
    super.key,
    required this.icon,
    required this.label,
    required this.value,
  });

  final IconData icon;
  final String label;
  final double value;

  static const int _segments = 30;

  @override
  Widget build(BuildContext context) {
    final colors = context.mawjColors;
    final percent = (value * 100).round();
    final filled = (value * _segments).round().clamp(0, _segments);
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = _panelWidth(constraints.maxWidth, 640);
        final big = width >= 520;
        return Align(
          alignment: const Alignment(0, 0.66),
          child: Container(
            width: width,
            padding: EdgeInsets.fromLTRB(big ? 28 : 18, 20, big ? 28 : 18, 22),
            decoration: _panel(colors.accent),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Row(
                  children: <Widget>[
                    Container(
                      width: big ? 56 : 44,
                      height: big ? 56 : 44,
                      decoration: BoxDecoration(
                        color: colors.accent,
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: Icon(
                        icon,
                        color: const Color(0xFF0A111E),
                        size: big ? 30 : 24,
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Text(
                        label.toUpperCase(),
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.82),
                          fontSize: big ? 18 : 14,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 1.6,
                        ),
                      ),
                    ),
                    Text(
                      '$percent',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: big ? 52 : 38,
                        fontWeight: FontWeight.w800,
                        height: 1,
                        fontFeatures: const <FontFeature>[
                          FontFeature.tabularFigures(),
                        ],
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.only(top: 12, left: 4),
                      child: Text(
                        '%',
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.6),
                          fontSize: big ? 20 : 15,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 18),
                Row(
                  children: <Widget>[
                    for (var i = 0; i < _segments; i++)
                      Expanded(
                        child: Container(
                          height: big ? 14 : 10,
                          margin: const EdgeInsets.symmetric(horizontal: 1.5),
                          decoration: BoxDecoration(
                            color: i < filled
                                ? colors.accent
                                : Colors.white.withValues(alpha: 0.14),
                            borderRadius: BorderRadius.circular(3),
                          ),
                        ),
                      ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

/// A short notice (muted, audio track, subtitles, recording...).
class StbMessageOsd extends StatelessWidget {
  const StbMessageOsd({
    super.key,
    required this.icon,
    required this.title,
    this.subtitle,
  });

  final IconData icon;
  final String title;
  final String? subtitle;

  @override
  Widget build(BuildContext context) {
    final colors = context.mawjColors;
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = _panelWidth(constraints.maxWidth, 680);
        return Align(
          alignment: const Alignment(0, 0.66),
          child: Container(
            width: width,
            padding: const EdgeInsets.fromLTRB(26, 22, 28, 22),
            decoration: _panel(colors.accent),
            child: Row(
              children: <Widget>[
                Container(
                  width: 64,
                  height: 64,
                  decoration: BoxDecoration(
                    color: colors.accent,
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Icon(icon, color: const Color(0xFF0A111E), size: 36),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      BidiText(
                        title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 30,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      if (subtitle != null && subtitle!.isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.only(top: 3),
                          child: BidiText(
                            subtitle!,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: Colors.white.withValues(alpha: 0.7),
                              fontSize: 20,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

/// What the channel banner shows.
class StbBannerData {
  const StbBannerData({
    required this.logo,
    required this.number,
    required this.name,
    required this.clock,
    required this.nowLabel,
    required this.nextLabel,
    required this.pinned,
    required this.pinTooltip,
    required this.onPin,
    required this.onClose,
    this.nowTitle,
    this.nowRange,
    this.progress,
    this.nowDescription,
    this.nextTitle,
    this.nextRange,
    this.chips = const <String>[],
    this.signal,
    this.recording = false,
    this.bottomInset = 96,
  });

  final Widget logo;
  final String number;
  final String name;
  final String clock;
  final String nowLabel;
  final String nextLabel;
  final bool pinned;
  final String pinTooltip;
  final VoidCallback onPin;
  final VoidCallback onClose;
  final String? nowTitle;
  final String? nowRange;
  final double? progress;
  final String? nowDescription;
  final String? nextTitle;
  final String? nextRange;

  /// Stream facts: `1920×1080`, `H264`, `AC3 5.1`...
  final List<String> chips;

  /// A signal meter, when the account can see tuner status.
  final Widget? signal;
  final bool recording;

  /// Space kept free under the banner (the control bar).
  final double bottomInset;
}

/// The lower-third channel banner: logo, name, now and next with progress,
/// stream details and signal. It is as wide as the window allows and its type
/// scales down with the window, so it stays readable and never overflows.
class StbBanner extends StatelessWidget {
  const StbBanner({super.key, required this.data});

  final StbBannerData data;

  @override
  Widget build(BuildContext context) {
    final colors = context.mawjColors;
    return LayoutBuilder(
      builder: (context, constraints) {
        final available = constraints.maxWidth;
        final width = available <= 0
            ? 1200.0
            : (available * 0.96).clamp(280.0, 1560.0).toDouble();
        // 1.0 at 1500 logical pixels wide; smaller windows shrink the type.
        final k = (width / 1500).clamp(0.62, 1.1).toDouble();
        double f(double value) => value * k;
        final wide = width >= 860;

        final details = Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Wrap(
              spacing: f(8),
              runSpacing: f(8),
              children: <Widget>[
                for (final chip in data.chips) _Chip(text: chip, scale: k),
              ],
            ),
            if (data.signal != null) ...<Widget>[
              SizedBox(height: f(16)),
              data.signal!,
            ],
          ],
        );

        final main = Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(
              children: <Widget>[
                if (data.number.isNotEmpty)
                  Container(
                    padding: EdgeInsets.symmetric(
                      horizontal: f(12),
                      vertical: f(4),
                    ),
                    margin: const EdgeInsetsDirectional.only(end: 12),
                    decoration: BoxDecoration(
                      color: colors.accent,
                      borderRadius: BorderRadius.circular(f(10)),
                    ),
                    child: Text(
                      data.number,
                      style: TextStyle(
                        color: const Color(0xFF0A111E),
                        fontSize: f(24),
                        fontWeight: FontWeight.w800,
                        fontFeatures: const <FontFeature>[
                          FontFeature.tabularFigures(),
                        ],
                      ),
                    ),
                  ),
                Expanded(
                  child: BidiText(
                    data.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: f(34),
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
                if (data.recording)
                  Padding(
                    padding: const EdgeInsetsDirectional.only(end: 14),
                    child: _RecDot(scale: k),
                  ),
                Text(
                  data.clock,
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.88),
                    fontSize: f(28),
                    fontWeight: FontWeight.w600,
                    fontFeatures: const <FontFeature>[
                      FontFeature.tabularFigures(),
                    ],
                  ),
                ),
                SizedBox(width: f(6)),
              ],
            ),
            if (data.nowTitle != null) ...<Widget>[
              SizedBox(height: f(16)),
              Row(
                children: <Widget>[
                  Text(
                    data.nowLabel.toUpperCase(),
                    style: TextStyle(
                      color: colors.accent,
                      fontSize: f(16),
                      fontWeight: FontWeight.w800,
                      letterSpacing: 1.6,
                    ),
                  ),
                  const SizedBox(width: 12),
                  if (data.nowRange != null)
                    Text(
                      data.nowRange!,
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.68),
                        fontSize: f(18),
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                ],
              ),
              SizedBox(height: f(4)),
              BidiText(
                data.nowTitle!,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: Colors.white,
                  fontSize: f(30),
                  fontWeight: FontWeight.w700,
                ),
              ),
              if (data.progress != null) ...<Widget>[
                SizedBox(height: f(10)),
                ClipRRect(
                  borderRadius: BorderRadius.circular(99),
                  child: LinearProgressIndicator(
                    value: data.progress!.clamp(0.0, 1.0).toDouble(),
                    minHeight: f(7),
                    backgroundColor: Colors.white.withValues(alpha: 0.16),
                    color: colors.accent,
                  ),
                ),
              ],
              if (wide && (data.nowDescription ?? '').isNotEmpty)
                Padding(
                  padding: EdgeInsets.only(top: f(10)),
                  child: BidiText(
                    data.nowDescription!,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.7),
                      fontSize: f(19),
                      height: 1.35,
                    ),
                  ),
                ),
            ],
            if (data.nextTitle != null) ...<Widget>[
              SizedBox(height: f(14)),
              Row(
                children: <Widget>[
                  Text(
                    data.nextLabel.toUpperCase(),
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.55),
                      fontSize: f(16),
                      fontWeight: FontWeight.w800,
                      letterSpacing: 1.6,
                    ),
                  ),
                  const SizedBox(width: 12),
                  if (data.nextRange != null)
                    Text(
                      data.nextRange!,
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.55),
                        fontSize: f(17),
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: BidiText(
                      data.nextTitle!,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.82),
                        fontSize: f(21),
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
            ],
            if (!wide) ...<Widget>[
              SizedBox(height: f(14)),
              details,
            ],
          ],
        );

        final body = Padding(
          padding: EdgeInsets.fromLTRB(f(26), f(24), f(26), f(24)),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: <Widget>[
              SizedBox(
                width: f(128),
                height: f(128),
                child: FittedBox(fit: BoxFit.contain, child: data.logo),
              ),
              SizedBox(width: f(26)),
              Expanded(child: main),
              if (wide) ...<Widget>[
                SizedBox(width: f(26)),
                Container(
                  width: 1,
                  height: f(150),
                  color: Colors.white.withValues(alpha: 0.12),
                ),
                SizedBox(width: f(26)),
                SizedBox(width: f(300), child: details),
              ],
            ],
          ),
        );

        return Align(
          alignment: Alignment.bottomCenter,
          child: Container(
            width: width,
            margin: EdgeInsets.only(bottom: data.bottomInset),
            decoration: _panel(colors.accent),
            child: Stack(
              children: <Widget>[
                body,
                PositionedDirectional(
                  top: 4,
                  end: 4,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: <Widget>[
                      IconButton(
                        tooltip: data.pinTooltip,
                        onPressed: data.onPin,
                        iconSize: f(26).clamp(18.0, 30.0).toDouble(),
                        icon: Icon(
                          data.pinned
                              ? Icons.push_pin_rounded
                              : Icons.push_pin_outlined,
                          color: data.pinned
                              ? colors.accent
                              : Colors.white.withValues(alpha: 0.7),
                        ),
                      ),
                      IconButton(
                        onPressed: data.onClose,
                        iconSize: f(26).clamp(18.0, 30.0).toDouble(),
                        icon: Icon(
                          Icons.close_rounded,
                          color: Colors.white.withValues(alpha: 0.7),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _Chip extends StatelessWidget {
  const _Chip({required this.text, this.scale = 1});

  final String text;
  final double scale;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.symmetric(horizontal: 12 * scale, vertical: 6 * scale),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.09),
        borderRadius: BorderRadius.circular(10 * scale),
        border: Border.all(color: Colors.white.withValues(alpha: 0.10)),
      ),
      child: Text(
        text,
        style: TextStyle(
          color: Colors.white,
          fontSize: 17 * scale,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

class _RecDot extends StatelessWidget {
  const _RecDot({this.scale = 1});

  final double scale;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Container(
          width: 12 * scale,
          height: 12 * scale,
          decoration: const BoxDecoration(
            color: Color(0xFFE5484D),
            shape: BoxShape.circle,
          ),
        ),
        const SizedBox(width: 6),
        Text(
          'REC',
          style: TextStyle(
            color: const Color(0xFFE5484D),
            fontSize: 17 * scale,
            fontWeight: FontWeight.w800,
            letterSpacing: 1.2,
          ),
        ),
      ],
    );
  }
}

/// Small red REC badge for a corner of the picture.
class StbRecBadge extends StatelessWidget {
  const StbRecBadge({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.6),
        borderRadius: BorderRadius.circular(999),
      ),
      child: const _RecDot(),
    );
  }
}
