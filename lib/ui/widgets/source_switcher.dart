import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/bidi.dart';
import '../../core/theme.dart';
import '../../data/app_state.dart';
import '../../l10n/strings.dart';

/// A small sheet for switching the active source in one tap. Managing the
/// sources (adding, editing, deleting) stays on its own page.
Future<void> showSourceSwitcher(
  BuildContext context, {
  required VoidCallback onManage,
}) {
  return showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    useSafeArea: true,
    constraints: const BoxConstraints(maxWidth: 480),
    builder: (sheetContext) {
      final state = sheetContext.watch<AppState>();
      final strings = sheetContext.strings;
      final colors = sheetContext.mawjColors;
      final active = state.activeSource?.id;
      return SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
              child: Align(
                alignment: AlignmentDirectional.centerStart,
                child: Text(
                  strings.switchSource,
                  style: Theme.of(sheetContext).textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                ),
              ),
            ),
            Flexible(
              child: ListView(
                shrinkWrap: true,
                children: <Widget>[
                  for (final source in state.sources)
                    ListTile(
                      leading: Icon(
                        source.id == active
                            ? Icons.radio_button_checked_rounded
                            : Icons.radio_button_unchecked_rounded,
                        color: source.id == active
                            ? colors.accent
                            : colors.subtext0,
                      ),
                      title: BidiText(source.name),
                      onTap: () {
                        unawaited(state.selectSource(source.id));
                        Navigator.of(sheetContext).pop();
                      },
                    ),
                ],
              ),
            ),
            ListTile(
              leading: const Icon(Icons.dns_rounded),
              title: Text(strings.manageSources),
              onTap: () {
                Navigator.of(sheetContext).pop();
                onManage();
              },
            ),
            const SizedBox(height: 8),
          ],
        ),
      );
    },
  );
}
