class AppNotification {
  final String id;
  final String title;
  final String body;
  final DateTime timestamp;
  final bool read;
  final String? actorName;
  final String? actorAvatar;
  final String? type;
  final String? actionUrl;
  final String? postId;
  final String? chatId;

  AppNotification({
    required this.id,
    required this.title,
    required this.body,
    required this.timestamp,
    this.read = false,
    this.actorName,
    this.actorAvatar,
    this.type,
    this.actionUrl,
    this.postId,
    this.chatId,
  });
}
