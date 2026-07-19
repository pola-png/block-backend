class Story {
  final String id;
  final String username;
  final String imageUrl;
  final bool isViewed;
  final bool isUploading;
  final bool hasActiveStories;

  Story({
    required this.id,
    required this.username,
    required this.imageUrl,
    this.isViewed = false,
    this.isUploading = false,
    this.hasActiveStories = false,
  });
}
