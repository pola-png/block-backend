import 'package:flutter/material.dart';

class LegalPageScaffold extends StatelessWidget {
  final String title;
  final String headline;
  final String intro;
  final List<LegalSectionData> sections;
  final String currentRoute;
  final bool showConsentActions;
  final VoidCallback? onAccept;
  final VoidCallback? onDecline;
  final Widget? footer;

  const LegalPageScaffold({
    super.key,
    required this.title,
    required this.headline,
    required this.intro,
    required this.sections,
    required this.currentRoute,
    this.showConsentActions = false,
    this.onAccept,
    this.onDecline,
    this.footer,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: Text(title),
        centerTitle: true,
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            Expanded(
              child: ListView(
                children: [
                  Text(
                    headline,
                    style: theme.textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    intro,
                    style: theme.textTheme.bodyMedium?.copyWith(height: 1.55),
                  ),
                  const SizedBox(height: 20),
                  for (final section in sections)
                    LegalTextSection(
                      title: section.title,
                      body: section.body,
                    ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      OutlinedButton(
                        onPressed: currentRoute == '/privacy'
                            ? null
                            : () => Navigator.of(context).pushNamed('/privacy'),
                        child: const Text('Privacy Policy'),
                      ),
                      OutlinedButton(
                        onPressed: currentRoute == '/terms'
                            ? null
                            : () => Navigator.of(context).pushNamed('/terms'),
                        child: const Text('Terms of Service'),
                      ),
                      OutlinedButton(
                        onPressed: currentRoute == '/account-deletion'
                            ? null
                            : () => Navigator.of(context)
                                .pushNamed('/account-deletion'),
                        child: const Text('Account Deletion'),
                      ),
                      OutlinedButton(
                        onPressed: currentRoute == '/safety-standards'
                            ? null
                            : () => Navigator.of(context)
                                .pushNamed('/safety-standards'),
                        child: const Text('Safety Standards'),
                      ),
                    ],
                  ),
                  if (footer != null) ...[
                    const SizedBox(height: 20),
                    footer!,
                  ],
                ],
              ),
            ),
            if (showConsentActions) ...[
              const SizedBox(height: 16),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  ElevatedButton(
                    onPressed: onDecline,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.red,
                    ),
                    child: const Text('Decline'),
                  ),
                  ElevatedButton(
                    onPressed: onAccept,
                    child: const Text('Accept'),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class LegalSectionData {
  final String title;
  final String body;

  const LegalSectionData({
    required this.title,
    required this.body,
  });
}

class LegalTextSection extends StatelessWidget {
  final String title;
  final String body;

  const LegalTextSection({
    super.key,
    required this.title,
    required this.body,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            body,
            style: theme.textTheme.bodyMedium?.copyWith(height: 1.5),
          ),
        ],
      ),
    );
  }
}
