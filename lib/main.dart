import 'package:flutter/material.dart';
import 'dart:io' show  Platform;
import 'package:window_size/window_size.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'pages/homepage.dart';
import 'pages/settings.dart';
import 'package:easy_localization/easy_localization.dart';

import 'languages.dart';

final ValueNotifier<ThemeMode> themeNotifier = ValueNotifier(ThemeMode.light);

ThemeData light = ThemeData(
  useMaterial3: true,
  colorScheme: ColorScheme.fromSeed(
    seedColor: const Color.fromARGB(255, 34, 192, 255),
    brightness: Brightness.light,
  ),
);

ThemeData dark = ThemeData(
  useMaterial3: true,
  colorScheme: ColorScheme.fromSeed(
    seedColor: const Color.fromARGB(255, 34, 192, 255),
    brightness: Brightness.dark,
  ),
);

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await EasyLocalization.ensureInitialized();
  //await Permission.storage.request().isGranted;
  final SharedPreferences storage = await SharedPreferences.getInstance();

  savedSettings.load();

  if (Platform.isWindows || Platform.isLinux || Platform.isMacOS) {
    setWindowTitle('SNSE');
    setWindowMaxSize(const Size(650, 1000));
    setWindowMinSize(const Size(650, 1000));
  }

  runApp(
    EasyLocalization(
      supportedLocales: getAvailableLocales(),
      path: 'assets/lang',
      fallbackLocale: const Locale('en'),
      child: MainApp(storage: storage)
    ),
  );
}

class MainApp extends StatelessWidget {
  final SharedPreferences storage;

  const MainApp({super.key, required this.storage});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<ThemeMode>(
      valueListenable: themeNotifier,
      builder: (context, mode, _) {
        return MaterialApp(
          title: 'SNSE',
          theme: light,
          darkTheme: dark,
          themeMode: mode,
          localizationsDelegates: context.localizationDelegates,
          supportedLocales: context.supportedLocales,
          locale: context.locale,
          home: HomePage(storage: storage),
        );
      },
    );
  }
}
