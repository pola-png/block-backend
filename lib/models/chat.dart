enum MessageDeliveryStatus {
  pending,
  sent,
  delivered,
  read,
  failed,
}

extension MessageDeliveryStatusX on MessageDeliveryStatus {
  String get value => name;

  static MessageDeliveryStatus fromRaw(
    dynamic raw, {
    bool isRead = false,
    bool isSent = false,
  }) {
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
    if (isSent) return MessageDeliveryStatus.sent;
    return MessageDeliveryStatus.sent;
  }
}

class Chat {
  final String id;
  final String partnerId;
  final String partnerName;
  final String partnerAvatar;
  final String lastMessage;
  final DateTime timestamp;
  final int unreadCount;
  final bool isOnline;
  final String lastSenderId;
  final String lastMessageStatus;
  final String lastMessageId;
  final String lastMessageDeliveredAt;
  final String lastMessageReadAt;
  final bool partnerIsVerified;
  final bool partnerIsAdmin;

  Chat({
    required this.id,
    required this.partnerId,
    required this.partnerName,
    required this.partnerAvatar,
    required this.lastMessage,
    required this.timestamp,
    required this.unreadCount,
    required this.isOnline,
    this.lastSenderId = '',
    this.lastMessageStatus = '',
    this.lastMessageId = '',
    this.lastMessageDeliveredAt = '',
    this.lastMessageReadAt = '',
    this.partnerIsVerified = false,
    this.partnerIsAdmin = false,
  });

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'id': id,
      'partnerId': partnerId,
      'partnerName': partnerName,
      'partnerAvatar': partnerAvatar,
      'lastMessage': lastMessage,
      'timestamp': timestamp.toIso8601String(),
      'unreadCount': unreadCount,
      'isOnline': isOnline,
      'lastSenderId': lastSenderId,
      'lastMessageStatus': lastMessageStatus,
      'lastMessageId': lastMessageId,
      'lastMessageDeliveredAt': lastMessageDeliveredAt,
      'lastMessageReadAt': lastMessageReadAt,
      'partnerIsVerified': partnerIsVerified,
      'partnerIsAdmin': partnerIsAdmin,
    };
  }

  factory Chat.fromJson(Map<String, dynamic> json) {
    final timestamp =
        DateTime.tryParse((json['timestamp'] as String?) ?? '') ??
            DateTime.fromMillisecondsSinceEpoch(0);
    return Chat(
      id: (json['id'] as String?) ?? '',
      partnerId: (json['partnerId'] as String?) ?? '',
      partnerName: (json['partnerName'] as String?) ?? '',
      partnerAvatar: (json['partnerAvatar'] as String?) ?? '',
      lastMessage: (json['lastMessage'] as String?) ?? '',
      timestamp: timestamp.isUtc ? timestamp.toLocal() : timestamp,
      unreadCount: (json['unreadCount'] as num?)?.toInt() ?? 0,
      isOnline: json['isOnline'] == true,
      lastSenderId: (json['lastSenderId'] as String?) ?? '',
      lastMessageStatus: (json['lastMessageStatus'] as String?) ?? '',
      lastMessageId: (json['lastMessageId'] as String?) ?? '',
      lastMessageDeliveredAt: (json['lastMessageDeliveredAt'] as String?) ?? '',
      lastMessageReadAt: (json['lastMessageReadAt'] as String?) ?? '',
      partnerIsVerified: json['partnerIsVerified'] == true,
      partnerIsAdmin: json['partnerIsAdmin'] == true,
    );
  }
}

class Message {
  final String id;
  final String content;
  final String? mediaUrl;
  final String? thumbnailUrl;
  final String? mediaType;
  final DateTime timestamp;
  final bool isSent;
  final bool isRead;
  final MessageDeliveryStatus deliveryStatus;
  final bool isEdited;
  final String? replyToId;
  final String? replyToContent;

  Message({
    required this.id,
    required this.content,
    this.mediaUrl,
    this.thumbnailUrl,
    this.mediaType,
    required this.timestamp,
    required this.isSent,
    this.isRead = false,
    this.deliveryStatus = MessageDeliveryStatus.sent,
    this.isEdited = false,
    this.replyToId,
    this.replyToContent,
  });

  bool get hasMedia => mediaUrl != null && mediaUrl!.isNotEmpty;
  bool get isImage => mediaType == 'image';
  bool get isVideo => mediaType == 'video';
  bool get isVoice => mediaType == 'voice';
}
