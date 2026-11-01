import 'package:flutter/material.dart';

import '../../core/bidi.dart';
import '../../core/theme.dart';

class ErrorBanner extends StatelessWidget {
  const ErrorBanner({
    super.key,
    required this.message,
    required this.retryLabel,
    required this.onRetry,
  });

  final String message;
  final String retryLabel;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final colors = context.mawjColors;
    final errorColor = Theme.of(context).colorScheme.error;
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 8),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: colors.surface0,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: errorColor.withValues(alpha: 0.6)),
      ),
      child: Row(
        children: <Widget>[
          Icon(Icons.error_outline_rounded, size: 18, color: errorColor),
          const SizedBox(width: 10),
          Expanded(
            child: BidiText(
              message,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: colors.subtext1,
                    height: 1.4,
                  ),
            ),
          ),
          TextButton(onPressed: onRetry, child: Text(retryLabel)),
        ],
      ),
    );
  }
}
