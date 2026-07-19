import 'package:flutter/material.dart';

import '../models/app_notification.dart';
import '../screens/notification_landing_screen.dart';

final GlobalKey<NavigatorState> appNavigatorKey = GlobalKey<NavigatorState>();

Future<void> openNotificationLandingFromPayload(
  Map<String, dynamic> payload,
) async {
  final navigator = appNavigatorKey.currentState;
  if (navigator == null) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      appNavigatorKey.currentState?.push(
        MaterialPageRoute(
          builder: (_) => NotificationLandingScreen(
            payload: Map<String, dynamic>.from(payload),
          ),
        ),
      );
    });
    return;
  }

  await navigator.push(
    MaterialPageRoute(
      builder: (_) => NotificationLandingScreen(
        payload: Map<String, dynamic>.from(payload),
      ),
    ),
  );
}

Future<void> openNotificationLandingFromNotification(
  AppNotification notification,
) async {
  await openNotificationLandingFromPayload(<String, dynamic>{
    'notificationId': notification.id,
    'type': notification.type ?? 'post',
    'actionUrl': notification.actionUrl ?? '',
    'postId': notification.postId ?? '',
    'title': notification.title,
    'body': notification.body,
  });
}
