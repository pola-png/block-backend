import 'package:flutter/material.dart';
import 'package:xapzap/services/appwrite_service.dart';

class AccountSettingsScreen extends StatefulWidget {
  const AccountSettingsScreen({super.key});

  @override
  State<AccountSettingsScreen> createState() => _AccountSettingsScreenState();
}

class _AccountSettingsScreenState extends State<AccountSettingsScreen> {
  final _formKey = GlobalKey<FormState>();
  final _fullNameController = TextEditingController();
  final _usernameController = TextEditingController();
  final _emailController = TextEditingController();
  final _phoneController = TextEditingController();
  bool _hasChanges = false;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadUserData();
  }

  Future<void> _loadUserData() async {
    try {
      final user = await AppwriteService.getAccount();
      final userRow = await AppwriteService.getRow('users', user.$id);
      _fullNameController.text = (userRow.data['fullName'] ?? '').toString();
      _usernameController.text = (userRow.data['username'] ?? '').toString();
      _emailController.text = user.email;
      _phoneController.text = user.phone;
    } catch (_) {
      // ignore
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      appBar: AppBar(
        title: const Text('Account Information'),
        centerTitle: true,
        backgroundColor:
            theme.appBarTheme.backgroundColor ?? theme.colorScheme.surface,
        foregroundColor:
            theme.appBarTheme.foregroundColor ?? theme.colorScheme.onSurface,
        elevation: 0,
        scrolledUnderElevation: 0,
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : SafeArea(
              child: Column(
                children: [
                  Expanded(child: _buildForm(context)),
                  _buildSaveButton(context),
                ],
              ),
            ),
    );
  }

  Widget _buildForm(BuildContext context) {
    final theme = Theme.of(context);
    return Form(
      key: _formKey,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _buildField(context, 'Full Name', _fullNameController),
          const SizedBox(height: 16),
          _buildUsernameField(context),
          const SizedBox(height: 16),
          _buildField(context, 'Email', _emailController, enabled: false),
          const SizedBox(height: 16),
          _buildField(context, 'Phone Number', _phoneController,
              required: false),
          const SizedBox(height: 8),
          Text(
            'This screen follows your current device theme automatically.',
            style: TextStyle(
                color: theme.colorScheme.onSurfaceVariant, fontSize: 12),
          ),
        ],
      ),
    );
  }

  Widget _buildField(
    BuildContext context,
    String label,
    TextEditingController controller, {
    bool enabled = true,
    bool required = true,
  }) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w500,
            color: theme.colorScheme.onSurface,
          ),
        ),
        const SizedBox(height: 6),
        TextFormField(
          controller: controller,
          enabled: enabled,
          decoration: InputDecoration(
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(color: theme.dividerColor),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(color: theme.dividerColor),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide:
                  BorderSide(color: theme.colorScheme.primary, width: 1.6),
            ),
            disabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide:
                  BorderSide(color: theme.dividerColor.withOpacity(0.6)),
            ),
            fillColor: enabled
                ? theme.colorScheme.surface
                : theme.colorScheme.surfaceContainerHighest,
            filled: true,
          ),
          style: TextStyle(color: theme.colorScheme.onSurface),
          validator: required
              ? (value) {
                  if (value == null || value.isEmpty) {
                    return 'This field is required';
                  }
                  return null;
                }
              : null,
          onChanged: (value) => setState(() => _hasChanges = true),
        ),
      ],
    );
  }

  Widget _buildUsernameField(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Username',
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w500,
            color: theme.colorScheme.onSurface,
          ),
        ),
        const SizedBox(height: 6),
        TextFormField(
          controller: _usernameController,
          decoration: InputDecoration(
            prefixText: '@',
            prefixStyle: TextStyle(color: theme.colorScheme.onSurfaceVariant),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(color: theme.dividerColor),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(color: theme.dividerColor),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide:
                  BorderSide(color: theme.colorScheme.primary, width: 1.6),
            ),
          ),
          style: TextStyle(color: theme.colorScheme.onSurface),
          validator: (value) {
            if (value == null || value.isEmpty) {
              return 'Username is required';
            }
            return null;
          },
          onChanged: (value) => setState(() => _hasChanges = true),
        ),
      ],
    );
  }

  Widget _buildSaveButton(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.all(16),
      child: SizedBox(
        width: double.infinity,
        height: 48,
        child: ElevatedButton(
          onPressed: _hasChanges ? _saveChanges : null,
          style: ElevatedButton.styleFrom(
            backgroundColor: _hasChanges
                ? theme.colorScheme.primary
                : theme.colorScheme.surfaceContainerHighest,
            foregroundColor: _hasChanges
                ? theme.colorScheme.onPrimary
                : theme.colorScheme.onSurfaceVariant,
            elevation: 0,
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          ),
          child: const Text(
            'Save Changes',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
          ),
        ),
      ),
    );
  }

  Future<void> _saveChanges() async {
    if (!_formKey.currentState!.validate()) return;
    try {
      final user = await AppwriteService.getAccount();
      await AppwriteService.updateRow('users', user.$id, {
        'fullName': _fullNameController.text,
        'username': _usernameController.text,
        'phone': _phoneController.text,
      });
      if (!mounted) return;
      setState(() => _hasChanges = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('Account information updated successfully!'),
          backgroundColor: Theme.of(context).colorScheme.primary,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('Failed to update account. Please try again.'),
          backgroundColor: Theme.of(context).colorScheme.error,
        ),
      );
    }
  }

  @override
  void dispose() {
    _fullNameController.dispose();
    _usernameController.dispose();
    _emailController.dispose();
    _phoneController.dispose();
    super.dispose();
  }
}
