import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutterwave_standard/flutterwave.dart';
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../services/backend_service.dart';
import '../services/currency_service.dart';

class PayoutVerificationScreen extends StatefulWidget {
  const PayoutVerificationScreen({super.key});

  @override
  State<PayoutVerificationScreen> createState() =>
      _PayoutVerificationScreenState();
}

class _PayoutVerificationScreenState extends State<PayoutVerificationScreen> {
  static const double _verificationFeeUsd = 2.0;

  bool _isLoading = true;
  bool _isProcessing = false;

  bool _isVerified = false;
  bool _idSubmitted = false;
  // unverified | fee_paid | id_pending | verified
  String _verificationStatus = 'unverified';

  File? _selectedIdFile;
  bool _isUploadingId = false;

  @override
  void initState() {
    super.initState();
    _loadVerificationStatus();
  }

  Future<void> _loadVerificationStatus() async {
    try {
      final user = Supabase.instance.client.auth.currentUser;
      if (user == null) return;

      final res = await Supabase.instance.client
          .from('profiles')
          .select('is_verified, id_submitted, verification_status')
          .eq('id', user.id)
          .maybeSingle();

      if (res != null && mounted) {
        setState(() {
          _isVerified = res['is_verified'] == true;
          _idSubmitted = res['id_submitted'] == true;
          _verificationStatus =
              res['verification_status'] as String? ?? 'unverified';
        });
      }
    } catch (e) {
      debugPrint('Error loading verification status: $e');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  bool get _feePaid =>
      _verificationStatus == 'fee_paid' ||
      _verificationStatus == 'id_pending' ||
      _isVerified;

  Future<void> _payVerificationFee() async {
    if (_isProcessing) return;
    setState(() => _isProcessing = true);

    try {
      final user = await BackendService.getCurrentUser();
      if (user == null) throw StateError('You must be logged in.');

      final supabaseUser = Supabase.instance.client.auth.currentUser;
      if (supabaseUser == null) throw StateError('Session expired. Please log in again.');

      final publicKey = dotenv.env['FLW_PUBLIC_KEY'] ?? '';
      final redirectUrl =
          dotenv.env['FLW_REDIRECT_URL'] ?? 'https://xapzap.com/payment-redirect';
      final isTestMode = (dotenv.env['FLW_TEST_MODE'] ?? 'false') == 'true';

      if (publicKey.isEmpty) throw StateError('Payment configuration missing.');

      final customer = Customer(
        name: user.name.trim().isNotEmpty ? user.name : 'XapZap User',
        phoneNumber: '08000000000',
        email: user.email.trim().isNotEmpty ? user.email : 'user@xapzap.com',
      );

      final txRef =
          'xapzap_kyc_${supabaseUser.id}_${DateTime.now().millisecondsSinceEpoch}';

      final localCurrencyInfo =
          await CurrencyService.getLocalCurrencyInfo(_verificationFeeUsd);
      final finalCurrency = localCurrencyInfo.currencyCode;
      final finalAmount = localCurrencyInfo.convertedAmount;

      final flutterwave = Flutterwave(
        publicKey: publicKey,
        currency: finalCurrency,
        amount: finalAmount.toStringAsFixed(2),
        customer: customer,
        txRef: txRef,
        redirectUrl: redirectUrl,
        paymentOptions: 'card,account,ussd,barter',
        customization: Customization(
          title: 'XapZap Identity Verification',
          description:
              'One-time KYC identity verification fee — ${finalAmount.toStringAsFixed(2)} $finalCurrency',
        ),
        isTestMode: isTestMode,
      );

      if (!mounted) return;
      final ChargeResponse response = await flutterwave.charge(context);

      debugPrint(
          'KYC Verification ChargeResponse: status=${response.status}, txRef=${response.txRef}');

      final String status = (response.status ?? '').toLowerCase();
      if (status != 'success' && status != 'successful') {
        throw StateError('Payment not completed. Status: "${response.status}"');
      }

      await Supabase.instance.client.from('profiles').update({
        'verification_fee_paid': true,
        'verification_status': _idSubmitted ? 'id_pending' : 'fee_paid',
        'kyc_tx_ref': txRef,
        'kyc_paid_at': DateTime.now().toIso8601String(),
      }).eq('id', supabaseUser.id);

      if (mounted) {
        setState(() {
          _verificationStatus = _idSubmitted ? 'id_pending' : 'fee_paid';
        });
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
                '✅ Verification fee paid! Please upload your Government ID to complete verification.'),
            backgroundColor: Colors.green,
            duration: Duration(seconds: 4),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Payment failed: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isProcessing = false);
    }
  }

  Future<void> _pickIdDocument() async {
    final picker = ImagePicker();
    final picked =
        await picker.pickImage(source: ImageSource.gallery, imageQuality: 85);
    if (picked != null && mounted) {
      setState(() => _selectedIdFile = File(picked.path));
    }
  }

  Future<void> _uploadIdDocument() async {
    if (_selectedIdFile == null || _isUploadingId) return;
    setState(() => _isUploadingId = true);

    try {
      final supabaseUser = Supabase.instance.client.auth.currentUser;
      if (supabaseUser == null) throw StateError('Session expired.');

      final fileExt = _selectedIdFile!.path.split('.').last.toLowerCase();
      final fileName =
          'kyc_id_${supabaseUser.id}_${DateTime.now().millisecondsSinceEpoch}.$fileExt';
      final storagePath = 'kyc_documents/$fileName';
      final bytes = await _selectedIdFile!.readAsBytes();

      await Supabase.instance.client.storage
          .from('xapzap-backend')
          .uploadBinary(
            storagePath,
            bytes,
            fileOptions:
                FileOptions(contentType: 'image/$fileExt', upsert: false),
          );

      final publicUrl = Supabase.instance.client.storage
          .from('xapzap-backend')
          .getPublicUrl(storagePath);

      await Supabase.instance.client.from('profiles').update({
        'id_submitted': true,
        'id_document_url': publicUrl,
        'verification_status': 'id_pending',
        'id_submitted_at': DateTime.now().toIso8601String(),
      }).eq('id', supabaseUser.id);

      if (mounted) {
        setState(() {
          _idSubmitted = true;
          _verificationStatus = 'id_pending';
        });
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
                '✅ Government ID uploaded! Your identity is now under review. We will notify you within 24–48 hours.'),
            backgroundColor: Colors.green,
            duration: Duration(seconds: 5),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Upload failed: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isUploadingId = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Identity Verification',
            style: TextStyle(fontWeight: FontWeight.bold)),
        backgroundColor: theme.colorScheme.surface,
        foregroundColor: theme.colorScheme.onSurface,
        elevation: 0.5,
        surfaceTintColor: Colors.transparent,
      ),
      body: _isLoading
          ? const Center(
              child: CircularProgressIndicator(color: Colors.pinkAccent))
          : ListView(
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 60),
              children: [
                _buildStatusBanner(theme, isDark),
                const SizedBox(height: 20),
                if (_isVerified) ...[
                  _buildVerifiedCard(theme, isDark),
                ] else ...[
                  _buildInfoCard(theme, isDark),
                  const SizedBox(height: 20),
                  _buildStep1(theme, isDark),
                  const SizedBox(height: 16),
                  _buildStep2(theme, isDark),
                  const SizedBox(height: 20),
                  _buildLegalNote(theme),
                ],
              ],
            ),
    );
  }

  Widget _buildStatusBanner(ThemeData theme, bool isDark) {
    Color bannerColor;
    IconData bannerIcon;
    String bannerText;

    if (_isVerified) {
      bannerColor = Colors.green;
      bannerIcon = Icons.verified_user_rounded;
      bannerText = 'Identity Verified — You are cleared for payouts';
    } else if (_verificationStatus == 'id_pending') {
      bannerColor = Colors.amber.shade700;
      bannerIcon = Icons.hourglass_top_rounded;
      bannerText = 'Under Review — Your ID is being verified (24–48 hrs)';
    } else if (_verificationStatus == 'fee_paid') {
      bannerColor = Colors.blue;
      bannerIcon = Icons.credit_score_rounded;
      bannerText = 'Fee Paid — Please upload your Government ID to continue';
    } else {
      bannerColor = Colors.redAccent;
      bannerIcon = Icons.warning_amber_rounded;
      bannerText =
          'Verification Required — Complete KYC to receive your earnings';
    }

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: bannerColor.withOpacity(isDark ? 0.15 : 0.08),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: bannerColor.withOpacity(0.35), width: 1.5),
      ),
      child: Row(
        children: [
          Icon(bannerIcon, color: bannerColor, size: 26),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              bannerText,
              style: TextStyle(
                color: bannerColor,
                fontWeight: FontWeight.w700,
                fontSize: 13,
                height: 1.3,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildInfoCard(ThemeData theme, bool isDark) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: isDark ? Colors.white10 : theme.dividerColor.withOpacity(0.5),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(isDark ? 0.2 : 0.03),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.pinkAccent.withOpacity(0.1),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.shield_rounded,
                    color: Colors.pinkAccent, size: 22),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  'Why is verification required?',
                  style: theme.textTheme.titleSmall
                      ?.copyWith(fontWeight: FontWeight.w800),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          _infoRow(theme,
              '🔒 Anti-fraud compliance — We verify identities to prevent fraudulent payout claims.'),
          const SizedBox(height: 8),
          _infoRow(theme,
              '💳 Financial regulations — Identity checks are required for processing financial transfers.'),
          const SizedBox(height: 8),
          _infoRow(theme,
              '✅ One-time only — Once verified, you never need to do this again.'),
          const SizedBox(height: 8),
          _infoRow(theme,
              '🔐 Secure storage — Your ID documents are encrypted and stored securely. They are never shared.'),
        ],
      ),
    );
  }

  Widget _infoRow(ThemeData theme, String text) {
    return Text(
      text,
      style: theme.textTheme.bodySmall?.copyWith(
        height: 1.45,
        color: theme.colorScheme.onSurfaceVariant,
        fontSize: 12.5,
      ),
    );
  }

  Widget _buildStep1(ThemeData theme, bool isDark) {
    final isPaid = _feePaid;
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: isPaid
              ? Colors.green.withOpacity(0.5)
              : (isDark ? Colors.white10 : theme.dividerColor.withOpacity(0.5)),
          width: isPaid ? 1.5 : 1.0,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              _stepCircle(theme, '1', isPaid),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Pay \$2.00 Verification Fee',
                      style: theme.textTheme.titleSmall
                          ?.copyWith(fontWeight: FontWeight.w800),
                    ),
                    Text(
                      isPaid
                          ? 'Fee paid ✓'
                          : 'One-time identity verification charge',
                      style: TextStyle(
                        fontSize: 12,
                        color: isPaid
                            ? Colors.green
                            : theme.colorScheme.onSurfaceVariant,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          if (!isPaid) ...[
            const SizedBox(height: 16),
            ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.pinkAccent,
                foregroundColor: Colors.white,
                minimumSize: const Size(double.infinity, 48),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12)),
                elevation: 0,
              ),
              onPressed: _isProcessing ? null : _payVerificationFee,
              icon: _isProcessing
                  ? const SizedBox(
                      height: 18,
                      width: 18,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.white),
                    )
                  : const Icon(Icons.credit_card_rounded),
              label: Text(
                _isProcessing
                    ? 'Processing...'
                    : 'Pay \$2.00 Verification Fee',
                style: const TextStyle(
                    fontWeight: FontWeight.bold, fontSize: 15),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildStep2(ThemeData theme, bool isDark) {
    final isSubmitted = _idSubmitted || _isVerified;
    final canUpload = _feePaid && !isSubmitted;

    return Opacity(
      opacity: (!_feePaid && !isSubmitted) ? 0.45 : 1.0,
      child: Container(
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          color: theme.colorScheme.surface,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: isSubmitted
                ? Colors.green.withOpacity(0.5)
                : (isDark
                    ? Colors.white10
                    : theme.dividerColor.withOpacity(0.5)),
            width: isSubmitted ? 1.5 : 1.0,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                _stepCircle(theme, '2', isSubmitted),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Upload Government ID',
                        style: theme.textTheme.titleSmall
                            ?.copyWith(fontWeight: FontWeight.w800),
                      ),
                      Text(
                        isSubmitted
                            ? 'ID submitted — under review'
                            : 'Passport, National ID, or Driver\'s License',
                        style: TextStyle(
                          fontSize: 12,
                          color: isSubmitted
                              ? Colors.green
                              : theme.colorScheme.onSurfaceVariant,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            if (canUpload) ...[
              const SizedBox(height: 16),
              if (_selectedIdFile != null) ...[
                ClipRRect(
                  borderRadius: BorderRadius.circular(10),
                  child: SizedBox(
                    height: 140,
                    width: double.infinity,
                    child: Image.file(_selectedIdFile!, fit: BoxFit.cover),
                  ),
                ),
                const SizedBox(height: 12),
              ],
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      style: OutlinedButton.styleFrom(
                        foregroundColor: theme.colorScheme.primary,
                        side: BorderSide(color: theme.colorScheme.primary),
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10)),
                      ),
                      onPressed: _pickIdDocument,
                      icon: const Icon(Icons.upload_file_rounded, size: 18),
                      label: Text(
                        _selectedIdFile == null
                            ? 'Select ID Document'
                            : 'Change Document',
                        style:
                            const TextStyle(fontWeight: FontWeight.bold),
                      ),
                    ),
                  ),
                  if (_selectedIdFile != null) ...[
                    const SizedBox(width: 12),
                    Expanded(
                      child: ElevatedButton.icon(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.green,
                          foregroundColor: Colors.white,
                          padding:
                              const EdgeInsets.symmetric(vertical: 12),
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(10)),
                          elevation: 0,
                        ),
                        onPressed:
                            _isUploadingId ? null : _uploadIdDocument,
                        icon: _isUploadingId
                            ? const SizedBox(
                                height: 16,
                                width: 16,
                                child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: Colors.white),
                              )
                            : const Icon(Icons.cloud_upload_rounded,
                                size: 18),
                        label: Text(
                          _isUploadingId ? 'Uploading...' : 'Submit ID',
                          style: const TextStyle(
                              fontWeight: FontWeight.bold),
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _stepCircle(ThemeData theme, String label, bool done) {
    return Container(
      width: 32,
      height: 32,
      decoration: BoxDecoration(
        color: done
            ? Colors.green.withOpacity(0.15)
            : theme.colorScheme.primary.withOpacity(0.12),
        shape: BoxShape.circle,
      ),
      child: Center(
        child: done
            ? const Icon(Icons.check_rounded, color: Colors.green, size: 18)
            : Text(
                label,
                style: TextStyle(
                  color: theme.colorScheme.primary,
                  fontWeight: FontWeight.bold,
                  fontSize: 14,
                ),
              ),
      ),
    );
  }

  Widget _buildVerifiedCard(ThemeData theme, bool isDark) {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: isDark
              ? [const Color(0xFF0D2B1E), const Color(0xFF0F1A12)]
              : [const Color(0xFFE8F5E9), Colors.white],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: Colors.green.withOpacity(0.35)),
      ),
      child: Column(
        children: [
          const Icon(Icons.verified_user_rounded,
              color: Colors.green, size: 56),
          const SizedBox(height: 16),
          Text(
            'Identity Verified!',
            style: theme.textTheme.titleLarge?.copyWith(
              fontWeight: FontWeight.w900,
              color: Colors.green.shade700,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Your identity has been verified successfully. You are now eligible to receive your earnings on the monthly payout date (27th of each month).',
            textAlign: TextAlign.center,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
              height: 1.5,
            ),
          ),
          const SizedBox(height: 20),
          ElevatedButton.icon(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.green,
              foregroundColor: Colors.white,
              padding:
                  const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12)),
            ),
            onPressed: () => Navigator.pop(context),
            icon: const Icon(Icons.check_circle_outline),
            label: const Text('Back to Monetization',
                style: TextStyle(fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  Widget _buildLegalNote(ThemeData theme) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest.withOpacity(0.3),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        'The \$2.00 verification fee is a one-time identity verification charge required under our anti-fraud and financial compliance policy. It is NOT a payment for any in-app feature or service. Your ID documents are stored securely and encrypted, and are only used for identity verification purposes. By proceeding, you agree to our Terms of Service and Privacy Policy.',
        style: theme.textTheme.bodySmall?.copyWith(
          color: theme.colorScheme.onSurfaceVariant,
          fontSize: 10.5,
          height: 1.5,
        ),
      ),
    );
  }
}
