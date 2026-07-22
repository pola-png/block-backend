import 'package:flutter/material.dart';
import '../models/news_article.dart';

class NewsDetailScreen extends StatelessWidget {
  final NewsArticle article;

  const NewsDetailScreen({
    Key? key,
    required this.article,
  }) : super(key: key);

  String _formatNewsTimestamp(DateTime dt) {
    final local = dt.toLocal();
    final now = DateTime.now();
    final difference = now.difference(local);
    if (difference.inMinutes < 60) {
      final m = difference.inMinutes.clamp(1, 59);
      return '${m}m ago';
    }
    if (difference.inHours < 24) {
      final h = difference.inHours;
      return '${h}h ago';
    }
    if (difference.inDays < 7) {
      final d = difference.inDays;
      return '${d}d ago';
    }
    return '${local.year}/${local.month.toString().padLeft(2, '0')}/${local.day.toString().padLeft(2, '0')}';
  }

  List<Widget> _parseContentToWidgets(BuildContext context) {
    final theme = Theme.of(context);
    final textTheme = theme.textTheme;
    final onSurfaceVariant = theme.colorScheme.onSurfaceVariant;
    final primary = theme.colorScheme.primary;

    final List<Widget> list = [];
    final List<String> lines = article.content.split('\n');

    for (final line in lines) {
      final trimmed = line.trim();
      if (trimmed.isEmpty) continue;

      if (trimmed.startsWith('# ')) {
        // H1 Skip since we render article title at the top
        continue;
      } else if (trimmed.startsWith('## ')) {
        final headingText = trimmed.replaceFirst('## ', '');
        list.add(
          Padding(
            padding: const EdgeInsets.only(top: 24, bottom: 8),
            child: Text(
              headingText,
              style: textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.bold,
                height: 1.2,
                color: theme.colorScheme.onSurface,
              ),
            ),
          ),
        );
      } else if (trimmed.startsWith('### ')) {
        final headingText = trimmed.replaceFirst('### ', '');
        list.add(
          Padding(
            padding: const EdgeInsets.only(top: 20, bottom: 8),
            child: Text(
              headingText,
              style: textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.bold,
                color: theme.colorScheme.onSurface,
              ),
            ),
          ),
        );
      } else if (trimmed.startsWith('* ') || trimmed.startsWith('- ')) {
        final bulletText = trimmed.substring(2);
        list.add(
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 8),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '• ',
                  style: TextStyle(
                    color: primary,
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                Expanded(
                  child: Text(
                    bulletText,
                    style: textTheme.bodyMedium?.copyWith(
                      color: onSurfaceVariant,
                      height: 1.4,
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      } else if (trimmed.startsWith('1. ') ||
          trimmed.startsWith('2. ') ||
          trimmed.startsWith('3. ') ||
          trimmed.startsWith('4. ') ||
          trimmed.startsWith('5. ')) {
        final numText = trimmed.substring(3);
        list.add(
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 8),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${trimmed.substring(0, 2)} ',
                  style: TextStyle(
                    color: primary,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                Expanded(
                  child: Text(
                    numText,
                    style: textTheme.bodyMedium?.copyWith(
                      color: onSurfaceVariant,
                      height: 1.4,
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      } else if (trimmed.startsWith('> ')) {
        final quoteText = trimmed.replaceFirst('> ', '');
        list.add(
          Container(
            margin: const EdgeInsets.symmetric(vertical: 12),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            decoration: BoxDecoration(
              border: Border(
                left: BorderSide(
                  color: primary,
                  width: 4,
                ),
              ),
              color: theme.colorScheme.surfaceVariant.withOpacity(0.3),
            ),
            child: Text(
              quoteText,
              style: textTheme.bodyMedium?.copyWith(
                fontStyle: FontStyle.italic,
                color: onSurfaceVariant,
                height: 1.4,
              ),
            ),
          ),
        );
      } else {
        // Look for image Markdown: ![alt](url)
        if (trimmed.startsWith('![') && trimmed.contains('](')) {
          final start = trimmed.indexOf('(') + 1;
          final end = trimmed.indexOf(')');
          if (start > 0 && end > start) {
            final imgUrl = trimmed.substring(start, end);
            list.add(
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 16),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: Image.network(
                    imgUrl,
                    fit: BoxFit.cover,
                    errorBuilder: (_, __, ___) => const SizedBox.shrink(),
                  ),
                ),
              ),
            );
            continue;
          }
        }
        // Plain paragraph
        list.add(
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Text(
              trimmed,
              style: textTheme.bodyMedium?.copyWith(
                color: onSurfaceVariant,
                height: 1.5,
                fontSize: 16,
              ),
            ),
          ),
        );
      }
    }

    // Insert inline images from imageUrls if not already embedded
    final List<String> imageUrls = article.imageUrls;
    final String? thumb = article.thumbnailUrl;
    if (imageUrls.length > 1) {
      final List<Widget> additionalImages = [];
      for (final img in imageUrls) {
        if (img != thumb && !img.contains('b-cdn.net')) {
          additionalImages.add(
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 16),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: AspectRatio(
                  aspectRatio: 16 / 10,
                  child: Image.network(
                    img,
                    fit: BoxFit.cover,
                    errorBuilder: (_, __, ___) => const SizedBox.shrink(),
                  ),
                ),
              ),
            ),
          );
        }
      }
      if (additionalImages.isNotEmpty) {
        final splitIndex = (list.length / 2).floor();
        list.insert(splitIndex.clamp(0, list.length), additionalImages[0]);
        if (additionalImages.length > 1 && list.length > splitIndex + 3) {
          list.insert((splitIndex + 3).clamp(0, list.length), additionalImages[1]);
        } else if (additionalImages.length > 1) {
          list.add(additionalImages[1]);
        }
      }
    }

    return list;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final textTheme = theme.textTheme;
    final onSurfaceVariant = theme.colorScheme.onSurfaceVariant;
    final primaryColor = theme.colorScheme.primary;

    String? thumb = article.thumbnailUrl ??
        (article.imageUrls.isNotEmpty ? article.imageUrls.first : null);
    if ((thumb ?? '').contains('b-cdn.net')) {
      thumb = null;
    }

    final timestampLabel = _formatNewsTimestamp(article.createdAt);

    return Scaffold(
      backgroundColor: theme.colorScheme.background,
      body: CustomScrollView(
        slivers: [
          // Slivers App Bar with Title/Category and back button overlay
          SliverAppBar(
            expandedHeight: thumb != null ? 240 : 100,
            pinned: true,
            elevation: 0.5,
            backgroundColor: theme.colorScheme.surface.withOpacity(0.95),
            flexibleSpace: FlexibleSpaceBar(
              background: thumb != null
                  ? Stack(
                      fit: StackFit.expand,
                      children: [
                        Image.network(
                          thumb,
                          fit: BoxFit.cover,
                          errorBuilder: (_, __, ___) => Container(
                            color: primaryColor.withOpacity(0.05),
                          ),
                        ),
                        // Soft dark gradient overlay
                        Container(
                          decoration: const BoxDecoration(
                            gradient: LinearGradient(
                              colors: [Colors.black54, Colors.transparent],
                              begin: Alignment.bottomCenter,
                              end: Alignment.topCenter,
                            ),
                          ),
                        ),
                      ],
                    )
                  : Container(
                      color: primaryColor.withOpacity(0.05),
                    ),
            ),
            leading: Padding(
              padding: const EdgeInsets.all(8.0),
              child: CircleAvatar(
                backgroundColor: theme.colorScheme.surface.withOpacity(0.8),
                child: IconButton(
                  icon: Icon(
                    Icons.arrow_back,
                    color: theme.colorScheme.onSurface,
                    size: 20,
                  ),
                  onPressed: () => Navigator.of(context).pop(),
                ),
              ),
            ),
          ),

          // Content body
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.all(18.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Category label pill
                  if (article.category != null && article.category!.isNotEmpty)
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 5,
                      ),
                      decoration: BoxDecoration(
                        color: primaryColor.withOpacity(0.08),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(
                          color: primaryColor.withOpacity(0.2),
                          width: 1,
                        ),
                      ),
                      child: Text(
                        article.category!.toUpperCase(),
                        style: textTheme.labelSmall?.copyWith(
                          color: primaryColor,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 1.1,
                        ),
                      ),
                    ),
                  const SizedBox(height: 12),

                  // Headline Title
                  Text(
                    article.title,
                    style: textTheme.headlineMedium?.copyWith(
                      fontWeight: FontWeight.w900,
                      height: 1.2,
                      color: theme.colorScheme.onSurface,
                    ),
                  ),
                  const SizedBox(height: 8),

                  if (article.subtitle != null && article.subtitle!.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: Text(
                        article.subtitle!,
                        style: textTheme.titleMedium?.copyWith(
                          color: onSurfaceVariant,
                          fontWeight: FontWeight.w500,
                          height: 1.3,
                        ),
                      ),
                    ),

                  const Divider(height: 24),

                  // Publisher & Meta info
                  Row(
                    children: [
                      CircleAvatar(
                        radius: 20,
                        backgroundColor: primaryColor.withOpacity(0.1),
                        child: Icon(
                          Icons.newspaper,
                          color: primaryColor,
                          size: 20,
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Text(
                                  'XapZap News',
                                  style: textTheme.titleSmall?.copyWith(
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                                const SizedBox(width: 4),
                                Icon(
                                  Icons.verified,
                                  color: primaryColor,
                                  size: 14,
                                ),
                              ],
                            ),
                            Text(
                              'Verified publisher',
                              style: textTheme.bodySmall?.copyWith(
                                color: onSurfaceVariant,
                              ),
                            ),
                          ],
                        ),
                      ),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Text(
                            timestampLabel,
                            style: textTheme.bodySmall?.copyWith(
                              color: onSurfaceVariant,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Row(
                            children: [
                              Icon(
                                Icons.timer_outlined,
                                size: 12,
                                color: onSurfaceVariant,
                              ),
                              const SizedBox(width: 3),
                              Text(
                                '8 min read',
                                style: textTheme.bodySmall?.copyWith(
                                  color: onSurfaceVariant,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ],
                  ),

                  const Divider(height: 24),

                  // Paragraphs list
                  ..._parseContentToWidgets(context),

                  const SizedBox(height: 32),

                  // Tags Section
                  if (article.tags.isNotEmpty) ...[
                    Text(
                      'TAGS',
                      style: textTheme.labelSmall?.copyWith(
                        fontWeight: FontWeight.bold,
                        color: onSurfaceVariant,
                        letterSpacing: 1.1,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: article.tags.map((tag) {
                        return Chip(
                          backgroundColor: theme.colorScheme.surfaceVariant.withOpacity(0.4),
                          label: Text(
                            '#$tag',
                            style: textTheme.bodySmall?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8),
                            side: BorderSide(
                              color: theme.dividerColor.withOpacity(0.1),
                              width: 1,
                            ),
                          ),
                        );
                      }).toList(),
                    ),
                  ],
                  const SizedBox(height: 80),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
