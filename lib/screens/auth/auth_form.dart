import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:xapzap/models/database_models.dart' hide Row, Document;
import 'package:url_launcher/url_launcher.dart';

import '../../services/backend_service.dart';
import '../../services/auth_wrapper.dart';
import '../../services/push_notification_service.dart';
import '../../services/network_status_service.dart';
import '../main_screen.dart';
import '../privacy_policy_screen.dart';
import '../terms_of_service_screen.dart';

enum AuthMode { signin, signup }

class AuthForm extends StatefulWidget {
  final AuthMode mode;

  const AuthForm({super.key, required this.mode});

  @override
  State<AuthForm> createState() => _AuthFormState();
}

class _AuthFormState extends State<AuthForm> {
  static const List<String> _countries = <String>[
    'Nigeria',
    'Ghana',
    'Kenya',
    'South Africa',
    'United States',
    'United Kingdom',
    'Canada',
    'India',
    'Germany',
    'France',
    'Italy',
    'Spain',
    'Brazil',
    'Mexico',
    'Argentina',
    'Egypt',
    'Morocco',
    'United Arab Emirates',
    'Saudi Arabia',
    'Qatar',
    'Turkey',
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

  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();
  final _usernameController = TextEditingController();
  final _displayNameController = TextEditingController();
  final _dateOfBirthController = TextEditingController();
  final _referralCodeController = TextEditingController();

  int _signupStep = 0;
  DateTime? _selectedDateOfBirth;
  String? _selectedCountry;
  String? _selectedGender;
  bool _isLoading = false;
  bool _obscurePassword = true;
  bool _obscureConfirmPassword = true;
  bool _acceptedLegal = false;
  bool _redirectCheckQueued = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _queueRedirectCheck();
    });
  }

  void _queueRedirectCheck() {
    if (_redirectCheckQueued) return;
    _redirectCheckQueued = true;
    unawaited(_redirectIfAlreadySignedIn());
  }

  Future<void> _redirectIfAlreadySignedIn() async {
    try {
      final user = await BackendService.getCurrentUser();
      if (!mounted || user == null) return;
      final banned = await BackendService.isUserBanned(user.$id);
      if (!mounted || banned) return;
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => const MainScreen()),
        (route) => false,
      );
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    if (kIsWeb) {
      final theme = Theme.of(context);
      return Scaffold(
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Card(
                elevation: 6,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Text(
                        'Continue in the XapZap app',
                        style: TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.w800,
                        ),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 12),
                      const Text(
                        'Auth is only available in the mobile app. Open XapZap to sign in or sign up.',
                        style: TextStyle(fontSize: 14),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 20),
                      SizedBox(
                        width: double.infinity,
                        height: 44,
                        child: ElevatedButton(
                          onPressed: _openApp,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: theme.colorScheme.primary,
                            foregroundColor: theme.colorScheme.onPrimary,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(10),
                            ),
                          ),
                          child: const Text('Open XapZap'),
                        ),
                      ),
                      const SizedBox(height: 10),
                      SizedBox(
                        width: double.infinity,
                        height: 44,
                        child: OutlinedButton(
                          onPressed: _openStore,
                          style: OutlinedButton.styleFrom(
                            foregroundColor: theme.colorScheme.primary,
                            side: BorderSide(color: theme.colorScheme.primary),
                          ),
                          child: const Text('Install the app'),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      );
    }

    final theme = Theme.of(context);
    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 512),
            child: Card(
              elevation: 4,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Form(
                  key: _formKey,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      _buildHeader(),
                      const SizedBox(height: 24),
                      if (widget.mode == AuthMode.signup) ...[
                        _buildSignupProgress(),
                        const SizedBox(height: 18),
                      ],
                      _buildInputFields(),
                      const SizedBox(height: 10),
                      if (widget.mode == AuthMode.signup &&
                          _signupStep == 3) ...[
                        _buildLegalConsent(),
                        const SizedBox(height: 8),
                      ],
                      _buildPrimaryActions(theme),
                      const SizedBox(height: 18),
                      _buildFooter(),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildHeader() {
    final theme = Theme.of(context);
    return Column(
      children: [
        Text(
          widget.mode == AuthMode.signin
              ? 'Welcome Back!'
              : _signupHeaderTitle(),
          style: TextStyle(
            fontSize: 24,
            fontWeight: FontWeight.bold,
            color: theme.colorScheme.onSurface,
          ),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 8),
        Text(
          widget.mode == AuthMode.signin
              ? 'Enter your credentials to access your account.'
              : _signupHeaderSubtitle(),
          style: TextStyle(
            fontSize: 14,
            color: theme.colorScheme.onSurfaceVariant,
          ),
          textAlign: TextAlign.center,
        ),
      ],
    );
  }

  Widget _buildInputFields() {
    if (widget.mode == AuthMode.signin) {
      return Column(
        children: [
          _buildEmailField(),
          const SizedBox(height: 12),
          _buildPasswordField(),
          Align(
            alignment: Alignment.centerRight,
            child: TextButton(
              onPressed: _isLoading ? null : _showForgotPasswordDialog,
              child: const Text('Forgot password?'),
            ),
          ),
        ],
      );
    }

    switch (_signupStep) {
      case 0:
        return Column(
          children: [
            _buildUsernameField(),
            const SizedBox(height: 12),
            _buildDisplayNameField(),
            const SizedBox(height: 12),
            _buildReferralCodeField(),
          ],
        );
      case 1:
        return Column(
          children: [
            _buildDateOfBirthField(),
            const SizedBox(height: 12),
            _buildCountryField(),
          ],
        );
      case 2:
        return _buildGenderField();
      case 3:
        return Column(
          children: [
            _buildEmailField(),
            const SizedBox(height: 12),
            _buildPasswordField(),
            const SizedBox(height: 12),
            _buildConfirmPasswordField(),
          ],
        );
      default:
        return const SizedBox.shrink();
    }
  }

  Widget _buildSignupProgress() {
    final theme = Theme.of(context);
    return Row(
      children: List<Widget>.generate(4, (index) {
        final isActive = index <= _signupStep;
        return Expanded(
          child: Container(
            height: 4,
            margin: EdgeInsets.only(right: index == 3 ? 0 : 6),
            decoration: BoxDecoration(
              color: isActive
                  ? theme.colorScheme.primary
                  : theme.colorScheme.outlineVariant,
              borderRadius: BorderRadius.circular(999),
            ),
          ),
        );
      }),
    );
  }

  String _signupHeaderTitle() {
    switch (_signupStep) {
      case 0:
        return 'Create your profile';
      case 1:
        return 'Your basic details';
      case 2:
        return 'Choose gender';
      case 3:
        return 'Secure your account';
      default:
        return 'Create an Account';
    }
  }

  String _signupHeaderSubtitle() {
    switch (_signupStep) {
      case 0:
        return 'Choose your username, how your name should appear, and add a referral code if you have one.';
      case 1:
        return 'Add your date of birth and country.';
      case 2:
        return 'Select the gender you want on your profile.';
      case 3:
        return 'Finish with email, password, and legal consent.';
      default:
        return 'Enter your details below to create your account.';
    }
  }

  Widget _buildUsernameField() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Username',
          style: TextStyle(fontSize: 14, fontWeight: FontWeight.w500),
        ),
        const SizedBox(height: 6),
        TextFormField(
          controller: _usernameController,
          decoration: InputDecoration(
            hintText: 'e.g., yourusername',
            prefixIcon: const Icon(
              Icons.alternate_email,
              size: 16,
              color: Color(0xFF9CA3AF),
            ),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
          ),
          validator: (value) {
            if (widget.mode != AuthMode.signup || _signupStep != 0) {
              return null;
            }
            final v = value?.trim() ?? '';
            if (v.isEmpty) return 'Please enter a username';
            final handle = v.startsWith('@') ? v.substring(1) : v;
            if (handle.length < 3) {
              return 'Username must be at least 3 characters';
            }
            if (!RegExp(r'^[a-zA-Z0-9_]+$').hasMatch(handle)) {
              return 'Only letters, numbers, and _ allowed';
            }
            return null;
          },
        ),
      ],
    );
  }

  Widget _buildDisplayNameField() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Full Name',
          style: TextStyle(fontSize: 14, fontWeight: FontWeight.w500),
        ),
        const SizedBox(height: 6),
        TextFormField(
          controller: _displayNameController,
          textCapitalization: TextCapitalization.words,
          decoration: InputDecoration(
            hintText: 'First name and last name',
            prefixIcon: const Icon(
              Icons.badge_outlined,
              size: 16,
              color: Color(0xFF9CA3AF),
            ),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
          ),
          validator: (value) {
            if (widget.mode != AuthMode.signup || _signupStep != 0) {
              return null;
            }
            final v = value?.trim() ?? '';
            if (v.isEmpty) return 'Please enter your full name';
            if (v.length < 2) return 'Display name is too short';
            return null;
          },
        ),
      ],
    );
  }

  Widget _buildReferralCodeField() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Referral code (optional)',
          style: TextStyle(fontSize: 14, fontWeight: FontWeight.w500),
        ),
        const SizedBox(height: 6),
        TextFormField(
          controller: _referralCodeController,
          decoration: InputDecoration(
            hintText: 'Enter a referral username',
            prefixIcon: const Icon(
              Icons.card_giftcard_outlined,
              size: 16,
              color: Color(0xFF9CA3AF),
            ),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
          ),
        ),
      ],
    );
  }

  Widget _buildDateOfBirthField() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Date of Birth',
          style: TextStyle(fontSize: 14, fontWeight: FontWeight.w500),
        ),
        const SizedBox(height: 6),
        TextFormField(
          readOnly: true,
          controller: _dateOfBirthController,
          decoration: InputDecoration(
            hintText: 'Select your date of birth',
            prefixIcon: const Icon(
              Icons.cake_outlined,
              size: 16,
              color: Color(0xFF9CA3AF),
            ),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
          ),
          validator: (_) {
            if (widget.mode != AuthMode.signup || _signupStep != 1) {
              return null;
            }
            if (_selectedDateOfBirth == null) {
              return 'Please select your date of birth';
            }
            return null;
          },
          onTap: _pickDateOfBirth,
        ),
      ],
    );
  }

  Widget _buildCountryField() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Country',
          style: TextStyle(fontSize: 14, fontWeight: FontWeight.w500),
        ),
        const SizedBox(height: 6),
        DropdownButtonFormField<String>(
          value: _selectedCountry,
          decoration: InputDecoration(
            hintText: 'Select your country',
            prefixIcon: const Icon(
              Icons.public,
              size: 16,
              color: Color(0xFF9CA3AF),
            ),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
          ),
          items: _countries
              .map(
                (country) => DropdownMenuItem<String>(
                  value: country,
                  child: Text(country),
                ),
              )
              .toList(),
          onChanged: (value) => setState(() => _selectedCountry = value),
          validator: (value) {
            if (widget.mode != AuthMode.signup || _signupStep != 1) {
              return null;
            }
            if (value == null || value.trim().isEmpty) {
              return 'Please select your country';
            }
            return null;
          },
        ),
      ],
    );
  }

  Widget _buildGenderField() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Gender',
          style: TextStyle(fontSize: 14, fontWeight: FontWeight.w500),
        ),
        const SizedBox(height: 6),
        ..._genders.map((gender) {
          return RadioListTile<String>(
            value: gender,
            groupValue: _selectedGender,
            dense: true,
            contentPadding: EdgeInsets.zero,
            title: Text(gender),
            onChanged: (value) => setState(() => _selectedGender = value),
          );
        }),
        if (widget.mode == AuthMode.signup &&
            _signupStep == 2 &&
            _selectedGender == null)
          const Padding(
            padding: EdgeInsets.only(top: 4),
            child: Text(
              'Please choose your gender',
              style: TextStyle(
                color: Color(0xFFB3261E),
                fontSize: 12,
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildEmailField() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Email',
          style: TextStyle(fontSize: 14, fontWeight: FontWeight.w500),
        ),
        const SizedBox(height: 6),
        TextFormField(
          controller: _emailController,
          keyboardType: TextInputType.emailAddress,
          decoration: InputDecoration(
            hintText: 'name@example.com',
            prefixIcon: const Icon(
              Icons.email_outlined,
              size: 16,
              color: Color(0xFF9CA3AF),
            ),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
          ),
          validator: (value) {
            final shouldValidate = widget.mode == AuthMode.signin ||
                (widget.mode == AuthMode.signup && _signupStep == 3);
            if (!shouldValidate) return null;
            if (value == null ||
                !RegExp(r'^[^@]+@[^@]+\.[^@]+').hasMatch(value.trim())) {
              return 'Please enter a valid email';
            }
            return null;
          },
        ),
      ],
    );
  }

  Widget _buildPasswordField() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Password',
          style: TextStyle(fontSize: 14, fontWeight: FontWeight.w500),
        ),
        const SizedBox(height: 6),
        TextFormField(
          controller: _passwordController,
          obscureText: _obscurePassword,
          decoration: InputDecoration(
            hintText: 'Enter your password',
            prefixIcon: const Icon(
              Icons.lock_outline,
              size: 16,
              color: Color(0xFF9CA3AF),
            ),
            suffixIcon: IconButton(
              icon: Icon(
                _obscurePassword ? Icons.visibility_off : Icons.visibility,
                size: 16,
              ),
              onPressed: () {
                setState(() => _obscurePassword = !_obscurePassword);
              },
            ),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
          ),
          validator: (value) {
            final shouldValidate = widget.mode == AuthMode.signin ||
                (widget.mode == AuthMode.signup && _signupStep == 3);
            if (!shouldValidate) return null;
            if (value == null || value.length < 8) {
              return 'Password must be at least 8 characters';
            }
            return null;
          },
        ),
      ],
    );
  }

  Widget _buildConfirmPasswordField() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Confirm Password',
          style: TextStyle(fontSize: 14, fontWeight: FontWeight.w500),
        ),
        const SizedBox(height: 6),
        TextFormField(
          controller: _confirmPasswordController,
          obscureText: _obscureConfirmPassword,
          decoration: InputDecoration(
            hintText: 'Confirm your password',
            prefixIcon: const Icon(
              Icons.lock_outline,
              size: 16,
              color: Color(0xFF9CA3AF),
            ),
            suffixIcon: IconButton(
              icon: Icon(
                _obscureConfirmPassword
                    ? Icons.visibility_off
                    : Icons.visibility,
                size: 16,
              ),
              onPressed: () {
                setState(
                  () => _obscureConfirmPassword = !_obscureConfirmPassword,
                );
              },
            ),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
          ),
          validator: (value) {
            if (widget.mode != AuthMode.signup || _signupStep != 3) {
              return null;
            }
            if (value != _passwordController.text) {
              return 'Passwords do not match';
            }
            return null;
          },
        ),
      ],
    );
  }

  Widget _buildPrimaryActions(ThemeData theme) {
    if (widget.mode == AuthMode.signup && _signupStep > 0) {
      return Row(
        children: [
          SizedBox(
            height: 44,
            child: OutlinedButton(
              onPressed: _isLoading
                  ? null
                  : () {
                      FocusScope.of(context).unfocus();
                      setState(() => _signupStep -= 1);
                    },
              child: const Text('Back'),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(child: _buildPrimaryButton(theme)),
        ],
      );
    }
    return _buildPrimaryButton(theme);
  }

  Widget _buildPrimaryButton(ThemeData theme) {
    return SizedBox(
      width: double.infinity,
      height: 44,
      child: ElevatedButton(
        onPressed: _isLoading ? null : _handleSubmit,
        style: ElevatedButton.styleFrom(
          backgroundColor: Colors.blue,
          foregroundColor: Colors.white,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        ),
        child: _isLoading
            ? const CircularProgressIndicator(
                valueColor: AlwaysStoppedAnimation<Color>(
                  Colors.white,
                ),
              )
            : Text(_primaryButtonLabel()),
      ),
    );
  }

  String _primaryButtonLabel() {
    if (widget.mode == AuthMode.signin) {
      return 'Sign In';
    }
    return _signupStep == 3 ? 'Create Account' : 'Next';
  }

  Widget _buildLegalConsent() {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest.withOpacity(0.35),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: theme.dividerColor),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          CheckboxListTile(
            value: _acceptedLegal,
            contentPadding: EdgeInsets.zero,
            dense: true,
            visualDensity: const VisualDensity(horizontal: -4, vertical: -4),
            controlAffinity: ListTileControlAffinity.leading,
            onChanged: (value) {
              setState(() => _acceptedLegal = value ?? false);
            },
            title: const Text(
              'I agree to the Terms of Service and Privacy Policy',
              style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
            ),
          ),
          const SizedBox(height: 2),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextButton(
                onPressed: () {
                  Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => const TermsOfServiceScreen(),
                    ),
                  );
                },
                style: TextButton.styleFrom(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  minimumSize: Size.zero,
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
                child: const Text(
                  'View Terms',
                  style: TextStyle(fontSize: 12),
                ),
              ),
              const SizedBox(width: 4),
              TextButton(
                onPressed: () {
                  Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => const PrivacyPolicyScreen(),
                    ),
                  );
                },
                style: TextButton.styleFrom(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  minimumSize: Size.zero,
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
                child: const Text(
                  'View Privacy Policy',
                  style: TextStyle(fontSize: 12),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildFooter() {
    final theme = Theme.of(context);
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Text(
          widget.mode == AuthMode.signin
              ? "Don't have an account? "
              : "Already have an account? ",
        ),
        GestureDetector(
          onTap: _switchMode,
          child: Text(
            widget.mode == AuthMode.signin ? 'Sign Up' : 'Sign In',
            style: TextStyle(
              color: theme.colorScheme.primary,
              decoration: TextDecoration.underline,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ],
    );
  }

  Future<void> _handleSubmit() async {
    FocusScope.of(context).unfocus();
    if (!_formKey.currentState!.validate()) return;
    if (widget.mode == AuthMode.signup && _signupStep == 2) {
      if (_selectedGender == null) {
        setState(() {});
        return;
      }
    }
    if (widget.mode == AuthMode.signup && _signupStep < 3) {
      setState(() => _signupStep += 1);
      return;
    }
    if (widget.mode == AuthMode.signup && !_acceptedLegal) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Accept the Terms of Service and Privacy Policy to continue.',
          ),
        ),
      );
      return;
    }

    setState(() => _isLoading = true);

    try {
      var authSucceeded = false;
      if (widget.mode == AuthMode.signin) {
        final email = _emailController.text.trim();
        final password = _passwordController.text;
        final emailExists = await BackendService.emailExists(email);
        if (!emailExists) {
          throw StateError('User does not exist');
        }
        await BackendService.signIn(
          email,
          password,
        );
        authSucceeded = true;
      } else {
        final raw = _usernameController.text.trim();
        final handle = raw.startsWith('@') ? raw.substring(1) : raw;
        final referralCode = _referralCodeController.text.trim();
        final dateOfBirth = _selectedDateOfBirth;
        final gender = _selectedGender;
        if (dateOfBirth == null) {
          throw StateError('Date of birth is required');
        }
        if (gender == null || gender.trim().isEmpty) {
          throw StateError('Gender is required');
        }
        await BackendService.signUp(
          _emailController.text.trim(),
          _passwordController.text,
          handle,
          displayName: _displayNameController.text.trim(),
          dateOfBirth: dateOfBirth,
          country: _selectedCountry,
          gender: gender,
          referralCode: referralCode.isEmpty ? null : referralCode,
        );
        authSucceeded = true;
      }
      if (authSucceeded) {
        try {
          await PushNotificationService.refreshPermissionsAndSync();
        } catch (_) {
          // Keep authentication success independent from notification setup.
        }
      }
      if (!mounted) return;
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => const AuthWrapper()),
        (route) => false,
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(_authErrorMessage(e))),
      );
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _showForgotPasswordDialog() async {
    final shouldSend = await showDialog<bool>(
      context: context,
      builder: (dialogContext) =>
          _ForgotPasswordDialog(initialEmail: _emailController.text.trim()),
    );

    if (shouldSend == true && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Reset email sent')),
      );
    }
  }

  String _authErrorMessage(Object error) {
    final normalized = error.toString().toLowerCase();
    if (normalized.contains('verification required') ||
        normalized.contains('confirm email') ||
        normalized.contains('email_not_confirmed') ||
        normalized.contains('email not confirmed')) {
      return 'Verification required: Please check your email to confirm registration.';
    }

    if (_isNoNetworkError(error, normalized)) {
      return 'No network';
    }

    if (normalized.contains('user does not exist') ||
        normalized.contains('user not found') ||
        normalized.contains('email not found') ||
        normalized.contains('not found')) {
      return 'User does not exist';
    }

    if (error is DatabaseException) {
      final type = (error.type ?? '').toLowerCase();
      final message = (error.message ?? '').toLowerCase();
      final code = error.code ?? 0;

      if (code == 0 ||
          code == 503 ||
          type.contains('general_network') ||
          message.contains('network') ||
          message.contains('connection')) {
        return 'No network';
      }

      if (type.contains('user_already_exists') ||
          message.contains('already exists')) {
        return 'Email already exists';
      }

      if (widget.mode == AuthMode.signin &&
          (code == 404 ||
              type.contains('user_not_found') ||
              message.contains('user not found') ||
              message.contains('email not found') ||
              message.contains('not found'))) {
        return 'User does not exist';
      }

      if (widget.mode == AuthMode.signin &&
          (type.contains('user_invalid_credentials') ||
              message.contains('invalid credentials') ||
              message.contains('wrong password') ||
              message.contains('password') ||
              code == 401)) {
        return 'Incorrect password';
      }
    }

    // Return the actual error message to easily identify what is failing
    return error.toString();
  }

  bool _isNoNetworkError(Object error, String normalized) {
    if (NetworkStatusService.isOffline.value) {
      return true;
    }

    return normalized.contains('socketexception') ||
        normalized.contains('failed host lookup') ||
        normalized.contains('network is unreachable') ||
        normalized.contains('connection refused') ||
        normalized.contains('connection timed out') ||
        normalized.contains('connection failed') ||
        normalized.contains('timed out') ||
        normalized.contains('timeout');
  }

  void _switchMode() {
    FocusScope.of(context).unfocus();
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(
        builder: (context) => AuthForm(
          mode: widget.mode == AuthMode.signin
              ? AuthMode.signup
              : AuthMode.signin,
        ),
      ),
    );
  }

  Future<void> _pickDateOfBirth() async {
    final now = DateTime.now();
    final initialDate =
        _selectedDateOfBirth ?? DateTime(now.year - 18, now.month, now.day);
    final picked = await showDatePicker(
      context: context,
      initialDate: initialDate,
      firstDate: DateTime(1900),
      lastDate: now,
    );
    if (picked == null || !mounted) return;
    setState(() {
      _selectedDateOfBirth = picked;
      _dateOfBirthController.text = _formatDate(picked);
    });
  }

  String _formatDate(DateTime value) {
    final month = value.month.toString().padLeft(2, '0');
    final day = value.day.toString().padLeft(2, '0');
    return '${value.year}-$month-$day';
  }

  void _openApp() {
    launchUrl(
      Uri.parse('xapzap://auth'),
      mode: LaunchMode.externalApplication,
    );
  }

  void _openStore() {
    launchUrl(
      Uri.parse('https://play.google.com/store/apps/details?id=com.xapzap.xap'),
      mode: LaunchMode.externalApplication,
    );
  }

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    _confirmPasswordController.dispose();
    _usernameController.dispose();
    _displayNameController.dispose();
    _dateOfBirthController.dispose();
    _referralCodeController.dispose();
    super.dispose();
  }
}

class _ForgotPasswordDialog extends StatefulWidget {
  final String initialEmail;

  const _ForgotPasswordDialog({required this.initialEmail});

  @override
  State<_ForgotPasswordDialog> createState() => _ForgotPasswordDialogState();
}

class _ForgotPasswordDialogState extends State<_ForgotPasswordDialog> {
  late final TextEditingController _emailController;
  final _formKey = GlobalKey<FormState>();
  bool _isSending = false;

  @override
  void initState() {
    super.initState();
    _emailController = TextEditingController(text: widget.initialEmail);
  }

  @override
  void dispose() {
    _emailController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    FocusScope.of(context).unfocus();
    if (!_formKey.currentState!.validate()) return;
    setState(() => _isSending = true);
    try {
      await BackendService.sendPasswordRecovery(
        _emailController.text.trim(),
      );
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Unable to send reset email')),
      );
    } finally {
      if (mounted) {
        setState(() => _isSending = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Reset password'),
      content: Form(
        key: _formKey,
        child: TextFormField(
          controller: _emailController,
          keyboardType: TextInputType.emailAddress,
          decoration: const InputDecoration(
            labelText: 'Email',
          ),
          validator: (value) {
            final text = value?.trim() ?? '';
            if (text.isEmpty ||
                !RegExp(r'^[^@]+@[^@]+\.[^@]+').hasMatch(text)) {
              return 'Enter a valid email';
            }
            return null;
          },
        ),
      ),
      actions: [
        TextButton(
          onPressed: _isSending ? null : () => Navigator.of(context).pop(false),
          child: const Text('Cancel'),
        ),
        ElevatedButton(
          onPressed: _isSending ? null : _submit,
          child: _isSending
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Text('Send'),
        ),
      ],
    );
  }
}
