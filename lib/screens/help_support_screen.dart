import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../services/backend_service.dart';

class HelpSupportScreen extends StatefulWidget {
  const HelpSupportScreen({super.key});

  @override
  State<HelpSupportScreen> createState() => _HelpSupportScreenState();
}

class _HelpSupportScreenState extends State<HelpSupportScreen> {
  final TextEditingController _subjectController = TextEditingController();
  final TextEditingController _messageController = TextEditingController();
  String _category = 'general';
  bool _submitting = false;

  @override
  void dispose() {
    _subjectController.dispose();
    _messageController.dispose();
    super.dispose();
  }

  Future<void> _launchEmail() async {
    final uri = Uri.parse('mailto:xapzaptech@gmail.com?subject=XapZap Support');
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  Future<void> _submitSupportRequest() async {
    final subject = _subjectController.text.trim();
    final message = _messageController.text.trim();
    if (subject.isEmpty || message.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Enter both a subject and your support message.'),
        ),
      );
      return;
    }

    setState(() => _submitting = true);
    try {
      await BackendService.createSupportRequest(
        subject: subject,
        message: message,
        category: _category,
      );
      if (!mounted) return;
      _subjectController.clear();
      _messageController.clear();
      setState(() => _submitting = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Support request sent. The admin team can now review it.'),
        ),
      );
    } catch (_) {
      if (!mounted) return;
      setState(() => _submitting = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Failed to send support request. Please try again.'),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Help & Support'),
        backgroundColor: theme.colorScheme.surface,
        foregroundColor: theme.colorScheme.onSurface,
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _card(
            theme,
            'Send request',
            'Account issues, moderation questions, bugs, payment issues, and creator support requests will go directly into the admin desktop console.',
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                DropdownButtonFormField<String>(
                  initialValue: _category,
                  decoration: const InputDecoration(
                    labelText: 'Category',
                    border: OutlineInputBorder(),
                  ),
                  items: const [
                    DropdownMenuItem(
                      value: 'general',
                      child: Text('General support'),
                    ),
                    DropdownMenuItem(
                      value: 'account',
                      child: Text('Account issue'),
                    ),
                    DropdownMenuItem(
                      value: 'bug',
                      child: Text('Bug report'),
                    ),
                    DropdownMenuItem(
                      value: 'moderation',
                      child: Text('Moderation question'),
                    ),
                    DropdownMenuItem(
                      value: 'payment',
                      child: Text('Payment or earnings'),
                    ),
                  ],
                  onChanged: (value) {
                    if (value == null) return;
                    setState(() => _category = value);
                  },
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _subjectController,
                  decoration: const InputDecoration(
                    labelText: 'Subject',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _messageController,
                  minLines: 5,
                  maxLines: 8,
                  decoration: const InputDecoration(
                    labelText: 'Describe the issue',
                    alignLabelWithHint: true,
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    onPressed: _submitting ? null : _submitSupportRequest,
                    child: Text(_submitting ? 'Sending...' : 'Send support request'),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          _card(
            theme,
            'Direct contact',
            'If you also want to email the team directly, you can still use support email.',
            FilledButton.tonal(
              onPressed: _launchEmail,
              child: const Text('Email support'),
            ),
          ),
          const SizedBox(height: 16),
          _card(
            theme,
            'Quick links',
            'Read the rules and policies that govern the app.',
            Column(
              children: [
                _linkButton(context, 'Privacy Policy', '/privacy'),
                _linkButton(context, 'Terms of Service', '/terms'),
                _linkButton(context, 'Safety Standards', '/safety-standards'),
                _linkButton(context, 'Account Deletion', '/account-deletion'),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _linkButton(BuildContext context, String label, String route) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: SizedBox(
        width: double.infinity,
        child: OutlinedButton(
          onPressed: () => Navigator.of(context).pushNamed(route),
          child: Text(label),
        ),
      ),
    );
  }

  Widget _card(ThemeData theme, String title, String body, Widget child) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: theme.dividerColor),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            body,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 12),
          child,
        ],
      ),
    );
  }
}
