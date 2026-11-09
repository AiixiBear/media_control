import 'package:flutter/services.dart';

import '../models/media.dart';

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
    final dynamic result = await _channel.invokeMethod<dynamic>(
      'getMediaSnapshot',
    );
    if (result is Map) {
      return MediaSnapshot.fromMap(result.cast<String, dynamic>());
    }
    return MediaSnapshot.empty();
  }

  @override
  Future<void> play({String? packageName}) =>
      _sendControl('play', packageName: packageName);

  @override
  Future<void> pause({String? packageName}) =>
      _sendControl('pause', packageName: packageName);

  @override
  Future<void> next({String? packageName}) =>
      _sendControl('next', packageName: packageName);

  @override
  Future<void> previous({String? packageName}) =>
      _sendControl('previous', packageName: packageName);

  @override
  Future<void> seekTo({String? packageName, required Duration position}) =>
      _sendControl(
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
    final dynamic result = await _channel.invokeMethod<dynamic>(
      'ensureNotificationPermission',
    );
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
      <String, dynamic>{'webUrl': ?webUrl},
    );
  }

  Future<void> _sendControl(
    String method, {
    String? packageName,
    Map<String, dynamic> extra = const <String, dynamic>{},
  }) async {
    final payload = <String, dynamic>{'packageName': ?packageName, ...extra};
    await _channel.invokeMethod<void>(method, payload);
  }
}
