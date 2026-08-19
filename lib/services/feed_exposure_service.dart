import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import 'backend_service.dart';

class FeedExposureService {
  static const String _prefsKeyPrefix = 'feed_recent_exposures_v2';
  static const String _topPostsKeyPrefix = 'feed_recent_top_posts_v1';
  static const int _maxEntries = 1500;
  static const int _maxRecentTopIdsPerFeed = 6;

  static Future<String> _scopeKey() async {
    try {
      final user = await BackendService.getCurrentUser();
      final userId = user?.$id.trim();
      if (userId != null && userId.isNotEmpty) {
        return 'user_$userId';
      }
    } catch (_) {}
    return 'guest';
  }

  static Future<FeedExposureStore> loadStore() async {
    try {
      final scopeKey = await _scopeKey();
      final prefsKey = '${_prefsKeyPrefix}_$scopeKey';
      final topPostsKey = '${_topPostsKeyPrefix}_$scopeKey';
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(prefsKey);
      if (raw == null || raw.isEmpty) {
        return FeedExposureStore(
          entries: const <String, FeedExposureEntry>{},
          recentTopPostIdsByFeed: _loadRecentTopPostIds(prefs, topPostsKey),
        );
      }
      final decoded = jsonDecode(raw);
      if (decoded is! Map<String, dynamic>) {
        return FeedExposureStore(
          entries: const <String, FeedExposureEntry>{},
          recentTopPostIdsByFeed: _loadRecentTopPostIds(prefs, topPostsKey),
        );
      }
      final entries = <String, FeedExposureEntry>{};
      decoded.forEach((key, value) {
        if (value is Map<String, dynamic>) {
          entries[key] = FeedExposureEntry.fromJson(value);
        }
      });
      return FeedExposureStore(
        entries: entries,
        recentTopPostIdsByFeed: _loadRecentTopPostIds(prefs, topPostsKey),
      );
    } catch (_) {
      return const FeedExposureStore(entries: <String, FeedExposureEntry>{});
    }
  }

  static Future<void> markShown(
    String feedKey,
    Iterable<String> postIds, {
    String? topPostId,
    int maxTracked = 40,
  }) async {
    final trimmed = postIds
        .map((postId) => postId.trim())
        .where((postId) => postId.isNotEmpty)
        .take(maxTracked)
        .toList(growable: false);
    if (trimmed.isEmpty) return;

    try {
      final now = DateTime.now().millisecondsSinceEpoch;
      final scopeKey = await _scopeKey();
      final prefsKey = '${_prefsKeyPrefix}_$scopeKey';
      final topPostsKey = '${_topPostsKeyPrefix}_$scopeKey';
      final prefs = await SharedPreferences.getInstance();
      final store = await loadStore();
      final next = Map<String, FeedExposureEntry>.from(store.entries);

      for (final postId in trimmed) {
        final current = next[postId];
        next[postId] = (current ?? const FeedExposureEntry()).registerExposure(
          feedKey,
          now,
        );
      }

      final sortedKeys = next.keys.toList(growable: false)
        ..sort((a, b) => (next[b]?.lastShownAtMs ?? 0).compareTo(
              next[a]?.lastShownAtMs ?? 0,
            ));
      if (sortedKeys.length > _maxEntries) {
        for (final staleKey in sortedKeys.skip(_maxEntries)) {
          next.remove(staleKey);
        }
      }

      final encoded = <String, dynamic>{};
      next.forEach((key, value) {
        encoded[key] = value.toJson();
      });
      await prefs.setString(prefsKey, jsonEncode(encoded));

      final normalizedTopPostId = topPostId?.trim() ?? '';
      if (normalizedTopPostId.isNotEmpty) {
        final nextRecentTopPostIds = <String, List<String>>{
          ...store.recentTopPostIdsByFeed,
        };
        final currentFeedTopIds =
            List<String>.from(nextRecentTopPostIds[feedKey] ?? const <String>[])
              ..removeWhere((postId) => postId == normalizedTopPostId)
              ..insert(0, normalizedTopPostId);
        if (currentFeedTopIds.length > _maxRecentTopIdsPerFeed) {
          currentFeedTopIds.removeRange(
            _maxRecentTopIdsPerFeed,
            currentFeedTopIds.length,
          );
        }
        nextRecentTopPostIds[feedKey] = currentFeedTopIds;
        await prefs.setString(topPostsKey, jsonEncode(nextRecentTopPostIds));
      }
    } catch (_) {}
  }

  static Map<String, List<String>> _loadRecentTopPostIds(
    SharedPreferences prefs,
    String topPostsKey,
  ) {
    final raw = prefs.getString(topPostsKey);
    if (raw == null || raw.isEmpty) {
      return const <String, List<String>>{};
    }

    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map<String, dynamic>) {
        return const <String, List<String>>{};
      }

      final result = <String, List<String>>{};
      decoded.forEach((key, value) {
        if (value is List) {
          result[key] = value
              .map((item) => item.toString().trim())
              .where((item) => item.isNotEmpty)
              .toList(growable: false);
        }
      });
      return result;
    } catch (_) {
      return const <String, List<String>>{};
    }
  }
}

class FeedExposureStore {
  final Map<String, FeedExposureEntry> entries;
  final Map<String, List<String>> recentTopPostIdsByFeed;

  const FeedExposureStore({
    required this.entries,
    this.recentTopPostIdsByFeed = const <String, List<String>>{},
  });

  double penaltyFor(String postId, String feedKey, DateTime now) {
    final entry = entries[postId];
    if (entry == null || entry.lastShownAtMs <= 0) return 0.0;

    final shownAt = DateTime.fromMillisecondsSinceEpoch(entry.lastShownAtMs);
    final ageHours = now.difference(shownAt).inMilliseconds.abs() / 3600000.0;

    final sameFeedCount = entry.feedCounts[feedKey] ?? 0;
    final totalCount = entry.totalCount;
    if (sameFeedCount <= 0 && totalCount <= 0) return 0.0;

    final sameFeedPenalty = sameFeedCount * 18.0;
    final repeatPenalty = totalCount * 6.0;
    final recencyMultiplier = switch (ageHours) {
      < 2 => 1.0,
      < 6 => 0.85,
      < 24 => 0.65,
      < 72 => 0.4,
      < 168 => 0.2,
      _ => 0.0,
    };

    return ((sameFeedPenalty + repeatPenalty) * recencyMultiplier)
        .clamp(0.0, 90.0);
  }

  bool wasShownRecently(
    String postId,
    String feedKey,
    DateTime now, {
    double withinHours = 24,
  }) {
    final entry = entries[postId];
    if (entry == null || entry.lastShownAtMs <= 0) return false;

    final sameFeedCount = entry.feedCounts[feedKey] ?? 0;
    if (sameFeedCount <= 0) return false;

    final shownAt = DateTime.fromMillisecondsSinceEpoch(entry.lastShownAtMs);
    final ageHours = now.difference(shownAt).inMilliseconds.abs() / 3600000.0;
    return ageHours < withinHours;
  }

  Set<String> recentTopPostIds(String feedKey) {
    return Set<String>.from(
        recentTopPostIdsByFeed[feedKey] ?? const <String>[]);
  }
}

class FeedExposureEntry {
  final int lastShownAtMs;
  final int totalCount;
  final Map<String, int> feedCounts;

  const FeedExposureEntry({
    this.lastShownAtMs = 0,
    this.totalCount = 0,
    this.feedCounts = const <String, int>{},
  });

  factory FeedExposureEntry.fromJson(Map<String, dynamic> json) {
    final feedCounts = <String, int>{};
    final rawFeedCounts = json['feedCounts'];
    if (rawFeedCounts is Map) {
      rawFeedCounts.forEach((key, value) {
        final parsed = value is int ? value : int.tryParse('$value');
        if (key != null && parsed != null) {
          feedCounts[key.toString()] = parsed;
        }
      });
    }
    return FeedExposureEntry(
      lastShownAtMs: json['lastShownAtMs'] is int
          ? json['lastShownAtMs'] as int
          : int.tryParse('${json['lastShownAtMs']}') ?? 0,
      totalCount: json['totalCount'] is int
          ? json['totalCount'] as int
          : int.tryParse('${json['totalCount']}') ?? 0,
      feedCounts: feedCounts,
    );
  }

  FeedExposureEntry registerExposure(String feedKey, int shownAtMs) {
    final nextFeedCounts = Map<String, int>.from(feedCounts);
    nextFeedCounts[feedKey] = (nextFeedCounts[feedKey] ?? 0) + 1;
    return FeedExposureEntry(
      lastShownAtMs: shownAtMs,
      totalCount: totalCount + 1,
      feedCounts: nextFeedCounts,
    );
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
        'lastShownAtMs': lastShownAtMs,
        'totalCount': totalCount,
        'feedCounts': feedCounts,
      };
}
