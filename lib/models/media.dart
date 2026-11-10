import 'dart:convert';
import 'dart:typed_data';

import '../device_util.dart';

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
        .map(
          (Map<dynamic, dynamic> item) =>
              MediaSessionInfo.fromMap(item.cast<String, dynamic>()),
        )
        .toList(growable: false);

    return MediaSnapshot(
      listenerEnabled: map['listenerEnabled'] as bool? ?? false,
      sessions: sessions,
      timestamp: DateTime.fromMillisecondsSinceEpoch(
        (map['timestampMs'] as num?)?.round() ??
            DateTime.now().millisecondsSinceEpoch,
      ),
    );
  }

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'listenerEnabled': listenerEnabled,
      'timestampMs': timestamp.millisecondsSinceEpoch,
      'sessions': sessions
          .map((MediaSessionInfo session) => session.toJson())
          .toList(growable: false),
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
      'entity_id':
          '${entityId}_${DeviceUtil.currentName.replaceAll(' ', '_').toLowerCase()}',
      'state': state,
      'attributes': <String, dynamic>{
        'friendly_name': '大便媒體控制 - ${DeviceUtil.currentName}',
        'media_title': active?.title,
        'media_artist': active?.artist.isNotEmpty == true
            ? active?.artist
            : active?.displayArtist,
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

  Map<String, dynamic> toHomeAssistantConfigJson(
    String entityId, {
    bool authRequired = false,
  }) {
    return <String, dynamic>{
      'entity_id':
          '${entityId}_${DeviceUtil.currentName.replaceAll(' ', '_').toLowerCase()}',
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
      // Auth is described here, never the token itself. When a password
      // is set in the app, callers must send it as a Bearer token
      // (recommended) or use the legacy /<password>/ path prefix.
      // Kept in sync with ServerSettings in lib/server/server_settings.dart.
      'requires_auth': authRequired,
      'auth': <String, dynamic>{
        'type': 'bearer',
        'header': 'Authorization',
        'scheme': 'Bearer',
        'alternative_header': 'X-Api-Key',
        'legacy_path_prefix': '/<password>',
      },
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
      appName:
          map['appName'] as String? ??
          map['packageName'] as String? ??
          'Unknown app',
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

Uint8List decodeDataUrl(String dataUrl) {
  final commaIndex = dataUrl.indexOf(',');
  if (commaIndex < 0) {
    return Uint8List(0);
  }
  return base64Decode(dataUrl.substring(commaIndex + 1));
}
