import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:mawjtvh/data/htsp_message.dart';

void main() {
  test('encodes the documented hello frame', () {
    final bytes = Htsmsg.encode(<String, Object?>{'seq': 1});
    // length 10 | type S64, name length 3, data length 1 | "seq" | 0x01
    expect(
      bytes,
      Uint8List.fromList(<int>[
        0, 0, 0, 10, //
        2, 3, 0, 0, 0, 1, 0x73, 0x65, 0x71, 1,
      ]),
    );
  });

  test('round-trips every value type', () {
    final message = <String, Object?>{
      'method': 'channelAdd',
      'zero': 0,
      'big': 4294967296,
      'negative': -2,
      'ratio': 1.5,
      'flag': true,
      'name': 'الجزيرة HD',
      'blob': Uint8List.fromList(<int>[1, 2, 3]),
      'tags': <Object?>[1, 2, 300],
      'nested': <String, Object?>{'a': 'b', 'list': <Object?>['x']},
    };
    final encoded = Htsmsg.encode(message);
    final framer = HtspFramer();
    final decoded = framer.add(encoded);
    expect(decoded, hasLength(1));
    final out = decoded.single;
    expect(out['method'], 'channelAdd');
    expect(out['zero'], 0);
    expect(out['big'], 4294967296);
    expect(out['negative'], -2);
    expect(out['ratio'], 1.5);
    expect(out['flag'], true);
    expect(out['name'], 'الجزيرة HD');
    expect(out['blob'], Uint8List.fromList(<int>[1, 2, 3]));
    expect(out['tags'], <Object?>[1, 2, 300]);
    expect(out['nested'], <String, Object?>{'a': 'b', 'list': <Object?>['x']});
  });

  test('the framer waits for whole messages and splits joined ones', () {
    final a = Htsmsg.encode(<String, Object?>{'n': 1});
    final b = Htsmsg.encode(<String, Object?>{'n': 2});
    final joined = Uint8List.fromList(<int>[...a, ...b]);
    final framer = HtspFramer();
    expect(framer.add(joined.sublist(0, 5)), isEmpty);
    final out = framer.add(joined.sublist(5));
    expect(out.map((m) => m['n']), <int>[1, 2]);
  });

  test('rejects truncated and oversized input', () {
    expect(
      () => HtspFramer().add(<int>[0xff, 0xff, 0xff, 0xff]),
      throwsA(isA<HtspFormatException>()),
    );
    expect(
      () => Htsmsg.decodeBody(Uint8List.fromList(<int>[3, 0, 0])),
      throwsA(isA<HtspFormatException>()),
    );
  });
}
