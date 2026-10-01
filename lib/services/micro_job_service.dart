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

  static Future<String?> _resolveCurrentUserId() async {
    final supaUid = Supabase.instance.client.auth.currentUser?.id;
    if (supaUid != null && supaUid.isNotEmpty) return supaUid;
    final backendUser = await BackendService.getCurrentUser();
    return backendUser?.$id;
  }

  static DateTime? _lastBalanceFetchTime;
  static bool _isReloading = false;

  // Reloads user balance and updates userBalanceNotifier via Supabase with throttling
  static Future<void> reloadUserBalance({bool force = false}) async {
    if (_isReloading) return;
    final now = DateTime.now();
    if (!force && _lastBalanceFetchTime != null && now.difference(_lastBalanceFetchTime!).inSeconds < 30) {
      return;
    }
    _isReloading = true;
    double resolvedBalance = userBalanceNotifier.value;
    try {
      final uid = await _resolveCurrentUserId();
      if (uid != null && uid.isNotEmpty) {
        final supaBal = await Supabase.instance.client
            .from('creator_balances')
            .select('balance_usd, available_balance_usd')
            .eq('creator_id', uid)
            .maybeSingle();

        if (supaBal != null) {
          final val = supaBal['available_balance_usd'] ?? supaBal['balance_usd'] ?? 0.0;
          resolvedBalance = double.tryParse(val.toString()) ?? 0.0;
        } else {
          // Immediately create initial balance record for this user
          await Supabase.instance.client.from('creator_balances').upsert({
            'creator_id': uid,
            'balance_usd': 0.0,
            'available_balance_usd': 0.0,
          });
        }
        _lastBalanceFetchTime = DateTime.now();
      }
    } catch (e) {
      debugPrint('[MicroJobService] Error reloading user balance: $e');
    } finally {
      _isReloading = false;
    }

    userBalanceNotifier.value = resolvedBalance;
  }

  static const String _lastCompletedTimeKey = 'xapzap_last_completed_task_time';
  static const String _lastQuickAdTimeKey = 'xapzap_last_quick_ad_time';
  static const int quickAdCooldownSeconds = 15;

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

  static Future<void> markQuickAdWatched() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_lastQuickAdTimeKey, DateTime.now().millisecondsSinceEpoch);
  }

  static Future<int> getQuickAdCooldownRemaining() async {
    final prefs = await SharedPreferences.getInstance();
    final lastTime = prefs.getInt(_lastQuickAdTimeKey) ?? 0;
    if (lastTime == 0) return 0;
    final elapsed = (DateTime.now().millisecondsSinceEpoch - lastTime) ~/ 1000;
    final remaining = quickAdCooldownSeconds - elapsed;
    return remaining > 0 ? remaining : 0;
  }

  // Reward the user and update the remote database in Supabase
  static Future<bool> rewardUser(String taskId, double rewardAmount) async {
    if (rewardAmount <= 0.0) return true;

    // 1. Mark task as completed locally (always allowed for rush gifts)
    final isNew = await _markTaskCompletedLocally(taskId);
    if (!isNew && !taskId.startsWith('video_watch_') && !taskId.startsWith('quick_ad_watch_') && !taskId.startsWith('rush_')) {
      return false;
    }

    // 2. Direct Supabase Balance Sync
    try {
      final uid = await _resolveCurrentUserId();
      if (uid != null && uid.isNotEmpty) {
        final supaBal = await Supabase.instance.client
            .from('creator_balances')
            .select('balance_usd, available_balance_usd')
            .eq('creator_id', uid)
            .maybeSingle();

        if (supaBal != null) {
          final curBal = double.tryParse((supaBal['balance_usd'] ?? 0.0).toString()) ?? 0.0;
          final curAvail = double.tryParse((supaBal['available_balance_usd'] ?? 0.0).toString()) ?? 0.0;
          await Supabase.instance.client
              .from('creator_balances')
              .update({
                'balance_usd': curBal + rewardAmount,
                'available_balance_usd': curAvail + rewardAmount,
              })
              .eq('creator_id', uid);
        } else {
          await Supabase.instance.client.from('creator_balances').upsert({
            'creator_id': uid,
            'balance_usd': rewardAmount,
            'available_balance_usd': rewardAmount,
          });
        }
      }
    } catch (e) {
      debugPrint('[MicroJobService] Supabase reward sync error: $e');
    }

    await setLastCompletedTime();
    await reloadUserBalance();
    return true;
  }

  // Deduct balance for entry fees in Supabase (e.g. Host = 1,000 pts ($0.10), Invitee = 500 pts ($0.05))
  static Future<bool> deductUserBalance(double amount) async {
    if (amount <= 0.0) return true;

    try {
      final uid = await _resolveCurrentUserId();
      if (uid != null && uid.isNotEmpty) {
        final supaBal = await Supabase.instance.client
            .from('creator_balances')
            .select('balance_usd, available_balance_usd')
            .eq('creator_id', uid)
            .maybeSingle();

        if (supaBal != null) {
          final curBal = double.tryParse((supaBal['balance_usd'] ?? 0.0).toString()) ?? 0.0;
          final curAvail = double.tryParse((supaBal['available_balance_usd'] ?? 0.0).toString()) ?? 0.0;
          final newBal = (curBal - amount).clamp(0.0, double.infinity);
          final newAvail = (curAvail - amount).clamp(0.0, double.infinity);
          await Supabase.instance.client
              .from('creator_balances')
              .update({
                'balance_usd': newBal,
                'available_balance_usd': newAvail,
              })
              .eq('creator_id', uid);
        }
      }
    } catch (e) {
      debugPrint('[MicroJobService] Supabase deduction error: $e');
    }

    await reloadUserBalance();
    return true;
  }

  // Reward a target user directly by userId in Supabase (e.g. for referrals)
  static Future<bool> rewardUserDirectly(String userId, double rewardAmount) async {
    if (rewardAmount <= 0.0 || userId.isEmpty) return true;
    try {
      final supaBal = await Supabase.instance.client
          .from('creator_balances')
          .select('balance_usd, available_balance_usd')
          .eq('creator_id', userId)
          .maybeSingle();

      if (supaBal != null) {
        final curBal = double.tryParse((supaBal['balance_usd'] ?? 0.0).toString()) ?? 0.0;
        final curAvail = double.tryParse((supaBal['available_balance_usd'] ?? 0.0).toString()) ?? 0.0;
        await Supabase.instance.client
            .from('creator_balances')
            .update({
              'balance_usd': curBal + rewardAmount,
              'available_balance_usd': curAvail + rewardAmount,
            })
            .eq('creator_id', userId);
      } else {
        await Supabase.instance.client.from('creator_balances').upsert({
          'creator_id': userId,
          'balance_usd': rewardAmount,
          'available_balance_usd': rewardAmount,
        });
      }
      return true;
    } catch (e) {
      debugPrint('Failed to reward user directly in Supabase: $e');
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

  static Future<bool> subscribeAdFree(String planName, double price, int durationDays) async {
    final currentBalance = userBalanceNotifier.value;
    if (currentBalance < price) {
      return false; // Insufficient balance
    }

    final newBalance = currentBalance - price;
    final prefs = await SharedPreferences.getInstance();
    
    // Calculate new expiry (if already active, extend from current expiry)
    final currentExpiry = prefs.getInt('ad_free_expiry_timestamp') ?? 0;
    final now = DateTime.now().millisecondsSinceEpoch;
    final baseTime = currentExpiry > now ? currentExpiry : now;
    final newExpiry = DateTime.fromMillisecondsSinceEpoch(baseTime)
        .add(Duration(days: durationDays))
        .millisecondsSinceEpoch;

    await prefs.setInt('ad_free_expiry_timestamp', newExpiry);
    await prefs.setString('ad_free_active_plan', planName);

    userBalanceNotifier.value = newBalance;
    try {
      final user = await BackendService.getCurrentUser();
      if (user != null) {
        await Supabase.instance.client
            .from('profiles')
            .update({
              'earnings_balance': newBalance,
              'ad_free_expiry': DateTime.fromMillisecondsSinceEpoch(newExpiry).toIso8601String(),
            })
            .eq('id', user.$id);
      }
    } catch (e) {
      debugPrint('Error updating ad-free plan in Supabase: $e');
    }
    return true;
  }

  static Future<bool> subscribeAdFreeViaPlayStore(String planName, double price, int durationDays) async {
    final prefs = await SharedPreferences.getInstance();
    final currentExpiry = prefs.getInt('ad_free_expiry_timestamp') ?? 0;
    final now = DateTime.now().millisecondsSinceEpoch;
    final baseTime = currentExpiry > now ? currentExpiry : now;
    final newExpiry = DateTime.fromMillisecondsSinceEpoch(baseTime)
        .add(Duration(days: durationDays))
        .millisecondsSinceEpoch;

    await prefs.setInt('ad_free_expiry_timestamp', newExpiry);
    await prefs.setString('ad_free_active_plan', planName);

    try {
      final user = await BackendService.getCurrentUser();
      if (user != null) {
        await Supabase.instance.client
            .from('profiles')
            .update({
              'ad_free_expiry': DateTime.fromMillisecondsSinceEpoch(newExpiry).toIso8601String(),
            })
            .eq('id', user.$id);
      }
    } catch (e) {
      debugPrint('Error updating ad-free Play Store plan in Supabase: $e');
    }
    return true;
  }
}
