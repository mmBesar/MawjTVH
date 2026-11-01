/// Plain data returned by the Tvheadend API that has no counterpart in the
/// shared channel/programme models.
library;

enum RecordingKind { upcoming, finished, failed }

/// One DVR entry (`dvr/entry/grid_*`).
class TvhRecording {
  const TvhRecording({
    required this.uuid,
    required this.channelName,
    required this.title,
    required this.start,
    required this.stop,
    this.channelUuid = '',
    this.subtitle = '',
    this.description = '',
    this.status = '',
    this.schedStatus = '',
    this.fileSize = 0,
    this.errors = 0,
    this.enabled = true,
    this.imageSource,
  });

  final String uuid;
  final String channelUuid;
  final String channelName;
  final String title;
  final String subtitle;
  final String description;
  final DateTime start;
  final DateTime stop;

  /// Human text from the server, e.g. "Running", "Completed OK".
  final String status;

  /// `scheduled`, `recording`, `completed`, `missed`, `completedError`...
  final String schedStatus;
  final int fileSize;
  final int errors;
  final bool enabled;
  final String? imageSource;

  bool get isRecording => schedStatus == 'recording';
  bool get isScheduled => schedStatus == 'scheduled';
  bool get isFinished =>
      schedStatus == 'completed' || schedStatus == 'completedError';
  bool get hasFile => fileSize > 0;
  Duration get length => stop.difference(start);
}

/// One tuner input from `status/inputs` (administrators only).
class TvhInputStatus {
  const TvhInputStatus({
    required this.input,
    this.stream = '',
    this.subs = 0,
    this.signal,
    this.signalScale = 0,
    this.snr,
    this.snrScale = 0,
    this.ber,
    this.unc,
    this.bps,
  });

  final String input;
  final String stream;
  final int subs;
  final int? signal;
  final int signalScale;
  final int? snr;
  final int snrScale;
  final int? ber;
  final int? unc;
  final int? bps;
}

/// One entry of `status/subscriptions` (administrators only).
class TvhSubscription {
  const TvhSubscription({
    required this.title,
    required this.channel,
    required this.service,
    required this.state,
    this.errors = 0,
    this.user = '',
    this.client = '',
    this.profile = '',
    this.bytesIn = 0,
    this.bytesOut = 0,
  });

  final String title;
  final String channel;
  final String service;
  final String state;
  final int errors;
  final String user;
  final String client;
  final String profile;
  final int bytesIn;
  final int bytesOut;
}

/// One entry of `status/connections` (administrators only).
class TvhConnection {
  const TvhConnection({
    required this.user,
    required this.peer,
    required this.kind,
    required this.started,
  });

  final String user;
  final String peer;
  final String kind;
  final DateTime started;
}

class TvhServerInfo {
  const TvhServerInfo({
    this.name = 'Tvheadend',
    this.version = '',
    this.apiVersion = 0,
  });

  final String name;
  final String version;
  final int apiVersion;
}

/// Permissions are decided by the server; the client only discovers them.
class TvhPermissions {
  const TvhPermissions({required this.admin, this.canRecord = false});

  /// Allowed to use `config/load`, the administrator probe.
  final bool admin;

  /// Allowed to read the DVR. Learned from the first DVR call.
  final bool canRecord;

  TvhPermissions copyWith({bool? admin, bool? canRecord}) => TvhPermissions(
        admin: admin ?? this.admin,
        canRecord: canRecord ?? this.canRecord,
      );
}

/// Signal quality for the stream being watched.
class TvhSignal {
  const TvhSignal({
    this.status = '',
    this.snrPercent,
    this.signalPercent,
    this.snrDb,
    this.signalDb,
    this.ber,
    this.unc,
  });

  final String status;
  final double? snrPercent;
  final double? signalPercent;
  final double? snrDb;
  final double? signalDb;
  final int? ber;
  final int? unc;

  bool get hasValues =>
      snrPercent != null ||
      signalPercent != null ||
      snrDb != null ||
      signalDb != null;

  /// Relative scale: 65535 is 100 %.
  static double relativeToPercent(int value) =>
      (value.clamp(0, 65535) / 65535.0 * 100.0).clamp(0.0, 100.0).toDouble();

  /// `status/inputs`: scale 1 is relative (65535 = 100 %), 2 is absolute
  /// (1000 = 1 dB), 0 means the tuner does not report it.
  factory TvhSignal.fromInput(TvhInputStatus input) {
    double? percent(int? value, int scale) =>
        value != null && scale == 1 ? relativeToPercent(value) : null;
    double? decibel(int? value, int scale) =>
        value != null && scale == 2 ? value / 1000.0 : null;
    return TvhSignal(
      status: input.stream,
      snrPercent: percent(input.snr, input.snrScale),
      signalPercent: percent(input.signal, input.signalScale),
      snrDb: decibel(input.snr, input.snrScale),
      signalDb: decibel(input.signal, input.signalScale),
      ber: input.ber,
      unc: input.unc,
    );
  }

  /// Picks the tuner that serves [subscription] among [inputs]: the only one
  /// with subscribers, else the one whose name starts the service's name.
  static TvhInputStatus? pickInput(
    List<TvhInputStatus> inputs,
    TvhSubscription? subscription,
  ) {
    final busy = inputs.where((input) => input.subs > 0).toList();
    if (busy.isEmpty) {
      return null;
    }
    if (busy.length == 1 || subscription == null) {
      return busy.first;
    }
    for (final input in busy) {
      if (input.input.isNotEmpty && subscription.service.startsWith(input.input)) {
        return input;
      }
    }
    for (final input in busy) {
      if (input.input.isNotEmpty && subscription.service.contains(input.input)) {
        return input;
      }
    }
    return busy.first;
  }
}
