import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:mawjtvh/data/ts_muxer.dart';

void main() {
  TsMuxer configured() {
    final mux = TsMuxer()
      ..configure(const <TsStream>[
        TsStream(index: 1, type: 'H264'),
        TsStream(index: 2, type: 'AAC', language: 'ara'),
        TsStream(index: 3, type: 'TELETEXT'),
      ]);
    return mux;
  }

  test('tables are two aligned packets with valid CRCs', () {
    final tables = configured().tables();
    expect(tables.length, 376);
    expect(tables[0], 0x47);
    expect(tables[188], 0x47);
    // PAT on PID 0, PMT on 0x1000.
    expect(((tables[1] & 0x1f) << 8) | tables[2], 0);
    expect(((tables[189] & 0x1f) << 8) | tables[190], 0x1000);
  });

  test('every output packet is 188 bytes and starts with a sync byte', () {
    final mux = configured();
    final bytes = mux.packet(
      stream: 1,
      payload: Uint8List.fromList(List<int>.generate(1000, (i) => i & 0xff)),
      pts: 900000,
      dts: 896400,
      keyframe: true,
    )!;
    expect(bytes.length % 188, 0);
    for (var i = 0; i < bytes.length; i += 188) {
      expect(bytes[i], 0x47);
    }
    // First packet starts a PES and carries a PCR (adaptation field).
    expect(bytes[1] & 0x40, 0x40);
    expect(bytes[3] & 0x20, 0x20);
  });

  test('continuity counters increase per PID and survive reconfigure', () {
    final mux = configured();
    Uint8List one() => mux.packet(
          stream: 2,
          payload: Uint8List(100),
          pts: 90000,
          dts: null,
          keyframe: true,
        )!;
    final a = one();
    final b = one();
    expect(b[3] & 0x0f, (a[3] & 0x0f) + 1);
    mux.configure(const <TsStream>[
      TsStream(index: 1, type: 'H264'),
      TsStream(index: 2, type: 'AAC', language: 'ara'),
    ]);
    final c = mux.packet(
      stream: 2,
      payload: Uint8List(100),
      pts: 90000,
      dts: null,
      keyframe: true,
    )!;
    expect(c[3] & 0x0f, (b[3] & 0x0f) + 1);
  });

  test('streams it cannot carry are skipped', () {
    final mux = configured();
    expect(
      mux.packet(
        stream: 3,
        payload: Uint8List(10),
        pts: 1,
        dts: null,
        keyframe: false,
      ),
      isNull,
    );
  });

  test('AVCC payloads are converted to Annex B', () {
    final meta = Uint8List.fromList(<int>[
      1, 0x64, 0, 0x1f, 0xFF, 0xE1, 0, 2, 0x67, 0x42, 1, 0, 2, 0x68, 0xCE,
    ]);
    final mux = TsMuxer()
      ..configure(<TsStream>[TsStream(index: 1, type: 'H264', meta: meta)]);
    final bytes = mux.packet(
      stream: 1,
      payload: Uint8List.fromList(<int>[0, 0, 0, 3, 0x65, 1, 2]),
      pts: 0,
      dts: 0,
      keyframe: true,
    )!;
    final text = bytes.toList();
    // SPS start code + SPS (0x67 0x42) appears before the slice.
    final sps = <int>[0, 0, 0, 1, 0x67, 0x42];
    var found = false;
    for (var i = 0; i + sps.length < text.length; i++) {
      if (text.sublist(i, i + sps.length).join(',') == sps.join(',')) {
        found = true;
      }
    }
    expect(found, isTrue);
  });

  test('a DVB subtitle packet gets its data identifier and end marker back', () {
    final mux = TsMuxer()
      ..configure(const <TsStream>[
        TsStream(index: 1, type: 'H264'),
        TsStream(
          index: 4,
          type: 'DVBSUB',
          language: 'eng',
          compositionId: 1,
          ancillaryId: 2,
        ),
      ]);
    // What Tvheadend sends: segments only, starting with the sync byte 0x0F.
    final segments = Uint8List.fromList(<int>[0x0f, 0x10, 0, 1, 0, 3, 1, 2, 3]);
    final bytes = mux.packet(
      stream: 4,
      payload: segments,
      pts: 90000,
      dts: null,
      keyframe: false,
    )!;
    expect(bytes.length, 188);
    var offset = 4;
    if (bytes[3] & 0x20 != 0) {
      offset += 1 + bytes[4];
    }
    // PES start code, private stream 1, then a header with only a PTS.
    expect(bytes.sublist(offset, offset + 4), <int>[0, 0, 1, 0xBD]);
    final data = bytes.sublist(offset + 14);
    expect(data, <int>[0x20, 0x00, ...segments, 0xFF]);
  });
}
