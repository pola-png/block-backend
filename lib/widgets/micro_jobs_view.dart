import 'dart:async';
import 'package:flutter/material.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';
import 'package:supabase_flutter/supabase_flutter.dart' as sb;
import '../models/post.dart';
import '../services/micro_job_service.dart';
import '../services/app_review_service.dart';
import '../services/backend_service.dart';
import '../services/ad_helper.dart';
import '../screens/job_video_player_screen.dart';
import 'home_feed_ad_widgets.dart';

// New screen imports
import '../screens/withdrawal_settings_screen.dart';
import '../screens/level_upgrades_screen.dart';
import '../screens/submit_video_campaign_screen.dart';
import '../screens/video_review_screen.dart';
import '../screens/monetization_screen.dart';

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

  @override
  void initState() {
    super.initState();
    BackendService.adminModeOverride.addListener(_onAdminOverrideChanged);
    _loadStateAndJobs();
    _loadBannerAds();
    _showAppOpenAd();
    _startCooldownCountdown();
    _interstitialTimer = Timer.periodic(const Duration(minutes: 2), (timer) {
      _showInterstitialAd();
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
      request: const AdRequest(),
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
      request: const AdRequest(),
      listener: BannerAdListener(
        onAdLoaded: (_) => setState(() => _isBottomBannerLoaded = true),
        onAdFailedToLoad: (ad, error) {
          ad.dispose();
          debugPrint('Bottom Banner failed to load: $error');
        },
      ),
    )..load();
  }

  void _showAppOpenAd() {
    AppOpenAd.load(
      adUnitId: AdHelper.appOpen,
      request: const AdRequest(),
      adLoadCallback: AppOpenAdLoadCallback(
        onAdLoaded: (ad) {
          ad.fullScreenContentCallback = FullScreenContentCallback(
            onAdDismissedFullScreenContent: (ad) => ad.dispose(),
            onAdFailedToShowFullScreenContent: (ad, error) => ad.dispose(),
          );
          ad.show();
        },
        onAdFailedToLoad: (error) => debugPrint('Failed to load App Open Ad: $error'),
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
      
      if (mounted) {
        setState(() {
          _adminVideos = videos;
          _advertiserCampaigns = campaigns;
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
    _bonusCountdownTimer?.cancel();
    _topBannerAd?.dispose();
    _bottomBannerAd?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final textTheme = theme.textTheme;
    final isDark = theme.brightness == Brightness.dark;
    final backgroundColor = isDark ? const Color(0xFF121212) : const Color(0xFFE9EBF0);
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
          // Available Earnings Card
          Card(
            elevation: 2,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                children: [
                  Text(
                    'Available Earnings',
                    style: TextStyle(
                      color: theme.colorScheme.onSurface,
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 6),
                  InkWell(
                    onTap: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(builder: (context) => const MonetizationScreen()),
                      ).then((_) => _loadStateAndJobs());
                    },
                    borderRadius: BorderRadius.circular(8),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                      child: ValueListenableBuilder<double>(
                        valueListenable: MicroJobService.userBalanceNotifier,
                        builder: (context, balance, _) {
                          return Text(
                            '\$${balance.toStringAsFixed(3)}',
                            style: TextStyle(
                              color: theme.colorScheme.onSurface,
                              fontSize: 32,
                              fontWeight: FontWeight.w900,
                              letterSpacing: -0.5,
                            ),
                          );
                        },
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
                        onTap: () => Navigator.push(
                          context,
                          MaterialPageRoute(builder: (context) => const LevelUpgradesScreen()),
                        ).then((_) => _loadStateAndJobs()),
                      ),
                      _buildQuickAction(
                        icon: Icons.wallet,
                        label: 'Withdraw Settings',
                        color: theme.colorScheme.primary,
                        onTap: () => Navigator.push(
                          context,
                          MaterialPageRoute(builder: (context) => const WithdrawalSettingsScreen()),
                        ),
                      ),
                      _buildQuickAction(
                        icon: Icons.campaign_rounded,
                        label: 'Submit Jobs',
                        color: theme.colorScheme.primary,
                        onTap: () => Navigator.push(
                          context,
                          MaterialPageRoute(builder: (context) => const SubmitVideoCampaignScreen()),
                        ),
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
            const SizedBox(height: 16),
          ],



          // 2. Starter App Review Task (only show if not completed and no earnings)
          if (!isUnlocked) ...[
            Text(
              'Starter Task (Required)',
              style: textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 10),
            Card(
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
                side: BorderSide(
                  color: _appReviewCompleted ? Colors.green.shade800.withOpacity(0.5) : theme.colorScheme.secondary.withOpacity(0.5),
                  width: 1.5,
                ),
              ),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Container(
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            color: (_appReviewCompleted ? Colors.green : theme.colorScheme.secondary).withOpacity(0.1),
                            shape: BoxShape.circle,
                          ),
                          child: Icon(
                            _appReviewCompleted ? Icons.check_circle : Icons.star_rate_rounded,
                            color: _appReviewCompleted ? Colors.green.shade800 : theme.colorScheme.secondary,
                            size: 28,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text(
                                'Review Our Application',
                                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                'Submit a 5-star review on the store to unlock other micro-jobs.',
                                style: TextStyle(color: theme.colorScheme.onSurfaceVariant, fontSize: 13),
                              ),
                            ],
                          ),
                        ),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            const Text(
                              'Reward',
                              style: TextStyle(fontSize: 11, color: Colors.grey),
                            ),
                            Text(
                              '+\$0.20',
                              style: TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.bold,
                                color: _appReviewCompleted ? Colors.grey : Colors.green.shade800,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    if (_appReviewCompleted)
                      ElevatedButton.icon(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.grey.shade800,
                          foregroundColor: Colors.white70,
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        ),
                        onPressed: null,
                        icon: const Icon(Icons.check, size: 18),
                        label: const Text('Already Reviewed & Claimed'),
                      )
                    else
                      ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: theme.colorScheme.primary,
                          foregroundColor: theme.colorScheme.onPrimary,
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        ),
                        onPressed: _completeAppReviewFlow,
                        child: const Text('Start Task Now', style: TextStyle(fontWeight: FontWeight.bold)),
                      ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 24),
          ],

          // 3. Advertiser Video Review Campaigns (Premium)
          if (_advertiserCampaigns.isNotEmpty) ...[
            Text(
              'Premium Video Reviews',
              style: textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 10),
            ...List.generate(_advertiserCampaigns.length, (index) {
              final campaign = _advertiserCampaigns[index];
              final isCompleted = _completedCampaignMap[campaign['id']] ?? false;
              
              // Verify level requirement: Level 2 = Short (up to 10m), Level 3 = Medium (up to 30m)
              // We lock if current user level is less than campaign's base required level
              final int duration = campaign['duration_minutes'] as int? ?? 1;
              
              int requiredLevel = 2;
              if (duration > 10 && duration <= 30) requiredLevel = 3;
              if (duration > 30) requiredLevel = 4;

              final isLocked = !_isAdmin && (_userLevel < requiredLevel);
              final reward = _getRewardForCampaign(campaign);

              return Card(
                margin: const EdgeInsets.only(bottom: 12),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                child: ListTile(
                  enabled: isUnlocked,
                  contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                  leading: Container(
                    width: 50,
                    height: 50,
                    decoration: BoxDecoration(
                      color: isLocked ? Colors.grey.shade900 : Colors.pinkAccent.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Icon(
                      isLocked ? Icons.lock : Icons.rate_review,
                      color: isLocked ? Colors.grey : Colors.pinkAccent,
                      size: 28,
                    ),
                  ),
                  title: Text(
                    'Review Ad: ${campaign['campaign_type']}',
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                  subtitle: Text(
                    'Duration: $duration mins ${isLocked ? "(Level $requiredLevel Required)" : ""}',
                    style: TextStyle(fontSize: 12, color: isLocked ? Colors.orangeAccent : Colors.grey),
                  ),
                  trailing: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(
                        '+\$${reward.toStringAsFixed(2)}',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          color: isLocked ? Colors.grey : Colors.green,
                          fontSize: 14,
                        ),
                      ),
                      const SizedBox(height: 4),
                      if (isCompleted)
                        const Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.check_circle, color: Colors.green, size: 14),
                            SizedBox(width: 4),
                            Icon(Icons.arrow_forward_ios, size: 11),
                          ],
                        )
                      else
                        const Icon(Icons.arrow_forward_ios, size: 12),
                    ],
                  ),
                  onTap: () {
                    if (!isUnlocked) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: const Text('Please complete the starter App Review task first to unlock review jobs!'),
                          backgroundColor: theme.colorScheme.error,
                        ),
                      );
                      return;
                    }

                    if (isLocked) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text('This $duration-minute video review requires a Level $requiredLevel upgrade to unlock!'),
                          backgroundColor: theme.colorScheme.secondary,
                          action: SnackBarAction(
                            label: 'UPGRADE',
                            textColor: Colors.white,
                            onPressed: () {
                              Navigator.push(
                                context,
                                MaterialPageRoute(builder: (context) => const LevelUpgradesScreen()),
                              ).then((_) => _loadStateAndJobs());
                            },
                          ),
                        ),
                      );
                      return;
                    }

                    final cooldown = _cooldownSeconds;
                    if (cooldown > 0) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text('Please wait $cooldown seconds before starting another task.'),
                          backgroundColor: Colors.amber,
                          duration: const Duration(seconds: 2),
                        ),
                      );
                      return;
                    }

                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => VideoReviewScreen(
                          campaign: campaign,
                          rewardAmount: reward,
                          userLevel: _userLevel,
                        ),
                      ),
                    ).then((_) => _loadStateAndJobs());
                  },
                ),
              );
            }),
            const SizedBox(height: 16),
          ],

          // 4. Video Watch Jobs (Standard)
          Text(
            'Video Watch Jobs',
            style: textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 10),
          if (_adminVideos.isEmpty)
            const Padding(
              padding: EdgeInsets.all(20.0),
              child: Center(
                child: Text('No watch jobs available right now. Please check back later.'),
              ),
            )
          else
            Builder(
              builder: (context) {
                final sortedVideos = List.of(_adminVideos);
                sortedVideos.sort((a, b) {
                  final aCompleted = _completedVideoMap[a.id] ?? false;
                  final bCompleted = _completedVideoMap[b.id] ?? false;
                  if (aCompleted && !bCompleted) return 1;
                  if (!aCompleted && bCompleted) return -1;
                  return 0;
                });

                return Column(
                  children: List.generate(sortedVideos.length, (index) {
                    final video = sortedVideos[index];
                    final isCompleted = _completedVideoMap[video.id] ?? false;
                    final reward = _getRewardForPost(video.id);

                    // Find the index of the first uncompleted video in the sorted list
                    final firstUncompletedIndex = sortedVideos.indexWhere(
                      (v) => !(_completedVideoMap[v.id] ?? false)
                    );
                    
                    // Lock sequentially if we are not admin, this job is not completed, and there is a previous uncompleted job
                    final isLockedSequentially = !_isAdmin && 
                        !isCompleted && 
                        firstUncompletedIndex != -1 && 
                        index > firstUncompletedIndex;

                    final cardWidget = Opacity(
                      opacity: (isUnlocked && !isLockedSequentially) ? 1.0 : 0.6,
                      child: Card(
                        margin: const EdgeInsets.only(bottom: 12),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        child: ListTile(
                          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                          leading: Container(
                            width: 50,
                            height: 50,
                            decoration: BoxDecoration(
                              color: theme.colorScheme.primaryContainer.withOpacity(0.3),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Icon(Icons.play_circle_fill, color: theme.colorScheme.primary, size: 32),
                          ),
                          title: Text(
                            video.content.isNotEmpty ? video.content : 'Sponsored Watch Mission',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontWeight: FontWeight.bold),
                          ),
                          subtitle: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const SizedBox(height: 4),
                              Row(
                                children: [
                                  const Icon(Icons.ads_click, size: 12, color: Colors.grey),
                                  const SizedBox(width: 4),
                                  Text('Ads included', style: TextStyle(color: theme.colorScheme.onSurfaceVariant, fontSize: 11)),
                                ],
                              ),
                            ],
                          ),
                          trailing: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            crossAxisAlignment: CrossAxisAlignment.end,
                            children: [
                              Text(
                                '+\$${reward.toStringAsFixed(2)}',
                                style: const TextStyle(
                                  fontWeight: FontWeight.bold,
                                  color: Colors.green,
                                  fontSize: 14,
                                ),
                              ),
                              const SizedBox(height: 4),
                              if (!isUnlocked)
                                Icon(Icons.lock, color: theme.colorScheme.secondary, size: 16)
                              else if (isLockedSequentially)
                                Icon(Icons.lock_outline, color: theme.colorScheme.secondary.withOpacity(0.6), size: 16)
                              else if (isCompleted)
                                const Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(Icons.check_circle, color: Colors.green, size: 14),
                                    SizedBox(width: 4),
                                    Icon(Icons.arrow_forward_ios, size: 11),
                                  ],
                                )
                              else
                                const Icon(Icons.arrow_forward_ios, size: 12),
                            ],
                          ),
                          onTap: () async {
                            if (!isUnlocked) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: const Text('Please complete the starter App Review task first to unlock video watch jobs!'),
                                  backgroundColor: theme.colorScheme.error,
                                ),
                              );
                              return;
                            }

                            if (isLockedSequentially) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: const Text('Please complete the previous watch jobs in sequence first!'),
                                  backgroundColor: theme.colorScheme.error,
                                ),
                              );
                              return;
                            }

                            final cooldown = await MicroJobService.getCooldownSecondsRemaining();
                            if (cooldown > 0) {
                              if (!mounted) return;
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: Text('Please wait $cooldown seconds before starting another task.'),
                                  duration: const Duration(seconds: 2),
                                ),
                              );
                              return;
                            }

                      if (!mounted) return;
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (context) => JobVideoPlayerScreen(
                            post: video,
                            rewardAmount: reward,
                          ),
                        ),
                      ).then((_) {
                        _loadStateAndJobs();
                        _startCooldownCountdown();
                      });
                    },
                  ),
                ),
              );

              // Inject inline native ad after every 2 jobs
              if ((index + 1) % 2 == 0) {
                return Column(
                  children: [
                    cardWidget,
                    HomeInlineNativeAdTile(
                      slotIndex: (index ~/ 2) + 1,
                      reserveSpaceWhenLoading: false,
                      sharedPool: true,
                    ),
                    const SizedBox(height: 12),
                  ],
                );
              }
              return cardWidget;
            }),
                );
              }
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
}
