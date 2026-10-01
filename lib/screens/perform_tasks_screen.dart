import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart' as sb;
import 'package:image_picker/image_picker.dart';
import '../models/post.dart';
import '../services/micro_job_service.dart';
import '../services/app_review_service.dart';
import '../services/backend_service.dart';
import '../services/ad_helper.dart';
import '../services/ad_gate_service.dart';
import '../services/vpn_enforcement_service.dart';
import 'level_upgrades_screen.dart';
import 'video_review_screen.dart';
import 'visit_website_gateway_screen.dart';
import 'ai_training_tasks_screen.dart';
import '../widgets/ad_free_subscription_dialog.dart';

class PerformTasksScreen extends StatefulWidget {
  const PerformTasksScreen({super.key});

  @override
  State<PerformTasksScreen> createState() => _PerformTasksScreenState();
}

class _PerformTasksScreenState extends State<PerformTasksScreen> with SingleTickerProviderStateMixin {
  late TabController _tabController;
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

  int _userLevel = 1;
  bool _isAdmin = false;
  int _cooldownSeconds = 0;
  Timer? _cooldownTimer;

  BannerAd? _bannerAd;
  bool _isBannerLoaded = false;

  String? _reviewProofPath;
  bool _isSubmittingProof = false;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 4, vsync: this, initialIndex: 0);
    BackendService.adminModeOverride.addListener(_onAdminOverrideChanged);
    _loadStateAndJobs();
    _startCooldownCountdown();
    _loadBannerAd();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _checkAdAwarenessConsent();
      AdFreeSubscriptionDialog.checkAndShowDailyPopup(context);
    });
  }

  Future<void> _checkAdAwarenessConsent() async {
    final prefs = await SharedPreferences.getInstance();
    final accepted = prefs.getBool('has_accepted_ad_awareness') ?? false;
    if (!accepted && mounted) {
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (context) {
          final isDark = Theme.of(context).brightness == Brightness.dark;
          return AlertDialog(
            backgroundColor: isDark ? Colors.grey.shade900 : Colors.white,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            title: const Row(
              children: [
                Icon(Icons.ads_click, color: Colors.pinkAccent, size: 28),
                SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Ads Support Earnings 💎',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
                  ),
                ),
              ],
            ),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Welcome to Available Tasks!',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                ),
                const SizedBox(height: 8),
                Text(
                  'XapZap provides high cash rewards for completing tasks. Complete tasks accurately to unlock payouts.',
                  style: TextStyle(fontSize: 13, height: 1.4, color: isDark ? Colors.white70 : Colors.grey.shade800),
                ),
                const SizedBox(height: 12),
                Text(
                  '• Every completed task credits real earnings to your balance.\n'
                  '• Complete tasks accurately to maximize your daily earnings.',
                  style: TextStyle(fontSize: 12, height: 1.5, color: isDark ? Colors.white54 : Colors.grey.shade600),
                ),
              ],
            ),
            actions: [
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.pinkAccent,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                ),
                onPressed: () async {
                  await prefs.setBool('has_accepted_ad_awareness', true);
                  if (context.mounted) {
                    Navigator.pop(context);
                  }
                },
                child: const Text(
                  'I Understand & Always Accept',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
              ),
            ],
          );
        },
      );
    }
  }

  @override
  void dispose() {
    BackendService.adminModeOverride.removeListener(_onAdminOverrideChanged);
    _cooldownTimer?.cancel();
    _tabController.dispose();
    _bannerAd?.dispose();
    super.dispose();
  }

  void _onAdminOverrideChanged() {
    if (mounted) {
      _loadStateAndJobs();
    }
  }

  void _loadBannerAd() {
    _bannerAd = BannerAd(
      adUnitId: AdHelper.banner,
      size: AdSize.banner,
      request: AdHelper.financialRequest,
      listener: BannerAdListener(
        onAdLoaded: (_) => setState(() => _isBannerLoaded = true),
        onAdFailedToLoad: (ad, error) {
          ad.dispose();
          debugPrint('Banner failed to load in perform tasks screen: $error');
        },
      ),
    )..load();
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

  Future<void> _loadStateAndJobs() async {
    if (mounted) {
      setState(() {
        _isLoadingJobs = true;
      });
    }

    final user = await BackendService.getCurrentUser();
    if (user != null) {
      await MicroJobService.reloadUserBalance();
      final level = await MicroJobService.getUserLevel(user.$id);
      bool isAdmin = false;
      bool isTasksUnlocked = false;
      try {
        final profileRes = await sb.Supabase.instance.client
            .from('profiles')
            .select('username, is_admin, is_tasks_unlocked')
            .eq('id', user.$id)
            .maybeSingle();
        if (profileRes != null) {
          isAdmin = profileRes['is_admin'] == true && BackendService.adminModeOverride.value;
          isTasksUnlocked = profileRes['is_tasks_unlocked'] == true;
        }
      } catch (_) {
        // Fallback for migrations
        final profileRes = await sb.Supabase.instance.client
            .from('profiles')
            .select('username, is_admin')
            .eq('id', user.$id)
            .maybeSingle();
        if (profileRes != null) {
          isAdmin = profileRes['is_admin'] == true && BackendService.adminModeOverride.value;
        }
      }

      final isDone = await MicroJobService.isTaskCompleted('starter_app_review');
      if (mounted) {
        setState(() {
          _appReviewCompleted = isDone || isTasksUnlocked;
          _isAdmin = isAdmin;
          _userLevel = isAdmin ? 4 : level;
        });
      }

      final videos = await MicroJobService.fetchAdminVideos();
      for (final video in videos) {
        final completed = await MicroJobService.isTaskCompleted('video_watch_${video.id}');
        _completedVideoMap[video.id] = completed;
      }

      final campaigns = await MicroJobService.fetchActiveCampaigns();
      for (final campaign in campaigns) {
        final comp = await MicroJobService.isCampaignReviewed(campaign['id'], user.$id);
        _completedCampaignMap[campaign['id']] = comp;
      }

      List<String> loadedUrls = [];
      try {
        final res = await sb.Supabase.instance.client
            .from('website_tasks')
            .select('url, is_visible, is_direct');
        for (final row in res) {
          final url = row['url'] as String;
          if (row['is_visible'] == true) {
            loadedUrls.add(url);
          }
          _websiteTasksVisibilityMap[url] = row['is_visible'] ?? true;
          _websiteTasksDirectMap[url] = row['is_direct'] ?? false;
        }
      } catch (e) {
        debugPrint('Error loading website tasks: $e');
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

  double _getRewardForPost(String postId) {
    final mod = postId.hashCode.abs() % 10;
    double base = 0.20 + (mod * 0.03);
    if (_userLevel == 2) {
      base *= 1.5; // Level 2 Bronze
    } else if (_userLevel == 3) {
      base *= 2.2; // Level 3 Silver
    } else if (_userLevel >= 4) {
      base *= 3.2; // Level 4 Gold
    }
    return double.parse(base.toStringAsFixed(2));
  }

  double _getRewardForCampaign(Map<String, dynamic> campaign) {
    final int duration = campaign['duration_minutes'] as int? ?? 1;
    final d = duration.clamp(1, 60);
    double base = 0.20 + ((d - 1) / (60 - 1)) * (0.50 - 0.20);
    
    if (_userLevel == 2) {
      base = 0.30 + ((d - 1) / (60 - 1)) * (0.60 - 0.30);
    } else if (_userLevel == 3) {
      base = 0.50 + ((d - 1) / (60 - 1)) * (0.85 - 0.50);
    } else if (_userLevel >= 4) {
      base = 0.80 + ((d - 1) / (60 - 1)) * (1.50 - 0.80);
    }
    return double.parse(base.toStringAsFixed(2));
  }

  double _getRewardForWebsiteTask(String url) {
    final mod = url.hashCode.abs() % 10;
    double base = 0.20 + (mod * 0.03);
    if (_userLevel == 2) {
      base *= 1.5; // Level 2 Bronze
    } else if (_userLevel == 3) {
      base *= 2.2; // Level 3 Silver
    } else if (_userLevel >= 4) {
      base *= 3.2; // Level 4 Gold
    }
    return double.parse(base.toStringAsFixed(2));
  }

  void _showTopToast(BuildContext context, String message, {bool isError = false}) {
    final overlayState = Overlay.maybeOf(context, rootOverlay: true);
    if (overlayState == null) return;

    late OverlayEntry overlayEntry;
    overlayEntry = OverlayEntry(
      builder: (context) {
        return _TopToastWidget(
          message: message,
          isError: isError,
          onDismiss: () {
            if (overlayEntry.mounted) {
              overlayEntry.remove();
            }
          },
        );
      },
    );

    overlayState.insert(overlayEntry);
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
      final bool adWatched = await XapZapAdGateService.instance.showRewardedAd(placement: 'starter_app_review');
      if (!adWatched) return;
      final success = await MicroJobService.rewardUser('starter_app_review', 0.20);
      if (success) {
        setState(() {
          _appReviewCompleted = true;
        });
        _loadStateAndJobs();
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    
    return Scaffold(
      backgroundColor: theme.brightness == Brightness.dark ? const Color(0xFF121212) : const Color(0xFFE2E8F0),
      appBar: AppBar(
        title: const Text('Available Tasks', style: TextStyle(fontWeight: FontWeight.bold)),
        bottom: TabBar(
          controller: _tabController,
          indicatorColor: theme.colorScheme.primary,
          labelColor: theme.colorScheme.onSurface,
          unselectedLabelColor: theme.colorScheme.onSurfaceVariant,
          tabs: const [
            Tab(text: 'AI Training (\$10-\$50)', icon: Icon(Icons.auto_awesome)),
            Tab(text: 'Website Visit Jobs', icon: Icon(Icons.language)),
            Tab(text: 'App Review', icon: Icon(Icons.star_rate_rounded)),
            Tab(text: 'Video Jobs', icon: Icon(Icons.video_library)),
          ],
        ),
      ),
      body: _isLoadingJobs
          ? const Center(child: CircularProgressIndicator(color: Colors.pinkAccent))
          : Column(
              children: [
                Expanded(
                  child: TabBarView(
                    controller: _tabController,
                    children: [
                      _buildAiTrainingJobsTab(theme),
                      _buildWebsiteJobsTab(theme),
                      _buildAppReviewTab(theme),
                      _buildVideoJobsTab(theme),
                    ],
                  ),
                ),
                if (_isBannerLoaded && _bannerAd != null)
                  Container(
                    alignment: Alignment.center,
                    width: _bannerAd!.size.width.toDouble(),
                    height: _bannerAd!.size.height.toDouble(),
                    child: AdWidget(key: ObjectKey(_bannerAd!), ad: _bannerAd!),
                  ),
              ],
            ),
    );
  }

  Widget _buildAiTrainingJobsTab(ThemeData theme) {
    return const AiTrainingTasksScreen();
  }

  Widget _buildAiProjectCard({
    required String title,
    required String description,
    required String payout,
    required String duration,
    required String milestones,
    required Color color,
    required IconData icon,
  }) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      elevation: 2,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(color: color.withOpacity(0.4), width: 1.5),
      ),
      color: isDark ? color.withOpacity(0.08) : color.withOpacity(0.04),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: color.withOpacity(0.2),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(icon, color: color, size: 24),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                      ),
                      Text(
                        '$duration • $milestones',
                        style: TextStyle(fontSize: 11, color: theme.colorScheme.onSurfaceVariant),
                      ),
                    ],
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color: Colors.green.withOpacity(0.15),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    payout,
                    style: const TextStyle(fontWeight: FontWeight.w900, color: Colors.green, fontSize: 15),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Text(
              description,
              style: TextStyle(fontSize: 12.5, color: theme.colorScheme.onSurfaceVariant, height: 1.35),
            ),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                style: OutlinedButton.styleFrom(
                  foregroundColor: color,
                  side: BorderSide(color: color),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                ),
                onPressed: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(builder: (context) => const AiTrainingTasksScreen()),
                  ).then((_) => _loadStateAndJobs());
                },
                icon: const Icon(Icons.arrow_forward, size: 16),
                label: const Text('Start Project in AI Workspace', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildVideoJobsTab(ThemeData theme) {
    final textTheme = theme.textTheme;
    const isUnlocked = true; // Watch ad tasks are always unlocked for all users

    return RefreshIndicator(
      onRefresh: _loadStateAndJobs,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Card(
            margin: const EdgeInsets.only(bottom: 16),
            color: theme.brightness == Brightness.dark ? Colors.grey.shade900 : Colors.amber.shade50,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14),
              side: BorderSide(color: Colors.amber.shade400, width: 1.5),
            ),
            child: ListTile(
              contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              leading: Container(
                width: 44,
                height: 44,
                decoration: const BoxDecoration(
                  color: Colors.amber,
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.play_arrow_rounded, color: Colors.white, size: 28),
              ),
              title: const Row(
                children: [
                  Flexible(
                    child: Text(
                      'Watch Quick Ad',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                    ),
                  ),
                  SizedBox(width: 8),
                  Icon(Icons.bolt, color: Colors.amber, size: 18),
                ],
              ),
              subtitle: const Text('Earn 50 Coins (Auto-converts to \$0.00119)'),
              trailing: const Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text('+50 Coins', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.green, fontSize: 13)),
                  SizedBox(height: 2),
                  Icon(Icons.arrow_forward_ios, size: 12, color: Colors.amber),
                ],
              ),
              onTap: () async {
                final int cooldown = await MicroJobService.getQuickAdCooldownRemaining();
                if (cooldown > 0) {
                  if (!mounted) return;
                  _showTopToast(context, 'Please wait $cooldown seconds before watching another ad.', isError: true);
                  return;
                }
                final bool adWatched = await XapZapAdGateService.instance.showRewardedAd(placement: 'watch_quick_ad');
                if (!adWatched) return;
                await MicroJobService.markQuickAdWatched();
                final String taskId = 'quick_ad_watch_${DateTime.now().millisecondsSinceEpoch}';
                final bool success = await MicroJobService.rewardUser(taskId, 0.00119);
                if (success && mounted) {
                  _showTopToast(context, 'Instant Reward of 50 Coins (+\$0.00119) credited to your balance! 🎉');
                  _loadStateAndJobs();
                }
              },
            ),
          ),
          Text('Video Watch Jobs', style: textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
          const SizedBox(height: 10),
          if (_adminVideos.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 20.0),
              child: Center(child: Text('No watch jobs available right now.')),
            )
          else
            Column(
              children: List.generate(_adminVideos.length, (index) {
                final video = _adminVideos[index];
                final isCompleted = _completedVideoMap[video.id] ?? false;
                final reward = _getRewardForPost(video.id);

                final firstUncompletedIndex = _adminVideos.indexWhere(
                  (v) => !(_completedVideoMap[v.id] ?? false)
                );
                final isLockedSequentially = !_isAdmin && !isCompleted && firstUncompletedIndex != -1 && index > firstUncompletedIndex;

                return Opacity(
                  opacity: (isUnlocked && !isLockedSequentially) ? 1.0 : 0.6,
                  child: Card(
                    margin: const EdgeInsets.only(bottom: 12),
                    color: theme.brightness == Brightness.dark ? null : Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                      side: BorderSide(color: theme.brightness == Brightness.dark ? Colors.white10 : Colors.grey.shade200, width: 1),
                    ),
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
                        video.content.isNotEmpty ? video.content : 'Sponsored Review Mission',
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
                            style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.green, fontSize: 14),
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
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text('Please wait $cooldown seconds before starting another task.'),
                              duration: const Duration(seconds: 2),
                            ),
                          );
                          return;
                        }
                        final bool adWatched = await XapZapAdGateService.instance.showRewardedAd(placement: 'perform_task_video');
                        if (!adWatched) return;
                        if (!mounted) return;
                        final syntheticCampaign = <String, dynamic>{
                          'id': video.id,
                          'video_url': video.videoUrl ?? video.preferredVideoUrl ?? '',
                          'campaign_type': 'Watch',
                          'duration_minutes': 20,
                          'target_reviews': 999,
                          'reviews_completed': 0,
                          'status': 'active',
                        };
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (context) => VideoReviewScreen(
                              campaign: syntheticCampaign,
                              rewardAmount: reward,
                              userLevel: _userLevel,
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
              }),
            ),
          const SizedBox(height: 20),

          // 3. Advertiser Campaigns
          if (_advertiserCampaigns.isNotEmpty) ...[
            Text('Premium Video Reviews', style: textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
            const SizedBox(height: 10),
            Column(
              children: List.generate(_advertiserCampaigns.length, (index) {
                final campaign = _advertiserCampaigns[index];
                final isCompleted = _completedCampaignMap[campaign['id']] ?? false;
                final int duration = campaign['duration_minutes'] as int? ?? 1;

                int requiredLevel = 2;
                if (duration > 10 && duration <= 30) requiredLevel = 3;
                if (duration > 30) requiredLevel = 4;

                final isLocked = !_isAdmin && (_userLevel < requiredLevel);
                final reward = _getRewardForCampaign(campaign);

                return Card(
                  margin: const EdgeInsets.only(bottom: 12),
                  color: theme.brightness == Brightness.dark ? null : Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                    side: BorderSide(color: theme.brightness == Brightness.dark ? Colors.white10 : Colors.grey.shade200, width: 1),
                  ),
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
                    onTap: () async {
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
                      final bool adWatched = await XapZapAdGateService.instance.showRewardedAd(placement: 'perform_task_review');
                      if (!adWatched) return;
                      if (!mounted) return;
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (context) => VideoReviewScreen(
                            campaign: campaign,
                            rewardAmount: reward,
                            userLevel: _userLevel,
                          ),
                        ),
                      ).then((_) {
                        _loadStateAndJobs();
                        _startCooldownCountdown();
                      });
                    },
                  ),
                );
              }),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildWebsiteJobsTab(ThemeData theme) {
    final textTheme = theme.textTheme;
    final isUnlocked = _appReviewCompleted;

    return RefreshIndicator(
      onRefresh: _loadStateAndJobs,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          if (!isUnlocked) ...[
            Card(
              color: theme.colorScheme.errorContainer.withOpacity(0.2),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
                side: BorderSide(color: theme.colorScheme.error.withOpacity(0.3)),
              ),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  children: [
                    const Icon(Icons.lock_outline, size: 36, color: Colors.orange),
                    const SizedBox(height: 12),
                    const Text(
                      'All Tasks Locked!',
                      style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'As a new user, you must submit an App Review first before you can unlock and perform any other tasks.',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: theme.colorScheme.onSurfaceVariant, fontSize: 13),
                    ),
                    const SizedBox(height: 16),
                    ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: theme.colorScheme.primary,
                        foregroundColor: theme.colorScheme.onPrimary,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                      ),
                      onPressed: () {
                        _tabController.animateTo(1); // Go to App Review tab
                      },
                      icon: const Icon(Icons.star_rate_rounded, size: 18),
                      label: const Text('Go to App Review Tab', style: TextStyle(fontWeight: FontWeight.bold)),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
          ],
          Text('Website Visit Jobs', style: textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
          const SizedBox(height: 10),
          if (_websiteTasksUrls.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 20.0),
              child: Center(child: Text('No website visit tasks available.')),
            )
          else
            Column(
              children: _websiteTasksUrls.map((url) {
                final isCompleted = _completedWebsiteTasksMap[url] ?? false;
                return Opacity(
                  opacity: isUnlocked ? 1.0 : 0.6,
                  child: Card(
                    margin: const EdgeInsets.only(bottom: 12),
                    color: theme.brightness == Brightness.dark ? null : Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                      side: BorderSide(color: theme.brightness == Brightness.dark ? Colors.white10 : Colors.grey.shade200, width: 1),
                    ),
                    child: ListTile(
                      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                      leading: Container(
                        width: 50,
                        height: 50,
                        decoration: BoxDecoration(
                          color: theme.colorScheme.primaryContainer.withOpacity(0.2),
                          shape: BoxShape.circle,
                        ),
                        child: Icon(Icons.public, color: theme.colorScheme.primary, size: 28),
                      ),
                      title: const Text(
                        'Browse Sponsored URL',
                        style: TextStyle(fontWeight: FontWeight.bold),
                      ),
                      subtitle: const Text(
                        'Visit sponsor website and browse to earn rewards',
                        style: TextStyle(fontSize: 12, color: Colors.grey),
                      ),
                      trailing: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Text(
                            '+\$${_getRewardForWebsiteTask(url).toStringAsFixed(2)}',
                            style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.green, fontSize: 14),
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
                      onTap: () async {
                        if (!isUnlocked) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: const Text('Please complete the starter App Review task first to unlock website visit tasks!'),
                              backgroundColor: theme.colorScheme.error,
                            ),
                          );
                          return;
                        }
                        if (isCompleted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text('You have already completed this website visit task!'),
                              backgroundColor: Colors.orange,
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
                        final bool isVpnValid = await VpnEnforcementService.instance.verifyVpnAndProceed(context);
                        if (!isVpnValid) return;
                        final bool adWatched = await XapZapAdGateService.instance.showRewardedAd(placement: 'perform_task_website');
                        if (!adWatched) return;
                        if (!mounted) return;
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (context) => VisitWebsiteGatewayScreen(
                              url: url,
                              isDirect: true,
                              rewardAmount: _getRewardForWebsiteTask(url),
                            ),
                          ),
                        ).then((_) => _loadStateAndJobs());
                      },
                    ),
                  ),
                );
              }).toList(),
            ),
        ],
      ),
    );
  }

  Widget _buildAppReviewTab(ThemeData theme) {
    final textTheme = theme.textTheme;
    final isDark = theme.brightness == Brightness.dark;

    return RefreshIndicator(
      onRefresh: _loadStateAndJobs,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Card(
            elevation: 2,
            color: theme.brightness == Brightness.dark ? null : Colors.white,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
              side: BorderSide(color: theme.brightness == Brightness.dark ? Colors.white10 : Colors.grey.shade200, width: 1),
            ),
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Center(
                    child: Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: (_appReviewCompleted ? Colors.green : theme.colorScheme.primary).withOpacity(0.1),
                        shape: BoxShape.circle,
                      ),
                      child: Icon(
                        _appReviewCompleted ? Icons.check_circle : Icons.star_rate_rounded,
                        color: _appReviewCompleted ? Colors.green : theme.colorScheme.primary,
                        size: 48,
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'Rate & Review XapZap',
                    textAlign: TextAlign.center,
                    style: textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Help us grow by leaving a 5-star review on the Play Store, upload a screenshot proof of your review below, and claim your \$1.00 reward!',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: theme.colorScheme.onSurfaceVariant, height: 1.4),
                  ),
                  const SizedBox(height: 24),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                    decoration: BoxDecoration(
                      color: Colors.green.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: Colors.green.withOpacity(0.3)),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text(
                          'Task Reward:',
                          style: TextStyle(fontWeight: FontWeight.bold),
                        ),
                        Text(
                          '\$1.00',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w900,
                            color: Colors.green.shade800,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 24),
                  if (_appReviewCompleted) ...[
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: Colors.grey.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.check_circle, color: Colors.green),
                          SizedBox(width: 8),
                          Text(
                            'Review Approved & Reward Claimed',
                            style: TextStyle(fontWeight: FontWeight.bold, color: Colors.grey),
                          ),
                        ],
                      ),
                    ),
                  ] else ...[
                    ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: theme.colorScheme.primary,
                        foregroundColor: theme.colorScheme.onPrimary,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                      onPressed: () async {
                        // Open Play Store listing / native in-app review
                        await AppReviewService.requestReview();
                      },
                      icon: const Icon(Icons.open_in_new),
                      label: const Text(
                        '1. Open Review Dialog & Rate',
                        style: TextStyle(fontWeight: FontWeight.bold),
                      ),
                    ),
                    const SizedBox(height: 20),
                    const Text(
                      '2. Upload Review Screenshot Proof',
                      style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                    ),
                    const SizedBox(height: 10),
                    InkWell(
                      onTap: () async {
                        final picker = ImagePicker();
                        final img = await picker.pickImage(source: ImageSource.gallery);
                        if (img != null) {
                          setState(() {
                            _reviewProofPath = img.path;
                          });
                        }
                      },
                      child: Container(
                        height: 150,
                        decoration: BoxDecoration(
                          color: isDark ? Colors.grey.shade900 : Colors.grey.shade100,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: Colors.grey.shade400, style: BorderStyle.solid),
                        ),
                        child: _reviewProofPath != null
                            ? Stack(
                                children: [
                                  Positioned.fill(
                                    child: ClipRRect(
                                      borderRadius: BorderRadius.circular(12),
                                      child: Image.file(
                                        File(_reviewProofPath!),
                                        fit: BoxFit.cover,
                                      ),
                                    ),
                                  ),
                                  Positioned(
                                    right: 8,
                                    top: 8,
                                    child: CircleAvatar(
                                      backgroundColor: Colors.black54,
                                      child: IconButton(
                                        icon: const Icon(Icons.close, color: Colors.white),
                                        onPressed: () {
                                          setState(() {
                                            _reviewProofPath = null;
                                          });
                                        },
                                      ),
                                    ),
                                  ),
                                ],
                              )
                            : Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Icon(Icons.add_photo_alternate, size: 40, color: Colors.grey.shade600),
                                  const SizedBox(height: 8),
                                  Text(
                                    'Tap to select screenshot from gallery',
                                    style: TextStyle(color: Colors.grey.shade600, fontSize: 12),
                                  ),
                                ],
                              ),
                      ),
                    ),
                    const SizedBox(height: 24),
                    ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.green.shade700,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                      onPressed: (_reviewProofPath == null || _isSubmittingProof)
                          ? null
                          : () async {
                              final bool isVpnValid = await VpnEnforcementService.instance.verifyVpnAndProceed(context);
                              if (!isVpnValid) return;
                              setState(() {
                                _isSubmittingProof = true;
                              });
                              // Simulate verification upload
                              await Future.delayed(const Duration(seconds: 2));
                              final bool adWatched = await XapZapAdGateService.instance.showRewardedAd(placement: 'app_review_proof');
                              if (!adWatched) {
                                if (mounted) {
                                  setState(() {
                                    _isSubmittingProof = false;
                                  });
                                }
                                return;
                              }
                              final success = await MicroJobService.rewardUser('starter_app_review', 1.00);
                               final currentUser = await BackendService.getCurrentUser();
                               if (success && currentUser != null) {
                                 try {
                                   await sb.Supabase.instance.client
                                       .from('profiles')
                                       .update({'is_tasks_unlocked': true})
                                       .eq('id', currentUser.$id);
                                 } catch (_) {}
                               }
                              if (mounted) {
                                setState(() {
                                  _isSubmittingProof = false;
                                  if (success) {
                                    _appReviewCompleted = true;
                                  }
                                });
                                if (success) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    const SnackBar(
                                      content: Text('Awesome! Review proof submitted and \$1.00 reward credited!'),
                                      backgroundColor: Colors.green,
                                    ),
                                  );
                                  _loadStateAndJobs();
                                }
                              }
                            },
                      child: _isSubmittingProof
                          ? const SizedBox(
                              height: 20,
                              width: 20,
                              child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
                            )
                          : const Text(
                              'Submit Proof & Claim \$1.00',
                              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                            ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _TopToastWidget extends StatefulWidget {
  final String message;
  final bool isError;
  final VoidCallback onDismiss;

  const _TopToastWidget({
    required this.message,
    required this.isError,
    required this.onDismiss,
  });

  @override
  State<_TopToastWidget> createState() => _TopToastWidgetState();
}

class _TopToastWidgetState extends State<_TopToastWidget> with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<Offset> _offsetAnimation;
  late Animation<double> _fadeAnimation;
  Timer? _dismissTimer;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 350),
    );

    _offsetAnimation = Tween<Offset>(
      begin: const Offset(0, -1.0),
      end: Offset.zero,
    ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeOutCubic));

    _fadeAnimation = CurvedAnimation(parent: _controller, curve: Curves.easeIn);

    _controller.forward();

    _dismissTimer = Timer(const Duration(seconds: 4), () {
      _dismiss();
    });
  }

  void _dismiss() async {
    _dismissTimer?.cancel();
    if (mounted) {
      await _controller.reverse();
    }
    widget.onDismiss();
  }

  @override
  void dispose() {
    _dismissTimer?.cancel();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final mediaQuery = MediaQuery.of(context);
    final topPadding = mediaQuery.padding.top + 10.0;

    return Positioned(
      top: topPadding,
      left: 16,
      right: 16,
      child: SlideTransition(
        position: _offsetAnimation,
        child: FadeTransition(
          opacity: _fadeAnimation,
          child: Material(
            color: Colors.transparent,
            child: GestureDetector(
              onTap: _dismiss,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                decoration: BoxDecoration(
                  color: widget.isError ? const Color(0xFFB91C1C) : const Color(0xFF047857),
                  borderRadius: BorderRadius.circular(16),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.35),
                      blurRadius: 16,
                      offset: const Offset(0, 6),
                    ),
                  ],
                  border: Border.all(
                    color: widget.isError ? Colors.redAccent.shade100 : const Color(0xFFA7F3D0),
                    width: 1.5,
                  ),
                ),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.2),
                        shape: BoxShape.circle,
                      ),
                      child: Icon(
                        widget.isError ? Icons.hourglass_bottom_rounded : Icons.stars_rounded,
                        color: Colors.white,
                        size: 22,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        widget.message,
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                          fontSize: 13.5,
                          height: 1.3,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    const Icon(Icons.close, color: Colors.white70, size: 18),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
