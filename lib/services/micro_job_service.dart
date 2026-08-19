import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'backend_service.dart';
import '../models/post.dart';

class MicroJobService {
  static const String _completedTasksKey = 'xapzap_completed_micro_jobs_v1';
  static final ValueNotifier<double> userBalanceNotifier = ValueNotifier<double>(0.0);

  // Checks if a task is already completed by the user
  static Future<bool> isTaskCompleted(String taskId) async {
    final prefs = await SharedPreferences.getInstance();
    final completed = prefs.getStringList(_completedTasksKey) ?? <String>[];
    return completed.contains(taskId);
  }

  // Marks a task as completed locally and returns true if it was newly completed
  static Future<bool> _markTaskCompletedLocally(String taskId) async {
    final prefs = await SharedPreferences.getInstance();
    final completed = prefs.getStringList(_completedTasksKey) ?? <String>[];
    if (completed.contains(taskId)) return false;
    completed.add(taskId);
    await prefs.setStringList(_completedTasksKey, completed);
    return true;
  }

  // Reloads user balance and updates userBalanceNotifier
  static Future<void> reloadUserBalance() async {
    final user = await BackendService.getCurrentUser();
    if (user == null) {
      userBalanceNotifier.value = 0.0;
      return;
    }
    final balanceRow = await BackendService.getLatestCreatorBalance(user.$id);
    if (balanceRow != null) {
      final data = balanceRow.data as Map<String, dynamic>;
      final val = data['balanceUsd'] ?? data['availableBalanceUsd'] ?? 0.0;
      if (val is num) {
        userBalanceNotifier.value = val.toDouble();
      } else {
        userBalanceNotifier.value = double.tryParse(val.toString()) ?? 0.0;
      }
    } else {
      userBalanceNotifier.value = 0.0;
    }
  }

  static const String _lastCompletedTimeKey = 'xapzap_last_completed_task_time';

  static Future<void> setLastCompletedTime() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_lastCompletedTimeKey, DateTime.now().millisecondsSinceEpoch);
  }

  static Future<int> getCooldownSecondsRemaining() async {
    final prefs = await SharedPreferences.getInstance();
    final lastTime = prefs.getInt(_lastCompletedTimeKey) ?? 0;
    if (lastTime == 0) return 0;
    
    final elapsedMs = DateTime.now().millisecondsSinceEpoch - lastTime;
    final remainingSeconds = 60 - (elapsedMs ~/ 1000);
    return remainingSeconds > 0 ? remainingSeconds : 0;
  }

  // Reward the user and update the remote database
  static Future<bool> rewardUser(String taskId, double rewardAmount) async {
    final user = await BackendService.getCurrentUser();
    if (user == null) return false;

    // 1. Mark task as completed locally
    final isNew = await _markTaskCompletedLocally(taskId);
    if (!isNew && !taskId.startsWith('video_watch_')) return false; // Already rewarded (except video watches)

    // 2. Update balance in Appwrite (and later Supabase)
    // NOTE: When migrating to Supabase, replace this block with:
    // await Supabase.instance.client.rpc('reward_user', params: { 'p_user_id': user.id, 'p_amount': rewardAmount });
    try {
      final balanceRow = await BackendService.getLatestCreatorBalance(user.$id);
      if (balanceRow != null) {
        final data = balanceRow.data as Map<String, dynamic>;
        final currentBalVal = data['balanceUsd'] ?? 0.0;
        final currentAvailVal = data['availableBalanceUsd'] ?? 0.0;
        
        final double currentBal = currentBalVal is num ? currentBalVal.toDouble() : (double.tryParse(currentBalVal.toString()) ?? 0.0);
        final double currentAvail = currentAvailVal is num ? currentAvailVal.toDouble() : (double.tryParse(currentAvailVal.toString()) ?? 0.0);

        final newBal = currentBal + rewardAmount;
        final newAvail = currentAvail + rewardAmount;

        await BackendService.updateRow(
          BackendService.creatorBalancesCollectionId,
          balanceRow.$id,
          {
            'balanceUsd': newBal,
            'availableBalanceUsd': newAvail,
          },
        );
      } else {
        // Create new balance row if one doesn't exist
        await BackendService.createDocument(
          BackendService.creatorBalancesCollectionId,
          {
            'creatorId': user.$id,
            'balanceUsd': rewardAmount,
            'availableBalanceUsd': rewardAmount,
          },
        );
      }
      
      // Record last completed time for cooldown
      await setLastCompletedTime();
      
      // Update notifier to refresh UI
      await reloadUserBalance();
      return true;
    } catch (e) {
      debugPrint('Failed to reward user: $e');
      return false;
    }
  }

  // Fetches videos posted by the admin as video watch tasks.
  // Filters posts to only include those by admin accounts (e.g. usernames containing admin/staff or post creators with specific IDs)
  static Future<List<Post>> fetchAdminVideos() async {
    try {
      // Get all posts
      final res = await BackendService.getDocuments(
        BackendService.postsCollectionId,
      );

      final List<Post> adminVideos = [];
      for (final row in res.rows) {
        try {
          final data = row.data as Map<String, dynamic>;
          
          // Only show boosted videos
          final isBoosted = data['isBoosted'] == true || data['is_boosted'] == true;
          if (!isBoosted) continue;

          // Extract videoUrl: check videoUrl column first, fallback to first item of mediaUrls
          String? videoUrl = data['videoUrl'] as String?;
          if (videoUrl == null || videoUrl.isEmpty) {
            final media = data['mediaUrls'] as List?;
            if (media != null && media.isNotEmpty) {
              final first = media.first.toString();
              if (first.startsWith('http://') || first.startsWith('https://')) {
                videoUrl = first;
              }
            }
          }

          final isVideo = videoUrl != null &&
              (videoUrl.toLowerCase().contains('.mp4') ||
               videoUrl.toLowerCase().contains('.mov') ||
               videoUrl.toLowerCase().contains('.m3u8'));

          if (isVideo) {
            adminVideos.add(
              Post(
                id: row.$id,
                username: data['username'] as String? ?? 'xapzap_admin',
                userAvatar: data['userAvatar'] as String? ?? '',
                content: data['content'] as String? ?? '',
                videoUrl: videoUrl,
                timestamp: DateTime.tryParse(row.$createdAt) ?? DateTime.now(),
                likes: data['likes'] as int? ?? 0,
                comments: data['comments'] as int? ?? 0,
                reposts: data['reposts'] as int? ?? 0,
                views: data['views'] as int? ?? 0,
                isBoosted: true,
              ),
            );
          }
        } catch (_) {}
      }

      // Always guarantee at least 8 jobs by padding with fallback/mock videos
      final fallbacks = _getFallbackAdminJobs();
      int fallbackIndex = 0;
      while (adminVideos.length < 8 && fallbackIndex < fallbacks.length) {
        final fb = fallbacks[fallbackIndex++];
        if (!adminVideos.any((v) => v.id == fb.id)) {
          adminVideos.add(fb);
        }
      }
      return adminVideos;
    } catch (_) {
      return _getFallbackAdminJobs();
    }
  }

  static List<Post> _getFallbackAdminJobs() {
    return [
      Post(
        id: 'admin_job_video_1',
        username: 'xapzap_staff',
        userAvatar: '',
        content: 'Watch this onboarding presentation to understand the new features of XapZap!',
        videoUrl: 'https://assets.mixkit.co/videos/preview/mixkit-stars-in-space-background-1611-large.mp4',
        timestamp: DateTime.now().subtract(const Duration(days: 1)),
        likes: 999,
        comments: 42,
        reposts: 15,
        views: 10423,
      ),
      Post(
        id: 'admin_job_video_2',
        username: 'xapzap_rewards',
        userAvatar: '',
        content: 'Find out how to maximize your daily earnings with Micro Jobs on our platform.',
        videoUrl: 'https://assets.mixkit.co/videos/preview/mixkit-forest-stream-in-the-sunlight-529-large.mp4',
        timestamp: DateTime.now().subtract(const Duration(days: 2)),
        likes: 1250,
        comments: 88,
        reposts: 22,
        views: 12435,
      ),
      Post(
        id: 'admin_job_video_3',
        username: 'xapzap_promo',
        userAvatar: '',
        content: 'Check out the top community moments from last month!',
        videoUrl: 'https://assets.mixkit.co/videos/preview/mixkit-texture-of-a-waving-blue-flag-in-wind-48866-large.mp4',
        timestamp: DateTime.now().subtract(const Duration(days: 3)),
        likes: 888,
        comments: 31,
        reposts: 11,
        views: 8904,
      ),
      Post(
        id: 'admin_job_video_4',
        username: 'xapzap_admin',
        userAvatar: '',
        content: 'Learn how to secure your XapZap account with 2FA.',
        videoUrl: 'https://assets.mixkit.co/videos/preview/mixkit-wavy-surface-of-dark-blue-liquid-48864-large.mp4',
        timestamp: DateTime.now().subtract(const Duration(days: 4)),
        likes: 654,
        comments: 29,
        reposts: 8,
        views: 7430,
      ),
      Post(
        id: 'admin_job_video_5',
        username: 'xapzap_support',
        userAvatar: '',
        content: 'How to request payouts and transfer your earnings.',
        videoUrl: 'https://assets.mixkit.co/videos/preview/mixkit-bright-neon-tunnel-in-a-futuristic-city-43183-large.mp4',
        timestamp: DateTime.now().subtract(const Duration(days: 5)),
        likes: 720,
        comments: 54,
        reposts: 14,
        views: 9540,
      ),
      Post(
        id: 'admin_job_video_6',
        username: 'xapzap_events',
        userAvatar: '',
        content: 'Upcoming creator events and community guidelines updates.',
        videoUrl: 'https://assets.mixkit.co/videos/preview/mixkit-rotating-planet-earth-in-space-1206-large.mp4',
        timestamp: DateTime.now().subtract(const Duration(days: 6)),
        likes: 1120,
        comments: 72,
        reposts: 19,
        views: 11240,
      ),
      Post(
        id: 'admin_job_video_7',
        username: 'xapzap_marketing',
        userAvatar: '',
        content: 'Maximize your reach and get more followers on XapZap.',
        videoUrl: 'https://assets.mixkit.co/videos/preview/mixkit-abstract-graphic-tunnel-of-golden-squares-43187-large.mp4',
        timestamp: DateTime.now().subtract(const Duration(days: 7)),
        likes: 830,
        comments: 38,
        reposts: 12,
        views: 8900,
      ),
      Post(
        id: 'admin_job_video_8',
        username: 'xapzap_moderator',
        userAvatar: '',
        content: 'Understanding copyright policies and safe uploading.',
        videoUrl: 'https://assets.mixkit.co/videos/preview/mixkit-spinning-disc-of-blue-neon-light-43181-large.mp4',
        timestamp: DateTime.now().subtract(const Duration(days: 8)),
        likes: 410,
        comments: 18,
        reposts: 5,
        views: 5210,
      ),
    ];
  }

  // Gets the current user level (defaults to 1 if not set)
  static Future<int> getUserLevel(String userId) async {
    try {
      final res = await Supabase.instance.client
          .from('profiles')
          .select('user_level')
          .eq('id', userId)
          .maybeSingle();
      if (res != null) {
        return res['user_level'] as int? ?? 1;
      }
    } catch (_) {}
    return 1;
  }

  // Fetches all active advertiser video campaigns
  static Future<List<Map<String, dynamic>>> fetchActiveCampaigns() async {
    try {
      final res = await Supabase.instance.client
          .from('video_campaigns')
          .select()
          .eq('status', 'active');
      
      // Filter out completed ones where limit is reached
      final List<Map<String, dynamic>> active = [];
      for (final row in res) {
        final completed = row['reviews_completed'] as int? ?? 0;
        final target = row['target_reviews'] as int? ?? 0;
        if (completed < target) {
          active.add(row);
        }
      }
      return active;
    } catch (_) {
      return [];
    }
  }

  // Checks if user completed the rating/review for a campaign
  static Future<bool> isCampaignReviewed(String campaignId, String userId) async {
    try {
      final res = await Supabase.instance.client
          .from('user_completed_reviews')
          .select('id')
          .eq('user_id', userId)
          .eq('campaign_id', campaignId)
          .maybeSingle();
      return res != null;
    } catch (_) {
      return false;
    }
  }
}
