import 'dart:async';
import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../models/chat.dart';

class ChatMessageCacheEntry {
  final List<Message> messages;
  final DateTime updatedAt;

  const ChatMessageCacheEntry({
    required this.messages,
    required this.updatedAt,
  });
}

class ChatMessageCache {
  static const String _storageKey = 'chat_message_cache_v1';
  static final Map<String, ChatMessageCacheEntry> _entries =
      <String, ChatMessageCacheEntry>{};
  static SharedPreferences? _prefs;
  static Future<void>? _initFuture;

  static Future<void> initialize() async {
    if (_prefs != null) return;
    _initFuture ??= _loadFromDisk();
    await _initFuture;
  }

  static ChatMessageCacheEntry? get(String chatId) => _entries[chatId];

  static void set(String chatId, List<Message> messages) {
    _entries[chatId] = ChatMessageCacheEntry(
      messages: List<Message>.unmodifiable(messages),
      updatedAt: DateTime.now(),
    );
    unawaited(_persist());
  }

  static void addOrUpdateMessage(String chatId, Message message) {
    final entry = _entries[chatId];
    final messages = entry != null
        ? List<Message>.from(entry.messages)
        : <Message>[];
    final existingIndex = messages.indexWhere((m) => m.id == message.id);
    if (existingIndex >= 0) {
      messages[existingIndex] = message;
    } else {
      messages.add(message);
      messages.sort((a, b) => a.timestamp.compareTo(b.timestamp));
    }
    set(chatId, messages);
  }

  static void markChatAsRead(String chatId) {
    final entry = _entries[chatId];
    if (entry == null) return;
    final updated = entry.messages.map((m) {
      if (!m.isSent && !m.isRead) {
        return Message(
          id: m.id,
          content: m.content,
          mediaUrl: m.mediaUrl,
          thumbnailUrl: m.thumbnailUrl,
          mediaType: m.mediaType,
          timestamp: m.timestamp,
          isSent: m.isSent,
          isRead: true,
          deliveryStatus: MessageDeliveryStatus.read,
        );
      }
      return m;
    }).toList();
    set(chatId, updated);
  }

  static void clear(String chatId) {
    _entries.remove(chatId);
    unawaited(_persist());
  }

  static void removeMessage(String chatId, String messageId) {
    final entry = _entries[chatId];
    if (entry == null) return;
    final messages = List<Message>.from(entry.messages);
    messages.removeWhere((m) => m.id == messageId);
    set(chatId, messages);
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
      decoded.forEach((chatId, value) {
        if (value is! Map) return;
        final messagesRaw = value['messages'];
        final updatedAtRaw = value['updatedAt'] as String?;
        final messages = <Message>[];
        if (messagesRaw is List) {
          for (final item in messagesRaw) {
            if (item is Map) {
              final message = _messageFromMap(item.cast<String, dynamic>());
              if (message != null) messages.add(message);
            }
          }
        }
        final updatedAt = DateTime.tryParse(updatedAtRaw ?? '') ?? DateTime.now();
        _entries[chatId] = ChatMessageCacheEntry(
          messages: List<Message>.unmodifiable(messages),
          updatedAt: updatedAt,
        );
      });
    } catch (_) {}
  }

  static Future<void> _persist() async {
    try {
      await initialize();
      final payload = <String, dynamic>{};
      for (final entry in _entries.entries) {
        payload[entry.key] = <String, dynamic>{
          'updatedAt': entry.value.updatedAt.toIso8601String(),
          'messages': entry.value.messages.map(_messageToMap).toList(),
        };
      }
      await _prefs?.setString(_storageKey, jsonEncode(payload));
    } catch (_) {}
  }

  static Map<String, dynamic> _messageToMap(Message message) {
    return <String, dynamic>{
      'id': message.id,
      'content': message.content,
      'mediaUrl': message.mediaUrl,
      'thumbnailUrl': message.thumbnailUrl,
      'mediaType': message.mediaType,
      'timestamp': message.timestamp.toIso8601String(),
      'isSent': message.isSent,
      'isRead': message.isRead,
      'deliveryStatus': message.deliveryStatus.value,
      'isEdited': message.isEdited,
      'replyToId': message.replyToId,
      'replyToContent': message.replyToContent,
    };
  }

  static Message? _messageFromMap(Map<String, dynamic> data) {
    final id = (data['id'] as String?) ?? '';
    if (id.isEmpty) return null;
    final timestamp = DateTime.tryParse((data['timestamp'] as String?) ?? '') ??
        DateTime.fromMillisecondsSinceEpoch(0);
    return Message(
      id: id,
      content: (data['content'] as String?) ?? '',
      mediaUrl: data['mediaUrl'] as String?,
      thumbnailUrl: data['thumbnailUrl'] as String?,
      mediaType: data['mediaType'] as String?,
      timestamp: timestamp,
      isSent: data['isSent'] == true,
      isRead: data['isRead'] == true,
      deliveryStatus: MessageDeliveryStatusX.fromRaw(
        data['deliveryStatus'],
        isRead: data['isRead'] == true,
        isSent: data['isSent'] == true,
      ),
      isEdited: data['isEdited'] == true,
      replyToId: data['replyToId'] as String?,
      replyToContent: data['replyToContent'] as String?,
    );
  }
}
