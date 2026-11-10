import 'package:flutter_test/flutter_test.dart';

import 'package:media_control/main.dart';

void main() {
  group('ServerSettings.validatePassword', () {
    test('empty password is allowed (means: no password)', () {
      expect(ServerSettings.validatePassword(''), isNull);
      expect(ServerSettings.validatePassword('   '), isNull);
    });

    test('short passwords are rejected', () {
      expect(ServerSettings.validatePassword('abc'), isNotNull);
      expect(ServerSettings.validatePassword('1234567'), isNotNull);
      expect(ServerSettings.validatePassword('12345678'), isNull);
    });

    test('whitespace and URL-breaking characters are rejected', () {
      expect(ServerSettings.validatePassword('has space1'), isNotNull);
      expect(ServerSettings.validatePassword('has/slash1'), isNotNull);
      expect(ServerSettings.validatePassword('has?mark12'), isNotNull);
      expect(ServerSettings.validatePassword('has#hash12'), isNotNull);
    });

    test('a normal password passes', () {
      expect(ServerSettings.validatePassword('correct-horse-1'), isNull);
    });
  });

  group('ServerSettings.generateToken', () {
    test('generates a 16-character alphanumeric token by default', () {
      final token = ServerSettings.generateToken();
      expect(token.length, 16);
      expect(token, matches(RegExp(r'^[A-Za-z0-9]{16}$')));
    });

    test(
      'generates the requested length and (almost always) unique values',
      () {
        final first = ServerSettings.generateToken(length: 24);
        final second = ServerSettings.generateToken(length: 24);
        expect(first.length, 24);
        expect(second.length, 24);
        expect(first, isNot(second));
      },
    );
  });

  group('ServerSettings legacy path prefix (backwards compatibility)', () {
    test('authRequired is false without a password', () {
      const settings = ServerSettings();
      expect(settings.authRequired, isFalse);
      expect(settings.routePrefix, '');
      expect(settings.isPathAllowed('/api/state'), isTrue);
    });

    test('authRequired is true with a password', () {
      const settings = ServerSettings(password: 'secret-123');
      expect(settings.authRequired, isTrue);
      expect(settings.routePrefix, '/secret-123');
      expect(settings.isPathAllowed('/secret-123/api/state'), isTrue);
      expect(settings.isPathAllowed('/api/state'), isFalse);
    });
  });

  group('extractHomeAssistantAction', () {
    test('prefers action, then command, then service', () {
      expect(
        extractHomeAssistantAction(<String, dynamic>{'action': 'media_play'}),
        'media_play',
      );
      expect(
        extractHomeAssistantAction(<String, dynamic>{'command': 'pause'}),
        'pause',
      );
      expect(
        extractHomeAssistantAction(<String, dynamic>{
          'service': 'media_player.media_next_track',
        }),
        'media_next_track',
      );
      expect(extractHomeAssistantAction(<String, dynamic>{}), '');
    });

    test('reads nested data and service_data maps', () {
      expect(
        extractHomeAssistantAction(<String, dynamic>{
          'data': <String, dynamic>{'action': 'media_seek'},
        }),
        'media_seek',
      );
    });
  });

  group('extractSeekPositionMs', () {
    test('millisecond keys win over second keys', () {
      expect(
        extractSeekPositionMs(<String, dynamic>{
          'positionMs': 42000,
          'position': 999,
        }),
        42000,
      );
      expect(extractSeekPositionMs(<String, dynamic>{'position': 42}), 42000);
      expect(
        extractSeekPositionMs(<String, dynamic>{'seek_position': 1.5}),
        1500,
      );
    });

    test('reads nested payloads and returns null when missing', () {
      expect(
        extractSeekPositionMs(<String, dynamic>{
          'service_data': <String, dynamic>{'positionMs': 1000},
        }),
        1000,
      );
      expect(extractSeekPositionMs(<String, dynamic>{}), isNull);
      expect(
        () => extractSeekPositionMs(<String, dynamic>{}, required: true),
        throwsArgumentError,
      );
    });

    test('clamps negative and huge values', () {
      expect(extractSeekPositionMs(<String, dynamic>{'positionMs': -5}), 0);
    });
  });

  group('ServerSettings.validatePort', () {
    test('accepts normal ports and rejects bad ones', () {
      expect(ServerSettings.validatePort('8080'), isNull);
      expect(ServerSettings.validatePort('1'), isNull);
      expect(ServerSettings.validatePort('65535'), isNull);
      expect(ServerSettings.validatePort(''), isNotNull);
      expect(ServerSettings.validatePort('abc'), isNotNull);
      expect(ServerSettings.validatePort('0'), isNotNull);
      expect(ServerSettings.validatePort('65536'), isNotNull);
      expect(ServerSettings.validatePort('-1'), isNotNull);
    });
  });

  group('ServerSettings port and update mode', () {
    test('defaults are 8080 and SSE', () {
      const settings = ServerSettings();
      expect(settings.normalizedPort, 8080);
      expect(settings.normalizedWebUiUpdateMode, 'sse');
      expect(settings.webUiUpdateModeLabel, '即時推送 (SSE)');
    });

    test('out-of-range ports fall back to 8080', () {
      expect(const ServerSettings(port: 0).normalizedPort, 8080);
      expect(const ServerSettings(port: 70000).normalizedPort, 8080);
      expect(const ServerSettings(port: 9090).normalizedPort, 9090);
    });

    test('unknown update modes fall back to SSE', () {
      expect(
        const ServerSettings(webUiUpdateMode: 'websocket')
            .normalizedWebUiUpdateMode,
        'sse',
      );
      expect(
        const ServerSettings(webUiUpdateMode: 'polling')
            .normalizedWebUiUpdateMode,
        'polling',
      );
      expect(
        const ServerSettings(webUiUpdateMode: 'polling').webUiUpdateModeLabel,
        '每秒輪詢',
      );
    });

    test('copyWith keeps the other fields', () {
      const settings = ServerSettings(password: 'secret-123', port: 9090);
      final copied = settings.copyWith(port: 8081);
      expect(copied.password, 'secret-123');
      expect(copied.port, 8081);
      expect(copied.webUiUpdateMode, 'sse');
    });
  });

  group('extractStringField', () {
    test('falls back across keys and nested maps', () {
      expect(
        extractStringField(
          <String, dynamic>{'package_name': 'com.example.music'},
          <String>['packageName', 'package_name'],
        ),
        'com.example.music',
      );
      expect(
        extractStringField(<String, dynamic>{}, <String>['packageName']),
        isNull,
      );
    });
  });
}
