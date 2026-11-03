import 'dart:async';

import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart';

import '../../core/bidi.dart';
import '../../core/theme.dart';
import '../../l10n/languages.dart';
import '../../l10n/strings.dart';
import '../../l10n/tvh_strings.dart';

/// Audio and subtitle choices of the running stream, with real language names.
Future<void> showTrackSheet(BuildContext context, Player player) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    showDragHandle: true,
    constraints: const BoxConstraints(maxWidth: 560),
    builder: (context) => _TrackSheet(player: player),
  );
}

class _TrackSheet extends StatelessWidget {
  const _TrackSheet({required this.player});

  final Player player;

  static bool _real(String id) => id != 'auto' && id != 'no';

  /// "العربية · AC3" style label for a track.
  static String _label(
    BuildContext context, {
    required int index,
    required String? language,
    required String? title,
    required String? codec,
  }) {
    final arabic = context.strings.isArabic;
    final name = languageName(language, arabic: arabic);
    final extra = <String>[
      if (title != null && title.trim().isNotEmpty && title.trim() != name) title.trim(),
      if (codec != null && codec.trim().isNotEmpty) codec.trim().toUpperCase(),
    ].join(' · ');
    final first = name.isNotEmpty ? name : context.strings.trackNumber(index + 1);
    return extra.isEmpty ? first : '$first · $extra';
  }

  @override
  Widget build(BuildContext context) {
    final strings = context.strings;
    final colors = context.mawjColors;
    return StreamBuilder<Tracks>(
      stream: player.stream.tracks,
      initialData: player.state.tracks,
      builder: (context, tracksSnapshot) {
        final tracks = tracksSnapshot.data ?? player.state.tracks;
        final audio = tracks.audio.where((t) => _real(t.id)).toList();
        final subtitles = tracks.subtitle.where((t) => _real(t.id)).toList();
        return StreamBuilder<Track>(
          stream: player.stream.track,
          initialData: player.state.track,
          builder: (context, selectedSnapshot) {
            final selected = selectedSnapshot.data ?? player.state.track;
            return SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(8, 0, 8, 24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  _Heading(text: strings.audioTracks),
                  if (audio.isEmpty)
                    _Empty(text: strings.noTracks)
                  else
                    for (var i = 0; i < audio.length; i++)
                      RadioListTile<bool>(
                        value: true,
                        groupValue: selected.audio.id == audio[i].id,
                        onChanged: (_) =>
                            unawaited(player.setAudioTrack(audio[i])),
                        title: BidiText(
                          _label(
                            context,
                            index: i,
                            language: audio[i].language,
                            title: audio[i].title,
                            codec: audio[i].codec,
                          ),
                        ),
                      ),
                  const SizedBox(height: 8),
                  _Heading(text: strings.subtitleTracks),
                  RadioListTile<bool>(
                    value: true,
                    groupValue: selected.subtitle.id == 'no',
                    onChanged: (_) =>
                        unawaited(player.setSubtitleTrack(SubtitleTrack.no())),
                    title: Text(strings.subtitlesOff),
                  ),
                  if (subtitles.isEmpty)
                    _Empty(text: strings.noTracks)
                  else
                    for (var i = 0; i < subtitles.length; i++)
                      RadioListTile<bool>(
                        value: true,
                        groupValue: selected.subtitle.id == subtitles[i].id,
                        onChanged: (_) => unawaited(
                          player.setSubtitleTrack(subtitles[i]),
                        ),
                        title: BidiText(
                          _label(
                            context,
                            index: i,
                            language: subtitles[i].language,
                            title: subtitles[i].title,
                            codec: subtitles[i].codec,
                          ),
                        ),
                      ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                    child: Text(
                      strings.tracksHelp,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: colors.subtext0,
                            height: 1.4,
                          ),
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }
}

class _Heading extends StatelessWidget {
  const _Heading({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 4),
      child: Text(
        text,
        style: Theme.of(context).textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.w800,
            ),
      ),
    );
  }
}

class _Empty extends StatelessWidget {
  const _Empty({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
      child: Text(
        text,
        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: context.mawjColors.overlay1,
            ),
      ),
    );
  }
}

/// "العربية · AC3" style label for a track, for notices outside the sheet.
String trackLabel(
  BuildContext context, {
  required int index,
  required String? language,
  required String? title,
  required String? codec,
}) =>
    _TrackSheet._label(
      context,
      index: index,
      language: language,
      title: title,
      codec: codec,
    );
