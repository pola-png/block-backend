import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'backend_service.dart';
import '../screens/level_upgrades_screen.dart';

class UserPlanService {
  UserPlanService._();

  /// Checks if the current user has an active subscription plan (Ad-Free Pass, Level Plan, or Admin).
  static Future<bool> isSubscriberOrAdmin() async {
    try {
      final isAdmin = await BackendService.isCurrentUserAdmin();
      if (isAdmin) return true;

      final prefs = await SharedPreferences.getInstance();
      final expiry = prefs.getInt('ad_free_expiry_timestamp') ?? 0;
      final now = DateTime.now().millisecondsSinceEpoch;
      if (expiry > now) {
        return true;
      }

      // Check database profiles for level or ad-free expiry
      final user = Supabase.instance.client.auth.currentUser;
      if (user != null) {
        final profileRes = await Supabase.instance.client
            .from('profiles')
            .select('ad_free_expiry, user_level, is_admin')
            .eq('id', user.id)
            .maybeSingle();

        if (profileRes != null) {
          if (profileRes['is_admin'] == true) return true;
          final userLevel = profileRes['user_level'];
          if (userLevel != null && (int.tryParse(userLevel.toString()) ?? 0) >= 1) {
            return true;
          }
          if (profileRes['ad_free_expiry'] != null) {
            final dbExpiryStr = profileRes['ad_free_expiry'] as String;
            final dbExpiryDt = DateTime.tryParse(dbExpiryStr);
            if (dbExpiryDt != null && dbExpiryDt.millisecondsSinceEpoch > now) {
              final dbExpiryTs = dbExpiryDt.millisecondsSinceEpoch;
              await prefs.setInt('ad_free_expiry_timestamp', dbExpiryTs);
              return true;
            }
          }
        }
      }
    } catch (e) {
      debugPrint('[UserPlanService] Error checking subscription plan: $e');
    }
    return false;
  }

  /// Verifies active subscription before posting media (images/videos).
  /// If not subscribed, prompts the user to upgrade with a direct navigation to LevelUpgradesScreen.
  static Future<bool> ensureSubscriberToPostMedia(
    BuildContext context, {
    String mediaType = 'media',
  }) async {
    final hasActivePlan = await isSubscriberOrAdmin();
    if (hasActivePlan) return true;

    if (context.mounted) {
      await showDialog<void>(
        context: context,
        barrierDismissible: true,
        builder: (ctx) => MediaSubscriptionRequiredDialog(mediaType: mediaType),
      );
    }
    return false;
  }
}

class MediaSubscriptionRequiredDialog extends StatelessWidget {
  final String mediaType;

  const MediaSubscriptionRequiredDialog({
    super.key,
    this.mediaType = 'media',
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return AlertDialog(
      backgroundColor: isDark ? const Color(0xFF1E1E28) : Colors.white,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      contentPadding: const EdgeInsets.fromLTRB(24, 24, 24, 16),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Premium badge icon
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [Color(0xFFFF8A00), Color(0xFFE52E71)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                  color: const Color(0xFFE52E71).withOpacity(0.35),
                  blurRadius: 18,
                  offset: const Offset(0, 6),
                ),
              ],
            ),
            child: const Icon(
              Icons.stars_rounded,
              color: Colors.white,
              size: 40,
            ),
          ),
          const SizedBox(height: 18),

          Text(
            'Plan Subscription Required',
            textAlign: TextAlign.center,
            style: theme.textTheme.titleLarge?.copyWith(
              fontWeight: FontWeight.w800,
              fontSize: 20,
            ),
          ),
          const SizedBox(height: 10),

          Text(
            'Posting $mediaType (images, videos, reels, and episodes) is exclusively available to members with an active Plan Subscription.\n\nSubscribe to an Ad-Free Pass or Level Upgrade to unlock unlimited media uploads!',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 14,
              color: isDark ? Colors.white70 : Colors.black87,
              height: 1.45,
            ),
          ),
          const SizedBox(height: 24),

          // Upgrade Button
          SizedBox(
            width: double.infinity,
            height: 48,
            child: ElevatedButton(
              onPressed: () {
                Navigator.of(context).pop();
                Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const LevelUpgradesScreen()),
                );
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF1DA1F2),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
                elevation: 3,
              ),
              child: const Text(
                'View Plans & Upgrade 🚀',
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                  fontSize: 15,
                ),
              ),
            ),
          ),
          const SizedBox(height: 8),

          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text(
              'Not Now',
              style: TextStyle(
                color: isDark ? Colors.white54 : Colors.black54,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
