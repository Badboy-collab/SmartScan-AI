import 'package:flutter/material.dart';

import 'core/di/injection.dart';
import 'core/routing/app_router.dart';
import 'core/theme/app_theme.dart';
import 'core/theme/theme_notifier.dart';

late final ThemeNotifier themeNotifier;

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  configureDependencies();
  
  themeNotifier = ThemeNotifier();
  await themeNotifier.loadTheme();
  
  runApp(const AHScannerApp());
}

class AHScannerApp extends StatelessWidget {
  const AHScannerApp({super.key});

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: themeNotifier,
      builder: (context, _) {
        return MaterialApp.router(
          title: 'AH Scanner',
          theme: themeNotifier.currentThemeData,
          routerConfig: AppRouter.router,
          debugShowCheckedModeBanner: false,
        );
      },
    );
  }
}
