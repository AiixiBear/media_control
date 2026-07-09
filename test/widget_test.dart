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
  testWidgets('App renders media control hub', (WidgetTester tester) async {
    await tester.pumpWidget(
      MediaControlApp(
        api: FakeMediaControlApi(),
        autoStartServer: false,
      ),
    );

    await tester.pumpAndSettle();

    expect(find.text('Background protection'), findsOneWidget);
    expect(find.text('現在正在玩'), findsOneWidget);
  });
}
