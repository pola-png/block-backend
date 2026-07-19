import 'package:flutter/material.dart';

class AboutXapZapScreen extends StatelessWidget {
  const AboutXapZapScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: const Text('About XapZap'),
        backgroundColor: theme.colorScheme.surface,
        foregroundColor: theme.colorScheme.onSurface,
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _card(
            theme,
            'Built for creators',
            'XapZap is a creator-first social app for posts, videos, reels, news, comments, and community conversations.',
          ),
          const SizedBox(height: 16),
          _card(
            theme,
            'What you can do',
            'Share posts, follow creators, save content, chat, report abuse, and grow your audience.',
          ),
          const SizedBox(height: 16),
          _card(
            theme,
            'Contact',
            'For support and policy questions, use Help & Support or contact xapzaptech@gmail.com.',
          ),
        ],
      ),
    );
  }

  Widget _card(ThemeData theme, String title, String body) {
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
          Text(title, style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800)),
          const SizedBox(height: 8),
          Text(body, style: theme.textTheme.bodyMedium),
        ],
      ),
    );
  }
}
