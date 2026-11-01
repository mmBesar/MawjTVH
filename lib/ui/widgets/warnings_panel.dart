import 'package:flutter/material.dart';

import '../../core/bidi.dart';
import '../../core/theme.dart';
import '../../data/models.dart';
import '../../l10n/strings.dart';

class WarningsPanel extends StatelessWidget {
  const WarningsPanel({super.key, required this.warnings});

  final Set<LoadWarning> warnings;

  @override
  Widget build(BuildContext context) {
    if (warnings.isEmpty) {
      return const SizedBox.shrink();
    }
    final colors = context.mawjColors;
    final strings = context.strings;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
      child: Column(
        children: <Widget>[
          for (final warning in warnings)
            Container(
              width: double.infinity,
              margin: const EdgeInsets.only(bottom: 8),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                color: colors.accentSoft,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: colors.surface1),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Icon(
                    Icons.info_outline_rounded,
                    size: 18,
                    color: colors.accent,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: BidiText(
                      strings.warningText(warning),
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: colors.subtext1,
                            height: 1.4,
                          ),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}
