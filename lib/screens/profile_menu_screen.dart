import 'package:flutter/material.dart';

import '../services/appwrite_service.dart';
import '../services/app_review_service.dart';
import 'about_xapzap_screen.dart';
import 'account_deletion_screen.dart';
import 'dashboard_screen.dart';
import 'drafts_screen.dart';
import 'edit_profile_screen.dart';
import 'help_support_screen.dart';
import 'monetization_screen.dart';
import 'premium_screen.dart';
import 'privacy_policy_screen.dart';
import 'referrals_screen.dart';
import 'saved_posts_screen.dart';
import 'safety_standards_screen.dart';
import 'settings_screen.dart';
import 'terms_of_service_screen.dart';
import '../widgets/tv_focusable_action.dart';

class ProfileMenuScreen extends StatelessWidget {
  const ProfileMenuScreen({super.key});

  Future<void> _signOut(BuildContext context) async {
    try {
      await AppwriteService.signOut();
      if (!context.mounted) return;
      Navigator.of(context).pushNamedAndRemoveUntil('/signin', (route) => false);
    } catch (_) {
      if (!context.mounted) return;
      Navigator.of(context).pushNamedAndRemoveUntil('/signin', (route) => false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Menu'),
        centerTitle: true,
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _MenuTile(
            icon: Icons.edit_outlined,
            title: 'Edit Profile',
            onTap: () {
              Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const EditProfileScreen()),
              );
            },
          ),
          const SizedBox(height: 8),
          _MenuTile(
            icon: Icons.bookmark_border,
            title: 'Saved Posts',
            onTap: () {
              Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const SavedPostsScreen()),
              );
            },
          ),
          const SizedBox(height: 8),
          _MenuTile(
            icon: Icons.file_copy_outlined,
            title: 'Drafts',
            onTap: () {
              Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const DraftsScreen()),
              );
            },
          ),
          const SizedBox(height: 8),
          _MenuTile(
            icon: Icons.bar_chart_outlined,
            title: 'Analytics',
            onTap: () {
              Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const DashboardScreen()),
              );
            },
          ),
          const SizedBox(height: 8),
          _MenuTile(
            icon: Icons.monetization_on_outlined,
            title: 'Monetization',
            onTap: () {
              Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const MonetizationScreen()),
              );
            },
          ),
          const SizedBox(height: 8),
          _MenuTile(
            icon: Icons.card_giftcard_outlined,
            title: 'Referrals',
            onTap: () {
              Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const ReferralsScreen()),
              );
            },
          ),
          const SizedBox(height: 8),
          _MenuTile(
            icon: Icons.star_outline,
            title: 'Rate App',
            onTap: () async {
              await AppReviewService.requestReview();
            },
          ),
          const SizedBox(height: 8),
          _MenuTile(
            icon: Icons.workspace_premium_outlined,
            title: 'Premium',
            onTap: () {
              Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const PremiumScreen()),
              );
            },
          ),
          const SizedBox(height: 8),
          _MenuTile(
            icon: Icons.settings_outlined,
            title: 'Settings & Privacy',
            onTap: () {
              Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const SettingsScreen()),
              );
            },
          ),
          const SizedBox(height: 8),
          _MenuTile(
            icon: Icons.support_agent_outlined,
            title: 'Help & Support',
            onTap: () {
              Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const HelpSupportScreen()),
              );
            },
          ),
          const SizedBox(height: 8),
          _MenuTile(
            icon: Icons.info_outline,
            title: 'About XapZap',
            onTap: () {
              Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const AboutXapZapScreen()),
              );
            },
          ),
          const SizedBox(height: 8),
          _MenuTile(
            icon: Icons.privacy_tip_outlined,
            title: 'Privacy Policy',
            onTap: () {
              Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const PrivacyPolicyScreen()),
              );
            },
          ),
          const SizedBox(height: 8),
          _MenuTile(
            icon: Icons.description_outlined,
            title: 'Terms of Service',
            onTap: () {
              Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const TermsOfServiceScreen()),
              );
            },
          ),
          const SizedBox(height: 8),
          _MenuTile(
            icon: Icons.shield_outlined,
            title: 'Safety Standards',
            onTap: () {
              Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const SafetyStandardsScreen()),
              );
            },
          ),
          const SizedBox(height: 8),
          _MenuTile(
            icon: Icons.delete_outline,
            title: 'Account Deletion',
            onTap: () {
              Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const AccountDeletionScreen()),
              );
            },
          ),
          const SizedBox(height: 16),
          FilledButton.tonal(
            onPressed: () => _signOut(context),
            style: FilledButton.styleFrom(
              backgroundColor: theme.colorScheme.errorContainer,
              foregroundColor: theme.colorScheme.onErrorContainer,
            ),
            child: const Text('Sign Out'),
          ),
        ],
      ),
    );
  }
}

class _MenuTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final VoidCallback onTap;

  const _MenuTile({
    required this.icon,
    required this.title,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return TvFocusableAction(
      borderRadius: BorderRadius.circular(16),
      onPressed: onTap,
      child: Material(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(16),
        child: ListTile(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          leading: Icon(icon),
          title: Text(title),
          trailing: const Icon(Icons.chevron_right),
          onTap: onTap,
        ),
      ),
    );
  }
}
