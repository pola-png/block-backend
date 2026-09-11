import 'package:flutter/material.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../services/backend_service.dart';
import '../services/micro_job_service.dart';

class AdminEarningsControlScreen extends StatefulWidget {
  const AdminEarningsControlScreen({super.key});

  @override
  State<AdminEarningsControlScreen> createState() => _AdminEarningsControlScreenState();
}

class _AdminEarningsControlScreenState extends State<AdminEarningsControlScreen> {
  final _userIdController = TextEditingController();
  bool _isSearching = false;
  Map<String, dynamic>? _userProfile;
  double? _userBalance;
  int _userTaskCount = 0;
  String? _error;

  @override
  void dispose() {
    _userIdController.dispose();
    super.dispose();
  }

  Future<void> _searchUser() async {
    final trimmedId = _userIdController.text.trim();
    if (trimmedId.isEmpty) return;

    setState(() {
      _isSearching = true;
      _userProfile = null;
      _userBalance = null;
      _userTaskCount = 0;
      _error = null;
    });

    try {
      final profileRes = await Supabase.instance.client
          .from('profiles')
          .select()
          .eq('id', trimmedId)
          .maybeSingle();

      if (profileRes == null) {
        setState(() {
          _error = 'User not found in profiles.';
          _isSearching = false;
        });
        return;
      }

      final balanceRow = await BackendService.getLatestCreatorBalance(trimmedId);
      double balance = 0.0;
      if (balanceRow != null) {
        final balanceData = balanceRow.data as Map<String, dynamic>;
        final val = balanceData['availableBalanceUsd'] ?? balanceData['balanceUsd'] ?? 0.0;
        balance = val is num ? val.toDouble() : (double.tryParse(val.toString()) ?? 0.0);
      }

      setState(() {
        _userProfile = profileRes;
        _userBalance = balance;
        _userTaskCount = profileRes['task_count'] as int? ?? 0;
        _isSearching = false;
      });
    } catch (e) {
      setState(() {
        _error = 'Failed to load user info: $e';
        _isSearching = false;
      });
    }
  }

  Future<void> _adjustBalance(double amount) async {
    if (_userProfile == null) return;
    final userId = _userProfile!['id'] as String;

    try {
      await BackendService.adjustUserBalance(userId, amount);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Balance adjusted by \$${amount.toStringAsFixed(2)}'),
          backgroundColor: Colors.green,
        ),
      );
      _searchUser();
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to adjust balance: $e'), backgroundColor: Colors.red),
      );
    }
  }

  Future<void> _toggleCheater(bool isCheater) async {
    if (_userProfile == null) return;
    final userId = _userProfile!['id'] as String;

    if (isCheater) {
      final reasonController = TextEditingController(text: 'Fraudulent/Fake video task completions.');
      final amountController = TextEditingController(text: '2.00');

      final proceed = await showDialog<bool>(
        context: context,
        builder: (dialogCtx) => AlertDialog(
          title: const Text('Flag Suspicious User & Apply Penalty'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: reasonController,
                decoration: const InputDecoration(labelText: 'Penalty Reason'),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: amountController,
                decoration: const InputDecoration(labelText: 'Penalty Deduction Amount (\$)'),
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogCtx).pop(false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              style: FilledButton.styleFrom(backgroundColor: Colors.red),
              onPressed: () => Navigator.of(dialogCtx).pop(true),
              child: const Text('Apply Penalty'),
            ),
          ],
        ),
      );

      if (proceed == true) {
        final reason = reasonController.text.trim();
        final deduction = double.tryParse(amountController.text.trim()) ?? 0.0;

        try {
          await BackendService.markUserCheater(
            userId,
            isCheater: true,
            deduction: deduction,
            reason: reason,
          );
          _searchUser();
        } catch (e) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text('Action failed: $e'), backgroundColor: Colors.red),
            );
          }
        }
      }
    } else {
      try {
        await BackendService.markUserCheater(userId, isCheater: false);
        _searchUser();
      } catch (e) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Action failed: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Earnings & Fraud Controls', style: TextStyle(fontWeight: FontWeight.bold)),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16.0),
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(12.0),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _userIdController,
                      decoration: const InputDecoration(
                        hintText: 'Enter Creator User ID',
                        border: InputBorder.none,
                      ),
                      onSubmitted: (_) => _searchUser(),
                    ),
                  ),
                  _isSearching
                      ? const SizedBox(
                          height: 20,
                          width: 20,
                          child: CircularProgressIndicator(strokeWidth: 2, color: Colors.pinkAccent),
                        )
                      : IconButton(
                          icon: const Icon(Icons.search, color: Colors.pinkAccent),
                          onPressed: _searchUser,
                        ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.all(8.0),
              child: Text(_error!, style: const TextStyle(color: Colors.red, fontWeight: FontWeight.bold)),
            ),
          if (_userProfile != null) ...[
            _buildProfileSummary(theme, isDark),
            const SizedBox(height: 16),
            _buildBalanceControls(theme),
            const SizedBox(height: 16),
            _buildCheaterControls(theme),
          ],
        ],
      ),
    );
  }

  Widget _buildProfileSummary(ThemeData theme, bool isDark) {
    final bool cheater = _userProfile!['is_cheater'] == true;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('User Information', style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
            const Divider(),
            _infoRow('Display Name', _userProfile!['display_name'] ?? _userProfile!['username'] ?? ''),
            _infoRow('Username', '@${_userProfile!['username'] ?? ''}'),
            _infoRow('Completed Tasks', '$_userTaskCount tasks completed'),
            _infoRow('Available Balance', '\$${_userBalance?.toStringAsFixed(2) ?? '0.00'}', isHighlight: true),
            _infoRow(
              'Profile Status',
              cheater ? '⚠️ FLAGGED FOR FAKE ACTIVITY' : '✅ Clear Account',
              highlightColor: cheater ? Colors.red : Colors.green,
            ),
          ],
        ),
      ),
    );
  }

  Widget _infoRow(String label, String value, {bool isHighlight = false, Color? highlightColor}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: const TextStyle(color: Colors.grey, fontSize: 13)),
          Text(
            value,
            style: TextStyle(
              fontWeight: FontWeight.bold,
              fontSize: 13,
              color: highlightColor ?? (isHighlight ? Colors.green : null),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBalanceControls(ThemeData theme) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Balance Adjustments', style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(backgroundColor: Colors.green, foregroundColor: Colors.white),
                  icon: const Icon(Icons.add, size: 16),
                  label: const Text('Add \$1.00'),
                  onPressed: () => _adjustBalance(1.0),
                ),
                ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(backgroundColor: Colors.orange, foregroundColor: Colors.white),
                  icon: const Icon(Icons.remove, size: 16),
                  label: const Text('Deduct \$1.00'),
                  onPressed: () => _adjustBalance(-1.0),
                ),
                OutlinedButton(
                  child: const Text('Custom Value'),
                  onPressed: () async {
                    final amountStr = await _promptForText(
                      context,
                      title: 'Enter Custom Adjustment',
                      label: 'Positive to add, negative to deduct (e.g. 5.00 or -3.50)',
                    );
                    if (amountStr != null) {
                      final double? val = double.tryParse(amountStr);
                      if (val != null) {
                        _adjustBalance(val);
                      }
                    }
                  },
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCheaterControls(ThemeData theme) {
    final bool isCheater = _userProfile!['is_cheater'] == true;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Fraud & Alert Controls', style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: isCheater
                  ? ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(backgroundColor: Colors.green, foregroundColor: Colors.white),
                      icon: const Icon(Icons.check_circle_outline),
                      label: const Text('Remove Cheater Penalty Flag'),
                      onPressed: () => _toggleCheater(false),
                    )
                  : ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(backgroundColor: Colors.red, foregroundColor: Colors.white),
                      icon: const Icon(Icons.gavel),
                      label: const Text('Mark as Cheater & Apply Fine'),
                      onPressed: () => _toggleCheater(true),
                    ),
            ),
          ],
        ),
      ),
    );
  }

  Future<String?> _promptForText(
    BuildContext context, {
    required String title,
    required String label,
    String initialValue = '',
  }) async {
    final controller = TextEditingController(text: initialValue);
    final result = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(title),
        content: TextField(
          controller: controller,
          decoration: InputDecoration(
            labelText: label,
            border: const OutlineInputBorder(),
          ),
          keyboardType: const TextInputType.numberWithOptions(decimal: true, signed: true),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(controller.text.trim()),
            child: const Text('Submit'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (result == null || result.trim().isEmpty) return null;
    return result.trim();
  }
}
