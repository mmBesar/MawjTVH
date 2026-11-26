import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:media_kit/media_kit.dart';

import '../core/media_session.dart';
import '../core/network_image.dart';
import 'models.dart';

/// Plays radio stations as audio: one player for the whole app, with no video
/// surface, that outlives every page. It keeps going with the screen off or
/// another app in front (through the Android media session), reconnects when
/// the stream drops, and is controlled from the notification, the lock screen
/// and headset buttons.
class RadioPlayer extends ChangeNotifier {
  RadioPlayer({
    required Future<Channel> Function(Channel channel) prepare,
    required void Function(Channel channel) release,
    required void Function(Channel channel) watched,
    required List<Channel> Function() stations,
    required bool Function() allowInsecure,
    required String? Function(Channel channel) nowOn,
  })  : _prepare = prepare,
        _release = release,
        _watched = watched,
        _stations = stations,
        _allowInsecure = allowInsecure,
        _nowOn = nowOn;

  final Future<Channel> Function(Channel channel) _prepare;
  final void Function(Channel channel) _release;
  final void Function(Channel channel) _watched;
  final List<Channel> Function() _stations;
  final bool Function() _allowInsecure;
  final String? Function(Channel channel) _nowOn;

  Player? _player;
  final List<StreamSubscription<Object?>> _subscriptions =
      <StreamSubscription<Object?>>[];
  StreamSubscription<MediaAction>? _actionSubscription;

  Channel? _channel;
  bool _wanted = false;
  bool _buffering = false;
  String? _error;
  int _attempts = 0;
  int _generation = 0;
  Timer? _retry;
  Timer? _sleepTimer;
  DateTime? _sleepAt;
  double _volume = 100;
  String _lastSubtitle = '';
  bool _disposed = false;

  /// The station that is loaded (playing or paused); null when stopped.
  Channel? get channel => _channel;

  /// True while a station is loaded, which is when the mini player shows.
  bool get active => _channel != null;

  /// True while audio is meant to be playing.
  bool get playing => _wanted;

  /// True while connecting or refilling the buffer.
  bool get buffering => _wanted && _buffering;

  /// Why the station could not be played, once every retry has failed.
  String? get error => _error;

  /// Volume from 0 to 100.
  double get volume => _volume;

  /// When the sleep timer stops the radio, or null when it is off.
  DateTime? get sleepAt => _sleepAt;

  bool get canSkip => _stations().length > 1;

  /// Starts [channel], replacing whatever was playing.
  Future<void> play(Channel channel) async {
    final previous = _channel;
    if (previous != null && previous.id != channel.id) {
      _release(previous);
    }
    _channel = channel;
    _wanted = true;
    _error = null;
    _attempts = 0;
    _buffering = true;
    _watched(channel);
    _changed();
    await _open();
  }

  /// Pauses. A live station has nothing to come back to, so this lets go of
  /// the stream (and the tuner); [resume] tunes in again at the live point.
  Future<void> pause() async {
    final channel = _channel;
    if (channel == null || !_wanted) {
      return;
    }
    _wanted = false;
    _buffering = false;
    _generation++;
    _retry?.cancel();
    await _player?.stop();
    _release(channel);
    _changed();
  }

  Future<void> resume() async {
    final channel = _channel;
    if (channel == null || _wanted) {
      return;
    }
    await play(channel);
  }

  Future<void> toggle() => _wanted ? pause() : resume();

  /// Stops and forgets the station: the mini player and notification go.
  Future<void> stop() async {
    final channel = _channel;
    if (channel == null) {
      return;
    }
    _wanted = false;
    _buffering = false;
    _error = null;
    _generation++;
    _retry?.cancel();
    _sleepTimer?.cancel();
    _sleepAt = null;
    _channel = null;
    await _player?.stop();
    _release(channel);
    _lastSubtitle = '';
    unawaited(MediaSessionService.stop());
    notifyListeners();
  }

  Future<void> next() => _step(1);

  Future<void> previous() => _step(-1);

  Future<void> _step(int delta) async {
    final list = _stations();
    final channel = _channel;
    if (list.length < 2 || channel == null) {
      return;
    }
    final at = list.indexWhere((entry) => entry.id == channel.id);
    final from = at < 0 ? 0 : at;
    final to = ((from + delta) % list.length + list.length) % list.length;
    await play(list[to]);
  }

  Future<void> setVolume(double value) async {
    _volume = value.clamp(0, 100).toDouble();
    notifyListeners();
    await _player?.setVolume(_volume);
  }

  /// Stops the radio after [after]; null switches the timer off.
  void sleepIn(Duration? after) {
    _sleepTimer?.cancel();
    if (after == null) {
      _sleepAt = null;
    } else {
      _sleepAt = DateTime.now().add(after);
      _sleepTimer = Timer(after, () => unawaited(stop()));
    }
    notifyListeners();
  }

  /// Called when the guide moves on, so the notification names the programme
  /// that is on now.
  void refreshNowOn() {
    if (_channel != null) {
      _pushSession();
    }
  }

  // ---- Playback ------------------------------------------------------------

  Future<Player> _ensurePlayer() async {
    final existing = _player;
    if (existing != null) {
      return existing;
    }
    final player = Player(
      configuration: const PlayerConfiguration(
        title: 'MawjTVH',
        logLevel: MPVLogLevel.warn,
        bufferSize: 8 * 1024 * 1024,
      ),
    );
    _player = player;
    final platform = player.platform;
    if (platform is NativePlayer) {
      // Audio only: never decode a picture, even if the station carries one.
      await platform.setProperty('vid', 'no');
      await platform.setProperty('audio-display', 'no');
      await platform.setProperty('network-timeout', '30');
      await platform.setProperty('cache-secs', '20');
    }
    await player.setVolume(_volume);
    _subscriptions
      ..add(player.stream.playing.listen((playing) {
        if (playing && _wanted) {
          _attempts = 0;
          if (_error != null) {
            _error = null;
          }
          notifyListeners();
        }
      }))
      ..add(player.stream.buffering.listen((buffering) {
        if (_buffering != buffering) {
          _buffering = buffering;
          notifyListeners();
        }
      }))
      ..add(player.stream.error.listen((message) {
        if (_wanted && message.trim().isNotEmpty) {
          _scheduleRetry(message.trim());
        }
      }))
      ..add(player.stream.completed.listen((done) {
        // A live stream that ends has been cut by the server or the network.
        if (done && _wanted) {
          _scheduleRetry('The stream ended');
        }
      }));
    _actionSubscription ??= MediaSessionService.actions.listen(_onAction);
    return player;
  }

  void _onAction(MediaAction action) {
    switch (action) {
      case MediaAction.play:
        unawaited(resume());
      case MediaAction.pause:
        unawaited(pause());
      case MediaAction.toggle:
        unawaited(toggle());
      case MediaAction.stop:
        unawaited(stop());
      case MediaAction.next:
        unawaited(next());
      case MediaAction.previous:
        unawaited(previous());
    }
  }

  Future<void> _open() async {
    final channel = _channel;
    if (channel == null || !_wanted) {
      return;
    }
    final generation = ++_generation;
    try {
      final player = await _ensurePlayer();
      final platform = player.platform;
      if (platform is NativePlayer) {
        await platform.setProperty(
          'tls-verify',
          _allowInsecure() ? 'no' : 'yes',
        );
      }
      // Reconnects first when the server session dropped, so the address is
      // always one that answers.
      final ready = await _prepare(channel);
      if (generation != _generation || !_wanted) {
        return;
      }
      await player.open(
        Media(
          ready.url,
          httpHeaders: const <String, String>{'User-Agent': kMawjUserAgent},
        ),
      );
    } catch (error) {
      if (generation == _generation && _wanted) {
        _scheduleRetry('$error');
      }
    }
  }

  /// Tries again after a growing pause (2, 4, 8 ... up to 30 seconds), and
  /// gives up with the reason after eight tries.
  void _scheduleRetry(String why) {
    _retry?.cancel();
    if (_attempts >= 8) {
      _wanted = false;
      _buffering = false;
      _error = why;
      final channel = _channel;
      if (channel != null) {
        _release(channel);
      }
      _changed();
      return;
    }
    final seconds = math.min(30, 2 << _attempts);
    _attempts++;
    _buffering = true;
    _changed();
    _retry = Timer(Duration(seconds: seconds), () => unawaited(_open()));
  }

  void _changed() {
    if (_disposed) {
      return;
    }
    notifyListeners();
    _pushSession();
  }

  void _pushSession() {
    final channel = _channel;
    if (channel == null || _disposed) {
      return;
    }
    final subtitle = _nowOn(channel) ?? '';
    _lastSubtitle = subtitle;
    unawaited(
      MediaSessionService.update(
        title: channel.name,
        subtitle: subtitle,
        playing: _wanted,
        canSkip: canSkip,
      ),
    );
  }

  /// The programme text last sent to the notification.
  @visibleForTesting
  String get lastSubtitle => _lastSubtitle;

  @override
  void dispose() {
    _disposed = true;
    _retry?.cancel();
    _sleepTimer?.cancel();
    for (final subscription in _subscriptions) {
      unawaited(subscription.cancel());
    }
    unawaited(_actionSubscription?.cancel());
    unawaited(_player?.dispose());
    unawaited(MediaSessionService.stop());
    super.dispose();
  }
}
