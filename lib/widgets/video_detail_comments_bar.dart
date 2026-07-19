import 'package:flutter/material.dart';
import 'package:lucide_icons/lucide_icons.dart';

class VideoDetailCommentsBar extends StatelessWidget {
  final int commentCount;
  final TextEditingController controller;
  final bool isSubmitting;
  final VoidCallback onSubmitted;
  final VoidCallback onCommentIconTap;

  const VideoDetailCommentsBar({
    super.key,
    required this.commentCount,
    required this.controller,
    required this.isSubmitting,
    required this.onSubmitted,
    required this.onCommentIconTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
      color: theme.scaffoldBackgroundColor,
      child: SafeArea(
        top: false,
        child: Material(
          color: theme.colorScheme.surfaceContainerHighest.withOpacity(0.35),
          borderRadius: BorderRadius.circular(999),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 2),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: controller,
                    enabled: !isSubmitting,
                    style: TextStyle(
                      color: theme.colorScheme.onSurface,
                      fontSize: 15,
                    ),
                    decoration: InputDecoration(
                      hintText: 'Add a comment...',
                      hintStyle: TextStyle(
                        color: theme.colorScheme.onSurfaceVariant,
                        fontSize: 15,
                      ),
                      border: InputBorder.none,
                      contentPadding: const EdgeInsets.symmetric(
                        vertical: 12,
                      ),
                    ),
                    textInputAction: TextInputAction.send,
                    onSubmitted: (_) => onSubmitted(),
                  ),
                ),
                GestureDetector(
                  onTap: onCommentIconTap,
                  behavior: HitTestBehavior.opaque,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
                    child: Text(
                      '$commentCount',
                      style: TextStyle(
                        color: theme.colorScheme.onSurfaceVariant,
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 2),
                IconButton(
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                  icon: isSubmitting
                      ? SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: theme.colorScheme.primary,
                          ),
                        )
                      : Icon(
                          LucideIcons.send,
                          color: theme.colorScheme.primary,
                          size: 18,
                        ),
                  onPressed: isSubmitting ? null : onSubmitted,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
