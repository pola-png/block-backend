import 'package:flutter/material.dart';
import 'package:firebase_messaging/firebase_messaging.dart';

import '../../services/firebase_service.dart';
import '../../services/push_notification_service.dart';

class NotificationsSettingsScreen extends StatefulWidget {
  const NotificationsSettingsScreen({super.key});

  @override
  State<NotificationsSettingsScreen> createState() =>
      _NotificationsSettingsScreenState();
}

class _NotificationsSettingsScreenState
    extends State<NotificationsSettingsScreen> {
  bool _loading = true;
  NotificationSettings? _settings;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final settings = await PushNotificationService.getSettings();
    if (!mounted) return;
    setState(() {
      _settings = settings;
      _loading = false;
    });
  }

  Future<void> _enablePush() async {
    setState(() => _loading = true);
    await PushNotificationService.refreshPermissionsAndSync(request: true);
    await _load();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final authStatus = _settings?.authorizationStatus;
    final bool firebaseReady = FirebaseService.isReady;
    final bool isEnabled =
        authStatus == AuthorizationStatus.authorized ||
        authStatus == AuthorizationStatus.provisional;

    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      appBar: AppBar(
        title: const Text('Notifications'),
        centerTitle: true,
        backgroundColor:
            theme.appBarTheme.backgroundColor ?? colorScheme.surface,
        foregroundColor:
            theme.appBarTheme.foregroundColor ?? colorScheme.onSurface,
        elevation: 0,
        scrolledUnderElevation: 0,
      ),
      body: RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            _buildStatusCard(
              context,
              title: 'Android push status',
              subtitle: !firebaseReady
                  ? 'Firebase is not ready on this build.'
                  : isEnabled
                  ? 'Push notifications are enabled on this device.'
                  : 'Push notifications are not enabled yet.',
              trailing: _loading
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : FilledButton(
                      onPressed: _enablePush,
                      child: Text(isEnabled ? 'Refresh' : 'Enable'),
                    ),
            ),
            const SizedBox(height: 12),
            _buildStatusCard(
              context,
              title: 'Permission',
              subtitle: _formatAuthorization(authStatus),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStatusCard(
    BuildContext context, {
    required String title,
    required String subtitle,
    Widget? trailing,
  }) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: theme.colorScheme.outlineVariant),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    color: theme.colorScheme.onSurface,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  subtitle,
                  style: TextStyle(
                    color: theme.colorScheme.onSurfaceVariant,
                    height: 1.4,
                  ),
                ),
              ],
            ),
          ),
          if (trailing != null) ...[
            const SizedBox(width: 12),
            trailing,
          ],
        ],
      ),
    );
  }

  String _formatAuthorization(AuthorizationStatus? status) {
    switch (status) {
      case AuthorizationStatus.authorized:
        return 'Authorized';
      case AuthorizationStatus.provisional:
        return 'Provisionally allowed';
      case AuthorizationStatus.denied:
        return 'Denied';
      case AuthorizationStatus.notDetermined:
        return 'Not requested yet';
      case null:
        return 'Unavailable';
    }
  }
}
