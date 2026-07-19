import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';

import '../services/appwrite_service.dart';
import '../services/storage_service.dart';
import '../services/avatar_cache.dart';

class EditProfileScreen extends StatefulWidget {
  const EditProfileScreen({super.key});

  @override
  State<EditProfileScreen> createState() => _EditProfileScreenState();
}

class _EditProfileScreenState extends State<EditProfileScreen> {
  static const List<String> _countries = <String>[
    'Nigeria',
    'Ghana',
    'Kenya',
    'South Africa',
    'United States',
    'Canada',
    'United Kingdom',
    'Germany',
    'France',
    'Italy',
    'Spain',
    'Netherlands',
    'Belgium',
    'Sweden',
    'Norway',
    'Denmark',
    'Finland',
    'Ireland',
    'Portugal',
    'Switzerland',
    'Austria',
    'Poland',
    'Czech Republic',
    'Romania',
    'Hungary',
    'Greece',
    'Turkey',
    'United Arab Emirates',
    'Saudi Arabia',
    'Qatar',
    'India',
    'Pakistan',
    'Bangladesh',
    'Japan',
    'China',
    'South Korea',
    'Australia',
    'New Zealand',
  ];
  static const List<String> _genders = <String>[
    'Male',
    'Female',
    'Prefer not to say',
  ];

  final _usernameController = TextEditingController();
  final _displayNameController = TextEditingController();
  final _bioController = TextEditingController();
  final _websiteController = TextEditingController();
  final _phoneController = TextEditingController();
  final _dobController = TextEditingController();
  final ImagePicker _picker = ImagePicker();

  XFile? _selectedImage;
  XFile? _selectedCover;
  String? _avatarUrl;
  String? _coverUrl;
  String? _selectedCountry;
  String? _selectedGender;
  bool _hasChanges = false;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadProfile();
  }

  Future<void> _loadProfile() async {
    try {
      final user = await AppwriteService.getCurrentUser();
      if (user == null) {
        setState(() => _loading = false);
        return;
      }
      final prof = await AppwriteService.getProfileByUserId(user.$id);
      final data = prof?.data ?? <String, dynamic>{};

      _usernameController.text = (data['username'] as String?) ?? '';
      _displayNameController.text =
          (data['displayName'] as String?)?.trim().isNotEmpty == true
              ? data['displayName'] as String
              : ((data['username'] as String?) ?? user.name);
      _bioController.text = (data['bio'] as String?) ?? '';
      _websiteController.text = (data['website'] as String?) ?? '';
      _phoneController.text = (data['phone'] as String?) ?? '';
      _dobController.text =
          _formatDobForDisplay(data['dateOfBirth'] as String?);
      _selectedCountry = (data['country'] as String?)?.trim();
      _selectedGender = (data['gender'] as String?)?.trim();
      _avatarUrl =
          await _resolveAvatarUrl(user.$id, data['avatarUrl'] as String?);
      _coverUrl = await _resolveCoverUrl(data['coverUrl'] as String?);
    } catch (_) {
      // Ignore load errors; user can still edit.
    } finally {
      if (mounted) {
        setState(() {
          _hasChanges = false;
          _loading = false;
        });
      }
    }
  }

  Future<String?> _resolveAvatarUrl(String userId, String? raw) async {
    // Prefer the raw path/url if present.
    if (raw != null && raw.isNotEmpty) {
      try {
        final signed = await StorageService.getSignedUrl(raw);
        await AvatarCache.setForUserId(userId, signed);
        return signed;
      } catch (_) {
        return raw;
      }
    }
    // Fallback to cache.
    final cached = AvatarCache.getForUserId(userId);
    if (cached != null) return cached;
    return null;
  }

  Future<String?> _resolveCoverUrl(String? raw) async {
    if (raw == null || raw.isEmpty) return null;
    try {
      final signed = await StorageService.getSignedUrl(raw);
      return signed;
    } catch (_) {
      return raw;
    }
  }

  String _displayValue(String? value) {
    final text = value?.trim() ?? '';
    return text.isEmpty ? 'Not set' : text;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    if (_loading) {
      return Scaffold(
        backgroundColor: theme.scaffoldBackgroundColor,
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      appBar: AppBar(
        backgroundColor: theme.colorScheme.surface,
        elevation: 0,
        surfaceTintColor: Colors.transparent,
        leadingWidth: 80,
        leading: TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(
            'Cancel',
            style: TextStyle(
              fontSize: 16,
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ),
        centerTitle: true,
        title: Text(
          'Edit Profile',
          style: TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.bold,
            color: theme.colorScheme.onSurface,
          ),
        ),
        actions: [
          TextButton(
            onPressed: _hasChanges ? _saveProfile : null,
            child: Text(
              'Done',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: _hasChanges
                    ? const Color(0xFF29ABE2)
                    : theme.colorScheme.onSurface.withOpacity(0.4),
              ),
            ),
          ),
        ],
      ),
      body: _buildForm(theme),
    );
  }

  Widget _buildForm(ThemeData theme) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(0, 0, 0, 24),
      children: [
        const SizedBox(height: 8),
        _buildProfilePicture(theme),
        const SizedBox(height: 12),
        _buildBannerPreview(),
        const SizedBox(height: 16),
        _buildSectionTitle(theme, 'Account'),
        _buildEditableRow(
          theme,
          title: 'Username',
          value: _usernameController.text,
          onEdit: () => _editTextField(
            title: 'Username',
            controller: _usernameController,
            hintText: 'Required',
          ),
        ),
        _buildEditableRow(
          theme,
          title: 'Display Name',
          value: _displayNameController.text,
          onEdit: () => _editTextField(
            title: 'Display Name',
            controller: _displayNameController,
            hintText: 'Enter display name',
          ),
        ),
        _buildEditableRow(
          theme,
          title: 'Bio',
          value: _bioController.text,
          onEdit: () => _editTextField(
            title: 'Bio',
            controller: _bioController,
            hintText: 'Tell people about yourself',
            maxLines: 4,
          ),
        ),
        _buildEditableRow(
          theme,
          title: 'Website',
          value: _websiteController.text,
          onEdit: () => _editTextField(
            title: 'Website',
            controller: _websiteController,
            hintText: 'https://example.com',
            keyboardType: TextInputType.url,
          ),
        ),
        _buildEditableRow(
          theme,
          title: 'Phone',
          value: _phoneController.text,
          onEdit: () => _editTextField(
            title: 'Phone',
            controller: _phoneController,
            hintText: 'Phone number',
            keyboardType: TextInputType.phone,
          ),
        ),
        const SizedBox(height: 16),
        _buildSectionTitle(theme, 'Personal'),
        _buildEditableRow(
          theme,
          title: 'Country',
          value: _selectedCountry ?? '',
          onEdit: () => _showSelectionSheet(
            title: 'Country',
            options: _countries,
            selectedValue: _selectedCountry,
            onSelected: (value) {
              setState(() {
                _selectedCountry = value;
                _hasChanges = true;
              });
            },
          ),
        ),
        _buildEditableRow(
          theme,
          title: 'Gender',
          value: _selectedGender ?? '',
          onEdit: () => _showSelectionSheet(
            title: 'Gender',
            options: _genders,
            selectedValue: _selectedGender,
            onSelected: (value) {
              setState(() {
                _selectedGender = value;
                _hasChanges = true;
              });
            },
          ),
        ),
        _buildEditableRow(
          theme,
          title: 'Date of Birth',
          value: _dobController.text,
          onEdit: _editDateOfBirth,
        ),
        const SizedBox(height: 32),
      ],
    );
  }

  Widget _buildProfilePicture(ThemeData theme) {
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 16),
      leading: Container(
        width: 56,
        height: 56,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: theme.colorScheme.primary,
          image: _selectedImage != null
              ? DecorationImage(
                  image: FileImage(File(_selectedImage!.path)),
                  fit: BoxFit.cover,
                )
              : (_avatarUrl != null
                  ? DecorationImage(
                      image: NetworkImage(_avatarUrl!),
                      fit: BoxFit.cover,
                    )
                  : null),
        ),
        child: _selectedImage == null && _avatarUrl == null
            ? const Icon(Icons.person, color: Colors.white, size: 30)
            : null,
      ),
      title: const Text('Profile Photo'),
      subtitle: Text(
        _selectedImage != null || _avatarUrl != null
            ? 'Tap edit to change it'
            : 'No profile photo yet',
      ),
      trailing: IconButton(
        onPressed: _changePhoto,
        icon: const Icon(Icons.edit_outlined),
      ),
    );
  }

  Widget _buildBannerPreview() {
    final hasBanner = _selectedCover != null ||
        (_coverUrl != null && _coverUrl!.isNotEmpty);

    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 16),
      title: const Text('Banner'),
      subtitle: Text(
        hasBanner ? 'Tap edit to change it' : 'No banner yet',
      ),
      trailing: IconButton(
        onPressed: _changeBanner,
        icon: const Icon(Icons.edit_outlined),
      ),
      onTap: _changeBanner,
    );
  }

  Widget _buildSectionTitle(ThemeData theme, String title) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
      child: Text(
        title,
        style: TextStyle(
          fontSize: 15,
          fontWeight: FontWeight.w700,
          color: theme.colorScheme.onSurfaceVariant,
          letterSpacing: 0.7,
        ),
      ),
    );
  }

  Widget _buildEditableRow(
    ThemeData theme, {
    required String title,
    required String value,
    required VoidCallback onEdit,
  }) {
    final icon = _iconForField(title);
    final accent = _accentForField(title);
    final display = _displayValue(value);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      child: Material(
        color: theme.colorScheme.surface,
        elevation: 0,
        borderRadius: BorderRadius.circular(20),
        child: InkWell(
          borderRadius: BorderRadius.circular(20),
          onTap: onEdit,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(20),
              color: theme.colorScheme.surface,
              gradient: LinearGradient(
                colors: [
                  accent.withOpacity(0.08),
                  theme.colorScheme.surface,
                ],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              boxShadow: [
                BoxShadow(
                  color: theme.colorScheme.shadow.withOpacity(
                    theme.brightness == Brightness.dark ? 0.12 : 0.04,
                  ),
                  blurRadius: 12,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: Row(
              children: [
                Container(
                  width: 46,
                  height: 46,
                  decoration: BoxDecoration(
                    color: accent.withOpacity(0.10),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Icon(icon, color: accent, size: 24),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: TextStyle(
                          color: theme.colorScheme.onSurface,
                          fontWeight: FontWeight.w800,
                          fontSize: 17,
                          height: 1.1,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        display,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: theme.colorScheme.onSurfaceVariant,
                          fontSize: 14,
                          height: 1.25,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 10),
                Icon(
                  Icons.chevron_right_rounded,
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  IconData _iconForField(String title) {
    switch (title) {
      case 'Username':
        return Icons.alternate_email_rounded;
      case 'Display Name':
        return Icons.badge_outlined;
      case 'Bio':
        return Icons.notes_rounded;
      case 'Website':
        return Icons.language_rounded;
      case 'Phone':
        return Icons.phone_iphone_rounded;
      case 'Country':
        return Icons.public_rounded;
      case 'Gender':
        return Icons.wc_rounded;
      case 'Date of Birth':
        return Icons.calendar_month_rounded;
      default:
        return Icons.edit_outlined;
    }
  }

  Color _accentForField(String title) {
    switch (title) {
      case 'Username':
        return const Color(0xFF2563EB);
      case 'Display Name':
        return const Color(0xFF7C3AED);
      case 'Bio':
        return const Color(0xFF0F766E);
      case 'Website':
        return const Color(0xFF0284C7);
      case 'Phone':
        return const Color(0xFF059669);
      case 'Country':
        return const Color(0xFFD97706);
      case 'Gender':
        return const Color(0xFFDB2777);
      case 'Date of Birth':
        return const Color(0xFFDC2626);
      default:
        return const Color(0xFF29ABE2);
    }
  }

  Future<void> _editTextField({
    required String title,
    required TextEditingController controller,
    String? hintText,
    int maxLines = 1,
    TextInputType keyboardType = TextInputType.text,
    List<TextInputFormatter> inputFormatters = const <TextInputFormatter>[],
  }) async {
    final result = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      builder: (ctx) => _EditProfileTextSheet(
        title: title,
        initialText: controller.text,
        hintText: hintText,
        maxLines: maxLines,
        keyboardType: keyboardType,
        inputFormatters: inputFormatters,
        icon: _iconForField(title),
        accent: _accentForField(title),
      ),
    );
    if (!mounted || result == null) return;
    setState(() {
      controller.text = result;
      _hasChanges = true;
    });
  }

  Future<void> _showSelectionSheet({
    required String title,
    required List<String> options,
    required String? selectedValue,
    required ValueChanged<String?> onSelected,
  }) async {
    await showModalBottomSheet<void>(
      context: context,
      useSafeArea: true,
      showDragHandle: true,
      builder: (ctx) {
        return SafeArea(
          child: ListView(
            shrinkWrap: true,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
                child: Text(
                  title,
                  style: Theme.of(ctx).textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                ),
              ),
              ...options.map((option) {
                final isSelected = option == selectedValue;
                return ListTile(
                  leading: Icon(_iconForSelection(title)),
                  title: Text(option),
                  trailing: isSelected
                      ? const Icon(Icons.check, color: Color(0xFF29ABE2))
                      : null,
                  onTap: () {
                    Navigator.of(ctx).pop();
                    onSelected(option);
                  },
                );
              }),
              const SizedBox(height: 12),
            ],
          ),
        );
      },
    );
  }

  Future<void> _editDateOfBirth() async {
    final result = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      builder: (ctx) => _EditProfileDobSheet(
        initialText: _dobController.text,
        accent: _accentForField('Date of Birth'),
      ),
    );
    if (!mounted || result == null) return;
    setState(() {
      _dobController.text = result;
      _hasChanges = true;
    });
  }

  Future<void> _changePhoto() async {
    showModalBottomSheet(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.only(bottom: 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: const Icon(Icons.camera_alt),
                title: const Text('Take Photo'),
                onTap: () async {
                  Navigator.pop(context);
                  final XFile? image =
                      await _picker.pickImage(source: ImageSource.camera);
                  if (image != null) {
                    setState(() {
                      _selectedImage = image;
                      _hasChanges = true;
                    });
                  }
                },
              ),
              ListTile(
                leading: const Icon(Icons.photo_library),
                title: const Text('Choose from Gallery'),
                onTap: () async {
                  Navigator.pop(context);
                  final XFile? image =
                      await _picker.pickImage(source: ImageSource.gallery);
                  if (image != null) {
                    setState(() {
                      _selectedImage = image;
                      _hasChanges = true;
                    });
                  }
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  IconData _iconForSelection(String title) {
    switch (title) {
      case 'Country':
        return Icons.public_rounded;
      case 'Gender':
        return Icons.person_rounded;
      default:
        return Icons.label_rounded;
    }
  }

  Future<void> _changeBanner() async {
    showModalBottomSheet(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.only(bottom: 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: const Icon(Icons.camera_alt),
                title: const Text('Take Photo'),
                onTap: () async {
                  Navigator.pop(context);
                  final XFile? image =
                      await _picker.pickImage(source: ImageSource.camera);
                  if (image != null) {
                    setState(() {
                      _selectedCover = image;
                      _hasChanges = true;
                    });
                  }
                },
              ),
              ListTile(
                leading: const Icon(Icons.photo_library),
                title: const Text('Choose from Gallery'),
                onTap: () async {
                  Navigator.pop(context);
                  final XFile? image =
                      await _picker.pickImage(source: ImageSource.gallery);
                  if (image != null) {
                    setState(() {
                      _selectedCover = image;
                      _hasChanges = true;
                    });
                  }
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _saveProfile() async {
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);
    try {
      final user = await AppwriteService.getCurrentUser();
      if (user == null) return;

      final rawUsername = _usernameController.text.trim();
      if (rawUsername.isEmpty) {
        messenger.showSnackBar(
          const SnackBar(content: Text('Username is required')),
        );
        return;
      }
      // Ensure username uniqueness (except for current user).
      final existingProfile =
          await AppwriteService.getProfileByUsername(rawUsername);
      if (existingProfile != null && existingProfile.$id != user.$id) {
        messenger.showSnackBar(
          const SnackBar(content: Text('Username already taken')),
        );
        return;
      }

      // Normalize and validate website (Appwrite `url` type).
      String website = _websiteController.text.trim();
      if (website.isNotEmpty &&
          !website.startsWith('http://') &&
          !website.startsWith('https://')) {
        website = 'https://$website';
      }
      if (website.isNotEmpty) {
        final uri = Uri.tryParse(website);
        if (uri == null || uri.host.isEmpty) {
          messenger.showSnackBar(
            const SnackBar(content: Text('Website must be a valid URL')),
          );
          return;
        }
      }

      // Normalize date of birth to ISO for datetime column.
      final dobRaw = _dobController.text.trim();
      String? dobIso;
      if (dobRaw.isNotEmpty) {
        final parsed = _parseDob(dobRaw);
        if (parsed == null) {
          messenger.showSnackBar(
            const SnackBar(content: Text('Date of birth must be YYYY-MM-DD')),
          );
          return;
        }
        dobIso = parsed.toIso8601String();
      }

      String? avatarUrl;
      String? coverUrl;
      if (_selectedImage != null) {
        avatarUrl =
            await StorageService.uploadProfileImage(_selectedImage!, user.$id);
      }
      if (_selectedCover != null) {
        coverUrl =
            await StorageService.uploadProfileCover(_selectedCover!, user.$id);
      }

      await AppwriteService.updateUserProfile(user.$id, {
        'username': rawUsername,
        'displayName': _displayNameController.text.trim(),
        'bio': _bioController.text.trim(),
        if (website.isNotEmpty) 'website': website,
        'phone': _phoneController.text.trim(),
        if (dobIso != null) 'dateOfBirth': dobIso,
        if ((_selectedCountry ?? '').trim().isNotEmpty)
          'country': _selectedCountry!.trim(),
        if ((_selectedGender ?? '').trim().isNotEmpty)
          'gender': _selectedGender!.trim(),
        if (avatarUrl != null) 'avatarUrl': avatarUrl,
        if (coverUrl != null) 'coverUrl': coverUrl,
      });

      if (!mounted) return;
      navigator.pop();
      messenger.showSnackBar(
        const SnackBar(
          content: Text('Profile updated successfully!'),
          backgroundColor: Color(0xFF10B981),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      messenger.showSnackBar(
        const SnackBar(
          content: Text('Unable to update your profile right now.'),
          backgroundColor: Color(0xFFEF4444),
        ),
      );
    }
  }

  @override
  void dispose() {
    _usernameController.dispose();
    _displayNameController.dispose();
    _bioController.dispose();
    _websiteController.dispose();
    _phoneController.dispose();
    _dobController.dispose();
    super.dispose();
  }

  String _formatDobForDisplay(String? raw) {
    if (raw == null || raw.trim().isEmpty) return '';
    final parsed = DateTime.tryParse(raw.trim());
    if (parsed == null) {
      return raw.trim().replaceAll('/', '-');
    }
    return _formatDobForDisplayFromDate(parsed);
  }

  String _formatDobForDisplayFromDate(DateTime value) {
    return _formatDobForDisplayFromDateValue(value);
  }

  DateTime? _parseDob(String raw) {
    return _parseDobValue(raw);
  }
}

String _formatDobForDisplayFromDateValue(DateTime value) {
    final local = value.toLocal();
    final month = local.month.toString().padLeft(2, '0');
    final day = local.day.toString().padLeft(2, '0');
    return '${local.year}-$month-$day';
  }

DateTime? _parseDobValue(String raw) {
    final normalized = raw.trim().replaceAll('/', '-');
    if (normalized.isEmpty) return null;
    final parts = normalized
        .split('-')
        .where((part) => part.isNotEmpty)
        .toList(growable: false);
    if (parts.length != 3) return null;

    final year = int.tryParse(parts[0]);
    final month = int.tryParse(parts[1]);
    final day = int.tryParse(parts[2]);
    if (year == null || month == null || day == null) return null;

    final parsed = DateTime(year, month, day);
    if (parsed.year != year || parsed.month != month || parsed.day != day) {
      return null;
    }
    return parsed;
  }

class _EditProfileTextSheet extends StatefulWidget {
  const _EditProfileTextSheet({
    required this.title,
    required this.initialText,
    required this.icon,
    required this.accent,
    required this.maxLines,
    required this.keyboardType,
    required this.inputFormatters,
    this.hintText,
  });

  final String title;
  final String initialText;
  final IconData icon;
  final Color accent;
  final int maxLines;
  final TextInputType keyboardType;
  final List<TextInputFormatter> inputFormatters;
  final String? hintText;

  @override
  State<_EditProfileTextSheet> createState() => _EditProfileTextSheetState();
}

class _EditProfileTextSheetState extends State<_EditProfileTextSheet> {
  late final TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.initialText);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;
    return SafeArea(
      child: Material(
        color: Theme.of(context).colorScheme.surface,
        child: SingleChildScrollView(
          padding: EdgeInsets.fromLTRB(16, 8, 16, 16 + bottomInset),
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxWidth: 640,
              minHeight: MediaQuery.of(context).size.height * 0.35,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                        color: widget.accent.withOpacity(0.14),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Icon(widget.icon, color: widget.accent),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        widget.title,
                        style: Theme.of(context).textTheme.titleLarge?.copyWith(
                              fontWeight: FontWeight.w800,
                              fontSize: 22,
                            ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _controller,
                  keyboardType: widget.keyboardType,
                  inputFormatters: widget.inputFormatters,
                  maxLines: widget.maxLines,
                  minLines: widget.maxLines > 1 ? 4 : 1,
                  textInputAction: widget.maxLines > 1
                      ? TextInputAction.newline
                      : TextInputAction.done,
                  decoration: InputDecoration(
                    labelText: widget.title,
                    hintText: widget.hintText,
                    prefixIcon: Icon(widget.icon),
                    alignLabelWithHint: widget.maxLines > 1,
                    filled: true,
                    fillColor: Theme.of(context).colorScheme.surface,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(18),
                      borderSide: BorderSide(
                        color: Theme.of(context).dividerColor,
                      ),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(18),
                      borderSide: BorderSide(
                        color: Theme.of(context).dividerColor.withOpacity(0.8),
                      ),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(18),
                      borderSide: const BorderSide(
                        color: Color(0xFF29ABE2),
                        width: 1.8,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    onPressed: () {
                      FocusScope.of(context).unfocus();
                      Navigator.of(context).pop(_controller.text);
                    },
                    style: FilledButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                    ),
                    child: const Text(
                      'Save',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _EditProfileDobSheet extends StatefulWidget {
  const _EditProfileDobSheet({
    required this.initialText,
    required this.accent,
  });

  final String initialText;
  final Color accent;

  @override
  State<_EditProfileDobSheet> createState() => _EditProfileDobSheetState();
}

class _EditProfileDobSheetState extends State<_EditProfileDobSheet> {
  late final TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.initialText);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;
    return SafeArea(
      child: Material(
        color: Theme.of(context).colorScheme.surface,
        child: SingleChildScrollView(
          padding: EdgeInsets.fromLTRB(16, 8, 16, 16 + bottomInset),
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxWidth: 640,
              minHeight: MediaQuery.of(context).size.height * 0.35,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                        color: widget.accent.withOpacity(0.14),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Icon(
                        Icons.calendar_month_rounded,
                        color: widget.accent,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Text(
                      'Date of Birth',
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(
                            fontWeight: FontWeight.w800,
                            fontSize: 22,
                          ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _controller,
                  keyboardType: TextInputType.datetime,
                  inputFormatters: <TextInputFormatter>[
                    _DobInputFormatter(),
                  ],
                  textInputAction: TextInputAction.done,
                  decoration: InputDecoration(
                    labelText: 'Date of Birth',
                    hintText: 'YYYY-MM-DD',
                    prefixIcon: const Icon(Icons.cake_rounded),
                    filled: true,
                    fillColor: Theme.of(context).colorScheme.surface,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(18),
                      borderSide: BorderSide(
                        color: Theme.of(context).dividerColor,
                      ),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(18),
                      borderSide: BorderSide(
                        color: Theme.of(context).dividerColor.withOpacity(0.8),
                      ),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(18),
                      borderSide: const BorderSide(
                        color: Color(0xFF29ABE2),
                        width: 1.8,
                      ),
                    ),
                    suffixIcon: IconButton(
                      tooltip: 'Pick date',
                      onPressed: () async {
                        final now = DateTime.now();
                        final initialDate =
                            _parseDobValue(_controller.text.trim()) ??
                                DateTime(now.year - 18, now.month, now.day);
                        final picked = await showDatePicker(
                          context: context,
                          initialDate: initialDate,
                          firstDate: DateTime(1900),
                          lastDate: now,
                        );
                        if (picked == null) return;
                        _controller.text =
                            _formatDobForDisplayFromDateValue(picked);
                      },
                      icon: const Icon(Icons.calendar_month_outlined),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    onPressed: () {
                      final parsed = _parseDobValue(_controller.text.trim());
                      if (parsed == null) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text(
                              'Date of birth must be YYYY-MM-DD',
                            ),
                          ),
                        );
                        return;
                      }
                      FocusScope.of(context).unfocus();
                      Navigator.of(context)
                          .pop(_formatDobForDisplayFromDateValue(parsed));
                    },
                    style: FilledButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                    ),
                    child: const Text(
                      'Save',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _DobInputFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    final digits = newValue.text.replaceAll(RegExp(r'[^0-9]'), '');
    final buffer = StringBuffer();
    for (var i = 0; i < digits.length && i < 8; i++) {
      buffer.write(digits[i]);
      if (i == 3 || i == 5) {
        if (i != digits.length - 1) {
          buffer.write('-');
        }
      }
    }

    final formatted = buffer.toString();
    return TextEditingValue(
      text: formatted,
      selection: TextSelection.collapsed(offset: formatted.length),
    );
  }
}

