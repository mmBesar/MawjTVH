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
  const RecordNowButton({
    super.key,
    required this.channel,
    this.dark = true,
    this.plain = false,
  });

  final Channel channel;
  final bool dark;

  /// No round backdrop: for a control bar that already has one.
  final bool plain;

  static const List<int> _minutes = <int>[30, 60, 120, 240];

  // Menu values: >0 minutes, or one of these.
  static const int _programme = -1;
  static const int _stop = -2;
  static const int _abort = -3;

  @override
  Widget build(BuildContext context) {
    if (isSyntheticChannel(channel)) {
      return const SizedBox.shrink();
    }
    final strings = context.strings;
    final state = context.watch<AppState>();
    final active = state.activeRecordingFor(channel);
    final now = state.epg.nowFor(channel, DateTime.now());
    final canRecordProgramme = now != null && now.eventId != null && !now.hasRecording;
    final error = dark ? const Color(0xFFED8796) : Theme.of(context).colorScheme.error;
    final icon = Icon(
      active != null ? Icons.stop_circle_rounded : Icons.fiber_manual_record_rounded,
      color: error,
    );

    Future<void> onSelected(int value) {
      switch (value) {
        case _stop:
          return runServerAction(
            context,
            action: () => state.stopRecording(active!),
            success: strings.stopRecording,
            forbidden: strings.recordingsForbidden,
          );
        case _abort:
          return runServerAction(
            context,
            action: () => state.cancelRecording(active!),
            success: strings.abortRecording,
            forbidden: strings.recordingsForbidden,
          );
        case _programme:
          return runServerAction(
            context,
            action: () => state.recordProgramme(now!),
            success: strings.recordingScheduled,
            forbidden: strings.recordingsForbidden,
          );
        default:
          return runServerAction(
            context,
            action: () => state.recordChannelNow(channel, value),
            success: strings.recordingStarted,
            forbidden: strings.recordingsForbidden,
          );
      }
    }

    final menu = PopupMenuButton<int>(
      tooltip: active != null ? strings.stopRecording : strings.recordOnServer,
      icon: icon,
      onSelected: (value) => onSelected(value),
      itemBuilder: (context) => <PopupMenuEntry<int>>[
        if (active != null) ...<PopupMenuEntry<int>>[
          PopupMenuItem<int>(
            value: _stop,
            child: Text(strings.stopRecording),
          ),
          PopupMenuItem<int>(
            value: _abort,
            child: Text(strings.abortRecording),
          ),
        ] else ...<PopupMenuEntry<int>>[
          if (canRecordProgramme)
            PopupMenuItem<int>(
              value: _programme,
              child: Text(strings.recordCurrentProgramme(now.title)),
            ),
          for (final minutes in _minutes)
            PopupMenuItem<int>(
              value: minutes,
              child: Text(strings.recordNowFor(minutes)),
            ),
        ],
      ],
    );
    if (!dark || plain) {
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
    this.plain = false,
  });

  final bool recording;
  final VoidCallback onPressed;
  final bool dark;
  final bool plain;

  @override
  Widget build(BuildContext context) {
    final strings = context.strings;
    final error = dark ? const Color(0xFFED8796) : Theme.of(context).colorScheme.error;
    final button = IconButton(
      tooltip: recording ? strings.stopLocalRecording : strings.recordOnDevice,
      onPressed: onPressed,
      color: recording ? error : (dark || plain ? Colors.white : null),
      icon: Icon(recording ? Icons.stop_circle_rounded : Icons.save_alt_rounded),
    );
    if (!dark || plain) {
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
