import 'package:flutter/cupertino.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/status.dart';
import 'appwrite_service.dart';
import 'avatar_cache.dart';

/// Central story cache so HomeScreen and the story viewer stay in sync.
class StoryManager {
  static final ValueNotifier<List<StatusUpdate>> stories =
      ValueNotifier<List<StatusUpdate>>([]);

  static final List<StatusUpdate> _serverStatuses = [];
  static StatusUpdate _myPlaceholder = _buildPlaceholder();
  static const String _viewedPrefsKey = 'viewed_status_ids';
  static Set<String> _viewedStatusIds = <String>{};
  static bool _viewedLoaded = false;

  static StatusUpdate _buildPlaceholder() {
    return StatusUpdate(
      id: 'me',
      username: 'You',
      userAvatar: '',
      timestamp: DateTime.now(),
      isViewed: false,
      mediaCount: 0,
      mediaUrls: const [],
      caption: '',
      likes: 0,
      views: 0,
      isUploading: false,
    );
  }

  static void _emit() {
    stories.value = List.unmodifiable([_myPlaceholder, ..._serverStatuses]);
  }

  static void init() {
    if (stories.value.isNotEmpty) return;

    // Synchronously populate user placeholder with cached avatar and display name on startup
    final me = AppwriteService.getCurrentUserSync();
    if (me != null) {
      final cachedAvatar = AvatarCache.getForUserId(me.$id);
      String displayName = 'You';
      final cachedProfile = AppwriteService.getCachedProfileByUserId(me.$id);
      if (cachedProfile != null) {
        displayName = (cachedProfile.data['displayName'] as String?)?.trim() ?? 'You';
      }
      _myPlaceholder = StatusUpdate(
        id: 'me',
        username: displayName,
        userAvatar: cachedAvatar ?? '',
        timestamp: DateTime.now(),
        isViewed: false,
        mediaCount: 0,
        mediaUrls: const [],
        caption: '',
        likes: 0,
        views: 0,
        isUploading: false,
      );
    }

    _ensureViewedLoaded();
    _emit();
  }

  static Future<void> _ensureViewedLoaded() async {
    if (_viewedLoaded) return;
    final prefs = await SharedPreferences.getInstance();
    _viewedStatusIds =
        prefs.getStringList(_viewedPrefsKey)?.toSet() ?? <String>{};
    _viewedLoaded = true;
  }

  static Future<void> _persistViewed() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(_viewedPrefsKey, _viewedStatusIds.toList());
  }

  static void updateMyProfile({String? username, String? userAvatar}) {
    _myPlaceholder = StatusUpdate(
      id: _myPlaceholder.id,
      username: username ?? _myPlaceholder.username,
      userAvatar: userAvatar ?? _myPlaceholder.userAvatar,
      timestamp: DateTime.now(),
      isViewed: _myPlaceholder.isViewed,
      mediaCount: _myPlaceholder.mediaCount,
      mediaUrls: _myPlaceholder.mediaUrls,
      caption: _myPlaceholder.caption,
      likes: _myPlaceholder.likes,
      views: _myPlaceholder.views,
      isUploading: _myPlaceholder.isUploading,
    );
    _emit();
  }

  static void setMyUploading(
    bool value, {
    String? caption,
    String? mediaPath,
  }) {
    _myPlaceholder = StatusUpdate(
      id: _myPlaceholder.id,
      username: _myPlaceholder.username,
      userAvatar: _myPlaceholder.userAvatar,
      timestamp: DateTime.now(),
      isViewed: _myPlaceholder.isViewed,
      mediaCount: value && mediaPath != null && mediaPath.isNotEmpty ? 1 : 0,
      mediaUrls: value && mediaPath != null && mediaPath.isNotEmpty
          ? <String>[mediaPath]
          : const <String>[],
      caption: caption ?? _myPlaceholder.caption,
      likes: _myPlaceholder.likes,
      views: _myPlaceholder.views,
      isUploading: value,
    );
    _emit();
  }

  static Future<void> addStatus(StatusUpdate status) async {
    await _ensureViewedLoaded();
    status.isViewed = _viewedStatusIds.contains(status.id);
    status.isUploading = false;
    _serverStatuses.removeWhere(
      (s) => DateTime.now().difference(s.timestamp).inHours >= 24,
    );
    _serverStatuses.removeWhere((s) => s.id == status.id);
    _serverStatuses.insert(0, status);
    _emit();
  }

  static Future<void> loadFromServer({int limit = 40}) async {
    try {
      await _ensureViewedLoaded();
      await AppwriteService.cleanupExpiredStatuses();
      final values = await AppwriteService.fetchStatuses(limit: limit);
      _serverStatuses
        ..clear()
        ..addAll(values.where((status) {
          final isFresh =
              DateTime.now().difference(status.timestamp).inHours < 24;
          status.isViewed = _viewedStatusIds.contains(status.id);
          status.isUploading = false;
          return isFresh;
        }));
      _emit();
    } catch (_) {
      // ignore
    }
  }

  static Future<void> markViewed(String statusId) async {
    await _ensureViewedLoaded();
    if (_viewedStatusIds.add(statusId)) {
      await _persistViewed();
    }
    for (final status in _serverStatuses) {
      if (status.id == statusId) {
        status.isViewed = true;
        break;
      }
    }
    _emit();
  }
}
