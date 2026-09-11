import 'package:flutter/material.dart';

import '../services/pending_upload_service.dart';

class PendingUploadsScreen extends StatelessWidget {
  final String? initialUploadId;

  const PendingUploadsScreen({super.key, this.initialUploadId});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<List<PendingUpload>>(
      valueListenable: PendingUploadService.uploads,
      builder: (context, uploads, _) {
        final theme = Theme.of(context);
        final completedCount = uploads.where((upload) => upload.completed).length;
        return Scaffold(
          appBar: AppBar(
            title: const Text('Pending uploads'),
            actions: [
              if (completedCount > 0)
                IconButton(
                  tooltip: 'Clear completed uploads',
                  onPressed: () async {
                    await PendingUploadService.clearCompletedUploads();
                  },
                  icon: const Icon(Icons.delete_outline_rounded),
                ),
            ],
          ),
          body: uploads.isEmpty
              ? const Center(
                  child: Text('No pending uploads'),
                )
              : ListView.separated(
                  padding: const EdgeInsets.all(16),
                  itemCount: uploads.length,
                  separatorBuilder: (context, _) => const SizedBox(height: 12),
                  itemBuilder: (context, index) {
                    final upload = uploads[index];
                    final isHighlighted = upload.id == initialUploadId;
                    return _buildCard(
                      theme,
                      upload,
                      highlighted: isHighlighted,
                    );
                  },
                ),
        );
      },
    );
  }

  Widget _buildCard(
    ThemeData theme,
    PendingUpload upload, {
    required bool highlighted,
  }) {
    final statusColor = upload.failed
        ? Colors.red
        : upload.completed
            ? Colors.green
            : theme.colorScheme.primary;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: highlighted
            ? theme.colorScheme.primaryContainer.withOpacity(0.35)
            : theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: highlighted ? statusColor.withOpacity(0.55) : theme.dividerColor,
          width: highlighted ? 1.4 : 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Text(
                  upload.title,
                  style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                ),
              ),
              if (highlighted)
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: Text(
                    'Opened from banner',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: statusColor,
                    ),
                  ),
                ),
              Text(
                upload.completed
                    ? 'Done'
                    : upload.failed
                        ? 'Failed'
                        : '${(upload.progress * 100).clamp(0, 100).toStringAsFixed(0)}%',
                style: TextStyle(color: statusColor, fontWeight: FontWeight.w600),
              ),
            ],
          ),
          const SizedBox(height: 8),
          LinearProgressIndicator(
            value: upload.completed || upload.failed ? 1.0 : upload.progress,
            backgroundColor: theme.dividerColor.withOpacity(0.4),
            color: statusColor,
          ),
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Text(
                  upload.failed && upload.error != null ? upload.error! : upload.status,
                  style: TextStyle(color: theme.colorScheme.onSurfaceVariant),
                ),
              ),
              if (!upload.completed)
                TextButton(
                  onPressed: () {
                    PendingUploadService.cancel(upload.id);
                  },
                  style: TextButton.styleFrom(
                    foregroundColor: Colors.red,
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                  ),
                  child: const Text('Cancel'),
                ),
            ],
          ),
        ],
      ),
    );
  }
}
