import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:media_control/main.dart';

/// A fake [MediaControlApi] that records every control call, so the
/// HTTP tests below can prove a command actually reached the API.
class RecordingFakeMediaControlApi implements MediaControlApi {
  final List<String> calls = <String>[];
  Duration? lastSeekPosition;

  MediaSnapshot _snapshot() {
    return MediaSnapshot(
      listenerEnabled: true,
      sessions: <MediaSessionInfo>[
        MediaSessionInfo(
          packageName: 'com.example.music',
          appName: 'Sample Music',
          title: 'Test Track',
          artist: 'Test Artist',
          album: 'Test Album',
          artworkDataUrl: null,
          durationMs: 240000,
          positionMs: 42000,
          playbackState: 'playing',
          isPlaying: true,
          canPlay: true,
          canPause: true,
          canSkipNext: true,
          canSkipPrevious: true,
          canSeekTo: true,
        ),
      ],
      timestamp: DateTime.fromMillisecondsSinceEpoch(0),
    );
  }

  @override
  Future<MediaSnapshot> getSnapshot() async => _snapshot();

  @override
  Future<void> play({String? packageName}) async {
    calls.add('play:$packageName');
  }

  @override
  Future<void> pause({String? packageName}) async {
    calls.add('pause:$packageName');
  }

  @override
  Future<void> next({String? packageName}) async {
    calls.add('next:$packageName');
  }

  @override
  Future<void> previous({String? packageName}) async {
    calls.add('previous:$packageName');
  }

  @override
  Future<void> seekTo({String? packageName, required Duration position}) async {
    calls.add('seekTo:$packageName');
    lastSeekPosition = position;
  }

  @override
  Future<void> openNotificationSettings() async {}

  @override
  Future<bool> ensureNotificationPermission() async => true;

  @override
  Future<void> startBackgroundProtection() async {}

  @override
  Future<void> updateBackgroundProtectionNotification({String? webUrl}) async {}
}

Future<HttpClientResponse> _request(
  HttpClient client,
  String method,
  Uri uri, {
  Map<String, String>? headers,
  Map<String, dynamic>? jsonBody,
}) async {
  final request = await client.openUrl(method, uri);
  headers?.forEach(request.headers.set);
  if (jsonBody != null) {
    request.headers.contentType = ContentType.json;
    request.write(jsonEncode(jsonBody));
  }
  return request.close();
}

Future<Map<String, dynamic>> _readJson(HttpClientResponse response) async {
  final body = await response.transform(utf8.decoder).join();
  return jsonDecode(body) as Map<String, dynamic>;
}

void main() {
  const token = 'test-token-123456';
  late MediaControlServer server;
  late RecordingFakeMediaControlApi api;
  late HttpClient client;
  late int port;

  setUp(() async {
    api = RecordingFakeMediaControlApi();
    server = MediaControlServer(
      api: api,
      settings: const ServerSettings(password: token),
    );
    final uri = await server.start(port: 0);
    port = uri.port;
    client = HttpClient();
  });

  tearDown(() async {
    client.close(force: true);
    await server.stop();
  });

  Uri url(String path) => Uri.parse('http://127.0.0.1:$port$path');

  test('unauthenticated state requests are rejected with 401', () async {
    final response = await _request(client, 'GET', url('/api/state'));
    expect(response.statusCode, HttpStatus.unauthorized);
    final body = await _readJson(response);
    expect(body['error'], isNotNull);
    expect(api.calls, isEmpty);
  });

  test('a wrong Bearer token is rejected', () async {
    final response = await _request(
      client,
      'GET',
      url('/api/state'),
      headers: <String, String>{'Authorization': 'Bearer wrong-token'},
    );
    expect(response.statusCode, HttpStatus.unauthorized);
  });

  test('a Bearer token grants access to the state API', () async {
    final response = await _request(
      client,
      'GET',
      url('/api/state'),
      headers: <String, String>{'Authorization': 'Bearer $token'},
    );
    expect(response.statusCode, HttpStatus.ok);
    final body = await _readJson(response);
    expect(body['listenerEnabled'], isTrue);
    expect((body['sessions'] as List).length, 1);
  });

  test('an X-Api-Key header grants access to the HA API', () async {
    final response = await _request(
      client,
      'GET',
      url('/api/home-assistant/media-player'),
      headers: <String, String>{'X-Api-Key': token},
    );
    expect(response.statusCode, HttpStatus.ok);
    final body = await _readJson(response);
    expect(body['entity_id'], contains('media_player.media_control_hub'));
    expect(body['state'], 'playing');
  });

  test('the legacy password path prefix still works', () async {
    final response = await _request(client, 'GET', url('/$token/api/state'));
    expect(response.statusCode, HttpStatus.ok);
  });

  test('the HA config endpoint advertises auth (without the token)', () async {
    final response = await _request(
      client,
      'GET',
      url('/api/home-assistant/config'),
      headers: <String, String>{'Authorization': 'Bearer $token'},
    );
    expect(response.statusCode, HttpStatus.ok);
    final body = await _readJson(response);
    expect(body['requires_auth'], isTrue);
    expect(body['auth']['type'], 'bearer');
    // The token itself must never appear in the config response.
    expect(jsonEncode(body), isNot(contains(token)));
  });

  test('the auth-check endpoint reports the auth state', () async {
    final response = await _request(
      client,
      'GET',
      url('/api/auth/check'),
      headers: <String, String>{'Authorization': 'Bearer $token'},
    );
    expect(response.statusCode, HttpStatus.ok);
    final body = await _readJson(response);
    expect(body, <String, dynamic>{
      'authenticated': true,
      'auth_required': true,
    });
  });

  test('HA commands run through the Bearer token', () async {
    final pause = await _request(
      client,
      'POST',
      url('/api/home-assistant/media-player/command'),
      headers: <String, String>{'Authorization': 'Bearer $token'},
      jsonBody: <String, dynamic>{
        'action': 'media_pause',
        'packageName': 'com.example.music',
      },
    );
    expect(pause.statusCode, HttpStatus.ok);
    await pause.transform(utf8.decoder).join();
    expect(api.calls, contains('pause:com.example.music'));

    final seek = await _request(
      client,
      'POST',
      url('/api/home-assistant/media-player/command'),
      headers: <String, String>{'Authorization': 'Bearer $token'},
      jsonBody: <String, dynamic>{
        'action': 'media_seek',
        'service_data': <String, dynamic>{'position': 42},
      },
    );
    expect(seek.statusCode, HttpStatus.ok);
    await seek.transform(utf8.decoder).join();
    expect(api.lastSeekPosition, const Duration(seconds: 42));

    final unknown = await _request(
      client,
      'POST',
      url('/api/home-assistant/media-player/command'),
      headers: <String, String>{'Authorization': 'Bearer $token'},
      jsonBody: <String, dynamic>{'action': 'media_explode'},
    );
    expect(unknown.statusCode, HttpStatus.badRequest);
    await unknown.transform(utf8.decoder).join();
  });

  test('WebUI seek commands run through the Bearer token', () async {
    final response = await _request(
      client,
      'POST',
      url('/api/control/seek'),
      headers: <String, String>{'Authorization': 'Bearer $token'},
      jsonBody: <String, dynamic>{
        'packageName': 'com.example.music',
        'positionMs': 120000,
      },
    );
    expect(response.statusCode, HttpStatus.ok);
    await response.transform(utf8.decoder).join();
    expect(api.calls, contains('seekTo:com.example.music'));
    expect(api.lastSeekPosition, const Duration(milliseconds: 120000));
  });

  test('the Web UI renders the configured update mode', () async {
    final sseResponse = await _request(
      client,
      'GET',
      url('/'),
      headers: <String, String>{'Authorization': 'Bearer $token'},
    );
    expect(sseResponse.statusCode, HttpStatus.ok);
    final sseHtml = await sseResponse.transform(utf8.decoder).join();
    expect(sseHtml, contains("const UPDATE_MODE = 'sse'"));
    // The auth prompt is part of the page so a browser can log in.
    expect(sseHtml, contains('id="authPanel"'));
    expect(sseHtml, contains('需要密碼'));
    // Progress bars are clickable to seek.
    expect(sseHtml, contains('點一下跳轉播放位置'));
  });

  test('WebUI control commands run through the Bearer token', () async {
    final response = await _request(
      client,
      'POST',
      url('/api/control/next'),
      headers: <String, String>{'Authorization': 'Bearer $token'},
      jsonBody: <String, dynamic>{'packageName': 'com.example.music'},
    );
    expect(response.statusCode, HttpStatus.ok);
    await response.transform(utf8.decoder).join();
    expect(api.calls, contains('next:com.example.music'));
  });

  test('SSE streams a snapshot, then the server keeps working', () async {
    final request = await client.getUrl(url('/api/events'));
    request.headers.set('Authorization', 'Bearer $token');
    final response = await request.close();
    expect(response.statusCode, HttpStatus.ok);
    expect(response.headers.contentType?.mimeType, 'text/event-stream');

    final buffer = StringBuffer();
    await for (final chunk
        in response
            .transform(utf8.decoder)
            .timeout(const Duration(seconds: 5))) {
      buffer.write(chunk);
      if (buffer.toString().contains('\n\n')) {
        break;
      }
    }
    final firstEvent = buffer.toString();
    expect(firstEvent, startsWith('data: '));
    expect(firstEvent, contains('listenerEnabled'));

    // A normal request still works while the SSE stream is open.
    final state = await _request(
      client,
      'GET',
      url('/api/state'),
      headers: <String, String>{'Authorization': 'Bearer $token'},
    );
    expect(state.statusCode, HttpStatus.ok);
    await state.transform(utf8.decoder).join();
  });

  test('a polling-mode server renders polling HTML', () async {
    final pollingServer = MediaControlServer(
      api: api,
      settings: const ServerSettings(
        password: token,
        webUiUpdateMode: 'polling',
      ),
    );
    final pollingUri = await pollingServer.start(port: 0);
    final pollingClient = HttpClient();
    try {
      final response = await _request(
        pollingClient,
        'GET',
        Uri.parse('http://127.0.0.1:${pollingUri.port}/'),
        headers: <String, String>{'Authorization': 'Bearer $token'},
      );
      expect(response.statusCode, HttpStatus.ok);
      final html = await response.transform(utf8.decoder).join();
      expect(html, contains("const UPDATE_MODE = 'polling'"));
    } finally {
      pollingClient.close(force: true);
      await pollingServer.stop();
    }
  });

  test('without a password the server stays open (legacy behaviour)', () async {
    final openServer = MediaControlServer(api: api);
    final uri = await openServer.start(port: 0);
    final openClient = HttpClient();
    try {
      final response = await _request(
        openClient,
        'GET',
        Uri.parse('http://127.0.0.1:${uri.port}/api/state'),
      );
      expect(response.statusCode, HttpStatus.ok);
      await response.transform(utf8.decoder).join();

      final check = await _request(
        openClient,
        'GET',
        Uri.parse('http://127.0.0.1:${uri.port}/api/auth/check'),
      );
      final body = await _readJson(check);
      expect(body['auth_required'], isFalse);
    } finally {
      openClient.close(force: true);
      await openServer.stop();
    }
  });
}
