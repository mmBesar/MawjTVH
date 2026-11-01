import 'package:flutter/material.dart';

import '../../core/network_image.dart';
import '../../core/theme.dart';
import '../../data/models.dart';

class ChannelLogo extends StatelessWidget {
  const ChannelLogo({
    super.key,
    required this.channel,
    required this.allowInsecure,
    this.size = 48,
    this.radius = 12,
  });

  final Channel channel;
  final bool allowInsecure;
  final double size;
  final double radius;

  @override
  Widget build(BuildContext context) {
    final colors = context.mawjColors;
    final url = channel.logoUrl;
    // Decode logos at the size they are actually drawn at. Channel images are
    // often much larger than the 34-54px tile, and a big source list can
    // otherwise exhaust the image cache (or Android's memory budget) until
    // previously loaded logos start failing to decode.
    final pixels = (size * MediaQuery.devicePixelRatioOf(context)).ceil();
    return ClipRRect(
      borderRadius: BorderRadius.circular(radius),
      child: Container(
        width: size,
        height: size,
        color: colors.surface1,
        alignment: Alignment.center,
        child: url == null || url.isEmpty
            ? _Fallback(size: size, color: colors.subtext0)
            : Image(
                image: ResizeImage(
                  MawjNetworkImage(url, allowInsecure: allowInsecure),
                  width: pixels,
                  height: pixels,
                  policy: ResizeImagePolicy.fit,
                ),
                width: size,
                height: size,
                fit: BoxFit.contain,
                gaplessPlayback: true,
                errorBuilder: (context, error, stackTrace) {
                  return _Fallback(size: size, color: colors.subtext0);
                },
              ),
      ),
    );
  }
}

class _Fallback extends StatelessWidget {
  const _Fallback({required this.size, required this.color});

  final double size;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Icon(Icons.live_tv_rounded, size: size * 0.5, color: color);
  }
}
