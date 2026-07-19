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
        final activeCount = active.length;
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
        return InkWell(
          onTap: () {
            Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => PendingUploadsScreen(
                  initialUploadId: upload.id,
                ),
              ),
            );
          },
          borderRadius: BorderRadius.circular(16),
          child: Container(
            margin: const EdgeInsets.all(12),
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  surface,
                  theme.colorScheme.surface.withOpacity(0.94),
                ],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: accent.withOpacity(0.22)),
              boxShadow: [
                BoxShadow(
                  color: accent.withOpacity(
                      theme.brightness == Brightness.dark ? 0.22 : 0.12),
                  blurRadius: 16,
                  offset: const Offset(0, 8),
                ),
              ],
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Stack(
                  clipBehavior: Clip.none,
                  children: [
                    Container(
                      width: 42,
                      height: 42,
                      decoration: BoxDecoration(
                        color: accent,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const Icon(Icons.cloud_upload_outlined,
                          color: Colors.white, size: 22),
                    ),
                    if (activeCount > 0)
                      Positioned(
                        top: -4,
                        right: -4,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 5,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: theme.colorScheme.error,
                            borderRadius: BorderRadius.circular(999),
                            border: Border.all(
                              color: theme.colorScheme.surface,
                              width: 1.5,
                            ),
                          ),
                          child: Text(
                            activeCount > 9 ? '9+' : '$activeCount',
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 10,
                              fontWeight: FontWeight.w800,
                              height: 1,
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        isFailed ? 'Upload failed' : 'Upload in progress',
                        style: TextStyle(
                          fontWeight: FontWeight.w800,
                          color: textColor,
                          fontSize: 15,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        upload.title,
                        style: TextStyle(
                          fontWeight: FontWeight.w600,
                          color: textColor.withOpacity(0.9),
                        ),
                      ),
                      const SizedBox(height: 8),
                      LinearProgressIndicator(
                        value: upload.completed || upload.failed
                            ? 1.0
                            : upload.progress,
                        color: accent,
                        backgroundColor: accent.withOpacity(0.15),
                        minHeight: 6,
                      ),
                      const SizedBox(height: 8),
                      Text(
                        isFailed
                            ? (upload.error?.trim().isNotEmpty == true
                                ? upload.error!.trim()
                                : 'Upload stopped because of an error.')
                            : upload.status,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: textColor.withOpacity(0.92),
                          fontWeight: FontWeight.w500,
                        ),
                        maxLines: 3,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      isFailed
                          ? 'Stopped'
                          : '${(upload.progress * 100).clamp(0, 100).toStringAsFixed(0)}%',
                      style: TextStyle(
                        color: textColor,
                        fontWeight: FontWeight.w800,
                        fontSize: 13,
                      ),
                    ),
                    if (isFailed) ...[
                      const SizedBox(height: 8),
                      TextButton(
                        onPressed: () => PendingUploadService.retry(upload.id),
                        child: const Text('Retry'),
                      ),
                    ],
                  ],
                ),
              ],
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
