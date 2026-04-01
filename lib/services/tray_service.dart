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

    // Windows requires .ico, macOS uses template image, Linux uses PNG.
    if (Platform.isWindows) {
      await trayManager.setIcon('assets/icons/app_icon.ico');
    } else if (Platform.isMacOS) {
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
    if (Platform.isMacOS) {
      // macOS convention: left click on menu bar icon shows the context menu.
      trayManager.popUpContextMenu();
    } else {
      // Linux / Windows: left click toggles show/hide.
      windowManager.isVisible().then((visible) {
        if (visible) {
          windowManager.hide();
        } else {
          windowManager.show();
          windowManager.focus();
        }
      });
    }
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
