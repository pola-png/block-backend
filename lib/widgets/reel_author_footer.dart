import 'dart:async';

import 'package:flutter/material.dart';
import '../utils/format_utils.dart';

class ReelAuthorFooter extends StatelessWidget {
  final String displayName;
  final String? avatarUrl;
  final String postContent;
  final int? viewCount;
  final double bottomInset;
  final Future<void> Function() onOpenAuthorProfile;

  const ReelAuthorFooter({
    super.key,
    required this.displayName,
    required this.avatarUrl,
    required this.postContent,
    required this.viewCount,
    this.bottomInset = 0,
    required this.onOpenAuthorProfile,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final authorPrimaryColor = isDark ? Colors.white : Colors.black;
    final authorSecondaryColor =
        isDark ? Colors.white.withOpacity(0.9) : Colors.black.withOpacity(0.86);

    return Positioned(
      left: 16,
      right: 16,
      bottom: 20 + bottomInset,
      child: GestureDetector(
        onTap: () => unawaited(onOpenAuthorProfile()),
        behavior: HitTestBehavior.translucent,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            _AuthorAvatar(avatarUrl: avatarUrl),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    children: [
                      Flexible(
                        child: Text(
                          displayName,
                          style: TextStyle(
                            color: authorPrimaryColor,
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      if (viewCount != null) ...[
                        const SizedBox(width: 8),
                        Icon(
                          Icons.visibility_outlined,
                          size: 16,
                          color: authorSecondaryColor,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          formatCompactCount(viewCount!),
                          style: TextStyle(
                            color: authorSecondaryColor,
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 4),
                  if (postContent.isNotEmpty)
                    Text(
                      postContent,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: authorSecondaryColor,
                        fontSize: 13,
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

}

class _AuthorAvatar extends StatelessWidget {
  final String? avatarUrl;

  const _AuthorAvatar({required this.avatarUrl});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final avatar = avatarUrl?.trim();
    return Container(
      width: 40,
      height: 40,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: theme.colorScheme.surfaceContainerHighest,
      ),
      child: ClipOval(
        child: avatar == null || avatar.isEmpty
            ? Icon(
                Icons.person,
                size: 22,
                color: theme.colorScheme.onSurfaceVariant,
              )
            : Image.network(
                avatar,
                fit: BoxFit.cover,
                width: 40,
                height: 40,
                errorBuilder: (context, error, stackTrace) => Icon(
                  Icons.person,
                  size: 22,
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
      ),
    );
  }
}
