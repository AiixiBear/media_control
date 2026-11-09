import 'package:flutter/material.dart';

import 'device_util.dart';
import 'ui/app.dart';

export 'api/media_control_api.dart';
export 'models/media.dart';
export 'server/home_assistant.dart';
export 'server/media_control_server.dart';
export 'server/server_settings.dart';
export 'ui/app.dart';
export 'ui/app_colors.dart';
export 'ui/app_settings.dart';
export 'ui/settings_page.dart';
export 'ui/widgets.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await DeviceUtil.init();
  runApp(const MediaControlApp());
}
