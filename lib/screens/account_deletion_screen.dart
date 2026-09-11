import 'package:flutter/material.dart';

import '../services/backend_service.dart';
import '../services/avatar_cache.dart';
import '../services/auth_wrapper.dart';
import 'legal_page_widgets.dart';

class AccountDeletionScreen extends StatefulWidget {
  const AccountDeletionScreen({super.key});

  @override
  State<AccountDeletionScreen> createState() => _AccountDeletionScreenState();
}

class _AccountDeletionScreenState extends State<AccountDeletionScreen> {
  bool _confirmed = false;
  bool _isDeleting = false;
  bool _showDeleteAction = false;

  @override
  void initState() {
    super.initState();
    _loadAuthState();
  }

  Future<void> _loadAuthState() async {
    final user = await BackendService.getCurrentUser();
    if (!mounted) return;
    setState(() => _showDeleteAction = user != null);
  }

  Future<void> _deleteAccount() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('Delete account'),
          content: const Text(
            'This permanently deletes your account, profile, posts, comments, likes, saves, follows, blocks, reports, and active sessions. This action cannot be undone.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: Colors.red,
                foregroundColor: Colors.white,
              ),
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: const Text('Delete'),
            ),
          ],
        );
      },
    );

    if (confirm != true || !mounted) {
      return;
    }

    setState(() => _isDeleting = true);

    try {
      await BackendService.deleteCurrentAccount();
      await AvatarCache.clearAll();
      if (!mounted) return;
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => const AuthWrapper()),
        (route) => false,
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Account deletion failed. Please try again.'),
        ),
      );
      setState(() => _isDeleting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return LegalPageScaffold(
      title: 'Account Deletion',
      headline: 'XapZap Account Deletion',
      intro:
          'This page describes the XapZap account deletion process for both the website and app, including what is deleted immediately and what limited records may still be retained.',
      currentRoute: '/account-deletion',
      sections: const [
        LegalSectionData(
          title: 'Purpose of this page',
          body:
              'This page explains how XapZap account deletion works across the website and app. It is intended for users who need a clear public description of the deletion process and data removal behavior.',
        ),
        LegalSectionData(
          title: 'How deletion works',
          body:
              'A signed-in user can permanently delete their account through the supported deletion flow. XapZap uses the same backend deletion function for account deletion so the web and app can follow the same server-side deletion path. Once confirmed, the service attempts to delete the profile, posts, comments, likes, follows, saves, blocks, reports, related account records, and active sessions immediately.',
        ),
        LegalSectionData(
          title: 'What may still remain temporarily',
          body:
              'Some limited residual technical, moderation, safety, or legal records may remain where necessary for system propagation, fraud prevention, security review, trust and safety history, dispute handling, or legal compliance.',
        ),
        LegalSectionData(
          title: 'Effect on access and visibility',
          body:
              'After deletion completes, the deleted account should no longer be able to sign in through normal product flows and the deleted profile should no longer be available in the ordinary app experience. Removed posts and comments are expected to become unavailable through supported user-facing views, subject to lawful exceptions and system propagation timing.',
        ),
        LegalSectionData(
          title: 'Irreversibility',
          body:
              'Account deletion is intended to be permanent and should be treated as irreversible. Users should only proceed if they understand they may permanently lose access to their account, public history, and related data.',
        ),
        LegalSectionData(
          title: 'Questions about deletion',
          body:
              'For deletion, privacy, or moderation questions, contact xapzaptech@gmail.com.',
        ),
      ],
      footer: _showDeleteAction
          ? _DeletionActionCard(
              confirmed: _confirmed,
              isDeleting: _isDeleting,
              onChanged: (value) => setState(() => _confirmed = value ?? false),
              onDelete: _deleteAccount,
            )
          : null,
    );
  }
}

class _DeletionActionCard extends StatelessWidget {
  final bool confirmed;
  final bool isDeleting;
  final ValueChanged<bool?> onChanged;
  final VoidCallback onDelete;

  const _DeletionActionCard({
    required this.confirmed,
    required this.isDeleting,
    required this.onChanged,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: theme.colorScheme.errorContainer.withValues(alpha: 0.35),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: theme.colorScheme.error.withValues(alpha: 0.22),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Delete this account now',
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'This action requires a signed-in account and cannot be undone.',
            style: theme.textTheme.bodyMedium?.copyWith(height: 1.45),
          ),
          const SizedBox(height: 12),
          CheckboxListTile(
            value: confirmed,
            contentPadding: EdgeInsets.zero,
            controlAffinity: ListTileControlAffinity.leading,
            onChanged: isDeleting ? null : onChanged,
            title: const Text('I understand this action is permanent'),
          ),
          const SizedBox(height: 8),
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: Colors.red,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 14),
              ),
              onPressed: (!confirmed || isDeleting) ? null : onDelete,
              child: isDeleting
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                      ),
                    )
                  : const Text('Delete My Account'),
            ),
          ),
        ],
      ),
    );
  }
}
