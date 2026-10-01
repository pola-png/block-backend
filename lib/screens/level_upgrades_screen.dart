import 'dart:async';
import 'package:flutter/material.dart';
import 'package:in_app_purchase/in_app_purchase.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../services/backend_service.dart';
import '../services/micro_job_service.dart';
import '../widgets/animated_balance_text.dart';

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

  bool _isAdFree = false;
  String _adFreePlanName = '';
  DateTime? _adFreeExpiryDate;
  Duration _remainingAdFreeTime = Duration.zero;
  Timer? _adFreeTimer;

  final List<Map<String, dynamic>> _adFreePlans = [
    {
      'title': '1 Week Ad-Free Pass',
      'price': 1.60,
      'durationDays': 7,
      'period': '7 Days',
      'badge': 'POPULAR',
      'badgeColor': Colors.blue,
      'gradient': const [Color(0xFF1E88E5), Color(0xFF42A5F5)],
      'icon': Icons.bolt,
    },
    {
      'title': '1 Month Ad-Free Pass',
      'price': 4.90,
      'durationDays': 30,
      'period': '30 Days',
      'badge': 'BEST VALUE (SAVE 35%)',
      'badgeColor': Colors.amber,
      'gradient': const [Color(0xFFFF8F00), Color(0xFFFFB300)],
      'icon': Icons.stars_rounded,
    },
  ];

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
    _loadAdFreeStatus();
    
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

  Future<void> _loadAdFreeStatus() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      int expiry = prefs.getInt('ad_free_expiry_timestamp') ?? 0;
      String planName = prefs.getString('ad_free_active_plan') ?? 'Ad-Free Pass';
      final now = DateTime.now().millisecondsSinceEpoch;

      // Authoritative verification against Supabase user profile if local cache expired or empty
      if (expiry <= now) {
        final user = Supabase.instance.client.auth.currentUser;
        if (user != null) {
          final profileRes = await Supabase.instance.client
              .from('profiles')
              .select('ad_free_expiry')
              .eq('id', user.id)
              .maybeSingle();

          if (profileRes != null && profileRes['ad_free_expiry'] != null) {
            final dbExpiryStr = profileRes['ad_free_expiry'] as String;
            final dbExpiryDt = DateTime.tryParse(dbExpiryStr);
            if (dbExpiryDt != null && dbExpiryDt.millisecondsSinceEpoch > now) {
              expiry = dbExpiryDt.millisecondsSinceEpoch;
              await prefs.setInt('ad_free_expiry_timestamp', expiry);
            }
          }
        }
      }

      if (expiry > now) {
        final expiryDt = DateTime.fromMillisecondsSinceEpoch(expiry);
        _adFreeTimer?.cancel();
        _adFreeTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
          if (!mounted) return;
          final diff = expiryDt.difference(DateTime.now());
          if (diff.isNegative) {
            setState(() {
              _isAdFree = false;
              _adFreeExpiryDate = null;
              _remainingAdFreeTime = Duration.zero;
            });
            _adFreeTimer?.cancel();
          } else {
            setState(() {
              _remainingAdFreeTime = diff;
            });
          }
        });

        if (mounted) {
          setState(() {
            _isAdFree = true;
            _adFreePlanName = planName;
            _adFreeExpiryDate = expiryDt;
            _remainingAdFreeTime = expiryDt.difference(DateTime.now());
          });
        }
      } else {
        if (mounted) {
          setState(() {
            _isAdFree = false;
            _adFreeExpiryDate = null;
            _remainingAdFreeTime = Duration.zero;
          });
        }
      }
    } catch (e) {
      debugPrint('Error loading ad-free status: $e');
    }
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
      const Set<String> kIds = <String>{
        'xapzap_level_2',
        'xapzap_level_3',
        'xapzap_level_4',
        'ad_free_1week',
        'ad_free_1month',
      };
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
          } else if (prodId == 'ad_free_1week') {
            await MicroJobService.subscribeAdFreeViaPlayStore('1 Week Ad-Free Pass', 1.60, 7);
            await _loadAdFreeStatus();
            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('1 Week Ad-Free Pass activated! ⚡'),
                  backgroundColor: Colors.green,
                ),
              );
            }
          } else if (prodId == 'ad_free_1month') {
            await MicroJobService.subscribeAdFreeViaPlayStore('1 Month Ad-Free Pass', 4.90, 30);
            await _loadAdFreeStatus();
            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('1 Month Ad-Free Pass activated! ⚡'),
                  backgroundColor: Colors.green,
                ),
              );
            }
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

    final String prodId = 'xapzap_level_$targetLevel';

    final bool available = await _inAppPurchase.isAvailable();
    if (!available) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Payment service is currently unavailable.'),
            backgroundColor: Colors.red,
          ),
        );
      }
      return;
    }

    setState(() { _isProcessing = true; });

    try {
      ProductDetails? product;
      for (final p in _products) {
        if (p.id == prodId) {
          product = p;
          break;
        }
      }

      if (product == null) {
        final response = await _inAppPurchase.queryProductDetails({prodId});
        if (response.productDetails.isNotEmpty) {
          product = response.productDetails.first;
          _products.add(product);
        }
      }

      if (product != null) {
        final PurchaseParam purchaseParam = PurchaseParam(productDetails: product);
        await _inAppPurchase.buyNonConsumable(purchaseParam: purchaseParam);
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Upgrade plan is currently unavailable. Please try again shortly.'),
              backgroundColor: Colors.orange,
            ),
          );
        }
      }
    } catch (e) {
      debugPrint('[IAP] Purchase trigger failed: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Could not open payment window: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() { _isProcessing = false; });
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
        'payment_method': 'google_play',
        'reference_id': txRef,
        'status': 'completed',
      });

      // 3. Apply 50% cashback sign-up bonus if eligible
      if (_isEligibleForBonus) {
        final bonusAmount = cost * 0.50;
        final balanceRow = await BackendService.getLatestCreatorBalance(user.id);
        if (balanceRow != null) {
          final data = balanceRow.data as Map<String, dynamic>;
          final double currentBal = double.tryParse((data['available_balance_usd'] ?? data['balance_usd'] ?? data['availableBalanceUsd'] ?? data['balanceUsd'] ?? 0.0).toString()) ?? 0.0;
          final double currentAvail = double.tryParse((data['available_balance_usd'] ?? data['availableBalanceUsd'] ?? currentBal).toString()) ?? currentBal;

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

  Future<void> _processAdFreePlayStorePurchase(String prodId) async {
    if (_isProcessing) return;

    final bool available = await _inAppPurchase.isAvailable();
    if (!available) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Payment service is currently unavailable.'),
            backgroundColor: Colors.red,
          ),
        );
      }
      return;
    }

    setState(() { _isProcessing = true; });

    try {
      ProductDetails? product;
      for (final p in _products) {
        if (p.id == prodId) {
          product = p;
          break;
        }
      }

      if (product == null) {
        final response = await _inAppPurchase.queryProductDetails({prodId});
        if (response.productDetails.isNotEmpty) {
          product = response.productDetails.first;
          _products.add(product);
        }
      }

      if (product != null) {
        final PurchaseParam purchaseParam = PurchaseParam(productDetails: product);
        await _inAppPurchase.buyNonConsumable(purchaseParam: purchaseParam);
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Ad-Free Pass is currently unavailable. Please try again in a moment.'),
              backgroundColor: Colors.orange,
            ),
          );
        }
      }
    } catch (e) {
      debugPrint('[IAP] Ad-Free purchase error: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Could not open payment window: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() { _isProcessing = false; });
      }
    }
  }

  @override
  void dispose() {
    _countdownTimer?.cancel();
    _adFreeTimer?.cancel();
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
          title: const Text('Upgrades & Subscriptions'),
          backgroundColor: backgroundColor,
          elevation: 0,
        ),
        body: const Center(child: CircularProgressIndicator(color: Colors.pinkAccent)),
      );
    }

    return DefaultTabController(
      length: 2,
      child: Scaffold(
        backgroundColor: backgroundColor,
        appBar: AppBar(
          title: const Text('Upgrades & Passes', style: TextStyle(fontWeight: FontWeight.bold)),
          backgroundColor: backgroundColor,
          elevation: 0,
          bottom: TabBar(
            indicatorColor: Colors.pinkAccent,
            labelColor: theme.colorScheme.primary,
            unselectedLabelColor: isDark ? Colors.white60 : Colors.black54,
            labelStyle: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
            tabs: const [
              Tab(
                icon: Icon(Icons.stars, size: 20),
                text: 'Level Upgrades',
              ),
              Tab(
                icon: Icon(Icons.block_flipped, size: 20),
                text: 'Ad-Free Passes ⚡',
              ),
            ],
          ),
        ),
        body: Stack(
          children: [
            TabBarView(
              children: [
                _buildLevelUpgradesTab(theme, isDark),
                _buildAdFreeTab(theme, isDark),
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
      ),
    );
  }

  Widget _buildLevelUpgradesTab(ThemeData theme, bool isDark) {
    return ListView(
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
    );
  }

  Widget _buildAdFreeTab(ThemeData theme, bool isDark) {
    final cardBg = isDark ? const Color(0xFF1E1E1E) : Colors.white;

    return ListView(
      padding: const EdgeInsets.all(16.0),
      children: [
        // Balance & Active Status Header Card
        Card(
          elevation: 4,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          child: Container(
            width: double.infinity,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(16),
              gradient: LinearGradient(
                colors: isDark
                    ? [const Color(0xFF1F2937), const Color(0xFF111827)]
                    : [const Color(0xFF0F172A), const Color(0xFF1E293B)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
            ),
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Expanded(
                      child: Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(8),
                            decoration: BoxDecoration(
                              color: Colors.amber.withOpacity(0.2),
                              shape: BoxShape.circle,
                            ),
                            child: const Icon(Icons.block_flipped, color: Colors.amber, size: 24),
                          ),
                          const SizedBox(width: 10),
                          const Expanded(
                            child: Text(
                              'Ad-Free Center',
                              style: TextStyle(color: Colors.white, fontSize: 17, fontWeight: FontWeight.bold),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    ValueListenableBuilder<double>(
                      valueListenable: MicroJobService.userBalanceNotifier,
                      builder: (context, balance, _) {
                        return Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                          decoration: BoxDecoration(
                            color: const Color(0xFF4ADE80).withOpacity(0.15),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: const Color(0xFF4ADE80).withOpacity(0.4)),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(Icons.account_balance_wallet, color: Color(0xFF4ADE80), size: 14),
                              const SizedBox(width: 4),
                              ReactiveAnimatedBalance(
                                decimalDigits: 5,
                                style: const TextStyle(
                                  color: Color(0xFF4ADE80),
                                  fontWeight: FontWeight.bold,
                                  fontSize: 12,
                                ),
                              ),
                            ],
                          ),
                        );
                      },
                    ),
                  ],
                ),
                const SizedBox(height: 16),

                // Active Banner or Standard Banner
                if (_isAdFree) ...[
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: Colors.green.withOpacity(0.15),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: Colors.greenAccent.withOpacity(0.4)),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            const Icon(Icons.verified, color: Colors.greenAccent, size: 20),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                'ACTIVE PASS: $_adFreePlanName ⚡',
                                style: const TextStyle(
                                  color: Colors.greenAccent,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 13,
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 6),
                        Text(
                          'Time Remaining: ${_formatDuration(_remainingAdFreeTime)}',
                          style: const TextStyle(color: Colors.white70, fontWeight: FontWeight.w600, fontSize: 12),
                        ),
                        const SizedBox(height: 4),
                        const Text(
                          'Interrupting pop-up ads are currently stopped on your account while keeping 100% of task rewards!',
                          style: TextStyle(color: Colors.white60, fontSize: 11, height: 1.3),
                        ),
                      ],
                    ),
                  ),
                ] else ...[
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: Colors.amber.withOpacity(0.12),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: Colors.amber.withOpacity(0.3)),
                    ),
                    child: const Row(
                      children: [
                        Icon(Icons.info_outline, color: Colors.amber, size: 20),
                        SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            'Activate an Ad-Free Pass to disable all pop-up ads while keeping full task earnings active!',
                            style: TextStyle(color: Colors.white70, fontSize: 12, height: 1.3),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
        const SizedBox(height: 20),

        // Benefits Card
        Card(
          elevation: 2,
          color: cardBg,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          child: Padding(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Ad-Free Pass Benefits',
                  style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 12),
                _buildBenefitItem(
                  icon: Icons.shield_outlined,
                  color: Colors.amber,
                  title: 'Zero Interrupting Pop-up Ads',
                  subtitle: 'No forced app-open or interstitial full-screen popups while navigating.',
                ),
                const SizedBox(height: 10),
                _buildBenefitItem(
                  icon: Icons.monetization_on_outlined,
                  color: Colors.green,
                  title: '100% Task & Video Rewards Active',
                  subtitle: 'All micro jobs, AI training tasks, and video rewards remain fully payable.',
                ),
                const SizedBox(height: 10),
                _buildBenefitItem(
                  icon: Icons.bolt_outlined,
                  color: Colors.blue,
                  title: 'Instant Pass Activation',
                  subtitle: 'Your ad-free status activates immediately upon subscription.',
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 20),

        Text(
          'Select Ad-Free Pass',
          style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 12),

        for (final plan in _adFreePlans) _buildAdFreePlanCard(plan, theme, isDark, cardBg),
      ],
    );
  }

  Widget _buildBenefitItem({
    required IconData icon,
    required Color color,
    required String title,
    required String subtitle,
  }) {
    return Row(
      children: [
        Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: color.withOpacity(0.12),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(icon, color: color, size: 20),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
              const SizedBox(height: 2),
              Text(subtitle, style: const TextStyle(color: Colors.grey, fontSize: 11)),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildAdFreePlanCard(
    Map<String, dynamic> plan,
    ThemeData theme,
    bool isDark,
    Color cardBg,
  ) {
    final double price = (plan['price'] as num).toDouble();
    final String title = plan['title'] as String;
    final int durationDays = plan['durationDays'] as int;
    final String badge = plan['badge'] as String;
    final Color badgeColor = plan['badgeColor'] as Color;
    final List<Color> gradient = plan['gradient'] as List<Color>;
    final IconData icon = plan['icon'] as IconData;
    final String playProductId = durationDays == 7 ? 'ad_free_1week' : 'ad_free_1month';

    return Card(
      margin: const EdgeInsets.only(bottom: 16),
      elevation: 3,
      color: cardBg,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: badgeColor.withOpacity(0.4), width: 1.5),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          gradient: LinearGradient(colors: gradient),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Icon(icon, color: Colors.white, size: 20),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          title,
                          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: theme.colorScheme.onSurface),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: badgeColor.withOpacity(0.15),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: badgeColor.withOpacity(0.5)),
                  ),
                  child: Text(
                    badge,
                    style: TextStyle(color: badgeColor, fontWeight: FontWeight.bold, fontSize: 10),
                  ),
                ),
              ],
            ),
            const Divider(height: 24),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('Duration:', style: TextStyle(color: theme.colorScheme.onSurfaceVariant, fontWeight: FontWeight.w500)),
                Text('$durationDays Days Pass', style: TextStyle(fontWeight: FontWeight.bold, color: theme.colorScheme.onSurface)),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('Price:', style: TextStyle(color: theme.colorScheme.onSurfaceVariant, fontWeight: FontWeight.w500)),
                Text(
                  '\$${price.toStringAsFixed(2)}',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900, color: badgeColor),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('Pop-up Ads:', style: TextStyle(color: theme.colorScheme.onSurfaceVariant, fontWeight: FontWeight.w500)),
                const Text('DISABLED 🛑', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.green, fontSize: 12)),
              ],
            ),
            const SizedBox(height: 16),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: badgeColor,
                foregroundColor: Colors.white,
                minimumSize: const Size(double.infinity, 44),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                elevation: 2,
              ),
              onPressed: _isProcessing ? null : () => _processAdFreePlayStorePurchase(playProductId),
              child: Text(
                'Subscribe (\$${price.toStringAsFixed(2)})',
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
            ),
          ],
        ),
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
