import 'dart:async';
import 'package:flutter/material.dart';
import 'package:in_app_purchase/in_app_purchase.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../services/backend_service.dart';
import '../services/micro_job_service.dart';

class LevelUpgradesScreen extends StatefulWidget {
  const LevelUpgradesScreen({super.key});

  @override
  State<LevelUpgradesScreen> createState() => _LevelUpgradesScreenState();
}

class _LevelUpgradesScreenState extends State<LevelUpgradesScreen> {
  int _currentLevel = 1;
  DateTime? _signUpDate;
  bool _isLoading = true;
  bool _isProcessing = false;
  Timer? _countdownTimer;
  Duration _remainingBonusTime = Duration.zero;
  bool _isEligibleForBonus = false;

  final InAppPurchase _inAppPurchase = InAppPurchase.instance;
  late StreamSubscription<List<PurchaseDetails>> _subscription;
  List<ProductDetails> _products = [];
  bool _billingAvailable = true;   // false if Play Billing unavailable
  bool _productsLoaded = false;     // true once queryProductDetails completes

  @override
  void initState() {
    super.initState();
    BackendService.adminModeOverride.addListener(_loadUserLevelAndDate);
    _loadUserLevelAndDate();
    
    final Stream<List<PurchaseDetails>> purchaseUpdated = _inAppPurchase.purchaseStream;
    _subscription = purchaseUpdated.listen((purchaseDetailsList) {
      _listenToPurchaseUpdated(purchaseDetailsList);
    }, onDone: () {
      _subscription.cancel();
    }, onError: (error) {
      debugPrint("Purchase stream error: $error");
    });
    _loadProducts();
  }

  Future<void> _loadUserLevelAndDate() async {
    try {
      final user = Supabase.instance.client.auth.currentUser;
      if (user == null) return;

      // 1. Fetch user level and profile creation date from Supabase profiles
      final profileRes = await Supabase.instance.client
          .from('profiles')
          .select('user_level, created_at, is_admin')
          .eq('id', user.id)
          .maybeSingle();

      if (profileRes != null) {
        final isAdmin = profileRes['is_admin'] == true && BackendService.adminModeOverride.value;
        final level = isAdmin ? 4 : (profileRes['user_level'] as int? ?? 1);
        final createdAtStr = profileRes['created_at'] as String?;
        final createdAt = createdAtStr != null ? DateTime.parse(createdAtStr) : DateTime.now();

        setState(() {
          _currentLevel = level;
          _signUpDate = createdAt;
        });

        _checkBonusEligibility(createdAt);
      }
    } catch (e) {
      debugPrint('Error loading level upgrades: $e');
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  void _checkBonusEligibility(DateTime signUpDate) {
    final expiryDate = signUpDate.add(const Duration(days: 10));
    final now = DateTime.now();

    if (now.isBefore(expiryDate)) {
      _isEligibleForBonus = true;
      _remainingBonusTime = expiryDate.difference(now);

      _countdownTimer?.cancel();
      _countdownTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
        if (!mounted) return;
        final diff = expiryDate.difference(DateTime.now());
        if (diff.isNegative) {
          setState(() {
            _isEligibleForBonus = false;
            _remainingBonusTime = Duration.zero;
          });
          _countdownTimer?.cancel();
        } else {
          setState(() {
            _remainingBonusTime = diff;
          });
        }
      });
    } else {
      _isEligibleForBonus = false;
    }
  }

  void _showBonusInfoDialog() {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          backgroundColor: isDark ? Colors.grey.shade900 : Colors.white,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: Row(
            children: [
              Icon(
                Icons.stars,
                color: isDark ? theme.colorScheme.primary : Colors.pink.shade600,
                size: 28,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  '50% Signup Cashback',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: isDark ? Colors.white : Colors.pink.shade800,
                  ),
                ),
              ),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Get half of your upgrade cost credited back instantly!',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 14,
                  color: isDark ? Colors.white70 : Colors.purple.shade900,
                ),
              ),
              const SizedBox(height: 12),
              Text(
                'This promotional deal is active for the first 10 days after you register on XapZap.',
                style: TextStyle(
                  fontSize: 13,
                  height: 1.4,
                  color: isDark ? Colors.white60 : Colors.grey.shade800,
                ),
              ),
              const SizedBox(height: 12),
              Text(
                '• Instant Cashout: The 50% cashback is calculated from the price tier of your upgrade and is immediately added to your Available Balance.\n'
                '• High-Paying Tasks: Unlocks high-rate review jobs (Bronze: up to \$0.30/rev, Silver: up to \$0.60/rev, Gold: up to \$1.00/rev!).\n'
                '• Real Utility: Use your bonus balance immediately to launch reviews, fund campaigns, or cash out via payout settings.\n'
                '• All Tiers Covered: Valid for any level upgrade (Bronze, Silver, or Gold) made within your signup countdown window.',
                style: TextStyle(
                  fontSize: 12,
                  height: 1.5,
                  color: isDark ? Colors.white54 : Colors.grey.shade700,
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              style: TextButton.styleFrom(
                foregroundColor: isDark ? theme.colorScheme.primary : Colors.pink.shade700,
              ),
              onPressed: () => Navigator.pop(context),
              child: const Text('Got it!', style: TextStyle(fontWeight: FontWeight.bold)),
            ),
          ],
        );
      },
    );
  }

  String _formatDuration(Duration d) {
    final days = d.inDays;
    final hours = d.inHours % 24;
    final minutes = d.inMinutes % 60;
    final seconds = d.inSeconds % 60;
    return '${days}d ${hours}h ${minutes}m ${seconds}s';
  }

  Future<void> _loadProducts() async {
    try {
      final bool available = await _inAppPurchase.isAvailable();
      if (!available) {
        debugPrint("[IAP] Play Billing not available on this device.");
        if (mounted) setState(() { _billingAvailable = false; _productsLoaded = true; });
        return;
      }
      const Set<String> kIds = <String>{'xapzap_level_2', 'xapzap_level_3', 'xapzap_level_4'};
      final ProductDetailsResponse response = await _inAppPurchase.queryProductDetails(kIds);
      if (response.notFoundIDs.isNotEmpty) {
        debugPrint("[IAP] Products not found in Play Console: ${response.notFoundIDs}");
      }
      debugPrint("[IAP] Loaded ${response.productDetails.length} products: "
          "${response.productDetails.map((p) => p.id).toList()}");
      if (mounted) {
        setState(() {
          _products = response.productDetails;
          _billingAvailable = true;
          _productsLoaded = true;
        });
      }
    } catch (e) {
      debugPrint("[IAP] Error fetching products: $e");
      if (mounted) setState(() { _productsLoaded = true; });
    }
  }

  void _listenToPurchaseUpdated(List<PurchaseDetails> purchaseDetailsList) async {
    for (var purchaseDetails in purchaseDetailsList) {
      if (purchaseDetails.status == PurchaseStatus.pending) {
        setState(() {
          _isProcessing = true;
        });
      } else {
        if (purchaseDetails.status == PurchaseStatus.error) {
          debugPrint("Purchase error: ${purchaseDetails.error}");
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text('Payment failed: ${purchaseDetails.error?.message ?? "Unknown error"}'),
                backgroundColor: Colors.red,
              ),
            );
          }
        } else if (purchaseDetails.status == PurchaseStatus.purchased ||
            purchaseDetails.status == PurchaseStatus.restored) {
          final String prodId = purchaseDetails.productID;
          int level = 1;
          double cost = 0.0;
          if (prodId == 'xapzap_level_2') {
            level = 2;
            cost = 6.00;
          } else if (prodId == 'xapzap_level_3') {
            level = 3;
            cost = 25.00;
          } else if (prodId == 'xapzap_level_4') {
            level = 4;
            cost = 50.00;
          }

          if (level > 1) {
            final success = await _updateLevelInDatabase(
              level,
              cost,
              purchaseDetails.purchaseID ?? purchaseDetails.transactionDate ?? 'google_play',
            );
            if (success) {
              if (mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text('Account upgraded to Level $level successfully!${_isEligibleForBonus ? " 50% Signup Bonus credited!" : ""}'),
                    backgroundColor: Colors.green,
                  ),
                );
                Navigator.pop(context, true);
              }
            }
          }
        }
        if (purchaseDetails.pendingCompletePurchase) {
          await _inAppPurchase.completePurchase(purchaseDetails);
        }
        setState(() {
          _isProcessing = false;
        });
      }
    }
  }

  Future<void> _processUpgrade(int targetLevel, double cost) async {
    if (_isProcessing) return;

    // Guard: billing service unavailable (e.g. no Google Play on device)
    if (!_billingAvailable) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Google Play Billing is not available on this device.'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    final String prodId = 'xapzap_level_$targetLevel';

    // Guard: products haven't loaded yet — retry
    if (!_productsLoaded) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Store products are still loading. Please try again in a moment.'),
          backgroundColor: Colors.amber,
        ),
      );
      _loadProducts(); // retry
      return;
    }

    // Find the matching product from Play Store
    ProductDetails? product;
    for (final p in _products) {
      if (p.id == prodId) {
        product = p;
        break;
      }
    }

    // Guard: product not found in Play Console
    if (product == null) {
      debugPrint('[IAP] Product $prodId not found in loaded products: '
          '${_products.map((p) => p.id).toList()}');
      if (mounted) {
        showDialog(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('Product Not Found'),
            content: const Text(
              'This upgrade product could not be loaded from the Play Store.\n\n'
              'Make sure:\n'
              '• You installed this app from the Play Store (not sideloaded)\n'
              '• Your device has Google Play Services\n'
              '• The products are Active in Play Console',
            ),
            actions: [
              TextButton(
                onPressed: () {
                  Navigator.pop(context);
                  _loadProducts(); // retry
                },
                child: const Text('Retry'),
              ),
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Close'),
              ),
            ],
          ),
        );
      }
      return;
    }

    // All good — launch Play Store billing sheet
    setState(() { _isProcessing = true; });

    try {
      final PurchaseParam purchaseParam = PurchaseParam(productDetails: product);
      await _inAppPurchase.buyNonConsumable(purchaseParam: purchaseParam);
      // _isProcessing will be set to false inside _listenToPurchaseUpdated
    } catch (e) {
      debugPrint('[IAP] Purchase trigger failed: $e');
      if (mounted) {
        setState(() { _isProcessing = false; });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Could not open payment sheet: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<bool> _updateLevelInDatabase(int newLevel, double cost, String txRef) async {
    final user = Supabase.instance.client.auth.currentUser;
    if (user == null) return false;

    try {
      // 1. Update level in profiles table
      await Supabase.instance.client
          .from('profiles')
          .update({'user_level': newLevel})
          .eq('id', user.id);

      // 2. Insert into level_upgrades log
      await Supabase.instance.client.from('level_upgrades').insert({
        'user_id': user.id,
        'from_level': _currentLevel,
        'to_level': newLevel,
        'amount_paid': cost,
        'payment_method': 'flutterwave',
        'reference_id': txRef,
        'status': 'completed',
      });

      // 3. Apply 50% cashback sign-up bonus if eligible
      if (_isEligibleForBonus) {
        final bonusAmount = cost * 0.50;
        final balanceRow = await BackendService.getLatestCreatorBalance(user.id);
        if (balanceRow != null) {
          final data = balanceRow.data as Map<String, dynamic>;
          final double currentBal = (data['balanceUsd'] ?? 0.0).toDouble();
          final double currentAvail = (data['availableBalanceUsd'] ?? 0.0).toDouble();

          await BackendService.updateRow(
            BackendService.creatorBalancesCollectionId,
            balanceRow.$id,
            {
              'balanceUsd': currentBal + bonusAmount,
              'availableBalanceUsd': currentAvail + bonusAmount,
            },
          );
        } else {
          await BackendService.createDocument(
            BackendService.creatorBalancesCollectionId,
            {
              'creatorId': user.id,
              'balanceUsd': bonusAmount,
              'availableBalanceUsd': bonusAmount,
            },
          );
        }
        await MicroJobService.reloadUserBalance();
      }

      return true;
    } catch (e) {
      debugPrint('Database level update failed: $e');
      return false;
    }
  }

  @override
  void dispose() {
    _countdownTimer?.cancel();
    _subscription.cancel();
    BackendService.adminModeOverride.removeListener(_loadUserLevelAndDate);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    final isDark = theme.brightness == Brightness.dark;
    final backgroundColor = isDark ? const Color(0xFF121212) : const Color(0xFFF9FAFC);

    if (_isLoading) {
      return Scaffold(
        backgroundColor: backgroundColor,
        appBar: AppBar(
          title: const Text('Upgrade Level'),
          backgroundColor: backgroundColor,
          elevation: 0,
        ),
        body: const Center(child: CircularProgressIndicator(color: Colors.pinkAccent)),
      );
    }

    return Scaffold(
      backgroundColor: backgroundColor,
      appBar: AppBar(
        title: const Text('Level Upgrades', style: TextStyle(fontWeight: FontWeight.bold)),
        backgroundColor: backgroundColor,
        elevation: 0,
      ),
      body: Stack(
        children: [
          ListView(
            padding: const EdgeInsets.all(16.0),
            children: [
              // Current Level Header Card
              Card(
                elevation: 4,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                child: Container(
                  width: double.infinity,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(16),
                    gradient: const LinearGradient(
                      colors: [Colors.deepPurple, Colors.pinkAccent],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                  ),
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    children: [
                      const Text(
                        'YOUR ACTIVE LEVEL',
                        style: TextStyle(color: Colors.white70, fontSize: 13, fontWeight: FontWeight.bold, letterSpacing: 1),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Level $_currentLevel',
                        style: const TextStyle(color: Colors.white, fontSize: 32, fontWeight: FontWeight.w900),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 20),

              // Countdown urgent bonus banner
              if (_isEligibleForBonus) ...[
                Container(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(16),
                    gradient: theme.brightness == Brightness.dark
                        ? LinearGradient(
                            colors: [
                              theme.colorScheme.primaryContainer.withOpacity(0.4),
                              theme.colorScheme.secondaryContainer.withOpacity(0.15),
                            ],
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                          )
                        : LinearGradient(
                            colors: [
                              Colors.pink.shade50.withOpacity(0.95),
                              Colors.purple.shade50.withOpacity(0.85),
                            ],
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                          ),
                    border: Border.all(
                      color: theme.brightness == Brightness.dark
                          ? theme.colorScheme.primary.withOpacity(0.5)
                          : Colors.pink.shade300,
                      width: 1.5,
                    ),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(16.0),
                    child: Column(
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(
                              Icons.stars,
                              color: theme.brightness == Brightness.dark
                                  ? theme.colorScheme.primary
                                  : Colors.pink.shade600,
                            ),
                            const SizedBox(width: 8),
                            Text(
                              'Special Double Payout Deal! 🔥',
                              style: TextStyle(
                                color: theme.brightness == Brightness.dark
                                    ? theme.colorScheme.primary
                                    : Colors.pink.shade700,
                                fontWeight: FontWeight.bold,
                                fontSize: 16,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'Upgrade within 10 days of signing up to get an immediate 50% cashback bonus added directly to your earnings balance!',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: theme.brightness == Brightness.dark
                                ? theme.colorScheme.onSurface
                                : Colors.purple.shade900,
                            fontSize: 13,
                            height: 1.4,
                          ),
                        ),
                        const SizedBox(height: 12),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                              decoration: BoxDecoration(
                                color: theme.brightness == Brightness.dark
                                    ? theme.colorScheme.onSurface.withOpacity(0.1)
                                    : Colors.pink.shade100.withOpacity(0.6),
                                borderRadius: BorderRadius.circular(20),
                              ),
                              child: Text(
                                'Expires in: ${_formatDuration(_remainingBonusTime)}',
                                style: TextStyle(
                                  color: theme.brightness == Brightness.dark
                                      ? theme.colorScheme.primary
                                      : Colors.pink.shade700,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 13,
                                ),
                              ),
                            ),
                            const SizedBox(width: 12),
                            TextButton.icon(
                              style: TextButton.styleFrom(
                                foregroundColor: theme.brightness == Brightness.dark
                                    ? theme.colorScheme.primary
                                    : Colors.pink.shade700,
                                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                              ),
                              onPressed: _showBonusInfoDialog,
                              icon: const Icon(Icons.help_outline, size: 16),
                              label: const Text(
                                'Learn More',
                                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 20),
              ],

              Text(
                'Available Levels',
                style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 12),

              _buildLevelCard(
                level: 2,
                title: 'Bronze Level 2',
                cost: 6.00,
                watchRate: '\$0.07 - \$0.15',
                reviewRate: '\$0.10 - \$0.30',
                unlockedReviews: 'Short Reviews (0 to 10 mins)',
                color: const Color(0xFFCD7F32), // Rich Copper Bronze
              ),
              _buildLevelCard(
                level: 3,
                title: 'Silver Level 3',
                cost: 25.00,
                watchRate: '\$0.16 - \$0.30',
                reviewRate: '\$0.30 - \$0.60',
                unlockedReviews: 'Medium Reviews (10 to 30 mins)',
                color: const Color(0xFFA6B4C9), // Shiny Platinum Silver
              ),
              _buildLevelCard(
                level: 4,
                title: 'Gold Level 4',
                cost: 50.00,
                watchRate: '\$0.18 - \$0.35',
                reviewRate: '\$0.60 - \$1.00',
                unlockedReviews: 'Premium Reviews (31+ mins)',
                color: const Color(0xFFD4AF37), // Elegant Gold
              ),
            ],
          ),
          if (_isProcessing)
            Container(
              color: Colors.black54,
              child: const Center(
                child: CircularProgressIndicator(color: Colors.pinkAccent),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildLevelCard({
    required int level,
    required String title,
    required double cost,
    required String watchRate,
    required String reviewRate,
    required String unlockedReviews,
    required Color color,
  }) {
    final isCurrent = _currentLevel == level;
    final canUpgrade = _currentLevel < level;
    final theme = Theme.of(context);

    return Card(
      margin: const EdgeInsets.only(bottom: 16),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: isCurrent ? BorderSide(color: color, width: 2) : BorderSide.none,
      ),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    CircleAvatar(
                      backgroundColor: color,
                      radius: 16,
                      child: Text(
                        level.toString(),
                        style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Text(
                      title,
                      style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18, color: theme.colorScheme.onSurface),
                    ),
                  ],
                ),
                if (isCurrent)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: color.withOpacity(0.2),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      'ACTIVE',
                      style: TextStyle(color: color, fontWeight: FontWeight.bold, fontSize: 11),
                    ),
                  ),
              ],
            ),
            const Divider(height: 24),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('One-time Price:', style: TextStyle(color: theme.colorScheme.onSurfaceVariant, fontWeight: FontWeight.w500)),
                Text(
                  '\$${cost.toStringAsFixed(2)}',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: theme.colorScheme.onSurface),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('Video Watch Rate:', style: TextStyle(color: theme.colorScheme.onSurfaceVariant, fontWeight: FontWeight.w500)),
                Text(watchRate, style: TextStyle(fontWeight: FontWeight.bold, color: theme.colorScheme.onSurface)),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('Video Review Rate:', style: TextStyle(color: theme.colorScheme.onSurfaceVariant, fontWeight: FontWeight.w500)),
                Text(reviewRate, style: TextStyle(fontWeight: FontWeight.bold, color: theme.colorScheme.onSurface)),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('Review Durations:', style: TextStyle(color: theme.colorScheme.onSurfaceVariant, fontWeight: FontWeight.w500)),
                Text(unlockedReviews, style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: theme.colorScheme.onSurface)),
              ],
            ),
            const SizedBox(height: 16),
            if (canUpgrade)
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: color,
                  foregroundColor: Colors.white,
                  minimumSize: const Size(double.infinity, 44),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
                onPressed: _isProcessing ? null : () => _processUpgrade(level, cost),
                child: Text('Upgrade to Level $level (\$${cost.toStringAsFixed(0)})', style: const TextStyle(fontWeight: FontWeight.bold)),
              )
            else if (!isCurrent)
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: theme.colorScheme.onSurface.withOpacity(0.12),
                  foregroundColor: theme.colorScheme.onSurface.withOpacity(0.38),
                  minimumSize: const Size(double.infinity, 44),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
                onPressed: null,
                child: const Text('Already Passed This Level'),
              ),
          ],
        ),
      ),
    );
  }
}
