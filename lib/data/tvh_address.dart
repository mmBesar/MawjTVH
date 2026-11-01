import 'dart:convert';

/// Forgiving parsing of what a person types into the "server" field.
///
/// Accepts `10.0.0.5`, `10.0.0.5:9981`, `tv.example.com`,
/// `https://tv.example.com` and `http://host:9981/tvh/` (a web root). A bare
/// address without a port uses Tvheadend's default HTTP port 9981; an explicit
/// `http://` or `https://` without a port uses 80 or 443 (a reverse proxy).
class TvhAddressException implements Exception {
  const TvhAddressException(this.message);

  final String message;

  @override
  String toString() => message;
}

class TvhAddress {
  const TvhAddress({
    required this.tls,
    required this.host,
    required this.port,
    this.webroot = '',
  });

  static const int defaultHttpPort = 9981;

  final bool tls;
  final String host;
  final int port;

  /// Path prefix when Tvheadend runs under a web root, such as `/tvh`. Empty,
  /// or starting with `/` and without a trailing `/`.
  final String webroot;

  factory TvhAddress.parse(String input) {
    final text = input.trim();
    if (text.isEmpty) {
      throw const TvhAddressException(
        'Enter the server address, for example 10.0.0.5 or '
        'https://tv.example.com',
      );
    }
    final explicitScheme = text.contains('://');
    final withScheme = explicitScheme ? text : 'http://$text';
    final uri = Uri.tryParse(withScheme);
    if (uri == null || uri.host.isEmpty) {
      throw TvhAddressException('That does not look like a server address: $text');
    }
    final scheme = uri.scheme.toLowerCase();
    if (scheme != 'http' && scheme != 'https') {
      throw const TvhAddressException(
        'Only http:// and https:// addresses are supported.',
      );
    }
    final tls = scheme == 'https';
    final int port;
    if (uri.hasPort) {
      port = uri.port;
    } else if (!explicitScheme) {
      port = defaultHttpPort;
    } else {
      port = tls ? 443 : 80;
    }
    var webroot = uri.path;
    while (webroot.endsWith('/')) {
      webroot = webroot.substring(0, webroot.length - 1);
    }
    return TvhAddress(tls: tls, host: uri.host, port: port, webroot: webroot);
  }

  int get _defaultPort => tls ? 443 : 80;

  String get _hostText => host.contains(':') ? '[$host]' : host;

  String _base(String userInfo) {
    final scheme = tls ? 'https' : 'http';
    final portText = port == _defaultPort ? '' : ':$port';
    return '$scheme://$userInfo$_hostText$portText$webroot';
  }

  /// `http(s)://host[:port]` plus the web root, no trailing slash.
  String get baseUrl => _base('');

  String url(String pathAndQuery) => '$baseUrl$pathAndQuery';

  Uri uri(String path, [Map<String, String>? query]) {
    final parsed = Uri.parse(url(path));
    if (query == null || query.isEmpty) {
      return parsed;
    }
    return parsed.replace(
      queryParameters: <String, String>{
        ...parsed.queryParameters,
        ...query,
      },
    );
  }

  String _userInfo(String user, String pass) =>
      user.isEmpty ? '' : '${pct(user)}:${pct(pass)}@';

  /// Playback URL of a channel, with the login as URL user info, which mpv,
  /// VLC and ExoPlayer all accept.
  String streamUrl(
    String uuid, {
    String user = '',
    String pass = '',
    String profile = '',
  }) {
    final query = profile.trim().isEmpty ? '' : '?profile=${pct(profile.trim())}';
    return '${_base(_userInfo(user, pass))}/stream/channel/$uuid$query';
  }

  /// URL of a finished (or still running) recording file.
  String dvrUrl(String uuid, {String user = '', String pass = ''}) {
    return '${_base(_userInfo(user, pass))}/dvrfile/$uuid';
  }

  /// A picture the server gave us: usually a relative `imagecache/<id>` path
  /// (fetched through the address the person typed, with the login), or a full
  /// http(s) URL elsewhere (fetched as is, without the login).
  ///
  /// Whatever host the server names for itself is ignored for `imagecache/`:
  /// behind a reverse proxy it often names an address nobody outside can reach.
  String? imageUrl(String? source, {String user = '', String pass = ''}) {
    final src = source?.trim() ?? '';
    if (src.isEmpty) {
      return null;
    }
    final cache = src.indexOf('imagecache/');
    if (cache >= 0) {
      return '${_base(_userInfo(user, pass))}/${src.substring(cache)}';
    }
    if (src.startsWith('http://') || src.startsWith('https://')) {
      return src;
    }
    return null;
  }
}

/// Percent-encodes everything but unreserved characters (RFC 3986), so a
/// password with `@` or `:` survives inside a URL.
String pct(String value) {
  final out = StringBuffer();
  for (final byte in utf8.encode(value)) {
    final isUnreserved = (byte >= 0x30 && byte <= 0x39) ||
        (byte >= 0x41 && byte <= 0x5a) ||
        (byte >= 0x61 && byte <= 0x7a) ||
        byte == 0x2d ||
        byte == 0x2e ||
        byte == 0x5f ||
        byte == 0x7e;
    if (isUnreserved) {
      out.writeCharCode(byte);
    } else {
      out.write('%${byte.toRadixString(16).toUpperCase().padLeft(2, '0')}');
    }
  }
  return out.toString();
}

/// `http://user:pass@host:9981/path?ticket=abc` becomes
/// `http://host:9981/path (password)`: where a URL points and how it logs in,
/// without any secret. For diagnostics a person may paste into an issue.
String redactUrl(String url) {
  final split = url.indexOf('://');
  final scheme = split < 0 ? '' : url.substring(0, split);
  final rest = split < 0 ? url : url.substring(split + 3);
  final queryAt = rest.indexOf('?');
  final hostAndPath = queryAt < 0 ? rest : rest.substring(0, queryAt);
  final query = queryAt < 0 ? '' : rest.substring(queryAt + 1);
  final slash = hostAndPath.indexOf('/');
  final authority = slash < 0 ? hostAndPath : hostAndPath.substring(0, slash);
  final path = slash < 0 ? '' : hostAndPath.substring(slash);
  final at = authority.lastIndexOf('@');
  final hasUserInfo = at >= 0;
  final host = hasUserInfo ? authority.substring(at + 1) : authority;
  final how = <String>[
    if (hasUserInfo) 'password',
    for (final part in query.split('&'))
      if (part.startsWith('ticket=')) 'ticket',
    for (final part in query.split('&'))
      if (part.toLowerCase().startsWith('auth=')) 'code',
  ];
  final suffix = how.isEmpty ? '' : ' (${how.join(', ')})';
  return '${scheme.isEmpty ? '' : '$scheme://'}$host$path$suffix';
}
