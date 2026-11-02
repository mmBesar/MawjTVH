import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import '../core/network_image.dart';
import 'htsp_backend.dart' show looksLikeRadioTag;
import 'models.dart';
import 'tvh_address.dart';
import 'tvh_models.dart';

enum TvhFailure { dns, connect, tls, timeout, http, badResponse }

class TvhException implements Exception {
  const TvhException(this.message, {this.kind = TvhFailure.badResponse, this.statusCode});

  final String message;
  final TvhFailure kind;
  final int? statusCode;

  /// 403 is the server saying this account may not do that.
  bool get isForbidden => statusCode == 403;
  bool get isUnauthorized => statusCode == 401;

  @override
  String toString() => message;
}

class TvhResponse {
  const TvhResponse(this.statusCode, this.bytes, {this.location});

  final int statusCode;
  final List<int> bytes;
  final String? location;

  String get body => utf8.decode(bytes, allowMalformed: true);
}

/// The one place that touches the network, so the rest can be tested with a
/// fake.
abstract class TvhTransport {
  Future<TvhResponse> send(
    String method,
    Uri uri, {
    Map<String, String>? form,
    Map<String, String>? headers,
    Duration? timeout,
  });

  void close();
}

class IoTvhTransport implements TvhTransport {
  IoTvhTransport({required bool allowInsecure}) {
    _client = HttpClient()
      ..connectionTimeout = const Duration(seconds: 8)
      ..idleTimeout = const Duration(seconds: 20)
      ..userAgent = kMawjUserAgent
      ..findProxy = (_) => 'DIRECT';
    if (allowInsecure) {
      _client.badCertificateCallback = (_, _, _) => true;
    }
  }

  late final HttpClient _client;

  @override
  Future<TvhResponse> send(
    String method,
    Uri uri, {
    Map<String, String>? form,
    Map<String, String>? headers,
    Duration? timeout,
  }) async {
    final limit = timeout ?? const Duration(seconds: 30);
    final request = await _client.openUrl(method, uri).timeout(limit);
    // Redirects are handled by the caller: the login must never travel to
    // another host, and a move from http to https needs the address updated.
    request.followRedirects = false;
    request.headers.set(HttpHeaders.acceptHeader, 'application/json, */*');
    request.headers.set(HttpHeaders.acceptEncodingHeader, 'gzip');
    headers?.forEach(request.headers.set);
    if (form != null) {
      request.headers.contentType = ContentType(
        'application',
        'x-www-form-urlencoded',
        charset: 'utf-8',
      );
      request.write(Uri(queryParameters: form).query);
    }
    final response = await request.close().timeout(limit);
    final builder = BytesBuilder(copy: false);
    await for (final chunk in response.timeout(limit)) {
      builder.add(chunk);
    }
    return TvhResponse(
      response.statusCode,
      builder.takeBytes(),
      location: response.headers.value(HttpHeaders.locationHeader),
    );
  }

  @override
  void close() => _client.close(force: true);
}

/// Tvheadend's HTTP JSON API. Works over HTTP or HTTPS, behind reverse
/// proxies and under a web root, with the account's own permissions: the
/// server decides what each call may do.
class TvhClient {
  TvhClient(this.source, {TvhTransport? transport})
      : _address = TvhAddress.parse(source.address),
        _transport = transport ?? IoTvhTransport(allowInsecure: source.allowInsecureCerts);

  final SourceConfig source;
  final TvhTransport _transport;
  TvhAddress _address;

  TvhAddress get address => _address;
  String get user => source.username;
  String get pass => source.password;

  void close() => _transport.close();

  Map<String, String> get _authHeaders => user.isEmpty
      ? const <String, String>{}
      : <String, String>{
          HttpHeaders.authorizationHeader:
              'Basic ${base64Encode(utf8.encode('$user:$pass'))}',
        };

  /// Typing `http://tv.example.com` in front of a server that sends
  /// everything to https makes the login fail, because a redirect drops the
  /// password. Ask once, without credentials, where the server really lives.
  Future<void> followUpgrade() async {
    const asked = '/api/serverinfo';
    try {
      final response = await _transport.send(
        'GET',
        _address.uri(asked),
        timeout: const Duration(seconds: 8),
      );
      if (response.statusCode < 300 || response.statusCode >= 400) {
        return;
      }
      final moved = upgradedAddress(_address, response.location, asked);
      if (moved != null) {
        _address = moved;
      }
    } catch (_) {
      // The real call that follows reports the actual problem.
    }
  }

  /// The address a server redirected us to, when it is the same host (an
  /// http to https upgrade, a proxy moving the web root...).
  static TvhAddress? upgradedAddress(
    TvhAddress current,
    String? location,
    String asked,
  ) {
    if (location == null || location.isEmpty) {
      return null;
    }
    final url = Uri.tryParse(location);
    if (url == null || url.host.isEmpty) {
      return null;
    }
    if (url.host.toLowerCase() != current.host.toLowerCase()) {
      return null;
    }
    final scheme = url.scheme.toLowerCase();
    if (scheme != 'http' && scheme != 'https') {
      return null;
    }
    final tls = scheme == 'https';
    final path = url.path;
    if (!path.endsWith(asked)) {
      return null;
    }
    var webroot = path.substring(0, path.length - asked.length);
    while (webroot.endsWith('/')) {
      webroot = webroot.substring(0, webroot.length - 1);
    }
    return TvhAddress(
      tls: tls,
      host: current.host,
      port: url.hasPort ? url.port : (tls ? 443 : 80),
      webroot: webroot,
    );
  }

  Future<TvhResponse> _send(
    String method,
    String path, {
    Map<String, String>? query,
    Map<String, String>? form,
    Duration? timeout,
  }) async {
    try {
      return await _transport.send(
        method,
        _address.uri(path, query),
        form: form,
        headers: _authHeaders,
        timeout: timeout,
      );
    } on TimeoutException {
      throw const TvhException(
        'The server did not answer in time.',
        kind: TvhFailure.timeout,
      );
    } on HandshakeException catch (error) {
      throw TvhException(
        'The server\'s certificate is not trusted (${error.message}). '
        'Turn on "Allow self-signed certificates" if you trust this server.',
        kind: TvhFailure.tls,
      );
    } on TlsException catch (error) {
      throw TvhException(
        'The secure connection failed (${error.message}). '
        'If the server uses a self-signed certificate, allow it in the server settings.',
        kind: TvhFailure.tls,
      );
    } on SocketException catch (error) {
      final text = '${error.message} ${error.osError?.message ?? ''}'.toLowerCase();
      if (text.contains('failed host lookup') ||
          text.contains('name or service not known') ||
          text.contains('no address associated') ||
          text.contains('nodename nor servname')) {
        throw TvhException(
          'Could not resolve the host name "${_address.host}". Check the '
          'spelling and type only the address, for example tv.example.com.',
          kind: TvhFailure.dns,
        );
      }
      throw TvhException(
        'Could not connect to ${_address.baseUrl}: ${error.message}',
        kind: TvhFailure.connect,
      );
    } on HttpException catch (error) {
      throw TvhException(
        'HTTP error: ${error.message}',
        kind: TvhFailure.connect,
      );
    }
  }

  static String statusMessage(int code) => switch (code) {
        401 => 'Wrong username or password.',
        403 => 'Your account is not allowed to do this on the server.',
        404 => 'The server does not know this item (the address may be wrong, '
            'or the item is gone).',
        _ => 'The server answered HTTP $code.',
      };

  Future<dynamic> _json(String path, {Map<String, String>? query}) async {
    final response = await _send('GET', path, query: query);
    if (response.statusCode != 200) {
      throw TvhException(
        statusMessage(response.statusCode),
        kind: TvhFailure.http,
        statusCode: response.statusCode,
      );
    }
    try {
      return jsonDecode(response.body);
    } on FormatException catch (error) {
      throw TvhException(
        'This does not look like a Tvheadend server (the answer was not JSON): '
        '${error.message}',
      );
    }
  }

  Future<void> _action(String path, Map<String, String> form) async {
    final response = await _send('POST', path, form: form);
    if (response.statusCode != 200) {
      // Tvheadend usually says why in the body ("Invalid argument"...).
      final said = response.body.replaceAll(RegExp(r'<[^>]*>'), ' ').trim();
      final detail = said.isEmpty
          ? ''
          : ' (${said.length > 160 ? said.substring(0, 160) : said})';
      throw TvhException(
        '${statusMessage(response.statusCode)} [$path]$detail',
        kind: TvhFailure.http,
        statusCode: response.statusCode,
      );
    }
  }

  /// Only the status code; the body is not read.
  Future<int> statusOf(String path) async =>
      (await _send('GET', path, timeout: const Duration(seconds: 15))).statusCode;

  // ---- identity and permissions ------------------------------------------

  Future<TvhServerInfo> serverInfo() async {
    final json = await _json('/api/serverinfo');
    return parseServerInfo(json);
  }

  /// `config/capabilities` needs the web interface privilege, so any usable
  /// account gets 200. `config/load` needs administrator rights.
  Future<TvhPermissions> probe() async {
    final caps = await statusOf('/api/config/capabilities');
    switch (caps) {
      case 200:
        break;
      case 401:
        throw const TvhException(
          'Wrong username or password.',
          kind: TvhFailure.http,
          statusCode: 401,
        );
      case 403:
        throw const TvhException(
          'This account has no "Web interface" permission on the server.',
          kind: TvhFailure.http,
          statusCode: 403,
        );
      default:
        throw TvhException(
          'This does not look like a Tvheadend server (HTTP $caps). '
          'Check the address, the port and the web root.',
          kind: TvhFailure.http,
          statusCode: caps,
        );
    }
    final load = await statusOf('/api/config/load');
    return TvhPermissions(admin: load == 200);
  }

  /// Names of the stream profiles this account may use.
  Future<List<String>> streamProfiles() async {
    try {
      final json = await _json('/api/profile/list');
      return <String>[
        for (final entry in entriesOf(json))
          if (str(entry, 'val').isNotEmpty) str(entry, 'val'),
      ];
    } on TvhException {
      return const <String>[];
    }
  }

  // ---- channels and guide -------------------------------------------------

  Future<List<Map<String, dynamic>>> rawTags() async =>
      entriesOf(await _json('/api/channeltag/grid', query: const <String, String>{
        'start': '0',
        'limit': '1000',
      }));

  Future<List<Map<String, dynamic>>> rawChannels() async =>
      entriesOf(await _json('/api/channel/grid', query: const <String, String>{
        'start': '0',
        'limit': '10000',
      }));

  /// Upcoming and running events, soonest first, up to [until]. Pages of
  /// [pageSize] keep memory and response sizes sane on servers with a week of
  /// guide for hundreds of channels.
  Future<List<Map<String, dynamic>>> rawEvents({
    required DateTime until,
    int pageSize = 4000,
    int maxEvents = 250000,
  }) async {
    final untilSeconds = until.millisecondsSinceEpoch ~/ 1000;
    final out = <Map<String, dynamic>>[];
    var start = 0;
    while (true) {
      final page = entriesOf(
        await _json('/api/epg/events/grid', query: <String, String>{
          'start': '$start',
          'limit': '$pageSize',
          'sort': 'start',
          'dir': 'ASC',
        }),
      );
      out.addAll(page);
      if (page.length < pageSize || out.length >= maxEvents) {
        break;
      }
      if (integer(page.last, 'start') > untilSeconds) {
        break;
      }
      start += page.length;
    }
    return out;
  }

  /// Everything the server has for one channel, for the channel's own guide.
  Future<List<Programme>> epgForChannel(String channelUuid, {int limit = 300}) async {
    final json = await _json('/api/epg/events/grid', query: <String, String>{
      'channel': channelUuid,
      'limit': '$limit',
      'sort': 'start',
      'dir': 'ASC',
    });
    return _programmes(json);
  }

  /// Server-side guide search. [fulltext] also searches descriptions.
  Future<List<Programme>> searchEpg(
    String text, {
    bool fulltext = false,
    int limit = 100,
  }) async {
    final json = await _json('/api/epg/events/grid', query: <String, String>{
      'title': text,
      'limit': '$limit',
      'sort': 'start',
      'dir': 'ASC',
      if (fulltext) 'fulltext': '1',
    });
    return _programmes(json);
  }

  List<Programme> _programmes(dynamic json) {
    final out = <Programme>[];
    for (final entry in entriesOf(json)) {
      final programme = programmeFromEvent(entry, imageResolver: _imageFor);
      if (programme != null) {
        out.add(programme);
      }
    }
    return out;
  }

  /// Turns raw event rows (see [rawEvents]) into programmes grouped by channel.
  Map<String, List<Programme>> groupEvents(List<Map<String, dynamic>> events) {
    final byChannel = <String, List<Programme>>{};
    for (final entry in events) {
      final programme = programmeFromEvent(entry, imageResolver: _imageFor);
      if (programme != null) {
        byChannel.putIfAbsent(programme.channelId, () => <Programme>[]).add(programme);
      }
    }
    for (final list in byChannel.values) {
      list.sort((a, b) => a.start.compareTo(b.start));
    }
    return byChannel;
  }

  String? _imageFor(String? source) =>
      _address.imageUrl(source, user: user, pass: pass);

  String? imageFor(String? source) => _imageFor(source);

  String streamUrl(String uuid) =>
      _address.streamUrl(uuid, user: user, pass: pass, profile: source.profile);

  String recordingUrl(String uuid) =>
      _address.dvrUrl(uuid, user: user, pass: pass);

  // ---- recordings ---------------------------------------------------------

  Future<List<TvhRecording>> recordings(RecordingKind kind) async {
    final path = switch (kind) {
      RecordingKind.upcoming => '/api/dvr/entry/grid_upcoming',
      RecordingKind.finished => '/api/dvr/entry/grid_finished',
      RecordingKind.failed => '/api/dvr/entry/grid_failed',
    };
    final json = await _json(path, query: const <String, String>{
      'start': '0',
      'limit': '10000',
    });
    return <TvhRecording>[
      for (final entry in entriesOf(json)) recordingFromJson(entry, imageResolver: _imageFor),
    ];
  }

  /// Uuid of the default recording profile (the one with an empty name),
  /// else the first one.
  Future<String> defaultDvrConfig() async {
    final entries = entriesOf(await _json('/api/dvr/config/grid'));
    for (final entry in entries) {
      if (str(entry, 'name').isEmpty && str(entry, 'uuid').isNotEmpty) {
        return str(entry, 'uuid');
      }
    }
    if (entries.isNotEmpty && str(entries.first, 'uuid').isNotEmpty) {
      return str(entries.first, 'uuid');
    }
    throw const TvhException('The server has no recording profile.');
  }

  /// The recording profile to use, or empty to let the server pick its
  /// default. Plain users often may not list profiles, and the server then
  /// falls back to the default by itself.
  Future<String> _configOrDefault() async {
    try {
      return await defaultDvrConfig();
    } on TvhException {
      return '';
    }
  }

  Future<void> recordEvent(int eventId) async {
    final config = await _configOrDefault();
    await _action('/api/dvr/entry/create_by_event', <String, String>{
      if (config.isNotEmpty) 'config_uuid': config,
      'event_id': '$eventId',
    });
  }

  /// Record every future showing of this programme's series.
  Future<void> recordSeries(int eventId) async {
    final config = await _configOrDefault();
    await _action('/api/dvr/autorec/create_by_series', <String, String>{
      if (config.isNotEmpty) 'config_uuid': config,
      'event_id': '$eventId',
    });
  }

  /// Record a channel right now for [minutes], a one-off timer.
  Future<void> recordNow(String channelUuid, String title, int minutes) async {
    final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    final config = await _configOrDefault();
    final conf = jsonEncode(<String, dynamic>{
      'start': now,
      'stop': now + minutes * 60,
      'channel': channelUuid,
      'title': <String, String>{'eng': title},
      'enabled': true,
      if (config.isNotEmpty) 'config_name': config,
    });
    await _action('/api/dvr/entry/create', <String, String>{'conf': conf});
  }

  /// Stops a running recording gracefully, keeping the file.
  Future<void> stopRecording(String uuid) =>
      _action('/api/dvr/entry/stop', <String, String>{'uuid': uuid});

  /// Deletes a scheduled recording, or aborts a running one.
  Future<void> cancelRecording(String uuid) =>
      _action('/api/dvr/entry/cancel', <String, String>{'uuid': uuid});

  /// Removes a finished recording from storage.
  Future<void> removeRecording(String uuid) =>
      _action('/api/dvr/entry/remove', <String, String>{'uuid': uuid});

  // ---- status (administrators) -------------------------------------------

  Future<List<TvhInputStatus>> inputs() async {
    final json = await _json('/api/status/inputs');
    return <TvhInputStatus>[
      for (final e in entriesOf(json))
        TvhInputStatus(
          input: str(e, 'input'),
          stream: str(e, 'stream'),
          subs: integer(e, 'subs'),
          signal: maybeInt(e, 'signal'),
          signalScale: integer(e, 'signal_scale'),
          snr: maybeInt(e, 'snr'),
          snrScale: integer(e, 'snr_scale'),
          ber: maybeInt(e, 'ber'),
          unc: maybeInt(e, 'unc'),
          bps: maybeInt(e, 'bps'),
        ),
    ];
  }

  Future<List<TvhSubscription>> subscriptions() async {
    final json = await _json('/api/status/subscriptions');
    return <TvhSubscription>[
      for (final e in entriesOf(json))
        TvhSubscription(
          title: str(e, 'title'),
          channel: str(e, 'channel'),
          service: str(e, 'service'),
          state: str(e, 'state'),
          errors: integer(e, 'errors'),
          user: str(e, 'username'),
          client: str(e, 'client'),
          profile: str(e, 'profile'),
          bytesIn: integer(e, 'in'),
          bytesOut: integer(e, 'out'),
        ),
    ];
  }

  Future<List<TvhConnection>> connections() async {
    final json = await _json('/api/status/connections');
    return <TvhConnection>[
      for (final e in entriesOf(json))
        TvhConnection(
          user: str(e, 'user'),
          peer: str(e, 'peer'),
          kind: str(e, 'type'),
          started: DateTime.fromMillisecondsSinceEpoch(
            integer(e, 'started') * 1000,
          ),
        ),
    ];
  }

  /// Signal for the stream of [channelName], from the tuner status. Needs an
  /// administrator account; any other account gets `null`.
  Future<TvhSignal?> signalFor(String channelName) async {
    try {
      final inputs = await this.inputs();
      final subs = await subscriptions();
      TvhSubscription? mine;
      for (final sub in subs) {
        if (sub.channel == channelName) {
          mine = sub;
          break;
        }
      }
      final input = TvhSignal.pickInput(inputs, mine);
      if (input == null) {
        return null;
      }
      return TvhSignal.fromInput(input);
    } on TvhException {
      return null;
    }
  }
}

// ---- JSON helpers (public so tests can exercise them) ----------------------

List<Map<String, dynamic>> entriesOf(dynamic json) {
  if (json is Map) {
    final entries = json['entries'];
    if (entries is List) {
      return <Map<String, dynamic>>[
        for (final entry in entries)
          if (entry is Map) entry.cast<String, dynamic>(),
      ];
    }
  }
  return const <Map<String, dynamic>>[];
}

String str(Map<String, dynamic> map, String key) {
  final value = map[key];
  if (value == null) {
    return '';
  }
  return value is String ? value : value.toString();
}

int integer(Map<String, dynamic> map, String key) => maybeInt(map, key) ?? 0;

int? maybeInt(Map<String, dynamic> map, String key) {
  final value = map[key];
  if (value is int) {
    return value;
  }
  if (value is num) {
    return value.toInt();
  }
  if (value is String) {
    return int.tryParse(value);
  }
  return null;
}

bool flag(Map<String, dynamic> map, String key, {bool fallback = true}) {
  final value = map[key];
  if (value is bool) {
    return value;
  }
  if (value is num) {
    return value != 0;
  }
  return fallback;
}

TvhServerInfo parseServerInfo(dynamic json) {
  if (json is! Map) {
    return const TvhServerInfo();
  }
  final map = json.cast<String, dynamic>();
  final name = str(map, 'name');
  return TvhServerInfo(
    name: name.isEmpty ? 'Tvheadend' : name,
    version: str(map, 'sw_version'),
    apiVersion: integer(map, 'api_version'),
  );
}

/// "S02E05" from the broadcaster's own text if there is one, else from the
/// season and episode numbers.
String episodeLabel(String onscreen, int? season, int? episode) {
  final text = onscreen.trim();
  if (text.isNotEmpty) {
    return text;
  }
  final s = (season ?? 0) > 0 ? season : null;
  final e = (episode ?? 0) > 0 ? episode : null;
  String two(int n) => n.toString().padLeft(2, '0');
  if (s != null && e != null) {
    return 'S${two(s)}E${two(e)}';
  }
  if (e != null) {
    return 'E$e';
  }
  if (s != null) {
    return 'S${two(s)}';
  }
  return '';
}

/// One line of facts: year, categories, rating, age.
String factsLine(int? year, List<String> categories, int? stars, int? age) {
  final parts = <String>[
    if ((year ?? 0) > 0) '$year',
    if (categories.any((c) => c.trim().isNotEmpty))
      categories.map((c) => c.trim()).where((c) => c.isNotEmpty).join(', '),
    if ((stars ?? 0) > 0) '★ ${(stars! / 10).toStringAsFixed(1)}',
    if ((age ?? 0) > 0) '$age+',
  ];
  return parts.join(' · ');
}

/// Tvheadend sends credits as `{"Some Name": "actor", ...}`; group the names
/// by role.
String creditsLine(dynamic credits) {
  if (credits is! Map || credits.isEmpty) {
    return '';
  }
  const labels = <String, String>{
    'director': 'Director',
    'actor': 'Cast',
    'presenter': 'Presenter',
    'writer': 'Writer',
    'producer': 'Producer',
  };
  const order = <String>['Director', 'Writer', 'Presenter', 'Cast', 'Producer'];
  final roles = <String, List<String>>{};
  credits.forEach((name, role) {
    final raw = role is String ? role.trim() : '';
    final key = raw.isEmpty ? 'actor' : raw;
    final label = labels[key] ?? key;
    roles.putIfAbsent(label, () => <String>[]).add('$name');
  });
  final keys = roles.keys.toList()
    ..sort((a, b) {
      int rank(String label) {
        final index = order.indexOf(label);
        return index < 0 ? order.length : index;
      }

      return rank(a).compareTo(rank(b));
    });
  return keys.map((label) => '$label: ${roles[label]!.take(6).join(', ')}').join('  ·  ');
}

typedef ImageResolver = String? Function(String? source);

/// One EPG event as a [Programme]. Returns null for events without a channel
/// or with an empty time span.
Programme? programmeFromEvent(
  Map<String, dynamic> event, {
  ImageResolver? imageResolver,
}) {
  final channel = str(event, 'channelUuid');
  final start = integer(event, 'start');
  final stop = integer(event, 'stop');
  if (channel.isEmpty || stop <= start) {
    return null;
  }
  final categories = <String>[
    for (final item in (event['category'] is List ? event['category'] as List : const <dynamic>[]))
      if (item is String && item.trim().isNotEmpty) item.trim(),
  ];
  final description = str(event, 'description');
  final summary = str(event, 'summary');
  final subtitle = str(event, 'subtitle');
  final image = str(event, 'image');
  final dvrUuid = str(event, 'dvrUuid');
  final dvrState = str(event, 'dvrState');
  final episode = episodeLabel(
    str(event, 'episodeOnscreen'),
    maybeInt(event, 'seasonNumber'),
    maybeInt(event, 'episodeNumber'),
  );
  final facts = factsLine(
    maybeInt(event, 'copyright_year'),
    categories,
    maybeInt(event, 'starRating'),
    maybeInt(event, 'ageRating'),
  );
  final credits = creditsLine(event['credits']);
  final title = str(event, 'title').trim();
  return Programme(
    channelId: channel,
    start: DateTime.fromMillisecondsSinceEpoch(start * 1000),
    stop: DateTime.fromMillisecondsSinceEpoch(stop * 1000),
    title: title.isEmpty ? '—' : title,
    subTitle: subtitle.isNotEmpty
        ? subtitle
        : (summary.isNotEmpty && description.isNotEmpty && summary != description
            ? summary
            : null),
    description: description.isNotEmpty
        ? description
        : (summary.isNotEmpty ? summary : null),
    categories: categories,
    iconUrl: image.isEmpty ? null : (imageResolver != null ? imageResolver(image) : image),
    episode: episode.isEmpty ? null : episode,
    eventId: maybeInt(event, 'eventId'),
    dvrUuid: dvrUuid.isEmpty ? null : dvrUuid,
    dvrState: dvrState.isEmpty ? null : dvrState,
    facts: facts.isEmpty ? null : facts,
    credits: credits.isEmpty ? null : credits,
  );
}

TvhRecording recordingFromJson(
  Map<String, dynamic> entry, {
  ImageResolver? imageResolver,
}) {
  final image = str(entry, 'image');
  return TvhRecording(
    uuid: str(entry, 'uuid'),
    channelUuid: str(entry, 'channel'),
    channelName: str(entry, 'channelname'),
    title: str(entry, 'disp_title'),
    subtitle: str(entry, 'disp_subtitle'),
    description: str(entry, 'disp_description'),
    start: DateTime.fromMillisecondsSinceEpoch(integer(entry, 'start') * 1000),
    stop: DateTime.fromMillisecondsSinceEpoch(integer(entry, 'stop') * 1000),
    status: str(entry, 'status'),
    schedStatus: str(entry, 'sched_status'),
    fileSize: integer(entry, 'filesize'),
    errors: integer(entry, 'errors'),
    enabled: flag(entry, 'enabled'),
    imageSource: image.isEmpty ? null : (imageResolver?.call(image) ?? image),
  );
}

/// Channels as the loader builds them: enabled ones only, grouped by their
/// first tag, sorted by number then name.
List<Channel> channelsFromJson({
  required String sourceId,
  required List<Map<String, dynamic>> channels,
  required List<Map<String, dynamic>> tags,
  required TvhClient client,
}) {
  final tagList = <({String uuid, String name, int index})>[
    for (final tag in tags)
      if (flag(tag, 'enabled') && str(tag, 'uuid').isNotEmpty)
        (uuid: str(tag, 'uuid'), name: str(tag, 'name'), index: integer(tag, 'index')),
  ]..sort((a, b) {
      final byIndex = a.index.compareTo(b.index);
      return byIndex != 0 ? byIndex : a.name.toLowerCase().compareTo(b.name.toLowerCase());
    });
  final tagOrder = <String, int>{
    for (var i = 0; i < tagList.length; i++) tagList[i].uuid: i,
  };
  final tagNames = <String, String>{for (final tag in tagList) tag.uuid: tag.name};

  final result = <Channel>[];
  for (final entry in channels) {
    if (!flag(entry, 'enabled')) {
      continue;
    }
    final uuid = str(entry, 'uuid');
    if (uuid.isEmpty) {
      continue;
    }
    final rawTags = entry['tags'] is List ? (entry['tags'] as List).whereType<String>() : const <String>[];
    final known = rawTags.where(tagOrder.containsKey).toList()
      ..sort((a, b) => tagOrder[a]!.compareTo(tagOrder[b]!));
    final names = <String>[for (final id in known) tagNames[id]!];
    final number = integer(entry, 'number');
    final icon = str(entry, 'icon_public_url').isNotEmpty
        ? str(entry, 'icon_public_url')
        : str(entry, 'icon');
    result.add(
      Channel(
        id: uuid,
        sourceId: sourceId,
        name: str(entry, 'name').isEmpty ? uuid : str(entry, 'name'),
        number: number > 0 ? '$number' : '',
        url: client.streamUrl(uuid),
        logoUrl: client.imageFor(icon),
        group: names.isEmpty ? null : names.first,
        tags: names,
        isRadio: names.any(looksLikeRadioTag),
      ),
    );
  }
  result.sort((a, b) {
    final an = int.tryParse(a.number) ?? 0;
    final bn = int.tryParse(b.number) ?? 0;
    final aZero = an == 0 ? 1 : 0;
    final bZero = bn == 0 ? 1 : 0;
    if (aZero != bZero) {
      return aZero.compareTo(bZero);
    }
    if (an != bn) {
      return an.compareTo(bn);
    }
    return a.name.toLowerCase().compareTo(b.name.toLowerCase());
  });
  return result;
}
