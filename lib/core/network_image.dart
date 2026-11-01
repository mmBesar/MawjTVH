import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';
import 'package:path_provider/path_provider.dart';

const String kMawjUserAgent =
    'MawjTVH/0.1.1 (+https://github.com/mmBesar/MawjTVH)';

/// Every poster and logo owns a socket while it downloads. A guide built from
/// a full XMLTV file can ask for thousands of images at once, and that burst
/// starves the player's HLS requests and the playlist/EPG refreshes that hit
/// the same host. Fetch through a small fixed number of slots instead of
/// letting the whole screen go out at the same time.
class _FetchLimiter {
  _FetchLimiter(this.maxConcurrent);

  final int maxConcurrent;
  int _active = 0;
  final List<Completer<void>> _waiting = <Completer<void>>[];

  Future<void> acquire() {
    if (_active < maxConcurrent) {
      _active += 1;
      return Future<void>.value();
    }
    final completer = Completer<void>();
    _waiting.add(completer);
    return completer.future;
  }

  void release() {
    if (_waiting.isNotEmpty) {
      // Hand this slot straight to the next waiter without freeing it.
      _waiting.removeAt(0).complete();
      return;
    }
    if (_active > 0) {
      _active -= 1;
    }
  }
}

final _FetchLimiter _imageFetches = _FetchLimiter(16);

/// One client per trust setting, kept alive. Opening a client per image meant
/// a new TCP connection and TLS handshake for every logo; a playlist of a few
/// hundred channels on a self-hosted server spent most of its time there.
final Map<bool, HttpClient> _clients = <bool, HttpClient>{};

HttpClient _sharedClient(bool allowInsecure) {
  return _clients.putIfAbsent(allowInsecure, () {
    final client = HttpClient()
      ..connectionTimeout = const Duration(seconds: 12)
      ..idleTimeout = const Duration(seconds: 30)
      ..maxConnectionsPerHost = 12
      ..userAgent = kMawjUserAgent;
    if (allowInsecure) {
      client.badCertificateCallback = (_, _, _) => true;
    }
    return client;
  });
}

/// An [ImageProvider] for channel logos that understands MawjTVH's per-source
/// "allow self-signed certificates" setting. Plain [NetworkImage] uses the
/// platform HTTP stack, which cannot be told to trust a specific source.
@immutable
class MawjNetworkImage extends ImageProvider<MawjNetworkImage> {
  const MawjNetworkImage(this.url, {required this.allowInsecure});

  final String url;
  final bool allowInsecure;

  @override
  Future<MawjNetworkImage> obtainKey(ImageConfiguration configuration) {
    return SynchronousFuture<MawjNetworkImage>(this);
  }

  @override
  ImageStreamCompleter loadImage(
    MawjNetworkImage key,
    ImageDecoderCallback decode,
  ) {
    return MultiFrameImageStreamCompleter(
      codec: _loadAsync(key, decode),
      scale: 1.0,
      debugLabel: key.url,
    );
  }

  Future<ui.Codec> _loadAsync(
    MawjNetworkImage key,
    ImageDecoderCallback decode,
  ) async {
    final uri = Uri.tryParse(key.url);
    if (uri == null || !uri.hasScheme) {
      throw ArgumentError.value(key.url, 'url', 'Not a valid image URL');
    }
    if (uri.scheme != 'http' && uri.scheme != 'https') {
      throw ArgumentError.value(key.url, 'url', 'Unsupported image scheme');
    }

    // A Tvheadend picture comes with the login as URL user info. HttpClient
    // does not turn that into a header by itself, so do it here and keep the
    // password out of the request line.
    final userInfo = uri.userInfo;
    final requestUri = userInfo.isEmpty
        ? uri
        : Uri(
            scheme: uri.scheme,
            host: uri.host,
            port: uri.hasPort ? uri.port : null,
            path: uri.path,
            query: uri.query.isEmpty ? null : uri.query,
          );
    final authorization = userInfo.isEmpty
        ? null
        : 'Basic ${base64Encode(utf8.encode(Uri.decodeComponent(userInfo)))}';

    // Logos are served again every time Flutter's in-memory image cache
    // evicts them (a big playlist can push the previous source out). Keep a
    // bounded copy on disk so switching sources, restarting, or a busy logo
    // host does not blank out artwork that was fetched successfully before.
    final cached = await _readCachedBytes(key.url);
    if (cached != null) {
      try {
        final buffer = await ui.ImmutableBuffer.fromUint8List(cached);
        return await decode(buffer);
      } catch (_) {
        await _deleteCachedBytes(key.url);
      }
    }

    // Large playlists can produce a burst of logo requests. Retry once on
    // transient failures (timeouts, connection resets, 429/5xx) so a busy
    // source does not leave permanent fallback tiles in the channel list.
    Object? lastError;
    await _imageFetches.acquire();
    try {
      for (var attempt = 0; attempt < 2; attempt++) {
        if (attempt > 0) {
          await Future<void>.delayed(const Duration(milliseconds: 400));
        }
        final client = _sharedClient(key.allowInsecure);

        try {
          final request = await client
              .getUrl(requestUri)
              .timeout(const Duration(seconds: 15));
          request.headers.set(HttpHeaders.acceptHeader, 'image/*,*/*;q=0.8');
          if (authorization != null) {
            request.headers.set(HttpHeaders.authorizationHeader, authorization);
          }
          final response =
              await request.close().timeout(const Duration(seconds: 15));
          if (response.statusCode < 200 || response.statusCode >= 300) {
            await response.drain<void>();
            final error = NetworkImageLoadException(
              statusCode: response.statusCode,
              uri: uri,
            );
            if (response.statusCode != 429 && response.statusCode < 500) {
              throw error;
            }
            lastError = error;
            continue;
          }
          final Uint8List bytes =
              await consolidateHttpClientResponseBytes(response)
                  .timeout(const Duration(seconds: 20));
          if (bytes.isEmpty) {
            throw StateError('Empty image response');
          }
          final buffer = await ui.ImmutableBuffer.fromUint8List(bytes);
          final codec = await decode(buffer);
          unawaited(_writeCachedBytes(key.url, bytes));
          return codec;
        } on SocketException catch (error) {
          lastError = error;
        } on HttpException catch (error) {
          lastError = error;
        } on TimeoutException catch (error) {
          lastError = error;
        }
      }
      if (lastError != null) {
        throw lastError;
      }
      throw StateError('Image request failed');
    } finally {
      _imageFetches.release();
    }
  }

  static Directory? _cacheDirectory;
  static int _cacheWrites = 0;
  static bool _pruning = false;

  static Future<Directory?> _cacheDir() async {
    final known = _cacheDirectory;
    if (known != null) {
      return known;
    }
    try {
      final base = await getTemporaryDirectory();
      final dir = Directory(
        '${base.path}${Platform.pathSeparator}mawjtvh_images',
      );
      if (!await dir.exists()) {
        await dir.create(recursive: true);
      }
      return _cacheDirectory = dir;
    } catch (_) {
      return null;
    }
  }

  /// A stable key derived from the URL. `String.hashCode` is not guaranteed to
  /// survive a restart, so use two FNV-1a passes for a 64-bit-ish filename.
  static String _cacheKey(String url) {
    var a = 0x811c9dc5;
    var b = 0x9e3779b9;
    for (final byte in utf8.encode(url)) {
      a = ((a ^ byte) * 0x01000193) & 0xFFFFFFFF;
      b = ((b + byte) * 0x85ebca6b) & 0xFFFFFFFF;
    }
    return '${a.toRadixString(16).padLeft(8, '0')}'
        '${b.toRadixString(16).padLeft(8, '0')}';
  }

  static Future<String?> _cachePath(String url) async {
    final dir = await _cacheDir();
    if (dir == null) {
      return null;
    }
    return '${dir.path}${Platform.pathSeparator}${_cacheKey(url)}.img';
  }

  static Future<Uint8List?> _readCachedBytes(String url) async {
    try {
      final path = await _cachePath(url);
      if (path == null) {
        return null;
      }
      final file = File(path);
      if (!await file.exists()) {
        return null;
      }
      final modified = (await file.stat()).modified;
      if (DateTime.now().difference(modified) > const Duration(days: 30)) {
        await file.delete();
        return null;
      }
      final bytes = await file.readAsBytes();
      if (bytes.isEmpty) {
        await file.delete();
        return null;
      }
      return bytes;
    } catch (_) {
      return null;
    }
  }

  static Future<void> _deleteCachedBytes(String url) async {
    try {
      final path = await _cachePath(url);
      if (path == null) {
        return;
      }
      final file = File(path);
      if (await file.exists()) {
        await file.delete();
      }
    } catch (_) {
      // A missing or locked cache file is not worth reporting.
    }
  }

  static Future<void> _writeCachedBytes(String url, Uint8List bytes) async {
    try {
      final path = await _cachePath(url);
      if (path == null) {
        return;
      }
      final temp = File('$path.tmp');
      await temp.writeAsBytes(bytes, flush: false);
      await temp.rename(path);
      if (++_cacheWrites % 256 == 0) {
        final dir = _cacheDirectory;
        if (dir != null) {
          await _pruneCache(dir);
        }
      }
    } catch (_) {
      // Disk caching is best-effort; the decoded image is already on screen.
    }
  }

  /// Keeps the temporary logo cache bounded without touching it on every hit.
  static Future<void> _pruneCache(Directory dir) async {
    if (_pruning) {
      return;
    }
    _pruning = true;
    try {
      final files = <File>[];
      await for (final entity in dir.list()) {
        if (entity is File && entity.path.endsWith('.img')) {
          files.add(entity);
        }
      }
      if (files.length <= 400) {
        return;
      }
      final entries = await Future.wait(
        files.map((file) async => (file: file, stat: await file.stat())),
      );
      entries.sort((a, b) => a.stat.modified.compareTo(b.stat.modified));
      var size = 0;
      final keep = <File>[];
      for (final entry in entries.reversed) {
        size += entry.stat.size;
        if (keep.length < 300 && size <= 96 * 1024 * 1024) {
          keep.add(entry.file);
        }
      }
      final keepPaths = keep.map((file) => file.path).toSet();
      for (final entry in entries) {
        if (!keepPaths.contains(entry.file.path)) {
          await entry.file.delete();
        }
      }
    } catch (_) {
      // Pruning is opportunistic; never fail an image load because of it.
    } finally {
      _pruning = false;
    }
  }

  @override
  bool operator ==(Object other) {
    return other is MawjNetworkImage &&
        other.url == url &&
        other.allowInsecure == allowInsecure;
  }

  @override
  int get hashCode => Object.hash(url, allowInsecure);

  @override
  String toString() => 'MawjNetworkImage("$url", insecure: $allowInsecure)';
}
