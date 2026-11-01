import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/bidi.dart';
import '../core/theme.dart';
import '../data/app_state.dart';
import '../data/models.dart';
import '../data/tvh_address.dart';
import '../l10n/strings.dart';
import '../l10n/tvh_strings.dart';

/// Add or edit a Tvheadend server.
class SourceEditorPage extends StatefulWidget {
  const SourceEditorPage({super.key, this.source});

  final SourceConfig? source;

  @override
  State<SourceEditorPage> createState() => _SourceEditorPageState();
}

class _SourceEditorPageState extends State<SourceEditorPage> {
  late final TextEditingController _name;
  late final TextEditingController _address;
  late final TextEditingController _username;
  late final TextEditingController _password;
  late final TextEditingController _profile;
  late bool _allowInsecure;

  bool _saving = false;
  bool _testing = false;
  bool _showPassword = false;
  String? _formError;
  String? _testMessage;
  bool _testPassed = false;
  List<String> _profiles = const <String>[];

  @override
  void initState() {
    super.initState();
    final source = widget.source;
    _name = TextEditingController(text: source?.name ?? '');
    _address = TextEditingController(text: source?.address ?? '');
    _username = TextEditingController(text: source?.username ?? '');
    _password = TextEditingController(text: source?.password ?? '');
    _profile = TextEditingController(text: source?.profile ?? '');
    _allowInsecure = source?.allowInsecureCerts ?? false;
  }

  @override
  void dispose() {
    _name.dispose();
    _address.dispose();
    _username.dispose();
    _password.dispose();
    _profile.dispose();
    super.dispose();
  }

  bool get _isEditing => widget.source != null;

  SourceConfig _draft() {
    final trimmedName = _name.text.trim();
    return SourceConfig(
      id: widget.source?.id ?? generateSourceId(),
      name: trimmedName.isEmpty ? _address.text.trim() : trimmedName,
      address: _address.text.trim(),
      username: _username.text.trim(),
      password: _password.text,
      profile: _profile.text.trim(),
      allowInsecureCerts: _allowInsecure,
    );
  }

  bool _validate() {
    final strings = context.strings;
    String? error;
    if (_address.text.trim().isEmpty) {
      error = strings.addressRequired;
    } else {
      try {
        TvhAddress.parse(_address.text);
      } on TvhAddressException catch (problem) {
        error = problem.message;
      }
    }
    setState(() => _formError = error);
    return error == null;
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
        _profiles = content.profiles;
        _testMessage = strings.connectedSummary(
          server: '${content.serverInfo.name} ${content.serverInfo.version}'.trim(),
          channels: content.playlist.channels.length,
          programmes: content.epg.programmeCount,
          admin: content.permissions.admin,
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

  Widget _label(BuildContext context, String text) {
    return Text(
      text,
      style: Theme.of(context).textTheme.labelLarge?.copyWith(
            fontWeight: FontWeight.w700,
          ),
    );
  }

  Widget _help(BuildContext context, String text) {
    final colors = context.mawjColors;
    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: Text(
        text,
        style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: colors.subtext0,
              height: 1.4,
            ),
      ),
    );
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
                  _ResultCard(message: _formError!, passed: false),
                  const SizedBox(height: 16),
                ],
                _label(context, strings.sourceName),
                const SizedBox(height: 6),
                TextField(
                  controller: _name,
                  textInputAction: TextInputAction.next,
                  decoration: InputDecoration(
                    hintText: strings.serverNameHint,
                    prefixIcon: const Icon(Icons.label_outline_rounded),
                  ),
                ),
                const SizedBox(height: 22),
                _label(context, strings.serverAddress),
                const SizedBox(height: 6),
                TextField(
                  controller: _address,
                  keyboardType: TextInputType.url,
                  textInputAction: TextInputAction.next,
                  autocorrect: false,
                  enableSuggestions: false,
                  // Addresses are LTR even when the interface is Arabic.
                  textDirection: TextDirection.ltr,
                  textAlign: TextAlign.start,
                  decoration: const InputDecoration(
                    hintText: 'tv.example.com  ·  10.0.0.5:9981',
                    prefixIcon: Icon(Icons.dns_rounded),
                  ),
                ),
                _help(context, strings.serverAddressHelp),
                const SizedBox(height: 22),
                _label(context, strings.username),
                const SizedBox(height: 6),
                TextField(
                  controller: _username,
                  textInputAction: TextInputAction.next,
                  autocorrect: false,
                  enableSuggestions: false,
                  textDirection: TextDirection.ltr,
                  textAlign: TextAlign.start,
                  decoration: const InputDecoration(
                    prefixIcon: Icon(Icons.person_outline_rounded),
                  ),
                ),
                const SizedBox(height: 14),
                _label(context, strings.password),
                const SizedBox(height: 6),
                TextField(
                  controller: _password,
                  obscureText: !_showPassword,
                  textInputAction: TextInputAction.next,
                  autocorrect: false,
                  enableSuggestions: false,
                  textDirection: TextDirection.ltr,
                  textAlign: TextAlign.start,
                  decoration: InputDecoration(
                    prefixIcon: const Icon(Icons.key_rounded),
                    suffixIcon: IconButton(
                      tooltip: _showPassword
                          ? strings.hidePassword
                          : strings.showPassword,
                      icon: Icon(
                        _showPassword
                            ? Icons.visibility_off_outlined
                            : Icons.visibility_outlined,
                      ),
                      onPressed: () =>
                          setState(() => _showPassword = !_showPassword),
                    ),
                  ),
                ),
                _help(context, strings.usernameHelp),
                const SizedBox(height: 22),
                _label(context, strings.streamProfile),
                const SizedBox(height: 6),
                TextField(
                  controller: _profile,
                  textInputAction: TextInputAction.done,
                  autocorrect: false,
                  enableSuggestions: false,
                  textDirection: TextDirection.ltr,
                  textAlign: TextAlign.start,
                  decoration: const InputDecoration(
                    hintText: 'pass',
                    prefixIcon: Icon(Icons.tune_rounded),
                  ),
                ),
                if (_profiles.isNotEmpty) ...<Widget>[
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 4,
                    children: <Widget>[
                      for (final name in _profiles)
                        ChoiceChip(
                          label: Text(name),
                          selected: _profile.text.trim() == name,
                          onSelected: (_) => setState(() => _profile.text = name),
                        ),
                    ],
                  ),
                ],
                _help(context, strings.streamProfileHelp),
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
