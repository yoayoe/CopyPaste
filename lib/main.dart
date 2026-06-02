import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';
import 'package:window_manager/window_manager.dart';
import 'services/app_service.dart';
import 'services/notification_service.dart';
import 'services/tray_service.dart';
import 'screens/home/home_screen.dart';
import 'providers/theme_provider.dart';

final appServiceProvider = Provider<AppService>((ref) => AppService());

final servicesReadyProvider = StateProvider<bool>((ref) => false);

final startupErrorProvider = StateProvider<String?>((ref) => null);

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  if (!Platform.isAndroid) {
    await windowManager.ensureInitialized();
    await NotificationService.setup();
    await TrayService.instance.setup();

    const windowOptions = WindowOptions(
      size: Size(420, 700),
      minimumSize: Size(380, 500),
      center: true,
      title: 'CopyPaste',
      titleBarStyle: TitleBarStyle.normal,
    );

    windowManager.waitUntilReadyToShow(windowOptions, () async {
      await windowManager.show();
      await windowManager.focus();
    });
  }

  runApp(const ProviderScope(child: CopyPasteApp()));
}

class CopyPasteApp extends ConsumerStatefulWidget {
  const CopyPasteApp({super.key});

  @override
  ConsumerState<CopyPasteApp> createState() => _CopyPasteAppState();
}

class _CopyPasteAppState extends ConsumerState<CopyPasteApp> with WindowListener {
  final _isDesktop = !Platform.isAndroid;

  @override
  void initState() {
    super.initState();
    if (_isDesktop) {
      windowManager.addListener(this);
      windowManager.setPreventClose(true);
    }
    _startServices();
  }

  @override
  void onWindowClose() {
    if (_isDesktop) {
      windowManager.hide();
    }
  }

  Future<String> _extractWebClient() async {
    final supportDir = await getApplicationSupportDirectory();
    final webClientDir = Directory('${supportDir.path}/web_client');

    final manifest = await AssetManifest.loadFromAssetBundle(rootBundle);
    final webAssets = manifest.listAssets()
        .where((k) => k.startsWith('web_client/'))
        .toList();

    for (final assetKey in webAssets) {
      final relativePath = assetKey.replaceFirst('web_client/', '');
      final file = File('${webClientDir.path}/$relativePath');
      await file.parent.create(recursive: true);
      final data = await rootBundle.load(assetKey);
      await file.writeAsBytes(data.buffer.asUint8List());
    }

    return webClientDir.path;
  }

  Future<void> _startServices() async {
    final appService = ref.read(appServiceProvider);
    final webClientPath = await _extractWebClient();

    try {
      debugPrint('[CopyPaste] web_client path: $webClientPath');
      debugPrint('[CopyPaste] web_client exists: ${Directory(webClientPath).existsSync()}');
      await appService.start(webClientPath);
      debugPrint('[CopyPaste] Services started! URL: ${appService.webUrl}');
      ref.read(servicesReadyProvider.notifier).state = true;
    } catch (e, stack) {
      debugPrint('[CopyPaste] Failed to start services: $e');
      debugPrint('[CopyPaste] Stack: $stack');
      ref.read(startupErrorProvider.notifier).state = e.toString();
    }
  }

  @override
  void dispose() {
    if (_isDesktop) {
      windowManager.removeListener(this);
      TrayService.instance.dispose();
    }
    ref.read(appServiceProvider).stop();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final themeMode = ref.watch(themeModeProvider);
    return MaterialApp(
      title: 'CopyPaste',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorSchemeSeed: Colors.blue,
        brightness: Brightness.light,
        useMaterial3: true,
      ),
      darkTheme: ThemeData(
        colorSchemeSeed: Colors.blue,
        brightness: Brightness.dark,
        useMaterial3: true,
      ),
      themeMode: themeMode,
      home: const HomeScreen(),
    );
  }
}
