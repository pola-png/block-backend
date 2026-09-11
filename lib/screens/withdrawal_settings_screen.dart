import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class WithdrawalSettingsScreen extends StatefulWidget {
  const WithdrawalSettingsScreen({super.key});

  @override
  State<WithdrawalSettingsScreen> createState() => _WithdrawalSettingsScreenState();
}

class _WithdrawalSettingsScreenState extends State<WithdrawalSettingsScreen> {
  final _formKey = GlobalKey<FormState>();
  final _bankNameController = TextEditingController();
  final _accountNumberController = TextEditingController();
  final _accountNameController = TextEditingController();
  final _routingController = TextEditingController();
  final _cryptoController = TextEditingController();

  String _preferredMethod = 'bank_transfer';
  bool _isLoading = true;
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    _loadWithdrawalDetails();
  }

  Future<void> _loadWithdrawalDetails() async {
    try {
      final user = Supabase.instance.client.auth.currentUser;
      if (user == null) return;

      final res = await Supabase.instance.client
          .from('user_withdrawal_details')
          .select()
          .eq('user_id', user.id)
          .maybeSingle();

      if (res != null && mounted) {
        setState(() {
          _preferredMethod = res['preferred_method'] ?? 'bank_transfer';
          _bankNameController.text = res['bank_name'] ?? '';
          _accountNumberController.text = res['account_number'] ?? '';
          _accountNameController.text = res['account_name'] ?? '';
          _routingController.text = res['routing_number_or_swift'] ?? '';
          _cryptoController.text = res['crypto_address'] ?? '';
        });
      }
    } catch (e) {
      debugPrint('Error loading withdrawal details: $e');
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _saveDetails() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() {
      _isSaving = true;
    });

    try {
      final user = Supabase.instance.client.auth.currentUser;
      if (user == null) return;

      await Supabase.instance.client.from('user_withdrawal_details').upsert({
        'user_id': user.id,
        'preferred_method': _preferredMethod,
        'bank_name': _preferredMethod == 'bank_transfer' ? _bankNameController.text.trim() : null,
        'account_number': _preferredMethod == 'bank_transfer' ? _accountNumberController.text.trim() : null,
        'account_name': _preferredMethod == 'bank_transfer' ? _accountNameController.text.trim() : null,
        'routing_number_or_swift': _preferredMethod == 'bank_transfer' ? _routingController.text.trim() : null,
        'crypto_address': _preferredMethod == 'crypto' ? _cryptoController.text.trim() : null,
        'updated_at': DateTime.now().toIso8601String(),
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Withdrawal details updated successfully!'),
            backgroundColor: Colors.green,
          ),
        );
        Navigator.pop(context);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to save details: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isSaving = false;
        });
      }
    }
  }

  @override
  void dispose() {
    _bankNameController.dispose();
    _accountNumberController.dispose();
    _accountNameController.dispose();
    _routingController.dispose();
    _cryptoController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    if (_isLoading) {
      return Scaffold(
        appBar: AppBar(title: const Text('Withdrawal Settings')),
        body: const Center(child: CircularProgressIndicator(color: Colors.pinkAccent)),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Withdrawal Settings', style: TextStyle(fontWeight: FontWeight.bold)),
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(16.0),
          children: [
            Card(
              color: theme.colorScheme.primaryContainer,
              margin: const EdgeInsets.only(bottom: 20),
              child: Padding(
                padding: EdgeInsets.all(16.0),
                child: Row(
                  children: [
                    Icon(Icons.info_outline, color: Colors.pinkAccent),
                    SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        'Provide your payout credentials below. Your earnings will be automatically paid out to your active coordinates.',
                        style: TextStyle(fontSize: 13, height: 1.4),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            Text(
              'Preferred Method',
              style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            DropdownButtonFormField<String>(
              value: _preferredMethod,
              decoration: InputDecoration(
                filled: true,
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
              ),
              items: const [
                DropdownMenuItem(value: 'bank_transfer', child: Text('Bank Transfer')),
                DropdownMenuItem(value: 'crypto', child: Text('USDT Crypto Wallet (TRC-20)')),
              ],
              onChanged: (val) {
                if (val != null) {
                  setState(() {
                    _preferredMethod = val;
                  });
                }
              },
            ),
            const SizedBox(height: 20),
            if (_preferredMethod == 'bank_transfer') ...[
              Text(
                'Bank Information',
                style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _bankNameController,
                decoration: InputDecoration(
                  labelText: 'Bank Name',
                  prefixIcon: const Icon(Icons.account_balance),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                ),
                validator: (val) => val == null || val.isEmpty ? 'Required' : null,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _accountNumberController,
                decoration: InputDecoration(
                  labelText: 'Account Number',
                  prefixIcon: const Icon(Icons.numbers),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                ),
                keyboardType: TextInputType.number,
                validator: (val) => val == null || val.isEmpty ? 'Required' : null,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _accountNameController,
                decoration: InputDecoration(
                  labelText: 'Account Holder Name',
                  prefixIcon: const Icon(Icons.person),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                ),
                validator: (val) => val == null || val.isEmpty ? 'Required' : null,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _routingController,
                decoration: InputDecoration(
                  labelText: 'Routing Number / Swift Code (Optional)',
                  prefixIcon: const Icon(Icons.code),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                ),
              ),
            ] else ...[
              Text(
                'USDT Wallet (TRC-20)',
                style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _cryptoController,
                decoration: InputDecoration(
                  labelText: 'Crypto Wallet Address (USDT TRC-20)',
                  prefixIcon: const Icon(Icons.wallet),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                ),
                validator: (val) {
                  if (val == null || val.isEmpty) return 'Required';
                  if (!val.startsWith('T') || val.length < 30) {
                    return 'Please enter a valid TRC-20 wallet address';
                  }
                  return null;
                },
              ),
            ],
            const SizedBox(height: 32),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.pinkAccent,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 16),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
              onPressed: _isSaving ? null : _saveDetails,
              child: _isSaving
                  ? const SizedBox(
                      height: 20,
                      width: 20,
                      child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
                    )
                  : const Text('Save Withdrawal Coordinates', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
            ),
          ],
        ),
      ),
    );
  }
}
