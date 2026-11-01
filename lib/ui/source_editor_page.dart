import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/bidi.dart';
import '../core/theme.dart';
import '../data/app_state.dart';
import '../data/models.dart';
import '../l10n/strings.dart';

class SourceEditorPage extends StatefulWidget {
  const SourceEditorPage({super.key, this.source});

  final SourceConfig? source;

  @override
  State<SourceEditorPage> createState() => _SourceEditorPageState();
}

class _SourceEditorPageState extends State<SourceEditorPage> {
  late final TextEditingController _name;
  late final TextEditingController _m3u;
  late final TextEditingController _epg;
  late EndpointKind _m3uKind;
  late EndpointKind _epgKind;
  late bool _allowInsecure;

  bool _saving = false;
  bool _testing = false;
  String? _formError;
  String? _testMessage;
  bool _testPassed = false;

  @override
  void initState() {
    super.initState();
    final source = widget.source;
    _name = TextEditingController(text: source?.name ?? '');
    _m3u = TextEditingController(text: source?.m3u.value ?? '');
    _epg = TextEditingController(text: source?.epg.value ?? '');
    _m3uKind = source?.m3u.kind ?? EndpointKind.url;
    _epgKind = source?.epg.kind ?? EndpointKind.url;
    _allowInsecure = source?.allowInsecureCerts ?? false;
  }

  @override
  void dispose() {
    _name.dispose();
    _m3u.dispose();
    _epg.dispose();
    super.dispose();
  }

  bool get _isEditing => widget.source != null;

  SourceConfig _draft() {
    final trimmedName = _name.text.trim();
    return SourceConfig(
      id: widget.source?.id ?? generateSourceId(),
      name: trimmedName.isEmpty ? 'Source' : trimmedName,
      m3u: SourceEndpoint(value: _m3u.text.trim(), kind: _m3uKind),
      epg: SourceEndpoint(value: _epg.text.trim(), kind: _epgKind),
      allowInsecureCerts: _allowInsecure,
    );
  }

  bool _validate() {
    final strings = context.strings;
    String? error;
    if (_name.text.trim().isEmpty) {
      error = strings.sourceNameRequired;
    } else if (_m3u.text.trim().isEmpty) {
      error = strings.playlistRequired;
    } else if (!_validEndpoint(_m3u.text.trim(), _m3uKind)) {
      error = strings.invalidLocation;
    } else if (_epg.text.trim().isNotEmpty &&
        !_validEndpoint(_epg.text.trim(), _epgKind)) {
      error = strings.invalidLocation;
    }
    setState(() => _formError = error);
    return error == null;
  }

  bool _validEndpoint(String value, EndpointKind kind) {
    if (kind == EndpointKind.file) {
      return value.isNotEmpty;
    }
    final uri = Uri.tryParse(value);
    return uri != null &&
        (uri.scheme == 'http' || uri.scheme == 'https') &&
        uri.host.isNotEmpty;
  }

  Future<void> _pickFile({required bool playlist}) async {
    final strings = context.strings;
    final type = playlist
        ? const XTypeGroup(
            label: 'M3U',
            extensions: <String>['m3u', 'm3u8'],
          )
        : const XTypeGroup(
            label: 'XMLTV',
            extensions: <String>['xml', 'xmltv', 'gz'],
          );
    try {
      final file = await openFile(acceptedTypeGroups: <XTypeGroup>[type]);
      if (file == null || !mounted) {
        return;
      }
      setState(() {
        if (playlist) {
          _m3u.text = file.path;
          _m3uKind = EndpointKind.file;
        } else {
          _epg.text = file.path;
          _epgKind = EndpointKind.file;
        }
      });
    } catch (error) {
      if (mounted) {
        setState(() => _formError = '${strings.errorGeneric} $error');
      }
    }
  }

  Future<void> _test() async {
    if (!_validate() || _testing) {
      return;
    }
    final state = context.read<AppState>();
    final strings = context.strings;
    setState(() {
      _testing = true;
      _testMessage = null;
      _testPassed = false;
    });
    try {
      final content = await state.probe(_draft());
      if (!mounted) {
        return;
      }
      setState(() {
        _testPassed = true;
        _testMessage = strings.testSummary(
          content.playlist.channels.length,
          content.epg.programmeCount,
        );
      });
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _testPassed = false;
        _testMessage = error.toString();
      });
    } finally {
      if (mounted) {
        setState(() => _testing = false);
      }
    }
  }

  Future<void> _save() async {
    if (_saving || !_validate()) {
      return;
    }
    final state = context.read<AppState>();
    final source = _draft();
    setState(() => _saving = true);
    try {
      if (_isEditing) {
        await state.updateSource(source);
      } else {
        await state.addSource(source);
      }
      if (mounted) {
        Navigator.of(context).pop(true);
      }
    } catch (error) {
      if (mounted) {
        setState(() {
          _saving = false;
          _formError = error.toString();
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final strings = context.strings;
    final colors = context.mawjColors;

    return Scaffold(
      appBar: AppBar(
        title: Text(
          _isEditing ? strings.editSourceTitle : strings.addSourceTitle,
        ),
        actions: <Widget>[
          Padding(
            padding: const EdgeInsetsDirectional.only(end: 10),
            child: FilledButton.icon(
              onPressed: _saving ? null : _save,
              icon: _saving
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.check_rounded, size: 18),
              label: Text(strings.save),
            ),
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 720),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                if (_formError != null) ...<Widget>[
                  _ResultCard(
                    message: _formError!,
                    passed: false,
                  ),
                  const SizedBox(height: 16),
                ],
                Text(
                  strings.sourceName,
                  style: Theme.of(context).textTheme.labelLarge?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                ),
                const SizedBox(height: 6),
                TextField(
                  controller: _name,
                  textInputAction: TextInputAction.next,
                  decoration: InputDecoration(
                    hintText: strings.sourceNameHint,
                    prefixIcon: const Icon(Icons.label_outline_rounded),
                  ),
                ),
                const SizedBox(height: 22),
                _EndpointField(
                  label: strings.playlistM3u,
                  hint: 'https://example.com/channels.m3u',
                  fileHint: '/home/you/channels.m3u',
                  help: strings.playlistHelp,
                  controller: _m3u,
                  kind: _m3uKind,
                  onKindChanged: (kind) => setState(() => _m3uKind = kind),
                  onBrowse: () => _pickFile(playlist: true),
                  browseLabel: strings.chooseFile,
                  fileLabel: strings.file,
                  urlLabel: strings.url,
                ),
                const SizedBox(height: 22),
                _EndpointField(
                  label: strings.xmltvGuide,
                  hint: 'https://example.com/xmltv.xml',
                  fileHint: '/home/you/guide.xml',
                  help: strings.guideHelp,
                  controller: _epg,
                  kind: _epgKind,
                  onKindChanged: (kind) => setState(() => _epgKind = kind),
                  onBrowse: () => _pickFile(playlist: false),
                  browseLabel: strings.chooseFile,
                  fileLabel: strings.file,
                  urlLabel: strings.url,
                ),
                const SizedBox(height: 10),
                SwitchListTile(
                  value: _allowInsecure,
                  onChanged: (value) => setState(() => _allowInsecure = value),
                  contentPadding: EdgeInsets.zero,
                  title: Text(strings.allowInsecure),
                  subtitle: Text(
                    strings.allowInsecureHelp,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: colors.subtext0,
                          height: 1.4,
                        ),
                  ),
                ),
                const SizedBox(height: 10),
                Row(
                  children: <Widget>[
                    OutlinedButton.icon(
                      onPressed: _testing ? null : _test,
                      icon: _testing
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.wifi_tethering_rounded, size: 18),
                      label: Text(
                        _testing ? strings.testing : strings.testConnection,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: _testMessage == null
                          ? const SizedBox.shrink()
                          : _ResultCard(
                              message: _testMessage!,
                              passed: _testPassed,
                            ),
                    ),
                  ],
                ),
                const SizedBox(height: 22),
                FilledButton.icon(
                  onPressed: _saving ? null : _save,
                  icon: const Icon(Icons.save_rounded),
                  label: Text(_isEditing ? strings.save : strings.saveAndLoad),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _EndpointField extends StatelessWidget {
  const _EndpointField({
    required this.label,
    required this.hint,
    required this.fileHint,
    required this.help,
    required this.controller,
    required this.kind,
    required this.onKindChanged,
    required this.onBrowse,
    required this.browseLabel,
    required this.fileLabel,
    required this.urlLabel,
  });

  final String label;
  final String hint;
  final String fileHint;
  final String help;
  final TextEditingController controller;
  final EndpointKind kind;
  final ValueChanged<EndpointKind> onKindChanged;
  final VoidCallback onBrowse;
  final String browseLabel;
  final String fileLabel;
  final String urlLabel;

  @override
  Widget build(BuildContext context) {
    final colors = context.mawjColors;
    final isFile = kind == EndpointKind.file;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(
          label,
          style: Theme.of(context).textTheme.labelLarge?.copyWith(
                fontWeight: FontWeight.w700,
              ),
        ),
        const SizedBox(height: 6),
        TextField(
          controller: controller,
          keyboardType: isFile ? TextInputType.text : TextInputType.url,
          textInputAction: TextInputAction.next,
          // URLs and filesystem paths are LTR even when the interface is Arabic.
          textDirection: TextDirection.ltr,
          textAlign: TextAlign.start,
          decoration: InputDecoration(
            hintText: isFile ? fileHint : hint,
            prefixIcon: Icon(
              isFile ? Icons.insert_drive_file_outlined : Icons.link_rounded,
            ),
            suffixIcon: isFile
                ? IconButton(
                    tooltip: browseLabel,
                    icon: const Icon(Icons.folder_open_rounded),
                    onPressed: onBrowse,
                  )
                : null,
          ),
        ),
        const SizedBox(height: 8),
        Row(
          children: <Widget>[
            SegmentedButton<EndpointKind>(
              segments: <ButtonSegment<EndpointKind>>[
                ButtonSegment<EndpointKind>(
                  value: EndpointKind.url,
                  label: Text(urlLabel),
                  icon: const Icon(Icons.link_rounded, size: 16),
                ),
                ButtonSegment<EndpointKind>(
                  value: EndpointKind.file,
                  label: Text(fileLabel),
                  icon: const Icon(Icons.folder_open_rounded, size: 16),
                ),
              ],
              selected: <EndpointKind>{kind},
              onSelectionChanged: (selection) => onKindChanged(selection.first),
              showSelectedIcon: false,
              style: const ButtonStyle(
                visualDensity: VisualDensity.compact,
              ),
            ),
            if (isFile) ...<Widget>[
              const SizedBox(width: 10),
              TextButton.icon(
                onPressed: onBrowse,
                icon: const Icon(Icons.folder_open_rounded, size: 16),
                label: Text(browseLabel),
              ),
            ],
          ],
        ),
        const SizedBox(height: 4),
        Text(
          help,
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: colors.subtext0,
                height: 1.4,
              ),
        ),
      ],
    );
  }
}

class _ResultCard extends StatelessWidget {
  const _ResultCard({required this.message, required this.passed});

  final String message;
  final bool passed;

  @override
  Widget build(BuildContext context) {
    final colors = context.mawjColors;
    final errorColor = Theme.of(context).colorScheme.error;
    final color = passed ? colors.accent : errorColor;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.5)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Icon(
            passed ? Icons.check_circle_outline_rounded : Icons.error_outline_rounded,
            size: 18,
            color: color,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: BidiText(
              message,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: colors.subtext1,
                    height: 1.4,
                  ),
            ),
          ),
        ],
      ),
    );
  }
}
