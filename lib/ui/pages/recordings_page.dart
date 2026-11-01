import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/bidi.dart';
import '../../core/theme.dart';
import '../../data/app_state.dart';
import '../../data/tvh_models.dart';
import '../../l10n/strings.dart';
import '../../l10n/tvh_strings.dart';
import '../player_page.dart';
import '../widgets/empty_state.dart';
import '../widgets/error_banner.dart';
import '../widgets/record_actions.dart';

enum _Tab { upcoming, finished, failed }

/// What the server has scheduled, recorded and failed to record. The server
/// decides whether this account may see or change any of it.
class RecordingsPage extends StatefulWidget {
  const RecordingsPage({super.key});

  @override
  State<RecordingsPage> createState() => _RecordingsPageState();
}

class _RecordingsPageState extends State<RecordingsPage> {
  _Tab _tab = _Tab.upcoming;
  bool _requested = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_requested) {
      _requested = true;
      final state = context.read<AppState>();
      if (state.activeSource != null) {
        unawaited(state.loadRecordings());
      }
    }
  }

  List<TvhRecording> _filter(List<TvhRecording> all) {
    final rows = all.where((recording) {
      return switch (_tab) {
        _Tab.upcoming => recording.isScheduled || recording.isRecording,
        _Tab.finished => recording.isFinished,
        _Tab.failed => !recording.isScheduled &&
            !recording.isRecording &&
            !recording.isFinished,
      };
    }).toList();
    rows.sort(
      (a, b) => _tab == _Tab.upcoming
          ? a.start.compareTo(b.start)
          : b.start.compareTo(a.start),
    );
    return rows;
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final strings = context.strings;
    final theme = Theme.of(context);
    final rows = _filter(state.recordings);

    return SafeArea(
      bottom: false,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 14, 12, 4),
            child: Row(
              children: <Widget>[
                Expanded(
                  child: Text(
                    strings.recordings,
                    style: theme.textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.w800,
                      letterSpacing: -0.3,
                    ),
                  ),
                ),
                IconButton(
                  tooltip: strings.refresh,
                  onPressed: state.recordingsLoading
                      ? null
                      : () => unawaited(state.loadRecordings()),
                  icon: state.recordingsLoading
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.refresh_rounded),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 4, 20, 8),
            child: SegmentedButton<_Tab>(
              segments: <ButtonSegment<_Tab>>[
                ButtonSegment<_Tab>(
                  value: _Tab.upcoming,
                  label: Text(strings.recordingsUpcoming),
                ),
                ButtonSegment<_Tab>(
                  value: _Tab.finished,
                  label: Text(strings.recordingsFinished),
                ),
                ButtonSegment<_Tab>(
                  value: _Tab.failed,
                  label: Text(strings.recordingsFailed),
                ),
              ],
              selected: <_Tab>{_tab},
              showSelectedIcon: false,
              onSelectionChanged: (selection) =>
                  setState(() => _tab = selection.first),
            ),
          ),
          if (state.recordingsError != null)
            ErrorBanner(
              message: state.recordingsError!,
              retryLabel: strings.retry,
              onRetry: () => unawaited(state.loadRecordings()),
            ),
          Expanded(
            child: rows.isEmpty
                ? (state.recordingsLoading
                    ? const SizedBox.shrink()
                    : EmptyState(
                        icon: Icons.fiber_manual_record_outlined,
                        title: strings.noRecordings,
                        body: state.recordingsError != null
                            ? strings.recordingsForbidden
                            : '',
                      ))
                : ListView.separated(
                    padding: const EdgeInsets.fromLTRB(16, 4, 16, 120),
                    itemCount: rows.length,
                    separatorBuilder: (context, index) => const SizedBox(height: 12),
                    itemBuilder: (context, index) => _RecordingCard(recording: rows[index]),
                  ),
          ),
        ],
      ),
    );
  }
}

class _RecordingCard extends StatelessWidget {
  const _RecordingCard({required this.recording});

  final TvhRecording recording;

  String _size(int bytes) {
    if (bytes <= 0) {
      return '';
    }
    const units = <String>['B', 'KB', 'MB', 'GB', 'TB'];
    var value = bytes.toDouble();
    var unit = 0;
    while (value >= 1024 && unit < units.length - 1) {
      value /= 1024;
      unit++;
    }
    return '${value.toStringAsFixed(unit < 2 ? 0 : 1)} ${units[unit]}';
  }

  Future<void> _confirmDelete(BuildContext context, AppState state) async {
    final strings = context.strings;
    final ok = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(strings.deleteRecording),
        content: Text(strings.confirmDeleteRecording),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: Text(strings.cancel),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: Text(strings.confirm),
          ),
        ],
      ),
    );
    if (ok == true && context.mounted) {
      await runServerAction(
        context,
        action: () => state.removeRecording(recording),
        success: strings.deleteRecording,
        forbidden: strings.recordingsForbidden,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = context.read<AppState>();
    final strings = context.strings;
    final colors = context.mawjColors;
    final theme = Theme.of(context);
    final use24 = state.settings.use24HourTime;
    final error = theme.colorScheme.error;
    final live = recording.isRecording;
    final canPlay = recording.hasFile && (recording.isFinished || live);

    final facts = <String>[
      strings.formatDate(recording.start),
      strings.formatRange(recording.start, recording.stop, use24HourTime: use24),
      if (recording.channelName.isNotEmpty) recording.channelName,
      if (_size(recording.fileSize).isNotEmpty) _size(recording.fileSize),
    ];

    return Container(
      padding: const EdgeInsets.fromLTRB(16, 14, 8, 10),
      decoration: BoxDecoration(
        color: colors.surface0,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: live ? error.withValues(alpha: 0.7) : colors.surface1),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              if (live)
                Padding(
                  padding: const EdgeInsetsDirectional.only(end: 8, top: 4),
                  child: Icon(Icons.fiber_manual_record_rounded, size: 14, color: error),
                ),
              Expanded(
                child: BidiText(
                  recording.title.isEmpty ? '—' : recording.title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ],
          ),
          if (recording.subtitle.isNotEmpty) ...<Widget>[
            const SizedBox(height: 2),
            BidiText(
              recording.subtitle,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodySmall?.copyWith(color: colors.subtext0),
            ),
          ],
          const SizedBox(height: 6),
          BidiText(
            facts.join(' · '),
            style: theme.textTheme.bodySmall?.copyWith(
              color: colors.subtext1,
              fontFeatures: const <FontFeature>[FontFeature.tabularFigures()],
            ),
          ),
          if (recording.status.isNotEmpty || recording.errors > 0) ...<Widget>[
            const SizedBox(height: 4),
            Text(
              <String>[
                if (recording.status.isNotEmpty) recording.status,
                if (recording.errors > 0)
                  '${strings.recordingProblems}: ${recording.errors}',
              ].join(' · '),
              style: theme.textTheme.labelSmall?.copyWith(
                color: recording.errors > 0 ? error : colors.overlay1,
              ),
            ),
          ],
          const SizedBox(height: 6),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: <Widget>[
              if (canPlay)
                TextButton.icon(
                  onPressed: () {
                    final channel = state.recordingAsChannel(recording);
                    if (channel != null) {
                      unawaited(openPlayer(context, channel));
                    }
                  },
                  icon: const Icon(Icons.play_arrow_rounded),
                  label: Text(strings.playRecording),
                ),
              if (live)
                TextButton.icon(
                  onPressed: () => runServerAction(
                    context,
                    action: () => state.stopRecording(recording),
                    success: strings.stopRecording,
                    forbidden: strings.recordingsForbidden,
                  ),
                  icon: const Icon(Icons.stop_rounded),
                  label: Text(strings.stopRecording),
                )
              else if (recording.isScheduled)
                TextButton.icon(
                  onPressed: () => runServerAction(
                    context,
                    action: () => state.cancelRecording(recording),
                    success: strings.cancelRecording,
                    forbidden: strings.recordingsForbidden,
                  ),
                  icon: const Icon(Icons.close_rounded),
                  label: Text(strings.cancelRecording),
                )
              else
                IconButton(
                  tooltip: strings.deleteRecording,
                  onPressed: () => unawaited(_confirmDelete(context, state)),
                  icon: const Icon(Icons.delete_outline_rounded),
                ),
            ],
          ),
        ],
      ),
    );
  }
}
