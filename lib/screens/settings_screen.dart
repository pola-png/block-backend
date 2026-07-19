import 'package:flutter/material.dart';
import 'package:lucide_icons/lucide_icons.dart';

import 'settings/account_settings_screen.dart';
import 'settings/privacy_settings_screen.dart';
import 'settings/appearance_settings_screen.dart';
import 'settings/notifications_settings_screen.dart';
import 'settings/help_settings_screen.dart';
import '../services/appwrite_service.dart';
import '../widgets/tv_focusable_action.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      appBar: AppBar(
        title: const Text('Settings'),
        centerTitle: true,
        backgroundColor: theme.appBarTheme.backgroundColor ?? theme.colorScheme.surface,
        foregroundColor: theme.appBarTheme.foregroundColor ?? theme.colorScheme.onSurface,
        elevation: 0,
        scrolledUnderElevation: 0,
      ),
      body: ListView(
        padding: const EdgeInsets.symmetric(vertical: 8),
        children: [
          _buildMenuItem(
            context,
            icon: LucideIcons.user,
            title: 'Account Information',
            description: 'Manage your name, email, and personal details',
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (context) => const AccountSettingsScreen()),
              );
            },
          ),
          _buildMenuItem(
            context,
            icon: LucideIcons.shield,
            title: 'Privacy & Security',
            description: 'Control who can see your activity and posts',
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (context) => const PrivacySettingsScreen()),
              );
            },
          ),
          _buildMenuItem(
            context,
            icon: LucideIcons.bell,
            title: 'Notifications',
            description: 'Manage your alert preferences and settings',
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (context) => const NotificationsSettingsScreen()),
              );
            },
          ),
          _buildMenuItem(
            context,
            icon: LucideIcons.paintbrush,
            title: 'Appearance',
            description: 'Customize app theme and display options',
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (context) => const AppearanceSettingsScreen()),
              );
            },
          ),
          _buildMenuItem(
            context,
            icon: LucideIcons.helpCircle,
            title: 'Help & Support',
            description: 'Access FAQs, contact support, and get help',
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (context) => const HelpSettingsScreen()),
              );
            },
          ),
          const SizedBox(height: 24),
          _buildLogoutButton(context),
        ],
      ),
    );
  }

  Widget _buildMenuItem(
    BuildContext context, {
    required IconData icon,
    required String title,
    required String description,
    required VoidCallback onTap,
  }) {
    final theme = Theme.of(context);
    return TvFocusableAction(
      onPressed: onTap,
      child: Material(
        color: theme.colorScheme.surface,
        child: InkWell(
          onTap: onTap,
          child: Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              border: Border(
                bottom: BorderSide(color: theme.dividerColor.withOpacity(0.6), width: 1),
              ),
            ),
            child: Row(
              children: [
                Icon(icon, size: 24, color: theme.colorScheme.onSurfaceVariant),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w500,
                          color: theme.colorScheme.onSurface,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        description,
                        style: TextStyle(
                          fontSize: 14,
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
                Icon(
                  LucideIcons.chevronRight,
                  size: 20,
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildLogoutButton(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.all(16),
      child: SizedBox(
        width: double.infinity,
        child: FilledButton.tonal(
          onPressed: () => _showLogoutDialog(context),
          style: FilledButton.styleFrom(
            backgroundColor: theme.colorScheme.errorContainer,
            foregroundColor: theme.colorScheme.onErrorContainer,
          ),
          child: const Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(LucideIcons.logOut, size: 20),
              SizedBox(width: 8),
              Text(
                'Logout',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showLogoutDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (BuildContext dialogContext) {
        final theme = Theme.of(dialogContext);
        return AlertDialog(
          backgroundColor: theme.colorScheme.surface,
          title: Text(
            'Logout',
            style: TextStyle(color: theme.colorScheme.onSurface),
          ),
          content: Text(
            'Are you sure you want to logout?',
            style: TextStyle(color: theme.colorScheme.onSurfaceVariant),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: Text(
                'Cancel',
                style: TextStyle(color: theme.colorScheme.onSurfaceVariant),
              ),
            ),
            TextButton(
              onPressed: () async {
                Navigator.pop(dialogContext);
                await AppwriteService.signOut();
                if (context.mounted) {
                  Navigator.pushNamedAndRemoveUntil(context, '/signin', (route) => false);
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Logged out successfully'),
                    ),
                  );
                }
              },
              child: Text(
                'Logout',
                style: TextStyle(color: theme.colorScheme.error),
              ),
            ),
          ],
        );
      },
    );
  }
}
