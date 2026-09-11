import '../models/chat.dart';
import '../services/backend_service.dart';
import '../services/chat_message_cache.dart';
import '../services/crypto_service.dart';

class ChatPrefetchService {
  static bool _running = false;

  static Future<void> preloadInbox({
    int chatLimit = 20,
    int messageLimit = 30,
  }) async {
    if (_running) return;
    _running = true;

    try {
      final me = await BackendService.getCurrentUser();
      if (me == null) return;

      final chats = await BackendService.fetchChatsForUser(me.$id);
      final rows = chats.rows.take(chatLimit).toList(growable: false);
      for (final row in rows) {
        await _preloadChatMessages(
          chatId: row.$id,
          partnerUserId: _partnerIdForRow(row.data, me.$id),
          currentUserId: me.$id,
          limit: messageLimit,
        );
      }
    } catch (_) {
      // Best-effort cache warmup only.
    } finally {
      _running = false;
    }
  }

  static String _partnerIdForRow(Map<String, dynamic> data, String meId) {
    final rawIds = (data['memberIds'] as String?) ?? '';
    final userIds = rawIds
        .split(',')
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty)
        .toList();
    if (userIds.length < 2) return '';
    return userIds.firstWhere((id) => id != meId, orElse: () => '');
  }

  static Future<void> _preloadChatMessages({
    required String chatId,
    required String partnerUserId,
    required String currentUserId,
    required int limit,
  }) async {
    if (chatId.isEmpty || partnerUserId.isEmpty) return;
    final cached = ChatMessageCache.get(chatId);
    if (cached != null && cached.messages.isNotEmpty) return;

    try {
      final messages = <Message>[];
      String? cursorId;
      while (true) {
        final page = await BackendService.fetchMessagesForChat(
          chatId,
          limit: limit,
          cursorId: cursorId,
        );
        if (page.rows.isEmpty) break;

        for (final row in page.rows) {
          final message = await _decodeMessageRow(
            chatId: chatId,
            partnerUserId: partnerUserId,
            currentUserId: currentUserId,
            rowId: row.$id,
            data: row.data,
          );
          if (message != null) {
            messages.add(message);
          }
        }

        if (page.rows.length < limit) break;
        cursorId = page.rows.last.$id;
      }

      if (messages.isNotEmpty) {
        messages.sort((a, b) => a.timestamp.compareTo(b.timestamp));
        ChatMessageCache.set(chatId, messages);
      }
    } catch (_) {}
  }

  static Future<Message?> _decodeMessageRow({
    required String chatId,
    required String partnerUserId,
    required String currentUserId,
    required String rowId,
    required Map<String, dynamic> data,
  }) async {
    final mediaUrl = (data['mediaUrl'] as String?)?.trim();
    final thumbnailUrl = (data['thumbnailUrl'] as String?)?.trim();
    final mediaType = (data['mediaType'] as String?)?.trim();
    final content = (data['content'] as String?)?.trim() ?? '';
    final cipher = data['ciphertext'] as String? ?? '';
    final nonce = data['nonce'] as String? ?? '';
    final mac = data['mac'] as String? ?? '';

    String text = content;
    if (cipher.isNotEmpty && nonce.isNotEmpty && mac.isNotEmpty) {
      final decrypted = await CryptoService.decryptMessage(
        chatId: chatId,
        partnerUserId: partnerUserId,
        ciphertextB64: cipher,
        nonceB64: nonce,
        macB64: mac,
      );
      if (decrypted != null && decrypted.trim().isNotEmpty) {
        text = decrypted.trim();
      }
    }

    if (text.isEmpty && (mediaUrl == null || mediaUrl.isEmpty)) {
      return null;
    }

    final senderId = (data['senderId'] as String?) ?? '';
    final createdAtStr =
        data['timestamp'] as String? ?? data['createdAt'] as String?;
    final createdAt = DateTime.tryParse(createdAtStr ?? '') ?? DateTime.now();
    final readBy = _readByList(data['readBy']);
    final isRead = readBy.contains(currentUserId);
    final isSent = senderId == currentUserId;
    final deliveryStatus = _deliveryStatusFromData(
      data,
      isSent: isSent,
      isRead: isRead,
    );

    return Message(
      id: rowId,
      content: text,
      mediaUrl: mediaUrl?.isNotEmpty == true ? mediaUrl : null,
      thumbnailUrl: thumbnailUrl?.isNotEmpty == true ? thumbnailUrl : null,
      mediaType: mediaType?.isNotEmpty == true ? mediaType : null,
      timestamp: createdAt,
      isSent: isSent,
      isRead: isRead,
      deliveryStatus: deliveryStatus,
    );
  }

  static List<String> _readByList(dynamic rawValue) {
    if (rawValue is List) {
      return rawValue
          .map((e) => e.toString().trim())
          .where((e) => e.isNotEmpty)
          .toList();
    }
    final raw = (rawValue as String?) ?? '';
    return raw
        .split(',')
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty)
        .toList();
  }

  static MessageDeliveryStatus _deliveryStatusFromData(
    Map<String, dynamic> data, {
    required bool isSent,
    required bool isRead,
  }) {
    final raw = data['deliveryStatus'];
    final normalized = raw?.toString().trim().toLowerCase() ?? '';
    switch (normalized) {
      case 'pending':
        return MessageDeliveryStatus.pending;
      case 'sent':
        return MessageDeliveryStatus.sent;
      case 'delivered':
        return MessageDeliveryStatus.delivered;
      case 'read':
        return MessageDeliveryStatus.read;
      case 'failed':
        return MessageDeliveryStatus.failed;
    }
    if (isRead) return MessageDeliveryStatus.read;
    if (isSent) return MessageDeliveryStatus.sent;
    return MessageDeliveryStatus.sent;
  }
}
