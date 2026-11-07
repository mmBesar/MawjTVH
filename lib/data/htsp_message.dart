import 'dart:convert';
import 'dart:typed_data';

/// Thrown when bytes are not a valid HTSP message.
class HtspFormatException implements Exception {
  HtspFormatException(this.message);

  final String message;

  @override
  String toString() => 'HTSP: $message';
}

/// The binary container ("htsmsg") that Tvheadend's HTSP protocol speaks.
///
/// A message is a 4-byte big-endian length followed by fields. A field is
/// `type(1) nameLength(1) dataLength(4) name data`. Maps hold named fields and
/// lists hold fields with empty names. Integers are little-endian with no
/// padding (zero is no bytes at all).
///
/// Values map onto Dart as: int, String, Uint8List, double, bool, `List<Object?>`
/// and `Map<String, Object?>`.
class Htsmsg {
  const Htsmsg._();

  static const int _map = 1;
  static const int _s64 = 2;
  static const int _str = 3;
  static const int _bin = 4;
  static const int _list = 5;
  static const int _dbl = 6;
  static const int _bool = 7;
  static const int _uuid = 8;

  /// Largest message accepted, a guard against a corrupt length.
  static const int maxMessage = 32 * 1024 * 1024;

  /// A whole message, length prefix included.
  static Uint8List encode(Map<String, Object?> message) {
    final body = BytesBuilder(copy: false);
    _writeFields(body, message.entries.map((e) => MapEntry(e.key, e.value)));
    final bytes = body.takeBytes();
    final out = ByteData(4 + bytes.length);
    out.setUint32(0, bytes.length);
    final result = out.buffer.asUint8List();
    result.setRange(4, 4 + bytes.length, bytes);
    return result;
  }

  /// Decodes one message body (without the 4-byte length).
  static Map<String, Object?> decodeBody(Uint8List body) {
    final fields = _readFields(body, 0, body.length, depth: 0);
    final map = <String, Object?>{};
    for (final entry in fields) {
      map[entry.key] = entry.value;
    }
    return map;
  }

  static void _writeFields(
    BytesBuilder out,
    Iterable<MapEntry<String, Object?>> fields,
  ) {
    for (final field in fields) {
      final value = field.value;
      if (value == null) {
        continue;
      }
      _writeField(out, field.key, value);
    }
  }

  static void _writeField(BytesBuilder out, String name, Object value) {
    final nameBytes = utf8.encode(name);
    if (nameBytes.length > 255) {
      throw HtspFormatException('Field name too long: $name');
    }
    late final int type;
    late final Uint8List data;
    if (value is bool) {
      type = _bool;
      data = Uint8List.fromList(<int>[value ? 1 : 0]);
    } else if (value is int) {
      type = _s64;
      data = _encodeInt(value);
    } else if (value is double) {
      type = _dbl;
      data = (ByteData(8)..setFloat64(0, value, Endian.little))
          .buffer
          .asUint8List();
    } else if (value is String) {
      type = _str;
      data = Uint8List.fromList(utf8.encode(value));
    } else if (value is Uint8List) {
      type = _bin;
      data = value;
    } else if (value is List) {
      type = _list;
      final inner = BytesBuilder(copy: false);
      for (final item in value) {
        if (item != null) {
          _writeField(inner, '', item);
        }
      }
      data = inner.takeBytes();
    } else if (value is Map<String, Object?>) {
      type = _map;
      final inner = BytesBuilder(copy: false);
      _writeFields(inner, value.entries);
      data = inner.takeBytes();
    } else {
      throw HtspFormatException('Unsupported value for $name: ${value.runtimeType}');
    }
    final header = ByteData(6)
      ..setUint8(0, type)
      ..setUint8(1, nameBytes.length)
      ..setUint32(2, data.length);
    out
      ..add(header.buffer.asUint8List())
      ..add(nameBytes)
      ..add(data);
  }

  /// Little-endian, trimmed of trailing zero bytes; negatives use all 8 bytes.
  static Uint8List _encodeInt(int value) {
    final bytes = <int>[];
    var rest = value;
    if (value < 0) {
      for (var i = 0; i < 8; i++) {
        bytes.add(rest & 0xff);
        rest = rest >> 8;
      }
      return Uint8List.fromList(bytes);
    }
    while (rest != 0) {
      bytes.add(rest & 0xff);
      rest = rest >> 8;
    }
    return Uint8List.fromList(bytes);
  }

  static int _decodeInt(Uint8List data, int start, int length) {
    if (length > 8) {
      throw HtspFormatException('Integer of $length bytes');
    }
    var value = 0;
    for (var i = length - 1; i >= 0; i--) {
      value = (value << 8) | data[start + i];
    }
    return value;
  }

  static List<MapEntry<String, Object?>> _readFields(
    Uint8List data,
    int start,
    int end, {
    required int depth,
  }) {
    if (depth > 32) {
      throw HtspFormatException('Messages nested too deeply');
    }
    final fields = <MapEntry<String, Object?>>[];
    var offset = start;
    final view = ByteData.sublistView(data);
    while (offset < end) {
      if (end - offset < 6) {
        throw HtspFormatException('Truncated field header');
      }
      final type = data[offset];
      final nameLength = data[offset + 1];
      final dataLength = view.getUint32(offset + 2);
      offset += 6;
      if (offset + nameLength + dataLength > end) {
        throw HtspFormatException('Field runs past the message');
      }
      final name = utf8.decode(
        data.sublist(offset, offset + nameLength),
        allowMalformed: true,
      );
      offset += nameLength;
      final dataStart = offset;
      final Object? value;
      switch (type) {
        case _map:
          final inner = _readFields(
            data,
            dataStart,
            dataStart + dataLength,
            depth: depth + 1,
          );
          value = <String, Object?>{for (final e in inner) e.key: e.value};
        case _list:
          final inner = _readFields(
            data,
            dataStart,
            dataStart + dataLength,
            depth: depth + 1,
          );
          value = <Object?>[for (final e in inner) e.value];
        case _s64:
          value = _decodeInt(data, dataStart, dataLength);
        case _str:
          value = utf8.decode(
            data.sublist(dataStart, dataStart + dataLength),
            allowMalformed: true,
          );
        case _bin:
        case _uuid:
          value = data.sublist(dataStart, dataStart + dataLength);
        case _dbl:
          if (dataLength != 8) {
            throw HtspFormatException('Double of $dataLength bytes');
          }
          value = view.getFloat64(dataStart, Endian.little);
        case _bool:
          value = dataLength > 0 && data[dataStart] != 0;
        default:
          throw HtspFormatException('Unknown field type $type');
      }
      offset = dataStart + dataLength;
      fields.add(MapEntry<String, Object?>(name, value));
    }
    return fields;
  }
}

/// Cuts a byte stream into whole messages.
///
/// Received chunks are only collected until a whole message is there, and are
/// then joined once, so a big message (a block of a recording) is copied one
/// time however many pieces it arrives in.
class HtspFramer {
  final List<Uint8List> _parts = <Uint8List>[];
  int _partsLength = 0;
  Uint8List _buffer = Uint8List(0);

  /// Length of the body of the message being waited for, once known.
  int? _frame;

  /// Adds received bytes; returns every message completed by them.
  List<Map<String, Object?>> add(List<int> chunk) {
    if (chunk.isNotEmpty) {
      _parts.add(chunk is Uint8List ? chunk : Uint8List.fromList(chunk));
      _partsLength += chunk.length;
    }
    final messages = <Map<String, Object?>>[];
    while (true) {
      var frame = _frame;
      if (frame == null) {
        if (_buffer.length + _partsLength < 4) {
          break;
        }
        _join();
        frame = ByteData.sublistView(_buffer, 0, 4).getUint32(0);
        if (frame > Htsmsg.maxMessage) {
          throw HtspFormatException('Message of $frame bytes');
        }
        _frame = frame;
      }
      if (_buffer.length + _partsLength < 4 + frame) {
        break;
      }
      _join();
      messages.add(
        Htsmsg.decodeBody(Uint8List.sublistView(_buffer, 4, 4 + frame)),
      );
      _buffer = Uint8List.sublistView(_buffer, 4 + frame);
      _frame = null;
    }
    return messages;
  }

  /// Moves everything collected so far into [_buffer].
  void _join() {
    if (_parts.isEmpty) {
      return;
    }
    final joined = Uint8List(_buffer.length + _partsLength);
    joined.setRange(0, _buffer.length, _buffer);
    var at = _buffer.length;
    for (final part in _parts) {
      joined.setRange(at, at + part.length, part);
      at += part.length;
    }
    _parts.clear();
    _partsLength = 0;
    _buffer = joined;
  }
}
