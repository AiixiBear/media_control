import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../api/media_control_api.dart';
import '../models/media.dart';
import 'home_assistant.dart';
import 'server_settings.dart';
import 'web_ui.dart';

class MediaControlServer {
  static const String homeAssistantEntityId = 'media_player.media_control_hub';

  MediaControlServer({required this.api, ServerSettings? settings})
    : _settings = settings ?? const ServerSettings();

  final MediaControlApi api;
  HttpServer? _server;
  ServerSettings _settings;
  final Set<HttpResponse> _sseClients = <HttpResponse>{};
  Timer? _sseTimer;

  bool get isRunning => _server != null;

  int? get port => _server?.port;

  void updateSettings(ServerSettings settings) {
    _settings = settings;
  }

  Future<Uri> start({int port = 8080}) async {
    if (_server != null) {
      return Uri.parse('http://127.0.0.1:${_server!.port}');
    }

    final server = await HttpServer.bind(
      _resolveAddress(_settings.normalizedListenInterface),
      port,
    );
    server.listen(
      _handleRequest,
      onError: (Object error, StackTrace stackTrace) {
        stderr.writeln('MediaControlServer error: $error\n$stackTrace');
      },
    );
    _server = server;
    // Push a fresh snapshot to SSE clients once a second. Control
    // commands also trigger an immediate push via _notifySseClients().
    _sseTimer?.cancel();
    _sseTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      _notifySseClients();
    });
    return Uri.parse('http://127.0.0.1:${server.port}');
  }

  InternetAddress _resolveAddress(String interfaceName) {
    final normalized = interfaceName.trim();
    if (normalized.isEmpty || normalized == '0.0.0.0' || normalized == 'all') {
      return InternetAddress.anyIPv4;
    }
    return InternetAddress(normalized);
  }

  Future<void> stop() async {
    _sseTimer?.cancel();
    _sseTimer = null;
    for (final client in _sseClients.toList()) {
      try {
        await client.close();
      } catch (_) {
        // Client already gone; nothing to clean up.
      }
    }
    _sseClients.clear();
    final server = _server;
    _server = null;
    if (server != null) {
      await server.close(force: true);
    }
  }

  /// Sends the current snapshot to every connected SSE client.
  /// Clients that already disconnected are dropped silently.
  Future<void> _notifySseClients() async {
    if (_sseClients.isEmpty) {
      return;
    }
    MediaSnapshot snapshot;
    try {
      snapshot = await api.getSnapshot();
    } catch (_) {
      return;
    }
    final payload = 'data: ${jsonEncode(snapshot.toJson())}\n\n';
    for (final client in _sseClients.toList()) {
      try {
        client.write(payload);
        await client.flush();
      } catch (_) {
        _sseClients.remove(client);
      }
    }
  }

  Future<void> _handleRequest(HttpRequest request) async {
    _applyCorsHeaders(request.response);

    if (request.method == 'OPTIONS') {
      request.response.statusCode = HttpStatus.noContent;
      await request.response.close();
      return;
    }

    final normalizedPath = _normalizePath(request.uri.path);
    if (!_settings.isAuthorized(request)) {
      request.response.statusCode = HttpStatus.unauthorized;
      request.response.headers.set(
        HttpHeaders.wwwAuthenticateHeader,
        'Bearer realm="media_control"',
      );
      _writeJson(request.response, <String, dynamic>{
        'error':
            '需要驗證：請在網址使用密碼前綴，或帶 Authorization: Bearer <密碼> / X-Api-Key: <密碼>',
      });
      return;
    }

    try {
      if (normalizedPath == '/' && request.method == 'GET') {
        request.response.headers.contentType = ContentType.html;
        request.response.write(
          buildWebUiHtml(updateMode: _settings.normalizedWebUiUpdateMode),
        );
        await request.response.close();
        return;
      }

      if (normalizedPath == '/api/auth/check' && request.method == 'GET') {
        _writeJson(request.response, <String, dynamic>{
          'authenticated': true,
          'auth_required': _settings.authRequired,
        });
        return;
      }

      if (normalizedPath == '/api/events' && request.method == 'GET') {
        final response = request.response;
        // bufferOutput must be false, otherwise Dart buffers the event
        // body until the response is closed (which never happens for SSE)
        // and no event ever reaches the client, even after flush().
        response.bufferOutput = false;
        response.headers.contentType = ContentType.parse(
          'text/event-stream; charset=utf-8',
        );
        response.headers.set(HttpHeaders.cacheControlHeader, 'no-cache');
        response.headers.set('connection', 'keep-alive');
        _sseClients.add(response);
        // Send the current snapshot immediately, then every second via
        // the broadcast timer (and right after each control command).
        await _notifySseClients();
        // Keep the connection open until the client disconnects; the
        // response is closed by stop() or by a write failure in
        // _notifySseClients(). Do not close it here.
        return;
      }

      if (normalizedPath == '/api/state' && request.method == 'GET') {
        final snapshot = await api.getSnapshot();
        _writeJson(request.response, snapshot.toJson());
        return;
      }

      if (normalizedPath == '/api/home-assistant/media-player' &&
          request.method == 'GET') {
        final snapshot = await api.getSnapshot();
        _writeJson(
          request.response,
          snapshot.toHomeAssistantMediaPlayerJson(homeAssistantEntityId),
        );
        return;
      }

      if (normalizedPath == '/api/home-assistant/config' &&
          request.method == 'GET') {
        final snapshot = await api.getSnapshot();
        _writeJson(
          request.response,
          snapshot.toHomeAssistantConfigJson(
            homeAssistantEntityId,
            authRequired: _settings.authRequired,
          ),
        );
        return;
      }

      if (normalizedPath == '/api/home-assistant/media-player/command' &&
          request.method == 'POST') {
        final body = await utf8.decoder.bind(request).join();
        final payload = body.isEmpty
            ? <String, dynamic>{}
            : jsonDecode(body) as Map<String, dynamic>;
        final action = extractHomeAssistantAction(payload);
        final packageName = extractStringField(payload, <String>[
          'packageName',
          'package_name',
        ]);
        final positionMs = extractSeekPositionMs(payload);

        await _executeHomeAssistantAction(
          action: action,
          packageName: packageName,
          positionMs: positionMs,
        );

        _writeJson(request.response, <String, dynamic>{'ok': true});
        await _notifySseClients();
        return;
      }

      if (normalizedPath.startsWith('/api/control/') &&
          request.method == 'POST') {
        final action = normalizedPath.split('/').last;
        final body = await utf8.decoder.bind(request).join();
        final payload = body.isEmpty
            ? <String, dynamic>{}
            : jsonDecode(body) as Map<String, dynamic>;
        final packageName = payload['packageName'] as String?;

        switch (action) {
          case 'play':
            await api.play(packageName: packageName);
            break;
          case 'pause':
            await api.pause(packageName: packageName);
            break;
          case 'next':
            await api.next(packageName: packageName);
            break;
          case 'previous':
            await api.previous(packageName: packageName);
            break;
          case 'seek':
          case 'seekTo':
            final positionMs = extractSeekPositionMs(payload, required: true)!;
            await api.seekTo(
              packageName: packageName,
              position: Duration(milliseconds: positionMs),
            );
            break;
          default:
            request.response.statusCode = HttpStatus.notFound;
            _writeJson(request.response, <String, dynamic>{
              'error': 'Unknown action: $action',
            });
            return;
        }

        _writeJson(request.response, <String, dynamic>{'ok': true});
        await _notifySseClients();
        return;
      }

      request.response.statusCode = HttpStatus.notFound;
      _writeJson(request.response, <String, dynamic>{'error': '找不到頁面'});
    } on FormatException catch (error) {
      request.response.statusCode = HttpStatus.badRequest;
      _writeJson(request.response, <String, dynamic>{'error': error.message});
    } on ArgumentError catch (error) {
      request.response.statusCode = HttpStatus.badRequest;
      _writeJson(request.response, <String, dynamic>{
        'error': error.message ?? error.toString(),
      });
    } catch (error) {
      request.response.statusCode = HttpStatus.internalServerError;
      _writeJson(request.response, <String, dynamic>{
        'error': error.toString(),
      });
    }
  }

  String _normalizePath(String path) {
    if (_settings.normalizedPassword.isEmpty) {
      return path.isEmpty ? '/' : path;
    }

    final prefix = _settings.routePrefix;
    if (path == prefix || path == '$prefix/') {
      return '/';
    }
    if (path.startsWith('$prefix/')) {
      return path.substring(prefix.length);
    }
    return path.isEmpty ? '/' : path;
  }

  void _applyCorsHeaders(HttpResponse response) {
    // No Access-Control-Allow-Origin wildcard: the Web UI is served from
    // this same server, and Home Assistant calls it server-to-server, so
    // cross-origin browser access is not needed. Previously `*` let any
    // website on the LAN call the control API when no password was set.
    response.headers.set(
      HttpHeaders.accessControlAllowHeadersHeader,
      'content-type, authorization, x-api-key',
    );
    response.headers.set(
      HttpHeaders.accessControlAllowMethodsHeader,
      'GET,POST,OPTIONS',
    );
  }

  void _writeJson(HttpResponse response, Map<String, dynamic> data) {
    response.headers.contentType = ContentType.json;
    response.write(jsonEncode(data));
    response.close();
  }

  Future<void> _executeHomeAssistantAction({
    required String action,
    required String? packageName,
    required int? positionMs,
  }) async {
    switch (action) {
      case 'media_play':
      case 'play':
        await api.play(packageName: packageName);
        return;
      case 'media_pause':
      case 'pause':
        await api.pause(packageName: packageName);
        return;
      case 'media_play_pause':
      case 'toggle':
        final snapshot = await api.getSnapshot();
        final activeSession = snapshot.activeSession;
        final targetPackage = packageName ?? activeSession?.packageName;
        if (activeSession?.isPlaying == true) {
          await api.pause(packageName: targetPackage);
        } else {
          await api.play(packageName: targetPackage);
        }
        return;
      case 'media_next_track':
      case 'next':
        await api.next(packageName: packageName);
        return;
      case 'media_previous_track':
      case 'previous':
        await api.previous(packageName: packageName);
        return;
      case 'media_seek':
      case 'seek':
      case 'seekTo':
        if (positionMs == null) {
          throw ArgumentError(
            'Seek action requires positionMs/position/seek_position in payload (root, data, or service_data).',
          );
        }
        await api.seekTo(
          packageName: packageName,
          position: Duration(milliseconds: positionMs),
        );
        return;
      default:
        throw ArgumentError('Unknown Home Assistant action: $action');
    }
  }
}
