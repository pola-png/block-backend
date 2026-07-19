import 'package:flutter/material.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'blocked_accounts_screen.dart';
import 'change_password_screen.dart';
import '../../widgets/tv_focusable_action.dart';

class PrivacySettingsScreen extends StatefulWidget {
  const PrivacySettingsScreen({super.key});

  @override
  State<PrivacySettingsScreen> createState() => _PrivacySettingsScreenState();
}

class _PrivacySettingsScreenState extends State<PrivacySettingsScreen> {
  bool _privateAccount = false;
  bool _showActivityStatus = true;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      appBar: AppBar(
        title: const Text('Privacy & Security'),
        centerTitle: true,
        backgroundColor: theme.appBarTheme.backgroundColor ?? theme.colorScheme.surface,
        foregroundColor: theme.appBarTheme.foregroundColor ?? theme.colorScheme.onSurface,
        elevation: 0,
        scrolledUnderElevation: 0,
      ),
      body: _buildSettings(context),
    );
  }

  Widget _buildSettings(BuildContext context) {
    return ListView(
      children: [
        _buildSwitchOption(
          context,
          'Private Account',
          'Only approved followers can see your posts',
          _privateAccount,
          (value) => setState(() => _privateAccount = value),
        ),
        _buildSwitchOption(
          context,
          'Show Activity Status',
          'Let others see when you\'re online',
          _showActivityStatus,
          (value) => setState(() => _showActivityStatus = value),
        ),
        _buildNavigationOption(
          context,
          'Blocked Accounts',
          'Manage users you\'ve blocked',
          LucideIcons.ban,
          () {
            Navigator.push(context, MaterialPageRoute(builder: (context) => const BlockedAccountsScreen()));
          },
        ),
        _buildNavigationOption(
          context,
          'Change Password',
          'Update your account password',
          LucideIcons.lock,
          () {
            Navigator.push(context, MaterialPageRoute(builder: (context) => const ChangePasswordScreen()));
          },
        ),
      ],
    );
  }

  Widget _buildSwitchOption(
    BuildContext context,
    String title,
    String description,
    bool value,
    Function(bool) onChanged,
  ) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: theme.dividerColor.withOpacity(0.6), width: 1)),
      ),
      child: Row(
        children: [
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
          Switch(
            value: value,
            onChanged: onChanged,
            activeColor: theme.colorScheme.primary,
          ),
        ],
      ),
    );
  }

  Widget _buildNavigationOption(
    BuildContext context,
    String title,
    String description,
    IconData icon,
    VoidCallback onTap,
  ) {
    final theme = Theme.of(context);
    return TvFocusableAction(
      onPressed: onTap,
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          border: Border(bottom: BorderSide(color: theme.dividerColor.withOpacity(0.6), width: 1)),
        ),
        child: Row(
          children: [
            Icon(
              icon,
              size: 24,
              color: theme.colorScheme.onSurfaceVariant,
            ),
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
            const Icon(
              LucideIcons.chevronRight,
              size: 20,
              color: Color(0xFF9CA3AF),
            ),
          ],
        ),
      ),
    );
  }
}
