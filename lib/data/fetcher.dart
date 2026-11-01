import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import '../core/network_image.dart';

enum FetchFailureKind { invalid, network, tls, http, file, tooLarge }

class FetchException implements Exception {
  const FetchException(
    this.message, {
    this.kind = FetchFailureKind.invalid,
    this.statusCode,
  });

  final String message;
  final FetchFailureKind kind;
  final int? statusCode;

  @override
  String toString() => message;
}

/// Small HTTP/file reader used for playlists and XMLTV. It deliberately uses
/// dart:io's HttpClient so the app can decide per source whether a
/// self-signed certificate is acceptable.
class MawjFetcher {
  MawjFetcher({
    this.connectTimeout = const Duration(seconds: 20),
    this.readTimeout = const Duration(seconds: 45),
    this.maxBytes = 128 * 1024 * 1024,
  });

  final Duration connectTimeout;
  final Duration readTimeout;
  final int maxBytes;

  Future<String> fetchText(
    String location, {
    required bool allowInsecure,
  }) async {
    final value = location.trim();
    if (value.isEmpty) {
      throw const FetchException(
        'The location is empty.',
        kind: FetchFailureKind.invalid,
      );
    }

    final uri = Uri.tryParse(value);
    if (uri != null && (uri.scheme == 'http' || uri.scheme == 'https')) {
      return _fetchHttp(uri, allowInsecure: allowInsecure);
    }
    if (uri != null && uri.scheme == 'file') {
      return _fetchFile(uri.toFilePath());
    }
    return _fetchFile(_expandHome(value));
  }

  Future<String> _fetchHttp(
    Uri uri, {
    required bool allowInsecure,
  }) async {
    final client = HttpClient()
      ..connectionTimeout = connectTimeout
      ..userAgent = kMawjUserAgent
      ..autoUncompress = true;

    if (allowInsecure) {
      client.badCertificateCallback = (_, _, _) => true;
    }

    final userInfo = uri.userInfo;
    final requestUri = userInfo.isEmpty
        ? uri
        : Uri(
            scheme: uri.scheme,
            host: uri.host,
            port: uri.hasPort ? uri.port : null,
            path: uri.path.isEmpty ? '/' : uri.path,
            query: uri.query.isEmpty ? null : uri.query,
            fragment: uri.fragment.isEmpty ? null : uri.fragment,
          );

    try {
      final request = await client.getUrl(requestUri).timeout(connectTimeout);
      request.followRedirects = true;
      request.maxRedirects = 5;
      request.headers
        ..set(
          HttpHeaders.acceptHeader,
          'application/xml, application/x-mpegURL, text/plain, */*',
        )
        ..set(HttpHeaders.acceptEncodingHeader, 'gzip');
      if (userInfo.isNotEmpty) {
        request.headers.set(
          HttpHeaders.authorizationHeader,
          'Basic ${base64Encode(utf8.encode(userInfo))}',
        );
      }

      final response = await request.close().timeout(connectTimeout);
      if (response.statusCode < 200 || response.statusCode >= 300) {
        await response.drain<void>();
        final hint = switch (response.statusCode) {
          401 || 403 => ' Authentication was rejected.',
          404 => ' The URL was not found.',
          >= 500 => ' The server reported an error.',
          _ => '',
        };
        throw FetchException(
          'HTTP ${response.statusCode} from ${requestUri.host}.$hint',
          kind: FetchFailureKind.http,
          statusCode: response.statusCode,
        );
      }

      final declaredLength = response.contentLength;
      if (declaredLength > maxBytes) {
        throw const FetchException(
          'The response is too large.',
          kind: FetchFailureKind.tooLarge,
        );
      }

      final builder = BytesBuilder(copy: false);
      await for (final chunk in response.timeout(readTimeout)) {
        builder.add(chunk);
        if (builder.length > maxBytes) {
          throw const FetchException(
            'The response is too large.',
            kind: FetchFailureKind.tooLarge,
          );
        }
      }

      return _decodeBytes(
        builder.takeBytes(),
        charset: response.headers.contentType?.charset,
      );
    } on FetchException {
      rethrow;
    } on HandshakeException catch (error) {
      throw FetchException(
        'TLS handshake failed: ${error.message}. '
        'If this source uses a self-signed certificate, enable '
        '"Allow self-signed / HTTP".',
        kind: FetchFailureKind.tls,
      );
    } on SocketException catch (error) {
      throw FetchException(
        'Cannot reach the server: ${error.message}.',
        kind: FetchFailureKind.network,
      );
    } on TimeoutException {
      throw const FetchException(
        'The server took too long to respond.',
        kind: FetchFailureKind.network,
      );
    } on HttpException catch (error) {
      throw FetchException(
        'HTTP error: ${error.message}.',
        kind: FetchFailureKind.network,
      );
    } finally {
      client.close(force: true);
    }
  }

  Future<String> _fetchFile(String path) async {
    try {
      final file = File(path);
      if (!await file.exists()) {
        throw FetchException(
          'File not found: $path',
          kind: FetchFailureKind.file,
        );
      }
      final length = await file.length();
      if (length > maxBytes) {
        throw const FetchException(
          'The file is too large.',
          kind: FetchFailureKind.tooLarge,
        );
      }
      return _decodeBytes(await file.readAsBytes());
    } on FetchException {
      rethrow;
    } on FileSystemException catch (error) {
      throw FetchException(
        'Cannot read the file: ${error.message}.',
        kind: FetchFailureKind.file,
      );
    }
  }

  String _decodeBytes(Uint8List bytes, {String? charset}) {
    if (bytes.isEmpty) {
      return '';
    }
    final data = _maybeGunzip(bytes);
    final normalizedCharset = charset?.toLowerCase().replaceAll('"', '').trim();
    if (normalizedCharset != null &&
        (normalizedCharset.contains('iso-8859-1') ||
            normalizedCharset.contains('latin1') ||
            normalizedCharset.contains('windows-1252'))) {
      return _stripBom(latin1.decode(data, allowInvalid: true));
    }
    try {
      return _stripBom(utf8.decode(data));
    } on FormatException {
      return _stripBom(utf8.decode(data, allowMalformed: true));
    }
  }

  Uint8List _maybeGunzip(Uint8List bytes) {
    if (bytes.length >= 2 && bytes[0] == 0x1f && bytes[1] == 0x8b) {
      try {
        return Uint8List.fromList(gzip.decode(bytes));
      } on FormatException {
        return bytes;
      }
    }
    return bytes;
  }

  String _stripBom(String value) =>
      value.startsWith('\uFEFF') ? value.substring(1) : value;

  String _expandHome(String path) {
    if (!path.startsWith('~')) {
      return path;
    }
    final home = Platform.environment['HOME'];
    if (home == null || home.isEmpty) {
      return path;
    }
    if (path == '~') {
      return home;
    }
    if (path.startsWith('~/')) {
      return '$home/${path.substring(2)}';
    }
    return path;
  }
}
