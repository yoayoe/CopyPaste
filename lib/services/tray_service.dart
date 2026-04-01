import 'dart:io';
import 'package:tray_manager/tray_manager.dart';
import 'package:window_manager/window_manager.dart';
import '../utils/logger.dart';

const _tag = 'TrayService';

class TrayService with TrayListener {
  static final TrayService instance = TrayService._();
  TrayService._();

  Future<void> setup() async {
    trayManager.addListener(this);

    // macOS uses template images (black & white, system handles coloring).
    if (Platform.isMacOS) {
      await trayManager.setIcon(
        'assets/icons/app_icon.png',
        isTemplate: true,
      );
    } else {
      await trayManager.setIcon('assets/icons/app_icon.png');
    }

    // setToolTip is not supported on Linux.
    if (!Platform.isLinux) {
      await trayManager.setToolTip('CopyPaste');
    }
    await _buildMenu();
    Log.d(_tag, 'Tray initialized');
  }

  Future<void> _buildMenu() async {
    await trayManager.setContextMenu(Menu(
      items: [
        MenuItem(
          key: 'show',
          label: 'Show CopyPaste',
        ),
        MenuItem.separator(),
        MenuItem(
          key: 'quit',
          label: 'Quit',
        ),
      ],
    ));
  }

  void dispose() {
    trayManager.removeListener(this);
  }

  // --- TrayListener ---

  @override
  void onTrayIconMouseDown() {
    // Left click — toggle show/hide.
    windowManager.isVisible().then((visible) {
      if (visible) {
        windowManager.hide();
      } else {
        windowManager.show();
        windowManager.focus();
      }
    });
  }

  @override
  void onTrayIconRightMouseDown() {
    trayManager.popUpContextMenu();
  }

  @override
  void onTrayMenuItemClick(MenuItem menuItem) {
    switch (menuItem.key) {
      case 'show':
        windowManager.show();
        windowManager.focus();
        break;
      case 'quit':
        windowManager.destroy();
        break;
    }
  }
}
