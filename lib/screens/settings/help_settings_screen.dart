import 'package:flutter/material.dart';

class HelpSettingsScreen extends StatelessWidget {
  const HelpSettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      appBar: AppBar(
        title: const Text('Help & Support'),
        centerTitle: true,
        backgroundColor: theme.appBarTheme.backgroundColor ?? theme.colorScheme.surface,
        foregroundColor: theme.appBarTheme.foregroundColor ?? theme.colorScheme.onSurface,
        elevation: 0,
        scrolledUnderElevation: 0,
      ),
      body: Center(
        child: Text(
          'Help & Support Screen',
          style: TextStyle(color: theme.colorScheme.onSurface),
        ),
      ),
    );
  }
}
