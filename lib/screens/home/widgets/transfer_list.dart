import 'dart:io';
import 'package:flutter/material.dart';
import '../../../models/transfer_task.dart';

class TransferList extends StatelessWidget {
  final List<TransferTask> transfers;

  const TransferList({super.key, required this.transfers});

  @override
  Widget build(BuildContext context) {
    if (transfers.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.folder_open, size: 64, color: Theme.of(context).disabledColor),
            const SizedBox(height: 16),
            Text('No transfers yet', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            Text(
              'Files sent or received will appear here',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.all(8),
      itemCount: transfers.length,
      itemBuilder: (context, index) => _TransferTile(task: transfers[index]),
    );
  }
}

class _TransferTile extends StatelessWidget {
  final TransferTask task;

  const _TransferTile({required this.task});

  IconData get _icon => switch (task.status) {
        TransferStatus.completed => Icons.check_circle,
        TransferStatus.failed => Icons.error,
        TransferStatus.inProgress => Icons.sync,
        TransferStatus.pending => Icons.hourglass_empty,
        TransferStatus.rejected => Icons.block,
      };

  Color _iconColor(BuildContext context) => switch (task.status) {
        TransferStatus.completed => Colors.green,
        TransferStatus.failed => Theme.of(context).colorScheme.error,
        TransferStatus.inProgress => Theme.of(context).colorScheme.primary,
        _ => Theme.of(context).disabledColor,
      };

  String get _directionLabel =>
      task.direction == TransferDirection.send ? 'Sent to' : 'From';

  String _formatSize(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1048576) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    return '${(bytes / 1048576).toStringAsFixed(1)} MB';
  }

  void _openFileLocation(BuildContext context) {
    final path = task.filePath;
    if (path == null || path.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('File path not available')),
      );
      return;
    }

    final file = File(path);
    if (!file.existsSync()) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('File not found: ${task.filename}')),
      );
      return;
    }

    // Open the containing folder.
    final dir = file.parent.path;
    if (Platform.isWindows) {
      final winPath = path.replaceAll('/', '\\');
      Process.run('explorer', ['/select,$winPath']);
    } else if (Platform.isMacOS) {
      Process.run('open', ['-R', path]);
    } else if (Platform.isLinux) {
      Process.run('xdg-open', [dir]);
    }

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Opening folder: $dir')),
    );
  }

  @override
  Widget build(BuildContext context) {
    final hasFile = task.filePath != null &&
        task.filePath!.isNotEmpty &&
        task.status == TransferStatus.completed;

    return Card(
      child: InkWell(
        onTap: hasFile ? () => _openFileLocation(context) : null,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(_icon, color: _iconColor(context), size: 20),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      task.filename,
                      style: const TextStyle(fontWeight: FontWeight.w600),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  Text(
                    _formatSize(task.totalBytes),
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      '$_directionLabel ${task.deviceName}',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ),
                  if (hasFile)
                    Icon(
                      Icons.folder_open,
                      size: 16,
                      color: Theme.of(context).colorScheme.primary,
                    ),
                ],
              ),
              if (task.status == TransferStatus.inProgress) ...[
                const SizedBox(height: 8),
                LinearProgressIndicator(value: task.progress),
                const SizedBox(height: 4),
                Text(
                  '${(task.progress * 100).toStringAsFixed(1)}%',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
              if (task.filePath != null &&
                  task.filePath!.isNotEmpty &&
                  task.status == TransferStatus.completed)
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(
                    task.filePath!,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          fontSize: 10,
                          color: Theme.of(context).colorScheme.outline,
                        ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              if (task.error != null)
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(
                    task.error!,
                    style: TextStyle(
                      fontSize: 12,
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
