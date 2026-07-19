import 'package:flutter/material.dart';

import '../services/pending_upload_service.dart';

class DraftsScreen extends StatelessWidget {
  const DraftsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Drafts'),
        backgroundColor: theme.colorScheme.surface,
        foregroundColor: theme.colorScheme.onSurface,
      ),
      body: ValueListenableBuilder<List<PendingUpload>>(
        valueListenable: PendingUploadService.uploads,
        builder: (context, uploads, _) {
          final visibleUploads = uploads.where((u) => !u.completed || u.failed || u.isDraft).toList();
          if (visibleUploads.isEmpty) {
            return ListView(
              children: const [
                SizedBox(
                  height: 300,
                  child: Center(child: Text('No drafts or pending uploads')),
                ),
              ],
            );
          }

          return ListView.separated(
            padding: const EdgeInsets.all(16),
            itemCount: visibleUploads.length,
            separatorBuilder: (_, __) => const SizedBox(height: 12),
            itemBuilder: (context, index) {
              final upload = visibleUploads[index];
              final statusColor = upload.failed || upload.isDraft
                  ? Colors.red
                  : upload.completed
                      ? Colors.green
                      : theme.colorScheme.primary;
              return Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: theme.colorScheme.surface,
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(color: theme.dividerColor),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            upload.title,
                            style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                        Text(
                          upload.completed
                              ? 'Done'
                              : upload.failed || upload.isDraft
                                  ? 'Draft'
                                  : '${(upload.progress * 100).clamp(0, 100).toStringAsFixed(0)}%',
                          style: TextStyle(
                            color: statusColor,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    LinearProgressIndicator(
                      value: upload.completed || upload.failed ? 1.0 : upload.progress,
                      color: statusColor,
                      backgroundColor: theme.dividerColor.withOpacity(0.35),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      upload.failed && upload.error != null ? upload.error! : upload.status,
                      style: TextStyle(color: theme.colorScheme.onSurfaceVariant),
                    ),
                  ],
                ),
              );
            },
          );
        },
      ),
    );
  }
}
