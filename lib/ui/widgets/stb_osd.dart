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
        final width = _panelWidth(constraints.maxWidth, 560);
        return Align(
          alignment: const Alignment(0, 0.66),
          child: Container(
            width: width,
            padding: const EdgeInsets.fromLTRB(22, 18, 24, 18),
            decoration: _panel(colors.accent),
            child: Row(
              children: <Widget>[
                Container(
                  width: 52,
                  height: 52,
                  decoration: BoxDecoration(
                    color: colors.accent,
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Icon(icon, color: const Color(0xFF0A111E), size: 28),
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
                          fontSize: 22,
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
                              fontSize: 15,
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
    this.nowTitle,
    this.nowRange,
    this.progress,
    this.nowDescription,
    this.nextTitle,
    this.nextRange,
    this.chips = const <String>[],
    this.signal,
    this.recording = false,
  });

  final Widget logo;
  final String number;
  final String name;
  final String clock;
  final String nowLabel;
  final String nextLabel;
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
}

/// The lower-third channel banner: logo, name, now and next with progress,
/// stream details and signal.
class StbBanner extends StatelessWidget {
  const StbBanner({super.key, required this.data});

  final StbBannerData data;

  @override
  Widget build(BuildContext context) {
    final colors = context.mawjColors;
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = _panelWidth(constraints.maxWidth, 1120);
        final wide = width >= 820;
        final details = Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: <Widget>[
                for (final chip in data.chips) _Chip(text: chip),
              ],
            ),
            if (data.signal != null) ...<Widget>[
              const SizedBox(height: 12),
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
                    padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
                    margin: const EdgeInsetsDirectional.only(end: 10),
                    decoration: BoxDecoration(
                      color: colors.accent,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      data.number,
                      style: const TextStyle(
                        color: Color(0xFF0A111E),
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
                        fontFeatures: <FontFeature>[FontFeature.tabularFigures()],
                      ),
                    ),
                  ),
                Expanded(
                  child: BidiText(
                    data.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 24,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
                if (data.recording)
                  const Padding(
                    padding: EdgeInsetsDirectional.only(end: 12),
                    child: _RecDot(),
                  ),
                Text(
                  data.clock,
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.85),
                    fontSize: 20,
                    fontWeight: FontWeight.w600,
                    fontFeatures: const <FontFeature>[
                      FontFeature.tabularFigures(),
                    ],
                  ),
                ),
              ],
            ),
            if (data.nowTitle != null) ...<Widget>[
              const SizedBox(height: 14),
              Row(
                children: <Widget>[
                  Text(
                    data.nowLabel.toUpperCase(),
                    style: TextStyle(
                      color: colors.accent,
                      fontSize: 12,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 1.4,
                    ),
                  ),
                  const SizedBox(width: 10),
                  if (data.nowRange != null)
                    Text(
                      data.nowRange!,
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.6),
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 3),
              BidiText(
                data.nowTitle!,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 19,
                  fontWeight: FontWeight.w700,
                ),
              ),
              if (data.progress != null) ...<Widget>[
                const SizedBox(height: 8),
                ClipRRect(
                  borderRadius: BorderRadius.circular(99),
                  child: LinearProgressIndicator(
                    value: data.progress!.clamp(0.0, 1.0).toDouble(),
                    minHeight: 5,
                    backgroundColor: Colors.white.withValues(alpha: 0.16),
                    color: colors.accent,
                  ),
                ),
              ],
              if (wide && (data.nowDescription ?? '').isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: BidiText(
                    data.nowDescription!,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.65),
                      fontSize: 13,
                      height: 1.35,
                    ),
                  ),
                ),
            ],
            if (data.nextTitle != null) ...<Widget>[
              const SizedBox(height: 12),
              Row(
                children: <Widget>[
                  Text(
                    data.nextLabel.toUpperCase(),
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.5),
                      fontSize: 12,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 1.4,
                    ),
                  ),
                  const SizedBox(width: 10),
                  if (data.nextRange != null)
                    Text(
                      data.nextRange!,
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.5),
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: BidiText(
                      data.nextTitle!,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.78),
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
            ],
            if (!wide) ...<Widget>[
              const SizedBox(height: 12),
              details,
            ],
          ],
        );

        return Align(
          alignment: Alignment.bottomCenter,
          child: Container(
            width: width,
            margin: const EdgeInsets.only(bottom: 96),
            padding: const EdgeInsets.all(20),
            decoration: _panel(colors.accent),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: <Widget>[
                data.logo,
                const SizedBox(width: 20),
                Expanded(child: main),
                if (wide) ...<Widget>[
                  const SizedBox(width: 20),
                  Container(
                    width: 1,
                    height: 120,
                    color: Colors.white.withValues(alpha: 0.12),
                  ),
                  const SizedBox(width: 20),
                  SizedBox(width: 230, child: details),
                ],
              ],
            ),
          ),
        );
      },
    );
  }
}

class _Chip extends StatelessWidget {
  const _Chip({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.09),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.white.withValues(alpha: 0.10)),
      ),
      child: Text(
        text,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 12,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

class _RecDot extends StatelessWidget {
  const _RecDot();

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Container(
          width: 10,
          height: 10,
          decoration: const BoxDecoration(
            color: Color(0xFFE5484D),
            shape: BoxShape.circle,
          ),
        ),
        const SizedBox(width: 6),
        const Text(
          'REC',
          style: TextStyle(
            color: Color(0xFFE5484D),
            fontSize: 13,
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
