import 'package:flutter/material.dart';

import '../models/post.dart';
import '../widgets/post_card.dart';

class VideoDetailMetaSection extends StatelessWidget {
  final Post post;
  final String? authorId;
  final bool isGuest;
  final VoidCallback? onGuestAction;
  final VoidCallback onOpenDescription;
  final Widget? bottomSection;
  final Widget? adWidget;

  const VideoDetailMetaSection({
    super.key,
    required this.post,
    required this.authorId,
    required this.isGuest,
    required this.onGuestAction,
    required this.onOpenDescription,
    this.bottomSection,
    this.adWidget,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      decoration: BoxDecoration(
        color: theme.scaffoldBackgroundColor,
        borderRadius: const BorderRadius.only(
          topLeft: Radius.circular(24),
          topRight: Radius.circular(24),
        ),
      ),
      child: ListView(
        padding: EdgeInsets.zero,
        children: [
          if (post.title?.trim().isNotEmpty == true ||
              post.content.trim().isNotEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 12, 6),
              child: Row(
                children: [
                  if (post.title?.trim().isNotEmpty == true)
                    Expanded(
                      child: Text(
                        post.title!.trim(),
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  if (post.content.trim().isNotEmpty)
                    IconButton(
                      tooltip: 'Open description',
                      onPressed: onOpenDescription,
                      icon: Icon(
                        Icons.more_horiz,
                        color: theme.colorScheme.onSurface,
                      ),
                    ),
                ],
              ),
            ),
          PostCard(
            post: _copyWithoutImage(post),
            isGuest: isGuest,
            onGuestAction: onGuestAction,
            mediaUrls: const <String>[],
            authorId: authorId,
            onOpenPost: null,
            isDetail: true,
            showViewsLabel: true,
            showVideoMeta: false,
          ),
          if (adWidget != null) ...[
            Padding(
              padding: const EdgeInsets.fromLTRB(0, 4, 0, 12),
              child: adWidget!,
            ),
          ],
          if (bottomSection != null) ...[
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: bottomSection!,
            ),
          ],
          const SizedBox(height: 8),
        ],
      ),
    );
  }

  Post _copyWithoutImage(Post original) {
    return Post(
      id: original.id,
      username: original.username,
      userAvatar: original.userAvatar,
      content: original.content,
      imageUrl: null,
      videoUrl: original.videoUrl,
      previewVideoUrl: original.previewVideoUrl,
      hlsVideoUrl: original.hlsVideoUrl,
      postType: original.postType,
      title: original.title,
      thumbnailUrl: original.thumbnailUrl,
      timestamp: original.timestamp,
      likes: original.likes,
      comments: original.comments,
      reposts: original.reposts,
      impressions: original.impressions,
      views: original.views,
      isLiked: original.isLiked,
      isReposted: original.isReposted,
      isSaved: original.isSaved,
    );
  }
}
