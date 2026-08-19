import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';

import 'admin/admin_desktop_app.dart';
import 'services/backend_service.dart';
import 'services/avatar_cache.dart';
import 'services/network_status_service.dart';
import 'services/storage_service.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  try {
    await dotenv.load(fileName: '.env');
  } catch (_) {}
  try {
    await BackendService.initialize();
  } catch (_) {}

  try {
    await AvatarCache.initialize();
  } catch (_) {}
  try {
    await NetworkStatusService.initialize();
  } catch (_) {}

  runApp(
    AdminDesktopBootstrap(
      supported: !kIsWeb &&
          (defaultTargetPlatform == TargetPlatform.windows ||
              defaultTargetPlatform == TargetPlatform.macOS ||
              defaultTargetPlatform == TargetPlatform.linux),
    ),
  );
}

