import 'package:flutter/material.dart';

import '../models/post.dart';
import '../services/boost_service.dart';
import '../services/backend_service.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutterwave_standard/flutterwave.dart';
import '../services/currency_service.dart';

class BoostPostScreen extends StatefulWidget {
  final Post post;

  const BoostPostScreen({super.key, required this.post});

  @override
  State<BoostPostScreen> createState() => _BoostPostScreenState();
}

class _BoostPostScreenState extends State<BoostPostScreen> {
  double _amount = 1.0;
  int _days = 1;
  bool _isSubmitting = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final targetReach = BoostService.computeTargetReach(
      _amount,
      _days,
    ).clamp(0, 1 << 31);

    return Scaffold(
      appBar: AppBar(title: const Text('Create ad')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Promote this post with ads',
              style: theme.textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            Text(
              'Base: \$1 ≈ 5,000 reach per day.\nIncrease amount or days to reach more people.',
              style: theme.textTheme.bodySmall,
            ),
            const SizedBox(height: 16),
            Text('Budget (\$)', style: theme.textTheme.labelMedium),
            const SizedBox(height: 4),
            Slider(
              min: 1,
              max: 20,
              divisions: 19,
              label: _amount.toStringAsFixed(0),
              value: _amount,
              onChanged: (v) {
                setState(() => _amount = v.roundToDouble());
              },
            ),
            Text('\$${_amount.toStringAsFixed(0)} per day'),
            const SizedBox(height: 16),
            Text('Duration (days)', style: theme.textTheme.labelMedium),
            const SizedBox(height: 4),
            Slider(
              min: 1,
              max: 30,
              divisions: 29,
              label: _days.toString(),
              value: _days.toDouble(),
              onChanged: (v) {
                setState(() => _days = v.round().clamp(1, 30));
              },
            ),
            Text('$_days day(s)'),
            const SizedBox(height: 16),
            Text(
              'Estimated reach: $targetReach people',
              style: theme.textTheme.bodyMedium?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
            const Spacer(),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: _isSubmitting ? null : _onStartBoost,
                child: _isSubmitting
                    ? const SizedBox(
                        height: 18,
                        width: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Text('Start ad (test mode)'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _onStartBoost() async {
    setState(() => _isSubmitting = true);
    try {
      // Create pending boost row first so we have a stable ID / txRef.
      final draft = await BoostService.createDraftBoost(
        postId: widget.post.id,
        amountUsd: _amount,
        days: _days,
      );

      final totalAmount = _amount * _days;
      final user = await BackendService.getCurrentUser();
      if (user == null) {
        throw StateError('User must be signed in to pay for ads.');
      }

      final publicKey = dotenv.env['FLW_PUBLIC_KEY'] ?? '';
      final redirectUrl =
          dotenv.env['FLW_REDIRECT_URL'] ?? 'https://example.com';
      final isTestMode = (dotenv.env['FLW_TEST_MODE'] ?? 'true') == 'true';

      if (publicKey.isEmpty) {
        throw StateError('Flutterwave public key is missing in .env');
      }

      final customer = Customer(
        name: user.name.trim().isNotEmpty ? user.name : 'XapZap User',
        phoneNumber: '08000000000',
        email: user.email.trim().isNotEmpty ? user.email : 'user@xapzap.com',
      );

      final txRef =
          'xapzap_ads_${draft.$id}_${DateTime.now().millisecondsSinceEpoch}';

      // Fetch network-detected local currency and exchange rates dynamically
      final localCurrencyInfo = await CurrencyService.getLocalCurrencyInfo(totalAmount);
      final finalCurrency = localCurrencyInfo.currencyCode;
      final finalAmount = localCurrencyInfo.convertedAmount;

      final flutterwave = Flutterwave(
        publicKey: publicKey,
        currency: finalCurrency,
        amount: finalAmount.toStringAsFixed(2),
        customer: customer,
        txRef: txRef,
        redirectUrl: redirectUrl,
        paymentOptions: "card,account,ussd,barter",
        customization: Customization(
          title: "Promote post",
          description: "Fund promotion for ${finalAmount.toStringAsFixed(2)} $finalCurrency",
        ),
        isTestMode: isTestMode,
      );

      if (!mounted) return;
      final ChargeResponse response = await flutterwave.charge(context);

      if ((response.status ?? '').toLowerCase() != 'success') {
        await BoostService.markBoostFailed(draft.$id);
        throw StateError('Payment not successful');
      }

      await BoostService.markBoostRunning(
        draft.$id,
        widget.post.id,
        paymentRef: response.txRef,
      );

      if (!mounted) return;
      Navigator.of(context).pop(true);
      final messenger = ScaffoldMessenger.of(context);
      messenger.showSnackBar(
        const SnackBar(content: Text('Ad campaign started.')),
      );
    } catch (e) {
      if (!mounted) return;
      Navigator.of(context).pop(false);
      final messenger = ScaffoldMessenger.of(context);
      messenger.showSnackBar(
        const SnackBar(content: Text('Failed to start ad campaign.')),
      );
    } finally {
      if (mounted) {
        setState(() => _isSubmitting = false);
      }
    }
  }
}
