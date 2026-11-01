import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../core/platform.dart';

/// MawjTVH's signature element. A programme's progress is drawn as a wave: the
/// part already aired is a bright, thicker line that ends in a dot, and the
/// part still to come is a faint line along the same curve.
///
/// Lists draw it still. Only the hero cards and the player animate it, and it
/// stands still when the system asks for reduced motion.
class WaveProgress extends StatefulWidget {
  const WaveProgress({
    super.key,
    required this.progress,
    required this.color,
    required this.trackColor,
    this.height = 16,
    this.animate = false,
    this.forceAnimate = false,
  });

  /// 0 to 1: how much of the programme has aired.
  final double progress;
  final Color color;
  final Color trackColor;
  final double height;
  final bool animate;

  /// Desktop draws waves still unless this is set: a wave that moves all the
  /// time keeps the GPU busy while the window sits idle. Short-lived loading
  /// indicators set it.
  final bool forceAnimate;

  @override
  State<WaveProgress> createState() => _WaveProgressState();
}

class _WaveProgressState extends State<WaveProgress>
    with TickerProviderStateMixin {
  AnimationController? _controller;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _syncController();
  }

  @override
  void didUpdateWidget(WaveProgress oldWidget) {
    super.didUpdateWidget(oldWidget);
    _syncController();
  }

  void _syncController() {
    final shouldAnimate = widget.animate &&
        (!kIsDesktop || widget.forceAnimate) &&
        !MediaQuery.disableAnimationsOf(context);
    if (shouldAnimate && _controller == null) {
      _controller = AnimationController(
        vsync: this,
        duration: const Duration(seconds: 5),
      )..repeat();
    } else if (!shouldAnimate && _controller != null) {
      _controller!.dispose();
      _controller = null;
    }
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final rtl = Directionality.of(context) == TextDirection.rtl;
    return SizedBox(
      height: widget.height,
      width: double.infinity,
      child: RepaintBoundary(
        child: CustomPaint(
          painter: _WavePainter(
            progress: widget.progress.clamp(0.0, 1.0).toDouble(),
            color: widget.color,
            trackColor: widget.trackColor,
            rtl: rtl,
            phase: _controller,
          ),
        ),
      ),
    );
  }
}

class _WavePainter extends CustomPainter {
  _WavePainter({
    required this.progress,
    required this.color,
    required this.trackColor,
    required this.rtl,
    required this.phase,
  }) : super(repaint: phase);

  final double progress;
  final Color color;
  final Color trackColor;
  final bool rtl;
  final Animation<double>? phase;

  static const double _period = 30;

  @override
  void paint(Canvas canvas, Size size) {
    if (size.width <= 0 || size.height <= 0) {
      return;
    }
    final mid = size.height / 2;
    final amplitude = math.max(1.5, size.height / 2 - 3);
    final shift = (phase?.value ?? 0) * 2 * math.pi;

    double yAt(double x) =>
        mid + amplitude * math.sin(x / _period * 2 * math.pi - shift);
    double mirror(double x) => rtl ? size.width - x : x;

    Path build(double end) {
      final path = Path()..moveTo(mirror(0), yAt(0));
      for (double x = 2; x < end; x += 2) {
        path.lineTo(mirror(x), yAt(x));
      }
      path.lineTo(mirror(end), yAt(end));
      return path;
    }

    canvas.drawPath(
      build(size.width),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.4
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round
        ..color = trackColor,
    );

    final head = size.width * progress;
    if (head > 0.5) {
      canvas.drawPath(
        build(head),
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2.6
          ..strokeCap = StrokeCap.round
          ..strokeJoin = StrokeJoin.round
          ..color = color,
      );
      canvas.drawCircle(
        Offset(mirror(head), yAt(head)),
        3.6,
        Paint()..color = color,
      );
    }
  }

  @override
  bool shouldRepaint(_WavePainter old) {
    return old.progress != progress ||
        old.color != color ||
        old.trackColor != trackColor ||
        old.rtl != rtl ||
        old.phase != phase;
  }
}
