import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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
              'Copied text will appear here',
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

    return Card(
      child: ListTile(
        title: Text(
          item.preview,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
        ),
        subtitle: Text(
          '${item.sourceDeviceName ?? "This device"} • $ageText',
        ),
        trailing: IconButton(
          icon: const Icon(Icons.copy),
          tooltip: 'Copy',
          onPressed: () {
            Clipboard.setData(ClipboardData(text: item.content));
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('Copied to clipboard'),
                duration: Duration(seconds: 1),
              ),
            );
          },
        ),
      ),
    );
  }
}
