import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../data/app_state.dart';
import '../../data/models.dart';
import '../../l10n/strings.dart';
import '../../l10n/tvh_strings.dart';

/// All / TV / Radio chips, shown only when the server has radio stations.
class MediaFilterChips extends StatelessWidget {
  const MediaFilterChips({super.key, this.padding = EdgeInsets.zero});

  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    if (!state.hasRadio) {
      return const SizedBox.shrink();
    }
    final strings = context.strings;
    final current = state.mediaFilter;
    Widget chip(MediaFilter value, String label, IconData icon) {
      return Padding(
        padding: const EdgeInsetsDirectional.only(end: 8),
        child: ChoiceChip(
          avatar: Icon(icon, size: 16),
          label: Text(label),
          selected: current == value,
          onSelected: (_) => state.setMediaFilter(value),
        ),
      );
    }

    return Padding(
      padding: padding,
      child: Row(
        children: <Widget>[
          chip(MediaFilter.all, strings.allKinds, Icons.apps_rounded),
          chip(MediaFilter.tv, strings.tvKind, Icons.tv_rounded),
          chip(MediaFilter.radio, strings.radioKind, Icons.radio_rounded),
        ],
      ),
    );
  }
}
