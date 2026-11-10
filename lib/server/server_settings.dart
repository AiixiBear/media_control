import 'dart:io';
import 'dart:math';

/// Local-server access settings.
///
/// The password is a single shared token for the local Web UI and the
/// Home Assistant-style REST API. It is stored on-device only, in
/// SharedPreferences (`server_password`), and is never hard-coded.
///
/// Two ways to present it (both are accepted when a password is set):
///
/// 1. **Bearer / API-key header (recommended)** — the token never appears
///    in the URL, so it is not written to browser history, server logs or
///    `Referer` headers:
///    `Authorization: Bearer <password>` or `X-Api-Key: <password>`
/// 2. **Legacy path prefix** — `http://<phone>:8080/<password>/` and
///    `http://<phone>:8080/<password>/api/state`. Kept so existing
///    bookmarks and the Home Assistant integration keep working.
///
/// When no password is set the server is open to anyone on the local
/// network. The app UI warns about this; see README for how to set one.
class ServerSettings {
  const ServerSettings({
    this.password = '',
    this.listenInterface = '0.0.0.0',
    this.port = defaultPort,
    this.webUiUpdateMode = defaultWebUiUpdateMode,
  });

  /// Minimum length for a password set in the settings UI.
  static const int minPasswordLength = 8;

  /// Default server port (also the port used before this setting existed).
  static const int defaultPort = 8080;

  /// Web UI live-update modes: 'sse' (server pushes, default) or
  /// 'polling' (the browser re-fetches /api/state every second).
  static const String defaultWebUiUpdateMode = 'sse';
  static const List<String> webUiUpdateModes = <String>['sse', 'polling'];

  final String password;
  final String listenInterface;
  final int port;
  final String webUiUpdateMode;

  /// Port actually used: falls back to [defaultPort] when out of range.
  int get normalizedPort => port >= 1 && port <= 65535 ? port : defaultPort;

  /// Update mode actually used: unknown values fall back to 'sse'.
  String get normalizedWebUiUpdateMode =>
      webUiUpdateModes.contains(webUiUpdateMode.trim().toLowerCase())
      ? webUiUpdateMode.trim().toLowerCase()
      : defaultWebUiUpdateMode;

  /// Chinese label for the update mode, for the settings UI.
  String get webUiUpdateModeLabel =>
      normalizedWebUiUpdateMode == 'polling' ? '每秒輪詢' : '即時推送 (SSE)';

  String get normalizedPassword => password.trim();

  /// True when a password is set and every request must present it.
  bool get authRequired => normalizedPassword.isNotEmpty;

  String get routePrefix {
    final cleanedPassword = normalizedPassword;
    if (cleanedPassword.isEmpty) {
      return '';
    }
    return '/$cleanedPassword';
  }

  String get normalizedListenInterface {
    final cleanedInterface = listenInterface.trim();
    if (cleanedInterface.isEmpty) {
      return '0.0.0.0';
    }
    return cleanedInterface;
  }

  ServerSettings copyWith({
    String? password,
    String? listenInterface,
    int? port,
    String? webUiUpdateMode,
  }) {
    return ServerSettings(
      password: password ?? this.password,
      listenInterface: listenInterface ?? this.listenInterface,
      port: port ?? this.port,
      webUiUpdateMode: webUiUpdateMode ?? this.webUiUpdateMode,
    );
  }

  /// Validates a port typed in the settings UI. Returns `null` when the
  /// value is a usable TCP port (1-65535), otherwise a Traditional
  /// Chinese error message.
  static String? validatePort(String value) {
    final cleaned = value.trim();
    if (cleaned.isEmpty) {
      return '請輸入連接埠，例如 $defaultPort';
    }
    final parsed = int.tryParse(cleaned);
    if (parsed == null) {
      return '連接埠必須是數字';
    }
    if (parsed < 1 || parsed > 65535) {
      return '連接埠必須在 1 到 65535 之間';
    }
    return null;
  }

  /// Legacy check: is this URL path under the password prefix?
  /// Kept for backwards compatibility and for the existing widget test.
  bool isPathAllowed(String path) {
    final cleanedPath = path.trim();
    if (cleanedPath.isEmpty || cleanedPath == '/') {
      return normalizedPassword.isEmpty;
    }

    if (normalizedPassword.isEmpty) {
      return true;
    }

    final prefix = routePrefix;
    return cleanedPath == prefix ||
        cleanedPath == '$prefix/' ||
        cleanedPath.startsWith('$prefix/');
  }

  /// Full authorisation check for one HTTP request.
  ///
  /// Accepts, in order: the legacy path prefix, a `Bearer` token, or an
  /// `X-Api-Key` header. When no password is set, everything is allowed
  /// (the previous behaviour — the app warns about this instead).
  bool isAuthorized(HttpRequest request) {
    if (!authRequired) {
      return true;
    }
    if (isPathAllowed(request.uri.path)) {
      return true;
    }
    final token = extractBearerToken(request) ?? extractApiKey(request);
    if (token == null) {
      return false;
    }
    return _constantTimeEquals(token, normalizedPassword);
  }

  /// Returns the token from `Authorization: Bearer <token>`, if present.
  String? extractBearerToken(HttpRequest request) {
    final header = request.headers.value(HttpHeaders.authorizationHeader);
    if (header == null) {
      return null;
    }
    const scheme = 'bearer ';
    if (header.length <= scheme.length ||
        header.substring(0, scheme.length).toLowerCase() != scheme) {
      return null;
    }
    final token = header.substring(scheme.length).trim();
    return token.isEmpty ? null : token;
  }

  /// Returns the token from `X-Api-Key: <token>`, if present.
  String? extractApiKey(HttpRequest request) {
    final header = request.headers.value('x-api-key');
    if (header == null || header.trim().isEmpty) {
      return null;
    }
    return header.trim();
  }

  /// Validates a password typed in the settings UI.
  ///
  /// Returns `null` when the value is acceptable, otherwise a
  /// Traditional-Chinese error message to show in the UI. An empty value
  /// is acceptable (it means "no password"), but the app warns about it.
  static String? validatePassword(String password) {
    final cleaned = password.trim();
    if (cleaned.isEmpty) {
      return null;
    }
    if (cleaned.length < minPasswordLength) {
      return '密碼至少需要 $minPasswordLength 個字元';
    }
    if (cleaned.contains(RegExp(r'\s'))) {
      return '密碼不能包含空白';
    }
    if (cleaned.contains(RegExp(r'[/?#\\<>]'))) {
      return '密碼不能包含 / ? # \\ < >';
    }
    return null;
  }

  /// Generates a random 16-character token (letters + digits) for the
  /// "產生隨機密碼" button in the settings UI.
  static String generateToken({int length = 16}) {
    const alphabet =
        'abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789';
    final random = Random.secure();
    return List<String>.generate(
      length,
      (_) => alphabet[random.nextInt(alphabet.length)],
    ).join();
  }

  String buildUrl(String host, int port) {
    final baseUrl = 'http://$host:$port';
    if (normalizedPassword.isEmpty) {
      return baseUrl;
    }
    return '$baseUrl$routePrefix/';
  }

  /// Constant-time string comparison, so a wrong token does not fail
  /// measurably faster than a nearly-right one.
  static bool _constantTimeEquals(String a, String b) {
    if (a.length != b.length) {
      return false;
    }
    var diff = 0;
    for (var i = 0; i < a.length; i++) {
      diff |= a.codeUnitAt(i) ^ b.codeUnitAt(i);
    }
    return diff == 0;
  }
}
