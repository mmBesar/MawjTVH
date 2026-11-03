import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/theme.dart';
import '../../data/app_state.dart';
import '../../data/models.dart';
import '../../data/tvh_models.dart';
import '../../l10n/strings.dart';
import '../../l10n/tvh_strings.dart';

/// Live signal numbers (SNR and SS) for the channel being watched, from the
/// server's tuner status. Shows nothing when the account cannot see tuner
/// status or the channel is not on a tuner (IPTV, recordings).
class SignalBadge extends StatefulWidget {
  const SignalBadge({
    super.key,
    required this.channel,
    this.dark = true,
    this.interval = const Duration(seconds: 4),
    this.meter = false,
  });

  final Channel channel;

  /// Draw for a dark video overlay (white text) instead of the app surface.
  final bool dark;
  final Duration interval;

  /// Draw two labelled level bars (for the channel banner) instead of a pill.
  final bool meter;

  @override
  State<SignalBadge> createState() => _SignalBadgeState();
}

class _SignalBadgeState extends State<SignalBadge> {
  Timer? _timer;
  TvhSignal? _signal;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    unawaited(_poll());
    _timer = Timer.periodic(widget.interval, (_) => unawaited(_poll()));
  }

  @override
  void didUpdateWidget(SignalBadge oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.channel.id != widget.channel.id) {
      _signal = null;
      unawaited(_poll());
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _poll() async {
    if (_busy || !mounted) {
      return;
    }
    final state = context.read<AppState>();
    if (!(state.isAdmin || state.usesHtsp) || isSyntheticChannel(widget.channel)) {
      return;
    }
    _busy = true;
    try {
      final signal = await state.signalFor(widget.channel);
      if (mounted) {
        setState(() => _signal = signal);
      }
    } finally {
      _busy = false;
    }
  }

  String _percent(double? value) =>
      value == null ? '—' : '${value.round()}%';

  String _db(double? value) =>
      value == null ? '—' : '${value.toStringAsFixed(1)} dB';

  @override
  Widget build(BuildContext context) {
    final signal = _signal;
    if (signal == null || !signal.hasValues) {
      return const SizedBox.shrink();
    }
    final strings = context.strings;
    final colors = context.mawjColors;
    final snr = signal.snrPercent != null
        ? _percent(signal.snrPercent)
        : _db(signal.snrDb);
    final ss = signal.signalPercent != null
        ? _percent(signal.signalPercent)
        : _db(signal.signalDb);
    final quality = signal.snrPercent ?? signal.signalPercent;
    final dot = quality == null
        ? colors.overlay1
        : (quality >= 60
            ? const Color(0xFF8BD5A0)
            : (quality >= 35 ? const Color(0xFFF5C26B) : const Color(0xFFED8796)));
    final textColor = widget.dark ? Colors.white : colors.subtext1;
    if (widget.meter) {
      return Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          _Level(
            label: strings.signalStrength,
            percent: signal.signalPercent,
            text: ss,
            color: dot,
          ),
          const SizedBox(height: 7),
          _Level(
            label: strings.signalSnr,
            percent: signal.snrPercent,
            text: snr,
            color: dot,
          ),
        ],
      );
    }
    return Tooltip(
      message: '${strings.signal}: ${strings.signalSnr} $snr · '
          '${strings.signalStrength} $ss'
          '${signal.unc != null ? ' · UNC ${signal.unc}' : ''}',
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: widget.dark ? 0.4 : 0.08),
          borderRadius: BorderRadius.circular(999),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Container(
              width: 7,
              height: 7,
              decoration: BoxDecoration(color: dot, shape: BoxShape.circle),
            ),
            const SizedBox(width: 6),
            Text(
              '${strings.signalSnr} $snr  ${strings.signalStrength} $ss',
              style: TextStyle(
                color: textColor,
                fontSize: 11,
                fontWeight: FontWeight.w700,
                fontFeatures: const <FontFeature>[FontFeature.tabularFigures()],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Level extends StatelessWidget {
  const _Level({
    required this.label,
    required this.percent,
    required this.text,
    required this.color,
  });

  final String label;
  final double? percent;
  final String text;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: <Widget>[
        SizedBox(
          width: 34,
          child: Text(
            label,
            style: const TextStyle(
              color: Colors.white60,
              fontSize: 11,
              fontWeight: FontWeight.w800,
            ),
          ),
        ),
        Expanded(
          child: ClipRRect(
            borderRadius: BorderRadius.circular(99),
            child: LinearProgressIndicator(
              value: ((percent ?? 0) / 100).clamp(0.0, 1.0).toDouble(),
              minHeight: 6,
              backgroundColor: Colors.white.withValues(alpha: 0.14),
              color: color,
            ),
          ),
        ),
        const SizedBox(width: 8),
        SizedBox(
          width: 52,
          child: Text(
            text,
            textAlign: TextAlign.end,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 12,
              fontWeight: FontWeight.w700,
              fontFeatures: <FontFeature>[FontFeature.tabularFigures()],
            ),
          ),
        ),
      ],
    );
  }
}
