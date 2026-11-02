import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

import '../core/network_image.dart';

/// What the system's mpv can do, found by asking it.
@immutable
class MpvCapabilities {
  const MpvCapabilities({
    required this.path,
    required this.version,
    required this.hwdecs,
    required this.bundled,
    required this.supportsWaylandAppId,
  });

  final String path;
  final String version;

  /// Every value `mpv --hwdec=help` lists, in mpv's own order.
  final List<String> hwdecs;

  /// True when this is the mpv shipped inside the app bundle.
  final bool bundled;
  final bool supportsWaylandAppId;

  /// The hardware decoders worth offering by name (not the generic ones).
  List<String> get specificHwdecs => hwdecs
      .where(
        (value) =>
            value != 'no' &&
            value != 'auto' &&
            value != 'auto-safe' &&
            value != 'auto-copy' &&
            value != 'auto-copy-safe',
      )
      .toList(growable: false);
}

/// Finds, probes and launches the mpv binary that plays channels on desktop.
///
/// mpv cannot be embedded in another window on Wayland (`--wid` is X11-only)
/// and the render API path freezes on some Mesa/Wayland setups. A separate
/// native mpv window avoids both: it gets GPU decoding, real compositor
/// fullscreen, and mpv's own on-screen controls.
class MpvRuntime {
  MpvRuntime._();

  static Future<MpvCapabilities?>? _probe;
  static String _customPath = '';

  /// Probes once per run; later calls reuse the answer.
  static Future<MpvCapabilities?> capabilities() {
    return _probe ??= _probeUncached();
  }

  /// Sets the path the user chose in settings and probes again.
  static void useCustomPath(String path) {
    final trimmed = path.trim();
    if (trimmed != _customPath) {
      _customPath = trimmed;
      _probe = null;
    }
  }

  /// Forgets the cached answer, e.g. after the user installs mpv.
  static void reset() => _probe = null;

  static String? _bundledMpv() {
    try {
      final dir = File(Platform.resolvedExecutable).parent.path;
      final file = File('$dir/bin/mpv');
      return file.existsSync() ? file.path : null;
    } catch (_) {
      return null;
    }
  }

  static String? _bundleLibDir() {
    try {
      final dir = Directory('${File(Platform.resolvedExecutable).parent.path}/lib');
      return dir.existsSync() ? dir.path : null;
    } catch (_) {
      return null;
    }
  }

  static String? _fromPath() {
    final separator = Platform.isWindows ? ';' : ':';
    final paths = (Platform.environment['PATH'] ?? '').split(separator);
    for (final dir in paths) {
      if (dir.isEmpty) {
        continue;
      }
      final file = File('$dir/mpv');
      try {
        if (file.existsSync()) {
          return file.path;
        }
      } catch (_) {
        // Unreadable PATH entry.
      }
    }
    return null;
  }

  /// The environment for a child mpv. Inside an AppImage (or appimage-run on
  /// NixOS) variables such as LD_LIBRARY_PATH point at the app's own bundled
  /// libraries; a system mpv that inherits them loads the wrong libmpv/ffmpeg
  /// and dies. Entries that point into the app's mount are removed.
  static Map<String, String> _environmentFor(String path) {
    final env = Map<String, String>.from(Platform.environment);
    final appDir = (() {
      try {
        return File(Platform.resolvedExecutable).parent.path;
      } catch (_) {
        return '';
      }
    })();
    final appImageDir = env['APPDIR'] ?? '';
    bool ours(String value) =>
        (appDir.isNotEmpty && value.startsWith(appDir)) ||
        (appImageDir.isNotEmpty && value.startsWith(appImageDir)) ||
        value.contains('/.mount_');

    final bundled = path.startsWith(appDir) && appDir.isNotEmpty;
    for (final key in env.keys.toList()) {
      final value = env[key] ?? '';
      if (key == 'LD_LIBRARY_PATH' || key == 'LD_PRELOAD') {
        if (bundled) {
          continue;
        }
        final kept = value.split(':').where((part) => part.isNotEmpty && !ours(part));
        if (kept.isEmpty) {
          env.remove(key);
        } else {
          env[key] = kept.join(':');
        }
      } else if (const <String>{
            'GDK_PIXBUF_MODULE_FILE',
            'GIO_EXTRA_MODULES',
            'GSETTINGS_SCHEMA_DIR',
            'GTK_PATH',
            'GTK_EXE_PREFIX',
            'GTK_DATA_PREFIX',
            'PERL5LIB',
            'PYTHONPATH',
            'QT_PLUGIN_PATH',
          }.contains(key) &&
          ours(value)) {
        env.remove(key);
      }
    }
    if (bundled) {
      final lib = _bundleLibDir();
      if (lib != null) {
        final existing = env['LD_LIBRARY_PATH'];
        env['LD_LIBRARY_PATH'] =
            existing == null || existing.isEmpty ? lib : '$lib:$existing';
      }
    }
    return env;
  }

  /// Where mpv usually lives when PATH is missing or trimmed, as it is under
  /// appimage-run and some launchers.
  static List<String> _wellKnownLocations() {
    final home = Platform.environment['HOME'] ?? '';
    final user = Platform.environment['USER'] ?? '';
    return <String>[
      '/run/current-system/sw/bin/mpv',
      if (user.isNotEmpty) '/etc/profiles/per-user/$user/bin/mpv',
      if (home.isNotEmpty) '$home/.nix-profile/bin/mpv',
      if (home.isNotEmpty) '$home/.local/bin/mpv',
      '/usr/local/bin/mpv',
      '/usr/bin/mpv',
      '/bin/mpv',
      '/snap/bin/mpv',
    ];
  }

  static String? _firstExisting(Iterable<String> paths) {
    for (final candidate in paths) {
      try {
        if (File(candidate).existsSync()) {
          return candidate;
        }
      } catch (_) {
        // Unreadable location.
      }
    }
    return null;
  }

  /// Why the last probe found nothing, for the settings page.
  static String? lastProblem;

  static Future<MpvCapabilities?> _probeUncached() async {
    final override = Platform.environment['MAWJTVH_MPV'];
    final candidates = <(String, bool)>[
      if (_customPath.isNotEmpty) (_customPath, false),
      if (override != null && override.isNotEmpty) (override, false),
      ?(() {
        final bundled = _bundledMpv();
        return bundled == null ? null : (bundled, true);
      })(),
      ?(() {
        final system = _fromPath();
        return system == null ? null : (system, false);
      })(),
      ?(() {
        final known = _firstExisting(_wellKnownLocations());
        return known == null ? null : (known, false);
      })(),
    ];
    lastProblem = null;

    for (final (path, bundled) in candidates) {
      try {
        final env = _environmentFor(path);
        final version = await Process.run(
          path,
          const <String>['--version'],
          environment: env,
          includeParentEnvironment: false,
        ).timeout(const Duration(seconds: 8));
        if (version.exitCode != 0) {
          lastProblem = '$path: ${'${version.stderr}'.trim()}';
          continue;
        }
        final help = await Process.run(
          path,
          const <String>['--no-config', '--hwdec=help'],
          environment: env,
          includeParentEnvironment: false,
        ).timeout(const Duration(seconds: 8));
        final options = await Process.run(
          path,
          const <String>['--no-config', '--list-options'],
          environment: env,
          includeParentEnvironment: false,
        ).timeout(const Duration(seconds: 8));
        final firstLine = '${version.stdout}'.split('\n').first.trim();
        return MpvCapabilities(
          path: path,
          version: firstLine,
          hwdecs: parseHwdecHelp('${help.stdout}\n${help.stderr}'),
          bundled: bundled,
          supportsWaylandAppId: '${options.stdout}'.contains('--wayland-app-id'),
        );
      } catch (error) {
        lastProblem = '$path: $error';
        debugPrint('mpv probe failed for $path: $error');
      }
    }
    return null;
  }

  /// Parses the output of `mpv --hwdec=help` into the listed values.
  @visibleForTesting
  static List<String> parseHwdecHelp(String output) {
    final values = <String>[];
    final pattern = RegExp(r'^\s{2,}([a-z0-9][a-z0-9-]*)(\s.*)?$');
    for (final line in const LineSplitter().convert(output)) {
      final match = pattern.firstMatch(line);
      if (match == null) {
        continue;
      }
      final value = match.group(1)!;
      if (!values.contains(value)) {
        values.add(value);
      }
    }
    return values;
  }

  /// Builds the command line for one playback session.
  @visibleForTesting
  static List<String> buildArguments({
    required MpvCapabilities capabilities,
    required String title,
    required String ipcPath,
    required String hwdec,
    required String videoOutput,
    required bool allowInsecure,
    required bool useUserConfig,
    required bool fullscreen,
  }) {
    // The person's own mpv is used as it is: their mpv.conf, scripts and
    // defaults apply. Only what the app has to control is passed, and the
    // decoder/output only when they were changed away from "automatic".
    final chosenHwdec =
        hwdec != 'auto-safe' &&
                (capabilities.hwdecs.isEmpty || capabilities.hwdecs.contains(hwdec))
            ? hwdec
            : null;
    return <String>[
      if (!useUserConfig) '--no-config',
      '--force-window=yes',
      '--title=$title',
      '--user-agent=$kMawjUserAgent',
      if (chosenHwdec != null) '--hwdec=$chosenHwdec',
      if (videoOutput != 'auto') '--vo=$videoOutput',
      if (allowInsecure) '--tls-verify=no',
      '--ytdl=no',
      '--input-ipc-server=$ipcPath',
      '--input-terminal=no',
      '--term-status-msg=',
      '--msg-level=all=warn',
      if (capabilities.supportsWaylandAppId)
        '--wayland-app-id=com.mmbesar.mawjtvh.player',
      if (fullscreen) '--fs',
    ];
  }

  /// Starts mpv on [url] and connects to its control socket.
  static Future<MpvSession> start({
    required MpvCapabilities capabilities,
    required String url,
    required String title,
    required String hwdec,
    required String videoOutput,
    required bool allowInsecure,
    required bool useUserConfig,
    required bool fullscreen,
  }) async {
    final runtimeDir = Platform.environment['XDG_RUNTIME_DIR'];
    final base = runtimeDir != null && Directory(runtimeDir).existsSync()
        ? runtimeDir
        : Directory.systemTemp.path;
    final ipcPath = '$base/mawjtvh-mpv-$pid.sock';
    try {
      final stale = File(ipcPath);
      if (stale.existsSync()) {
        stale.deleteSync();
      }
    } catch (_) {
      // A stale socket that cannot be removed is reported by mpv itself.
    }

    final arguments = buildArguments(
      capabilities: capabilities,
      title: title,
      ipcPath: ipcPath,
      hwdec: hwdec,
      videoOutput: videoOutput,
      allowInsecure: allowInsecure,
      useUserConfig: useUserConfig,
      fullscreen: fullscreen,
    );
    final process = await Process.start(
      capabilities.path,
      <String>[...arguments, '--', url],
      environment: _environmentFor(capabilities.path),
      includeParentEnvironment: false,
    );
    final session = MpvSession._(process, ipcPath, arguments);
    session._attach();
    unawaited(session._connect());
    return session;
  }
}

/// One running mpv process and its JSON IPC connection.
class MpvSession {
  MpvSession._(this._process, this.ipcPath, this.arguments);

  final Process _process;
  final String ipcPath;
  final List<String> arguments;

  final List<String> log = <String>[];
  final Map<int, Completer<Object?>> _pending = <int, Completer<Object?>>{};
  Socket? _socket;
  int _nextId = 1;
  bool _closed = false;

  /// Completes with mpv's exit code when the window closes or mpv fails.
  Future<int> get exitCode => _process.exitCode;

  void _attach() {
    void capture(Stream<List<int>> stream) {
      stream
          .transform(utf8.decoder)
          .transform(const LineSplitter())
          .listen((line) {
        if (line.trim().isEmpty) {
          return;
        }
        log.add(line.trim());
        if (log.length > 60) {
          log.removeAt(0);
        }
      }, onError: (Object _) {});
    }

    capture(_process.stdout);
    capture(_process.stderr);
    unawaited(_process.exitCode.then((_) => _cleanup()));
  }

  Future<void> _connect() async {
    final address = InternetAddress(ipcPath, type: InternetAddressType.unix);
    for (var attempt = 0; attempt < 50 && !_closed; attempt++) {
      try {
        final socket = await Socket.connect(address, 0);
        _socket = socket;
        socket
            .cast<List<int>>()
            .transform(utf8.decoder)
            .transform(const LineSplitter())
            .listen(_onLine, onError: (Object _) {}, onDone: () => _socket = null);
        return;
      } catch (_) {
        await Future<void>.delayed(const Duration(milliseconds: 100));
      }
    }
  }

  void _onLine(String line) {
    try {
      final decoded = jsonDecode(line);
      if (decoded is Map<String, dynamic>) {
        final id = decoded['request_id'];
        if (id is int) {
          final completer = _pending.remove(id);
          if (completer != null && !completer.isCompleted) {
            completer.complete(
              decoded['error'] == 'success' ? decoded['data'] : null,
            );
          }
        }
      }
    } catch (_) {
      // Events and anything else mpv prints are not needed.
    }
  }

  /// Sends one command and returns mpv's answer, or null when it cannot be
  /// reached in time.
  Future<Object?> command(List<Object> arguments) async {
    for (var wait = 0; _socket == null && wait < 30 && !_closed; wait++) {
      await Future<void>.delayed(const Duration(milliseconds: 100));
    }
    final socket = _socket;
    if (socket == null) {
      return null;
    }
    final id = _nextId++;
    final completer = Completer<Object?>();
    _pending[id] = completer;
    try {
      socket.write('${jsonEncode(<String, Object>{
            'command': arguments,
            'request_id': id,
          })}\n');
      return await completer.future.timeout(const Duration(seconds: 3));
    } catch (_) {
      _pending.remove(id);
      return null;
    }
  }

  Future<Object?> property(String name) {
    return command(<Object>['get_property', name]);
  }

  /// Switches to another stream in the same window.
  Future<void> load(String url, String title) async {
    await command(<Object>['set_property', 'title', title]);
    await command(<Object>['loadfile', url, 'replace']);
  }

  Future<void> togglePause() => command(const <Object>['cycle', 'pause']);

  /// Asks mpv to quit, then makes sure it is gone.
  Future<void> stop() async {
    if (_closed) {
      return;
    }
    try {
      _socket?.write('${jsonEncode(<String, Object>{
            'command': <String>['quit'],
          })}\n');
    } catch (_) {
      // The kill below covers an unreachable socket.
    }
    await _process.exitCode
        .timeout(const Duration(milliseconds: 600), onTimeout: () => -1);
    _process.kill(ProcessSignal.sigterm);
    _cleanup();
  }

  /// Immediate, synchronous teardown for app exit.
  void kill() {
    _process.kill(ProcessSignal.sigkill);
    _cleanup();
  }

  void _cleanup() {
    if (_closed) {
      return;
    }
    _closed = true;
    for (final completer in _pending.values) {
      if (!completer.isCompleted) {
        completer.complete(null);
      }
    }
    _pending.clear();
    try {
      _socket?.destroy();
    } catch (_) {
      // Already closed.
    }
    _socket = null;
    try {
      final file = File(ipcPath);
      if (file.existsSync()) {
        file.deleteSync();
      }
    } catch (_) {
      // The runtime directory is cleaned at logout anyway.
    }
  }
}
