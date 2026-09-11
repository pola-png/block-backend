import 'dart:convert';
import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:package_info_plus/package_info_plus.dart';

import 'backend_service.dart';
import 'crypto_service.dart';
import 'firebase_service.dart';
import 'navigation_service.dart';

@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  await FirebaseService.initialize();
}

class PushNotificationService {
  PushNotificationService._();

  static const String _channelId = 'xapzap_notifications';
  static const String _channelName = 'XapZap Notifications';
  static const String _channelDescription =
      'General alerts, messages, and activity updates.';
  static const String _broadcastTopicId = 'all-users';

  static final FlutterLocalNotificationsPlugin _localNotifications =
      FlutterLocalNotificationsPlugin();
  static const AndroidNotificationChannel _channel = AndroidNotificationChannel(
    _channelId,
    _channelName,
    description: _channelDescription,
    importance: Importance.high,
  );

  static bool _initialized = false;
  static bool _localNotificationsInitialized = false;
  static StreamSubscription<String>? _tokenRefreshSub;

  static Future<void> initialize() async {
    if (_initialized) return;
    _initialized = true;

    await _initializeLocalNotifications();
    startEncouragementNotificationService();

    if (kIsWeb || !FirebaseService.isReady) return;

    FirebaseMessaging.onBackgroundMessage(firebaseMessagingBackgroundHandler);
    await _requestPermissionAndSync(request: false);

    FirebaseMessaging.onMessage.listen(_handleForegroundMessage);
    FirebaseMessaging.onMessageOpenedApp.listen(_handleOpenedMessage);
    final initialMessage = await FirebaseMessaging.instance.getInitialMessage();
    if (initialMessage != null) {
      _handleOpenedMessage(initialMessage);
    }
    _tokenRefreshSub?.cancel();
    _tokenRefreshSub = FirebaseMessaging.instance.onTokenRefresh.listen((
      token,
    ) async {
      await _saveTokenToProfile(token: token, enabled: true);
    });

    // Subscribe directly to Firebase topic so push can be sent from Firebase Console
    try {
      await FirebaseMessaging.instance.subscribeToTopic('all-users');
      if (kDebugMode) debugPrint('Subscribed to Firebase topic: all-users');
    } catch (e) {
      if (kDebugMode) debugPrint('Firebase topic subscription failed: $e');
    }
  }

  static Future<void> _requestPermissionAndSync({bool request = false}) async {
    try {
      final user = await BackendService.getCurrentUser();
      if (user == null) return;

      if (!request) {
        if (defaultTargetPlatform == TargetPlatform.android) {
          final current = await Permission.notification.status;
          if (!current.isGranted && !current.isLimited && !current.isProvisional) {
            return;
          }
        }
        final settings = await FirebaseMessaging.instance.getNotificationSettings();
        if (settings.authorizationStatus != AuthorizationStatus.authorized &&
            settings.authorizationStatus != AuthorizationStatus.provisional) {
          return;
        }
      } else {
        final allowed = await _ensureAndroidNotificationPermission();
        if (!allowed) return;
        final settings = await _requestPermissionIfNeeded();
        if (settings.authorizationStatus == AuthorizationStatus.denied) {
          return;
        }
      }

      await _syncTokenToProfile();
    } catch (_) {}
  }

  static Future<void> maybeRequestNotificationPermissionOnLaunch() async {
    if (kIsWeb || !FirebaseService.isReady) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      final currentVersion = await _getAppVersion();
      final lastAskedVersion = prefs.getString('notification_permission_asked_version');
      
      if (lastAskedVersion != currentVersion) {
        await refreshPermissionsAndSync(request: true);
        await prefs.setString('notification_permission_asked_version', currentVersion);
      } else {
        await refreshPermissionsAndSync(request: false);
      }
    } catch (_) {
      await refreshPermissionsAndSync(request: false);
    }
  }

  static Future<String> _getAppVersion() async {
    try {
      final packageInfo = await PackageInfo.fromPlatform();
      return packageInfo.version;
    } catch (_) {
      return '1.0.0';
    }
  }

  static Future<void> refreshPermissionsAndSync({bool request = false}) async {
    if (kIsWeb || !FirebaseService.isReady) return;
    try {
      await _initializeLocalNotifications();

      if (!request) {
        if (defaultTargetPlatform == TargetPlatform.android) {
          final current = await Permission.notification.status;
          if (!current.isGranted && !current.isLimited && !current.isProvisional) {
            return;
          }
        }
        final settings = await FirebaseMessaging.instance.getNotificationSettings();
        if (settings.authorizationStatus != AuthorizationStatus.authorized &&
            settings.authorizationStatus != AuthorizationStatus.provisional) {
          return;
        }
      } else {
        final allowed = await _ensureAndroidNotificationPermission();
        if (!allowed) {
          return;
        }
        final settings = await _requestPermissionIfNeeded();
        if (settings.authorizationStatus == AuthorizationStatus.denied) {
          return;
        }
      }

      await _syncTokenToProfile();
    } catch (_) {
      // Notification setup should never block authentication success.
    }
  }

  static Future<bool> _ensureAndroidNotificationPermission() async {
    if (kIsWeb) return false;
    if (defaultTargetPlatform != TargetPlatform.android) return true;

    try {
      final current = await Permission.notification.status;
      if (current.isGranted || current.isLimited || current.isProvisional) {
        return true;
      }

      final requested = await Permission.notification.request();
      return requested.isGranted ||
          requested.isLimited ||
          requested.isProvisional;
    } catch (_) {
      // If runtime permission probing fails, continue with Firebase's own
      // notification settings flow instead of hard failing setup.
      return true;
    }
  }

  static Future<NotificationSettings?> getSettings() async {
    if (kIsWeb || !FirebaseService.isReady) return null;
    try {
      return await FirebaseMessaging.instance.getNotificationSettings();
    } catch (_) {
      return null;
    }
  }

  static Future<String?> getToken() async {
    if (kIsWeb || !FirebaseService.isReady) return null;
    try {
      return await FirebaseMessaging.instance.getToken();
    } catch (_) {
      return null;
    }
  }

  static Future<void> _initializeLocalNotifications() async {
    if (_localNotificationsInitialized) return;
    _localNotificationsInitialized = true;
    const android = AndroidInitializationSettings('@mipmap/ic_launcher');
    const initSettings = InitializationSettings(android: android);
    await _localNotifications.initialize(
      initSettings,
      onDidReceiveNotificationResponse: (response) {
        final payload = response.payload;
        if (payload == null || payload.isEmpty) return;
        try {
          final decoded = jsonDecode(payload);
          if (decoded is Map<String, dynamic>) {
            unawaited(openNotificationLandingFromPayload(decoded));
          }
        } catch (_) {}
      },
    );

    final androidPlugin =
        _localNotifications.resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>();
    await androidPlugin?.createNotificationChannel(_channel);

    final launchDetails = await _localNotifications.getNotificationAppLaunchDetails();
    if (launchDetails?.didNotificationLaunchApp == true) {
      final payload = launchDetails!.notificationResponse?.payload;
      if (payload != null && payload.isNotEmpty) {
        try {
          final decoded = jsonDecode(payload);
          if (decoded is Map<String, dynamic>) {
            unawaited(openNotificationLandingFromPayload(decoded));
          }
        } catch (_) {}
      }
    }
  }

  static Future<NotificationSettings> _requestPermissionIfNeeded() async {
    final messaging = FirebaseMessaging.instance;
    final current = await messaging.getNotificationSettings();
    // Request on Android 13+ (notDetermined) and also re-request if provisional.
    if (current.authorizationStatus == AuthorizationStatus.notDetermined ||
        current.authorizationStatus == AuthorizationStatus.provisional) {
      return messaging.requestPermission(
        alert: true,
        announcement: false,
        badge: true,
        carPlay: false,
        criticalAlert: false,
        provisional: false,
        sound: true,
      );
    }
    return current;
  }

  static Future<void> _syncTokenToProfile() async {
    try {
      final settings = await getSettings();
      final enabled =
          settings?.authorizationStatus == AuthorizationStatus.authorized ||
              settings?.authorizationStatus == AuthorizationStatus.provisional;
      final token = await getToken();
      await _saveTokenToProfile(token: token, enabled: enabled);
    } catch (_) {
      // Ignore token/profile sync failures here; auth should continue.
    }
  }

  static Future<void> _saveTokenToProfile({
    required String? token,
    required bool enabled,
  }) async {
    final user = await BackendService.getCurrentUser();
    if (user == null) return;

    final payload = <String, dynamic>{
      'pushNotificationsEnabled': enabled,
      'pushPlatform': defaultTargetPlatform.name,
      'pushUpdatedAt': DateTime.now().toUtc().toIso8601String(),
      if (token != null && token.isNotEmpty) 'fcmToken': token,
    };

    try {
      await BackendService.updateUserProfile(user.$id, payload);
    } catch (_) {
      // Keep notification registration non-fatal if the backend schema
      // does not yet contain the push fields.
    }

    if (token == null || token.isEmpty) {
      return;
    }

    try {
      final deviceId = await CryptoService.getDeviceId();
      final registration = await BackendService.registerMessagingPushDevice(
        token: token,
        enabled: enabled,
        deviceId: deviceId,
        targetName: 'mobile-${defaultTargetPlatform.name}',
        topicId: _broadcastTopicId,
      );

      final targetId = registration?['targetId']?.toString().trim();
      if (enabled) {
        await BackendService.subscribeCurrentUserToTopic(
          topicId: _broadcastTopicId,
          targetId: targetId?.isNotEmpty == true ? targetId : null,
          deviceId: deviceId,
        );
      }
    } catch (err, stackTrace) {
      if (kDebugMode) {
        debugPrint('Appwrite Messaging registration failed: $err');
        debugPrintStack(stackTrace: stackTrace);
      }
      // Appwrite Messaging registration is best-effort; local FCM handling
      // should still work even if the bridge endpoint is not ready yet.
    }
  }

  static Future<void> _handleForegroundMessage(RemoteMessage message) async {
    final notification = message.notification;
    if (notification == null) return;

    await _localNotifications.show(
      message.hashCode,
      notification.title ?? 'XapZap',
      notification.body,
      payload: jsonEncode(<String, dynamic>{
        ...message.data,
        'title': notification.title ?? 'XapZap',
        'body': notification.body ?? '',
      }),
      const NotificationDetails(
        android: AndroidNotificationDetails(
          _channelId,
          _channelName,
          channelDescription: _channelDescription,
          importance: Importance.high,
          priority: Priority.high,
          icon: '@mipmap/ic_launcher',
        ),
      ),
    );
  }

  static void _handleOpenedMessage(RemoteMessage message) {
    if (message.data.isEmpty) return;
    unawaited(openNotificationLandingFromPayload(message.data));
    if (kDebugMode) {
      debugPrint('Push notification opened: ${message.messageId}');
    }
  }

  static Timer? _encouragementTimer;

  static void startEncouragementNotificationService() {
    _encouragementTimer?.cancel();
    // Schedule local notifications every 60 seconds to mock real active withdrawals and encourage user action
    _encouragementTimer = Timer.periodic(const Duration(seconds: 60), (timer) async {
      final messages = [
        "User @joh*** just withdrew \$15.50 successfully!",
        "User @mic*** completed 12 video tasks and made \$3.60!",
        "New high-paying website visit tasks are available right now!",
        "User @ann*** claimed a \$1.00 app review reward!",
        "Earn up to \$5.00 today by watching video reviews!",
        "User @dav*** just upgraded to Level 3 and withdrew \$45.00!"
      ];
      final randomIdx = DateTime.now().second % messages.length;
      final msg = messages[randomIdx];

      try {
        await _localNotifications.show(
          timer.hashCode + randomIdx,
          '💰 Earnings Alert!',
          msg,
          payload: jsonEncode(<String, dynamic>{
            'type': 'earnings_alert',
            'message': msg,
          }),
          const NotificationDetails(
            android: AndroidNotificationDetails(
              _channelId,
              _channelName,
              channelDescription: _channelDescription,
              importance: Importance.high,
              priority: Priority.high,
              icon: '@mipmap/ic_launcher',
            ),
          ),
        );
      } catch (e) {
        debugPrint('Failed to trigger local encouragement notification: $e');
      }
    });
  }
}
