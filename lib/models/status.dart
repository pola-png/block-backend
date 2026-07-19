class StatusUpdate {
  final String id;
  final String username;
  final String userAvatar;
  final DateTime timestamp;
  bool isViewed;
  final int mediaCount;
  final List<String> mediaUrls;
  final String caption;
  int likes;
  int views;
  bool isUploading;

  StatusUpdate({
    required this.id,
    required this.username,
    required this.userAvatar,
    required this.timestamp,
    required this.isViewed,
    required this.mediaCount,
    this.mediaUrls = const [],
    this.caption = '',
    this.likes = 0,
    this.views = 0,
    this.isUploading = false,
  });
}

class StatusMedia {
  final String id;
  final String url;
  final MediaType type;
  final Duration duration;

  StatusMedia({
    required this.id,
    required this.url,
    required this.type,
    this.duration = const Duration(seconds: 20),
  });
}

enum MediaType { image, video }
