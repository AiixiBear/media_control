/// Pure helpers for the Home Assistant-style REST API.
///
/// These were previously private methods on [MediaControlServer]; they are
/// top-level functions here so they can be unit-tested without starting
/// an HTTP server. They have no I/O and no state.
///
/// Payload shapes accepted (all three are checked, in this order):
/// the payload itself, `payload['data']`, and `payload['service_data']`.
library;

/// Extracts the action name from a Home Assistant command payload.
///
/// Looks at `action` / `command` first, then at `service`
/// (e.g. `media_player.media_play_pause` -> `media_play_pause`).
/// Returns `''` when nothing usable is present.
String extractHomeAssistantAction(Map<String, dynamic> payload) {
  final action = extractStringField(payload, <String>['action', 'command']);
  if (action != null && action.trim().isNotEmpty) {
    return action.trim();
  }

  final service = extractStringField(payload, <String>['service']);
  if (service != null && service.trim().isNotEmpty) {
    final trimmed = service.trim();
    final dotIndex = trimmed.lastIndexOf('.');
    return dotIndex >= 0 ? trimmed.substring(dotIndex + 1) : trimmed;
  }

  return '';
}

/// Extracts a non-empty string field, checking the payload, its `data`
/// map and its `service_data` map, in that order.
String? extractStringField(Map<String, dynamic> payload, List<String> keys) {
  for (final candidate in candidatePayloads(payload)) {
    for (final key in keys) {
      final raw = candidate[key];
      if (raw is String && raw.trim().isNotEmpty) {
        return raw.trim();
      }
    }
  }
  return null;
}

/// Extracts a seek position in milliseconds.
///
/// Millisecond keys are tried first (`positionMs`, `position_ms`,
/// `seek_position_ms`, `seekPosition`), then second keys
/// (`position`, `seek_position`, `media_position`), which are
/// interpreted as seconds. Returns `null` when no position is present,
/// and throws [ArgumentError] when [required] is true and none is found.
int? extractSeekPositionMs(
  Map<String, dynamic> payload, {
  bool required = false,
}) {
  const msKeys = <String>[
    'positionMs',
    'position_ms',
    'seek_position_ms',
    'seekPosition',
  ];
  const secondKeys = <String>['position', 'seek_position', 'media_position'];

  for (final candidate in candidatePayloads(payload)) {
    for (final key in msKeys) {
      final value = _toDouble(candidate[key]);
      if (value != null) {
        return value.round().clamp(0, 1 << 31);
      }
    }
  }

  for (final candidate in candidatePayloads(payload)) {
    for (final key in secondKeys) {
      final value = _toDouble(candidate[key]);
      if (value != null) {
        return (value * 1000).round().clamp(0, 1 << 31);
      }
    }
  }

  if (required) {
    throw ArgumentError(
      'Missing seek position. Provide positionMs or seek_position (seconds).',
    );
  }
  return null;
}

/// The payload itself, plus its nested `data` and `service_data` maps.
List<Map<String, dynamic>> candidatePayloads(Map<String, dynamic> payload) {
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
