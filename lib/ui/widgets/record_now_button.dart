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
    if (isSyntheticChannel(channel)) {
      return const SizedBox.shrink();
    }
    final strings = context.strings;
    final state = context.read<AppState>();
    final icon = Icon(
      Icons.fiber_manual_record_rounded,
      color: dark ? const Color(0xFFED8796) : Theme.of(context).colorScheme.error,
    );
    final menu = PopupMenuButton<int>(
      tooltip: strings.recordOnServer,
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

/// Starts or stops a copy of the stream being watched, saved on this device.
class LocalRecordButton extends StatelessWidget {
  const LocalRecordButton({
    super.key,
    required this.recording,
    required this.onPressed,
    this.dark = true,
  });

  final bool recording;
  final VoidCallback onPressed;
  final bool dark;

  @override
  Widget build(BuildContext context) {
    final strings = context.strings;
    final error = dark ? const Color(0xFFED8796) : Theme.of(context).colorScheme.error;
    final button = IconButton(
      tooltip: recording ? strings.stopLocalRecording : strings.recordOnDevice,
      onPressed: onPressed,
      color: recording ? error : (dark ? Colors.white : null),
      icon: Icon(recording ? Icons.stop_circle_rounded : Icons.save_alt_rounded),
    );
    if (!dark) {
      return button;
    }
    return Material(
      color: Colors.black.withValues(alpha: 0.45),
      shape: const CircleBorder(),
      clipBehavior: Clip.antiAlias,
      child: button,
    );
  }
}
