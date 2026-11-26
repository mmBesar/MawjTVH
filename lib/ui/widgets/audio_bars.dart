import 'dart:math' as math;

import 'package:flutter/material.dart';

/// A small equaliser: bars that dance while [playing] and rest low when not.
///
/// The motion is decorative. The audio is decoded inside libmpv and no level
/// meter is exposed to the app, so the bars do not follow the actual sound.
class AudioBars extends StatefulWidget {
  const AudioBars({
    super.key,
    required this.playing,
    required this.color,
    this.bars = 5,
    this.height = 24,
    this.barWidth = 4,
    this.gap = 3,
    this.animate = true,
  });

  final bool playing;
  final Color color;
  final int bars;
  final double height;
  final double barWidth;
  final double gap;

  /// False when the person asked for reduced motion: the bars stay still.
  final bool animate;

  @override
  State<AudioBars> createState() => _AudioBarsState();
}

class _AudioBarsState extends State<AudioBars>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1400),
  );

  bool get _moving => widget.playing && widget.animate;

  @override
  void initState() {
    super.initState();
    if (_moving) {
      _controller.repeat();
    }
  }

  @override
  void didUpdateWidget(AudioBars oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (_moving && !_controller.isAnimating) {
      _controller.repeat();
    } else if (!_moving && _controller.isAnimating) {
      _controller.stop();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  /// Height of bar [index] from 0.18 to 1, from two sines that never line up.
  double _level(int index, double t) {
    final phase = index * 1.7;
    final a = math.sin(2 * math.pi * (t * (1 + index % 3)) + phase);
    final b = math.sin(2 * math.pi * (t * (2 + index % 2)) + phase * 2.3);
    return 0.18 + 0.82 * ((a + b) / 4 + 0.5).clamp(0.0, 1.0);
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: widget.height,
      child: AnimatedBuilder(
        animation: _controller,
        builder: (context, child) {
          return Row(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: <Widget>[
              for (var i = 0; i < widget.bars; i++) ...<Widget>[
                if (i > 0) SizedBox(width: widget.gap),
                AnimatedContainer(
                  duration: const Duration(milliseconds: 140),
                  curve: Curves.easeOut,
                  width: widget.barWidth,
                  height: widget.height *
                      (widget.playing
                          ? (widget.animate ? _level(i, _controller.value) : 0.6)
                          : 0.18),
                  decoration: BoxDecoration(
                    color: widget.color,
                    borderRadius: BorderRadius.circular(widget.barWidth),
                  ),
                ),
              ],
            ],
          );
        },
      ),
    );
  }
}
