import 'package:flutter/material.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:provider/provider.dart';
import '../../providers/theme_provider.dart';
import '../../widgets/tv_focusable_action.dart';

class AppearanceSettingsScreen extends StatefulWidget {
  const AppearanceSettingsScreen({super.key});

  @override
  State<AppearanceSettingsScreen> createState() => _AppearanceSettingsScreenState();
}

class _AppearanceSettingsScreenState extends State<AppearanceSettingsScreen> {
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      appBar: AppBar(
        title: const Text('Appearance'),
        centerTitle: true,
        backgroundColor: theme.appBarTheme.backgroundColor ?? theme.colorScheme.surface,
        foregroundColor: theme.appBarTheme.foregroundColor ?? theme.colorScheme.onSurface,
        elevation: 0,
        scrolledUnderElevation: 0,
      ),
      body: _buildThemeOptions(),
    );
  }

  Widget _buildThemeOptions() {
    final themeProvider = Provider.of<ThemeProvider>(context);
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        const Text(
          'Theme',
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 16),
        _buildThemeOption(
          themeProvider,
          ThemeMode.light,
          'Light',
          'Clean and bright interface',
          LucideIcons.sun,
        ),
        const SizedBox(height: 12),
        _buildThemeOption(
          themeProvider,
          ThemeMode.dark,
          'Dark',
          'Easy on the eyes in low light',
          LucideIcons.moon,
        ),
        const SizedBox(height: 12),
        _buildThemeOption(
          themeProvider,
          ThemeMode.system,
          'System',
          'Match system setting',
          LucideIcons.smartphone,
        ),
      ],
    );
  }

  Widget _buildThemeOption(ThemeProvider themeProvider, ThemeMode mode, String title, String description, IconData icon) {
    final isSelected = themeProvider.themeMode == mode;
    final theme = Theme.of(context);

    return TvFocusableAction(
      onPressed: () => themeProvider.setThemeMode(mode),
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          border: Border.all(
            color: isSelected ? theme.colorScheme.primary : theme.dividerColor,
            width: isSelected ? 2 : 1,
          ),
          borderRadius: BorderRadius.circular(12),
          color: isSelected ? theme.colorScheme.primary.withOpacity(0.08) : theme.cardColor,
        ),
        child: Row(
          children: [
            Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                color: isSelected ? theme.colorScheme.primary : theme.dividerColor,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(
                icon,
                color: isSelected ? Colors.white : theme.iconTheme.color,
                size: 24,
              ),
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
                      fontWeight: FontWeight.w600,
                      color: isSelected ? theme.colorScheme.primary : theme.textTheme.bodyLarge?.color,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    description,
                    style: TextStyle(
                      fontSize: 14,
                      color: theme.textTheme.bodySmall?.color,
                    ),
                  ),
                ],
              ),
            ),
            if (isSelected)
              const Icon(
                LucideIcons.checkCircle,
                color: Color(0xFF29ABE2),
                size: 24,
              ),
          ],
        ),
      ),
    );
  }
}
