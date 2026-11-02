import 'dart:typed_data';

/// One elementary stream of a subscription, as HTSP describes it.
class TsStream {
  const TsStream({
    required this.index,
    required this.type,
    this.meta,
    this.language = '',
  });

  /// HTSP stream index, the key used by `muxpkt`.
  final int index;

  /// `H264`, `HEVC`, `MPEG2VIDEO`, `AAC`, `MPEG2AUDIO`, `AC3`, `EAC3`...
  final String type;

  /// Codec configuration blocks (avcC / hvcC) when the server sent them.
  final Uint8List? meta;
  final String language;
}

/// Rebuilds an MPEG transport stream from HTSP packets, so the player can
/// read a live channel as one ordinary stream.
///
/// Timestamps are 90 kHz (the proxy asks HTSP for that). Continuity counters
/// survive [configure], so the player sees one unbroken stream even when the
/// subscription behind it is restarted.
class TsMuxer {
  static const int _packet = 188;
  static const int _pmtPid = 0x1000;
  static const int _firstPid = 0x100;

  final Map<int, int> _continuity = <int, int>{};
  final Map<int, _Track> _tracks = <int, _Track>{};
  int _pcrPid = _firstPid;
  int _version = -1;
  bool _discontinuity = false;
  int _lastTables = 0;

  bool get isConfigured => _tracks.isNotEmpty;

  /// Starts a fresh program layout (a new subscription). Streams that cannot
  /// be carried (subtitles, unknown codecs) are ignored.
  void configure(List<TsStream> streams) {
    _tracks.clear();
    var pid = _firstPid;
    var videoCount = 0;
    var audioCount = 0;
    for (final stream in streams) {
      final info = _codec(stream.type);
      if (info == null) {
        continue;
      }
      final isVideo = info.video;
      final streamId = isVideo
          ? 0xE0 + (videoCount++ & 0x0f)
          : (info.privateStream ? 0xBD : 0xC0 + (audioCount++ & 0x1f));
      _tracks[stream.index] = _Track(
        pid: pid++,
        streamType: info.streamType,
        streamId: streamId,
        video: isVideo,
        language: stream.language,
        headers: isVideo ? _parameterSets(stream) : null,
        nalLength: isVideo ? _nalLengthSize(stream) : 0,
        privateDescriptor: info.descriptor,
      );
    }
    final firstVideo = _tracks.values.where((t) => t.video).firstOrNull;
    final first = _tracks.values.firstOrNull;
    _pcrPid = (firstVideo ?? first)?.pid ?? _firstPid;
    _version = (_version + 1) & 0x1f;
    _discontinuity = true;
    _lastTables = 0;
  }

  /// PAT and PMT; send them at the start and about twice a second.
  Uint8List tables() {
    final out = BytesBuilder(copy: false)
      ..add(_section(0, _pat()))
      ..add(_section(_pmtPid, _pmt()));
    return out.takeBytes();
  }

  /// True when the program tables are due again (every 400 ms of stream time).
  bool tablesDue(int ts90k) {
    if (_lastTables == 0 || (ts90k - _lastTables).abs() > 36000) {
      _lastTables = ts90k;
      return true;
    }
    return false;
  }

  /// Wraps one HTSP packet into transport stream packets.
  Uint8List? packet({
    required int stream,
    required Uint8List payload,
    required int? pts,
    required int? dts,
    required bool keyframe,
  }) {
    final track = _tracks[stream];
    if (track == null || payload.isEmpty) {
      return null;
    }
    var data = payload;
    if (track.video) {
      data = _prepareVideo(track, payload, keyframe);
    }
    final effectivePts = pts ?? dts;
    if (effectivePts == null) {
      return null;
    }
    final pes = _pes(track, data, effectivePts, dts != null && dts != pts ? dts : null);
    final pcr = track.pid == _pcrPid ? ((dts ?? effectivePts) - 9000) : null;
    return _packetise(track.pid, pes, pcr: pcr, random: keyframe);
  }

  // ---- video helpers -------------------------------------------------------

  Uint8List _prepareVideo(_Track track, Uint8List payload, bool keyframe) {
    var data = payload;
    if (track.nalLength > 0 && !_hasStartCode(data)) {
      data = _lengthPrefixedToAnnexB(data, track.nalLength);
    }
    final headers = track.headers;
    if (keyframe && headers != null && headers.isNotEmpty) {
      final out = BytesBuilder(copy: false)
        ..add(headers)
        ..add(data);
      return out.takeBytes();
    }
    return data;
  }

  static bool _hasStartCode(Uint8List data) {
    if (data.length >= 4 && data[0] == 0 && data[1] == 0) {
      return data[2] == 1 || (data[2] == 0 && data[3] == 1);
    }
    return false;
  }

  static Uint8List _lengthPrefixedToAnnexB(Uint8List data, int lengthSize) {
    final out = BytesBuilder(copy: false);
    var offset = 0;
    while (offset + lengthSize <= data.length) {
      var size = 0;
      for (var i = 0; i < lengthSize; i++) {
        size = (size << 8) | data[offset + i];
      }
      offset += lengthSize;
      if (size <= 0 || offset + size > data.length) {
        break;
      }
      out
        ..add(const <int>[0, 0, 0, 1])
        ..add(Uint8List.sublistView(data, offset, offset + size));
      offset += size;
    }
    return out.takeBytes();
  }

  static int _nalLengthSize(TsStream stream) {
    final meta = stream.meta;
    if (meta == null || meta.isEmpty) {
      return 0;
    }
    if (stream.type == 'H264' && meta.length > 4 && meta[0] == 1) {
      return (meta[4] & 3) + 1;
    }
    if (stream.type == 'HEVC' && meta.length > 21 && meta[0] == 1) {
      return (meta[21] & 3) + 1;
    }
    return 0;
  }

  /// SPS/PPS (and VPS for HEVC) from avcC / hvcC, as Annex B.
  static Uint8List? _parameterSets(TsStream stream) {
    final meta = stream.meta;
    if (meta == null || meta.length < 8) {
      return null;
    }
    final out = BytesBuilder(copy: false);
    void add(Uint8List unit) {
      out
        ..add(const <int>[0, 0, 0, 1])
        ..add(unit);
    }

    try {
      if (stream.type == 'H264' && meta[0] == 1) {
        var offset = 5;
        final spsCount = meta[offset++] & 0x1f;
        for (var i = 0; i < spsCount; i++) {
          final size = (meta[offset] << 8) | meta[offset + 1];
          offset += 2;
          add(Uint8List.sublistView(meta, offset, offset + size));
          offset += size;
        }
        final ppsCount = meta[offset++];
        for (var i = 0; i < ppsCount; i++) {
          final size = (meta[offset] << 8) | meta[offset + 1];
          offset += 2;
          add(Uint8List.sublistView(meta, offset, offset + size));
          offset += size;
        }
      } else if (stream.type == 'HEVC' && meta[0] == 1 && meta.length > 23) {
        var offset = 22;
        final arrays = meta[offset++];
        for (var a = 0; a < arrays; a++) {
          offset += 1; // array type
          final count = (meta[offset] << 8) | meta[offset + 1];
          offset += 2;
          for (var i = 0; i < count; i++) {
            final size = (meta[offset] << 8) | meta[offset + 1];
            offset += 2;
            add(Uint8List.sublistView(meta, offset, offset + size));
            offset += size;
          }
        }
      }
    } on RangeError {
      return null;
    }
    final bytes = out.takeBytes();
    return bytes.isEmpty ? null : bytes;
  }

  // ---- PES and TS packets --------------------------------------------------

  Uint8List _pes(_Track track, Uint8List payload, int pts, int? dts) {
    final hasDts = dts != null;
    final headerLength = hasDts ? 10 : 5;
    final length = 3 + headerLength + payload.length;
    final out = BytesBuilder(copy: false);
    out.add(<int>[
      0,
      0,
      1,
      track.streamId,
      // Video PES may be unbounded (0); audio must carry its length.
      track.video || length > 0xffff ? 0 : (length >> 8) & 0xff,
      track.video || length > 0xffff ? 0 : length & 0xff,
      0x80,
      hasDts ? 0xC0 : 0x80,
      headerLength,
      ..._timestamp(hasDts ? 3 : 2, pts),
      if (hasDts) ..._timestamp(1, dts),
    ]);
    out.add(payload);
    return out.takeBytes();
  }

  static List<int> _timestamp(int marker, int value) {
    final v = value & 0x1ffffffff;
    return <int>[
      (marker << 4) | (((v >> 30) & 0x07) << 1) | 1,
      (v >> 22) & 0xff,
      (((v >> 15) & 0x7f) << 1) | 1,
      (v >> 7) & 0xff,
      ((v & 0x7f) << 1) | 1,
    ];
  }

  Uint8List _packetise(
    int pid,
    Uint8List pes, {
    int? pcr,
    required bool random,
  }) {
    final out = BytesBuilder(copy: false);
    var offset = 0;
    var first = true;
    while (offset < pes.length) {
      final packet = Uint8List(_packet);
      packet[0] = 0x47;
      packet[1] = (first ? 0x40 : 0) | ((pid >> 8) & 0x1f);
      packet[2] = pid & 0xff;

      // Adaptation field content after its length byte: flags, then PCR.
      final af = <int>[];
      var hasAf = false;
      if (first && (pcr != null || random)) {
        final withPcr = pcr != null;
        af.add(
          (_discontinuity && withPcr ? 0x80 : 0) |
              (random ? 0x40 : 0) |
              (withPcr ? 0x10 : 0),
        );
        if (withPcr) {
          final base = pcr & 0x1ffffffff;
          af.addAll(<int>[
            (base >> 25) & 0xff,
            (base >> 17) & 0xff,
            (base >> 9) & 0xff,
            (base >> 1) & 0xff,
            ((base & 1) << 7) | 0x7e,
            0,
          ]);
          _discontinuity = false;
        }
        hasAf = true;
      }

      final remaining = pes.length - offset;
      final capacity = _packet - 4 - (hasAf ? 1 + af.length : 0);
      if (remaining < capacity) {
        // Last packet of the PES: fill the gap with adaptation stuffing.
        final stuffing = capacity - remaining;
        if (!hasAf) {
          hasAf = true;
          if (stuffing >= 2) {
            af
              ..add(0x00)
              ..addAll(List<int>.filled(stuffing - 2, 0xff));
          }
          // stuffing == 1: a zero-length adaptation field is one byte.
        } else {
          af.addAll(List<int>.filled(stuffing, 0xff));
        }
      }

      var headerEnd = 4;
      if (hasAf) {
        packet[3] = 0x30 | _next(pid);
        packet[4] = af.length;
        packet.setRange(5, 5 + af.length, af);
        headerEnd = 5 + af.length;
      } else {
        packet[3] = 0x10 | _next(pid);
      }
      final room = _packet - headerEnd;
      final take = room < remaining ? room : remaining;
      packet.setRange(headerEnd, headerEnd + take, pes, offset);
      offset += take;
      first = false;
      out.add(packet);
    }
    return out.takeBytes();
  }

  int _next(int pid) {
    final value = _continuity[pid] ?? 0;
    _continuity[pid] = (value + 1) & 0x0f;
    return value;
  }

  // ---- tables --------------------------------------------------------------

  Uint8List _pat() => Uint8List.fromList(<int>[
        0x00, 0x01, // transport_stream_id
        0xC1 | (_version << 1), 0x00, 0x00,
        0x00, 0x01, // program 1
        0xE0 | ((_pmtPid >> 8) & 0x1f), _pmtPid & 0xff,
      ]);

  Uint8List _pmt() {
    final body = <int>[
      0x00, 0x01, // program number
      0xC1 | (_version << 1), 0x00, 0x00,
      0xE0 | ((_pcrPid >> 8) & 0x1f), _pcrPid & 0xff,
      0xF0, 0x00, // no program descriptors
    ];
    for (final track in _tracks.values) {
      final descriptors = <int>[
        ...track.privateDescriptor,
        if (track.language.length >= 3 && !track.video)
          ...<int>[0x0A, 4, ...track.language.codeUnits.take(3), 0],
      ];
      body.addAll(<int>[
        track.streamType,
        0xE0 | ((track.pid >> 8) & 0x1f), track.pid & 0xff,
        0xF0 | ((descriptors.length >> 8) & 0x0f), descriptors.length & 0xff,
        ...descriptors,
      ]);
    }
    return Uint8List.fromList(body);
  }

  /// A PSI section split into 188-byte packets (always one for these sizes).
  Uint8List _section(int pid, Uint8List body) {
    final tableId = pid == 0 ? 0x00 : 0x02;
    final length = body.length + 4; // plus CRC
    final section = <int>[
      tableId,
      0xB0 | ((length >> 8) & 0x0f),
      length & 0xff,
      ...body,
    ];
    final crc = _crc32(section);
    section.addAll(<int>[
      (crc >> 24) & 0xff,
      (crc >> 16) & 0xff,
      (crc >> 8) & 0xff,
      crc & 0xff,
    ]);
    final packet = Uint8List(_packet)..fillRange(0, _packet, 0xff);
    packet[0] = 0x47;
    packet[1] = 0x40 | ((pid >> 8) & 0x1f);
    packet[2] = pid & 0xff;
    packet[3] = 0x10 | _next(pid);
    packet[4] = 0; // pointer field
    packet.setRange(5, 5 + section.length, section);
    return packet;
  }

  static int _crc32(List<int> data) {
    var crc = 0xffffffff;
    for (final byte in data) {
      crc ^= byte << 24;
      for (var i = 0; i < 8; i++) {
        crc = (crc & 0x80000000) != 0
            ? ((crc << 1) ^ 0x04c11db7) & 0xffffffff
            : (crc << 1) & 0xffffffff;
      }
    }
    return crc;
  }

  static _Codec? _codec(String type) {
    switch (type) {
      case 'MPEG2VIDEO':
        return const _Codec(0x02, video: true);
      case 'H264':
        return const _Codec(0x1B, video: true);
      case 'HEVC':
        return const _Codec(0x24, video: true);
      case 'MPEG2AUDIO':
        return const _Codec(0x03);
      case 'AAC':
        return const _Codec(0x0F);
      case 'AC3':
        return const _Codec(0x81, privateStream: true);
      case 'EAC3':
        return const _Codec(0x87, privateStream: true);
      default:
        return null;
    }
  }
}

class _Codec {
  const _Codec(
    this.streamType, {
    this.video = false,
    this.privateStream = false,
  });

  final int streamType;
  final bool video;
  final bool privateStream;

  List<int> get descriptor => const <int>[];
}

class _Track {
  _Track({
    required this.pid,
    required this.streamType,
    required this.streamId,
    required this.video,
    required this.language,
    required this.headers,
    required this.nalLength,
    required this.privateDescriptor,
  });

  final int pid;
  final int streamType;
  final int streamId;
  final bool video;
  final String language;
  final Uint8List? headers;
  final int nalLength;
  final List<int> privateDescriptor;
}
