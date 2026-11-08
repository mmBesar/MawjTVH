import 'dart:async';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/foundation.dart' show TargetPlatform, defaultTargetPlatform;
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/app_info.dart';
import '../../core/bidi.dart';
import '../../core/catppuccin.dart';
import '../../core/platform.dart';
import '../../core/theme.dart';
import '../../core/ui_zoom.dart';
import '../../data/app_state.dart';
import '../../data/local_recorder.dart';
import '../../data/models.dart';
import '../../data/mpv_runtime.dart';
import '../../l10n/languages.dart';
import '../../l10n/strings.dart';
import '../../l10n/tvh_strings.dart';
import 'server_page.dart';

class SettingsPage extends StatelessWidget {
  const SettingsPage({super.key, required this.onOpenSources});

  final VoidCallback onOpenSources;

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final strings = context.strings;
    final colors = context.mawjColors;
    final settings = state.settings;

    return SafeArea(
      bottom: false,
      child: ListView(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 120),
      children: <Widget>[
        Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 760),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                Text(
                  strings.settings,
                  style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                ),
                const SizedBox(height: 20),
                _Section(
                  title: strings.appearance,
                  children: <Widget>[
                    _FieldLabel(text: strings.theme),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: <Widget>[
                        for (final family in ThemeFamily.values)
                          _ThemeChip(
                            family: family,
                            selected: settings.themeFamily == family,
                            accent: settings.accent,
                            label: strings.themeFamilyLabel(family),
                            onTap: () => unawaited(
                              state.setThemeFamily(family),
                            ),
                          ),
                      ],
                    ),
                    if (settings.themeFamily == ThemeFamily.system) ...<Widget>[
                      const SizedBox(height: 8),
                      Text(
                        strings.systemThemeHelp,
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: colors.subtext0,
                              height: 1.4,
                            ),
                      ),
                    ],
                    const SizedBox(height: 20),
                    _FieldLabel(text: strings.accent),
                    const SizedBox(height: 10),
                    Wrap(
                      spacing: 10,
                      runSpacing: 10,
                      children: <Widget>[
                        for (final accent in ThemeAccent.values)
                          _AccentDot(
                            accent: accent,
                            selected: settings.accent == accent,
                            palette: paletteFor(
                              settings.themeFamily == ThemeFamily.system
                                  ? ThemeFamily.studio
                                  : settings.themeFamily,
                            ),
                            onTap: () => unawaited(state.setAccent(accent)),
                          ),
                      ],
                    ),
                  ],
                ),
                _Section(
                  title: strings.displaySection,
                  children: <Widget>[
                    _dropdown<double>(
                      icon: Icons.zoom_in_rounded,
                      label: strings.uiScaleLabel,
                      value: <double>[0, ...kUiScaleSteps].contains(settings.uiScale)
                          ? settings.uiScale
                          : 0,
                      options: <(double, String)>[
                        (0.0, strings.autoWord),
                        for (final step in kUiScaleSteps)
                          (step, '${(step * 100).round()}%'),
                      ],
                      onChanged: (value) => unawaited(state.setUiScale(value)),
                    ),
                    Padding(
                      padding: const EdgeInsets.only(top: 6, bottom: 12),
                      child: Text(
                        strings.uiScaleHelp,
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: colors.subtext0,
                            ),
                      ),
                    ),
                    _dropdown<double>(
                      icon: Icons.calendar_view_week_rounded,
                      label: strings.guideSizeLabel,
                      value: _guideSteps.contains(settings.guideScale)
                          ? settings.guideScale
                          : 0,
                      options: <(double, String)>[
                        (0.0, strings.autoWord),
                        for (final step in _guideSteps.where((v) => v > 0))
                          (step, '${(step * 100).round()}%'),
                      ],
                      onChanged: (value) =>
                          unawaited(state.setGuideScale(value)),
                    ),
                    const SizedBox(height: 12),
                    _dropdown<String>(
                      icon: Icons.dashboard_customize_rounded,
                      label: strings.viewMode,
                      value: <String>['cards', 'list', 'compact', 'wall']
                              .contains(settings.channelView)
                          ? settings.channelView
                          : 'cards',
                      options: <(String, String)>[
                        ('cards', strings.viewCards),
                        ('list', strings.viewList),
                        ('compact', strings.viewCompact),
                        ('wall', strings.viewWall),
                      ],
                      onChanged: (value) =>
                          unawaited(state.setChannelView(value)),
                    ),
                    const SizedBox(height: 12),
                    _dropdown<int>(
                      icon: Icons.timer_outlined,
                      label: strings.osdSecondsLabel,
                      value: <int>[4, 6, 8, 12, 20, 30].contains(settings.osdSeconds)
                          ? settings.osdSeconds
                          : 8,
                      options: <(int, String)>[
                        for (final seconds in <int>[4, 6, 8, 12, 20, 30])
                          (seconds, strings.secondsShort(seconds)),
                      ],
                      onChanged: (value) =>
                          unawaited(state.setOsdSeconds(value)),
                    ),
                    if (defaultTargetPlatform == TargetPlatform.android)
                      SwitchListTile(
                        value: settings.pipOnLeave,
                        onChanged: (value) =>
                            unawaited(state.setPipOnLeave(value)),
                        contentPadding: EdgeInsets.zero,
                        title: Text(strings.pipLabel),
                        subtitle: Text(
                          strings.pipHelp,
                          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                color: colors.subtext0,
                              ),
                        ),
                      ),
                  ],
                ),
                _Section(
                  title: strings.audioAndSubtitles,
                  children: <Widget>[
                    InputDecorator(
                      decoration: InputDecoration(
                        prefixIcon: const Icon(Icons.audiotrack_rounded),
                        labelText: strings.preferredAudio,
                      ),
                      child: DropdownButtonHideUnderline(
                        child: DropdownButton<String>(
                          value: _langOptions.contains(settings.preferredAudioLang)
                              ? settings.preferredAudioLang
                              : '',
                          isExpanded: true,
                          isDense: true,
                          items: <DropdownMenuItem<String>>[
                            DropdownMenuItem<String>(
                              value: '',
                              child: Text(strings.streamDefault),
                            ),
                            for (final code in _langOptions.where((c) => c.isNotEmpty))
                              DropdownMenuItem<String>(
                                value: code,
                                child: Text(
                                  languageName(code, arabic: strings.isArabic),
                                ),
                              ),
                          ],
                          onChanged: (value) {
                            if (value != null) {
                              unawaited(state.setPreferredAudioLang(value));
                            }
                          },
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    InputDecorator(
                      decoration: InputDecoration(
                        prefixIcon: const Icon(Icons.subtitles_rounded),
                        labelText: strings.preferredSubtitle,
                      ),
                      child: DropdownButtonHideUnderline(
                        child: DropdownButton<String>(
                          value: settings.preferredSubtitleLang == 'off' ||
                                  _langOptions.contains(settings.preferredSubtitleLang)
                              ? settings.preferredSubtitleLang
                              : 'off',
                          isExpanded: true,
                          isDense: true,
                          items: <DropdownMenuItem<String>>[
                            DropdownMenuItem<String>(
                              value: 'off',
                              child: Text(strings.subtitlesOffByDefault),
                            ),
                            for (final code in _langOptions.where((c) => c.isNotEmpty))
                              DropdownMenuItem<String>(
                                value: code,
                                child: Text(
                                  languageName(code, arabic: strings.isArabic),
                                ),
                              ),
                          ],
                          onChanged: (value) {
                            if (value != null) {
                              unawaited(state.setPreferredSubtitleLang(value));
                            }
                          },
                        ),
                      ),
                    ),
                    SwitchListTile(
                      value: settings.rememberTracks,
                      onChanged: (value) =>
                          unawaited(state.setRememberTracks(value)),
                      contentPadding: EdgeInsets.zero,
                      title: Text(strings.rememberTracks),
                      subtitle: Text(
                        strings.rememberTracksHelp,
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: colors.subtext0,
                            ),
                      ),
                    ),
                    if (kIsDesktop)
                      SwitchListTile(
                        value: settings.zapBanner,
                        onChanged: (value) =>
                            unawaited(state.setZapBanner(value)),
                        contentPadding: EdgeInsets.zero,
                        title: Text(strings.zapBanner),
                        subtitle: Text(
                          strings.zapBannerHelp,
                          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                color: colors.subtext0,
                              ),
                        ),
                      ),
                  ],
                ),
                _Section(
                  title: strings.visualsAndPerformance,
                  children: <Widget>[
                    SwitchListTile(
                      value: settings.richVisuals,
                      onChanged: (value) =>
                          unawaited(state.setRichVisuals(value)),
                      contentPadding: EdgeInsets.zero,
                      title: Text(strings.richVisuals),
                      subtitle: Text(
                        strings.richVisualsHelp,
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: colors.subtext0,
                            ),
                      ),
                    ),
                    SwitchListTile(
                      value: settings.reduceMotion,
                      onChanged: (value) =>
                          unawaited(state.setReduceMotion(value)),
                      contentPadding: EdgeInsets.zero,
                      title: Text(strings.reduceMotion),
                      subtitle: Text(
                        strings.reduceMotionHelp,
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: colors.subtext0,
                            ),
                      ),
                    ),
                  ],
                ),
                _Section(
                  title: strings.language,
                  children: <Widget>[
                    InputDecorator(
                      decoration: const InputDecoration(
                        prefixIcon: Icon(Icons.translate_rounded),
                      ),
                      child: DropdownButtonHideUnderline(
                        child: DropdownButton<AppLanguage>(
                          value: settings.language,
                          isExpanded: true,
                          isDense: true,
                          items: <DropdownMenuItem<AppLanguage>>[
                            DropdownMenuItem<AppLanguage>(
                              value: AppLanguage.system,
                              child: Text(strings.systemLanguage),
                            ),
                            DropdownMenuItem<AppLanguage>(
                              value: AppLanguage.english,
                              child: Text(strings.english),
                            ),
                            DropdownMenuItem<AppLanguage>(
                              value: AppLanguage.arabic,
                              child: Text(strings.arabic),
                            ),
                          ],
                          onChanged: (value) {
                            if (value != null) {
                              unawaited(state.setLanguage(value));
                            }
                          },
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      strings.languageHelp,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: colors.subtext0,
                          ),
                    ),
                    const SizedBox(height: 20),
                    _FieldLabel(text: strings.timeFormat),
                    SwitchListTile(
                      value: settings.use24HourTime,
                      onChanged: (value) =>
                          unawaited(state.setUse24HourTime(value)),
                      contentPadding: EdgeInsets.zero,
                      title: Text(strings.use24HourTime),
                      subtitle: Text(
                        strings.use24HourTimeHelp,
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: colors.subtext0,
                            ),
                      ),
                    ),
                  ],
                ),
                if (kIsDesktop) const _PlayerSettings(),
                _Section(
                  title: strings.recordings,
                  children: <Widget>[
                    _FieldLabel(text: strings.recordFolder),
                    FutureBuilder<String>(
                      future: LocalRecordings.directory(settings.recordDir)
                          .then((dir) => dir.path)
                          .catchError((Object _) => settings.recordDir),
                      builder: (context, snapshot) {
                        return ListTile(
                          contentPadding: EdgeInsets.zero,
                          leading: const Icon(Icons.folder_rounded),
                          title: BidiText(
                            snapshot.data ?? settings.recordDir,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                          subtitle: Text(
                            settings.recordDir.isEmpty
                                ? strings.defaultFolder
                                : strings.recordFolderHelp,
                          ),
                        );
                      },
                    ),
                    Wrap(
                      spacing: 8,
                      children: <Widget>[
                        if (kIsDesktop)
                          FilledButton.tonalIcon(
                            onPressed: () async {
                              final path = await getDirectoryPath();
                              if (path != null) {
                                unawaited(state.updateSettings(
                                  settings.copyWith(recordDir: path),
                                ));
                              }
                            },
                            icon: const Icon(Icons.folder_open_rounded, size: 18),
                            label: Text(strings.chooseFolder),
                          ),
                        if (settings.recordDir.isNotEmpty)
                          TextButton(
                            onPressed: () => unawaited(
                              state.updateSettings(settings.copyWith(recordDir: '')),
                            ),
                            child: Text(strings.resetToDefault),
                          ),
                      ],
                    ),
                  ],
                ),
                _Section(
                  title: strings.dataAndGuide,
                  children: <Widget>[
                    _InfoRow(
                      icon: Icons.dns_rounded,
                      label: strings.activeSource,
                      value: state.activeSource?.name ?? strings.noActiveSource,
                    ),
                    _InfoRow(
                      icon: Icons.router_rounded,
                      label: strings.server,
                      value: state.hasContent
                          ? '${state.serverInfo.name} ${state.serverInfo.version}'
                              .trim()
                          : strings.notConfigured,
                    ),
                    _InfoRow(
                      icon: state.isAdmin
                          ? Icons.admin_panel_settings_outlined
                          : Icons.person_outline_rounded,
                      label: strings.username,
                      value: state.hasContent
                          ? '${state.activeSource?.username ?? ''} · '
                              '${state.isAdmin ? strings.adminAccount : strings.userAccount}'
                          : strings.notConfigured,
                    ),
                    if (state.isAdmin)
                      ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading: const Icon(Icons.monitor_heart_outlined),
                        title: Text(strings.serverStatus),
                        trailing: const Icon(Icons.chevron_right_rounded),
                        onTap: () => Navigator.of(context).push(
                          MaterialPageRoute<void>(
                            builder: (context) => const ServerPage(),
                          ),
                        ),
                      ),
                    _InfoRow(
                      icon: Icons.schedule_rounded,
                      label: strings.lastUpdated,
                      value: state.lastLoaded == null
                          ? strings.never
                          : '${strings.relativeTime(state.lastLoaded!, state.now)} · '
                              '${strings.formatDateTime(state.lastLoaded!, use24HourTime: settings.use24HourTime)}',
                    ),
                    if (state.hasContent)
                      _InfoRow(
                        icon: Icons.live_tv_rounded,
                        label: strings.channelsLabel,
                        value:
                            '${strings.channelCount(state.channels.length)} · '
                            '${strings.programmeCount(state.epg.programmeCount)}',
                      ),
                    const SizedBox(height: 6),
                    _FieldLabel(text: strings.guideSpan),
                    DropdownButton<int>(
                      isExpanded: true,
                      value: const <int>[12, 24, 48, 72]
                              .contains(settings.guideHours)
                          ? settings.guideHours
                          : 12,
                      dropdownColor: colors.surface1,
                      items: <DropdownMenuItem<int>>[
                        for (final hours in const <int>[12, 24, 48, 72])
                          DropdownMenuItem<int>(
                            value: hours,
                            child: Text(strings.hoursCount(hours)),
                          ),
                      ],
                      onChanged: (value) {
                        if (value != null) {
                          unawaited(
                            state.updateSettings(
                              settings.copyWith(guideHours: value),
                            ),
                          );
                        }
                      },
                    ),
                    const SizedBox(height: 12),
                    _FieldLabel(text: strings.guideDaysBackLabel),
                    DropdownButton<int>(
                      isExpanded: true,
                      value: const <int>[0, 1, 2, 3, 5, 7, 14]
                              .contains(settings.guideDaysBack)
                          ? settings.guideDaysBack
                          : 3,
                      dropdownColor: colors.surface1,
                      items: <DropdownMenuItem<int>>[
                        for (final days in const <int>[0, 1, 2, 3, 5, 7, 14])
                          DropdownMenuItem<int>(
                            value: days,
                            child: Text(strings.daysCount(days)),
                          ),
                      ],
                      onChanged: (value) {
                        if (value != null) {
                          unawaited(
                            state.updateSettings(
                              settings.copyWith(guideDaysBack: value),
                            ),
                          );
                        }
                      },
                    ),
                    Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Text(
                        strings.guideDaysBackHelp,
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: colors.subtext0,
                            ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    _FieldLabel(text: strings.autoRefresh),
                    DropdownButton<int>(
                      isExpanded: true,
                      value: const <int>[0, 30, 60, 180, 360, 720, 1440]
                              .contains(settings.autoRefreshMinutes)
                          ? settings.autoRefreshMinutes
                          : 360,
                      dropdownColor: colors.surface1,
                      items: <DropdownMenuItem<int>>[
                        for (final minutes in const <int>[
                          0, 30, 60, 180, 360, 720, 1440,
                        ])
                          DropdownMenuItem<int>(
                            value: minutes,
                            child: Text(
                              minutes == 0
                                  ? strings.autoRefreshOff
                                  : strings.autoRefreshEvery(minutes),
                            ),
                          ),
                      ],
                      onChanged: (value) {
                        if (value != null) {
                          unawaited(
                            state.updateSettings(
                              settings.copyWith(autoRefreshMinutes: value),
                            ),
                          );
                        }
                      },
                    ),
                    Text(
                      strings.autoRefreshHelp,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: colors.subtext0,
                          ),
                    ),
                    const SizedBox(height: 14),
                    Wrap(
                      spacing: 10,
                      runSpacing: 10,
                      children: <Widget>[
                        OutlinedButton.icon(
                          onPressed:
                              state.isLoading ? null : () => state.refresh(),
                          icon: state.isLoading
                              ? const SizedBox(
                                  width: 16,
                                  height: 16,
                                  child:
                                      CircularProgressIndicator(strokeWidth: 2),
                                )
                              : const Icon(Icons.refresh_rounded, size: 18),
                          label: Text(
                            state.isLoading ? strings.refreshing : strings.refresh,
                          ),
                        ),
                        TextButton.icon(
                          onPressed: onOpenSources,
                          icon: const Icon(Icons.dns_rounded, size: 18),
                          label: Text(strings.sources),
                        ),
                      ],
                    ),
                  ],
                ),
                _Section(
                  title: strings.about,
                  children: <Widget>[
                    Row(
                      children: <Widget>[
                        Container(
                          width: 54,
                          height: 54,
                          decoration: BoxDecoration(
                            color: colors.accentSoft,
                            borderRadius: BorderRadius.circular(16),
                          ),
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(16),
                            child: Image.asset(
                              'assets/branding/mawjtvh_icon.png',
                              fit: BoxFit.cover,
                            ),
                          ),
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: <Widget>[
                              Text(
                                '${strings.appName} $kAppVersion',
                                style: Theme.of(context)
                                    .textTheme
                                    .titleMedium
                                    ?.copyWith(fontWeight: FontWeight.w700),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                strings.appTagline,
                                style: Theme.of(context)
                                    .textTheme
                                    .bodySmall
                                    ?.copyWith(color: colors.subtext0),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 14),
                    Text(
                      strings.aboutBody,
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                            color: colors.subtext1,
                            height: 1.55,
                          ),
                    ),
                    const SizedBox(height: 12),
                    SelectableText(
                      kProjectUrl,
                      textDirection: TextDirection.ltr,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: colors.accent,
                          ),
                    ),
                    const SizedBox(height: 14),
                    Wrap(
                      spacing: 10,
                      runSpacing: 10,
                      children: <Widget>[
                        OutlinedButton.icon(
                          onPressed: () {
                            showLicensePage(
                              context: context,
                              applicationName: strings.appName,
                              applicationVersion: kAppVersion,
                              applicationIcon: Padding(
                                padding: const EdgeInsets.all(8),
                                child: Icon(
                                  Icons.live_tv_rounded,
                                  color: colors.accent,
                                  size: 36,
                                ),
                              ),
                            );
                          },
                          icon: const Icon(
                            Icons.description_outlined,
                            size: 18,
                          ),
                          label: Text(strings.licenses),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 8,
                          ),
                          decoration: BoxDecoration(
                            color: colors.surface0,
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(
                            kLicenseName,
                            style:
                                Theme.of(context).textTheme.labelSmall?.copyWith(
                                      color: colors.subtext0,
                                    ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ],
    ),
    );
  }
}

class _Section extends StatelessWidget {
  const _Section({required this.title, required this.children});

  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final colors = context.mawjColors;
    return Padding(
      padding: const EdgeInsets.only(bottom: 26),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            title,
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  color: colors.accent,
                  fontWeight: FontWeight.w700,
                ),
          ),
          const SizedBox(height: 10),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: colors.surface0,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: colors.surface1),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: children,
            ),
          ),
        ],
      ),
    );
  }
}

class _FieldLabel extends StatelessWidget {
  const _FieldLabel({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: Theme.of(context).textTheme.labelLarge?.copyWith(
            fontWeight: FontWeight.w700,
          ),
    );
  }
}

class _ThemeChip extends StatelessWidget {
  const _ThemeChip({
    required this.family,
    required this.selected,
    required this.accent,
    required this.label,
    required this.onTap,
  });

  final ThemeFamily family;
  final bool selected;
  final ThemeAccent accent;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.mawjColors;
    final preview = previewColorFor(family, accent);
    return Material(
      color: selected ? colors.accentSoft : colors.mantle,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: selected ? colors.accent : colors.surface1,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Container(
                width: 18,
                height: 18,
                decoration: BoxDecoration(
                  color: family == ThemeFamily.amoled
                      ? Colors.black
                      : preview,
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: colors.overlay0.withValues(alpha: 0.5),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Text(
                label,
                style: Theme.of(context).textTheme.labelMedium?.copyWith(
                      fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                    ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _AccentDot extends StatelessWidget {
  const _AccentDot({
    required this.accent,
    required this.selected,
    required this.palette,
    required this.onTap,
  });

  final ThemeAccent accent;
  final bool selected;
  final CatppuccinPalette palette;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final color = palette.accent(accent);
    final foreground =
        color.computeLuminance() > 0.55 ? Colors.black : Colors.white;
    return Tooltip(
      message: accent.label,
      child: InkWell(
        onTap: onTap,
        customBorder: const CircleBorder(),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          width: 34,
          height: 34,
          decoration: BoxDecoration(
            color: color,
            shape: BoxShape.circle,
            border: Border.all(
              color: selected
                  ? Theme.of(context).colorScheme.onSurface
                  : Colors.transparent,
              width: 2.5,
            ),
          ),
          child: selected
              ? Icon(Icons.check_rounded, size: 18, color: foreground)
              : null,
        ),
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  const _InfoRow({
    required this.icon,
    required this.label,
    required this.value,
  });

  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final colors = context.mawjColors;
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Icon(icon, size: 18, color: colors.overlay0),
          const SizedBox(width: 10),
          SizedBox(
            width: 130,
            child: Text(
              label,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: colors.subtext0,
                  ),
            ),
          ),
          Expanded(
            child: BidiText(
              value,
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: colors.text,
                    fontWeight: FontWeight.w500,
                  ),
            ),
          ),
        ],
      ),
    );
  }
}


/// Desktop player options: engine, hardware decoding and video output, with
/// the hardware decoders offered taken from what the installed mpv reports.
class _PlayerSettings extends StatelessWidget {
  const _PlayerSettings();

  static String _hwdecLabel(AppStrings strings, String value) {
    return switch (value) {
      'auto-safe' => strings.hwdecAutoSafe,
      'auto' => strings.hwdecAuto,
      'auto-copy-safe' || 'auto-copy' => strings.hwdecAutoCopy,
      'no' => strings.hwdecOff,
      _ => value,
    };
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final strings = context.strings;
    final colors = context.mawjColors;
    final theme = Theme.of(context);
    final settings = state.settings;

    return _Section(
      title: strings.playerSection,
      children: <Widget>[
        FutureBuilder<MpvCapabilities?>(
          future: MpvRuntime.capabilities(),
          builder: (context, snapshot) {
            final capabilities = snapshot.data;
            final loading = snapshot.connectionState != ConnectionState.done;
            final hwdecs = <String>[
              'auto-safe',
              'auto',
              if (capabilities == null ||
                  capabilities.hwdecs.contains('auto-copy-safe'))
                'auto-copy-safe',
              'no',
              ...?capabilities?.specificHwdecs,
            ];
            final hwdec =
                hwdecs.contains(settings.hwdec) ? settings.hwdec : 'auto-safe';
            const outputs = <String>[
              'auto',
              'gpu-next',
              'gpu',
              'dmabuf-wayland',
            ];
            final output = outputs.contains(settings.videoOutput)
                ? settings.videoOutput
                : 'auto';
            final enabled = capabilities != null;

            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                _InfoRow(
                  icon: Icons.smart_display_rounded,
                  label: 'mpv',
                  value: loading
                      ? '…'
                      : capabilities == null
                          ? '${strings.mpvMissing}${MpvRuntime.lastProblem == null ? '' : '\n${MpvRuntime.lastProblem}'}'
                          : strings.mpvFound(
                              capabilities.version,
                              capabilities.bundled,
                            ),
                ),
                _MpvPathField(
                  initial: settings.mpvPath,
                  label: strings.mpvPathLabel,
                  hint: strings.mpvPathHint,
                  apply: strings.apply,
                  onApply: (value) {
                    MpvRuntime.useCustomPath(value);
                    unawaited(
                      state.updateSettings(settings.copyWith(mpvPath: value)),
                    );
                  },
                ),
                SwitchListTile(
                  value: enabled && settings.useMpvWindow,
                  onChanged: enabled
                      ? (value) => unawaited(
                            state.updateSettings(
                              settings.copyWith(useMpvWindow: value),
                            ),
                          )
                      : null,
                  contentPadding: EdgeInsets.zero,
                  title: Text(strings.useMpvWindow),
                  subtitle: Text(
                    strings.useMpvWindowBody,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: colors.subtext0,
                    ),
                  ),
                ),
                if (!settings.useMpvWindow)
                  SwitchListTile(
                    value: enabled && settings.recordingsInMpv,
                    onChanged: enabled
                        ? (value) => unawaited(
                              state.updateSettings(
                                settings.copyWith(recordingsInMpv: value),
                              ),
                            )
                        : null,
                    contentPadding: EdgeInsets.zero,
                    title: Text(strings.recordingsInMpv),
                    subtitle: Text(
                      strings.recordingsInMpvBody,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: colors.subtext0,
                      ),
                    ),
                  ),
                if (!settings.useMpvWindow) ...<Widget>[
                  const SizedBox(height: 8),
                  _FieldLabel(text: strings.inAppRenderer),
                  DropdownButton<String>(
                    isExpanded: true,
                    value: const <String>['auto', 'gpu', 'cpu']
                            .contains(settings.inAppRenderer)
                        ? settings.inAppRenderer
                        : 'auto',
                    dropdownColor: colors.surface1,
                    items: <DropdownMenuItem<String>>[
                      DropdownMenuItem<String>(
                        value: 'auto',
                        child: Text(strings.rendererAuto),
                      ),
                      DropdownMenuItem<String>(
                        value: 'gpu',
                        child: Text(strings.rendererGpu),
                      ),
                      DropdownMenuItem<String>(
                        value: 'cpu',
                        child: Text(strings.rendererCpu),
                      ),
                    ],
                    onChanged: (value) {
                      if (value != null) {
                        unawaited(
                          state.updateSettings(
                            settings.copyWith(inAppRenderer: value),
                          ),
                        );
                      }
                    },
                  ),
                  Text(
                    strings.inAppRendererHelp,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: colors.subtext0,
                      height: 1.4,
                    ),
                  ),
                  const SizedBox(height: 12),
                  _FieldLabel(text: strings.hardwareDecoding),
                  DropdownButton<String>(
                    isExpanded: true,
                    value: const <String>['auto-safe', 'auto', 'auto-copy-safe', 'no']
                            .contains(settings.hwdec)
                        ? settings.hwdec
                        : 'auto-safe',
                    dropdownColor: colors.surface1,
                    items: <DropdownMenuItem<String>>[
                      for (final value in const <String>[
                        'auto-safe',
                        'auto',
                        'auto-copy-safe',
                        'no',
                      ])
                        DropdownMenuItem<String>(
                          value: value,
                          child: Text(_hwdecLabel(strings, value)),
                        ),
                    ],
                    onChanged: (value) {
                      if (value != null) {
                        unawaited(
                          state.updateSettings(settings.copyWith(hwdec: value)),
                        );
                      }
                    },
                  ),
                ],
                if (enabled && settings.useMpvWindow) ...<Widget>[
                  const SizedBox(height: 8),
                  _FieldLabel(text: strings.hardwareDecoding),
                  DropdownButton<String>(
                    isExpanded: true,
                    value: hwdec,
                    dropdownColor: colors.surface1,
                    items: <DropdownMenuItem<String>>[
                      for (final value in hwdecs)
                        DropdownMenuItem<String>(
                          value: value,
                          child: Text(_hwdecLabel(strings, value)),
                        ),
                    ],
                    onChanged: (value) {
                      if (value != null) {
                        unawaited(
                          state.updateSettings(settings.copyWith(hwdec: value)),
                        );
                      }
                    },
                  ),
                  const SizedBox(height: 12),
                  _FieldLabel(text: strings.videoOutput),
                  DropdownButton<String>(
                    isExpanded: true,
                    value: output,
                    dropdownColor: colors.surface1,
                    items: <DropdownMenuItem<String>>[
                      for (final value in outputs)
                        DropdownMenuItem<String>(
                          value: value,
                          child: Text(
                            value == 'auto' ? strings.videoOutputAuto : value,
                          ),
                        ),
                    ],
                    onChanged: (value) {
                      if (value != null) {
                        unawaited(
                          state.updateSettings(
                            settings.copyWith(videoOutput: value),
                          ),
                        );
                      }
                    },
                  ),
                  SwitchListTile(
                    value: settings.startFullscreen,
                    onChanged: (value) => unawaited(
                      state.updateSettings(
                        settings.copyWith(startFullscreen: value),
                      ),
                    ),
                    contentPadding: EdgeInsets.zero,
                    title: Text(strings.startFullscreen),
                  ),
                  SwitchListTile(
                    value: settings.useMpvConfig,
                    onChanged: (value) => unawaited(
                      state.updateSettings(
                        settings.copyWith(useMpvConfig: value),
                      ),
                    ),
                    contentPadding: EdgeInsets.zero,
                    title: Text(strings.useMpvConfig),
                    subtitle: Text(
                      strings.useMpvConfigBody,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: colors.subtext0,
                      ),
                    ),
                  ),
                ],
              ],
            );
          },
        ),
      ],
    );
  }
}


class _MpvPathField extends StatefulWidget {
  const _MpvPathField({
    required this.initial,
    required this.label,
    required this.hint,
    required this.apply,
    required this.onApply,
  });

  final String initial;
  final String label;
  final String hint;
  final String apply;
  final ValueChanged<String> onApply;

  @override
  State<_MpvPathField> createState() => _MpvPathFieldState();
}

class _MpvPathFieldState extends State<_MpvPathField> {
  late final TextEditingController _controller =
      TextEditingController(text: widget.initial);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: <Widget>[
          Expanded(
            child: TextField(
              controller: _controller,
              autocorrect: false,
              textDirection: TextDirection.ltr,
              decoration: InputDecoration(
                labelText: widget.label,
                hintText: widget.hint,
              ),
              onSubmitted: widget.onApply,
            ),
          ),
          const SizedBox(width: 10),
          FilledButton(
            onPressed: () => widget.onApply(_controller.text),
            child: Text(widget.apply),
          ),
        ],
      ),
    );
  }
}

/// Languages offered as defaults; empty is "stream default".
const List<String> _langOptions = <String>[
  '',
  'ara',
  'eng',
  'fra',
  'deu',
  'spa',
  'ita',
  'por',
  'rus',
  'tur',
  'fas',
  'kur',
  'hin',
  'urd',
  'heb',
  'zho',
  'jpn',
  'kor',
];

const List<double> _guideSteps = <double>[0, 1.0, 1.15, 1.3, 1.5, 1.75];

Widget _dropdown<T>({
  required IconData icon,
  required String label,
  required T value,
  required List<(T, String)> options,
  required void Function(T value) onChanged,
}) {
  return InputDecorator(
    decoration: InputDecoration(
      prefixIcon: Icon(icon),
      labelText: label,
    ),
    child: DropdownButtonHideUnderline(
      child: DropdownButton<T>(
        value: value,
        isExpanded: true,
        isDense: true,
        items: <DropdownMenuItem<T>>[
          for (final option in options)
            DropdownMenuItem<T>(value: option.$1, child: Text(option.$2)),
        ],
        onChanged: (next) {
          if (next != null) {
            onChanged(next);
          }
        },
      ),
    ),
  );
}
