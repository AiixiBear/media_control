import 'package:flutter_test/flutter_test.dart';

import 'package:media_control/main.dart';

class FakeMediaControlApi implements MediaControlApi {
  @override
  Future<MediaSnapshot> getSnapshot() async {
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
  Future<void> next({String? packageName}) async {}

  @override
  Future<void> openNotificationSettings() async {}

  @override
  Future<bool> ensureNotificationPermission() async => true;

  @override
  Future<void> startBackgroundProtection() async {}

  @override
  Future<void> updateBackgroundProtectionNotification({String? webUrl}) async {}

  @override
  Future<void> pause({String? packageName}) async {}

  @override
  Future<void> play({String? packageName}) async {}

  @override
  Future<void> previous({String? packageName}) async {}

  @override
  Future<void> seekTo({String? packageName, required Duration position}) async {}
}

void main() {
  test('password routes are scoped correctly', () {
    const settings = ServerSettings(password: 'secret');

    expect(settings.routePrefix, '/secret');
    expect(settings.isPathAllowed('/secret/'), isTrue);
    expect(settings.isPathAllowed('/secret/api/state'), isTrue);
    expect(settings.isPathAllowed('/api/state'), isFalse);
    expect(settings.isPathAllowed('/'), isFalse);
  });

  testWidgets('App renders media control hub', (WidgetTester tester) async {
    await tester.pumpWidget(
      MediaControlApp(
        api: FakeMediaControlApi(),
        autoStartServer: false,
      ),
    );

    await tester.pumpAndSettle();

    expect(find.text('蜘蛛網 UI 端點'), findsOneWidget);
    expect(find.text('大便媒體控制'), findsWidgets);
  });
}
