import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart' as sb;
import '../models/post.dart';
import '../services/micro_job_service.dart';
import '../services/app_review_service.dart';
import '../services/backend_service.dart';
import '../services/ad_helper.dart';
import '../services/ad_gate_service.dart';
import '../screens/job_video_player_screen.dart';
import 'home_feed_ad_widgets.dart';

// New screen imports
import '../screens/withdrawal_settings_screen.dart';
import '../screens/level_upgrades_screen.dart';
import '../screens/submit_video_campaign_screen.dart';
import '../screens/video_review_screen.dart';
import '../screens/monetization_screen.dart';
import '../screens/visit_website_gateway_screen.dart';
import '../screens/perform_tasks_screen.dart';

class MicroJobsView extends StatefulWidget {
  const MicroJobsView({super.key});

  @override
  State<MicroJobsView> createState() => _MicroJobsViewState();
}

class _MicroJobsViewState extends State<MicroJobsView> {
  bool _appReviewCompleted = false;
  List<Post> _adminVideos = [];
  List<Map<String, dynamic>> _advertiserCampaigns = [];
  bool _isLoadingJobs = true;
  final Map<String, bool> _completedVideoMap = {};
  final Map<String, bool> _completedCampaignMap = {};

  List<String> _websiteTasksUrls = [];
  final Map<String, bool> _completedWebsiteTasksMap = {};
  final Map<String, bool> _websiteTasksVisibilityMap = {};
  final Map<String, bool> _websiteTasksDirectMap = {};

  static const List<String> _defaultWebsiteUrls = [];
  
  int _userLevel = 1;
  bool _isAdmin = false;
  DateTime? _signUpDate;
  bool _isEligibleForBonus = false;
  Duration _remainingBonusTime = Duration.zero;
  Timer? _bonusCountdownTimer;
  bool _hasShownBonusPopup = false;

  Timer? _interstitialTimer;
  BannerAd? _topBannerAd;
  BannerAd? _bottomBannerAd;
  bool _isTopBannerLoaded = false;
  bool _isBottomBannerLoaded = false;
  int _cooldownSeconds = 0;
  Timer? _cooldownTimer;
  final _urlInputController = TextEditingController();

  double _livePayouts = 132450.80;
  int _onlineMembers = 14204;
  List<_LiveActivity> _liveActivities = [];
  Timer? _tickerTimer;
  final _random = Random();

  @override
  void initState() {
    super.initState();
    _liveActivities = [
      _LiveActivity('User @joh*** completed task and earned \$0.030', 'just now'),
      _LiveActivity('User @mic*** completed Watch Video job', '1m ago'),
      _LiveActivity('User @ann*** withdrew \$10.00 successfully', '2m ago'),
    ];
    BackendService.adminModeOverride.addListener(_onAdminOverrideChanged);
    _loadStateAndJobs();
    _loadBannerAds();
    _showAppOpenAd();
    _startCooldownCountdown();
    
    MicroJobService.getTotalPayoutBase().then((val) {
      if (mounted) {
        setState(() {
          _livePayouts = val;
        });
      }
    });

    _interstitialTimer = Timer.periodic(const Duration(minutes: 2), (timer) {
      _showInterstitialAd();
    });

    _tickerTimer = Timer.periodic(const Duration(seconds: 4), (timer) {
      if (!mounted) return;
      final added = 0.05 + _random.nextDouble() * 0.70;
      final memberChange = _random.nextInt(7) - 3;
      final letters = 'abcdefghijklmnopqrstuvwxyz';
      final u1 = letters[_random.nextInt(26)];
      final u2 = letters[_random.nextInt(26)];
      final u3 = letters[_random.nextInt(26)];
      final username = '@$u1$u2$u3***';
      final events = [
        'completed task and earned \$0.030',
        'completed Watch Video job',
        'completed video watch and earned \$0.150',
        'withdrew \$5.00 successfully',
        'withdrew \$15.00 successfully',
        'upgraded to Bronze Level',
      ];
      final event = events[_random.nextInt(events.length)];
      setState(() {
        _livePayouts += added;
        _onlineMembers = (_onlineMembers + memberChange).clamp(13900, 14600);
        _liveActivities.insert(0, _LiveActivity('User $username $event', 'just now'));
        if (_liveActivities.length > 4) {
          _liveActivities.removeLast();
        }
      });
    });
  }

  void _startCooldownCountdown() async {
    _cooldownTimer?.cancel();
    final remaining = await MicroJobService.getCooldownSecondsRemaining();
    if (remaining > 0) {
      if (mounted) {
        setState(() {
          _cooldownSeconds = remaining;
        });
      }
      _cooldownTimer = Timer.periodic(const Duration(seconds: 1), (timer) async {
        if (!mounted) return;
        final seconds = await MicroJobService.getCooldownSecondsRemaining();
        setState(() {
          _cooldownSeconds = seconds;
        });
        if (seconds <= 0) {
          _cooldownTimer?.cancel();
        }
      });
    } else {
      if (mounted) {
        setState(() {
          _cooldownSeconds = 0;
        });
      }
    }
  }

  void _checkBonusEligibility(DateTime signUpDate) {
    final expiryDate = signUpDate.add(const Duration(days: 10));
    final now = DateTime.now();

    if (now.isBefore(expiryDate)) {
      setState(() {
        _isEligibleForBonus = true;
        _remainingBonusTime = expiryDate.difference(now);
      });

      if (!_hasShownBonusPopup) {
        _hasShownBonusPopup = true;
        Future.delayed(const Duration(milliseconds: 600), () {
          if (mounted) {
            _showAutomaticBonusPopup();
          }
        });
      }

      _bonusCountdownTimer?.cancel();
      _bonusCountdownTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
        if (!mounted) return;
        final diff = expiryDate.difference(DateTime.now());
        if (diff.isNegative) {
          setState(() {
            _isEligibleForBonus = false;
            _remainingBonusTime = Duration.zero;
          });
          _bonusCountdownTimer?.cancel();
        } else {
          setState(() {
            _remainingBonusTime = diff;
          });
        }
      });
    } else {
      setState(() {
        _isEligibleForBonus = false;
      });
    }
  }

  void _showAutomaticBonusPopup() {
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
                  '50% Upgrade Bonus Active! ⚡',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: isDark ? Colors.white : Colors.pink.shade800,
                    fontSize: 18,
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
                'Get half of your upgrade money back instantly!',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 14,
                  color: isDark ? Colors.white70 : Colors.purple.shade900,
                ),
              ),
              const SizedBox(height: 12),
              Text(
                'Your special new member deal is active! If you upgrade to Bronze, Silver, or Gold level within 10 days of registration, you will receive an immediate 50% cashback.',
                style: TextStyle(
                  fontSize: 13,
                  height: 1.4,
                  color: isDark ? Colors.white60 : Colors.grey.shade800,
                ),
              ),
              const SizedBox(height: 12),
              Text(
                '• Instant Payout: The 50% cashback is sent to your creator balance immediately after upgrade.\n'
                '• High-Paying Tasks: Unlocks high-rate review jobs (Bronze: up to \$0.30/rev, Silver: up to \$0.60/rev, Gold: up to \$1.00/rev!).\n'
                '• Double Value: Earn higher watch rates and recoup half of your investment right away!\n'
                '• Expires soon: Check the live countdown at the top of your screen.',
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

  void _loadBannerAds() {
    _topBannerAd = BannerAd(
      adUnitId: AdHelper.banner,
      size: AdSize.banner,
      request: AdHelper.financialRequest,
      listener: BannerAdListener(
        onAdLoaded: (_) => setState(() => _isTopBannerLoaded = true),
        onAdFailedToLoad: (ad, error) {
          ad.dispose();
          debugPrint('Top Banner failed to load: $error');
        },
      ),
    )..load();

    _bottomBannerAd = BannerAd(
      adUnitId: AdHelper.banner,
      size: AdSize.banner,
      request: AdHelper.financialRequest,
      listener: BannerAdListener(
        onAdLoaded: (_) => setState(() => _isBottomBannerLoaded = true),
        onAdFailedToLoad: (ad, error) {
          ad.dispose();
          debugPrint('Bottom Banner failed to load: $error');
        },
      ),
    )..load();
  }

  int _appOpenAdRetryCount = 0;

  void _showAppOpenAd() {
    debugPrint('[Jobs] Requesting App Open Ad...');
    AppOpenAd.load(
      adUnitId: AdHelper.appOpen,
      request: const AdRequest(),
      adLoadCallback: AppOpenAdLoadCallback(
        onAdLoaded: (ad) {
          _appOpenAdRetryCount = 0; // reset retry counter on success
          ad.fullScreenContentCallback = FullScreenContentCallback(
            onAdDismissedFullScreenContent: (ad) => ad.dispose(),
            onAdFailedToShowFullScreenContent: (ad, error) {
              ad.dispose();
              debugPrint('[Jobs] App Open Ad failed to show: $error. Falling back to Interstitial.');
              XapZapAdGateService.instance.showInterstitialAd(placement: 'jobs_screen_open_fallback');
            },
          );
          ad.show();
        },
        onAdFailedToLoad: (error) {
          debugPrint('[Jobs] App Open Ad failed to load: $error');
          if (_appOpenAdRetryCount < 2) {
            _appOpenAdRetryCount++;
            debugPrint('[Jobs] Retrying App Open Ad load (attempt $_appOpenAdRetryCount)...');
            Future.delayed(const Duration(seconds: 2), _showAppOpenAd);
          } else {
            debugPrint('[Jobs] App Open Ad load retries exhausted. Falling back to Interstitial.');
            XapZapAdGateService.instance.showInterstitialAd(placement: 'jobs_screen_open_fallback');
          }
        },
      ),
    );
  }

  void _showInterstitialAd() {
    InterstitialAd.load(
      adUnitId: AdHelper.interstitial,
      request: const AdRequest(),
      adLoadCallback: InterstitialAdLoadCallback(
        onAdLoaded: (ad) {
          ad.fullScreenContentCallback = FullScreenContentCallback(
            onAdDismissedFullScreenContent: (ad) => ad.dispose(),
            onAdFailedToShowFullScreenContent: (ad, error) => ad.dispose(),
          );
          ad.show();
        },
        onAdFailedToLoad: (error) => debugPrint('Failed to load interstitial: $error'),
      ),
    );
  }

  Future<void> _loadStateAndJobs() async {
    if (_adminVideos.isEmpty && _advertiserCampaigns.isEmpty) {
      setState(() {
        _isLoadingJobs = true;
      });
    }

    final user = await BackendService.getCurrentUser();
    if (user != null) {
      await MicroJobService.reloadUserBalance();
      
      // Fetch user level and registration date from profiles table
      final level = await MicroJobService.getUserLevel(user.$id);
      final profileRes = await sb.Supabase.instance.client
          .from('profiles')
          .select('created_at, username, is_admin')
          .eq('id', user.$id)
          .maybeSingle();

      DateTime? signUp;
      bool isAdmin = false;
      if (profileRes != null) {
        final createdStr = profileRes['created_at'] as String?;
        if (createdStr != null) {
          signUp = DateTime.parse(createdStr);
        }
        isAdmin = profileRes['is_admin'] == true && BackendService.adminModeOverride.value;
      }

      final isDone = await MicroJobService.isTaskCompleted('starter_app_review');
      if (mounted) {
        setState(() {
          _appReviewCompleted = isDone;
          _isAdmin = isAdmin;
          _userLevel = isAdmin ? 4 : level;
          if (signUp != null) {
            _signUpDate = signUp;
            _checkBonusEligibility(signUp);
          }
        });
      }

      // Check which standard watch videos have been completed by the user
      final videos = await MicroJobService.fetchAdminVideos();
      for (final video in videos) {
        final completed = await MicroJobService.isTaskCompleted('video_watch_${video.id}');
        _completedVideoMap[video.id] = completed;
      }

      // Fetch active advertiser video reviews
      final campaigns = await MicroJobService.fetchActiveCampaigns();
      for (final campaign in campaigns) {
        final comp = await MicroJobService.isCampaignReviewed(campaign['id'], user.$id);
        _completedCampaignMap[campaign['id']] = comp;
      }

      // LOAD WEBSITE TASKS
      List<String> loadedUrls = [];
      try {
        final prefs = await SharedPreferences.getInstance();
        final deletedDefaults = prefs.getStringList('deleted_default_urls') ?? [];
        for (final url in _defaultWebsiteUrls) {
          if (!deletedDefaults.contains(url)) {
            loadedUrls.add(url);
            _websiteTasksVisibilityMap[url] = prefs.getBool('visibility_$url') ?? true;
          }
        }
      } catch (_) {
        loadedUrls = List.from(_defaultWebsiteUrls);
      }

      try {
        final query = sb.Supabase.instance.client.from('website_tasks').select('url, is_visible, is_direct');
        final res = isAdmin ? await query : await query.eq('is_visible', true);
        if (res.isNotEmpty) {
          for (final row in res) {
            final url = row['url'] as String;
            final isVisible = row['is_visible'] == true;
            final isDirect = row['is_direct'] == true;
            if (!loadedUrls.contains(url)) {
              loadedUrls.add(url);
            }
            _websiteTasksVisibilityMap[url] = isVisible;
            _websiteTasksDirectMap[url] = isDirect;
          }
        }
      } catch (e) {
        debugPrint('Error loading website tasks from Supabase: $e');
      }

      try {
        final prefs = await SharedPreferences.getInstance();
        final localList = prefs.getStringList('local_website_tasks') ?? [];
        for (final url in localList) {
          if (!loadedUrls.contains(url)) {
            loadedUrls.add(url);
          }
          _websiteTasksVisibilityMap[url] = prefs.getBool('visibility_$url') ?? true;
          _websiteTasksDirectMap[url] = prefs.getBool('direct_$url') ?? false;
        }
      } catch (_) {}

      for (final url in loadedUrls) {
        final completed = await MicroJobService.isTaskCompleted('visit_website_${url.hashCode}');
        _completedWebsiteTasksMap[url] = completed;
      }
      
      if (mounted) {
        setState(() {
          _adminVideos = videos;
          _advertiserCampaigns = campaigns;
          _websiteTasksUrls = loadedUrls;
        });
      }
    }

    if (mounted) {
      setState(() {
        _isLoadingJobs = false;
      });
    }
  }



  Future<void> _completeAppReviewFlow() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Review XapZap'),
          content: const Text(
            'To support XapZap, please open the Play Store and leave a 5-star review. Once done, confirm here to receive your \$0.20 reward!',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: Theme.of(context).colorScheme.primary,
                foregroundColor: Theme.of(context).colorScheme.onPrimary,
              ),
              onPressed: () {
                AppReviewService.openStoreListing();
                Navigator.pop(context, true);
              },
              child: const Text('Go to Store & Complete'),
            ),
          ],
        );
      },
    );

    if (confirmed == true) {
      final success = await MicroJobService.rewardUser('starter_app_review', 0.20);
      if (success) {
        setState(() {
          _appReviewCompleted = true;
        });
        _startCooldownCountdown();
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Awesome! Reward of \$0.20 credited to your balance!'),
            backgroundColor: Colors.green,
          ),
        );
      }
    }
  }

  double _getRewardForPost(String postId) {
    // Standard watch jobs payout based on user level
    // Level 1: $0.02 - $0.06
    // Level 2: $0.07 - $0.15
    // Level 3: $0.16 - $0.30
    // Level 4: $0.18 - $0.35
    final mod = postId.hashCode.abs() % 5;
    
    double minRate = 0.02;
    double step = 0.01;
    
    if (_userLevel == 2) {
      minRate = 0.07;
      step = 0.02;
    } else if (_userLevel == 3) {
      minRate = 0.16;
      step = 0.035;
    } else if (_userLevel >= 4) {
      minRate = 0.18;
      step = 0.042;
    }
    
    return minRate + (mod * step);
  }

  double _getRewardForCampaign(Map<String, dynamic> campaign) {
    // Review payouts scale linearly with duration within the required campaign level tier
    // Bronze (Lvl 2, <=10 mins): $0.10 - $0.30
    // Silver (Lvl 3, 11-30 mins): $0.30 - $0.60
    // Gold (Lvl 4, >30 mins): $0.60 - $1.00
    final int duration = campaign['duration_minutes'] as int? ?? 1;

    int campaignLevel = 2;
    if (duration > 10 && duration <= 30) campaignLevel = 3;
    if (duration > 30) campaignLevel = 4;

    if (campaignLevel == 3) {
      // Silver: $0.30 to $0.60 (for 11 to 30 minutes)
      final d = duration.clamp(11, 30);
      return 0.30 + ((d - 11) / (30 - 11)) * (0.60 - 0.30);
    } else if (campaignLevel >= 4) {
      // Gold: $0.60 to $1.00 (for 31 to 60+ minutes)
      final d = duration.clamp(31, 60);
      return 0.60 + ((d - 31) / (60 - 31)) * (1.00 - 0.60);
    } else {
      // Bronze / Level 2: $0.10 to $0.30 (for 1 to 10 minutes)
      final d = duration.clamp(1, 10);
      return 0.10 + ((d - 1) / (10 - 1)) * (0.30 - 0.10);
    }
  }

  void _onAdminOverrideChanged() {
    if (mounted) {
      _loadStateAndJobs();
    }
  }

  @override
  void dispose() {
    BackendService.adminModeOverride.removeListener(_onAdminOverrideChanged);
    _interstitialTimer?.cancel();
    _cooldownTimer?.cancel();
    _tickerTimer?.cancel();
    _bonusCountdownTimer?.cancel();
    _topBannerAd?.dispose();
    _bottomBannerAd?.dispose();
    _urlInputController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final textTheme = theme.textTheme;
    final isDark = theme.brightness == Brightness.dark;
    final backgroundColor = isDark ? const Color(0xFF121212) : const Color(0xFFE2E8F0);
    final hasEarning = MicroJobService.userBalanceNotifier.value > 0;
    final isUnlocked = _appReviewCompleted || hasEarning;

    if (_isLoadingJobs) {
      return Container(
        color: backgroundColor,
        child: const Center(
          child: CircularProgressIndicator(color: Colors.pinkAccent),
        ),
      );
    }

    return Container(
      color: backgroundColor,
      child: Column(
        children: [
          Expanded(
            child: RefreshIndicator(
              onRefresh: _loadStateAndJobs,
              child: ListView(
                physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
        children: [
          Card(
            elevation: 2,
            color: isDark ? null : Colors.white,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
              side: BorderSide(color: isDark ? Colors.white10 : Colors.grey.shade200, width: 1),
            ),
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                children: [
                  InkWell(
                    onTap: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(builder: (context) => const MonetizationScreen()),
                      ).then((_) => _loadStateAndJobs());
                    },
                    borderRadius: BorderRadius.circular(8),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Row(
                            children: [
                              Icon(Icons.account_balance_wallet, color: theme.colorScheme.primary, size: 20),
                              const SizedBox(width: 8),
                              Text(
                                'Available Earnings',
                                style: TextStyle(
                                  color: theme.colorScheme.onSurface,
                                  fontSize: 14,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ],
                          ),
                          ValueListenableBuilder<double>(
                            valueListenable: MicroJobService.userBalanceNotifier,
                            builder: (context, balance, _) {
                              return Text(
                                '\$${balance.toStringAsFixed(3)}',
                                style: const TextStyle(
                                  color: Color(0xFF1B5E20), // Deep premium forest green
                                  fontSize: 26,
                                  fontWeight: FontWeight.w900,
                                  letterSpacing: -0.5,
                                ),
                              );
                            },
                          ),
                        ],
                      ),
                    ),
                  ),
                  if (_isEligibleForBonus) ...[
                    const SizedBox(height: 4),
                    Text(
                      '50% Upgrade Bonus: ${_formatDuration(_remainingBonusTime)}',
                      style: TextStyle(
                        color: Colors.orange.shade900,
                        fontWeight: FontWeight.w800,
                        fontSize: 12,
                      ),
                    ),
                  ],
                  const SizedBox(height: 12),
                  // Action buttons
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: [
                      _buildQuickAction(
                        icon: Icons.double_arrow_rounded,
                        label: 'Upgrade Level',
                        color: Colors.amber,
                        onTap: () async {
                          await XapZapAdGateService.instance.showInterstitialAd(placement: 'jobs_upgrade_level');
                          if (!mounted) return;
                          Navigator.push(
                            context,
                            MaterialPageRoute(builder: (context) => const LevelUpgradesScreen()),
                          ).then((_) => _loadStateAndJobs());
                        },
                      ),
                      _buildQuickAction(
                        icon: Icons.wallet,
                        label: 'Withdraw Settings',
                        color: theme.colorScheme.primary,
                        onTap: () async {
                          await XapZapAdGateService.instance.showInterstitialAd(placement: 'jobs_withdraw_settings');
                          if (!mounted) return;
                          Navigator.push(
                            context,
                            MaterialPageRoute(builder: (context) => const WithdrawalSettingsScreen()),
                          );
                        },
                      ),
                      _buildQuickAction(
                        icon: Icons.campaign_rounded,
                        label: 'Submit Jobs',
                        color: theme.colorScheme.primary,
                        onTap: () async {
                          await XapZapAdGateService.instance.showInterstitialAd(placement: 'jobs_submit_campaign');
                          if (!mounted) return;
                          Navigator.push(
                            context,
                            MaterialPageRoute(builder: (context) => const SubmitVideoCampaignScreen()),
                          );
                        },
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),

          // Locked Premium Tiers Preview (Urging Level Upgrades)
          _buildHighPayingTasksPreview(),
          const SizedBox(height: 16),

          // Top Banner Ad
          if (_isTopBannerLoaded && _topBannerAd != null) ...[
            Container(
              alignment: Alignment.center,
              width: _topBannerAd!.size.width.toDouble(),
              height: _topBannerAd!.size.height.toDouble(),
              margin: const EdgeInsets.only(bottom: 16),
              child: AdWidget(
                key: const Key('jobs_top_banner'),
                ad: _topBannerAd!,
              ),
            ),
          ],

          // Cooldown countdown banner
          if (_cooldownSeconds > 0) ...[
            Builder(
              builder: (context) {
                final isDark = Theme.of(context).brightness == Brightness.dark;
                final cardBgColor = isDark
                    ? Colors.amber.shade900.withOpacity(0.15)
                    : Theme.of(context).colorScheme.secondaryContainer.withOpacity(0.5);
                final cardBorderColor = isDark
                    ? Colors.amber.shade700
                    : Theme.of(context).colorScheme.secondary.withOpacity(0.2);
                final contentColor = isDark
                    ? Colors.amberAccent
                    : Theme.of(context).colorScheme.onSecondaryContainer;

                return Card(
                  color: cardBgColor,
                  elevation: 0,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                    side: BorderSide(color: cardBorderColor, width: 1),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                    child: Row(
                      children: [
                        Icon(Icons.hourglass_bottom_rounded, color: contentColor),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            'Next task unlocks in $_cooldownSeconds seconds',
                            style: TextStyle(
                              color: contentColor,
                              fontWeight: FontWeight.bold,
                              fontSize: 14,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              }
            ),
            const SizedBox(height: 10),
          ],
          
          // 2. Perform Tasks & Earn Action Card (Small height, 500+ tasks available)
          Card(
            elevation: 2,
            color: isDark ? null : Colors.white,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
              side: BorderSide(color: isDark ? Colors.white10 : Colors.grey.shade200, width: 1),
            ),
            child: InkWell(
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (context) => const PerformTasksScreen()),
                ).then((_) => _loadStateAndJobs());
              },
              borderRadius: BorderRadius.circular(16),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: theme.colorScheme.primary.withOpacity(0.1),
                        shape: BoxShape.circle,
                      ),
                      child: Icon(Icons.rocket_launch, color: theme.colorScheme.primary, size: 24),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Perform Tasks & Earn',
                            style: TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.bold,
                              color: theme.colorScheme.onSurface,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            '500+ tasks available',
                            style: TextStyle(
                              fontSize: 12,
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Icon(Icons.arrow_forward_ios, size: 14, color: theme.colorScheme.onSurfaceVariant),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(height: 10),

          // 3. Live Statistics & Payouts Card
          Card(
            elevation: 2,
            color: isDark ? null : Colors.white,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
              side: BorderSide(color: isDark ? Colors.white10 : Colors.grey.shade200, width: 1),
            ),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Icon(Icons.analytics, color: Colors.blue, size: 20),
                      const SizedBox(width: 8),
                      Text(
                        'Global Platform Stats',
                        style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: theme.colorScheme.onSurface),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Total Payouts',
                            style: TextStyle(fontSize: 11, color: Colors.grey),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            '\$${_formatPayout(_livePayouts)}',
                            style: const TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                              color: Colors.green,
                            ),
                          ),
                        ],
                      ),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          const Text(
                            'Active Members Online',
                            style: TextStyle(fontSize: 11, color: Colors.grey),
                          ),
                          const SizedBox(height: 4),
                          Row(
                            children: [
                              Container(
                                width: 8,
                                height: 8,
                                decoration: const BoxDecoration(
                                  color: Colors.green,
                                  shape: BoxShape.circle,
                                ),
                              ),
                              const SizedBox(width: 6),
                              Text(
                                '$_onlineMembers',
                                style: TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.bold,
                                  color: theme.colorScheme.onSurface,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 10),

          // 4. Live Activity Feed Card
          Card(
            elevation: 2,
            color: isDark ? null : Colors.white,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
              side: BorderSide(color: isDark ? Colors.white10 : Colors.grey.shade200, width: 1),
            ),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Row(
                        children: [
                          const Icon(Icons.chat_bubble_outline_rounded, color: Colors.orange, size: 20),
                          const SizedBox(width: 8),
                          Text(
                            'Live Activity Feed',
                            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: theme.colorScheme.onSurface),
                          ),
                        ],
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                        decoration: BoxDecoration(
                          color: Colors.red.shade900.withOpacity(0.2),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: const Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.fiber_manual_record, color: Colors.red, size: 8),
                            SizedBox(width: 4),
                            Text(
                              'LIVE',
                              style: TextStyle(color: Colors.red, fontSize: 9, fontWeight: FontWeight.bold),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Column(
                    children: _liveActivities.map((act) {
                      return Padding(
                        padding: const EdgeInsets.symmetric(vertical: 6.0),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Expanded(
                              child: Text(
                                act.message,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(fontSize: 12, color: theme.colorScheme.onSurface),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Text(
                              act.timeAgo,
                              style: const TextStyle(fontSize: 11, color: Colors.grey),
                            ),
                          ],
                        ),
                      );
                    }).toList(),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 80),
        ],
      ),
    ),
          ),
          if (_isBottomBannerLoaded && _bottomBannerAd != null)
            Container(
              alignment: Alignment.center,
              width: _bottomBannerAd!.size.width.toDouble(),
              height: _bottomBannerAd!.size.height.toDouble(),
              margin: const EdgeInsets.symmetric(vertical: 8),
              child: AdWidget(
                key: const Key('jobs_bottom_banner_fixed'),
                ad: _bottomBannerAd!,
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildHighPayingTasksPreview() {
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: ExpansionTile(
        shape: const Border(),
        collapsedShape: const Border(),
        leading: Icon(Icons.stars, color: Colors.amber.shade800),
        title: Text(
          '🔥 High-Paying Jobs',
          style: TextStyle(fontWeight: FontWeight.bold, color: Colors.amber.shade800),
        ),
        subtitle: const Text(
          'Earn up to \$1.00 per video review',
          style: TextStyle(color: Colors.grey, fontSize: 12),
        ),
        childrenPadding: const EdgeInsets.all(8.0),
        children: [
          // Tier 2 (Bronze)
          _buildTierPreviewTile(
            level: 2,
            name: 'Bronze Lvl 2 Jobs',
            rate: '\$0.10 - \$0.30 per video review',
            desc: 'Watch and write rating critques for short advertiser video ads (under 10 mins).',
            color: const Color(0xFFCD7F32), // Rich Copper Bronze
          ),
          
          // Tier 3 (Silver)
          _buildTierPreviewTile(
            level: 3,
            name: 'Silver Lvl 3 Jobs',
            rate: '\$0.30 - \$0.60 per video review',
            desc: 'Analyze medium-length advertiser video hooks and branding clips (10 to 30 mins).',
            color: const Color(0xFFA6B4C9), // Shiny Platinum Silver
          ),
          
          // Tier 4 (Gold)
          _buildTierPreviewTile(
            level: 4,
            name: 'Gold Lvl 4 Jobs',
            rate: '\$0.60 - \$1.00 per video review',
            desc: 'Complete detailed marketing feedback reports on full productions and vlogs (31+ mins).',
            color: const Color(0xFFD4AF37), // Elegant Gold
          ),
        ],
      ),
    );
  }

  Widget _buildTierPreviewTile({
    required int level,
    required String name,
    required String rate,
    required String desc,
    required Color color,
  }) {
    final isLocked = _userLevel < level;
    final theme = Theme.of(context);
    
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ExpansionTile(
        shape: const Border(),
        collapsedShape: const Border(),
        leading: Icon(
          isLocked ? Icons.lock_outline : Icons.stars,
          color: isLocked ? Colors.grey : color,
        ),
        title: Text(
          name,
          style: TextStyle(
            fontWeight: FontWeight.bold,
            color: isLocked ? Colors.grey : theme.colorScheme.onSurface,
          ),
        ),
        subtitle: Text(
          rate,
          style: TextStyle(color: isLocked ? Colors.grey : Colors.green.shade800, fontSize: 12),
        ),
        trailing: Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(
            color: (isLocked ? Colors.red : Colors.green).withOpacity(0.15),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Text(
            isLocked ? 'LOCKED' : 'UNLOCKED',
            style: TextStyle(
              color: isLocked ? Colors.red.shade800 : Colors.green.shade800,
              fontSize: 10,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
        children: [
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  desc,
                  style: TextStyle(fontSize: 13, height: 1.4, color: theme.colorScheme.onSurfaceVariant),
                ),
                const SizedBox(height: 12),
                if (isLocked)
                  ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: theme.colorScheme.primary,
                      foregroundColor: theme.colorScheme.onPrimary,
                      minimumSize: const Size(double.infinity, 40),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                    ),
                    onPressed: () => _showUpgradeDialog(level),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(Icons.lock_open, size: 16),
                        const SizedBox(width: 8),
                        Text('Upgrade Level to Unlock Lvl $level'),
                      ],
                    ),
                  )
                else
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: Colors.green.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      '✅ Active Tier Status: Unlocked. Perform unlocked missions below!',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: Colors.green.shade700, fontSize: 12, fontWeight: FontWeight.bold),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  void _showUpgradeDialog(int targetLevel) {
    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: Row(
            children: [
              Icon(Icons.upgrade, color: Colors.amber.shade800),
              const SizedBox(width: 8),
              Text('Level $targetLevel Required'),
            ],
          ),
          content: Text(
            'To perform this high-paying task and earn premium review rates, you must upgrade your earning account to Level $targetLevel.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Maybe Later'),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: Theme.of(context).colorScheme.primary,
                foregroundColor: Theme.of(context).colorScheme.onPrimary,
              ),
              onPressed: () {
                Navigator.pop(context); // Close dialog
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (context) => const LevelUpgradesScreen()),
                ).then((_) => _loadStateAndJobs());
              },
              child: const Text('Upgrade Now'),
            ),
          ],
        );
      },
    );
  }

  Widget _buildQuickAction({
    required IconData icon,
    required String label,
    required Color color,
    required VoidCallback onTap,
  }) {
    final theme = Theme.of(context);
    return InkWell(
      onTap: onTap,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: theme.colorScheme.surfaceVariant.withOpacity(0.5),
              shape: BoxShape.circle,
            ),
            child: Icon(icon, color: color, size: 20),
          ),
          const SizedBox(height: 4),
          Text(
            label,
            style: TextStyle(color: theme.colorScheme.onSurface, fontSize: 10, fontWeight: FontWeight.bold),
          ),
        ],
      ),
    );
  }

  String _formatPayout(double value) {
    if (value >= 1000000) {
      return '${(value / 1000000).toStringAsFixed(1)}M';
    } else if (value >= 1000) {
      return '${(value / 1000).toStringAsFixed(1)}k';
    }
    return value.toStringAsFixed(2);
  }
}

class _LiveActivity {
  final String message;
  final String timeAgo;
  _LiveActivity(this.message, this.timeAgo);
}
