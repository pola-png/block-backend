import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'backend_service.dart';
import '../models/post.dart';

class MicroJobService {
  static const String _completedTasksKey = 'xapzap_completed_micro_jobs_v1';
  static final ValueNotifier<double> userBalanceNotifier = ValueNotifier<double>(0.0);

  // Checks if a task is already completed by the user (resets after 60 seconds)
  static Future<bool> isTaskCompleted(String taskId) async {
    final prefs = await SharedPreferences.getInstance();
    final completedTime = prefs.getInt('${_completedTasksKey}_time_$taskId') ?? 0;
    if (completedTime == 0) return false;
    final elapsedMs = DateTime.now().millisecondsSinceEpoch - completedTime;
    if (elapsedMs >= 60 * 1000) {
      return false; // Completed more than 60s ago, so it is available again
    }
    return true;
  }

  // Marks a task as completed locally and returns true if it was newly completed
  static Future<bool> _markTaskCompletedLocally(String taskId) async {
    final prefs = await SharedPreferences.getInstance();
    final now = DateTime.now().millisecondsSinceEpoch;

    final completedTime = prefs.getInt('${_completedTasksKey}_time_$taskId') ?? 0;
    if (completedTime != 0 && (now - completedTime < 60 * 1000)) {
      return false;
    }

    await prefs.setInt('${_completedTasksKey}_time_$taskId', now);

    final completed = prefs.getStringList(_completedTasksKey) ?? <String>[];
    if (!completed.contains(taskId)) {
      completed.add(taskId);
      await prefs.setStringList(_completedTasksKey, completed);
    }
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
    final remainingSeconds = 10 - (elapsedMs ~/ 1000);
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

  static Future<List<Post>> fetchAdminVideos() async {
    final List<Post> combinedVideos = [];

    // 1. Fetch boosted posts
    try {
      final res = await BackendService.getDocuments(
        BackendService.postsCollectionId,
      );
      for (final row in res.rows) {
        try {
          final data = row.data as Map<String, dynamic>;
          final isBoosted = data['isBoosted'] == true || data['is_boosted'] == true;
          if (!isBoosted) continue;

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
               videoUrl.toLowerCase().contains('.m3u8') ||
               videoUrl.toLowerCase().contains('youtube.com') ||
               videoUrl.toLowerCase().contains('youtu.be'));

          if (isVideo) {
            combinedVideos.add(
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
    } catch (_) {}

    // 2. Fetch advertiser campaigns from Supabase and parse them into Post models
    try {
      final campaigns = await fetchActiveCampaigns();
      for (final campaign in campaigns) {
        final videoUrl = campaign['video_url'] as String? ?? '';
        if (videoUrl.isNotEmpty) {
          combinedVideos.add(
            Post(
              id: campaign['id'] as String,
              username: 'sponsored_promo',
              userAvatar: '',
              content: campaign['title'] as String? ?? 'Sponsored Premium Review Campaign',
              videoUrl: videoUrl,
              timestamp: DateTime.now(),
              likes: 120,
              comments: 5,
              reposts: 2,
              views: 1000,
              isBoosted: true,
            ),
          );
        }
      }
    } catch (_) {}

    // Shuffle the combined list to rotate videos dynamically
    combinedVideos.shuffle();
    return combinedVideos;
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

  static double _totalPayoutBase = 132450.80;

  static Future<double> getTotalPayoutBase() async {
    final prefs = await SharedPreferences.getInstance();
    _totalPayoutBase = prefs.getDouble('xapzap_total_payout_base') ?? 132450.80;
    try {
      final res = await Supabase.instance.client
          .from('app_settings')
          .select('value')
          .eq('key', 'total_payout_usd')
          .maybeSingle();
      if (res != null && res['value'] != null) {
        final val = double.tryParse(res['value'].toString());
        if (val != null) {
          _totalPayoutBase = val;
          await prefs.setDouble('xapzap_total_payout_base', val);
        }
      }
    } catch (_) {}
    return _totalPayoutBase;
  }

  static Future<void> saveTotalPayoutBase(double value) async {
    final prefs = await SharedPreferences.getInstance();
    _totalPayoutBase = value;
    await prefs.setDouble('xapzap_total_payout_base', value);
    try {
      await Supabase.instance.client
          .from('app_settings')
          .upsert({'key': 'total_payout_usd', 'value': value.toString()});
    } catch (_) {}
  }
}
