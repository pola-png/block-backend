import 'dart:async';
import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../models/chat.dart';

/// Persistent lightweight inbox cache for chat row previews.
/// Stores just enough data to render the chat list instantly on cold launch.
class ChatPreviewCache {
  static const String _storageKey = 'chat_preview_cache_v1';
  static final Map<String, Chat> _entries = <String, Chat>{};
  static SharedPreferences? _prefs;
  static bool _initialized = false;
  static Future<void>? _initFuture;

  static Future<void> initialize() async {
    if (_initialized) return;
    _initialized = true;
    _initFuture ??= _loadFromDisk();
    await _initFuture;
  }

  static List<Chat> getAll() {
    final chats = _entries.values.toList(growable: false);
    chats.sort((a, b) => b.timestamp.compareTo(a.timestamp));
    return chats;
  }

  static Chat? get(String chatId) => _entries[chatId];

  static void setAll(List<Chat> chats) {
    _entries
      ..clear()
      ..addEntries(chats.map((chat) => MapEntry(chat.id, chat)));
    unawaited(_persist());
  }

  static void set(Chat chat) {
    _entries[chat.id] = chat;
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
      if (decoded is! List) return;
      for (final item in decoded) {
        if (item is! Map) continue;
        final chat = Chat.fromJson(item.cast<String, dynamic>());
        if (chat.id.isEmpty) continue;
        _entries[chat.id] = chat;
      }
    } catch (_) {}
  }

  static Future<void> _persist() async {
    try {
      await initialize();
      final payload = _entries.values.map((chat) => chat.toJson()).toList();
      await _prefs?.setString(_storageKey, jsonEncode(payload));
    } catch (_) {}
  }
}
