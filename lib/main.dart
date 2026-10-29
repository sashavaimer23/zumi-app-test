import 'dart:ui' show PlatformDispatcher;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'config.dart';
import 'data/demo_repository.dart';
import 'data/repository.dart';
import 'data/supabase_repository.dart';
import 'screens/shell.dart';
import 'screens/splash.dart';
import 'state/app_state.dart';
import 'theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  Repository repo;
  if (AppConfig.hasSupabase) {
    await Supabase.initialize(url: AppConfig.supabaseUrl, publishableKey: AppConfig.supabaseAnonKey);
    repo = SupabaseRepository();
  } else {
    repo = DemoRepository();
  }

  final prefs = await SharedPreferences.getInstance();
  splashSeenBefore = prefs.getBool('splash_seen') ?? false;
  if (!splashSeenBefore) prefs.setBool('splash_seen', true);

  // ошибки приложения → обезличенная статистика для разработчика (без данных людей)
  final reported = <String>{};
  void report(Object error) {
    final text = '$error'.split('\n').first.trim();
    if (text.isEmpty || reported.length >= 20 || !reported.add(text)) return;
    repo.logError(text);
  }

  FlutterError.onError = (details) {
    FlutterError.presentError(details);
    report(details.exceptionAsString());
  };
  PlatformDispatcher.instance.onError = (error, stack) {
    report(error);
    return true;
  };

  runApp(
    ChangeNotifierProvider(
      create: (_) => AppState(repo, prefs),
      child: const ZumiApp(),
    ),
  );
}

class ZumiApp extends StatelessWidget {
  const ZumiApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Zumi',
      debugShowCheckedModeBanner: false,
      theme: buildTheme(),
      // заставка поверх всего приложения — главная грузится под ней
      builder: (context, child) => SplashGate(child: child ?? const SizedBox.shrink()),
      home: const Shell(),
    );
  }
}
