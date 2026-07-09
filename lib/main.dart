import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
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
        final action = (payload['action'] as String? ?? '').trim();
        final packageName = payload['packageName'] as String?;
        final positionMs = (payload['positionMs'] as num?)?.round();

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
            final positionMs = (payload['positionMs'] as num?)?.round() ?? 0;
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
        await api.seekTo(
          packageName: packageName,
          position: Duration(milliseconds: positionMs ?? 0),
        );
        return;
      default:
        throw ArgumentError('Unknown Home Assistant action: $action');
    }
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
      'entity_id': entityId,
      'state': state,
      'attributes': <String, dynamic>{
        'friendly_name': 'Media Control Hub',
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
      'entity_id': entityId,
      'name': 'Media Control Hub',
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
      title: 'S',
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
                  label: serverRunning ? '狗屎蜘蛛網頁服務員正在跑' : '伺服器嚴肅停止',
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
      title: 'Background protection',
      subtitle: 'Uses a persistent notification so Android is less likely to stop the app while media control is active.',
      trailing: _StatusChip(label: enabled ? 'Running' : 'Stopped', color: accent),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            enabled
                ? 'The keep-alive notification is active. Leave it running while other devices use the web dashboard.'
                : 'Turn on the persistent notification to keep the local server and media bridge alive in the background.',
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
    :root {
      color-scheme: dark;
      --bg: #07111d;
      --panel: rgba(14, 23, 39, 0.74);
      --panel-border: rgba(255, 255, 255, 0.08);
      --muted: rgba(226, 232, 240, 0.72);
      --accent: #5ce1e6;
      --accent-strong: #15c89a;
      --warning: #f59e0b;
      --shadow: 0 24px 80px rgba(0, 0, 0, 0.38);
    }

    * { box-sizing: border-box; }

    body {
      margin: 0;
      min-height: 100vh;
      font-family: Inter, Segoe UI, Roboto, Helvetica, Arial, sans-serif;
      background:
        radial-gradient(circle at top left, rgba(92, 225, 230, 0.18), transparent 28%),
        radial-gradient(circle at top right, rgba(21, 200, 154, 0.12), transparent 22%),
        linear-gradient(180deg, #08111f 0%, #0b1729 48%, #050b14 100%);
      color: white;
    }

    .shell {
      width: min(1120px, calc(100% - 32px));
      margin: 0 auto;
      padding: 24px 0 40px;
    }

    .hero {
      border: 1px solid var(--panel-border);
      border-radius: 28px;
      padding: 28px;
      background: linear-gradient(145deg, rgba(20, 49, 73, 0.92), rgba(10, 20, 36, 0.92));
      box-shadow: var(--shadow);
    }

    .eyebrow {
      display: inline-flex;
      align-items: center;
      gap: 8px;
      padding: 8px 12px;
      border-radius: 999px;
      border: 1px solid rgba(92, 225, 230, 0.26);
      background: rgba(92, 225, 230, 0.12);
      color: var(--accent);
      font-size: 12px;
      font-weight: 700;
      letter-spacing: 0.08em;
      text-transform: uppercase;
    }

    h1 {
      margin: 16px 0 10px;
      font-size: clamp(36px, 6vw, 68px);
      line-height: 0.95;
      letter-spacing: -0.05em;
    }

    .lede {
      max-width: 760px;
      margin: 0;
      color: var(--muted);
      font-size: 16px;
      line-height: 1.6;
    }

    .toolbar {
      display: flex;
      flex-wrap: wrap;
      gap: 12px;
      margin-top: 22px;
    }

    button {
      appearance: none;
      border: 0;
      border-radius: 14px;
      padding: 12px 16px;
      font: inherit;
      font-weight: 700;
      color: white;
      cursor: pointer;
      transition: transform 0.15s ease, opacity 0.15s ease, box-shadow 0.15s ease;
    }

    button:hover { transform: translateY(-1px); }
    button:disabled { opacity: 0.45; cursor: not-allowed; transform: none; }

    .primary {
      background: linear-gradient(135deg, var(--accent), #3b82f6);
      box-shadow: 0 12px 30px rgba(92, 225, 230, 0.22);
      color: #07111d;
    }

    .secondary {
      background: rgba(255, 255, 255, 0.06);
      border: 1px solid rgba(255, 255, 255, 0.08);
    }

    .grid {
      display: grid;
      grid-template-columns: repeat(12, minmax(0, 1fr));
      gap: 16px;
      margin-top: 18px;
    }

    .card {
      grid-column: span 12;
      border: 1px solid var(--panel-border);
      border-radius: 24px;
      background: var(--panel);
      backdrop-filter: blur(18px);
      box-shadow: var(--shadow);
      padding: 20px;
    }

    .card-header {
      display: flex;
      justify-content: space-between;
      gap: 16px;
      align-items: flex-start;
      margin-bottom: 16px;
    }

    .title { margin: 0; font-size: 20px; font-weight: 800; }
    .subtitle { margin: 4px 0 0; color: var(--muted); line-height: 1.5; }

    .pill {
      border-radius: 999px;
      padding: 8px 12px;
      font-size: 12px;
      font-weight: 800;
      white-space: nowrap;
    }

    .pill.success { background: rgba(21, 200, 154, 0.16); color: var(--accent-strong); border: 1px solid rgba(21, 200, 154, 0.28); }
    .pill.warn { background: rgba(245, 158, 11, 0.16); color: var(--warning); border: 1px solid rgba(245, 158, 11, 0.28); }
    .pill.info { background: rgba(96, 165, 250, 0.16); color: #93c5fd; border: 1px solid rgba(96, 165, 250, 0.28); }

    .meta {
      display: grid;
      grid-template-columns: repeat(auto-fit, minmax(170px, 1fr));
      gap: 12px;
    }

    .metric {
      padding: 14px;
      border-radius: 18px;
      background: rgba(255, 255, 255, 0.04);
      border: 1px solid rgba(255, 255, 255, 0.06);
    }

    .metric label {
      display: block;
      color: var(--muted);
      font-size: 12px;
      margin-bottom: 6px;
      text-transform: uppercase;
      letter-spacing: 0.08em;
    }

    .metric strong { font-size: 17px; }

    .sessions { display: grid; gap: 14px; }

    .session {
      padding: 16px;
      border-radius: 18px;
      background: rgba(255, 255, 255, 0.04);
      border: 1px solid rgba(255, 255, 255, 0.06);
    }

    .session-top {
      display: flex;
      gap: 14px;
      justify-content: space-between;
      align-items: flex-start;
    }

    .now-cover {
      width: 104px;
      height: 104px;
      flex: 0 0 auto;
      border-radius: 20px;
      overflow: hidden;
      display: grid;
      place-items: center;
      font-size: 34px;
      font-weight: 800;
      color: rgba(255, 255, 255, 0.82);
      background: linear-gradient(135deg, rgba(92, 225, 230, 0.22), rgba(59, 130, 246, 0.22));
      border: 1px solid rgba(255, 255, 255, 0.08);
    }

    .now-cover.small {
      width: 64px;
      height: 64px;
      border-radius: 16px;
      font-size: 20px;
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

    .session h3 { margin: 0; font-size: 18px; }
    .session .artist, .session .package, .session .timing { margin: 6px 0 0; color: var(--muted); }

    .progress {
      margin: 14px 0 10px;
      height: 10px;
      border-radius: 999px;
      overflow: hidden;
      background: rgba(255, 255, 255, 0.08);
    }

    .progress > div {
      height: 100%;
      width: 0%;
      background: linear-gradient(90deg, var(--accent), #3b82f6);
      border-radius: inherit;
      transition: width 0.25s ease;
    }

    .controls {
      display: flex;
      flex-wrap: wrap;
      gap: 10px;
      margin-top: 14px;
    }

    .danger {
      color: #fecaca;
      background: rgba(251, 113, 133, 0.14);
      border: 1px solid rgba(251, 113, 133, 0.26);
      padding: 14px 16px;
      border-radius: 16px;
      margin-top: 16px;
      display: none;
    }

    .hint { color: var(--muted); line-height: 1.55; }

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
      <div class="eyebrow">本地媒體橋接</div>
      <h1>透過區域網路，在任何裝置上遙控手機。</h1>
      <p class="lede">
        這個頁面會讀取安卓正在使用的媒體進程，顯示歌曲資訊與播放進度，並且可以送出播放、暫停、上一首、下一首、拖曲等控制指令。
      </p>
      <div class="toolbar">
        <button class="primary" id="refreshBtn">重刷媒體州</button>
        <button class="secondary" id="copyBtn">拷貝網址</button>
      </div>
      <div class="danger" id="errorBox"></div>
    </section>

    <section class="grid">
      <article class="card span-7">
        <div class="card-header">
          <div>
            <h2 class="title">即時快照</h2>
            <p class="subtitle">只要開著這頁，就會每秒從手機撈一次資料。</p>
          </div>
          <div class="pill info" id="serverState">載入中</div>
        </div>
        <div class="meta" id="metrics"></div>
      </article>

      <article class="card span-5">
        <div class="card-header">
          <div>
            <h2 class="title">怎麼用</h2>
            <p class="subtitle">打開這個URL在其他裝置在同一個無線網路</p>
          </div>
        </div>
        <p class="hint">
          如果沒有顯示媒體，去手機的設定裡開啟這個App的通知存取權限。然後在手機上開始播放音樂或影片，再回來這頁看看。
        </p>
        <p class="hint" id="urlHint"></p>
      </article>

      <article class="card span-12">
        <div class="card-header">
          <div>
            <h2 class="title">現在正在玩</h2>
            <p class="subtitle">這裡會顯示目前最相關的播放進程。</p>
          </div>
          <div class="pill success" id="sessionCount">0 個進程</div>
        </div>
        <div id="nowPlaying"></div>
      </article>

      <article class="card span-12">
        <div class="card-header">
          <div>
            <h2 class="title">上線進程</h2>
            <p class="subtitle">每張卡片都能各自控制對應的播放進程（如果App有開放的話）。</p>
          </div>
        </div>
        <div class="sessions" id="sessions"></div>
      </article>
    </section>
  </main>

  <script>
    const metrics = document.getElementById('metrics');
    const sessionsContainer = document.getElementById('sessions');
    const nowPlaying = document.getElementById('nowPlaying');
    const errorBox = document.getElementById('errorBox');
    const serverState = document.getElementById('serverState');
    const sessionCount = document.getElementById('sessionCount');
    const urlHint = document.getElementById('urlHint');

    function formatTime(ms) {
      if (!ms || ms <= 0) {
        return '--:--';
      }
      const totalSeconds = Math.floor(ms / 1000);
      const minutes = Math.floor(totalSeconds / 60);
      const seconds = totalSeconds % 60;
      return String(minutes).padStart(2, '0') + ':' + String(seconds).padStart(2, '0');
    }

    function escapeHtml(value) {
      return String(value)
        .replaceAll('&', '&amp;')
        .replaceAll('<', '&lt;')
        .replaceAll('>', '&gt;')
        .replaceAll('"', '&quot;')
        .replaceAll("'", '&#39;');
    }

    async function sendControl(action, payload = {}) {
      await fetch('/api/control/' + action, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify(payload),
      });
      await refresh();
    }

    function renderMetrics(snapshot) {
      const active = snapshot.sessions.find(session => session.isPlaying) || snapshot.sessions[0] || null;
      metrics.innerHTML = `
        <div class="metric"><label>通知監聽器</label><strong>${snapshot.listenerEnabled ? '啟用' : '需要設定上面'}</strong></div>
        <div class="metric"><label>進程數</label><strong>${snapshot.sessions.length}</strong></div>
        <div class="metric"><label>焦點</label><strong>${escapeHtml(active ? active.appName : '沒有')}</strong></div>
      `;
      serverState.textContent = snapshot.listenerEnabled ? '媒體權限已就緒' : '去啟用權限讓我可以看你通知拉齁';
      serverState.className = 'pill ' + (snapshot.listenerEnabled ? 'success' : 'warn');
      sessionCount.textContent = snapshot.sessions.length + ' 個進程';
      urlHint.textContent = window.location.href;
    }

    function renderNowPlaying(session) {
      if (!session) {
        nowPlaying.innerHTML = '<p class="hint">沒有媒體進程，去播音樂阿。</p>';
        return;
      }

      const progress = session.durationMs > 0 ? Math.max(0, Math.min(100, (session.positionMs / session.durationMs) * 100)) : 0;
      nowPlaying.innerHTML = `
        <div class="session">
          <div class="session-top">
            <div class="now-cover">${session.artworkDataUrl ? `<img src="${escapeHtml(session.artworkDataUrl)}" alt="cover art">` : '<span>♪</span>'}</div>
            <div class="now-meta">
              <h3>${escapeHtml(session.title)}</h3>
              <div class="artist">${escapeHtml(session.artist || session.album || '沒有藝人資訊')}</div>
              <div class="package">${escapeHtml(session.appName)} · ${escapeHtml(session.packageName)}</div>
            </div>
            <div class="pill ${session.isPlaying ? 'success' : 'info'}">${session.isPlaying ? '正在玩' : '已經暫停'}</div>
          </div>
          <div class="progress"><div style="width:${progress}%"></div></div>
          <div class="timing">${formatTime(session.positionMs)} / ${formatTime(session.durationMs)}</div>
          <div class="controls">
            <button class="secondary" onclick="sendControl('previous', { packageName: '${escapeHtml(session.packageName)}' })">Previous</button>
            <button class="primary" onclick="sendControl('${session.isPlaying ? 'pause' : 'play'}', { packageName: '${escapeHtml(session.packageName)}' })">${session.isPlaying ? 'Pause' : 'Play'}</button>
            <button class="secondary" onclick="sendControl('next', { packageName: '${escapeHtml(session.packageName)}' })">Next</button>
          </div>
        </div>
      `;
    }

    function renderSessions(sessions) {
      if (!sessions.length) {
        sessionsContainer.innerHTML = '<p class="hint">就沒有啊。</p>';
        return;
      }

      sessionsContainer.innerHTML = sessions.map(session => {
        const progress = session.durationMs > 0 ? Math.max(0, Math.min(100, (session.positionMs / session.durationMs) * 100)) : 0;
        return `
          <div class="session">
            <div class="session-top">
              <div class="now-cover small">${session.artworkDataUrl ? `<img src="${escapeHtml(session.artworkDataUrl)}" alt="cover art">` : '<span>♪</span>'}</div>
              <div class="now-meta">
                <h3>${escapeHtml(session.appName)}</h3>
                <div class="artist">${escapeHtml(session.title)}</div>
                <div class="package">${escapeHtml(session.artist || session.album || '沒有藝人資訊')}</div>
              </div>
              <div class="pill ${session.isPlaying ? 'success' : 'info'}">${session.isPlaying ? 'Playing' : session.playbackState}</div>
            </div>
            <div class="progress"><div style="width:${progress}%"></div></div>
            <div class="timing">${formatTime(session.positionMs)} / ${formatTime(session.durationMs)}</div>
            <div class="controls">
              <button class="secondary" onclick="sendControl('previous', { packageName: '${escapeHtml(session.packageName)}' })">Previous</button>
              <button class="primary" onclick="sendControl('${session.isPlaying ? 'pause' : 'play'}', { packageName: '${escapeHtml(session.packageName)}' })">${session.isPlaying ? 'Pause' : 'Play'}</button>
              <button class="secondary" onclick="sendControl('next', { packageName: '${escapeHtml(session.packageName)}' })">Next</button>
            </div>
          </div>
        `;
      }).join('');
    }

    async function refresh() {
      try {
        const response = await fetch('/api/state', { cache: 'no-store' });
        const snapshot = await response.json();
        errorBox.style.display = 'none';
        renderMetrics(snapshot);
        renderNowPlaying(snapshot.sessions.find(session => session.isPlaying) || snapshot.sessions[0] || null);
        renderSessions(snapshot.sessions);
      } catch (error) {
        errorBox.textContent = String(error);
        errorBox.style.display = 'block';
      }
    }

    document.getElementById('refreshBtn').addEventListener('click', refresh);
    document.getElementById('copyBtn').addEventListener('click', async () => {
      await navigator.clipboard.writeText(window.location.href);
      document.getElementById('copyBtn').textContent = '已拷貝';
      setTimeout(() => document.getElementById('copyBtn').textContent = '拷貝網址', 1500);
    });

    refresh();
    setInterval(refresh, 1000);
  </script>
</body>
</html>
r''';
}