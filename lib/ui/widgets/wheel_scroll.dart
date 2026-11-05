import 'package:flutter/gestures.dart';
import 'package:flutter/widgets.dart';

/// Lets the mouse wheel scroll a horizontal strip (tags, tabs). Dragging with
/// the mouse is already allowed app-wide; this adds the wheel and the
/// trackpad's vertical swipe.
class WheelScroll extends StatefulWidget {
  const WheelScroll({super.key, this.controller, required this.builder});

  /// Use an existing controller, or leave null to have one made.
  final ScrollController? controller;
  final Widget Function(BuildContext context, ScrollController controller)
      builder;

  @override
  State<WheelScroll> createState() => _WheelScrollState();
}

class _WheelScrollState extends State<WheelScroll> {
  ScrollController? _own;

  ScrollController get _controller =>
      widget.controller ?? (_own ??= ScrollController());

  @override
  void dispose() {
    _own?.dispose();
    super.dispose();
  }

  void _onSignal(PointerSignalEvent event) {
    if (event is! PointerScrollEvent) {
      return;
    }
    final controller = _controller;
    if (!controller.hasClients) {
      return;
    }
    final delta = event.scrollDelta.dy != 0
        ? event.scrollDelta.dy
        : event.scrollDelta.dx;
    if (delta == 0) {
      return;
    }
    final position = controller.position;
    if (position.maxScrollExtent <= 0) {
      return;
    }
    GestureBinding.instance.pointerSignalResolver.register(event, (signal) {
      final target = (position.pixels + delta).clamp(
        position.minScrollExtent,
        position.maxScrollExtent,
      );
      controller.jumpTo(target.toDouble());
    });
  }

  @override
  Widget build(BuildContext context) {
    return Listener(
      onPointerSignal: _onSignal,
      child: widget.builder(context, _controller),
    );
  }
}
