import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:crypto/crypto.dart';
import '../models/database_models.dart' as models;
import '../models/database_models.dart' show Query, ID, DatabaseException, Client, Account, Functions, Storage, InputFile, Permission, Role, Messaging, enums;
import 'package:flutter/foundation.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../config/environment.dart';
import '../models/status.dart';
import '../models/app_notification.dart';
import 'chat_message_cache.dart';
import 'chat_preview_cache.dart';
import 'profile_preview_cache.dart';
import 'feed_exposure_service.dart';
import 'storage_service.dart';

class _FeedInterestProfile {
  final Set<String> followedAuthorIds;
  final Map<String, double> authorWeights;
  final Map<String, double> typeWeights;
  final Map<String, double> keywordWeights;

  const _FeedInterestProfile({
    required this.followedAuthorIds,
    required this.authorWeights,
    required this.typeWeights,
    required this.keywordWeights,
  });
}

class FeedPage {
  final List<models.Row> rows;
  final String? nextCursor;
  final int total;

  const FeedPage({
    required this.rows,
    required this.nextCursor,
    required this.total,
  });

  models.RowList toRowList() {
    return models.RowList(total: total, rows: rows);
  }
}

class BackendService {
  static final ValueNotifier<bool> adminModeOverride = ValueNotifier<bool>(true);
  static const String endpoint = Environment.supabaseUrl;
  static const String projectId = 'supabase';
  static const String databaseId = 'xapzap_db';

  // Collections
  static const String postsCollectionId = 'posts';
  static const String commentsCollectionId = 'comments';
  static const String profilesCollectionId = 'profiles';
  static const String followsCollectionId = 'follows';
  static const String blocksCollectionId = 'blocks';
  static const String likesCollectionId = 'likes';
  static const String commentLikesCollectionId = 'commentLikes';
  static const String repostsCollectionId = 'reposts';
  static const String reportsCollectionId = 'reports';
  static const String savesCollectionId = 'saves';
  static const String chatsCollectionId = 'chats';
  static const String chatDevicesCollectionId = 'chat_devices';
  static const String messagingTargetsCollectionId = 'messaging_targets';
  static const String messagesCollectionId = 'messages';
  static const String statusesCollectionId = 'statuses';
  static const String notificationsCollectionId = 'notifications';
  static const String postBoostsCollectionId = 'post_boosts';
  static const String newsCollectionId = 'news';
  static const String adRevenueCollectionId = 'ad_revenue_events';
  static const String adUnitRevenueDailyCollectionId = 'ad_unit_revenue_daily';
  static const String adImpressionsCollectionId = 'ad_impressions';
  static const String creatorEarningsDailyCollectionId =
      'creator_earnings_daily';
  static const String creatorBalancesCollectionId = 'creator_balances';
  static const String creatorPayoutsCollectionId = 'creator_payouts';
  static const String referralsCollectionId = 'referrals';
  static const String supportRequestsCollectionId = 'support_requests';

  // Buckets
  // Appwrite bucket ID for media uploads
  static const String mediaBucketId = '6915baaa00381391d7b2';

  static late Client _client;
  static late Account _account;
  static late Functions _functions;
  static late TablesDB _tables;
  static late Storage _storage;
  static late Realtime _realtime;

  static Realtime get realtime => _realtime;

  static Account get account => _account;

  static Client get client => _client;

  // Follow graph change notifier
  static final ValueNotifier<int> followingVersion = ValueNotifier<int>(0);

  static Future<void> initialize() async {
    _client = Client().setEndpoint(endpoint).setProject(projectId);
    _account = Account(_client);
    _functions = Functions(_client);
    _tables = TablesDB(_client);
    _storage = Storage(_client);
    _realtime = Realtime(_client);

    try {
      final prefs = await SharedPreferences.getInstance();
      _isLoggedInCache = prefs.getBool('is_logged_in') ?? false;
      final userJson = prefs.getString('cached_user_json');
      if (userJson != null) {
        final map = jsonDecode(userJson) as Map<String, dynamic>;
        _currentUserCache = models.User.fromMap(map);
      }

      // If we have a live Supabase Auth session, let that override the cache immediately
      final supabaseUser = Supabase.instance.client.auth.currentUser;
      if (supabaseUser != null) {
        _currentUserCache = _userFromSupabaseUser(supabaseUser);
        _isLoggedInCache = true;
      }

      final profileJson = prefs.getString('cached_profile_json');
      if (profileJson != null && _currentUserCache != null) {
        final map = jsonDecode(profileJson) as Map<String, dynamic>;
        final profile = models.Row.fromMap(map);
        _profileCache[_currentUserCache!.$id] = profile;
        _isBannedCache = profile.data['isBanned'] == true;
        _isAdminCache = profile.data['isAdmin'] == true;
      }
    } catch (_) {}
  }

  static bool _isLoggedInCache = false;
  static bool? _isAdminCache;
  static bool? _isBannedCache;
  static bool _admobAutoSyncStartedThisSession = false;

  /// In-memory session cache — avoids one HTTP round-trip per card per build.
  static models.User? _currentUserCache;
  static Future<models.User?>? _getCurrentUserFuture;

  static bool isLoggedInSync() {
    return _isLoggedInCache || _currentUserCache != null;
  }

  static models.User? getCurrentUserSync() {
    return _currentUserCache;
  }

  static bool isUserBannedSync() {
    return _isBannedCache == true;
  }

  /// In-memory follow-state cache keyed by "followerId:followeeId".
  static final Map<String, bool> _followingCache = <String, bool>{};

  static final Map<String, bool> _batchLikesCache = {};
  static final Map<String, bool> _batchSavesCache = {};
  static final Map<String, bool> _batchRepostsCache = {};

  static Future<void> prefetchUserReactionsAndFollows({
    required String userId,
    required List<String> postIds,
    required List<String> authorIds,
  }) async {
    if (userId.isEmpty) return;
    final uniquePostIds = postIds.where((id) => id.isNotEmpty).toSet().toList();
    final uniqueAuthorIds = authorIds.where((id) => id.isNotEmpty && id != userId).toSet().toList();

    if (uniquePostIds.isEmpty && uniqueAuthorIds.isEmpty) return;

    final futures = <Future<dynamic>>[];

    if (uniquePostIds.isNotEmpty) {
      // 1. Prefetch Likes
      futures.add(() async {
        try {
          final res = await _tables.listRows(
            databaseId: databaseId,
            tableId: likesCollectionId,
            queries: [
              Query.equal('userId', userId),
              Query.equal('postId', uniquePostIds),
              Query.limit(uniquePostIds.length),
            ],
          );
          final likedIds = res.rows.map((r) => r.data['postId'] as String?).whereType<String>().toSet();
          for (final pid in uniquePostIds) {
            _batchLikesCache[pid] = likedIds.contains(pid);
          }
        } catch (_) {}
      }());

      // 2. Prefetch Saves
      futures.add(() async {
        try {
          final res = await _tables.listRows(
            databaseId: databaseId,
            tableId: savesCollectionId,
            queries: [
              Query.equal('userId', userId),
              Query.equal('postId', uniquePostIds),
              Query.limit(uniquePostIds.length),
            ],
          );
          final savedIds = res.rows.map((r) => r.data['postId'] as String?).whereType<String>().toSet();
          for (final pid in uniquePostIds) {
            _batchSavesCache[pid] = savedIds.contains(pid);
          }
        } catch (_) {}
      }());

      // 3. Prefetch Reposts
      futures.add(() async {
        try {
          final res = await _tables.listRows(
            databaseId: databaseId,
            tableId: repostsCollectionId,
            queries: [
              Query.equal('userId', userId),
              Query.equal('postId', uniquePostIds),
              Query.limit(uniquePostIds.length),
            ],
          );
          final repostedIds = res.rows.map((r) => r.data['postId'] as String?).whereType<String>().toSet();
          for (final pid in uniquePostIds) {
            _batchRepostsCache[pid] = repostedIds.contains(pid);
          }
        } catch (_) {}
      }());
    }

    if (uniqueAuthorIds.isNotEmpty) {
      // 4. Prefetch Followings
      futures.add(() async {
        try {
          final res = await _tables.listRows(
            databaseId: databaseId,
            tableId: followsCollectionId,
            queries: [
              Query.equal('followerId', userId),
              Query.equal('followeeId', uniqueAuthorIds),
              Query.limit(uniqueAuthorIds.length),
            ],
          );
          final followingAuthorIds = res.rows.map((r) => r.data['followeeId'] as String?).whereType<String>().toSet();
          for (final aid in uniqueAuthorIds) {
            _followingCache['$userId:$aid'] = followingAuthorIds.contains(aid);
          }
        } catch (_) {}
      }());
    }

    final allAuthorIds = {...authorIds, userId}.where((id) => id.isNotEmpty).toList();
    if (allAuthorIds.isNotEmpty) {
      // 5. Prefetch Creator Profiles
      futures.add(() async {
        try {
          final res = await _tables.listRows(
            databaseId: databaseId,
            tableId: profilesCollectionId,
            queries: [
              Query.equal('userId', allAuthorIds),
              Query.limit(allAuthorIds.length),
            ],
          );
          for (final row in res.rows) {
            final uid = row.data['userId'] as String? ?? row.$id;
            if (uid.isNotEmpty) {
              _profileCache[uid] = row;
              _cacheProfilePreviewFromData(row.$id, row.data);
            }
          }
        } catch (_) {}
      }());
    }

    await Future.wait(futures);
  }

  static bool? isPostLikedBySync(String postId) {
    return _batchLikesCache[postId];
  }

  static bool? isPostSavedBySync(String postId) {
    return _batchSavesCache[postId];
  }

  static bool? isPostRepostedBySync(String postId) {
    return _batchRepostsCache[postId];
  }

  static bool? isFollowingSync(String followerId, String followeeId) {
    return _followingCache['$followerId:$followeeId'];
  }

  static void _resetAuthCaches() {
    _isAdminCache = null;
    _isBannedCache = null;
    _currentUserCache = null;
    _getCurrentUserFuture = null;
    _isLoggedInCache = false;
    _followingCache.clear();
    unawaited(_clearPrefsCache());
  }

  static Future<models.User> getAccount() {
    return _account.get();
  }

  static bool _isTransientUploadError(Object error) {
    final text = error.toString().toLowerCase();
    return text.contains('broken pipe') ||
        text.contains('connection reset by peer') ||
        text.contains('connection aborted') ||
        text.contains('socketexception') ||
        text.contains('clientexception') ||
        text.contains('timed out') ||
        text.contains('timeout');
  }



  // Generic TablesDB helpers
  static Future<models.Row> getRow(String tableId, String rowId) {
    return _tables.getRow(
      databaseId: databaseId,
      tableId: tableId,
      rowId: rowId,
    );
  }

  static Future<models.Row> updateRow(
    String tableId,
    String rowId,
    Map<String, dynamic> data,
  ) {
    return _tables.updateRow(
      databaseId: databaseId,
      tableId: tableId,
      rowId: rowId,
      data: data,
    );
  }

  static Future<String> getChatId(String userId1, String userId2) async {
    final sortedIds = [userId1, userId2]..sort();
    // Appwrite rowId max length is 36 chars; hash the pair to keep it short yet deterministic.
    final chatId = _hashId(sortedIds.join('_'));
    final memberIdsValue = sortedIds.join(',');

    try {
      await _tables.getRow(
        databaseId: databaseId,
        tableId: chatsCollectionId,
        rowId: chatId,
      );
    } catch (e) {
      if (e is DatabaseException && e.code == 404) {
        await _tables.createRow(
          databaseId: databaseId,
          tableId: chatsCollectionId,
          rowId: chatId,
          data: {
            'chatId': chatId,
            // memberIds is a single string column; store as comma-separated list.
            'memberIds': memberIdsValue,
            'createdAt': DateTime.now().toIso8601String(),
          },
        );
      } else {
        rethrow;
      }
    }
    try {
      await _tables.updateRow(
        databaseId: databaseId,
        tableId: chatsCollectionId,
        rowId: chatId,
        data: {'memberIds': memberIdsValue},
      );
    } catch (_) {}
    return chatId;
  }

  static String _hashId(String input) {
    // 32-char md5 hex fits Appwrite UID requirements (a-z, A-Z, 0-9, underscore) and length <= 36.
    return md5.convert(utf8.encode(input)).toString();
  }

  // Auth
  static Future<models.User> signUp(
    String email,
    String password,
    String username, {
    String? displayName,
    required DateTime dateOfBirth,
    String? country,
    required String gender,
    String? referralCode,
  }) async {
    final safeDisplayName = (displayName ?? '').trim();
    final safeCountry = (country ?? '').trim();
    final safeGender = gender.trim();

    // 1. Sign up the user in Supabase Auth
    final authRes = await Supabase.instance.client.auth.signUp(
      email: email,
      password: password,
      data: {
        'username': username,
        'displayName': safeDisplayName.isEmpty ? username : safeDisplayName,
      },
    );

    final user = authRes.user;
    if (user == null) {
      throw const AuthException('Signup failed: user is null');
    }

    // 2. Create the profile row in the database immediately using the user's UUID
    try {
      await Supabase.instance.client.from('profiles').insert({
        'id': user.id,
        'username': username,
        'display_name': safeDisplayName.isEmpty ? username : safeDisplayName,
        'gender': safeGender,
        'country': safeCountry,
        'date_of_birth': dateOfBirth.toUtc().toIso8601String(),
        'is_admin': false,
        'is_banned': false,
      });
    } catch (dbErr) {
      debugPrint('Warning: DB profile insertion error: $dbErr');
    }

    // 3. Log them in or check session
    if (authRes.session == null) {
      throw const AuthException('Verification required: Please check your email to confirm your registration.');
    }

    final createdUser = models.User.fromMap({
      '\$id': user.id,
      '\$createdAt': user.createdAt,
      '\$updatedAt': user.updatedAt ?? user.createdAt,
      'name': safeDisplayName.isEmpty ? username : safeDisplayName,
      'email': email,
      'phone': '',
      'status': true,
      'emailVerification': true,
      'phoneVerification': true,
      'prefs': <String, dynamic>{},
      'accessedAt': DateTime.now().toIso8601String(),
      'labels': <String>[],
      'mfa': false,
      'passwordUpdate': DateTime.now().toIso8601String(),
      'registration': DateTime.now().toIso8601String(),
      'targets': <dynamic>[],
    });

    _currentUserCache = createdUser;
    unawaited(_saveUserToPrefs(createdUser));
    _isLoggedInCache = true;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('is_logged_in', true);
    } catch (_) {}

    try {
      final profile = await getProfileByUserId(createdUser.$id);
      if (profile != null) {
        _profileCache[createdUser.$id] = profile;
        unawaited(_saveProfileToPrefs(profile));
        final rawBanned = profile.data['isBanned'];
        _isBannedCache = rawBanned is bool
            ? rawBanned
            : (rawBanned is String ? (rawBanned.toLowerCase() == 'true') : false);
        _isAdminCache = profile.data['isAdmin'] == true;
      } else {
        _isBannedCache = false;
        _isAdminCache = false;
      }
    } catch (_) {
      _isBannedCache = false;
      _isAdminCache = false;
    }

    final safeReferralCode = referralCode?.trim() ?? '';
    if (safeReferralCode.isNotEmpty) {
      try {
        final referrerProfile = await getProfileByUsername(safeReferralCode);
        final referrerUserId = (referrerProfile?.data['userId'] as String? ??
                referrerProfile?.$id ??
                '')
            .trim();

        if (referrerUserId.isNotEmpty && referrerUserId != createdUser.$id) {
          final alreadyFollowing =
              await isFollowing(createdUser.$id, referrerUserId);
          if (!alreadyFollowing) {
            await _tables.createRow(
              databaseId: databaseId,
              tableId: followsCollectionId,
              rowId: ID.unique(),
              data: <String, dynamic>{
                'followerId': createdUser.$id,
                'followeeId': referrerUserId,
                'followedAt': DateTime.now().toIso8601String(),
                'status': 'referral',
                'notificationEnabled': true,
              },
            );
          }
        }
      } catch (_) {}
    }

    return createdUser;
  }

  /// Wraps a Supabase [User] into the [models.User] shape expected by the app.
  static models.User _userFromSupabaseUser(User u) {
    final meta = u.userMetadata ?? {};
    final displayName = (meta['displayName'] as String? ?? '').trim();
    final username = (meta['username'] as String? ?? '').trim();
    return models.User.fromMap({
      '\$id': u.id,
      '\$createdAt': u.createdAt,
      '\$updatedAt': u.updatedAt ?? u.createdAt,
      'name': displayName.isNotEmpty ? displayName : username,
      'email': u.email ?? '',
      'phone': u.phone ?? '',
      'status': true,
      'emailVerification': u.emailConfirmedAt != null,
      'phoneVerification': false,
      'prefs': <String, dynamic>{},
      'accessedAt': DateTime.now().toIso8601String(),
      'labels': <String>[],
      'mfa': false,
      'passwordUpdate': DateTime.now().toIso8601String(),
      'registration': u.createdAt,
      'targets': <dynamic>[],
    });
  }

  static Future<models.Session> signIn(String email, String password) async {
    // Sign in via Supabase Auth only.
    final authRes = await Supabase.instance.client.auth.signInWithPassword(
      email: email,
      password: password,
    );
    final supabaseUser = authRes.user;
    if (supabaseUser == null) {
      throw const AuthException('Sign in failed: no user returned.');
    }

    final user = _userFromSupabaseUser(supabaseUser);
    _currentUserCache = user;
    _isLoggedInCache = true;
    unawaited(_saveUserToPrefs(user));
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('is_logged_in', true);
    } catch (_) {}

    final profile = await getProfileByUserId(user.$id);
    if (profile != null) {
      _profileCache[user.$id] = profile;
      unawaited(_saveProfileToPrefs(profile));
      final rawBanned = profile.data['isBanned'];
      _isBannedCache = rawBanned is bool
          ? rawBanned
          : (rawBanned is String ? rawBanned.toLowerCase() == 'true' : false);
      _isAdminCache = profile.data['isAdmin'] == true;
    } else {
      _isBannedCache = false;
      _isAdminCache = false;
    }

    // Return a dummy models.Session (callers only check it's non-null)
    return models.Session.fromMap({
      '\$id': authRes.session?.accessToken ?? '',
      '\$createdAt': DateTime.now().toIso8601String(),
      'userId': user.$id,
      'expire': authRes.session?.expiresAt?.toString() ?? '',
      'provider': 'email',
      'providerUid': user.email,
      'providerAccessToken': authRes.session?.accessToken ?? '',
      'ip': '',
      'osCode': '',
      'osName': '',
      'osVersion': '',
      'clientType': '',
      'clientCode': '',
      'clientName': '',
      'clientVersion': '',
      'clientEngine': '',
      'clientEngineVersion': '',
      'deviceName': '',
      'deviceBrand': '',
      'deviceModel': '',
      'countryCode': '',
      'countryName': '',
      'current': true,
      'factors': <dynamic>[],
      'secret': '',
      'mfaUpdatedAt': '',
    });
  }

  static Future<bool> emailExists(String email) async {
    // Supabase client SDK does not provide a public method to check if an email exists for security reasons.
    // We return true here to let signIn proceed and handle user existence natively.
    return true;
  }

  static Future<void> signInWithGoogle() async {
    await Supabase.instance.client.auth.signInWithOAuth(
      OAuthProvider.google,
      redirectTo: kIsWeb ? null : 'xapzap://login-callback',
    );
  }

  static Future<void> sendPasswordRecovery(String email) async {
    await Supabase.instance.client.auth.resetPasswordForEmail(
      email.trim(),
      redirectTo: 'xapzap://reset-password',
    );
  }

  static Future<void> completePasswordRecovery({
    required String userId,
    required String secret,
    required String password,
  }) async {
    // In Supabase, the password reset is completed by updating the user attributes
    // on the currently authenticated session (which is established by the deep link).
    await Supabase.instance.client.auth.updateUser(
      UserAttributes(password: password),
    );
  }

  static Future<void> signOut() async {
    _resetAuthCaches();
    ChatMessageCache.clearAll();
    ChatPreviewCache.clearAll();
    ProfilePreviewCache.clearAll();
    try {
      await Supabase.instance.client.auth.signOut();
    } catch (_) {}
  }

  static Future<void> deleteCurrentAccount() async {
    final user = await getCurrentUser();
    if (user == null) {
      throw StateError('User must be signed in to delete their account.');
    }

    try {
      // 1. Delete profile row first
      await Supabase.instance.client.from('profiles').delete().eq('id', user.$id);
    } catch (_) {}

    try {
      // 2. Call optional delete_user RPC trigger if defined
      await Supabase.instance.client.rpc('delete_user');
    } catch (_) {}

    await signOut();
  }

  static Future<Map<String, dynamic>?> executeBlockFilterFunction({
    required String path,
    Map<String, dynamic>? payload,
  }) async {
    final functionId =
        dotenv.env['BLOCK_FILTER_FUNCTION_ID']?.trim() ?? 'default_function';
    if (functionId.isEmpty) {
      throw StateError(
        'BLOCK_FILTER_FUNCTION_ID is missing from .env.',
      );
    }

    final execution = await _functions.createExecution(
      functionId: functionId,
      path: path,
      method: enums.ExecutionMethod.pOST,
      body: jsonEncode(payload ?? const <String, dynamic>{}),
    );
    if (execution.responseBody.isEmpty) return null;
    try {
      final decoded = jsonDecode(execution.responseBody);
      return decoded is Map<String, dynamic> ? decoded : null;
    } catch (_) {
      return null;
    }
  }

  static Future<Map<String, dynamic>?> syncAdmobRevenue({
    String? date,
    bool allocate = true,
  }) async {
    final payload = <String, dynamic>{
      'allocate': allocate,
      if (date != null && date.trim().isNotEmpty) 'date': date.trim(),
    };
    try {
      payload['userJwt'] = (await _account.createJWT()).jwt;
    } catch (_) {}
    final syncSecret = dotenv.env['XAPZAP_ADMOB_SYNC_SECRET']?.trim();
    if (syncSecret != null && syncSecret.isNotEmpty) {
      payload['syncSecret'] = syncSecret;
    }
    return executeBlockFilterFunction(
      path: '/v1/admin/admob/sync',
      payload: payload,
    );
  }

  static Future<void> maybeAutoSyncAdmobRevenue() async {
    if (_admobAutoSyncStartedThisSession) return;

    final user = await getCurrentUser();
    if (user == null) return;
    _admobAutoSyncStartedThisSession = true;

    final prefs = await SharedPreferences.getInstance();
    final todayKey = DateTime.now().toUtc().toIso8601String().substring(0, 10);
    final lastSyncedDay = prefs.getString('admob_last_auto_sync_day');
    if (lastSyncedDay == todayKey) return;

    try {
      await syncAdmobRevenue();
      await prefs.setString('admob_last_auto_sync_day', todayKey);
    } catch (_) {
      // Silent by design: this runs in the background after login.
    }
  }

  static Future<models.User?> getCurrentUser() async {
    // Try to get live Supabase Auth session first
    final supabaseUser = Supabase.instance.client.auth.currentUser;
    if (supabaseUser != null) {
      final user = _userFromSupabaseUser(supabaseUser);
      _currentUserCache = user;
      unawaited(_saveUserToPrefs(user));
      return user;
    }

    if (_currentUserCache != null) return _currentUserCache;
    if (_getCurrentUserFuture != null) return _getCurrentUserFuture;

    _getCurrentUserFuture = () async {
      try {
        final activeUser = Supabase.instance.client.auth.currentUser;
        if (activeUser != null) {
          final user = _userFromSupabaseUser(activeUser);
          _currentUserCache = user;
          unawaited(_saveUserToPrefs(user));
          return user;
        }
        return null;
      } catch (_) {
        return null;
      } finally {
        _getCurrentUserFuture = null;
      }
    }();

    return _getCurrentUserFuture;
  }

  static Future<void> _saveUserToPrefs(models.User user) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('cached_user_json', jsonEncode(_userToMap(user)));
    } catch (_) {}
  }

  static Future<void> _saveProfileToPrefs(models.Row profile) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('cached_profile_json', jsonEncode(_rowToMap(profile)));
    } catch (_) {}
  }

  static Future<void> _clearPrefsCache() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove('cached_user_json');
      await prefs.remove('cached_profile_json');
      await prefs.remove('is_logged_in');
    } catch (_) {}
  }

  static Map<String, dynamic> _userToMap(models.User user) {
    return <String, dynamic>{
      '\$id': user.$id,
      '\$createdAt': user.$createdAt,
      '\$updatedAt': user.$updatedAt,
      'name': user.name,
      'registration': user.registration,
      'status': user.status,
      'labels': user.labels,
      'passwordUpdate': user.passwordUpdate,
      'email': user.email,
      'phone': user.phone,
      'emailVerification': user.emailVerification,
      'phoneVerification': user.phoneVerification,
      'accessedAt': user.accessedAt,
    };
  }

  static Map<String, dynamic> _rowToMap(models.Row row) {
    return <String, dynamic>{
      '\$id': row.$id,
      '\$sequence': row.$sequence,
      '\$tableId': row.$tableId,
      '\$databaseId': row.$databaseId,
      '\$createdAt': row.$createdAt,
      '\$updatedAt': row.$updatedAt,
      '\$permissions': row.$permissions,
      'data': row.data,
    };
  }

  static Future<void> validateSessionAndStatus({
    required Function(bool isAuthenticated, bool isBanned) onCompleted,
  }) async {
    try {
      final freshUser = await _account.get();
      _currentUserCache = freshUser;
      await _saveUserToPrefs(freshUser);
      _isLoggedInCache = true;
      try {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setBool('is_logged_in', true);
      } catch (_) {}

      final freshProfile = await getProfileByUserId(freshUser.$id);
      var isBanned = false;
      if (freshProfile != null) {
        _profileCache[freshUser.$id] = freshProfile;
        await _saveProfileToPrefs(freshProfile);
        final rawBanned = freshProfile.data['isBanned'];
        isBanned = rawBanned is bool
            ? rawBanned
            : (rawBanned is String ? (rawBanned.toLowerCase() == 'true') : false);
        _isBannedCache = isBanned;
        _isAdminCache = freshProfile.data['isAdmin'] == true;
      }
      onCompleted(true, isBanned);
    } catch (e) {
      var isSessionExpired = false;
      if (e is DatabaseException) {
        if (e.code == 401 || e.code == 403) {
          isSessionExpired = true;
        }
      } else {
        final errString = e.toString().toLowerCase();
        if (errString.contains('unauthorized') ||
            errString.contains('session_not_found') ||
            errString.contains('session not found')) {
          isSessionExpired = true;
        }
      }

      if (isSessionExpired) {
        _resetAuthCaches();
        await _clearPrefsCache();
        onCompleted(false, false);
      } else {
        // Transient network error or server error: do not log the user out
        onCompleted(true, _isBannedCache == true);
      }
    }
  }



  static String _stringValue(dynamic raw) {
    return raw == null ? '' : raw.toString().trim();
  }



  static Future<bool> isCurrentUserAdmin() async {
    if (!adminModeOverride.value) return false;
    if (_isAdminCache != null) return _isAdminCache!;
    final user = await getCurrentUser();
    if (user == null) {
      _isAdminCache = false;
      return false;
    }
    try {
      final prof = await getProfileByUserId(user.$id);
      final raw = prof?.data['isAdmin'];
      final val = raw is bool
          ? raw
          : (raw is String ? (raw.toLowerCase() == 'true') : false);
      _isAdminCache = val;
      return val;
    } catch (_) {
      _isAdminCache = false;
      return false;
    }
  }

  static Future<bool> isUserBanned(String userId) async {
    if (userId.isEmpty) return false;
    try {
      final prof = await getProfileByUserId(userId);
      final raw = prof?.data['isBanned'];
      if (raw is bool) return raw;
      if (raw is String) {
        final lower = raw.toLowerCase();
        return lower == 'true' || lower == '1' || lower == 'yes';
      }
      return false;
    } catch (_) {
      return false;
    }
  }

  static Future<bool> isCurrentUserBanned() async {
    if (_isBannedCache != null) return _isBannedCache!;
    final user = await getCurrentUser();
    if (user == null) {
      _isBannedCache = false;
      return false;
    }
    final banned = await isUserBanned(user.$id);
    _isBannedCache = banned;
    return banned;
  }

  // Admin helpers
  static Future<models.RowList> listProfiles({
    int limit = 50,
    String? cursor,
  }) async {
    final queries = <String>[
      Query.orderAsc('displayName'),
      Query.limit(limit),
      if (cursor != null) Query.cursorAfter(cursor),
    ];
    return _tables.listRows(
      databaseId: databaseId,
      tableId: profilesCollectionId,
      queries: queries,
    );
  }

  static Future<void> setAdminFlag(String userId, bool isAdmin) async {
    await _tables.updateRow(
      databaseId: databaseId,
      tableId: profilesCollectionId,
      rowId: userId,
      data: {'isAdmin': isAdmin},
    );
    if (_isAdminCache != null) {
      // If we toggled ourselves, reset cache.
      final me = await getCurrentUser();
      if (me != null && me.$id == userId) {
        _resetAuthCaches();
      }
    }
  }

  // Generic docs (TablesDB)
  static Future<models.Row> createDocument(
    String tableId,
    Map<String, dynamic> data, {
    List<String>? permissions,
  }) async {
    final me = await getCurrentUser();
    permissions ??= me != null
        ? [Permission.read(Role.any()), Permission.write(Role.user(me.$id))]
        : [Permission.read(Role.any())];
    return _tables.createRow(
      databaseId: databaseId,
      tableId: tableId,
      rowId: ID.unique(),
      data: data,
      permissions: permissions,
    );
  }

  static Future<models.RowList> getDocuments(
    String tableId, {
    List<String>? queries,
  }) =>
      _tables.listRows(
        databaseId: databaseId,
        tableId: tableId,
        queries: queries ?? <String>[],
      );

  static Future<models.Row?> getLatestCreatorBalance(String creatorId) async {
    try {
      final res = await _tables.listRows(
        databaseId: databaseId,
        tableId: creatorBalancesCollectionId,
        queries: <String>[
          Query.equal('creatorId', creatorId),
          Query.limit(1),
        ],
      );
      return res.rows.isNotEmpty ? res.rows.first : null;
    } catch (_) {
      return null;
    }
  }

  static Future<models.RowList> fetchCreatorEarningsDaily({
    required String creatorId,
    int limit = 20,
    String? cursorId,
  }) async {
    if (creatorId.isEmpty) {
      return models.RowList(total: 0, rows: []);
    }
    return await _tables.listRows(
      databaseId: databaseId,
      tableId: creatorEarningsDailyCollectionId,
      queries: <String>[
        Query.equal('creatorId', creatorId),
        Query.orderDesc('reportDate'),
        Query.limit(limit),
        if (cursorId != null) Query.cursorAfter(cursorId),
      ],
    );
  }

  static Future<Map<String, dynamic>> fetchCreatorEarningsSummary({
    required String creatorId,
  }) async {
    if (creatorId.isEmpty) {
      return <String, dynamic>{
        'creatorEarningsUsd': 0.0,
        'referralEarningsUsd': 0.0,
        'impressions': 0,
        'rows': 0,
      };
    }

    double creatorEarningsUsd = 0;
    double referralEarningsUsd = 0;
    int impressions = 0;
    int rows = 0;
    String? cursorId;

    while (true) {
      final result = await _tables.listRows(
        databaseId: databaseId,
        tableId: creatorEarningsDailyCollectionId,
        queries: <String>[
          Query.equal('creatorId', creatorId),
          Query.orderDesc('reportDate'),
          Query.limit(100),
          if (cursorId != null) Query.cursorAfter(cursorId),
        ],
      );
      if (result.rows.isEmpty) {
        break;
      }

      for (final row in result.rows) {
        final data = row.data;
        creatorEarningsUsd += _parseDouble(data['creatorEarningsUsd']);
        referralEarningsUsd += _parseDouble(data['referralEarningsUsd']);
        impressions += _parseInt(data['impressions']);
        rows += 1;
      }

      cursorId = result.rows.last.$id;
      if (result.rows.length < 100) {
        break;
      }
    }

    return <String, dynamic>{
      'creatorEarningsUsd': creatorEarningsUsd,
      'referralEarningsUsd': referralEarningsUsd,
      'impressions': impressions,
      'rows': rows,
    };
  }

  static Future<models.RowList> fetchCreatorPayouts({
    required String creatorId,
    int limit = 20,
    String? cursorId,
  }) async {
    if (creatorId.isEmpty) {
      return models.RowList(total: 0, rows: []);
    }
    return await _tables.listRows(
      databaseId: databaseId,
      tableId: creatorPayoutsCollectionId,
      queries: <String>[
        Query.equal('creatorId', creatorId),
        Query.orderDesc('requestedAt'),
        Query.limit(limit),
        if (cursorId != null) Query.cursorAfter(cursorId),
      ],
    );
  }

  static Future<List<Map<String, dynamic>>> fetchReferralFollows(
    String userId,
  ) async {
    if (userId.isEmpty) return <Map<String, dynamic>>[];
    try {
      final result = await _tables.listRows(
        databaseId: databaseId,
        tableId: followsCollectionId,
        queries: <String>[
          Query.equal('followeeId', userId),
          Query.equal('status', 'referral'),
          Query.orderDesc('followedAt'),
          Query.limit(100),
        ],
      );

      final followerIds = result.rows
          .map((row) => (row.data['followerId'] as String?)?.trim())
          .whereType<String>()
          .where((id) => id.isNotEmpty)
          .toSet()
          .toList(growable: false);

      final profiles = await Future.wait(
        followerIds.map((id) async {
          try {
            return await getProfileByUserId(id);
          } catch (_) {
            return null;
          }
        }),
      );

      return profiles
          .whereType<models.Row>()
          .map((profile) {
            final data = profile.data;
            return <String, dynamic>{
              'userId': (data['userId'] as String? ?? profile.$id).trim(),
              'username': (data['username'] as String? ?? '').trim(),
              'displayName': (data['displayName'] as String? ??
                      data['username'] as String? ??
                      'User')
                  .trim(),
              'avatarUrl': (data['avatarUrl'] as String?)?.trim(),
            };
          })
          .where((item) => (item['userId'] as String).isNotEmpty)
          .toList(growable: false);
    } catch (_) {
      return <Map<String, dynamic>>[];
    }
  }

  static Future<models.RowList> fetchSavedPosts({
    required String userId,
    int limit = 50,
  }) async {
    if (userId.isEmpty) return models.RowList(total: 0, rows: []);
    try {
      final savedRows = await _tables.listRows(
        databaseId: databaseId,
        tableId: savesCollectionId,
        queries: <String>[
          Query.equal('userId', userId),
          Query.orderDesc('createdAt'),
          Query.limit(limit),
        ],
      );

      final rows = <models.Row>[];
      for (final saveRow in savedRows.rows) {
        final postId = (saveRow.data['postId'] as String?)?.trim();
        if (postId == null || postId.isEmpty) continue;
        try {
          rows.add(await getRow(postsCollectionId, postId));
        } catch (_) {}
      }
      return models.RowList(total: rows.length, rows: rows);
    } catch (_) {
      return models.RowList(total: 0, rows: []);
    }
  }

  static double _parseDouble(dynamic value) {
    if (value == null) return 0;
    if (value is double) return value;
    if (value is int) return value.toDouble();
    return double.tryParse(value.toString()) ?? 0;
  }

  static int _parseInt(dynamic value) {
    if (value == null) return 0;
    if (value is int) return value;
    if (value is double) return value.round();
    return int.tryParse(value.toString()) ?? 0;
  }

  static Future<models.RowList> fetchAdUnitRevenueDaily({
    int limit = 20,
    String? cursorId,
  }) async {
    return await _tables.listRows(
      databaseId: databaseId,
      tableId: adUnitRevenueDailyCollectionId,
      queries: <String>[
        Query.orderDesc('reportDate'),
        Query.limit(limit),
        if (cursorId != null) Query.cursorAfter(cursorId),
      ],
    );
  }

  static Future<models.RowList> fetchAdImpressions({
    int limit = 20,
    String? cursorId,
  }) async {
    return await _tables.listRows(
      databaseId: databaseId,
      tableId: adImpressionsCollectionId,
      queries: <String>[
        Query.orderDesc('eventDate'),
        Query.limit(limit),
        if (cursorId != null) Query.cursorAfter(cursorId),
      ],
    );
  }

  static Future<models.Row> createPost(Map<String, dynamic> data) async {
    // Posts table has a required `postId` column; keep it in sync with the row ID.
    final rowId = ID.unique();
    final postType = _resolvePostType(data);
    final createdAt = (data['createdAt']?.toString().trim().isNotEmpty ?? false)
        ? data['createdAt']
        : DateTime.now().toIso8601String();
    final rawContent = (data['content'] ?? '').toString().trim();
    final rawCaption = (data['caption'] ?? rawContent).toString().trim();
    final rawTitle = (data['title'] ?? '').toString().trim();
    final shortDescription = rawContent.length <= 160
        ? rawContent
        : '${rawContent.substring(0, 157).trimRight()}...';
    final normalizedTitle =
        postType == 'video' || postType == 'news' ? rawTitle : '';
    final row = await _tables.createRow(
      databaseId: databaseId,
      tableId: postsCollectionId,
      rowId: rowId,
      data: <String, dynamic>{
        ...data,
        'createdAt': createdAt,
        'likes': data['likes'] ?? 0,
        'comments': data['comments'] ?? 0,
        'reposts': data['reposts'] ?? 0,
        'shares': data['shares'] ?? 0,
        'impressions': data['impressions'] ?? 0,
        'views': data['views'] ?? 0,
        'isBoosted': data['isBoosted'] ?? false,
        'mediaUrls': data['mediaUrls'] ?? <String>[],
        'title': normalizedTitle,
        'description': shortDescription,
        'caption': rawCaption,
        'postType': postType,
        'postId': data['postId'] ?? rowId,
      },
    );
    unawaited(_notifyNewPost(rowId: rowId, data: row.data));
    unawaited(
      Future<void>.delayed(
        const Duration(seconds: 1),
        () => processNotificationQueue(limit: 50),
      ),
    );
    return row;
  }

  static Future<void> _notifyNewPost({
    required String rowId,
    required Map<String, dynamic> data,
  }) async {
    try {
      final currentUser = await getCurrentUser();
      final profile = currentUser == null
          ? null
          : await getProfileByUserId(currentUser.$id);
      final profileData = profile?.data ?? const <String, dynamic>{};
      final actorName =
          (profileData['displayName'] as String?)?.trim().isNotEmpty == true
              ? (profileData['displayName'] as String).trim()
              : ((profileData['username'] as String?)?.trim().isNotEmpty == true
                  ? (profileData['username'] as String).trim()
                  : 'New post on XapZap');
      final actorAvatar = (profileData['avatarUrl'] as String?)?.trim() ?? '';
      final rawTitle = (data['title'] as String?)?.trim() ?? '';
      final rawBody = (data['content'] as String?)?.trim() ??
          (data['caption'] as String?)?.trim() ??
          '';
      final body = rawTitle.isNotEmpty
          ? rawTitle
          : rawBody.isNotEmpty
              ? (rawBody.length > 120
                  ? '${rawBody.substring(0, 117)}...'
                  : rawBody)
              : '$actorName posted a new update';

      await executeBlockFilterFunction(
        path: '/v1/messaging/push/send',
        payload: <String, dynamic>{
          'mode': 'topic',
          'topicId': 'all-users',
          'title': actorName,
          'body': body,
          'data': <String, dynamic>{
            'type': 'post',
            'postId': rowId,
            'creatorId': currentUser?.$id ?? '',
            if (actorAvatar.isNotEmpty) 'actorAvatar': actorAvatar,
            'actionUrl': '/post/$rowId',
          },
        },
      );
    } catch (_) {
      // Best-effort broadcast push. In-app notification rows are still handled
      // by the notification queue path.
    }
  }

  static Future<Map<String, dynamic>?> processNotificationQueue({
    int limit = 5,
  }) async {
    try {
      return await executeBlockFilterFunction(
        path: '/v1/notifications/process-queue',
        payload: <String, dynamic>{
          'limit': limit,
        },
      );
    } catch (_) {
      return null;
    }
  }

  static Future<void> _createInAppNotification({
    required String recipientUserId,
    required String title,
    required String body,
    required String type,
    String actorName = '',
    String actorAvatar = '',
    String actionUrl = '',
    String postId = '',
    String chatId = '',
    String creatorId = '',
  }) async {
    final safeRecipientUserId = recipientUserId.trim();
    if (safeRecipientUserId.isEmpty) return;

    final now = DateTime.now().toIso8601String();
    try {
      await _tables.createRow(
        databaseId: databaseId,
        tableId: notificationsCollectionId,
        rowId: ID.unique(),
        permissions: [
          Permission.read(Role.user(safeRecipientUserId)),
          Permission.write(Role.user(safeRecipientUserId)),
        ],
        data: <String, dynamic>{
          'userId': safeRecipientUserId,
          'title': title.trim().isNotEmpty ? title.trim() : 'Notification',
          'body': body.trim(),
          'type': type.trim().isNotEmpty ? type.trim() : 'generic',
          if (actorName.trim().isNotEmpty) 'actorName': actorName.trim(),
          if (actorAvatar.trim().isNotEmpty) 'actorAvatar': actorAvatar.trim(),
          if (actionUrl.trim().isNotEmpty) 'actionUrl': actionUrl.trim(),
          if (postId.trim().isNotEmpty) 'postId': postId.trim(),
          if (chatId.trim().isNotEmpty) 'chatId': chatId.trim(),
          if (creatorId.trim().isNotEmpty) 'creatorId': creatorId.trim(),
          'timestamp': now,
          'createdAt': now,
          'read': false,
        },
      );
    } catch (_) {}
  }

  static Future<void> markNotificationAsRead(String notificationId) async {
    final safeNotificationId = notificationId.trim();
    if (safeNotificationId.isEmpty) return;
    try {
      await updateRow(
        notificationsCollectionId,
        safeNotificationId,
        <String, dynamic>{'read': true},
      );
    } catch (_) {}
  }

  static Future<void> markAllNotificationsAsRead(String userId) async {
    final safeUserId = userId.trim();
    if (safeUserId.isEmpty) return;
    try {
      final res = await _tables.listRows(
        databaseId: databaseId,
        tableId: notificationsCollectionId,
        queries: <String>[
          Query.equal('userId', safeUserId),
          Query.equal('read', false),
          Query.limit(500),
        ],
      );
      for (final row in res.rows) {
        try {
          await updateRow(
            notificationsCollectionId,
            row.$id,
            <String, dynamic>{'read': true},
          );
        } catch (_) {}
      }
    } catch (_) {}
  }

  static Future<Map<String, dynamic>?> sendChatPushNotification({
    required String recipientUserId,
    required String chatId,
    required String senderUserId,
    required String senderName,
    String senderAvatar = '',
    required String body,
  }) async {
    final safeRecipientUserId = recipientUserId.trim();
    final safeChatId = chatId.trim();
    final safeSenderUserId = senderUserId.trim();
    final safeSenderName = senderName.trim();
    final safeBody = body.trim();

    if (safeRecipientUserId.isEmpty ||
        safeChatId.isEmpty ||
        safeSenderUserId.isEmpty ||
        safeSenderName.isEmpty ||
        safeBody.isEmpty) {
      return null;
    }

    try {
      await _createInAppNotification(
        recipientUserId: safeRecipientUserId,
        title: safeSenderName,
        body: safeBody,
        type: 'chat',
        actorName: safeSenderName,
        actorAvatar: senderAvatar.trim(),
        actionUrl: '/chat/$safeChatId',
        chatId: safeChatId,
        creatorId: safeSenderUserId,
      );
      return <String, dynamic>{
        'ok': true,
        'created': true,
        'userId': safeRecipientUserId,
        'chatId': safeChatId,
      };
    } catch (_) {
      return null;
    }
  }

  static Future<Map<String, dynamic>?> registerMessagingPushDevice({
    required String token,
    required bool enabled,
    String? deviceId,
    String? targetName,
    String? topicId,
  }) async {
    final user = await getCurrentUser();
    if (user == null) {
      throw StateError('User must be signed in to register push target.');
    }

    final safeDeviceId = deviceId?.trim();
    if (safeDeviceId == null || safeDeviceId.isEmpty) {
      throw StateError('Device ID is required.');
    }

    final safeToken = token.trim();
    if (safeToken.isEmpty) {
      throw StateError('Push token is required.');
    }

    final targetId = _hashId('${user.$id}:push:$safeDeviceId');
    final account = Account(_client);
    var created = false;
    var updated = false;

    try {
      await account.createPushTarget(
        targetId: targetId,
        identifier: safeToken,
        providerId:
            dotenv.env['XAPZAP_PUSH_PROVIDER_ID']?.trim().isNotEmpty == true
                ? dotenv.env['XAPZAP_PUSH_PROVIDER_ID']!.trim()
                : null,
      );
      created = true;
    } on DatabaseException catch (e) {
      if (e.code != 409) rethrow;
      await account.updatePushTarget(
        targetId: targetId,
        identifier: safeToken,
      );
      updated = true;
    }

    final rowId = _hashId('${user.$id}:push-mapping:$safeDeviceId');
    final mappingPayload = <String, dynamic>{
      'userId': user.$id,
      'targetId': targetId,
      'targetType': defaultTargetPlatform.name.toLowerCase(),
    };

    try {
      await updateRow(messagingTargetsCollectionId, rowId, mappingPayload);
    } on DatabaseException catch (e) {
      if (e.code != 404) rethrow;
      await _tables.createRow(
        databaseId: databaseId,
        tableId: messagingTargetsCollectionId,
        rowId: rowId,
        data: mappingPayload,
      );
    }

    return <String, dynamic>{
      'ok': true,
      'userId': user.$id,
      'targetId': targetId,
      'deviceId': safeDeviceId,
      'platform': defaultTargetPlatform.name,
      'enabled': enabled,
      'created': created,
      'updated': updated,
      if (topicId != null && topicId.trim().isNotEmpty) 'topicId': topicId,
    };
  }

  static Future<Map<String, dynamic>?> subscribeCurrentUserToTopic({
    required String topicId,
    String? targetId,
    String? deviceId,
  }) async {
    final user = await getCurrentUser();
    if (user == null) {
      throw StateError('User must be signed in to subscribe push topic.');
    }

    final safeTopicId = topicId.trim();
    if (safeTopicId.isEmpty) {
      throw StateError('Topic ID is required.');
    }

    String? resolvedTargetId = targetId?.trim();
    if (resolvedTargetId == null || resolvedTargetId.isEmpty) {
      final safeDeviceId = deviceId?.trim();
      if (safeDeviceId == null || safeDeviceId.isEmpty) {
        throw StateError('Target ID or device ID is required.');
      }
      final rowId = _hashId('${user.$id}:push-mapping:$safeDeviceId');
      final row = await getRow(messagingTargetsCollectionId, rowId);
      resolvedTargetId = (row.data['targetId'] as String?)?.trim();
    }

    if (resolvedTargetId == null || resolvedTargetId.isEmpty) {
      throw StateError('Target ID or device ID is required.');
    }

    final messaging = Messaging(_client);
    final subscriberId = _hashId('$safeTopicId:$resolvedTargetId:subscriber');
    var created = false;
    try {
      await messaging.createSubscriber(
        topicId: safeTopicId,
        subscriberId: subscriberId,
        targetId: resolvedTargetId,
      );
      created = true;
    } on DatabaseException catch (e) {
      if (e.code != 409) rethrow;
    }

    return <String, dynamic>{
      'ok': true,
      'userId': user.$id,
      'topicId': safeTopicId,
      'targetId': resolvedTargetId,
      'subscriberId': subscriberId,
      'created': created,
    };
  }

  static String _resolvePostType(Map<String, dynamic> data) {
    final raw = (data['postType'] ?? data['type'])?.toString().trim();
    if (raw != null && raw.isNotEmpty) {
      return raw;
    }

    final mediaUrls = data['mediaUrls'];
    final hasMedia = mediaUrls is List && mediaUrls.isNotEmpty;
    if (hasMedia) {
      return 'image';
    }
    return 'text';
  }

  // Posts
  static Future<FeedPage> fetchPostsPage({
    int limit = 20,
    String? cursorId,
    bool applyFeedRanking = false,
    int sessionSeed = 0,
  }) async {
    final queryLimit = applyFeedRanking ? limit * 5 : limit;
    final res = await _tables.listRows(
      databaseId: databaseId,
      tableId: postsCollectionId,
      queries: <String>[
        Query.orderDesc('createdAt'),
        Query.limit(queryLimit),
        if (cursorId != null) Query.cursorAfter(cursorId),
      ],
    );
    final nextCursor = res.rows.isNotEmpty ? res.rows.last.$id : null;
    if (!applyFeedRanking) {
      return FeedPage(rows: res.rows, nextCursor: nextCursor, total: res.total);
    }
    final exposureStore = await FeedExposureService.loadStore();
    final now = DateTime.now();
    final scored = List<models.Row>.from(res.rows);
    scored.sort(
      (a, b) => _homeScore(
        b,
        exposureStore,
        now,
        feedKey: 'for_you',
        sessionSeed: sessionSeed,
      ).compareTo(
        _homeScore(
          a,
          exposureStore,
          now,
          feedKey: 'for_you',
          sessionSeed: sessionSeed,
        ),
      ),
    );
    final sliced = _selectDiverseRows(
      scored,
      limit: limit,
      authorCap: 1,
      sourceCap: 1,
    );
    final deRepeated = _pushRecentRowsOutOfTop(
      sliced,
      exposureStore,
      now,
      feedKey: 'for_you',
      protectedTopSlots: 4,
      recentWindowHours: 36,
    );
    final topGuarded = _avoidRecentTopPostIds(
      deRepeated,
      exposureStore,
      feedKey: 'for_you',
    );
    return FeedPage(
      rows: _rotateTopRows(topGuarded, sessionSeed: sessionSeed, topWindow: 7),
      nextCursor: nextCursor,
      total: topGuarded.length,
    );
  }

  static Future<models.RowList> fetchPosts({
    int limit = 20,
    String? cursorId,
    bool applyFeedRanking = false,
    int sessionSeed = 0,
  }) async {
    return (await fetchPostsPage(
      limit: limit,
      cursorId: cursorId,
      applyFeedRanking: applyFeedRanking,
      sessionSeed: sessionSeed,
    ))
        .toRowList();
  }

  static Future<FeedPage> fetchForYouFeedPage({
    String? userId,
    int limit = 20,
    String? cursorId,
    int sessionSeed = 0,
  }) async {
    final sevenDaysAgo = DateTime.now().subtract(const Duration(days: 7));
    var res = await _tables.listRows(
      databaseId: databaseId,
      tableId: postsCollectionId,
      queries: <String>[
        Query.greaterThanEqual('createdAt', sevenDaysAgo.toIso8601String()),
        Query.limit(limit * 5),
        if (cursorId != null) Query.cursorAfter(cursorId),
      ],
    );
    if (res.rows.length < limit) {
      res = await _tables.listRows(
        databaseId: databaseId,
        tableId: postsCollectionId,
        queries: <String>[
          Query.limit(limit * 5),
          if (cursorId != null) Query.cursorAfter(cursorId),
        ],
      );
    }
    final nextCursor = res.rows.isNotEmpty ? res.rows.last.$id : null;

    final interestProfile = userId == null
        ? const _FeedInterestProfile(
            followedAuthorIds: <String>{},
            authorWeights: <String, double>{},
            typeWeights: <String, double>{},
            keywordWeights: <String, double>{},
          )
        : await _buildInterestProfile(userId);
    final exposureStore = await FeedExposureService.loadStore();
    final now = DateTime.now();
    final scored = List<models.Row>.from(res.rows);
    scored.sort(
      (a, b) => _forYouScore(
        b,
        interestProfile,
        exposureStore,
        now,
        feedKey: 'for_you',
        sessionSeed: sessionSeed,
      ).compareTo(
        _forYouScore(
          a,
          interestProfile,
          exposureStore,
          now,
          feedKey: 'for_you',
          sessionSeed: sessionSeed,
        ),
      ),
    );
    final sliced = _selectDiverseRows(
      scored,
      limit: limit,
      authorCap: 1,
      sourceCap: 1,
    );
    final deRepeated = _pushRecentRowsOutOfTop(
      sliced,
      exposureStore,
      now,
      feedKey: 'for_you',
      protectedTopSlots: 4,
      recentWindowHours: 36,
    );
    final topGuarded = _avoidRecentTopPostIds(
      deRepeated,
      exposureStore,
      feedKey: 'for_you',
    );
    return FeedPage(
      rows: _rotateTopRows(topGuarded, sessionSeed: sessionSeed, topWindow: 7),
      nextCursor: nextCursor,
      total: topGuarded.length,
    );
  }

  static Future<models.RowList> fetchForYouFeed({
    String? userId,
    int limit = 20,
    String? cursorId,
    int sessionSeed = 0,
  }) async {
    return (await fetchForYouFeedPage(
      userId: userId,
      limit: limit,
      cursorId: cursorId,
      sessionSeed: sessionSeed,
    ))
        .toRowList();
  }

  static Future<FeedPage> fetchWatchFeedPage({
    int limit = 20,
    String? cursorId,
    int sessionSeed = 0,
  }) async {
    final res = await _tables.listRows(
      databaseId: databaseId,
      tableId: postsCollectionId,
      queries: <String>[
        Query.equal('postType', <String>['video']),
        Query.limit(limit * 6),
        if (cursorId != null) Query.cursorAfter(cursorId),
      ],
    );
    final nextCursor = res.rows.isNotEmpty ? res.rows.last.$id : null;

    final filtered = res.rows.where((row) {
      final data = row.data;
      final postType = (data['postType'] as String? ?? '').toLowerCase();
      final mediaUrls = data['mediaUrls'];
      final hasMedia = mediaUrls is List && mediaUrls.isNotEmpty;
      return postType == 'video' &&
          ((data['videoUrl'] as String?)?.isNotEmpty == true ||
              hasMedia ||
              (data['thumbnailUrl'] as String?)?.isNotEmpty == true);
    }).toList(growable: false);

    final exposureStore = await FeedExposureService.loadStore();
    final now = DateTime.now();
    filtered.sort(
      (a, b) => _watchScore(
        b,
        exposureStore,
        now,
        feedKey: 'watch',
        sessionSeed: sessionSeed,
      ).compareTo(
        _watchScore(
          a,
          exposureStore,
          now,
          feedKey: 'watch',
          sessionSeed: sessionSeed,
        ),
      ),
    );
    final sliced = _selectDiverseRows(
      filtered,
      limit: limit,
      authorCap: 1,
      sourceCap: 1,
    );
    final deRepeated = _pushRecentRowsOutOfTop(
      sliced,
      exposureStore,
      now,
      feedKey: 'watch',
      protectedTopSlots: 4,
      recentWindowHours: 36,
    );
    final topGuarded = _avoidRecentTopPostIds(
      deRepeated,
      exposureStore,
      feedKey: 'watch',
    );
    return FeedPage(
      rows: _rotateTopRows(topGuarded, sessionSeed: sessionSeed, topWindow: 7),
      nextCursor: nextCursor,
      total: topGuarded.length,
    );
  }

  static Future<models.RowList> fetchWatchFeed({
    int limit = 20,
    String? cursorId,
    int sessionSeed = 0,
  }) async {
    return (await fetchWatchFeedPage(
      limit: limit,
      cursorId: cursorId,
      sessionSeed: sessionSeed,
    ))
        .toRowList();
  }

  static Future<FeedPage> fetchReelsFeedPage({
    int limit = 20,
    String? cursorId,
    int sessionSeed = 0,
  }) async {
    final res = await _tables.listRows(
      databaseId: databaseId,
      tableId: postsCollectionId,
      queries: <String>[
        Query.equal('postType', <String>['reel']),
        Query.limit(limit * 5),
        if (cursorId != null) Query.cursorAfter(cursorId),
      ],
    );
    final nextCursor = res.rows.isNotEmpty ? res.rows.last.$id : null;

    final exposureStore = await FeedExposureService.loadStore();
    final now = DateTime.now();
    final scored = List<models.Row>.from(res.rows);
    scored.sort(
      (a, b) => _reelScore(
        b,
        exposureStore,
        now,
        feedKey: 'reels',
        sessionSeed: sessionSeed,
      ).compareTo(
        _reelScore(
          a,
          exposureStore,
          now,
          feedKey: 'reels',
          sessionSeed: sessionSeed,
        ),
      ),
    );
    final sliced = _selectDiverseRows(
      scored,
      limit: limit,
      authorCap: 1,
      sourceCap: 1,
    );
    final deRepeated = _pushRecentRowsOutOfTop(
      sliced,
      exposureStore,
      now,
      feedKey: 'reels',
      protectedTopSlots: 4,
      recentWindowHours: 36,
    );
    final topGuarded = _avoidRecentTopPostIds(
      deRepeated,
      exposureStore,
      feedKey: 'reels',
    );
    return FeedPage(
      rows: _rotateTopRows(topGuarded, sessionSeed: sessionSeed, topWindow: 7),
      nextCursor: nextCursor,
      total: topGuarded.length,
    );
  }

  static Future<models.RowList> fetchReelsFeed({
    int limit = 20,
    String? cursorId,
    int sessionSeed = 0,
  }) async {
    return (await fetchReelsFeedPage(
      limit: limit,
      cursorId: cursorId,
      sessionSeed: sessionSeed,
    ))
        .toRowList();
  }

  static List<models.Row> _selectDiverseRows(
    List<models.Row> rows, {
    required int limit,
    required int authorCap,
    required int sourceCap,
  }) {
    final selected = <models.Row>[];
    final authorCounts = <String, int>{};
    final sourceCounts = <String, int>{};

    for (final row in rows) {
      if (selected.length >= limit) break;

      final data = row.data;
      final authorId = (data['userId'] as String?)?.trim() ?? '';
      final sourcePostId = (data['sourcePostId'] as String?)?.trim() ?? '';

      final authorCount = authorId.isEmpty ? 0 : (authorCounts[authorId] ?? 0);
      final sourceCount =
          sourcePostId.isEmpty ? 0 : (sourceCounts[sourcePostId] ?? 0);

      if ((authorId.isNotEmpty && authorCount >= authorCap) ||
          (sourcePostId.isNotEmpty && sourceCount >= sourceCap)) {
        continue;
      }

      selected.add(row);
      if (authorId.isNotEmpty) {
        authorCounts[authorId] = authorCount + 1;
      }
      if (sourcePostId.isNotEmpty) {
        sourceCounts[sourcePostId] = sourceCount + 1;
      }
    }

    if (selected.length < limit) {
      for (final row in rows) {
        if (selected.length >= limit) break;
        if (selected.contains(row)) continue;
        selected.add(row);
      }
    }

    return selected;
  }

  static List<models.Row> _rotateTopRows(
    List<models.Row> rows, {
    required int sessionSeed,
    required int topWindow,
  }) {
    if (rows.length < 2 || topWindow < 2 || sessionSeed == 0) return rows;
    final window = rows.take(topWindow).toList(growable: false);
    if (window.length < 2) return rows;
    final offset = (sessionSeed % (window.length - 1)) + 1;
    final rotated = <models.Row>[
      ...window.sublist(offset),
      ...window.sublist(0, offset),
      ...rows.skip(window.length),
    ];
    return rotated;
  }

  static List<models.Row> _pushRecentRowsOutOfTop(
    List<models.Row> rows,
    FeedExposureStore exposureStore,
    DateTime now, {
    required String feedKey,
    required int protectedTopSlots,
    required double recentWindowHours,
  }) {
    if (rows.length < 2 || protectedTopSlots <= 0) return rows;

    final topCount = protectedTopSlots.clamp(0, rows.length);
    final topRows = rows.take(topCount).toList(growable: true);
    final tailRows = rows.skip(topCount).toList(growable: true);

    for (var i = 0; i < topRows.length; i++) {
      final current = topRows[i];
      final shouldDrop = exposureStore.wasShownRecently(
        current.$id,
        feedKey,
        now,
        withinHours: recentWindowHours,
      );
      if (!shouldDrop) continue;

      final replacementIndex = tailRows.indexWhere(
        (row) => !exposureStore.wasShownRecently(
          row.$id,
          feedKey,
          now,
          withinHours: recentWindowHours,
        ),
      );
      if (replacementIndex == -1) {
        continue;
      }

      final replacement = tailRows.removeAt(replacementIndex);
      tailRows.insert(0, current);
      topRows[i] = replacement;
    }

    return <models.Row>[...topRows, ...tailRows];
  }

  static List<models.Row> _avoidRecentTopPostIds(
    List<models.Row> rows,
    FeedExposureStore exposureStore, {
    required String feedKey,
  }) {
    if (rows.length < 2) return rows;

    final blockedTopIds = exposureStore.recentTopPostIds(feedKey);
    if (blockedTopIds.isEmpty) return rows;

    final currentTop = rows.first;
    if (!blockedTopIds.contains(currentTop.$id)) {
      return rows;
    }

    final replacementIndex = rows.indexWhere(
      (row) => !blockedTopIds.contains(row.$id),
    );
    if (replacementIndex <= 0) {
      return rows;
    }

    final reordered = List<models.Row>.from(rows);
    final replacement = reordered.removeAt(replacementIndex);
    reordered.insert(0, replacement);
    return reordered;
  }

  static double _forYouScore(
    models.Row row,
    _FeedInterestProfile interestProfile,
    FeedExposureStore exposureStore,
    DateTime now, {
    required String feedKey,
    int sessionSeed = 0,
  }) {
    final data = row.data;
    final createdAt = DateTime.tryParse(row.$createdAt) ??
        DateTime.tryParse((data['createdAt'] as String?) ?? '') ??
        now;
    final ageInHours = now.difference(createdAt).inMilliseconds / 3600000.0;
    final engagement = ((data['likes'] as num?) ?? 0).toDouble() +
        (((data['comments'] as num?) ?? 0).toDouble() * 2) +
        (((data['reposts'] as num?) ?? 0).toDouble() * 3) +
        (((data['views'] as num?) ?? 0).toDouble() * 0.1);
    final recencyScore = ageInHours < 24 ? (24 - ageInHours) : 0.0;
    final momentumScore = ((engagement + 1) / (ageInHours + 2.0)) * 6.0;
    final newPostBoost = ageInHours < 1
        ? 10.0
        : ageInHours < 6
            ? 6.0
            : ageInHours < 24
                ? 2.0
                : 0.0;
    final explorationBoost = ageInHours < 3 && engagement < 8 ? 4.0 : 0.0;

    final authorId = (data['userId'] as String?) ?? '';
    final postType = ((data['postType'] as String?) ?? '').toLowerCase();
    double interestBoost = 0.0;
    if (authorId.isNotEmpty) {
      if (interestProfile.followedAuthorIds.contains(authorId)) {
        interestBoost += 14.0;
      }
      interestBoost += interestProfile.authorWeights[authorId] ?? 0.0;
    }
    interestBoost += (interestProfile.typeWeights[postType] ?? 0.0) * 3.0;
    interestBoost += _keywordOverlapScore(data, interestProfile.keywordWeights);
    final seenRecentlyPenalty = exposureStore.penaltyFor(row.$id, feedKey, now);
    final jitter = ((Object.hash(row.$id, sessionSeed) % 2000) / 1000.0) - 1.0;

    return engagement +
        recencyScore +
        momentumScore +
        newPostBoost +
        explorationBoost +
        interestBoost +
        jitter -
        seenRecentlyPenalty;
  }

  static double _keywordOverlapScore(
    Map<String, dynamic> data,
    Map<String, double> keywordWeights,
  ) {
    if (keywordWeights.isEmpty) return 0.0;
    final tokens = _extractInterestTokens(data);
    var score = 0.0;
    for (final token in tokens) {
      score += keywordWeights[token] ?? 0.0;
    }
    return score.clamp(0.0, 18.0);
  }

  static Future<_FeedInterestProfile> _buildInterestProfile(
      String userId) async {
    final followedAuthorIds = (await getFollowingUserIds(userId)).toSet();
    final authorWeights = <String, double>{};
    final typeWeights = <String, double>{};
    final keywordWeights = <String, double>{};

    Future<void> absorbRows(
      String tableId,
      double weight,
    ) async {
      final rows = await _tables.listRows(
        databaseId: databaseId,
        tableId: tableId,
        queries: <String>[
          Query.equal('userId', userId),
          Query.orderDesc('createdAt'),
          Query.limit(25),
        ],
      );
      final postIds = rows.rows
          .map((row) => row.data['postId'] as String?)
          .whereType<String>()
          .toSet();
      if (postIds.isEmpty) return;

      final List<models.Row> posts = [];
      try {
        final postsRes = await _tables.listRows(
          databaseId: databaseId,
          tableId: postsCollectionId,
          queries: <String>[
            Query.equal('\$id', postIds.toList()),
            Query.limit(25),
          ],
        );
        posts.addAll(postsRes.rows);
      } catch (_) {
        // ignore and fallback
      }

      for (final post in posts) {
        final data = post.data;
        final authorId = (data['userId'] as String?) ?? '';
        if (authorId.isNotEmpty) {
          authorWeights[authorId] = (authorWeights[authorId] ?? 0.0) + weight;
        }
        final postType = ((data['postType'] as String?) ?? '').toLowerCase();
        if (postType.isNotEmpty) {
          typeWeights[postType] = (typeWeights[postType] ?? 0.0) + weight;
        }
        for (final token in _extractInterestTokens(data)) {
          keywordWeights[token] = (keywordWeights[token] ?? 0.0) + weight;
        }
      }
    }

    await absorbRows(likesCollectionId, 1.5);
    await absorbRows(savesCollectionId, 2.5);
    await absorbRows(repostsCollectionId, 2.0);

    return _FeedInterestProfile(
      followedAuthorIds: followedAuthorIds,
      authorWeights: authorWeights,
      typeWeights: typeWeights,
      keywordWeights: keywordWeights,
    );
  }

  static Set<String> _extractInterestTokens(Map<String, dynamic> data) {
    final tags = data['tags'] is List
        ? (data['tags'] as List).map((e) => e.toString()).join(' ')
        : '';
    final source = [
      data['title'],
      data['content'],
      data['caption'],
      data['description'],
      data['topic'],
      data['category'],
      data['seoCategory'],
      tags,
    ].whereType<String>().join(' ').toLowerCase();

    return source
        .split(RegExp(r'[^a-z0-9]+'))
        .where((token) => token.length >= 3)
        .toSet();
  }

  static double _watchScore(
    models.Row row,
    FeedExposureStore exposureStore,
    DateTime now, {
    required String feedKey,
    int sessionSeed = 0,
  }) {
    final data = row.data;
    final createdAt = DateTime.tryParse(row.$createdAt) ??
        DateTime.tryParse((data['createdAt'] as String?) ?? '') ??
        now;
    final ageInHours = now.difference(createdAt).inMilliseconds / 3600000.0;
    final engagement = (((data['views'] as num?) ?? 0).toDouble() * 0.5) +
        (((data['likes'] as num?) ?? 0).toDouble()) +
        (((data['comments'] as num?) ?? 0).toDouble() * 2) +
        (((data['reposts'] as num?) ?? 0).toDouble() * 3);
    final freshness = ageInHours < 12
        ? 14.0
        : ageInHours < 48
            ? 8.0
            : ageInHours < 168
                ? 3.0
                : 0.0;
    final seenRecentlyPenalty = exposureStore.penaltyFor(row.$id, feedKey, now);
    final jitter = ((Object.hash(row.$id, sessionSeed) % 1200) / 1000.0) - 0.6;
    return engagement + freshness + jitter - seenRecentlyPenalty;
  }

  static double _reelScore(
    models.Row row,
    FeedExposureStore exposureStore,
    DateTime now, {
    required String feedKey,
    int sessionSeed = 0,
  }) {
    final data = row.data;
    final createdAt = DateTime.tryParse(row.$createdAt) ??
        DateTime.tryParse((data['createdAt'] as String?) ?? '') ??
        now;
    final ageInHours = now.difference(createdAt).inMilliseconds / 3600000.0;
    final engagement = (((data['likes'] as num?) ?? 0).toDouble()) +
        (((data['comments'] as num?) ?? 0).toDouble() * 2) +
        (((data['reposts'] as num?) ?? 0).toDouble() * 3) +
        (((data['views'] as num?) ?? 0).toDouble() * 0.3);
    final freshness = ageInHours < 12
        ? 12.0
        : ageInHours < 48
            ? 6.0
            : ageInHours < 168
                ? 2.0
                : 0.0;
    final seenRecentlyPenalty = exposureStore.penaltyFor(row.$id, feedKey, now);
    final jitter = ((Object.hash(row.$id, sessionSeed) % 1200) / 1000.0) - 0.6;
    return engagement + freshness + jitter - seenRecentlyPenalty;
  }

  static double _homeScore(
    models.Row row,
    FeedExposureStore exposureStore,
    DateTime now, {
    required String feedKey,
    int sessionSeed = 0,
  }) {
    final data = row.data;
    final createdAt = DateTime.tryParse(row.$createdAt) ??
        DateTime.tryParse((data['createdAt'] as String?) ?? '') ??
        now;
    final ageInHours = now.difference(createdAt).inMilliseconds / 3600000.0;
    final relevance = ((data['likes'] as num?) ?? 0).toDouble() +
        (((data['comments'] as num?) ?? 0).toDouble() * 2) +
        (((data['reposts'] as num?) ?? 0).toDouble() * 3) +
        (((data['views'] as num?) ?? 0).toDouble() * 0.2);
    final freshness = ageInHours < 24 ? (24 - ageInHours) * 0.8 : 0.0;
    final seenRecentlyPenalty = exposureStore.penaltyFor(row.$id, feedKey, now);
    final jitter = ((Object.hash(row.$id, sessionSeed) % 1600) / 1000.0) - 0.8;
    return relevance + freshness + jitter - seenRecentlyPenalty;
  }

  static Future<List<String>> getFollowingUserIds(String userId) async {
    try {
      final res = await _tables.listRows(
        databaseId: databaseId,
        tableId: followsCollectionId,
        queries: [Query.equal('followerId', userId), Query.limit(500)],
      );
      return res.rows
          .map((d) => (d.data['followeeId'] as String))
          .toList(growable: false);
    } catch (_) {
      return <String>[];
    }
  }

  static Future<int> getFollowerCount(String userId) async {
    try {
      final res = await _tables.listRows(
        databaseId: databaseId,
        tableId: followsCollectionId,
        queries: [Query.equal('followeeId', userId), Query.limit(1000)],
      );
      return res.total;
    } catch (_) {
      return 0;
    }
  }

  static Future<FeedPage> fetchPostsByUserIdsPage(
    List<String> userIds, {
    int limit = 20,
    String? cursorId,
    int sessionSeed = 0,
  }) async {
    if (userIds.isEmpty) {
      return const FeedPage(rows: <models.Row>[], nextCursor: null, total: 0);
    }
    final res = await _tables.listRows(
      databaseId: databaseId,
      tableId: postsCollectionId,
      queries: <String>[
        Query.equal('userId', userIds),
        Query.orderDesc('createdAt'),
        Query.limit(limit * 5),
        if (cursorId != null) Query.cursorAfter(cursorId),
      ],
    );
    final nextCursor = res.rows.isNotEmpty ? res.rows.last.$id : null;
    final exposureStore = await FeedExposureService.loadStore();
    final now = DateTime.now();
    final scored = List<models.Row>.from(res.rows);
    scored.sort(
      (a, b) => _followingScore(
        b,
        exposureStore,
        now,
        sessionSeed: sessionSeed,
      ).compareTo(
        _followingScore(
          a,
          exposureStore,
          now,
          sessionSeed: sessionSeed,
        ),
      ),
    );
    final sliced = _selectDiverseRows(
      scored,
      limit: limit,
      authorCap: 2,
      sourceCap: 1,
    );
    final deRepeated = _pushRecentRowsOutOfTop(
      sliced,
      exposureStore,
      now,
      feedKey: 'following',
      protectedTopSlots: 4,
      recentWindowHours: 36,
    );
    final topGuarded = _avoidRecentTopPostIds(
      deRepeated,
      exposureStore,
      feedKey: 'following',
    );
    return FeedPage(
      rows: _rotateTopRows(topGuarded, sessionSeed: sessionSeed, topWindow: 7),
      nextCursor: nextCursor,
      total: topGuarded.length,
    );
  }

  static Future<models.RowList> fetchPostsByUserIds(
    List<String> userIds, {
    int limit = 20,
    String? cursorId,
    int sessionSeed = 0,
  }) async {
    return (await fetchPostsByUserIdsPage(
      userIds,
      limit: limit,
      cursorId: cursorId,
      sessionSeed: sessionSeed,
    ))
        .toRowList();
  }

  static double _followingScore(
    models.Row row,
    FeedExposureStore exposureStore,
    DateTime now, {
    int sessionSeed = 0,
  }) {
    final data = row.data;
    final createdAt = DateTime.tryParse(row.$createdAt) ??
        DateTime.tryParse((data['createdAt'] as String?) ?? '') ??
        now;
    final ageInHours = now.difference(createdAt).inMilliseconds / 3600000.0;
    final relevance = ((data['likes'] as num?) ?? 0).toDouble() +
        (((data['comments'] as num?) ?? 0).toDouble() * 1.5) +
        (((data['reposts'] as num?) ?? 0).toDouble() * 2.5) +
        (((data['views'] as num?) ?? 0).toDouble() * 0.1);
    final freshness = ageInHours < 48
        ? (48 - ageInHours) * 0.9
        : ageInHours < 168
            ? 4.0
            : 0.0;
    final seenRecentlyPenalty =
        exposureStore.penaltyFor(row.$id, 'following', now);
    final jitter = ((Object.hash(row.$id, sessionSeed) % 1200) / 1000.0) - 0.6;
    return relevance + freshness + jitter - seenRecentlyPenalty;
  }

  static Future<models.RowList> fetchRepostsByUserIds(
    List<String> userIds, {
    int limit = 20,
  }) async {
    if (userIds.isEmpty) return models.RowList(total: 0, rows: []);
    return await _tables.listRows(
      databaseId: databaseId,
      tableId: repostsCollectionId,
      queries: <String>[
        Query.equal('userId', userIds),
        Query.orderDesc('createdAt'),
        Query.limit(limit),
      ],
    );
  }

  static Future<models.Row?> getProfileByUsername(String username) async {
    try {
      final res = await _tables.listRows(
        databaseId: databaseId,
        tableId: profilesCollectionId,
        queries: <String>[Query.equal('username', username), Query.limit(1)],
      );
      if (res.rows.isEmpty) return null;
      return res.rows.first;
    } catch (_) {
      return null;
    }
  }

  static Future<models.RowList> searchProfiles(
    String query, {
    int limit = 20,
  }) async {
    final usernameRows = await _tables.listRows(
      databaseId: databaseId,
      tableId: profilesCollectionId,
      queries: <String>[
        Query.search('username', query),
        Query.limit(limit),
      ],
    );
    final displayNameRows = await _tables.listRows(
      databaseId: databaseId,
      tableId: profilesCollectionId,
      queries: <String>[
        Query.search('displayName', query),
        Query.limit(limit),
      ],
    );
    final merged = <String, models.Row>{};
    for (final row in usernameRows.rows) {
      merged[row.$id] = row;
    }
    for (final row in displayNameRows.rows) {
      merged[row.$id] = row;
    }
    return models.RowList(
      total: merged.length,
      rows: merged.values.toList(growable: false),
    );
  }

  static Future<models.RowList> searchPostsByHashtag(
    String tag, {
    int limit = 20,
    String? cursorId,
  }) async {
    final cleanTag = tag.trim().replaceFirst('#', '').toLowerCase();
    if (cleanTag.isEmpty) {
      return models.RowList(total: 0, rows: []);
    }

    final matchedRows = <models.Row>[];
    String? cursor = cursorId;

    while (matchedRows.length < limit) {
      final batch = await _tables.listRows(
        databaseId: databaseId,
        tableId: postsCollectionId,
        queries: <String>[
          Query.orderDesc('createdAt'),
          Query.limit(100),
          if (cursor != null) Query.cursorAfter(cursor),
        ],
      );
      if (batch.rows.isEmpty) {
        break;
      }

      for (final row in batch.rows) {
        if (_rowMatchesHashtag(row, cleanTag)) {
          matchedRows.add(row);
          if (matchedRows.length >= limit) break;
        }
      }

      cursor = batch.rows.last.$id;
      if (batch.rows.length < 100) {
        break;
      }
    }

    return models.RowList(total: matchedRows.length, rows: matchedRows);
  }

  static bool _rowMatchesHashtag(models.Row row, String cleanTag) {
    final values = <String?>[
      row.data['content'] as String?,
      row.data['title'] as String?,
      row.data['caption'] as String?,
      row.data['description'] as String?,
      row.data['seoTitle'] as String?,
      row.data['seoDescription'] as String?,
      row.data['seoCategory'] as String?,
    ];

    final seoKeywords = row.data['seoKeywords'];
    if (seoKeywords is Iterable) {
      for (final item in seoKeywords) {
        values.add(item?.toString());
      }
    } else if (seoKeywords is String) {
      values.add(seoKeywords);
    }

    for (final value in values) {
      if (value == null || value.trim().isEmpty) continue;
      final normalized = value.toLowerCase();
      if (normalized.contains('#$cleanTag') || normalized.contains(cleanTag)) {
        return true;
      }
    }
    return false;
  }

  static Future<void> updatePostSeo(
    String postId, {
    String? seoTitle,
    String? seoDescription,
    String? seoSlug,
    List<String>? seoKeywords,
  }) async {
    final data = <String, dynamic>{};
    if (seoTitle != null && seoTitle.isNotEmpty) {
      data['seoTitle'] = seoTitle;
    }
    if (seoDescription != null && seoDescription.isNotEmpty) {
      data['seoDescription'] = seoDescription;
    }
    if (seoSlug != null && seoSlug.isNotEmpty) {
      data['seoSlug'] = seoSlug;
    }
    if (seoKeywords != null && seoKeywords.isNotEmpty) {
      data['seoKeywords'] = seoKeywords;
    }
    if (data.isEmpty) return;
    await updateRow(postsCollectionId, postId, data);
  }

  static Future<Map<String, dynamic>> fetchEpisodeMetadata(
      String postId) async {
    final row = await getRow(postsCollectionId, postId);
    final data = row.data;
    int? readInt(String key) {
      final raw = data[key];
      if (raw is int) return raw;
      return int.tryParse('$raw');
    }

    String? readString(String key) {
      final raw = data[key];
      if (raw == null) return null;
      final value = raw.toString().trim();
      return value.isEmpty ? null : value;
    }

    final isEpisode = data['isEpisode'] == true ||
        '${data['isEpisode']}'.toLowerCase() == 'true';
    return <String, dynamic>{
      'isEpisode': isEpisode,
      'postId': row.$id,
      'userId': readString('userId'),
      'postType': readString('postType'),
      'episodeContentType':
          readString('episodeContentType') ?? readString('postType'),
      'seriesTitle': readString('seriesTitle'),
      'episodeNumber': readInt('episodeNumber'),
      'episodeTitle': readString('episodeTitle'),
      'episodeDescription': readString('episodeDescription'),
      'seriesThumbnailUrl': readString('seriesThumbnailUrl'),
      'seriesCoverUrl': readString('seriesCoverUrl'),
      'seriesHeaderText': readString('seriesHeaderText'),
      'thumbnailUrl': readString('thumbnailUrl'),
      'isArchived': data['isArchived'] == true ||
          '${data['isArchived']}'.toLowerCase() == 'true',
    };
  }

  static Future<models.Row?> fetchNextEpisodeRow({
    required String userId,
    required String seriesTitle,
    required int currentEpisodeNumber,
    required String contentType,
  }) async {
    final res = await _tables.listRows(
      databaseId: databaseId,
      tableId: postsCollectionId,
      queries: <String>[
        Query.equal('userId', <String>[userId]),
        Query.equal('seriesTitle', <String>[seriesTitle]),
        Query.equal('postType', <String>[contentType]),
        Query.equal('isEpisode', <dynamic>[true]),
        Query.equal('isArchived', <dynamic>[false]),
        Query.orderAsc('episodeNumber'),
        Query.limit(100),
      ],
    );
    for (final row in res.rows) {
      final raw = row.data['episodeNumber'];
      final number = raw is int ? raw : int.tryParse('$raw');
      if (number != null && number > currentEpisodeNumber) {
        return row;
      }
    }
    return null;
  }

  static Future<List<models.Row>> fetchSeriesEpisodeRows({
    required String userId,
    required String seriesTitle,
    required String contentType,
    bool includeArchived = false,
  }) async {
    final queries = <String>[
      Query.equal('userId', <String>[userId]),
      Query.equal('seriesTitle', <String>[seriesTitle]),
      Query.equal('postType', <String>[contentType]),
      Query.equal('isEpisode', <dynamic>[true]),
      Query.orderAsc('episodeNumber'),
      Query.limit(200),
    ];
    if (!includeArchived) {
      queries.add(Query.equal('isArchived', <dynamic>[false]));
    }
    final res = await _tables.listRows(
      databaseId: databaseId,
      tableId: postsCollectionId,
      queries: queries,
    );
    final rows = List<models.Row>.from(res.rows);
    rows.sort((a, b) {
      int readEpisode(models.Row row) {
        final raw = row.data['episodeNumber'];
        if (raw is int) return raw;
        return int.tryParse('$raw') ?? 0;
      }

      return readEpisode(a).compareTo(readEpisode(b));
    });
    return rows;
  }

  static Future<Map<String, dynamic>?> fetchSeriesHeaderData({
    required String userId,
    required String seriesTitle,
    required String contentType,
  }) async {
    final rows = await fetchSeriesEpisodeRows(
      userId: userId,
      seriesTitle: seriesTitle,
      contentType: contentType,
      includeArchived: true,
    );
    if (rows.isEmpty) return null;
    final row = rows.first;
    final data = row.data;
    String? readString(String key) {
      final raw = data[key];
      if (raw == null) return null;
      final value = raw.toString().trim();
      return value.isEmpty ? null : value;
    }

    return <String, dynamic>{
      'seriesTitle': readString('seriesTitle') ?? seriesTitle,
      'seriesCoverUrl':
          readString('seriesCoverUrl') ?? readString('thumbnailUrl'),
      'seriesHeaderText':
          readString('seriesHeaderText') ?? readString('episodeDescription'),
      'episodeCount': rows.length,
    };
  }

  static Future<void> updateSeriesHeader({
    required String userId,
    required String seriesTitle,
    required String contentType,
    String? seriesCoverUrl,
    String? seriesHeaderText,
  }) async {
    final rows = await fetchSeriesEpisodeRows(
      userId: userId,
      seriesTitle: seriesTitle,
      contentType: contentType,
      includeArchived: true,
    );
    for (final row in rows) {
      final payload = <String, dynamic>{
        if (seriesCoverUrl != null) 'seriesCoverUrl': seriesCoverUrl,
        if (seriesHeaderText != null) 'seriesHeaderText': seriesHeaderText,
      };
      if (payload.isNotEmpty) {
        await updateRow(postsCollectionId, row.$id, payload);
      }
    }
  }

  static Future<void> reorderSeriesEpisodes({
    required List<String> postIdsInOrder,
  }) async {
    for (var index = 0; index < postIdsInOrder.length; index++) {
      await updateRow(
        postsCollectionId,
        postIdsInOrder[index],
        <String, dynamic>{'episodeNumber': index + 1},
      );
    }
  }

  static Future<void> archivePost(String postId, {bool archived = true}) async {
    await updateRow(
      postsCollectionId,
      postId,
      <String, dynamic>{
        'isArchived': archived,
        'archivedAt': archived ? DateTime.now().toIso8601String() : '',
      },
    );
  }

  static Future<models.RowList> searchPostsByText(
    String text, {
    int limit = 20,
    String? cursorId,
  }) async {
    return await _tables.listRows(
      databaseId: databaseId,
      tableId: postsCollectionId,
      queries: <String>[
        Query.search('content', text),
        Query.orderDesc('createdAt'),
        Query.limit(limit),
        if (cursorId != null) Query.cursorAfter(cursorId),
      ],
    );
  }

  static Future<models.RowList> searchPostsByTextFields(
    String text, {
    int limit = 20,
    String? cursorId,
  }) async {
    final query = text.trim();
    if (query.isEmpty) {
      return models.RowList(total: 0, rows: []);
    }

    final fields = <String>[
      'content',
      'title',
      'caption',
      'description',
      'seoTitle',
      'seoDescription',
      'seoCategory',
    ];
    final results = <String, models.Row>{};

    for (final field in fields) {
      final rows = await _tables.listRows(
        databaseId: databaseId,
        tableId: postsCollectionId,
        queries: <String>[
          Query.search(field, query),
          Query.orderDesc('createdAt'),
          Query.limit(limit),
          if (cursorId != null) Query.cursorAfter(cursorId),
        ],
      );
      for (final row in rows.rows) {
        results[row.$id] = row;
      }
      if (results.length >= limit) break;
    }

    final merged = results.values.toList(growable: false)
      ..sort((a, b) {
        final aTime = DateTime.tryParse(a.$createdAt) ??
            DateTime.fromMillisecondsSinceEpoch(0);
        final bTime = DateTime.tryParse(b.$createdAt) ??
            DateTime.fromMillisecondsSinceEpoch(0);
        return bTime.compareTo(aTime);
      });

    if (merged.length > limit) {
      merged.removeRange(limit, merged.length);
    }

    return models.RowList(total: merged.length, rows: merged);
  }

  static Future<models.RowList> searchPostsByTextAcrossPages(
    String text, {
    int limit = 20,
  }) async {
    final query = text.trim().toLowerCase();
    if (query.isEmpty) {
      return models.RowList(total: 0, rows: []);
    }

    final matchedRows = <models.Row>[];
    String? cursorId;

    while (matchedRows.length < limit) {
      final batch = await _tables.listRows(
        databaseId: databaseId,
        tableId: postsCollectionId,
        queries: <String>[
          Query.orderDesc('createdAt'),
          Query.limit(100),
          if (cursorId != null) Query.cursorAfter(cursorId),
        ],
      );
      if (batch.rows.isEmpty) break;

      for (final row in batch.rows) {
        final data = row.data;
        final haystack = [
          data['content'],
          data['title'],
          data['username'],
          data['displayName'],
          data['caption'],
          data['description'],
          data['seoTitle'],
          data['seoDescription'],
          data['seoCategory'],
        ].whereType<String>().join(' ').toLowerCase();
        final seoKeywords = data['seoKeywords'];
        final keywordHaystack = seoKeywords is Iterable
            ? seoKeywords.map((item) => item.toString()).join(' ').toLowerCase()
            : seoKeywords is String
                ? seoKeywords.toLowerCase()
                : '';
        final combined = '$haystack $keywordHaystack';
        if (combined.contains(query)) {
          matchedRows.add(row);
          if (matchedRows.length >= limit) break;
        }
      }

      cursorId = batch.rows.last.$id;
      if (batch.rows.length < 100) break;
    }

    return models.RowList(total: matchedRows.length, rows: matchedRows);
  }

  static Future<void> incrementPostLikes(String postId, int delta) async {
    await _incrementPostField(postId, 'likes', delta);
  }

  static Future<void> incrementPostReposts(String postId, int delta) async {
    await _incrementPostField(postId, 'reposts', delta);
  }

  static Future<void> incrementPostComments(String postId, int delta) async {
    await _incrementPostField(postId, 'comments', delta);
  }

  static Future<void> incrementPostShares(String postId, int delta) async {
    await _incrementPostField(postId, 'shares', delta);
  }

  static Future<void> incrementPostViews(String postId, int delta) async {
    await _incrementPostField(postId, 'views', delta);
  }

  static Future<void> incrementPostImpressions(String postId, int delta) async {
    await _incrementPostField(postId, 'impressions', delta);
  }

  static Future<void> _incrementPostField(
    String postId,
    String field,
    int delta,
  ) async {
    try {
      final row = await getRow(postsCollectionId, postId);
      final current = row.data[field] ?? 0;
      final parsed = current is int ? current : int.tryParse('$current') ?? 0;
      final next = (parsed + delta).clamp(0, 1 << 31);
      await updateRow(postsCollectionId, postId, {field: next});
      if (field == 'impressions') {
        final boostId = row.data['activeBoostId'] as String?;
        final isBoosted = row.data['isBoosted'] as bool? ?? false;
        if (boostId != null && boostId.isNotEmpty && isBoosted) {
          try {
            final boostRow = await getRow(postBoostsCollectionId, boostId);
            final data = boostRow.data;
            final status = (data['status'] as String?)?.toLowerCase();
            if (status == 'running') {
              final deliveredRaw = data['deliveredImpressions'] ?? 0;
              final delivered = deliveredRaw is int
                  ? deliveredRaw
                  : int.tryParse('$deliveredRaw') ?? 0;
              final targetRaw = data['targetReach'] ?? 0;
              final target = targetRaw is int
                  ? targetRaw
                  : int.tryParse('$targetRaw') ?? 0;
              final newDelivered = (delivered + delta).clamp(
                0,
                target > 0 ? target : 1 << 31,
              );
              final updateData = <String, dynamic>{
                'deliveredImpressions': newDelivered,
              };
              if (target > 0 && newDelivered >= target) {
                updateData['status'] = 'completed';
                await updateRow(postsCollectionId, postId, {
                  'isBoosted': false,
                  'activeBoostId': null,
                });
              }
              await updateRow(postBoostsCollectionId, boostId, updateData);
            }
          } catch (_) {}
        }
      }
    } catch (_) {}
  }

  // Reposts (per-user tracking)
  static Future<bool> isPostRepostedBy(String userId, String postId) async {
    final cached = _batchRepostsCache[postId];
    if (cached != null) return cached;
    try {
      final res = await _tables.listRows(
        databaseId: databaseId,
        tableId: repostsCollectionId,
        queries: [
          Query.equal('userId', userId),
          Query.equal('postId', postId),
          Query.limit(1),
        ],
      );
      final result = res.rows.isNotEmpty;
      _batchRepostsCache[postId] = result;
      return result;
    } catch (_) {
      return false;
    }
  }

  static Future<void> repostPost(String originalPostId) async {
    final user = await getCurrentUser();
    if (user == null) {
      throw StateError('User must be signed in to repost.');
    }

    // Toggle per-user repost record (mirror behavior, not a fresh post).
    try {
      final res = await _tables.listRows(
        databaseId: databaseId,
        tableId: repostsCollectionId,
        queries: [
          Query.equal('userId', user.$id),
          Query.equal('postId', originalPostId),
          Query.limit(1),
        ],
      );

      if (res.rows.isNotEmpty) {
        // Undo repost: remove record and decrement counter.
        _batchRepostsCache[originalPostId] = false;
        for (final row in res.rows) {
          await _tables.deleteRow(
            databaseId: databaseId,
            tableId: repostsCollectionId,
            rowId: row.$id,
          );
        }
        await incrementPostReposts(originalPostId, -1);
      } else {
        // Create repost record and increment counter.
        _batchRepostsCache[originalPostId] = true;
        await _tables.createRow(
          databaseId: databaseId,
          tableId: repostsCollectionId,
          rowId: ID.unique(),
          data: {
            'postId': originalPostId,
            'userId': user.$id,
            'createdAt': DateTime.now().toIso8601String(),
          },
        );
        await incrementPostReposts(originalPostId, 1);
      }
    } catch (_) {}
  }

  // Comments
  static Future<models.RowList> fetchComments(
    String postId, {
    int limit = 50,
  }) async {
    final res = await _tables.listRows(
      databaseId: databaseId,
      tableId: commentsCollectionId,
      queries: <String>[
        Query.equal('postId', postId),
        Query.orderDesc('createdAt'),
        Query.limit(limit),
      ],
    );
    return res;
  }

  static Future<models.Row> createComment(String postId, String content) async {
    final user = await getCurrentUser();
    if (user == null) throw StateError('User must be signed in to comment.');
    final profile = await getProfileByUserId(user.$id);
    final displayName =
        ((profile?.data['displayName'] as String?)?.trim().isNotEmpty == true)
            ? (profile!.data['displayName'] as String).trim()
            : (((profile?.data['username'] as String?)?.trim().isNotEmpty ==
                    true)
                ? (profile!.data['username'] as String).trim()
                : user.name);
    final username =
        ((profile?.data['username'] as String?)?.trim().isNotEmpty == true)
            ? (profile!.data['username'] as String).trim()
            : displayName;
    final avatar = profile?.data['avatarUrl'] as String?;
    final row = await _tables.createRow(
      databaseId: databaseId,
      tableId: commentsCollectionId,
      rowId: ID.unique(),
      permissions: [
        Permission.read(Role.any()),
        Permission.write(Role.user(user.$id)),
      ],
      data: {
        'type': 'text',
        'postId': postId,
        'userId': user.$id,
        'username': username,
        'displayName': displayName,
        'userAvatar': avatar ?? '',
        'content': content,
        'likes': 0,
        'replies': 0,
        'createdAt': DateTime.now().toIso8601String(),
      },
    );
    unawaited(() async {
      try {
        final post = await getRow(postsCollectionId, postId);
        final recipientId = (post.data['userId'] as String?)?.trim() ?? '';
        if (recipientId.isEmpty || recipientId == user.$id) return;
        await _createInAppNotification(
          recipientUserId: recipientId,
          title: displayName,
          body: 'commented on your post',
          type: 'comment',
          actorName: displayName,
          actorAvatar: avatar ?? '',
          actionUrl: '/post/$postId',
          postId: postId,
          creatorId: user.$id,
        );
      } catch (_) {}
    }());
    return row;
  }

  static Future<models.Row> createReplyComment(
    String postId,
    String parentCommentId,
    String content,
  ) async {
    final user = await getCurrentUser();
    if (user == null) throw StateError('User must be signed in to comment.');
    final profile = await getProfileByUserId(user.$id);
    final displayName =
        ((profile?.data['displayName'] as String?)?.trim().isNotEmpty == true)
            ? (profile!.data['displayName'] as String).trim()
            : (((profile?.data['username'] as String?)?.trim().isNotEmpty ==
                    true)
                ? (profile!.data['username'] as String).trim()
                : user.name);
    final username =
        ((profile?.data['username'] as String?)?.trim().isNotEmpty == true)
            ? (profile!.data['username'] as String).trim()
            : displayName;
    final avatar = profile?.data['avatarUrl'] as String?;
    final row = await _tables.createRow(
      databaseId: databaseId,
      tableId: commentsCollectionId,
      rowId: ID.unique(),
      permissions: [
        Permission.read(Role.any()),
        Permission.write(Role.user(user.$id)),
      ],
      data: {
        'type': 'text',
        'postId': postId,
        'parentCommentId': parentCommentId,
        'userId': user.$id,
        'username': username,
        'displayName': displayName,
        'userAvatar': avatar ?? '',
        'content': content,
        'likes': 0,
        'replies': 0,
        'createdAt': DateTime.now().toIso8601String(),
      },
    );
    unawaited(() async {
      try {
        final parentComment = await getRow(commentsCollectionId, parentCommentId);
        final parentOwnerId =
            (parentComment.data['userId'] as String?)?.trim() ?? '';
        final post = await getRow(postsCollectionId, postId);
        final postOwnerId = (post.data['userId'] as String?)?.trim() ?? '';
        final recipients = <String>{
          if (parentOwnerId.isNotEmpty) parentOwnerId,
          if (postOwnerId.isNotEmpty) postOwnerId,
        }..remove(user.$id);
        for (final recipientId in recipients) {
          await _createInAppNotification(
            recipientUserId: recipientId,
            title: displayName,
            body: 'replied to a comment',
            type: 'comment',
            actorName: displayName,
            actorAvatar: avatar ?? '',
            actionUrl: '/post/$postId',
            postId: postId,
            creatorId: user.$id,
          );
        }
      } catch (_) {}
    }());
    return row;
  }

  static Future<models.Row> createVoiceComment(
    String postId,
    String voiceUrl,
  ) async {
    final user = await getCurrentUser();
    if (user == null) throw StateError('User must be signed in to comment.');
    final profile = await getProfileByUserId(user.$id);
    final displayName =
        ((profile?.data['displayName'] as String?)?.trim().isNotEmpty == true)
            ? (profile!.data['displayName'] as String).trim()
            : (((profile?.data['username'] as String?)?.trim().isNotEmpty ==
                    true)
                ? (profile!.data['username'] as String).trim()
                : user.name);
    final username =
        ((profile?.data['username'] as String?)?.trim().isNotEmpty == true)
            ? (profile!.data['username'] as String).trim()
            : displayName;
    final avatar = profile?.data['avatarUrl'] as String?;
    return _tables.createRow(
      databaseId: databaseId,
      tableId: commentsCollectionId,
      rowId: ID.unique(),
      permissions: [
        Permission.read(Role.any()),
        Permission.write(Role.user(user.$id)),
      ],
      data: {
        'type': 'voice',
        'postId': postId,
        'userId': user.$id,
        'username': username,
        'displayName': displayName,
        'userAvatar': avatar ?? '',
        'voiceUrl': voiceUrl,
        'likes': 0,
        'replies': 0,
        'createdAt': DateTime.now().toIso8601String(),
      },
    );
  }

  // Likes
  static Future<bool> isPostLikedBy(String userId, String postId) async {
    final cached = _batchLikesCache[postId];
    if (cached != null) return cached;
    try {
      final res = await _tables.listRows(
        databaseId: databaseId,
        tableId: likesCollectionId,
        queries: [
          Query.equal('userId', userId),
          Query.equal('postId', postId),
          Query.limit(1),
        ],
      );
      final result = res.rows.isNotEmpty;
      _batchLikesCache[postId] = result;
      return result;
    } catch (_) {
      return false;
    }
  }

  static Future<models.Row> likePost(String postId) async {
    _batchLikesCache[postId] = true;
    final user = await getCurrentUser();
    if (user == null) throw StateError('User must be signed in to like posts.');
    final profile = await getProfileByUserId(user.$id);
    final displayName =
        ((profile?.data['displayName'] as String?)?.trim().isNotEmpty == true)
            ? (profile!.data['displayName'] as String).trim()
            : (((profile?.data['username'] as String?)?.trim().isNotEmpty ==
                    true)
                ? (profile!.data['username'] as String).trim()
                : user.name);
    final avatar = profile?.data['avatarUrl'] as String? ?? '';
    final doc = await _tables.createRow(
      databaseId: databaseId,
      tableId: likesCollectionId,
      rowId: ID.unique(),
      data: {
        'postId': postId,
        'userId': user.$id,
        'createdAt': DateTime.now().toIso8601String(),
      },
    );
    await incrementPostLikes(postId, 1);
    unawaited(() async {
      try {
        final post = await getRow(postsCollectionId, postId);
        final recipientId = (post.data['userId'] as String?)?.trim() ?? '';
        if (recipientId.isEmpty || recipientId == user.$id) return;
        await _createInAppNotification(
          recipientUserId: recipientId,
          title: displayName,
          body: 'liked your post',
          type: 'like',
          actorName: displayName,
          actorAvatar: avatar,
          actionUrl: '/post/$postId',
          postId: postId,
          creatorId: user.$id,
        );
      } catch (_) {}
    }());
    return doc;
  }

  static Future<void> unlikePost(String postId) async {
    _batchLikesCache[postId] = false;
    final user = await getCurrentUser();
    if (user == null) return;
    try {
      final res = await _tables.listRows(
        databaseId: databaseId,
        tableId: likesCollectionId,
        queries: [
          Query.equal('userId', user.$id),
          Query.equal('postId', postId),
        ],
      );
      for (final row in res.rows) {
        await _tables.deleteRow(
          databaseId: databaseId,
          tableId: likesCollectionId,
          rowId: row.$id,
        );
      }
      await incrementPostLikes(postId, -1);
    } catch (_) {}
  }

  // Saves
  static Future<bool> isPostSavedBy(String userId, String postId) async {
    final cached = _batchSavesCache[postId];
    if (cached != null) return cached;
    try {
      final res = await _tables.listRows(
        databaseId: databaseId,
        tableId: savesCollectionId,
        queries: [
          Query.equal('userId', userId),
          Query.equal('postId', postId),
          Query.limit(1),
        ],
      );
      final result = res.rows.isNotEmpty;
      _batchSavesCache[postId] = result;
      return result;
    } catch (_) {
      return false;
    }
  }

  static Future<models.Row> savePost(String postId) async {
    _batchSavesCache[postId] = true;
    final user = await getCurrentUser();
    if (user == null) throw StateError('User must be signed in to save posts.');
    return _tables.createRow(
      databaseId: databaseId,
      tableId: savesCollectionId,
      rowId: ID.unique(),
      data: {
        'postId': postId,
        'userId': user.$id,
        'createdAt': DateTime.now().toIso8601String(),
      },
    );
  }

  static Future<void> unsavePost(String postId) async {
    _batchSavesCache[postId] = false;
    final user = await getCurrentUser();
    if (user == null) return;
    try {
      final res = await _tables.listRows(
        databaseId: databaseId,
        tableId: savesCollectionId,
        queries: [
          Query.equal('userId', user.$id),
          Query.equal('postId', postId),
        ],
      );
      for (final row in res.rows) {
        await _tables.deleteRow(
          databaseId: databaseId,
          tableId: savesCollectionId,
          rowId: row.$id,
        );
      }
    } catch (_) {}
  }

  // Follows
  static Future<bool> isFollowing(String followerId, String followeeId) async {
    final cacheKey = '$followerId:$followeeId';
    final cached = _followingCache[cacheKey];
    if (cached != null) return cached;
    try {
      final res = await _tables.listRows(
        databaseId: databaseId,
        tableId: followsCollectionId,
        queries: [
          Query.equal('followerId', followerId),
          Query.equal('followeeId', followeeId),
          Query.limit(1),
        ],
      );
      final result = res.rows.isNotEmpty;
      _followingCache[cacheKey] = result;
      return result;
    } catch (_) {
      return false;
    }
  }

  static Future<bool> isUserBlocked(
      String blockerId, String blockedUserId) async {
    try {
      final res = await _tables.listRows(
        databaseId: databaseId,
        tableId: blocksCollectionId,
        queries: [
          Query.equal('blockerId', blockerId),
          Query.equal('blockedUserId', blockedUserId),
          Query.limit(1),
        ],
      );
      return res.rows.isNotEmpty;
    } catch (_) {
      return false;
    }
  }

  static Future<void> blockUser(String blockedUserId) async {
    final user = await getCurrentUser();
    if (user == null) {
      throw StateError('User must be signed in to block users.');
    }
    final safeBlockedUserId = blockedUserId.trim();
    if (safeBlockedUserId.isEmpty || safeBlockedUserId == user.$id) {
      return;
    }
    final alreadyBlocked = await isUserBlocked(user.$id, safeBlockedUserId);
    if (alreadyBlocked) return;
    await _tables.createRow(
      databaseId: databaseId,
      tableId: blocksCollectionId,
      rowId: ID.unique(),
      data: {
        'blockerId': user.$id,
        'blockedUserId': safeBlockedUserId,
        'createdAt': DateTime.now().toIso8601String(),
      },
    );
  }

  static Future<void> unblockUser(String blockedUserId) async {
    final user = await getCurrentUser();
    if (user == null) return;
    try {
      final res = await _tables.listRows(
        databaseId: databaseId,
        tableId: blocksCollectionId,
        queries: [
          Query.equal('blockerId', user.$id),
          Query.equal('blockedUserId', blockedUserId),
        ],
      );
      for (final row in res.rows) {
        await _tables.deleteRow(
          databaseId: databaseId,
          tableId: blocksCollectionId,
          rowId: row.$id,
        );
      }
    } catch (_) {}
  }

  static Future<void> followUser(String followeeId) async {
    final user = await getCurrentUser();
    if (user == null) return;
    try {
      final profile = await getProfileByUserId(user.$id);
      final displayName =
          ((profile?.data['displayName'] as String?)?.trim().isNotEmpty ==
                  true)
              ? (profile!.data['displayName'] as String).trim()
              : (((profile?.data['username'] as String?)?.trim().isNotEmpty ==
                      true)
                  ? (profile!.data['username'] as String).trim()
                  : user.name);
      final avatar = profile?.data['avatarUrl'] as String? ?? '';
      await _tables.createRow(
        databaseId: databaseId,
        tableId: followsCollectionId,
        rowId: ID.unique(),
        data: {
          'followerId': user.$id,
          'followeeId': followeeId,
          // Match follows table schema: required followedAt column.
          'followedAt': DateTime.now().toIso8601String(),
        },
      );
      unawaited(() async {
        try {
          if (followeeId.trim().isEmpty || followeeId.trim() == user.$id) {
            return;
          }
          await _createInAppNotification(
            recipientUserId: followeeId.trim(),
            title: displayName,
            body: 'started following you',
            type: 'follow',
            actorName: displayName,
            actorAvatar: avatar,
            actionUrl: '/profile/${user.$id}',
            creatorId: user.$id,
          );
        } catch (_) {}
      }());
      // Invalidate cached follow state for this pair.
      final me = _currentUserCache;
      if (me != null) {
        _followingCache.remove('${me.$id}:$followeeId');
      }
      followingVersion.value++;
    } catch (_) {}
  }

  static Future<void> unfollowUser(String followeeId) async {
    final user = await getCurrentUser();
    if (user == null) return;
    try {
      final res = await _tables.listRows(
        databaseId: databaseId,
        tableId: followsCollectionId,
        queries: [
          Query.equal('followerId', user.$id),
          Query.equal('followeeId', followeeId),
        ],
      );
      for (final row in res.rows) {
        await _tables.deleteRow(
          databaseId: databaseId,
          tableId: followsCollectionId,
          rowId: row.$id,
        );
      }
      // Invalidate cached follow state for this pair.
      final me = _currentUserCache;
      if (me != null) {
        _followingCache.remove('${me.$id}:$followeeId');
      }
      followingVersion.value++;
    } catch (_) {}
  }

  // Reports
  static Future<models.Row> reportPost(String postId, String reason) async {
    final user = await getCurrentUser();
    if (user == null) {
      throw StateError('User must be signed in to report posts.');
    }
    return _tables.createRow(
      databaseId: databaseId,
      tableId: reportsCollectionId,
      rowId: ID.unique(),
      data: {
        'postId': postId,
        'userId': user.$id,
        'reason': reason,
        'createdAt': DateTime.now().toIso8601String(),
      },
    );
  }

  static Future<models.Row> reportProfile(String userId, String reason) async {
    final user = await getCurrentUser();
    if (user == null) {
      throw StateError('User must be signed in to report profiles.');
    }
    return _tables.createRow(
      databaseId: databaseId,
      tableId: reportsCollectionId,
      rowId: ID.unique(),
      data: {
        'reportedUserId': userId,
        'userId': user.$id,
        'reason': reason,
        'createdAt': DateTime.now().toIso8601String(),
      },
    );
  }

  static Future<models.Row> createSupportRequest({
    required String subject,
    required String message,
    String category = 'general',
  }) async {
    final user = await getCurrentUser();
    final profile = user == null ? null : await getProfileByUserId(user.$id);
    return createDocument(
      supportRequestsCollectionId,
      <String, dynamic>{
        'userId': user?.$id ?? '',
        'email': user?.email ?? '',
        'username': (profile?.data['username'] ?? '').toString(),
        'displayName':
            (profile?.data['displayName'] ?? user?.name ?? '').toString(),
        'subject': subject.trim(),
        'message': message.trim(),
        'category': category.trim().isEmpty ? 'general' : category.trim(),
        'status': 'open',
        'createdAt': DateTime.now().toUtc().toIso8601String(),
      },
    );
  }

  static Future<void> _incrementCommentField(
    String commentId,
    String field,
    int delta,
  ) async {
    try {
      final row = await _tables.getRow(
        databaseId: databaseId,
        tableId: commentsCollectionId,
        rowId: commentId,
      );
      final current = row.data[field] ?? 0;
      final parsed = current is int ? current : int.tryParse('$current') ?? 0;
      final next = (parsed + delta).clamp(0, 1 << 31);
      await _tables.updateRow(
        databaseId: databaseId,
        tableId: commentsCollectionId,
        rowId: commentId,
        data: {field: next},
      );
    } catch (_) {}
  }

  static Future<void> incrementCommentLikes(String commentId, int delta) =>
      _incrementCommentField(commentId, 'likes', delta);

  static Future<void> incrementCommentReplies(String commentId, int delta) =>
      _incrementCommentField(commentId, 'replies', delta);

  // Comment likes
  static Future<bool> isCommentLikedBy(String userId, String commentId) async {
    try {
      final res = await _tables.listRows(
        databaseId: databaseId,
        tableId: commentLikesCollectionId,
        queries: [
          Query.equal('userId', userId),
          Query.equal('commentId', commentId),
          Query.limit(1),
        ],
      );
      return res.rows.isNotEmpty;
    } catch (_) {
      return false;
    }
  }

  static Future<Set<String>> fetchLikedCommentIds(
    String userId, {
    Iterable<String>? commentIds,
  }) async {
    if (userId.isEmpty) return <String>{};
    final wanted = commentIds == null
        ? <String>{}
        : commentIds
            .map((id) => id.trim())
            .where((id) => id.isNotEmpty)
            .toSet();
    try {
      final res = await _tables.listRows(
        databaseId: databaseId,
        tableId: commentLikesCollectionId,
        queries: [
          Query.equal('userId', userId),
          Query.limit(500),
        ],
      );
      return res.rows
          .map((row) => (row.data['commentId'] as String?)?.trim())
          .whereType<String>()
          .where(
              (id) => id.isNotEmpty && (wanted.isEmpty || wanted.contains(id)))
          .toSet();
    } catch (_) {
      return <String>{};
    }
  }

  static Future<void> likeComment(String commentId) async {
    final user = await getCurrentUser();
    if (user == null) {
      throw StateError('User must be signed in to like comments.');
    }
    if (await isCommentLikedBy(user.$id, commentId)) {
      return;
    }
    final profile = await getProfileByUserId(user.$id);
    final displayName =
        ((profile?.data['displayName'] as String?)?.trim().isNotEmpty == true)
            ? (profile!.data['displayName'] as String).trim()
            : (((profile?.data['username'] as String?)?.trim().isNotEmpty ==
                    true)
                ? (profile!.data['username'] as String).trim()
                : user.name);
    final avatar = profile?.data['avatarUrl'] as String? ?? '';
    await _tables.createRow(
      databaseId: databaseId,
      tableId: commentLikesCollectionId,
      rowId: ID.unique(),
      permissions: [
        Permission.read(Role.any()),
        Permission.write(Role.user(user.$id)),
      ],
      data: {
        'commentId': commentId,
        'userId': user.$id,
        'createdAt': DateTime.now().toIso8601String(),
        'isActive': true,
        'deviceType': Platform.operatingSystem,
      },
    );
    await incrementCommentLikes(commentId, 1);
    unawaited(() async {
      try {
        final comment = await _tables.getRow(
          databaseId: databaseId,
          tableId: commentsCollectionId,
          rowId: commentId,
        );
        final recipientId = (comment.data['userId'] as String?)?.trim() ?? '';
        final postId = (comment.data['postId'] as String?)?.trim() ?? '';
        if (recipientId.isEmpty || recipientId == user.$id || postId.isEmpty) {
          return;
        }
        await _createInAppNotification(
          recipientUserId: recipientId,
          title: displayName,
          body: 'liked your comment',
          type: 'comment_like',
          actorName: displayName,
          actorAvatar: avatar,
          actionUrl: '/post/$postId',
          postId: postId,
          creatorId: user.$id,
        );
      } catch (_) {}
    }());
  }

  static Future<void> unlikeComment(String commentId) async {
    final user = await getCurrentUser();
    if (user == null) return;
    try {
      final res = await _tables.listRows(
        databaseId: databaseId,
        tableId: commentLikesCollectionId,
        queries: [
          Query.equal('userId', user.$id),
          Query.equal('commentId', commentId),
        ],
      );
      for (final row in res.rows) {
        await _tables.deleteRow(
          databaseId: databaseId,
          tableId: commentLikesCollectionId,
          rowId: row.$id,
        );
      }
      await incrementCommentLikes(commentId, -1);
    } catch (_) {}
  }

  static Future<void> deleteComment(String commentId) async {
    await _tables.deleteRow(
      databaseId: databaseId,
      tableId: commentsCollectionId,
      rowId: commentId,
    );
  }

  static Future<void> deletePost(String postId) async {
    await _tables.deleteRow(
      databaseId: databaseId,
      tableId: postsCollectionId,
      rowId: postId,
    );
  }

  static Future<void> deleteMessage(String messageId) async {
    await _tables.deleteRow(
      databaseId: databaseId,
      tableId: messagesCollectionId,
      rowId: messageId,
    );
  }


  static Future<void> createStatus(
    String statusId,
    String userId,
    String mediaPath,
    DateTime timestamp, {
    String caption = '',
  }) async {
    try {
      await _tables.createRow(
        databaseId: databaseId,
        tableId: statusesCollectionId,
        rowId: statusId,
        data: {
          'timestamp': timestamp.toUtc().toIso8601String(),
          if (caption.isNotEmpty) 'caption': caption,
          'userId': userId,
          'statusId': statusId,
          'mediaPath': mediaPath,
        },
      );
    } catch (_) {}
  }

  static Future<List<StatusUpdate>> fetchStatuses({int limit = 40}) async {
    try {
      final res = await _tables.listRows(
        databaseId: databaseId,
        tableId: statusesCollectionId,
        queries: <String>[Query.orderDesc('timestamp'), Query.limit(limit)],
      );
      final List<StatusUpdate> items = [];
      final Map<String, models.Row?> profileCache = {};
      for (final row in res.rows) {
        final data = row.data;
        final timestampStr = data['timestamp'] as String?;
        final timestamp =
            DateTime.tryParse(timestampStr ?? '') ?? DateTime.now();
        final userId = data['userId'] as String? ?? '';
        String username = 'User';
        String userAvatar = '';
        String? mediaPath = data['mediaPath'] as String?;
        if (userId.isNotEmpty) {
          models.Row? profile;
          if (profileCache.containsKey(userId)) {
            profile = profileCache[userId];
          } else {
            profile = await getProfileByUserId(userId);
            profileCache[userId] = profile;
          }
          if (profile != null) {
            final profileData = profile.data;
            username = (profileData['displayName'] as String?)?.trim() ??
                (profileData['username'] as String?)?.trim() ??
                username;
            final rawAvatar = (profileData['avatarUrl'] as String?)?.trim();
            if (rawAvatar != null && rawAvatar.isNotEmpty) {
              userAvatar = rawAvatar.startsWith('http')
                  ? rawAvatar
                  : await StorageService.getSignedUrl(rawAvatar);
            }
          }
        }
        final List<String> mediaUrls = [];
        if (mediaPath != null && mediaPath.isNotEmpty) {
          try {
            final signed = await StorageService.getSignedUrl(mediaPath);
            mediaUrls.add(signed);
          } catch (_) {}
        }
        items.add(
          StatusUpdate(
            id: row.$id,
            username: username,
            userAvatar: userAvatar,
            timestamp: timestamp,
            isViewed: false,
            mediaCount: mediaUrls.length,
            mediaUrls: mediaUrls,
            caption: data['caption'] as String? ?? '',
            likes: (data['likes'] as num?)?.toInt() ?? 0,
            views: (data['views'] as num?)?.toInt() ?? 0,
            isUploading: false,
          ),
        );
      }
      return items;
    } catch (_) {
      return [];
    }
  }

  static Future<List<AppNotification>> fetchNotifications(
    String userId, {
    int limit = 20,
  }) async {
    try {
      final res = await _tables.listRows(
        databaseId: databaseId,
        tableId: notificationsCollectionId,
        queries: <String>[
          Query.equal('userId', userId),
          Query.orderDesc('timestamp'),
          Query.limit(limit),
        ],
      );
      final List<AppNotification> items = [];
      for (final row in res.rows) {
        final data = row.data;
        final timestampStr = data['timestamp'] as String?;
        final timestamp =
            DateTime.tryParse(timestampStr ?? '') ?? DateTime.now();
        items.add(
          AppNotification(
            id: row.$id,
            title: data['title'] as String? ?? 'Notification',
            body: data['body'] as String? ?? '',
            timestamp: timestamp,
            read: data['read'] == true,
            actorName: data['actorName'] as String?,
            actorAvatar: data['actorAvatar'] as String?,
            type: data['type'] as String?,
            actionUrl: data['actionUrl'] as String?,
            postId: data['postId'] as String?,
            chatId: data['chatId'] as String?,
          ),
        );
      }
      return items;
    } catch (_) {
      return [];
    }
  }

  static Future<void> cleanupExpiredStatuses() async {
    try {
      final cutoff = DateTime.now()
          .subtract(const Duration(hours: 24))
          .toUtc()
          .toIso8601String();
      while (true) {
        final res = await _tables.listRows(
          databaseId: databaseId,
          tableId: statusesCollectionId,
          queries: <String>[
            Query.lessThan('timestamp', cutoff),
            Query.limit(100),
          ],
        );
        if (res.rows.isEmpty) break;
        for (final row in res.rows) {
          final data = row.data;
          final mediaPath = data['mediaPath'] as String?;
          if (mediaPath != null && mediaPath.isNotEmpty) {
            try {
              await StorageService.deleteFile(mediaPath);
            } catch (_) {}
          }
          await _tables.deleteRow(
            databaseId: databaseId,
            tableId: statusesCollectionId,
            rowId: row.$id,
          );
        }
        if (res.rows.length < 100) break;
      }
    } catch (_) {}
  }

  static Future<void> incrementStatusViews(String statusId, int delta) async {
    if (delta == 0) return;
    try {
      final row = await getRow(statusesCollectionId, statusId);
      final current = (row.data['views'] as num?)?.toInt() ?? 0;
      final next = current + delta;
      await updateRow(statusesCollectionId, statusId, {
        'views': next < 0 ? 0 : next,
      });
    } catch (_) {}
  }



  // Profiles
  static Future<models.Row?> getProfileByUserId(String userId) async {
    final cached = _profileCache[userId];
    if (cached != null) {
      final username = cached.data['username'] as String?;
      if (username != null && username.trim().isNotEmpty) {
        _cacheProfilePreviewFromData(cached.$id, cached.data);
        return cached;
      }
    }

    // The profiles table primary key is the Supabase Auth UUID.
    // If the caller passed an Appwrite-style hex ID (not a UUID), resolve the
    // real UUID from the current Supabase Auth session instead.
    String resolvedId = userId;
    if (!RegExp(r'^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$', caseSensitive: false).hasMatch(userId)) {
      final supabaseUid = Supabase.instance.client.auth.currentUser?.id;
      if (supabaseUid != null && supabaseUid.isNotEmpty) {
        resolvedId = supabaseUid;
        // Check cache under the resolved ID too.
        final cachedByUuid = _profileCache[resolvedId];
        if (cachedByUuid != null) {
          _profileCache[userId] = cachedByUuid; // alias
          return cachedByUuid;
        }
      }
    }

    try {
      final row = await getRow(profilesCollectionId, resolvedId);
      _profileCache[resolvedId] = row;
      if (resolvedId != userId) _profileCache[userId] = row; // alias Appwrite ID
      _cacheProfilePreviewFromData(row.$id, row.data);
      if (_currentUserCache != null && userId == _currentUserCache!.$id) {
        unawaited(_saveProfileToPrefs(row));
      }
      return row;
    } catch (e, stack) {
      debugPrint('Error loading profile for $userId (resolved $resolvedId): $e');
      debugPrint(stack.toString());
      return null;
    }
  }


  static models.Row? getCachedProfileByUserId(String userId) {
    return _profileCache[userId];
  }

  static final Map<String, models.Row> _profileCache = <String, models.Row>{};

  static models.Row? peekCachedProfileByUserId(String userId) {
    final safeUserId = userId.trim();
    if (safeUserId.isEmpty) return null;
    return _profileCache[safeUserId];
  }

  static void _cacheProfilePreviewFromData(
    String fallbackUserId,
    Map<String, dynamic> data,
  ) {
    final userId = _stringValue(data['userId']).isNotEmpty
        ? _stringValue(data['userId'])
        : fallbackUserId;
    if (userId.isEmpty) return;
    ProfilePreviewCache.set(
      ProfilePreview(
        userId: userId,
        displayName: _stringValue(data['displayName']),
        username: _stringValue(data['username']),
        avatarUrl: _stringValue(data['avatarUrl']),
      ),
    );
  }

  static Future<void> updateUserProfile(
    String userId,
    Map<String, dynamic> data,
  ) async {
    // Ensure required username/displayName are always present.
    final existing = await getProfileByUserId(userId);
    final existingData = existing?.data ?? <String, dynamic>{};

    final String username = (data['username'] as String?) ??
        (existingData['username'] as String?) ??
        '';

    final String displayName = (data['displayName'] as String?) ??
        (existingData['displayName'] as String?) ??
        username;

    final payload = <String, dynamic>{
      ...data,
      'userId': userId,
      'username': username,
      'displayName': displayName,
    };
    try {
      await updateRow(profilesCollectionId, userId, payload);
    } on DatabaseException catch (e) {
      if (e.code == 404) {
        await _tables.createRow(
          databaseId: databaseId,
          tableId: profilesCollectionId,
          rowId: userId,
          data: payload,
        );
      } else {
        rethrow;
      }
    }
    try {
      await Supabase.instance.client.auth.updateUser(
        UserAttributes(
          data: {
            'username': username,
            'displayName': displayName,
          },
        ),
      );
      final freshUser = await _account.get();
      _currentUserCache = freshUser;
      unawaited(_saveUserToPrefs(freshUser));
    } catch (e) {
      debugPrint('Warning: Auth metadata update failed: $e');
    }
    _profileCache.remove(userId);
    _cacheProfilePreviewFromData(
      userId,
      <String, dynamic>{
        ...payload,
        'userId': userId,
      },
    );
  }

  static Future<void> upsertChatDeviceBundle(
    String userId,
    String deviceId,
    Map<String, dynamic> data,
  ) async {
    final rowId = _hashId('${userId}_$deviceId');
    final payload = <String, dynamic>{
      ...data,
      'userId': userId,
      'deviceId': deviceId,
      'updatedAt': DateTime.now().toIso8601String(),
    };
    try {
      await updateRow(chatDevicesCollectionId, rowId, payload);
    } on DatabaseException catch (e) {
      if (e.code == 404) {
        await _tables.createRow(
          databaseId: databaseId,
          tableId: chatDevicesCollectionId,
          rowId: rowId,
          data: <String, dynamic>{
            ...payload,
            'createdAt': DateTime.now().toIso8601String(),
          },
        );
      } else {
        rethrow;
      }
    }
  }

  static Future<models.RowList> fetchChatDevicesForUser(
    String userId, {
    int limit = 20,
  }) async {
    return _tables.listRows(
      databaseId: databaseId,
      tableId: chatDevicesCollectionId,
      queries: <String>[
        Query.equal('userId', userId),
        Query.limit(limit),
      ],
    );
  }

  // Chats & messages
  static Future<models.RowList> fetchChatsForUser(String userId) async {
    final rows = await _tables.listRows(
      databaseId: databaseId,
      tableId: chatsCollectionId,
      queries: <String>[
        Query.orderDesc('createdAt'),
        Query.limit(500),
      ],
    );
    final safeUserId = userId.trim();
    final filtered = rows.rows.where((row) {
      final raw = (row.data['memberIds'] as String?) ?? '';
      return raw
          .split(',')
          .map((e) => e.trim())
          .any((memberId) => memberId == safeUserId);
    }).toList(growable: false);
    return models.RowList(total: filtered.length, rows: filtered);
  }

  static Future<models.RowList> fetchMessagesForChat(
    String chatId, {
    int limit = 100,
    String? cursorId,
  }) async {
    return await _tables.listRows(
      databaseId: databaseId,
      tableId: messagesCollectionId,
      queries: <String>[
        Query.equal('chatId', chatId),
        Query.orderDesc('timestamp'),
        Query.limit(limit),
        if (cursorId != null) Query.cursorAfter(cursorId),
      ],
    );
  }

  // News (separate table for human- and AI-authored articles)
  static Future<models.Row> createNewsArticle(Map<String, dynamic> data) async {
    final rowId = ID.unique();
    return _tables.createRow(
      databaseId: databaseId,
      tableId: newsCollectionId,
      rowId: rowId,
      data: <String, dynamic>{...data, 'newsId': data['newsId'] ?? rowId},
    );
  }

  static Future<models.RowList> fetchNewsArticles({
    int limit = 20,
    String? cursorId,
  }) async {
    return _tables.listRows(
      databaseId: databaseId,
      tableId: newsCollectionId,
      queries: <String>[
        Query.orderDesc('createdAt'),
        Query.limit(limit),
        if (cursorId != null) Query.cursorAfter(cursorId),
      ],
    );
  }
}

class Account {
  Account(dynamic client);

  Client get client => Client();

  Future<models.User> get() async {
    final user = Supabase.instance.client.auth.currentUser;
    if (user == null) {
      throw const AuthException('No current user found');
    }
    return models.User.fromMap({
      '\$id': user.id,
      '\$createdAt': user.createdAt,
      '\$updatedAt': user.updatedAt ?? user.createdAt,
      'name': user.userMetadata?['displayName'] ?? user.userMetadata?['username'] ?? '',
      'email': user.email ?? '',
      'phone': '',
      'status': true,
      'emailVerification': true,
      'phoneVerification': true,
      'prefs': <String, dynamic>{},
      'accessedAt': DateTime.now().toIso8601String(),
      'labels': <String>[],
      'mfa': false,
      'passwordUpdate': DateTime.now().toIso8601String(),
      'registration': DateTime.now().toIso8601String(),
      'targets': <dynamic>[],
    });
  }

  Future<void> create({
    required String userId,
    required String email,
    required String password,
    String? name,
  }) async {
    final res = await Supabase.instance.client.auth.signUp(
      email: email,
      password: password,
      data: {
        'username': name ?? '',
        'displayName': name ?? '',
      },
    );
    if (res.user == null) {
      throw const AuthException('Signup failed');
    }
  }

  Future<models.Session> createEmailPasswordSession({
    required String email,
    required String password,
  }) async {
    final authRes = await Supabase.instance.client.auth.signInWithPassword(
      email: email,
      password: password,
    );
    return models.Session.fromMap({
      '\$id': authRes.session?.accessToken ?? 'dummy_session',
      '\$createdAt': DateTime.now().toIso8601String(),
      'userId': authRes.user?.id ?? 'dummy_user_id',
      'expire': DateTime.now().add(const Duration(days: 7)).toIso8601String(),
      'provider': 'email',
      'providerUid': '',
      'providerAccessToken': '',
      'providerAccessTokenExpiry': '',
      'providerRefreshToken': '',
      'ip': '',
      'osCode': '',
      'osName': '',
      'osVersion': '',
      'clientType': '',
      'clientCode': '',
      'clientName': '',
      'clientVersion': '',
      'clientEngine': '',
      'clientEngineVersion': '',
      'deviceModel': '',
      'deviceBrand': '',
      'deviceName': '',
      'countryCode': '',
      'countryName': '',
      'current': true,
      'factors': <String>[],
      'mfaUpdatedAt': DateTime.now().toIso8601String(),
      'secret': '',
    });
  }

  Future<void> deleteSession({required String sessionId}) async {
    await Supabase.instance.client.auth.signOut();
  }

  Future<void> deleteSessions() async {
    await Supabase.instance.client.auth.signOut();
  }

  Future<dynamic> createOAuth2Session({required dynamic provider}) async {
    return null;
  }

  Future<dynamic> createRecovery({required String email, required String url}) async {
    return null;
  }

  Future<dynamic> updateRecovery({
    required String userId,
    required String secret,
    required String password,
    String? passwordAgain,
  }) async {
    return null;
  }

  Future<models.Jwt> createJWT() async {
    return models.Jwt.fromMap({
      'jwt': Supabase.instance.client.auth.currentSession?.accessToken ?? '',
    });
  }

  Future<dynamic> createPushTarget({
    required String targetId,
    String? providerId,
    required String identifier,
    String? name,
  }) async {
    return null;
  }

  Future<dynamic> updatePushTarget({
    required String targetId,
    String? providerId,
    required String identifier,
    String? name,
  }) async {
    return null;
  }
}

class TablesDB {
  TablesDB(dynamic client);

  static const List<String> _creatorIdTables = [
    'posts',
    'comments',
    'creator_balances',
    'creator_payouts',
    'ad_impressions'
  ];

  static String _mapTable(String id) {
    return _camelToSnake(id);
  }

  static String _mapColumn(String table, String col) {
    final snake = _camelToSnake(col);
    if (_creatorIdTables.contains(table)) {
      if (snake == 'user_id' || snake == 'creator_id') {
        return 'creator_id';
      }
    }
    if (table == 'creator_payouts' && (snake == 'requested_at' || snake == 'requested')) {
      return 'created_at';
    }
    return snake;
  }

  static String _camelToSnake(String str) {
    if (str == 'commentLikes') return 'comment_likes';
    final reg = RegExp(r'(?<=[a-z])[A-Z]');
    return str.replaceAllMapped(reg, (Match m) => '_${m.group(0)!.toLowerCase()}').toLowerCase();
  }

  static String _snakeToCamel(String str) {
    final reg = RegExp(r'_([a-z])');
    return str.replaceAllMapped(reg, (Match m) => m.group(1)!.toUpperCase());
  }

  static Map<String, dynamic> _keysToSnake(Map<dynamic, dynamic> map) {
    final Map<String, dynamic> result = {};
    map.forEach((key, value) {
      final keyStr = key.toString();
      if (keyStr.startsWith('\$')) {
        result[keyStr] = value;
      } else {
        result[_camelToSnake(keyStr)] = value;
      }
    });
    return result;
  }

  static Map<String, dynamic> keysToCamel(Map<dynamic, dynamic> map) {
    final Map<String, dynamic> result = {};
    map.forEach((key, value) {
      final keyStr = key.toString();
      if (keyStr.startsWith('\$')) {
        result[keyStr] = value;
      } else {
        result[_snakeToCamel(keyStr)] = value;
      }
    });
    return result;
  }

  static models.Row _mapItemToRow(String tableId, Map<dynamic, dynamic> item) {
    final id = item['id']?.toString() ?? '';
    final createdAt = item['created_at']?.toString() ?? DateTime.now().toIso8601String();
    final updatedAt = item['updated_at']?.toString() ?? createdAt;

    final dataMap = keysToCamel(item);
    if (tableId.contains('profile')) {
      dataMap['userId'] = id;
    }
    if (tableId.contains('payout')) {
      dataMap['requestedAt'] = dataMap['createdAt'] ?? createdAt;
    }
    if (dataMap.containsKey('creatorId')) {
      dataMap['userId'] = dataMap['creatorId'];
    } else if (dataMap.containsKey('userId')) {
      dataMap['creatorId'] = dataMap['userId'];
    }

    return models.Row.fromMap({
      '\$id': id,
      '\$sequence': 0,
      '\$tableId': tableId,
      '\$databaseId': 'supabase',
      '\$createdAt': createdAt,
      '\$updatedAt': updatedAt,
      '\$permissions': <dynamic>[],
      'data': dataMap,
    });
  }

  Future<models.Row> getRow({
    required String databaseId,
    required String tableId,
    required String rowId,
  }) async {
    final mapped = _mapTable(tableId);
    final res = await Supabase.instance.client.from(mapped).select().eq('id', rowId).single();
    return _mapItemToRow(mapped, res);
  }

  Future<models.Row> updateRow({
    required String databaseId,
    required String tableId,
    required String rowId,
    required Map<String, dynamic> data,
  }) async {
    final mapped = _mapTable(tableId);
    final cleanData = _keysToSnake(data)
      ..remove('\$id')
      ..remove('\$createdAt')
      ..remove('\$updatedAt');

    if (_creatorIdTables.contains(mapped)) {
      if (cleanData.containsKey('user_id')) {
        cleanData['creator_id'] = cleanData.remove('user_id');
      }
    }

    final res = await Supabase.instance.client
        .from(mapped)
        .update(cleanData)
        .eq('id', rowId)
        .select()
        .single();
    return _mapItemToRow(mapped, res);
  }

  Future<models.Row> createRow({
    required String databaseId,
    required String tableId,
    required String rowId,
    required Map<String, dynamic> data,
    List<dynamic>? permissions,
  }) async {
    final mapped = _mapTable(tableId);
    final cleanData = _keysToSnake(data)
      ..remove('\$id')
      ..remove('\$createdAt')
      ..remove('\$updatedAt');
    
    cleanData['id'] = rowId;

    if (_creatorIdTables.contains(mapped)) {
      if (cleanData.containsKey('user_id')) {
        cleanData['creator_id'] = cleanData.remove('user_id');
      }
    }

    final res = await Supabase.instance.client.from(mapped).insert(cleanData).select().single();
    return _mapItemToRow(mapped, res);
  }

  Future<dynamic> deleteRow({
    required String databaseId,
    required String tableId,
    required String rowId,
  }) async {
    final mapped = _mapTable(tableId);
    await Supabase.instance.client.from(mapped).delete().eq('id', rowId);
    return true;
  }

  Future<models.RowList> listRows({
    required String databaseId,
    required String tableId,
    List<dynamic>? queries,
  }) async {
    final mapped = _mapTable(tableId);
    dynamic builder = Supabase.instance.client.from(mapped).select();

    if (queries != null) {
      for (final q in queries) {
        final queryStr = q.toString();
        if (queryStr.contains('equal(')) {
          final match = RegExp(r'equal\("([^"]+)",\s*\[?"?([^"\]]+)"?\]?\)').firstMatch(queryStr);
          if (match != null) {
            final col = _mapColumn(mapped, match.group(1)!);
            builder = builder.eq(col, match.group(2)!);
          }
        } else if (queryStr.contains('limit(')) {
          final match = RegExp(r'limit\((\d+)\)').firstMatch(queryStr);
          if (match != null) {
            builder = builder.limit(int.parse(match.group(1)!));
          }
        } else if (queryStr.contains('orderDesc(')) {
          final match = RegExp(r'orderDesc\("([^"]+)"\)').firstMatch(queryStr);
          if (match != null) {
            final col = _mapColumn(mapped, match.group(1)!);
            builder = builder.order(col, ascending: false);
          }
        } else if (queryStr.contains('orderAsc(')) {
          final match = RegExp(r'orderAsc\("([^"]+)"\)').firstMatch(queryStr);
          if (match != null) {
            final col = _mapColumn(mapped, match.group(1)!);
            builder = builder.order(col, ascending: true);
          }
        } else if (queryStr.contains('greaterThanEqual(')) {
          final match = RegExp(r'greaterThanEqual\("([^"]+)",\s*"([^"]+)"\)').firstMatch(queryStr);
          if (match != null) {
            final col = _mapColumn(mapped, match.group(1)!);
            builder = builder.gte(col, match.group(2)!);
          }
        } else if (queryStr.contains('lessThan(')) {
          final match = RegExp(r'lessThan\("([^"]+)",\s*"([^"]+)"\)').firstMatch(queryStr);
          if (match != null) {
            final col = _mapColumn(mapped, match.group(1)!);
            builder = builder.lt(col, match.group(2)!);
          }
        } else if (queryStr.contains('search(')) {
          final match = RegExp(r'search\("([^"]+)",\s*"([^"]+)"\)').firstMatch(queryStr);
          if (match != null) {
            final col = _mapColumn(mapped, match.group(1)!);
            builder = builder.ilike(col, '%${match.group(2)!}%');
          }
        }
      }
    }

    final List<dynamic> res = await builder;
    return models.RowList.fromMap({
      'total': res.length,
      'rows': res.map((item) {
        final camelMap = keysToCamel(item);
        return {
          '\$id': item['id']?.toString() ?? '',
          '\$createdAt': item['created_at']?.toString() ?? DateTime.now().toIso8601String(),
          '\$updatedAt': item['updated_at']?.toString() ?? DateTime.now().toIso8601String(),
          '\$collectionId': mapped,
          '\$databaseId': 'supabase',
          '\$permissions': <dynamic>[],
          'data': {
            ...camelMap,
            '\$id': item['id']?.toString() ?? '',
            '\$createdAt': item['created_at']?.toString() ?? DateTime.now().toIso8601String(),
            '\$updatedAt': item['updated_at']?.toString() ?? DateTime.now().toIso8601String(),
          },
        };
      }).toList(),
    });
  }
}

class Realtime {
  // ignore: avoid_unused_constructor_parameters
  Realtime(dynamic client);

  RealtimeSubscription subscribe(List<String> channels) {
    return RealtimeSubscription(channels);
  }
}

class RealtimeSubscription {
  final List<String> channels;
  final StreamController<RealtimeMessage> _controller = StreamController<RealtimeMessage>.broadcast();
  final List<RealtimeChannel> _supabaseChannels = [];

  Stream<RealtimeMessage> get stream => _controller.stream;

  RealtimeSubscription(this.channels) {
    _init();
  }

  static String _camelToSnake(String str) {
    if (str == 'commentLikes') return 'comment_likes';
    if (str == 'postBoosts') return 'post_boosts';
    final reg = RegExp(r'(?<=[a-z])[A-Z]');
    return str.replaceAllMapped(reg, (Match m) => '_${m.group(0)!.toLowerCase()}').toLowerCase();
  }

  void _init() {
    for (final channelStr in channels) {
      final parts = channelStr.split('.');
      if (parts.length < 4) continue;
      
      final collectionId = parts[3];
      String? documentId;
      if (parts.length > 5) {
        documentId = parts[5];
      }

      final tableName = _camelToSnake(collectionId);
      final filterObj = documentId != null
          ? PostgresChangeFilter(
              type: PostgresChangeFilterType.eq,
              column: 'id',
              value: documentId,
            )
          : null;

      final channelName = 'realtime_$collectionId${documentId != null ? "_$documentId" : ""}';
      final supabaseChannel = Supabase.instance.client.channel(channelName);

      supabaseChannel.onPostgresChanges(
        event: PostgresChangeEvent.all,
        schema: 'public',
        table: tableName,
        filter: filterObj,
        callback: (payload) {
          final record = (payload.eventType == PostgresChangeEvent.delete)
              ? payload.oldRecord
              : payload.newRecord;

          if (record.isEmpty) return;

          final camelPayload = TablesDB.keysToCamel(record);
          camelPayload['\$id'] = record['id'] ?? '';
          if (record['created_at'] != null) {
            camelPayload['\$createdAt'] = record['created_at'];
          }
          if (record['updated_at'] != null) {
            camelPayload['\$updatedAt'] = record['updated_at'];
          }

          String eventName = '';
          switch (payload.eventType) {
            case PostgresChangeEvent.insert:
              eventName = 'databases.${BackendService.databaseId}.collections.$collectionId.documents.${record["id"]}.create';
              break;
            case PostgresChangeEvent.update:
              eventName = 'databases.${BackendService.databaseId}.collections.$collectionId.documents.${record["id"]}.update';
              break;
            case PostgresChangeEvent.delete:
              eventName = 'databases.${BackendService.databaseId}.collections.$collectionId.documents.${record["id"]}.delete';
              break;
            default:
              break;
          }

          if (eventName.isNotEmpty) {
            _controller.add(RealtimeMessage(
              events: [eventName],
              payload: camelPayload,
              timestamp: DateTime.now().toIso8601String(),
              channels: [channelStr],
            ));
          }
        },
      );

      supabaseChannel.subscribe();
      _supabaseChannels.add(supabaseChannel);
    }
  }

  void close() {
    for (final channel in _supabaseChannels) {
      Supabase.instance.client.removeChannel(channel);
    }
    _controller.close();
  }
}

class RealtimeMessage {
  final List<String> events;
  final Map<String, dynamic> payload;
  final String timestamp;
  final List<String> channels;

  RealtimeMessage({
    required this.events,
    required this.payload,
    required this.timestamp,
    required this.channels,
  });
}

