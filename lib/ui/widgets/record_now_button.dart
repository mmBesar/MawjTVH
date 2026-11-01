import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../data/app_state.dart';
import '../../data/models.dart';
import '../../l10n/strings.dart';
import '../../l10n/tvh_strings.dart';
import 'record_actions.dart';

/// Starts a one-off recording of [channel] on the server, from now for a
/// chosen length.
class RecordNowButton extends StatelessWidget {
  const RecordNowButton({super.key, required this.channel, this.dark = true});

  final Channel channel;
  final bool dark;

  static const List<int> _minutes = <int>[30, 60, 120, 240];

  @override
  Widget build(BuildContext context) {
    if (channel.id.startsWith(kRecordingIdPrefix)) {
      return const SizedBox.shrink();
    }
    final strings = context.strings;
    final state = context.read<AppState>();
    final icon = Icon(
      Icons.fiber_manual_record_rounded,
      color: dark ? const Color(0xFFED8796) : Theme.of(context).colorScheme.error,
    );
    final menu = PopupMenuButton<int>(
      tooltip: strings.recordNow,
      icon: icon,
      onSelected: (minutes) => runServerAction(
        context,
        action: () => state.recordChannelNow(channel, minutes),
        success: strings.recordingStarted,
        forbidden: strings.recordingsForbidden,
      ),
      itemBuilder: (context) => <PopupMenuEntry<int>>[
        for (final minutes in _minutes)
          PopupMenuItem<int>(
            value: minutes,
            child: Text(strings.recordNowFor(minutes)),
          ),
      ],
    );
    if (!dark) {
      return menu;
    }
    return Material(
      color: Colors.black.withValues(alpha: 0.45),
      shape: const CircleBorder(),
      clipBehavior: Clip.antiAlias,
      child: menu,
    );
  }
}
