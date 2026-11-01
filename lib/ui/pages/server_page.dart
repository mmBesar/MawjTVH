import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/bidi.dart';
import '../../core/theme.dart';
import '../../data/app_state.dart';
import '../../data/tvh_models.dart';
import '../../l10n/strings.dart';
import '../../l10n/tvh_strings.dart';
import '../widgets/empty_state.dart';
import '../widgets/error_banner.dart';

/// Live status of the server: tuners with their signal, running streams and
/// connected clients. Administrators only; the server enforces that too.
class ServerPage extends StatefulWidget {
  const ServerPage({super.key});

  @override
  State<ServerPage> createState() => _ServerPageState();
}

class _ServerPageState extends State<ServerPage> {
  Timer? _timer;
  List<TvhInputStatus> _inputs = const <TvhInputStatus>[];
  List<TvhSubscription> _subscriptions = const <TvhSubscription>[];
  List<TvhConnection> _connections = const <TvhConnection>[];
  String? _error;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    unawaited(_poll());
    _timer = Timer.periodic(const Duration(seconds: 5), (_) => unawaited(_poll()));
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _poll() async {
    if (_busy || !mounted) {
      return;
    }
    _busy = true;
    final state = context.read<AppState>();
    try {
      final result = await state.withClient((client) async {
        final inputs = await client.inputs();
        final subscriptions = await client.subscriptions();
        final connections = await client.connections();
        return (inputs, subscriptions, connections);
      });
      if (mounted) {
        setState(() {
          _inputs = result.$1;
          _subscriptions = result.$2;
          _connections = result.$3;
          _error = null;
        });
      }
    } catch (error) {
      if (mounted) {
        setState(() => _error = error.toString());
      }
    } finally {
      _busy = false;
    }
  }

  Widget _title(BuildContext context, String text) {
    final colors = context.mawjColors;
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 18, 4, 8),
      child: Text(
        text,
        style: Theme.of(context).textTheme.titleSmall?.copyWith(
              color: colors.subtext0,
              fontWeight: FontWeight.w700,
            ),
      ),
    );
  }

  Widget _card(BuildContext context, List<Widget> lines) {
    final colors = context.mawjColors;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: colors.surface0,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: colors.surface1),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: lines,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final strings = context.strings;
    final colors = context.mawjColors;
    final theme = Theme.of(context);

    Widget body;
    if (!state.isAdmin) {
      body = EmptyState(
        icon: Icons.lock_outline_rounded,
        title: strings.server,
        body: strings.adminOnly,
      );
    } else {
      final small = theme.textTheme.bodySmall?.copyWith(color: colors.subtext1);
      body = ListView(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 32),
        children: <Widget>[
          if (_error != null)
            ErrorBanner(
              message: _error!,
              retryLabel: strings.retry,
              onRetry: () => unawaited(_poll()),
            ),
          _title(context, strings.tuners),
          if (_inputs.isEmpty)
            _card(context, <Widget>[Text(strings.nothingActive, style: small)])
          else
            for (final input in _inputs) ...<Widget>[
              _card(context, <Widget>[
                BidiText(
                  input.input,
                  style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 4),
                if (input.stream.isNotEmpty) BidiText(input.stream, style: small),
                const SizedBox(height: 6),
                Text(_signalLine(strings, input), style: small),
              ]),
              const SizedBox(height: 10),
            ],
          _title(context, strings.activeStreams),
          if (_subscriptions.isEmpty)
            _card(context, <Widget>[Text(strings.nothingActive, style: small)])
          else
            for (final sub in _subscriptions) ...<Widget>[
              _card(context, <Widget>[
                BidiText(
                  sub.channel.isEmpty ? sub.title : sub.channel,
                  style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 4),
                BidiText(
                  <String>[
                    if (sub.user.isNotEmpty) sub.user,
                    if (sub.client.isNotEmpty) sub.client,
                    if (sub.profile.isNotEmpty) sub.profile,
                    sub.state,
                    if (sub.errors > 0) '${strings.recordingProblems}: ${sub.errors}',
                  ].join(' · '),
                  style: small,
                ),
              ]),
              const SizedBox(height: 10),
            ],
          _title(context, strings.connectionsLabel),
          if (_connections.isEmpty)
            _card(context, <Widget>[Text(strings.nothingActive, style: small)])
          else
            _card(context, <Widget>[
              for (final connection in _connections)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 3),
                  child: BidiText(
                    '${connection.user.isEmpty ? '—' : connection.user} · '
                    '${connection.peer} · ${connection.kind}',
                    style: small,
                  ),
                ),
            ]),
        ],
      );
    }

    return Scaffold(
      appBar: AppBar(title: Text(strings.serverStatus)),
      body: body,
    );
  }

  String _signalLine(AppStrings strings, TvhInputStatus input) {
    final signal = TvhSignal.fromInput(input);
    final parts = <String>[
      if (signal.signalPercent != null)
        '${strings.signalStrength} ${signal.signalPercent!.round()}%',
      if (signal.signalDb != null)
        '${strings.signalStrength} ${signal.signalDb!.toStringAsFixed(1)} dB',
      if (signal.snrPercent != null)
        '${strings.signalSnr} ${signal.snrPercent!.round()}%',
      if (signal.snrDb != null)
        '${strings.signalSnr} ${signal.snrDb!.toStringAsFixed(1)} dB',
      if (input.ber != null) 'BER ${input.ber}',
      if (input.unc != null) 'UNC ${input.unc}',
      '${input.subs} ${strings.activeStreams.toLowerCase()}',
    ];
    return parts.join(' · ');
  }
}
