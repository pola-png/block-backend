import 'package:flutter/material.dart';
import 'package:lucide_icons/lucide_icons.dart';
import '../utils/format_utils.dart';

class ReelReactionRail extends StatelessWidget {
  final bool isLiked;
  final bool isSaved;
  final bool hasReposted;
  final int likeCount;
  final int commentCount;
  final int repostCount;
  final int shareCount;
  final double bottomInset;
  final VoidCallback onLike;
  final VoidCallback onSave;
  final VoidCallback onComment;
  final VoidCallback onRepost;
  final VoidCallback onShare;

  const ReelReactionRail({
    super.key,
    required this.isLiked,
    required this.isSaved,
    required this.hasReposted,
    required this.likeCount,
    required this.commentCount,
    required this.repostCount,
    required this.shareCount,
    this.bottomInset = 0,
    required this.onLike,
    required this.onSave,
    required this.onComment,
    required this.onRepost,
    required this.onShare,
  });

  @override
  Widget build(BuildContext context) {
    return Positioned(
      right: 12,
      bottom: 80 + bottomInset,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _ReelReactionButton(
            icon: isLiked ? Icons.favorite : Icons.favorite_border,
            iconColor: isLiked ? const Color(0xFFFF2D55) : Colors.white,
            countText: formatCompactCount(likeCount),
            onTap: onLike,
          ),
          const SizedBox(height: 18),
          _ReelReactionButton(
            icon: LucideIcons.bookmark,
            iconColor: isSaved ? const Color(0xFF1DA1F2) : Colors.white,
            label: 'Save',
            onTap: onSave,
          ),
          const SizedBox(height: 18),
          _ReelReactionButton(
            icon: LucideIcons.messageCircle,
            iconColor: Colors.white,
            countText: formatCompactCount(commentCount),
            onTap: onComment,
          ),
          const SizedBox(height: 18),
          _ReelReactionButton(
            icon: LucideIcons.repeat2,
            iconColor: hasReposted ? const Color(0xFF1DA1F2) : Colors.white,
            countText: formatCompactCount(repostCount),
            onTap: onRepost,
          ),
          const SizedBox(height: 18),
          _ReelReactionButton(
            icon: LucideIcons.share2,
            iconColor: Colors.white,
            countText: formatCompactCount(shareCount),
            onTap: onShare,
          ),
        ],
      ),
    );
  }
}

class _ReelReactionButton extends StatelessWidget {
  final IconData icon;
  final Color iconColor;
  final String? countText;
  final String? label;
  final VoidCallback onTap;

  const _ReelReactionButton({
    required this.icon,
    required this.iconColor,
    required this.onTap,
    this.countText,
    this.label,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        InkResponse(
          onTap: onTap,
          borderRadius: BorderRadius.circular(999),
          radius: 28,
          child: Container(
            padding: const EdgeInsets.all(6),
            decoration: BoxDecoration(
              color: Colors.black.withOpacity(0.25),
              shape: BoxShape.circle,
            ),
            child: Icon(icon, color: iconColor, size: 26),
          ),
        ),
        const SizedBox(height: 4),
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (countText != null)
              Text(
                countText!,
                style: const TextStyle(color: Colors.white, fontSize: 12),
              ),
            if (label != null) ...[
              SizedBox(width: countText != null ? 1 : 0),
              Text(
                label!,
                style: const TextStyle(color: Colors.white70, fontSize: 10),
              ),
            ],
          ],
        ),
      ],
    );
  }
}
