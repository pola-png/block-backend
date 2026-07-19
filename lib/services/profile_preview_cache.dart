import 'dart:async';
import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

class ProfilePreview {
  final String userId;
  final String displayName;
  final String username;
  final String avatarUrl;

  const ProfilePreview({
    required this.userId,
    required this.displayName,
    required this.username,
    required this.avatarUrl,
  });

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'userId': userId,
      'displayName': displayName,
      'username': username,
      'avatarUrl': avatarUrl,
    };
  }

  factory ProfilePreview.fromJson(Map<String, dynamic> json) {
    return ProfilePreview(
      userId: (json['userId'] as String?) ?? '',
      displayName: (json['displayName'] as String?) ?? '',
      username: (json['username'] as String?) ?? '',
      avatarUrl: (json['avatarUrl'] as String?) ?? '',
    );
  }
}

class ProfilePreviewCache {
  static const String _storageKey = 'profile_preview_cache_v1';
  static final Map<String, ProfilePreview> _entries =
      <String, ProfilePreview>{};
  static SharedPreferences? _prefs;
  static bool _initialized = false;
  static Future<void>? _initFuture;

  static Future<void> initialize() async {
    if (_initialized) return;
    _initialized = true;
    _initFuture ??= _loadFromDisk();
    await _initFuture;
  }

  static List<ProfilePreview> getAll() {
    return _entries.values.toList(growable: false);
  }

  static ProfilePreview? getByUserId(String userId) {
    final safeUserId = userId.trim();
    if (safeUserId.isEmpty) return null;
    return _entries[safeUserId];
  }

  static void set(ProfilePreview preview) {
    if (preview.userId.trim().isEmpty) return;
    _entries[preview.userId] = preview;
    unawaited(_persist());
  }

  static void setAll(List<ProfilePreview> previews) {
    _entries
      ..clear()
      ..addEntries(
        previews.where((preview) => preview.userId.trim().isNotEmpty).map(
              (preview) => MapEntry(preview.userId, preview),
            ),
      );
    unawaited(_persist());
  }

  static void clearAll() {
    _entries.clear();
    unawaited(_persist());
  }

  static Future<void> _loadFromDisk() async {
    try {
      _prefs = await SharedPreferences.getInstance();
      final raw = _prefs?.getString(_storageKey);
      if (raw == null || raw.isEmpty) return;
      final decoded = jsonDecode(raw);
      if (decoded is! Map<String, dynamic>) return;
      decoded.forEach((userId, value) {
        if (value is Map) {
          final preview = ProfilePreview.fromJson(
            value.cast<String, dynamic>(),
          );
          if (preview.userId.isNotEmpty) {
            _entries[userId] = preview;
          }
        }
      });
    } catch (_) {}
  }

  static Future<void> _persist() async {
    try {
      await initialize();
      final payload = <String, dynamic>{};
      for (final entry in _entries.entries) {
        payload[entry.key] = entry.value.toJson();
      }
      await _prefs?.setString(_storageKey, jsonEncode(payload));
    } catch (_) {}
  }
}
