import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/bidi.dart';
import '../../core/text.dart';
import '../../core/theme.dart';
import '../../data/app_state.dart';
import '../../data/local_recorder.dart';
import '../../data/models.dart';
import '../../data/tvh_models.dart';
import '../../l10n/strings.dart';
import '../../l10n/tvh_strings.dart';
import '../player_page.dart';
import '../widgets/channel_logo.dart';
import '../widgets/empty_state.dart';
import '../widgets/error_banner.dart';
import '../widgets/record_actions.dart';

enum _Tab { upcoming, finished, failed, device }

enum _Group { none, channel, series, day }

/// What the server has scheduled, recorded and failed to record, plus what
/// was recorded on this device. The server decides whether this account may
/// see or change any of it.
class RecordingsPage extends StatefulWidget {
  const RecordingsPage({super.key});

  @override
  State<RecordingsPage> createState() => _RecordingsPageState();
}

class _RecordingsPageState extends State<RecordingsPage> {
  _Tab _tab = _Tab.upcoming;
  _Group _group = _Group.none;
  String? _channelFilter;
  bool _searching = false;
  String _query = '';
  final TextEditingController _search = TextEditingController();
  bool _requested = false;
  List<LocalRecordingFile>? _local;
  String? _localError;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_requested) {
      _requested = true;
      // After the first frame: loading notifies listeners, which must not
      // happen while the tree is being built (the desktop builds every tab
      // at start-up).
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          unawaited(context.read<AppState>().loadRecordings());
        }
      });
    }
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  Future<void> _loadLocal() async {
    final folder = context.read<AppState>().settings.recordDir;
    try {
      final files = await LocalRecordings.list(folder);
      if (mounted) {
        setState(() {
          _local = files;
          _localError = null;
        });
      }
    } catch (error) {
      if (mounted) {
        setState(() => _localError = '$error');
      }
    }
  }

  void _refresh(AppState state) {
    unawaited(state.loadRecordings());
    if (_tab == _Tab.device) {
      unawaited(_loadLocal());
    }
  }

  bool _matches(TvhRecording recording) {
    final tokens = searchTokens(_query);
    if (tokens.isEmpty) {
      return true;
    }
    return matchesAllTokens(
      foldForSearch(
        '${recording.title} ${recording.subtitle} ${recording.channelName} '
        '${recording.description}',
      ),
      tokens,
    );
  }

  List<TvhRecording> _filter(List<TvhRecording> all) {
    final rows = all.where((recording) {
      final inTab = switch (_tab) {
        _Tab.upcoming => recording.isScheduled || recording.isRecording,
        _Tab.finished => recording.isFinished,
        _Tab.failed => !recording.isScheduled &&
            !recording.isRecording &&
            !recording.isFinished,
        _Tab.device => false,
      };
      return inTab &&
          (_channelFilter == null || recording.channelUuid == _channelFilter) &&
          _matches(recording);
    }).toList();
    rows.sort(
      (a, b) => _tab == _Tab.upcoming
          ? a.start.compareTo(b.start)
          : b.start.compareTo(a.start),
    );
    return rows;
  }

  /// Rows with section headers (strings) in between, for the chosen grouping.
  List<Object> _grouped(List<TvhRecording> rows, AppStrings strings) {
    if (_group == _Group.none) {
      return rows;
    }
    String keyOf(TvhRecording r) => switch (_group) {
          _Group.channel => r.channelName.isEmpty ? '—' : r.channelName,
          _Group.series => r.title.isEmpty ? '—' : r.title,
          _Group.day => strings.formatDate(r.start),
          _Group.none => '',
        };
    final groups = <String, List<TvhRecording>>{};
    for (final row in rows) {
      groups.putIfAbsent(keyOf(row), () => <TvhRecording>[]).add(row);
    }
    final keys = groups.keys.toList();
    if (_group != _Group.day) {
      keys.sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
    }
    return <Object>[
      for (final key in keys) ...<Object>[
        '$key  ·  ${groups[key]!.length}',
        ...groups[key]!,
      ],
    ];
  }

  String _groupLabel(AppStrings strings, _Group group) => switch (group) {
        _Group.none => strings.groupNone,
        _Group.channel => strings.groupChannel,
        _Group.series => strings.groupSeries,
        _Group.day => strings.groupDay,
      };

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final strings = context.strings;
    final colors = context.mawjColors;
    final theme = Theme.of(context);
    final all = state.recordings;
    final rows = _filter(all);
    final items = _grouped(rows, strings);

    // Channels that appear in this tab, for the filter chips.
    final seen = <String>{};
    final channelChips = <TvhRecording>[];
    for (final recording in all) {
      if (recording.channelUuid.isNotEmpty && seen.add(recording.channelUuid)) {
        channelChips.add(recording);
      }
    }
    channelChips.sort(
      (a, b) => a.channelName.toLowerCase().compareTo(b.channelName.toLowerCase()),
    );

    return SafeArea(
      bottom: false,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 14, 4, 4),
            child: Row(
              children: <Widget>[
                Expanded(
                  child: _searching
                      ? TextField(
                          controller: _search,
                          autofocus: true,
                          onChanged: (value) => setState(() => _query = value),
                          decoration: InputDecoration(
                            hintText: strings.filterRecordings,
                            prefixIcon: const Icon(Icons.search_rounded),
                          ),
                        )
                      : Text(
                          strings.recordings,
                          style: theme.textTheme.headlineSmall?.copyWith(
                            fontWeight: FontWeight.w800,
                            letterSpacing: -0.3,
                          ),
                        ),
                ),
                IconButton(
                  tooltip: strings.searchTooltip,
                  onPressed: () => setState(() {
                    _searching = !_searching;
                    if (!_searching) {
                      _query = '';
                      _search.clear();
                    }
                  }),
                  icon: Icon(_searching ? Icons.close_rounded : Icons.search_rounded),
                ),
                if (_tab != _Tab.device)
                  PopupMenuButton<_Group>(
                    tooltip: strings.groupBy,
                    icon: Icon(
                      Icons.workspaces_outline,
                      color: _group == _Group.none ? null : colors.accent,
                    ),
                    onSelected: (value) => setState(() => _group = value),
                    itemBuilder: (context) => <PopupMenuEntry<_Group>>[
                      for (final group in _Group.values)
                        CheckedPopupMenuItem<_Group>(
                          value: group,
                          checked: group == _group,
                          child: Text('${strings.groupBy}: ${_groupLabel(strings, group)}'),
                        ),
                    ],
                  ),
                IconButton(
                  tooltip: strings.refresh,
                  onPressed: state.recordingsLoading ? null : () => _refresh(state),
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
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
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
                  ButtonSegment<_Tab>(
                    value: _Tab.device,
                    label: Text(strings.localTab),
                    icon: const Icon(Icons.save_alt_rounded, size: 16),
                  ),
                ],
                selected: <_Tab>{_tab},
                showSelectedIcon: false,
                onSelectionChanged: (selection) {
                  setState(() => _tab = selection.first);
                  if (_tab == _Tab.device) {
                    unawaited(_loadLocal());
                  }
                },
              ),
            ),
          ),
          if (_tab != _Tab.device && channelChips.length > 1)
            SizedBox(
              height: 44,
              child: ListView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 16),
                children: <Widget>[
                  Padding(
                    padding: const EdgeInsetsDirectional.only(end: 8),
                    child: ChoiceChip(
                      label: Text(strings.allChannelsFilter),
                      selected: _channelFilter == null,
                      onSelected: (_) => setState(() => _channelFilter = null),
                    ),
                  ),
                  for (final recording in channelChips)
                    Padding(
                      padding: const EdgeInsetsDirectional.only(end: 8),
                      child: ChoiceChip(
                        avatar: _logoFor(state, recording, 20),
                        label: BidiText(recording.channelName),
                        selected: _channelFilter == recording.channelUuid,
                        onSelected: (selected) => setState(
                          () => _channelFilter = selected ? recording.channelUuid : null,
                        ),
                      ),
                    ),
                ],
              ),
            ),
          if (state.recordingsError != null && _tab != _Tab.device)
            ErrorBanner(
              message: state.recordingsError!,
              retryLabel: strings.retry,
              onRetry: () => unawaited(state.loadRecordings()),
            ),
          Expanded(
            child: _tab == _Tab.device
                ? _buildLocal(context, state)
                : (items.isEmpty
                    ? (state.recordingsLoading
                        ? const SizedBox.shrink()
                        : EmptyState(
                            icon: Icons.fiber_manual_record_outlined,
                            title: strings.noRecordings,
                            body: state.recordingsError != null
                                ? strings.recordingsForbidden
                                : '',
                          ))
                    : ListView.builder(
                        padding: const EdgeInsets.fromLTRB(16, 4, 16, 120),
                        itemCount: items.length,
                        itemBuilder: (context, index) {
                          final item = items[index];
                          if (item is String) {
                            return Padding(
                              padding: const EdgeInsets.fromLTRB(4, 14, 4, 8),
                              child: BidiText(
                                item,
                                style: theme.textTheme.titleSmall?.copyWith(
                                  color: colors.subtext0,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            );
                          }
                          return Padding(
                            padding: const EdgeInsets.only(bottom: 12),
                            child: _RecordingCard(recording: item as TvhRecording),
                          );
                        },
                      )),
          ),
        ],
      ),
    );
  }

  Widget? _logoFor(AppState state, TvhRecording recording, double size) {
    final channel = state.channelById(recording.channelUuid);
    if (channel == null) {
      return null;
    }
    return ChannelLogo(
      channel: channel,
      allowInsecure: state.activeSource?.allowInsecureCerts ?? false,
      size: size,
      radius: size / 5,
    );
  }

  Widget _buildLocal(BuildContext context, AppState state) {
    final strings = context.strings;
    final colors = context.mawjColors;
    final theme = Theme.of(context);
    if (_local == null && _localError == null) {
      unawaited(_loadLocal());
      return const Center(child: CircularProgressIndicator());
    }
    if (_localError != null) {
      return EmptyState(
        icon: Icons.folder_off_outlined,
        title: strings.noLocalRecordings,
        body: _localError!,
      );
    }
    final tokens = searchTokens(_query);
    final files = _local!
        .where((file) =>
            tokens.isEmpty ||
            matchesAllTokens(foldForSearch(file.name), tokens))
        .toList();
    if (files.isEmpty) {
      return EmptyState(
        icon: Icons.save_alt_rounded,
        title: strings.noLocalRecordings,
        body: '',
      );
    }
    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 120),
      itemCount: files.length,
      separatorBuilder: (context, index) => const SizedBox(height: 12),
      itemBuilder: (context, index) {
        final file = files[index];
        final title = file.name.contains('.')
            ? file.name.substring(0, file.name.lastIndexOf('.'))
            : file.name;
        return Container(
          padding: const EdgeInsets.fromLTRB(16, 12, 8, 8),
          decoration: BoxDecoration(
            color: colors.surface0,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: colors.surface1),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              BidiText(
                title,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 4),
              Text(
                '${strings.formatDateTime(file.modified, use24HourTime: state.settings.use24HourTime)} · ${_sizeText(file.size)}',
                style: theme.textTheme.bodySmall?.copyWith(color: colors.subtext1),
              ),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: <Widget>[
                  TextButton.icon(
                    onPressed: () => unawaited(
                      openPlayer(
                        context,
                        Channel(
                          id: '${kRecordingIdPrefix}local:${file.path}',
                          sourceId: state.activeSource?.id ?? '',
                          name: title,
                          number: '',
                          url: file.path,
                        ),
                      ),
                    ),
                    icon: const Icon(Icons.play_arrow_rounded),
                    label: Text(strings.playRecording),
                  ),
                  IconButton(
                    tooltip: strings.deleteFile,
                    onPressed: () => unawaited(_confirmDeleteFile(context, file)),
                    icon: const Icon(Icons.delete_outline_rounded),
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }

  Future<void> _confirmDeleteFile(BuildContext context, LocalRecordingFile file) async {
    final strings = context.strings;
    final ok = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(strings.deleteFile),
        content: Text(strings.confirmDeleteFile),
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
    if (ok == true) {
      await LocalRecordings.delete(file.path);
      unawaited(_loadLocal());
    }
  }
}

String _sizeText(int bytes) {
  if (bytes <= 0) {
    return '0 B';
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

class _RecordingCard extends StatelessWidget {
  const _RecordingCard({required this.recording});

  final TvhRecording recording;

  String _size(int bytes) => bytes <= 0 ? '' : _sizeText(bytes);

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
    final channel = state.channelById(recording.channelUuid);
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
              if (channel != null)
                Padding(
                  padding: const EdgeInsetsDirectional.only(end: 12),
                  child: ChannelLogo(
                    channel: channel,
                    allowInsecure: state.activeSource?.allowInsecureCerts ?? false,
                    size: 44,
                    radius: 12,
                  ),
                ),
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
