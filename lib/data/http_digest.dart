import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';

/// What a server asks for in `WWW-Authenticate: Digest ...`.
class DigestChallenge {
  const DigestChallenge({
    required this.realm,
    required this.nonce,
    this.opaque,
    this.qop,
    this.algorithm = 'MD5',
  });

  final String realm;
  final String nonce;
  final String? opaque;

  /// `auth` when the server offers it, otherwise null (the older form).
  final String? qop;

  /// `MD5` or `MD5-sess`.
  final String algorithm;

  static final RegExp _param =
      RegExp(r'(\w+)\s*=\s*(?:"((?:[^"\\]|\\.)*)"|([^\s,]+))');

  /// The Digest challenge among [headers] (a response can carry several, such
  /// as Basic and Digest), or null when there is none this client can answer.
  static DigestChallenge? pick(Iterable<String>? headers) {
    for (final header in headers ?? const <String>[]) {
      // One header value may hold more than one challenge.
      for (final piece in header.split(RegExp(r'(?=\bDigest\s)', caseSensitive: false))) {
        final parsed = parse(piece);
        if (parsed != null) {
          return parsed;
        }
      }
    }
    return null;
  }

  /// Parses `Digest realm="x", nonce="y", qop="auth", ...`.
  static DigestChallenge? parse(String header) {
    final trimmed = header.trim();
    if (trimmed.length < 7 || trimmed.substring(0, 6).toLowerCase() != 'digest') {
      return null;
    }
    final values = <String, String>{};
    for (final match in _param.allMatches(trimmed.substring(6))) {
      final quoted = match.group(2);
      values[match.group(1)!.toLowerCase()] =
          quoted?.replaceAllMapped(RegExp(r'\\(.)'), (m) => m.group(1)!) ??
              match.group(3)!;
    }
    final nonce = values['nonce'];
    if (nonce == null) {
      return null;
    }
    final algorithm = (values['algorithm'] ?? 'MD5').toUpperCase();
    if (algorithm != 'MD5' && algorithm != 'MD5-SESS') {
      return null;
    }
    String? qop;
    final offered = values['qop'];
    if (offered != null) {
      final tokens = offered.split(',').map((t) => t.trim().toLowerCase());
      if (!tokens.contains('auth')) {
        return null;
      }
      qop = 'auth';
    }
    return DigestChallenge(
      realm: values['realm'] ?? '',
      nonce: nonce,
      opaque: values['opaque'],
      qop: qop,
      algorithm: algorithm,
    );
  }
}

/// Answers Digest challenges (RFC 7616 with MD5, the form Tvheadend speaks).
/// Keeps the last challenge so later requests are signed straight away.
class DigestAuth {
  DigestAuth(this.username, this.password, {String Function()? cnonce})
      : _cnonce = cnonce ?? _randomCnonce;

  final String username;
  final String password;
  final String Function() _cnonce;

  DigestChallenge? _challenge;
  int _count = 0;

  /// True once a challenge has been accepted.
  bool get ready => _challenge != null;

  /// Remembers a new challenge (a fresh nonce starts the count again).
  void accept(DigestChallenge challenge) {
    _challenge = challenge;
    _count = 0;
  }

  /// The `Authorization` value for a request, or null before any challenge.
  /// [requestTarget] is the path and query, as sent on the request line.
  String? authorization(String method, String requestTarget) {
    final challenge = _challenge;
    if (challenge == null) {
      return null;
    }
    _count++;
    final nc = _count.toRadixString(16).padLeft(8, '0');
    final cnonce = _cnonce();
    var ha1 = _md5('$username:${challenge.realm}:$password');
    if (challenge.algorithm == 'MD5-SESS') {
      ha1 = _md5('$ha1:${challenge.nonce}:$cnonce');
    }
    final ha2 = _md5('${method.toUpperCase()}:$requestTarget');
    final qop = challenge.qop;
    final response = qop == null
        ? _md5('$ha1:${challenge.nonce}:$ha2')
        : _md5('$ha1:${challenge.nonce}:$nc:$cnonce:$qop:$ha2');
    final parts = <String>[
      'username="${_quote(username)}"',
      'realm="${_quote(challenge.realm)}"',
      'nonce="${challenge.nonce}"',
      'uri="$requestTarget"',
      'response="$response"',
      if (challenge.algorithm != 'MD5') 'algorithm=${challenge.algorithm}',
      if (challenge.opaque != null) 'opaque="${challenge.opaque}"',
      if (qop != null) ...<String>['qop=$qop', 'nc=$nc', 'cnonce="$cnonce"'],
    ];
    return 'Digest ${parts.join(', ')}';
  }

  static String _md5(String text) => md5.convert(utf8.encode(text)).toString();

  static String _quote(String text) =>
      text.replaceAll(r'\', r'\\').replaceAll('"', r'\"');

  static String _randomCnonce() {
    final random = Random.secure();
    return List<String>.generate(
      8,
      (_) => random.nextInt(256).toRadixString(16).padLeft(2, '0'),
    ).join();
  }
}

/// The request-target of [uri]: its path and query.
String requestTargetOf(Uri uri) {
  final path = uri.path.isEmpty ? '/' : uri.path;
  return uri.hasQuery ? '$path?${uri.query}' : path;
}
