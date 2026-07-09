import 'dart:io';
import 'package:device_info_plus/device_info_plus.dart';

class DeviceUtil {
  // 💡 改成標準字串變數，預設為未知
  static String currentName = 'Unknown Device';

  // 💡 在 main.dart 啟動時呼叫此方法初始化
  static Future<void> init() async {
    try {
      final DeviceInfoPlugin deviceInfo = DeviceInfoPlugin();
      if (Platform.isAndroid) {
        final AndroidDeviceInfo androidInfo = await deviceInfo.androidInfo;
        currentName = androidInfo.model;
      }
    } catch (e) {
      currentName = 'Unknown Device';
    }
  }
}
