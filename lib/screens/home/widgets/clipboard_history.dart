import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:pasteboard/pasteboard.dart';
import '../../../models/clipboard_item.dart';

class ClipboardHistory extends StatelessWidget {
  final List<ClipboardItem> items;

  const ClipboardHistory({super.key, required this.items});

  @override
  Widget build(BuildContext context) {
    if (items.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.content_paste_off,
                size: 64, color: Theme.of(context).disabledColor),
            const SizedBox(height: 16),
            Text(
              'No clipboard history yet',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            Text(
              'Copied text or images will appear here',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.all(8),
      itemCount: items.length,
      itemBuilder: (context, index) {
        final item = items[index];
        return _ClipboardItemTile(item: item);
      },
    );
  }
}

class _ClipboardItemTile extends StatelessWidget {
  final ClipboardItem item;

  const _ClipboardItemTile({required this.item});

  @override
  Widget build(BuildContext context) {
    final age = DateTime.now().difference(item.timestamp);
    final ageText = age.inMinutes < 1
        ? 'just now'
        : age.inMinutes < 60
            ? '${age.inMinutes}m ago'
            : '${age.inHours}h ago';

    final isImage = item.type == ClipboardItemType.image;

    return Card(
      child: ListTile(
        leading: isImage && item.imageData != null
            ? ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: Image.memory(
                  item.imageData!,
                  width: 48,
                  height: 48,
                  fit: BoxFit.cover,
                  errorBuilder: (_, __, ___) => const Icon(Icons.image, size: 48),
                ),
              )
            : isImage
                ? const Icon(Icons.image, size: 32)
                : null,
        title: Text(
          item.preview,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
        ),
        subtitle: Text(
          '${item.sourceDeviceName ?? "This device"} • $ageText',
        ),
        trailing: IconButton(
          icon: Icon(isImage ? Icons.content_copy : Icons.copy),
          tooltip: isImage ? 'Copy image' : 'Copy',
          onPressed: () {
            if (isImage && item.imageData != null) {
              Pasteboard.writeImage(item.imageData!);
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('Image copied to clipboard'),
                  duration: Duration(seconds: 1),
                ),
              );
            } else {
              Clipboard.setData(ClipboardData(text: item.content));
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('Copied to clipboard'),
                  duration: Duration(seconds: 1),
                ),
              );
            }
          },
        ),
      ),
    );
  }
}
