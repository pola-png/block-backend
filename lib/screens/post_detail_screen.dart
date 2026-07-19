import 'package:flutter/material.dart';
import 'package:lucide_icons/lucide_icons.dart';
import '../models/post.dart';
import '../services/appwrite_service.dart';
import '../screens/comment_screen.dart';
import '../widgets/post_card.dart';
import '../widgets/tv_focusable_action.dart';
import '../utils/news_seo.dart';

class PostDetailScreen extends StatefulWidget {
  final Post post;
  final List<String>? mediaUrls;
  final String? authorId;
  final bool isGuest;
  final VoidCallback? onGuestAction;

  const PostDetailScreen({
    super.key,
    required this.post,
    this.mediaUrls,
    this.authorId,
    this.isGuest = false,
    this.onGuestAction,
  });

  @override
  State<PostDetailScreen> createState() => _PostDetailScreenState();
}

class _PostDetailScreenState extends State<PostDetailScreen> {
  NewsSeo? _newsSeo;

  @override
  void initState() {
    super.initState();
    _maybeInitNewsSeo();
  }

  void _maybeInitNewsSeo() {
    final postType = widget.post.postType?.toLowerCase() ?? '';
    final isNews = postType.contains('news') || postType.contains('blog');
    if (!isNews) return;
    final seo = buildNewsSeo(widget.post.title ?? '', widget.post.content);
    setState(() => _newsSeo = seo);
    // Best-effort: persist SEO fields back to Appwrite for future use.
    AppwriteService.updatePostSeo(
      widget.post.id,
      seoTitle: seo.seoTitle,
      seoDescription: seo.seoDescription,
      seoSlug: seo.seoSlug,
      seoKeywords: seo.seoKeywords,
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        backgroundColor: theme.colorScheme.surface,
        title: Text(
          'Post',
          style: TextStyle(color: theme.colorScheme.onSurface),
        ),
        iconTheme: IconThemeData(color: theme.iconTheme.color),
      ),
      backgroundColor: theme.scaffoldBackgroundColor,
      body: Column(
        children: [
          Expanded(
            child: ListView.builder(
              padding: EdgeInsets.zero,
              itemCount: 1 + (_newsSeo != null ? 1 : 0) + 1,
              itemBuilder: (context, index) {
                if (index == 0) {
                  return Container(
                    margin: const EdgeInsets.only(bottom: 8),
                    decoration: BoxDecoration(
                      color: Theme.of(context).colorScheme.surface,
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.05),
                          blurRadius: 6,
                          offset: const Offset(0, 3),
                        ),
                      ],
                    ),
                    child: PostCard(
                      post: widget.post,
                      isGuest: widget.isGuest,
                      onGuestAction: widget.onGuestAction,
                      mediaUrls: widget.mediaUrls,
                      authorId: widget.authorId,
                      onOpenPost: null,
                      isDetail: true,
                    ),
                  );
                }
                if (index == 1 && _newsSeo != null) {
                  final seo = _newsSeo!;
                  return Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(
                        horizontal: 16, vertical: 12),
                    margin: const EdgeInsets.only(bottom: 8),
                    color: theme.colorScheme.surface,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'SEO summary',
                          style: theme.textTheme.labelLarge?.copyWith(
                            fontWeight: FontWeight.w700,
                            color: theme.colorScheme.primary,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          seo.seoTitle,
                          style: theme.textTheme.titleMedium,
                        ),
                        const SizedBox(height: 4),
                        Text(
                          seo.seoDescription,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                        if (seo.seoKeywords.isNotEmpty) ...[
                          const SizedBox(height: 8),
                          Wrap(
                            spacing: 6,
                            runSpacing: 4,
                            children: seo.seoKeywords
                                .map(
                                  (k) => Chip(
                                    label: Text(k),
                                    materialTapTargetSize:
                                        MaterialTapTargetSize.shrinkWrap,
                                    visualDensity: VisualDensity.compact,
                                  ),
                                )
                                .toList(),
                          ),
                        ],
                      ],
                    ),
                  );
                }
                return _buildCommentsEntry(theme);
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCommentsEntry(ThemeData theme) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
      child: Material(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(20),
        child: TvFocusableAction(
          borderRadius: BorderRadius.circular(20),
          onPressed: _openCommentsModal,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
            child: Row(
              children: [
                Icon(
                  LucideIcons.messageCircle,
                  color: theme.colorScheme.onSurface,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Comments',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                          color: theme.colorScheme.onSurface,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'Open comments in the shared modal screen',
                        style: TextStyle(
                          fontSize: 13,
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
                Text(
                  '${widget.post.comments}',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(width: 8),
                Icon(
                  Icons.chevron_right,
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _openCommentsModal() {
    showCommentModal(
      context,
      post: widget.post,
      isGuest: widget.isGuest,
      onGuestAction: widget.onGuestAction,
    );
  }
}
