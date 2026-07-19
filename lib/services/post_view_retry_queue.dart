import 'dart:async';
import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import 'appwrite_service.dart';

class PostViewRetryQueue {
  static const String _prefsKey = 'pending_post_view_increments_v1';

  static final Map<String, int> _pending = <String, int>{};
  static bool _initialized = false;
  static bool _flushing = false;

  static Future<void> initialize() async {
    if (_initialized) return;
    _initialized = true;
    await _load();
  }

  static Future<void> record(String postId, int delta) async {
    if (postId.trim().isEmpty || delta == 0) return;
    await initialize();
    try {
      await AppwriteService.incrementPostViews(postId, delta);
      unawaited(flushPending());
      return;
    } catch (_) {
      await _enqueue(postId, delta);
      unawaited(flushPending());
    }
  }

  static Future<void> flushPending() async {
    await initialize();
    if (_flushing || _pending.isEmpty) return;
    _flushing = true;
    try {
      final entries = List<MapEntry<String, int>>.from(_pending.entries);
      for (final entry in entries) {
        try {
          await AppwriteService.incrementPostViews(entry.key, entry.value);
          _pending.remove(entry.key);
          await _save();
        } catch (_) {
          // Keep failed items queued for the next retry opportunity.
        }
      }
    } finally {
      _flushing = false;
    }
  }

  static Future<void> _enqueue(String postId, int delta) async {
    _pending[postId] = (_pending[postId] ?? 0) + delta;
    await _save();
  }

  static Future<void> _load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_prefsKey);
      if (raw == null || raw.isEmpty) return;
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return;
      _pending.clear();
      for (final entry in decoded.entries) {
        final value = entry.value;
        final parsed = value is int ? value : int.tryParse('$value') ?? 0;
        if (parsed > 0) {
          _pending[entry.key.toString()] = parsed;
        }
      }
    } catch (_) {
      _pending.clear();
    }
  }

  static Future<void> _save() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      if (_pending.isEmpty) {
        await prefs.remove(_prefsKey);
        return;
      }
      await prefs.setString(_prefsKey, jsonEncode(_pending));
    } catch (_) {}
  }
}
