import 'package:flutter/foundation.dart';
import 'package:in_app_update/in_app_update.dart';

class PlayStoreUpdateService {
  static Future<bool> tryImmediatePlayCoreUpdate() async {
    if (kDebugMode || kIsWeb || defaultTargetPlatform != TargetPlatform.android) {
      return false;
    }

    try {
      final info = await InAppUpdate.checkForUpdate();
      final hasUpdate =
          info.updateAvailability == UpdateAvailability.updateAvailable ||
          info.updateAvailability ==
              UpdateAvailability.developerTriggeredUpdateInProgress;
      if (!hasUpdate) {
        return false;
      }
      if (info.immediateUpdateAllowed) {
        final result = await InAppUpdate.performImmediateUpdate();
        return result == AppUpdateResult.success;
      }
      if (info.flexibleUpdateAllowed) {
        final startResult = await InAppUpdate.startFlexibleUpdate();
        if (startResult == AppUpdateResult.success) {
          await InAppUpdate.completeFlexibleUpdate();
          return true;
        }
      }
    } catch (_) {
      return false;
    }

    return false;
  }
}
