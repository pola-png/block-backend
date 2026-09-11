import 'package:flutter/material.dart';

import '../screens/pending_uploads_screen.dart';
import '../services/pending_upload_service.dart';

class PendingUploadBanner extends StatelessWidget {
  const PendingUploadBanner({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ValueListenableBuilder<List<PendingUpload>>(
      valueListenable: PendingUploadService.uploads,
      builder: (context, uploads, _) {
        final failed = uploads.where((u) => u.failed).toList();
        final active = uploads.where((u) => !u.completed && !u.failed).toList();
        final upload = failed.isNotEmpty ? failed.first : active.firstOrNull;
        if (upload == null) return const SizedBox.shrink();
        final isFailed = upload.failed;
        final accent =
            isFailed ? theme.colorScheme.error : theme.colorScheme.primary;
        final surface = isFailed
            ? theme.colorScheme.errorContainer
            : theme.colorScheme.primaryContainer;
        final textColor = isFailed
            ? theme.colorScheme.onErrorContainer
            : theme.colorScheme.onPrimaryContainer;

        final progressPercent = (upload.progress * 100).clamp(0, 100).toStringAsFixed(0);

        return Card(
          margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          color: surface,
          elevation: 1,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
          child: InkWell(
            onTap: () {
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => PendingUploadsScreen(
                    initialUploadId: upload.id,
                  ),
                ),
              );
            },
            borderRadius: BorderRadius.circular(8),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: Stack(
                children: [
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    child: Row(
                      children: [
                        SizedBox(
                          width: 16,
                          height: 16,
                          child: isFailed
                              ? Icon(Icons.error_outline, size: 16, color: accent)
                              : CircularProgressIndicator(
                                  value: upload.progress,
                                  strokeWidth: 2,
                                  color: accent,
                                  backgroundColor: accent.withOpacity(0.2),
                                ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            isFailed
                                ? 'Upload failed: ${upload.title}'
                                : 'Uploading: ${upload.title} ($progressPercent%)',
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: textColor,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        if (isFailed) ...[
                          const SizedBox(width: 8),
                          TextButton(
                            style: TextButton.styleFrom(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                              minimumSize: Size.zero,
                              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                            ),
                            onPressed: () => PendingUploadService.retry(upload.id),
                            child: Text(
                              'Retry',
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.bold,
                                color: accent,
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                  Positioned(
                    left: 0,
                    right: 0,
                    bottom: 0,
                    child: LinearProgressIndicator(
                      value: upload.completed || upload.failed ? 1.0 : upload.progress,
                      color: accent.withOpacity(0.5),
                      backgroundColor: Colors.transparent,
                      minHeight: 1.5,
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

extension _FirstOrNull<E> on List<E> {
  E? get firstOrNull => isEmpty ? null : first;
}
