import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'platform.dart';

/// Zoom steps offered for the whole interface.
const List<double> kUiScaleSteps = <double>[
  0.8,
  0.9,
  1.0,
  1.1,
  1.2,
  1.3,
  1.45,
  1.6,
  1.8,
];

/// What "Auto" means on desktop: the pages are drawn at their natural size.
const double kDesktopPageScale = 1.0;

/// The desktop sidebar keeps the size it always had (it was drawn at 1.2),
/// whatever the pages next to it are scaled to under "Auto".
const double kDesktopSidebarScale = 1.2;

/// The scale to use: the chosen one, or the desktop default.
double effectiveUiScale(double chosen) {
  if (chosen > 0) {
    return chosen.clamp(0.8, 2.2).toDouble();
  }
  return kIsDesktop ? kDesktopPageScale : 1.0;
}

/// Extra zoom for the desktop sidebar on top of [effectiveUiScale]. Only
/// under "Auto": a size the person chose scales everything alike.
double sidebarExtraScale(double chosen) {
  if (chosen > 0 || !kIsDesktop) {
    return 1.0;
  }
  return kDesktopSidebarScale / kDesktopPageScale;
}

/// The next zoom step above or below [current].
double stepUiScale(double current, int direction) {
  var index = 0;
  var best = double.infinity;
  for (var i = 0; i < kUiScaleSteps.length; i++) {
    final distance = (kUiScaleSteps[i] - current).abs();
    if (distance < best) {
      best = distance;
      index = i;
    }
  }
  return kUiScaleSteps[(index + direction).clamp(0, kUiScaleSteps.length - 1)];
}

/// Draws everything below it [scale] times bigger, text, icons and spacing
/// alike, while layout and pointer input follow the scaled picture.
class UiZoom extends StatelessWidget {
  const UiZoom({super.key, required this.scale, required this.child});

  final double scale;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    if ((scale - 1).abs() < 0.01) {
      return child;
    }
    final media = MediaQuery.of(context);
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth / scale;
        final height = constraints.maxHeight / scale;
        return ClipRect(
          child: OverflowBox(
            alignment: Alignment.topLeft,
            minWidth: width,
            maxWidth: width,
            minHeight: height,
            maxHeight: height,
            child: Transform.scale(
              scale: scale,
              alignment: Alignment.topLeft,
              child: MediaQuery(
                data: media.copyWith(
                  size: Size(width, height),
                  // Video is sized in device pixels from this.
                  devicePixelRatio: media.devicePixelRatio * scale,
                  padding: media.padding / scale,
                  viewPadding: media.viewPadding / scale,
                  viewInsets: media.viewInsets / scale,
                ),
                child: child,
              ),
            ),
          ),
        );
      },
    );
  }
}

/// Ctrl + / Ctrl - / Ctrl 0 change the zoom from anywhere.
Map<ShortcutActivator, VoidCallback> uiZoomShortcuts({
  required double Function() current,
  required void Function(double scale) onChange,
}) {
  void bump(int direction) =>
      onChange(stepUiScale(effectiveUiScale(current()), direction));
  return <ShortcutActivator, VoidCallback>{
    const SingleActivator(LogicalKeyboardKey.equal, control: true): () => bump(1),
    const SingleActivator(LogicalKeyboardKey.add, control: true): () => bump(1),
    const SingleActivator(LogicalKeyboardKey.numpadAdd, control: true): () =>
        bump(1),
    const SingleActivator(LogicalKeyboardKey.minus, control: true): () =>
        bump(-1),
    const SingleActivator(LogicalKeyboardKey.numpadSubtract, control: true): () =>
        bump(-1),
    const SingleActivator(LogicalKeyboardKey.digit0, control: true): () =>
        onChange(0),
  };
}
