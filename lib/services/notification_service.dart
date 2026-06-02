import 'dart:io';
import 'package:local_notifier/local_notifier.dart';
import '../utils/logger.dart';

const _tag = 'NotificationService';

class NotificationService {
  static int _counter = 0;
  static bool _initialized = false;

  static Future<void> setup() async {
    if (Platform.isAndroid) return;
    await localNotifier.setup(appName: 'CopyPaste');
    _initialized = true;
    Log.d(_tag, 'Initialized');
  }

  static Future<void> showClipboardReceived(String sourceName, String content) async {
    if (!_initialized) return;
    final preview = content.length > 60 ? '${content.substring(0, 60)}…' : content;
    final notification = LocalNotification(
      identifier: 'clipboard_${_counter++}',
      title: 'Clipboard from $sourceName',
      body: preview,
    );
    await notification.show();
  }

  static Future<void> showFileReceived(String filename, String sourceName) async {
    if (!_initialized) return;
    final notification = LocalNotification(
      identifier: 'file_${_counter++}',
      title: 'File received',
      body: '$filename from $sourceName',
    );
    await notification.show();
  }

  static Future<void> showFileSent(String filename) async {
    if (!_initialized) return;
    final notification = LocalNotification(
      identifier: 'file_${_counter++}',
      title: 'File sent',
      body: filename,
    );
    await notification.show();
  }
}
