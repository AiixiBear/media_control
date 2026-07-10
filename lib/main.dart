import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'device_util.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await DeviceUtil.init();
  runApp(const MediaControlApp());
}

abstract class MediaControlApi {
  Future<MediaSnapshot> getSnapshot();
  Future<void> play({String? packageName});
  Future<void> pause({String? packageName});
  Future<void> next({String? packageName});
  Future<void> previous({String? packageName});
  Future<void> seekTo({String? packageName, required Duration position});
  Future<void> openNotificationSettings();
  Future<bool> ensureNotificationPermission();
  Future<void> startBackgroundProtection();
  Future<void> updateBackgroundProtectionNotification({String? webUrl});
}

class PlatformMediaControlApi implements MediaControlApi {
  const PlatformMediaControlApi();

  static const MethodChannel _channel = MethodChannel('media_control/media');

  @override
  Future<MediaSnapshot> getSnapshot() async {
    final dynamic result = await _channel.invokeMethod<dynamic>('getMediaSnapshot');
    if (result is Map) {
      return MediaSnapshot.fromMap(result.cast<String, dynamic>());
    }
    return MediaSnapshot.empty();
  }

  @override
  Future<void> play({String? packageName}) => _sendControl('play', packageName: packageName);

  @override
  Future<void> pause({String? packageName}) => _sendControl('pause', packageName: packageName);

  @override
  Future<void> next({String? packageName}) => _sendControl('next', packageName: packageName);

  @override
  Future<void> previous({String? packageName}) => _sendControl('previous', packageName: packageName);

  @override
  Future<void> seekTo({String? packageName, required Duration position}) => _sendControl(
        'seekTo',
        packageName: packageName,
        extra: <String, dynamic>{'positionMs': position.inMilliseconds},
      );

  @override
  Future<void> openNotificationSettings() async {
    await _channel.invokeMethod<void>('openNotificationSettings');
  }

  @override
  Future<bool> ensureNotificationPermission() async {
    final dynamic result = await _channel.invokeMethod<dynamic>('ensureNotificationPermission');
    return result is bool ? result : false;
  }

  @override
  Future<void> startBackgroundProtection() async {
    await _channel.invokeMethod<void>('startBackgroundProtection');
  }

  @override
  Future<void> updateBackgroundProtectionNotification({String? webUrl}) async {
    await _channel.invokeMethod<void>(
      'updateBackgroundProtectionNotification',
      <String, dynamic>{
        if (webUrl != null) 'webUrl': webUrl,
      },
    );
  }

  Future<void> _sendControl(
    String method, {
    String? packageName,
    Map<String, dynamic> extra = const <String, dynamic>{},
  }) async {
    final payload = <String, dynamic>{
      if (packageName != null) 'packageName': packageName,
      ...extra,
    };
    await _channel.invokeMethod<void>(method, payload);
  }
}

class MediaControlServer {
  static const String homeAssistantEntityId = 'media_player.media_control_hub';

  MediaControlServer({required this.api});

  final MediaControlApi api;
  HttpServer? _server;

  bool get isRunning => _server != null;

  int? get port => _server?.port;

  Future<Uri> start() async {
    if (_server != null) {
      return Uri.parse('http://127.0.0.1:${_server!.port}');
    }

    final server = await HttpServer.bind(InternetAddress.anyIPv4, 8080);
    server.listen(
      _handleRequest,
      onError: (Object error, StackTrace stackTrace) {
        stderr.writeln('MediaControlServer error: $error\n$stackTrace');
      },
    );
    _server = server;
    return Uri.parse('http://127.0.0.1:${server.port}');
  }

  Future<void> stop() async {
    final server = _server;
    _server = null;
    if (server != null) {
      await server.close(force: true);
    }
  }

  Future<void> _handleRequest(HttpRequest request) async {
    _applyCorsHeaders(request.response);

    if (request.method == 'OPTIONS') {
      request.response.statusCode = HttpStatus.noContent;
      await request.response.close();
      return;
    }

    try {
      if (request.uri.path == '/' && request.method == 'GET') {
        request.response.headers.contentType = ContentType.html;
        request.response.write(_buildWebUiHtml());
        await request.response.close();
        return;
      }

      if (request.uri.path == '/api/state' && request.method == 'GET') {
        final snapshot = await api.getSnapshot();
        _writeJson(request.response, snapshot.toJson());
        return;
      }

      if (request.uri.path == '/api/home-assistant/media-player' && request.method == 'GET') {
        final snapshot = await api.getSnapshot();
        _writeJson(request.response, snapshot.toHomeAssistantMediaPlayerJson(homeAssistantEntityId));
        return;
      }

      if (request.uri.path == '/api/home-assistant/config' && request.method == 'GET') {
        final snapshot = await api.getSnapshot();
        _writeJson(request.response, snapshot.toHomeAssistantConfigJson(homeAssistantEntityId));
        return;
      }

      if (request.uri.path == '/api/home-assistant/media-player/command' && request.method == 'POST') {
        final body = await utf8.decoder.bind(request).join();
        final payload = body.isEmpty ? <String, dynamic>{} : jsonDecode(body) as Map<String, dynamic>;
        final action = _extractHomeAssistantAction(payload);
        final packageName = _extractStringField(payload, <String>['packageName', 'package_name']);
        final positionMs = _extractSeekPositionMs(payload);

        await _executeHomeAssistantAction(
          action: action,
          packageName: packageName,
          positionMs: positionMs,
        );

        _writeJson(request.response, <String, dynamic>{'ok': true});
        return;
      }

      if (request.uri.path.startsWith('/api/control/') && request.method == 'POST') {
        final action = request.uri.pathSegments.last;
        final body = await utf8.decoder.bind(request).join();
        final payload = body.isEmpty ? <String, dynamic>{} : jsonDecode(body) as Map<String, dynamic>;
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
            final positionMs = _extractSeekPositionMs(payload, required: true)!;
            await api.seekTo(
              packageName: packageName,
              position: Duration(milliseconds: positionMs),
            );
            break;
          default:
            request.response.statusCode = HttpStatus.notFound;
            _writeJson(request.response, <String, dynamic>{'error': 'Unknown action: $action'});
            return;
        }

        _writeJson(request.response, <String, dynamic>{'ok': true});
        return;
      }

      request.response.statusCode = HttpStatus.notFound;
      _writeJson(request.response, <String, dynamic>{'error': 'Not found'});
    } on FormatException catch (error) {
      request.response.statusCode = HttpStatus.badRequest;
      _writeJson(request.response, <String, dynamic>{'error': error.message});
    } on ArgumentError catch (error) {
      request.response.statusCode = HttpStatus.badRequest;
      _writeJson(request.response, <String, dynamic>{'error': error.message ?? error.toString()});
    } catch (error) {
      request.response.statusCode = HttpStatus.internalServerError;
      _writeJson(request.response, <String, dynamic>{'error': error.toString()});
    }
  }

  void _applyCorsHeaders(HttpResponse response) {
    response.headers.set(HttpHeaders.accessControlAllowOriginHeader, '*');
    response.headers.set(HttpHeaders.accessControlAllowHeadersHeader, 'content-type');
    response.headers.set(HttpHeaders.accessControlAllowMethodsHeader, 'GET,POST,OPTIONS');
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
          throw ArgumentError('Seek action requires positionMs/position/seek_position in payload (root, data, or service_data).');
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

  int? _extractSeekPositionMs(Map<String, dynamic> payload, {bool required = false}) {
    final msKeys = <String>['positionMs', 'position_ms', 'seek_position_ms', 'seekPosition'];
    final secondKeys = <String>['position', 'seek_position', 'media_position'];
    final candidates = _candidatePayloads(payload);

    for (final candidate in candidates) {
      for (final key in msKeys) {
        final value = _toDouble(candidate[key]);
        if (value != null) {
          return value.round().clamp(0, 1 << 31);
        }
      }
    }

    for (final candidate in candidates) {
      for (final key in secondKeys) {
        final value = _toDouble(candidate[key]);
        if (value != null) {
          return (value * 1000).round().clamp(0, 1 << 31);
        }
      }
    }

    if (required) {
      throw ArgumentError('Missing seek position. Provide positionMs or seek_position (seconds).');
    }
    return null;
  }

  String _extractHomeAssistantAction(Map<String, dynamic> payload) {
    final action = _extractStringField(payload, <String>['action', 'command']);
    if (action != null && action.trim().isNotEmpty) {
      return action.trim();
    }

    final service = _extractStringField(payload, <String>['service']);
    if (service != null && service.trim().isNotEmpty) {
      final trimmed = service.trim();
      final dotIndex = trimmed.lastIndexOf('.');
      return dotIndex >= 0 ? trimmed.substring(dotIndex + 1) : trimmed;
    }

    return '';
  }

  String? _extractStringField(Map<String, dynamic> payload, List<String> keys) {
    for (final candidate in _candidatePayloads(payload)) {
      for (final key in keys) {
        final raw = candidate[key];
        if (raw is String && raw.trim().isNotEmpty) {
          return raw.trim();
        }
      }
    }
    return null;
  }

  List<Map<String, dynamic>> _candidatePayloads(Map<String, dynamic> payload) {
    final maps = <Map<String, dynamic>>[payload];
    final data = payload['data'];
    if (data is Map) {
      maps.add(data.cast<String, dynamic>());
    }
    final serviceData = payload['service_data'];
    if (serviceData is Map) {
      maps.add(serviceData.cast<String, dynamic>());
    }
    return maps;
  }

  double? _toDouble(dynamic raw) {
    if (raw == null) {
      return null;
    }
    if (raw is num) {
      return raw.toDouble();
    }
    if (raw is String) {
      return double.tryParse(raw.trim());
    }
    return null;
  }
}

class MediaSnapshot {
  const MediaSnapshot({
    required this.listenerEnabled,
    required this.sessions,
    required this.timestamp,
  });

  final bool listenerEnabled;
  final List<MediaSessionInfo> sessions;
  final DateTime timestamp;

  factory MediaSnapshot.empty() {
    return MediaSnapshot(
      listenerEnabled: false,
      sessions: const <MediaSessionInfo>[],
      timestamp: DateTime.now(),
    );
  }

  factory MediaSnapshot.fromMap(Map<String, dynamic> map) {
    final sessions = (map['sessions'] as List<dynamic>? ?? <dynamic>[])
        .whereType<Map>()
        .map((Map<dynamic, dynamic> item) => MediaSessionInfo.fromMap(item.cast<String, dynamic>()))
        .toList(growable: false);

    return MediaSnapshot(
      listenerEnabled: map['listenerEnabled'] as bool? ?? false,
      sessions: sessions,
      timestamp: DateTime.fromMillisecondsSinceEpoch(
        (map['timestampMs'] as num?)?.round() ?? DateTime.now().millisecondsSinceEpoch,
      ),
    );
  }

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'listenerEnabled': listenerEnabled,
      'timestampMs': timestamp.millisecondsSinceEpoch,
      'sessions': sessions.map((MediaSessionInfo session) => session.toJson()).toList(growable: false),
    };
  }

  MediaSessionInfo? get activeSession {
    for (final session in sessions) {
      if (session.isPlaying) {
        return session;
      }
    }
    return sessions.isNotEmpty ? sessions.first : null;
  }

  Map<String, dynamic> toHomeAssistantMediaPlayerJson(String entityId) {
    final active = activeSession;
    final state = active == null
        ? 'idle'
        : active.isPlaying
            ? 'playing'
            : 'paused';


    return <String, dynamic>{
      'entity_id': '${entityId}_${DeviceUtil.currentName.replaceAll(' ', '_').toLowerCase()}',
      'state': state,
      'attributes': <String, dynamic>{
        'friendly_name': '大便媒體控制 - ${DeviceUtil.currentName}',
        'media_title': active?.title,
        'media_artist': active?.artist.isNotEmpty == true ? active?.artist : active?.displayArtist,
        'media_album_name': active?.album,
        'media_duration': active?.durationMs,
        'media_position': active?.positionMs,
        'media_position_updated_at': timestamp.toUtc().toIso8601String(),
        'app_name': active?.appName,
        'package_name': active?.packageName,
        'artwork_url': active?.artworkDataUrl,
        'supported_features': <int>[
          if (active?.canPlay ?? false) 16,
          if (active?.canPause ?? false) 32,
          if (active?.canSkipNext ?? false) 64,
          if (active?.canSkipPrevious ?? false) 128,
          if (active?.canSeekTo ?? false) 16,
        ],
      },
    };
  }

  Map<String, dynamic> toHomeAssistantConfigJson(String entityId) {
    return <String, dynamic>{
      'entity_id': '${entityId}_${DeviceUtil.currentName.replaceAll(' ', '_').toLowerCase()}',
      'name': '大便媒體控制 - ${DeviceUtil.currentName}',
      'unique_id': 'media_control_hub',
      'device_class': 'speaker',
      'features': <String>[
        'media_play',
        'media_pause',
        'media_play_pause',
        'media_next_track',
        'media_previous_track',
        'media_seek',
      ],
      'command_endpoint': '/api/home-assistant/media-player/command',
      'state_endpoint': '/api/home-assistant/media-player',
    };
  }
}

class MediaSessionInfo {
  const MediaSessionInfo({
    required this.packageName,
    required this.appName,
    required this.title,
    required this.artist,
    required this.album,
    required this.artworkDataUrl,
    required this.durationMs,
    required this.positionMs,
    required this.playbackState,
    required this.isPlaying,
    required this.canPlay,
    required this.canPause,
    required this.canSkipNext,
    required this.canSkipPrevious,
    required this.canSeekTo,
  });

  final String packageName;
  final String appName;
  final String title;
  final String artist;
  final String album;
  final String? artworkDataUrl;
  final int durationMs;
  final int positionMs;
  final String playbackState;
  final bool isPlaying;
  final bool canPlay;
  final bool canPause;
  final bool canSkipNext;
  final bool canSkipPrevious;
  final bool canSeekTo;

  factory MediaSessionInfo.fromMap(Map<String, dynamic> map) {
    return MediaSessionInfo(
      packageName: map['packageName'] as String? ?? '',
      appName: map['appName'] as String? ?? map['packageName'] as String? ?? 'Unknown app',
      title: map['title'] as String? ?? 'Unknown title',
      artist: map['artist'] as String? ?? '',
      album: map['album'] as String? ?? '',
      artworkDataUrl: map['artworkDataUrl'] as String?,
      durationMs: (map['durationMs'] as num?)?.round() ?? 0,
      positionMs: (map['positionMs'] as num?)?.round() ?? 0,
      playbackState: map['playbackState'] as String? ?? 'unknown',
      isPlaying: map['isPlaying'] as bool? ?? false,
      canPlay: map['canPlay'] as bool? ?? false,
      canPause: map['canPause'] as bool? ?? false,
      canSkipNext: map['canSkipNext'] as bool? ?? false,
      canSkipPrevious: map['canSkipPrevious'] as bool? ?? false,
      canSeekTo: map['canSeekTo'] as bool? ?? false,
    );
  }

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'packageName': packageName,
      'appName': appName,
      'title': title,
      'artist': artist,
      'album': album,
      if (artworkDataUrl != null) 'artworkDataUrl': artworkDataUrl,
      'durationMs': durationMs,
      'positionMs': positionMs,
      'playbackState': playbackState,
      'isPlaying': isPlaying,
      'canPlay': canPlay,
      'canPause': canPause,
      'canSkipNext': canSkipNext,
      'canSkipPrevious': canSkipPrevious,
      'canSeekTo': canSeekTo,
    };
  }

  String get displayArtist {
    if (artist.isNotEmpty) {
      return artist;
    }
    if (album.isNotEmpty) {
      return album;
    }
    return 'No artist metadata';
  }

  bool get hasArtwork => artworkDataUrl != null && artworkDataUrl!.isNotEmpty;

  double get progressFraction {
    if (durationMs <= 0) {
      return 0;
    }
    return (positionMs / durationMs).clamp(0, 1);
  }
}

Uint8List _decodeDataUrl(String dataUrl) {
  final commaIndex = dataUrl.indexOf(',');
  if (commaIndex < 0) {
    return Uint8List(0);
  }
  return base64Decode(dataUrl.substring(commaIndex + 1));
}

class MediaControlApp extends StatefulWidget {
  const MediaControlApp({
    super.key,
    this.api = const PlatformMediaControlApi(),
    this.autoStartServer = true,
    this.autoStartBackgroundProtection = false,
  });

  final MediaControlApi api;
  final bool autoStartServer;
  final bool autoStartBackgroundProtection;

  @override
  State<MediaControlApp> createState() => _MediaControlAppState();
}

class _MediaControlAppState extends State<MediaControlApp> with WidgetsBindingObserver {
  late final MediaControlServer _server;
  Timer? _pollTimer;

  MediaSnapshot? _snapshot;
  Uri? _serverUri;
  String? _localAddress;
  String? _errorMessage;
  bool _backgroundProtectionEnabled = false;
  bool _startingServer = false;
  bool _startingBackgroundProtection = false;
  bool _refreshing = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _server = MediaControlServer(api: widget.api);
    _bootstrap();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _pollTimer?.cancel();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _refreshSnapshot();
    }
  }

  Future<void> _bootstrap() async {
    if (widget.autoStartBackgroundProtection) {
      await _startBackgroundProtection();
    }
    if (widget.autoStartServer) {
      await _startServer();
    }
    await _refreshSnapshot();
    _pollTimer?.cancel();
    _pollTimer = Timer.periodic(const Duration(seconds: 2), (_) {
      _refreshSnapshot();
    });
  }

  Future<void> _startBackgroundProtection() async {
    if (_backgroundProtectionEnabled || _startingBackgroundProtection) {
      return;
    }

    setState(() {
      _startingBackgroundProtection = true;
      _errorMessage = null;
    });

    try {
      final permissionGranted = await widget.api.ensureNotificationPermission();
      if (!permissionGranted) {
        throw StateError('Notification permission was not granted.');
      }

      await widget.api.startBackgroundProtection();
      if (!mounted) {
        return;
      }
      setState(() {
        _backgroundProtectionEnabled = true;
      });
      await _syncBackgroundProtectionNotification();
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _errorMessage = error.toString();
      });
    } finally {
      if (mounted) {
        setState(() {
          _startingBackgroundProtection = false;
        });
      }
    }
  }

  Future<void> _startServer() async {
    if (_serverUri != null || _startingServer) {
      return;
    }

    setState(() {
      _startingServer = true;
      _errorMessage = null;
    });

    try {
      final uri = await _server.start();
      final localAddress = await _findLocalAddress();
      if (!mounted) {
        return;
      }
      setState(() {
        _serverUri = uri;
        _localAddress = localAddress;
      });
      await _syncBackgroundProtectionNotification();
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _errorMessage = error.toString();
      });
    } finally {
      if (mounted) {
        setState(() {
          _startingServer = false;
        });
      }
    }
  }

  Future<void> _syncBackgroundProtectionNotification() async {
    if (!_backgroundProtectionEnabled || _serverUri == null) {
      return;
    }

    final webUrl = 'http://${_localAddress ?? 'localhost'}:${_serverUri!.port}';
    await widget.api.updateBackgroundProtectionNotification(webUrl: webUrl);
  }

  Future<void> _refreshSnapshot() async {
    if (_refreshing) {
      return;
    }

    _refreshing = true;
    try {
      final snapshot = await widget.api.getSnapshot();
      if (!mounted) {
        return;
      }
      setState(() {
        _snapshot = snapshot;
        _errorMessage = null;
      });
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _errorMessage = error.toString();
      });
    } finally {
      _refreshing = false;
    }
  }

  Future<void> _control(Future<void> Function() action) async {
    try {
      await action();
      await _refreshSnapshot();
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _errorMessage = error.toString();
      });
    }
  }

  Future<String?> _findLocalAddress() async {
    try {
      final interfaces = await NetworkInterface.list(
        includeLinkLocal: false,
        includeLoopback: false,
        type: InternetAddressType.IPv4,
      );

      for (final networkInterface in interfaces) {
        for (final address in networkInterface.addresses) {
          if (!address.isLoopback && !address.address.startsWith('169.254.')) {
            return address.address;
          }
        }
      }
    } catch (_) {
      return null;
    }
    return null;
  }

  String _formatDuration(int milliseconds) {
    if (milliseconds <= 0) {
      return '--:--';
    }
    final totalSeconds = (milliseconds / 1000).floor();
    final minutes = totalSeconds ~/ 60;
    final seconds = totalSeconds % 60;
    return '${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
  }

  Future<void> _copyToClipboard(String text) async {
    await Clipboard.setData(ClipboardData(text: text));
    if (!mounted) {
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('URL copied to clipboard')),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = ColorScheme.fromSeed(
      seedColor: const Color(0xFF5CE1E6),
      brightness: Brightness.dark,
    );
    final snapshot = _snapshot ?? MediaSnapshot.empty();
    final activeSession = snapshot.activeSession;

    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: '大便媒體控制',
      theme: ThemeData(
        colorScheme: colorScheme,
        scaffoldBackgroundColor: const Color(0xFF07111D),
        useMaterial3: true,
      ),
      home: Scaffold(
        body: Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: <Color>[
                Color(0xFF08111F),
                Color(0xFF0B1729),
                Color(0xFF050B14),
              ],
            ),
          ),
          child: SafeArea(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(20),
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 980),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: <Widget>[
                      _HeroCard(
                        snapshot: snapshot,
                        serverRunning: _serverUri != null,
                        serverLoading: _startingServer,
                        serverError: _errorMessage,
                        onStartServer: _startServer,
                        onRefresh: _refreshSnapshot,
                      ),
                      const SizedBox(height: 20),
                      _ServerCard(
                        serverUri: _serverUri,
                        localAddress: _localAddress,
                        onCopy: _serverUri == null
                            ? null
                            : () => _copyToClipboard('http://${_localAddress ?? 'localhost'}:${_serverUri!.port}'),
                      ),
                      const SizedBox(height: 20),
                      _BackgroundProtectionCard(
                        enabled: _backgroundProtectionEnabled,
                        loading: _startingBackgroundProtection,
                        onEnable: _startBackgroundProtection,
                      ),
                      const SizedBox(height: 20),
                      _PermissionCard(
                        enabled: snapshot.listenerEnabled,
                        onOpenSettings: () => _control(widget.api.openNotificationSettings),
                      ),
                      const SizedBox(height: 20),
                      if (activeSession != null)
                        _NowPlayingCard(
                          session: activeSession,
                          formatDuration: _formatDuration,
                          onPlay: () => _control(() => widget.api.play(packageName: activeSession.packageName)),
                          onPause: () => _control(() => widget.api.pause(packageName: activeSession.packageName)),
                          onNext: () => _control(() => widget.api.next(packageName: activeSession.packageName)),
                          onPrevious: () => _control(() => widget.api.previous(packageName: activeSession.packageName)),
                          onSeekTo: (Duration position) => _control(() => widget.api.seekTo(
                                packageName: activeSession.packageName,
                                position: position,
                              )),
                        )
                      else
                        _EmptyStateCard(
                          title: '沒有媒體進程yet',
                          message: '去播音樂阿',
                        ),
                      const SizedBox(height: 20),
                      _SessionListCard(
                        sessions: snapshot.sessions,
                        formatDuration: _formatDuration,
                        onPlay: (MediaSessionInfo session) => _control(() => widget.api.play(packageName: session.packageName)),
                        onPause: (MediaSessionInfo session) => _control(() => widget.api.pause(packageName: session.packageName)),
                        onNext: (MediaSessionInfo session) => _control(() => widget.api.next(packageName: session.packageName)),
                        onPrevious: (MediaSessionInfo session) => _control(() => widget.api.previous(packageName: session.packageName)),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _HeroCard extends StatelessWidget {
  const _HeroCard({
    required this.snapshot,
    required this.serverRunning,
    required this.serverLoading,
    required this.serverError,
    required this.onStartServer,
    required this.onRefresh,
  });

  final MediaSnapshot snapshot;
  final bool serverRunning;
  final bool serverLoading;
  final String? serverError;
  final Future<void> Function() onStartServer;
  final Future<void> Function() onRefresh;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(28),
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: <Color>[
            Color(0xFF143149),
            Color(0xFF10253B),
            Color(0xFF0A1424),
          ],
        ),
        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
        boxShadow: const <BoxShadow>[
          BoxShadow(color: Color(0xAA000000), blurRadius: 30, offset: Offset(0, 18)),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(
                        '大便媒體控制',
                        style: theme.textTheme.displaySmall?.copyWith(
                          fontWeight: FontWeight.w800,
                          letterSpacing: -0.8,
                        ),
                      ),
                      const SizedBox(height: 10),
                      Text(
                        '就字面上的意思看不懂嗎？',
                        style: theme.textTheme.titleMedium?.copyWith(
                          color: Colors.white.withValues(alpha: 0.78),
                          height: 1.35,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 16),
                _StatusChip(
                  label: serverRunning ? '正在跑' : '嚴肅停止',
                  color: serverRunning ? const Color(0xFF15C89A) : const Color(0xFFF59E0B),
                ),
              ],
            ),
            const SizedBox(height: 20),
            Wrap(
              spacing: 12,
              runSpacing: 12,
              children: <Widget>[
                FilledButton.icon(
                  onPressed: serverLoading ? null : onStartServer,
                  icon: serverLoading
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.public),
                  label: Text(serverRunning ? '重新啟動服務員' : 'Start server'),
                ),
                OutlinedButton.icon(
                  onPressed: onRefresh,
                  icon: const Icon(Icons.refresh),
                  label: const Text('重刷媒體州'),
                ),
              ],
            ),
            if (serverError != null) ...<Widget>[
              const SizedBox(height: 16),
              _InlineMessage(
                icon: Icons.error_outline,
                title: 'Server error',
                message: serverError!,
              ),
            ],
            const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }
}

class _ServerCard extends StatelessWidget {
  const _ServerCard({
    required this.serverUri,
    required this.localAddress,
    required this.onCopy,
  });

  final Uri? serverUri;
  final String? localAddress;
  final VoidCallback? onCopy;

  @override
  Widget build(BuildContext context) {
    return _PanelCard(
      title: '蜘蛛網UI終點',
      subtitle: '打開這個URL在其他裝置在同一個無線網路',
      child: serverUri == null
          ? const Text(
              'Start the server first to get a local URL.',
              style: TextStyle(color: Colors.white70),
            )
          : Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                SelectableText(
                  'http://${localAddress ?? 'localhost'}:${serverUri!.port}',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 12,
                  runSpacing: 12,
                  children: <Widget>[
                    if (onCopy != null)
                      OutlinedButton.icon(
                        onPressed: onCopy,
                        icon: const Icon(Icons.copy),
                        label: const Text('拷貝URL'),
                      ),
                    Text(
                      '迴圈背面: http://127.0.0.1:${serverUri!.port}',
                      style: TextStyle(color: Colors.white.withValues(alpha: 0.72)),
                    ),
                  ],
                ),
              ],
            ),
    );
  }
}

class _PermissionCard extends StatelessWidget {
  const _PermissionCard({required this.enabled, required this.onOpenSettings});

  final bool enabled;
  final Future<void> Function() onOpenSettings;

  @override
  Widget build(BuildContext context) {
    final accent = enabled ? const Color(0xFF15C89A) : const Color(0xFFF97316);

    return _PanelCard(
      title: '通知進入',
      subtitle: '需要這個設定讓我去查其他的App',
      trailing: _StatusChip(label: enabled ? '啟用' : '需要設定上面', color: accent),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            enabled
                ? '這個應用程式可以讀取你媽的通知'
                : '去啟用權限讓我可以看你通知拉齁',
            style: const TextStyle(color: Colors.white70),
          ),
          const SizedBox(height: 12),
          FilledButton.icon(
            onPressed: () => onOpenSettings(),
            icon: const Icon(Icons.settings),
            label: const Text('Open settings'),
          ),
        ],
      ),
    );
  }
}

class _BackgroundProtectionCard extends StatelessWidget {
  const _BackgroundProtectionCard({
    required this.enabled,
    required this.loading,
    required this.onEnable,
  });

  final bool enabled;
  final bool loading;
  final Future<void> Function() onEnable;

  @override
  Widget build(BuildContext context) {
    final accent = enabled ? const Color(0xFF15C89A) : const Color(0xFFF59E0B);

    return _PanelCard(
      title: '背景保護',
      subtitle: '簡單來說就是防止安卓大大殺你後台',
      trailing: _StatusChip(label: enabled ? '正在跑' : 'Stopped', color: accent),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            enabled
                ? '保後台通知啟動，應該是不會被殺後台拉'
                : '打開通知權限確保不會被安卓大大殺後台',
            style: const TextStyle(color: Colors.white70),
          ),
          const SizedBox(height: 12),
          FilledButton.icon(
            onPressed: loading ? null : onEnable,
            icon: loading
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.notifications_active),
            label: Text(enabled ? 'Restart protection' : 'Enable protection'),
          ),
        ],
      ),
    );
  }
}

class _NowPlayingCard extends StatelessWidget {
  const _NowPlayingCard({
    required this.session,
    required this.formatDuration,
    required this.onPlay,
    required this.onPause,
    required this.onNext,
    required this.onPrevious,
    required this.onSeekTo,
  });

  final MediaSessionInfo session;
  final String Function(int milliseconds) formatDuration;
  final Future<void> Function() onPlay;
  final Future<void> Function() onPause;
  final Future<void> Function() onNext;
  final Future<void> Function() onPrevious;
  final Future<void> Function(Duration position) onSeekTo;

  @override
  Widget build(BuildContext context) {
    final progress = session.progressFraction;
    final durationLabel = formatDuration(session.durationMs);
    final positionLabel = formatDuration(session.positionMs);

    return _PanelCard(
      title: '現在正在玩',
      subtitle: session.appName,
      trailing: _StatusChip(
        label: session.isPlaying ? '正在玩' : '已經暫停',
        color: session.isPlaying ? const Color(0xFF15C89A) : const Color(0xFF60A5FA),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              _ArtworkThumbnail(
                artworkDataUrl: session.artworkDataUrl,
                size: 96,
                radius: 22,
                fallbackIconSize: 40,
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      session.title,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 24,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      session.displayArtist,
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.76),
                        fontSize: 15,
                      ),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      session.packageName,
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.55),
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 18),
          ClipRRect(
            borderRadius: BorderRadius.circular(999),
            child: LinearProgressIndicator(
              minHeight: 10,
              value: progress,
              backgroundColor: Colors.white.withValues(alpha: 0.08),
              color: const Color(0xFF5CE1E6),
            ),
          ),
          const SizedBox(height: 10),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: <Widget>[
              Text(positionLabel, style: const TextStyle(color: Colors.white70)),
              Text(durationLabel, style: const TextStyle(color: Colors.white70)),
            ],
          ),
          const SizedBox(height: 14),
          Wrap(
            spacing: 12,
            runSpacing: 12,
            children: <Widget>[
              OutlinedButton.icon(
                onPressed: onPrevious,
                icon: const Icon(Icons.skip_previous),
                label: const Text('Previous'),
              ),
              FilledButton.icon(
                onPressed: session.isPlaying ? onPause : onPlay,
                icon: Icon(session.isPlaying ? Icons.pause : Icons.play_arrow),
                label: Text(session.isPlaying ? 'Pause' : 'Play'),
              ),
              OutlinedButton.icon(
                onPressed: onNext,
                icon: const Icon(Icons.skip_next),
                label: const Text('Next'),
              ),
            ],
          ),
          if (session.canSeekTo) ...<Widget>[
            const SizedBox(height: 16),
            Slider(
              min: 0,
              max: session.durationMs > 0 ? session.durationMs.toDouble() : 1,
              value: session.positionMs.clamp(0, session.durationMs).toDouble(),
              onChanged: (double value) {},
              onChangeEnd: (double value) => onSeekTo(Duration(milliseconds: value.round())),
            ),
          ],
        ],
      ),
    );
  }
}

class _SessionListCard extends StatelessWidget {
  const _SessionListCard({
    required this.sessions,
    required this.formatDuration,
    required this.onPlay,
    required this.onPause,
    required this.onNext,
    required this.onPrevious,
  });

  final List<MediaSessionInfo> sessions;
  final String Function(int milliseconds) formatDuration;
  final Future<void> Function(MediaSessionInfo session) onPlay;
  final Future<void> Function(MediaSessionInfo session) onPause;
  final Future<void> Function(MediaSessionInfo session) onNext;
  final Future<void> Function(MediaSessionInfo session) onPrevious;

  @override
  Widget build(BuildContext context) {
    return _PanelCard(
      title: '上線進程',
      subtitle: '${sessions.length} 進程${sessions.length == 1 ? '' : ''} 偵測到',
      child: sessions.isEmpty
          ? const Text('就沒有啊', style: TextStyle(color: Colors.white70))
          : Column(
              children: sessions
                  .map(
                    (MediaSessionInfo session) => Padding(
                      padding: const EdgeInsets.only(bottom: 14),
                      child: Container(
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.04),
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(color: Colors.white.withValues(alpha: 0.06)),
                        ),
                        child: Padding(
                          padding: const EdgeInsets.all(16),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: <Widget>[
                              Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: <Widget>[
                                  _ArtworkThumbnail(
                                    artworkDataUrl: session.artworkDataUrl,
                                    size: 56,
                                    radius: 14,
                                    fallbackIconSize: 22,
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: <Widget>[
                                        Text(
                                          session.appName,
                                          style: const TextStyle(
                                            color: Colors.white,
                                            fontSize: 18,
                                            fontWeight: FontWeight.w700,
                                          ),
                                        ),
                                        const SizedBox(height: 4),
                                        Text(
                                          session.title,
                                          style: TextStyle(color: Colors.white.withValues(alpha: 0.78)),
                                        ),
                                        const SizedBox(height: 2),
                                        Text(
                                          session.displayArtist,
                                          style: TextStyle(
                                            color: Colors.white.withValues(alpha: 0.56),
                                            fontSize: 12,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  _StatusChip(
                                    label: session.isPlaying ? 'Playing' : session.playbackState,
                                    color: session.isPlaying ? const Color(0xFF15C89A) : const Color(0xFF64748B),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 8),
                              Text(
                                session.displayArtist,
                                style: const TextStyle(color: Colors.white70),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                '${formatDuration(session.positionMs)} / ${formatDuration(session.durationMs)}',
                                style: TextStyle(color: Colors.white.withValues(alpha: 0.56)),
                              ),
                              const SizedBox(height: 12),
                              Wrap(
                                spacing: 10,
                                runSpacing: 10,
                                children: <Widget>[
                                  OutlinedButton.icon(
                                    onPressed: () => onPrevious(session),
                                    icon: const Icon(Icons.skip_previous),
                                    label: const Text('Previous'),
                                  ),
                                  FilledButton.icon(
                                    onPressed: session.isPlaying ? () => onPause(session) : () => onPlay(session),
                                    icon: Icon(session.isPlaying ? Icons.pause : Icons.play_arrow),
                                    label: Text(session.isPlaying ? 'Pause' : 'Play'),
                                  ),
                                  OutlinedButton.icon(
                                    onPressed: () => onNext(session),
                                    icon: const Icon(Icons.skip_next),
                                    label: const Text('Next'),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  )
                  .toList(growable: false),
            ),
    );
  }
}

class _ArtworkThumbnail extends StatelessWidget {
  const _ArtworkThumbnail({
    required this.artworkDataUrl,
    required this.size,
    required this.radius,
    required this.fallbackIconSize,
  });

  final String? artworkDataUrl;
  final double size;
  final double radius;
  final double fallbackIconSize;

  @override
  Widget build(BuildContext context) {
    final dataUrl = artworkDataUrl;

    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(radius),
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: <Color>[Color(0xFF20324B), Color(0xFF0F172A)],
        ),
        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
      ),
      clipBehavior: Clip.antiAlias,
      child: dataUrl == null || dataUrl.isEmpty
          ? Icon(Icons.album, color: Colors.white.withValues(alpha: 0.7), size: fallbackIconSize)
          : Image.memory(
              _decodeDataUrl(dataUrl),
              fit: BoxFit.cover,
              errorBuilder: (BuildContext context, Object error, StackTrace? stackTrace) {
                return Icon(Icons.album, color: Colors.white.withValues(alpha: 0.7), size: fallbackIconSize);
              },
            ),
    );
  }
}

class _EmptyStateCard extends StatelessWidget {
  const _EmptyStateCard({required this.title, required this.message});

  final String title;
  final String message;

  @override
  Widget build(BuildContext context) {
    return _PanelCard(
      title: title,
      subtitle: 'Waiting for media playback',
      child: Text(message, style: const TextStyle(color: Colors.white70)),
    );
  }
}




class _PanelCard extends StatelessWidget {
  const _PanelCard({
    required this.title,
    required this.subtitle,
    required this.child,
    this.trailing,
  });

  final String title;
  final String subtitle;
  final Widget child;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(
                        title,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 18,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        subtitle,
                        style: TextStyle(color: Colors.white.withValues(alpha: 0.62)),
                      ),
                    ],
                  ),
                ),
                ?trailing,
              ],
            ),
            const SizedBox(height: 16),
            child,
          ],
        ),
      ),
    );
  }
}

class _StatusChip extends StatelessWidget {
  const _StatusChip({required this.label, required this.color});

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.16),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      child: Text(
        label,
        style: TextStyle(
          color: color,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

class _InlineMessage extends StatelessWidget {
  const _InlineMessage({required this.icon, required this.title, required this.message});

  final IconData icon;
  final String title;
  final String message;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF3A1D24),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFFFF7A90).withValues(alpha: 0.3)),
      ),
      padding: const EdgeInsets.all(14),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Icon(icon, color: const Color(0xFFFF8A8A)),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(title, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700)),
                const SizedBox(height: 4),
                Text(message, style: const TextStyle(color: Colors.white70)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

String _buildWebUiHtml() {
  return r'''
<!doctype html>
<html lang="zh-Hant">
<head>
  <meta charset="utf-8" />
  <meta name="viewport" content="width=device-width, initial-scale=1" />
  <title>大便媒體控制</title>
  <style>
    /* 定義全域 CSS 變數與色彩配置 */
    :root {
      color-scheme: dark;
      --bg: #07111d;
      --panel: rgba(14, 23, 39, 0.6);
      --panel-border: rgba(255, 255, 255, 0.1);
      --muted: rgba(226, 232, 240, 0.72);
      --accent: #5ce1e6;
      --accent-strong: #15c89a;
      --warning: #f59e0b;
      --shadow: 0 24px 80px rgba(0, 0, 0, 0.4);
      --glass-blur: blur(24px);
    }

    /* 基礎重置與排版設定 */
    * { 
      box-sizing: border-box; 
    }

    body {
      margin: 0;
      min-height: 100vh;
      font-family: 'Inter', system-ui, -apple-system, sans-serif;
      background:
        radial-gradient(circle at top left, rgba(92, 225, 230, 0.15), transparent 30%),
        radial-gradient(circle at bottom right, rgba(21, 200, 154, 0.15), transparent 30%),
        linear-gradient(180deg, #08111f 0%, #0b1729 50%, #050b14 100%);
      color: white;
      -webkit-font-smoothing: antialiased;
    }

    .shell {
      width: min(1120px, calc(100% - 48px));
      margin: 0 auto;
      padding: 32px 0 64px;
    }

    /* 英雄區塊樣式（Hero Section） */
    .hero {
      border: 1px solid var(--panel-border);
      border-radius: 32px;
      padding: 40px;
      background: linear-gradient(135deg, rgba(20, 49, 73, 0.8), rgba(10, 20, 36, 0.9));
      box-shadow: var(--shadow);
      backdrop-filter: var(--glass-blur);
      position: relative;
      overflow: hidden;
    }

    /* 裝飾性標籤 */
    .eyebrow {
      display: inline-flex;
      align-items: center;
      gap: 8px;
      padding: 8px 16px;
      border-radius: 999px;
      border: 1px solid rgba(92, 225, 230, 0.3);
      background: rgba(92, 225, 230, 0.1);
      color: var(--accent);
      font-size: 13px;
      font-weight: 700;
      letter-spacing: 0.1em;
      text-transform: uppercase;
    }

    h1 {
      margin: 20px 0 16px;
      font-size: clamp(40px, 6vw, 72px);
      line-height: 1.1;
      letter-spacing: -0.03em;
      background: linear-gradient(to right, #fff, #a5b4fc);
      -webkit-background-clip: text;
      -webkit-text-fill-color: transparent;
    }

    .lede {
      max-width: 600px;
      margin: 0;
      color: var(--muted);
      font-size: 18px;
      line-height: 1.6;
    }

    .toolbar {
      display: flex;
      flex-wrap: wrap;
      gap: 16px;
      margin-top: 32px;
    }

    /* 按鈕共用樣式 */
    button {
      appearance: none;
      border: 0;
      border-radius: 16px;
      padding: 14px 24px;
      font: inherit;
      font-size: 15px;
      font-weight: 600;
      color: white;
      cursor: pointer;
      transition: all 0.2s cubic-bezier(0.4, 0, 0.2, 1);
    }

    button:hover { 
      transform: translateY(-2px); 
    }
    
    button:active {
      transform: translateY(0);
    }

    button:disabled { 
      opacity: 0.5; 
      cursor: not-allowed; 
      transform: none; 
    }

    .primary {
      background: linear-gradient(135deg, var(--accent), #3b82f6);
      box-shadow: 0 8px 24px rgba(59, 130, 246, 0.3);
      color: #000;
    }

    .primary:hover {
      box-shadow: 0 12px 32px rgba(59, 130, 246, 0.4);
    }

    .secondary {
      background: rgba(255, 255, 255, 0.08);
      border: 1px solid rgba(255, 255, 255, 0.15);
    }

    .secondary:hover {
      background: rgba(255, 255, 255, 0.12);
    }

    /* 網格系統配置 */
    .grid {
      display: grid;
      grid-template-columns: repeat(12, minmax(0, 1fr));
      gap: 24px;
      margin-top: 24px;
    }

    /* 卡片模組化樣式 */
    .card {
      grid-column: span 12;
      border: 1px solid var(--panel-border);
      border-radius: 28px;
      background: var(--panel);
      backdrop-filter: var(--glass-blur);
      box-shadow: var(--shadow);
      padding: 28px;
      transition: transform 0.3s ease;
    }
    
    .card:hover {
      border-color: rgba(255, 255, 255, 0.2);
    }

    .card-header {
      display: flex;
      justify-content: space-between;
      gap: 16px;
      align-items: flex-start;
      margin-bottom: 24px;
    }

    .title { 
      margin: 0; 
      font-size: 22px; 
      font-weight: 700; 
    }

    .subtitle { 
      margin: 8px 0 0; 
      color: var(--muted); 
      line-height: 1.5; 
      font-size: 14px;
    }

    /* 狀態標籤指示器 */
    .pill {
      border-radius: 999px;
      padding: 6px 14px;
      font-size: 13px;
      font-weight: 700;
      white-space: nowrap;
    }

    .pill.success { background: rgba(21, 200, 154, 0.15); color: var(--accent-strong); border: 1px solid rgba(21, 200, 154, 0.3); }
    .pill.warn { background: rgba(245, 158, 11, 0.15); color: var(--warning); border: 1px solid rgba(245, 158, 11, 0.3); }
    .pill.info { background: rgba(96, 165, 250, 0.15); color: #93c5fd; border: 1px solid rgba(96, 165, 250, 0.3); }

    /* 數據面板 */
    .meta {
      display: grid;
      grid-template-columns: repeat(auto-fit, minmax(160px, 1fr));
      gap: 16px;
    }

    .metric {
      padding: 16px;
      border-radius: 20px;
      background: rgba(255, 255, 255, 0.03);
      border: 1px solid rgba(255, 255, 255, 0.08);
      transition: background 0.2s;
    }
    
    .metric:hover {
      background: rgba(255, 255, 255, 0.05);
    }

    .metric label {
      display: block;
      color: var(--muted);
      font-size: 12px;
      margin-bottom: 8px;
      text-transform: uppercase;
      letter-spacing: 0.1em;
    }

    .metric strong { 
      font-size: 20px; 
      font-weight: 600;
    }

    .sessions { 
      display: grid; 
      gap: 16px; 
    }

    /* 媒體會話控制項 */
    .session {
      padding: 20px;
      border-radius: 24px;
      background: rgba(255, 255, 255, 0.03);
      border: 1px solid rgba(255, 255, 255, 0.08);
      transition: background 0.2s;
    }

    .session:hover {
      background: rgba(255, 255, 255, 0.05);
    }

    .session-top {
      display: flex;
      gap: 20px;
      justify-content: space-between;
      align-items: center;
    }

    /* 媒體封面圖片 */
    .now-cover {
      width: 96px;
      height: 96px;
      flex: 0 0 auto;
      border-radius: 20px;
      overflow: hidden;
      display: grid;
      place-items: center;
      font-size: 32px;
      color: rgba(255, 255, 255, 0.8);
      background: linear-gradient(135deg, rgba(92, 225, 230, 0.2), rgba(59, 130, 246, 0.2));
      border: 1px solid rgba(255, 255, 255, 0.1);
      box-shadow: 0 8px 16px rgba(0,0,0,0.2);
    }

    .now-cover.small {
      width: 72px;
      height: 72px;
      border-radius: 16px;
      font-size: 24px;
    }

    .now-cover img {
      width: 100%;
      height: 100%;
      object-fit: cover;
      display: block;
    }

    .now-meta {
      flex: 1;
      min-width: 0;
    }

    .session h3 { 
      margin: 0; 
      font-size: 20px; 
      font-weight: 600;
      white-space: nowrap;
      overflow: hidden;
      text-overflow: ellipsis;
    }
    
    .session .artist { 
      margin: 8px 0 0; 
      color: var(--muted);
      font-size: 15px; 
    }
    
    .session .package, .session .timing { 
      margin: 6px 0 0; 
      color: rgba(255,255,255,0.4);
      font-size: 13px;
    }

    /* 播放進度條 */
    .progress {
      margin: 20px 0 12px;
      height: 8px;
      border-radius: 999px;
      background: rgba(255, 255, 255, 0.08);
      overflow: hidden;
    }

    .progress > div {
      height: 100%;
      width: 0%;
      background: linear-gradient(90deg, var(--accent), #3b82f6);
      border-radius: inherit;
      transition: width 1s linear;
      box-shadow: 0 0 10px rgba(92, 225, 230, 0.5);
    }

    .controls {
      display: flex;
      flex-wrap: wrap;
      gap: 12px;
      margin-top: 20px;
    }
    
    .controls button {
      padding: 10px 20px;
      font-size: 14px;
    }

    .danger {
      color: #fecaca;
      background: rgba(251, 113, 133, 0.15);
      border: 1px solid rgba(251, 113, 133, 0.3);
      padding: 16px 20px;
      border-radius: 16px;
      margin-top: 24px;
      display: none;
      font-weight: 500;
    }

    .hint { 
      color: var(--muted); 
      line-height: 1.6; 
      font-size: 15px;
    }

    /* 響應式佈局調整 */
    @media (min-width: 860px) {
      .span-7 { grid-column: span 7; }
      .span-5 { grid-column: span 5; }
      .span-4 { grid-column: span 4; }
    }
  </style>
</head>
<body>
  <main class="shell">
    <section class="hero">
      <div class="eyebrow">LOCAL</div>
      <h1>大便媒體遙控</h1>
      <p class="lede">
        即時讀取您的 Android 媒體進程，優雅地顯示歌曲資訊與播放進度。並提供播放、暫停、切換曲目等遠端控制指令。
      </p>
      <div class="toolbar">
        <button class="primary" id="refreshBtn">重刷媒體狀態</button>
        <button class="secondary" id="copyBtn">複製控制網址</button>
      </div>
      <div class="danger" id="errorBox"></div>
    </section>

    <section class="grid">
      <article class="card span-7">
        <div class="card-header">
          <div>
            <h2 class="title">即時快照</h2>
            <p class="subtitle">系統將自動每秒向手機機同步一次最新狀態。</p>
          </div>
          <div class="pill info" id="serverState">系統載入中</div>
        </div>
        <div class="meta" id="metrics"></div>
      </article>

      <article class="card span-5">
        <div class="card-header">
          <div>
            <h2 class="title">使用說明</h2>
            <p class="subtitle">就字面上的意思啊</p>
          </div>
        </div>
        <p class="hint">
          若未顯示任何媒體資訊，請至手機的系統設定內開啟此應用程式的「通知存取權限」。接著在裝置上開始播放音樂或影片，即可在此進行控制。
        </p>
        <p class="hint" id="urlHint" style="word-break: break-all; opacity: 0.7; font-family: monospace;"></p>
      </article>

      <article class="card span-12">
        <div class="card-header">
          <div>
            <h2 class="title">現正播放</h2>
            <p class="subtitle">此處顯示目前處於活躍狀態的最相關播放進程。</p>
          </div>
          <div class="pill success" id="sessionCount">0 個進程</div>
        </div>
        <div id="nowPlaying"></div>
      </article>

      <article class="card span-12">
        <div class="card-header">
          <div>
            <h2 class="title">活躍進程列表</h2>
            <p class="subtitle">可獨立控制各應用程式的背景播放進程（依據該應用程式開放之 API 權限而定）。</p>
          </div>
        </div>
        <div class="sessions" id="sessions"></div>
      </article>
    </section>
  </main>

  <script>
    /* 取得 DOM 節點參考 */
    const domNodes = {
      metrics: document.getElementById('metrics'),
      sessionsContainer: document.getElementById('sessions'),
      nowPlaying: document.getElementById('nowPlaying'),
      errorBox: document.getElementById('errorBox'),
      serverState: document.getElementById('serverState'),
      sessionCount: document.getElementById('sessionCount'),
      urlHint: document.getElementById('urlHint'),
      refreshBtn: document.getElementById('refreshBtn'),
      copyBtn: document.getElementById('copyBtn')
    };

    /**
     * 將毫秒轉換為 MM:SS 格式的字串
     * @param {number} ms - 毫秒數
     * @returns {string} 格式化後的時間字串
     */
    function formatTime(ms) {
      if (!ms || ms <= 0) {
        return '--:--';
      }
      const totalSeconds = Math.floor(ms / 1000);
      const minutes = Math.floor(totalSeconds / 60);
      const seconds = totalSeconds % 60;
      return String(minutes).padStart(2, '0') + ':' + String(seconds).padStart(2, '0');
    }

    /**
     * 跳脫 HTML 特殊字元以防止 XSS 攻擊
     * @param {string} value - 原始字串
     * @returns {string} 跳脫後的安全字串
     */
    function escapeHtml(value) {
      if (!value) return '';
      return String(value)
        .replaceAll('&', '&amp;')
        .replaceAll('<', '&lt;')
        .replaceAll('>', '&gt;')
        .replaceAll('"', '&quot;')
        .replaceAll("'", '&#39;');
    }

    /**
     * 發送控制指令至後端 API
     * @param {string} action - 控制動作 (play, pause, next, previous)
     * @param {Object} payload - 附帶資料，通常包含目標套件名稱
     */
    async function sendControl(action, payload = {}) {
      try {
        await fetch('/api/control/' + action, {
          method: 'POST',
          headers: { 'Content-Type': 'application/json' },
          body: JSON.stringify(payload),
        });
        await refresh();
      } catch (error) {
        console.error('API 控制請求失敗', error);
      }
    }

    /**
     * 渲染系統狀態數據區塊
     * @param {Object} snapshot - 後端回傳的狀態快照
     */
    function renderMetrics(snapshot) {
      const active = snapshot.sessions.find(session => session.isPlaying) || snapshot.sessions[0] || null;
      domNodes.metrics.innerHTML = `
        <div class="metric"><label>通知監聽器</label><strong>${snapshot.listenerEnabled ? '運作中' : '需設定權限'}</strong></div>
        <div class="metric"><label>活動進程數</label><strong>${snapshot.sessions.length}</strong></div>
        <div class="metric"><label>當前焦點</label><strong>${escapeHtml(active ? active.appName : '無')}</strong></div>
      `;
      
      domNodes.serverState.textContent = snapshot.listenerEnabled ? '系統權限已就緒' : '請啟用通知存取權限';
      domNodes.serverState.className = 'pill ' + (snapshot.listenerEnabled ? 'success' : 'warn');
      domNodes.sessionCount.textContent = snapshot.sessions.length + ' 個進程';
      domNodes.urlHint.textContent = window.location.href;
    }

    /**
     * 產生單一進程的 HTML 結構
     * @param {Object} session - 媒體進程資料
     * @param {boolean} isMain - 是否為主播放區塊
     * @returns {string} HTML 結構字串
     */
    function createSessionHTML(session, isMain = false) {
      const progress = session.durationMs > 0 
        ? Math.max(0, Math.min(100, (session.positionMs / session.durationMs) * 100)) 
        : 0;
        
      const coverClass = isMain ? 'now-cover' : 'now-cover small';
      
      return `
        <div class="session">
          <div class="session-top">
            <div class="${coverClass}">
              ${session.artworkDataUrl ? `<img src="${escapeHtml(session.artworkDataUrl)}" alt="Album Art">` : '<span>♪</span>'}
            </div>
            <div class="now-meta">
              <h3>${escapeHtml(isMain ? session.title : session.appName)}</h3>
              <div class="artist">${escapeHtml(isMain ? (session.artist || session.album || '未知演出者') : session.title)}</div>
              <div class="package">${escapeHtml(isMain ? `${session.appName} · ${session.packageName}` : (session.artist || session.album || '未知演出者'))}</div>
            </div>
            <div class="pill ${session.isPlaying ? 'success' : 'info'}">
              ${session.isPlaying ? '播放中' : (isMain ? '已暫停' : session.playbackState || '已暫停')}
            </div>
          </div>
          <div class="progress"><div style="width:${progress}%"></div></div>
          <div class="timing">${formatTime(session.positionMs)} / ${formatTime(session.durationMs)}</div>
          <div class="controls">
            <button class="secondary" onclick="sendControl('previous', { packageName: '${escapeHtml(session.packageName)}' })">上一首</button>
            <button class="primary" onclick="sendControl('${session.isPlaying ? 'pause' : 'play'}', { packageName: '${escapeHtml(session.packageName)}' })">${session.isPlaying ? '暫停' : '播放'}</button>
            <button class="secondary" onclick="sendControl('next', { packageName: '${escapeHtml(session.packageName)}' })">下一首</button>
          </div>
        </div>
      `;
    }

    /**
     * 渲染主播放區塊
     * @param {Object|null} session - 主要的媒體進程資料
     */
    function renderNowPlaying(session) {
      if (!session) {
        domNodes.nowPlaying.innerHTML = '<p class="hint">目前沒有進行中的媒體進程，請在裝置上開始播放內容。</p>';
        return;
      }
      domNodes.nowPlaying.innerHTML = createSessionHTML(session, true);
    }

    /**
     * 渲染所有活躍的進程列表
     * @param {Array} sessions - 所有的媒體進程陣列
     */
    function renderSessions(sessions) {
      if (!sessions || !sessions.length) {
        domNodes.sessionsContainer.innerHTML = '<p class="hint">查無其他進程。</p>';
        return;
      }
      domNodes.sessionsContainer.innerHTML = sessions.map(session => createSessionHTML(session, false)).join('');
    }

    /**
     * 狀態同步函式，向後端要求最新狀態並更新畫面
     */
    async function refresh() {
      try {
        const response = await fetch('/api/state', { cache: 'no-store' });
        if (!response.ok) throw new Error('伺服器回應異常：' + response.status);
        
        const snapshot = await response.json();
        domNodes.errorBox.style.display = 'none';
        
        renderMetrics(snapshot);
        renderNowPlaying(snapshot.sessions.find(session => session.isPlaying) || snapshot.sessions[0] || null);
        renderSessions(snapshot.sessions);
      } catch (error) {
        domNodes.errorBox.textContent = '系統發生錯誤：' + String(error);
        domNodes.errorBox.style.display = 'block';
      }
    }

    /* 綁定事件監聽器 */
    domNodes.refreshBtn.addEventListener('click', refresh);
    
    domNodes.copyBtn.addEventListener('click', async () => {
      try {
        await navigator.clipboard.writeText(window.location.href);
        domNodes.copyBtn.textContent = '已複製網址';
        setTimeout(() => domNodes.copyBtn.textContent = '複製控制網址', 2000);
      } catch (err) {
        console.error('複製失敗', err);
      }
    });

    /* 初始化並設定定時更新機制 */
    refresh();
    setInterval(refresh, 1000);
  </script>
</body>
</html>
''';
}