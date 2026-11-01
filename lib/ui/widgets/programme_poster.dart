import 'package:flutter/material.dart';

import '../../core/network_image.dart';
import '../../core/theme.dart';
import '../../data/models.dart';

/// A poster/thumbnail for an XMLTV programme. Falls back to a neutral tile when
/// the guide has no icon or the image cannot be loaded.
class ProgrammePoster extends StatelessWidget {
  const ProgrammePoster({
    super.key,
    required this.programme,
    required this.allowInsecure,
    this.width = 160,
    this.height = 90,
    this.radius = 12,
    this.fit = BoxFit.cover,
  });

  final Programme programme;
  final bool allowInsecure;
  final double width;
  final double height;
  final double radius;
  final BoxFit fit;

  @override
  Widget build(BuildContext context) {
    final colors = context.mawjColors;
    final url = programme.iconUrl;
    // XMLTV artwork is frequently full HD. Decode only what the poster slot
    // needs so a guide full of programmes cannot blow the image cache.
    final ratio = MediaQuery.devicePixelRatioOf(context);
    final cacheWidth = width.isFinite ? (width * ratio).ceil() : 1080;
    final cacheHeight = (height * ratio).ceil();
    final fallback = _Fallback(
      width: width,
      height: height,
      color: colors.overlay0,
      background: colors.surface1,
    );

    return ClipRRect(
      borderRadius: BorderRadius.circular(radius),
      child: SizedBox(
        width: width,
        height: height,
        child: ColoredBox(
          color: colors.surface1,
          child: url == null || url.trim().isEmpty
            ? fallback
            : Image(
                image: ResizeImage(
                  MawjNetworkImage(
                    url.trim(),
                    allowInsecure: allowInsecure,
                  ),
                  width: cacheWidth,
                  height: cacheHeight,
                  policy: ResizeImagePolicy.fit,
                ),
                width: width,
                height: height,
                fit: fit,
                gaplessPlayback: true,
                errorBuilder: (context, error, stackTrace) => fallback,
              ),
        ),
      ),
    );
  }
}

class _Fallback extends StatelessWidget {
  const _Fallback({
    required this.width,
    required this.height,
    required this.color,
    required this.background,
  });

  final double width;
  final double height;
  final Color color;
  final Color background;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(color: background),
      child: SizedBox(
        width: width,
        height: height,
        child: Icon(
          Icons.movie_filter_rounded,
          color: color,
          size: width.isFinite && width < 60 ? 18 : 28,
        ),
      ),
    );
  }
}
