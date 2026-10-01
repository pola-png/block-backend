import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/ad_gate_service.dart';
import '../screens/level_upgrades_screen.dart';

class AdFreeSubscriptionDialog extends StatefulWidget {
  const AdFreeSubscriptionDialog({super.key});

  static Future<void> checkAndShowDailyPopup(BuildContext context) async {
    try {
      final isAdFree = await XapZapAdGateService.instance.isAdFreeActive();
      if (isAdFree) return; // User already has active Ad-Free plan!

      final prefs = await SharedPreferences.getInstance();
      final nowStr = DateTime.now().toIso8601String().substring(0, 10); // YYYY-MM-DD
      final lastShown = prefs.getString('last_ad_free_popup_date');

      if (lastShown != nowStr) {
        await prefs.setString('last_ad_free_popup_date', nowStr);
        if (context.mounted) {
          showDialog(
            context: context,
            barrierDismissible: true,
            builder: (context) => const AdFreeSubscriptionDialog(),
          );
        }
      }
    } catch (e) {
      debugPrint('Error checking daily ad free popup: $e');
    }
  }

  @override
  State<AdFreeSubscriptionDialog> createState() => _AdFreeSubscriptionDialogState();
}

class _AdFreeSubscriptionDialogState extends State<AdFreeSubscriptionDialog> {
  bool _isSubscribing = false;

  final List<Map<String, dynamic>> _plans = [
    {
      'title': '1 Week Plan',
      'price': 1.60,
      'durationDays': 7,
      'period': '7 Days',
      'badge': 'Popular',
      'color': Colors.blue,
    },
    {
      'title': '1 Month Plan',
      'price': 4.90,
      'durationDays': 30,
      'period': '30 Days',
      'badge': 'Best Value',
      'color': Colors.orange,
    },
  ];

  Future<void> _handleSubscribe(Map<String, dynamic> plan) async {
    Navigator.pop(context);
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const LevelUpgradesScreen()),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return AlertDialog(
      backgroundColor: isDark ? const Color(0xFF1E1E1E) : Colors.white,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      contentPadding: const EdgeInsets.all(20),
      content: SingleChildScrollView(
        child: Container(
          width: double.maxFinite,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Header Icon
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: Colors.amber.withOpacity(0.15),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.block_flipped, color: Colors.amber, size: 38),
              ),
              const SizedBox(height: 12),
              
              Text(
                'Stop Interrupting Pop-up Ads!',
                textAlign: TextAlign.center,
                style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),

              // Warning Card
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.red.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.red.withOpacity(0.3)),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.warning_amber_rounded, color: Colors.redAccent, size: 24),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        'Free accounts encounter frequent pop-up ads. Upgrade to Ad-Free to stop pop-ups while continuing to earn full task rewards!',
                        style: TextStyle(
                          fontSize: 11.5,
                          height: 1.35,
                          color: isDark ? Colors.white70 : Colors.red.shade900,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),

              // Plans list
              Column(
                children: _plans.map((plan) {
                  final String title = plan['title'];
                  final double price = plan['price'];
                  final String period = plan['period'];
                  final String badge = plan['badge'];
                  final Color color = plan['color'];

                  return Card(
                    margin: const EdgeInsets.only(bottom: 10),
                    elevation: 1,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                      side: BorderSide(color: color.withOpacity(0.5), width: 1.5),
                    ),
                    color: isDark ? color.withOpacity(0.08) : color.withOpacity(0.04),
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: Row(
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Text(
                                      title,
                                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                                    ),
                                    const SizedBox(width: 6),
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                      decoration: BoxDecoration(
                                        color: color.withOpacity(0.2),
                                        borderRadius: BorderRadius.circular(6),
                                      ),
                                      child: Text(
                                        badge,
                                        style: TextStyle(color: color, fontSize: 10, fontWeight: FontWeight.bold),
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  '\$${price.toStringAsFixed(2)} / $period',
                                  style: TextStyle(
                                    fontWeight: FontWeight.w900,
                                    fontSize: 16,
                                    color: Colors.green.shade700,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          ElevatedButton(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: color,
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                            ),
                            onPressed: _isSubscribing ? null : () => _handleSubscribe(plan),
                            child: const Text(
                              'Subscribe',
                              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                }).toList(),
              ),

              const SizedBox(height: 10),
              Text(
                '* Note: Banner & task completion rewarded video ads remain active to support task payouts.',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 10.5, color: theme.colorScheme.onSurfaceVariant),
              ),
              const SizedBox(height: 14),

              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Continue with Pop-up Ads'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
