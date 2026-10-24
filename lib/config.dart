import 'package:flutter/foundation.dart';

/// Ключи передаются при запуске:
///
///   flutter run --dart-define=SUPABASE_URL=https://xxxx.supabase.co \
///               --dart-define=SUPABASE_ANON_KEY=eyJ... \
///               --dart-define=MAPTILER_KEY=...        (карта для большого трафика)
///               --dart-define=SITE_URL=https://zumi.co.zm   (адрес сайта для ссылок «Поделиться»)
///               --dart-define=ADS_EMAIL=ads@zumi.co.zm     (почта для рекламодателей, по желанию)
///
/// Если ключей Supabase нет — приложение работает в ДЕМО-режиме:
/// все данные в памяти, вход/публикация/чаты работают локально.
class AppConfig {
  static const supabaseUrl = String.fromEnvironment('SUPABASE_URL');
  static const supabaseAnonKey = String.fromEnvironment('SUPABASE_ANON_KEY');

  static bool get hasSupabase => supabaseUrl.isNotEmpty && supabaseAnonKey.isNotEmpty;

  /// Карта. Бесплатные серверы OpenStreetMap подходят только для теста —
  /// при большой нагрузке они могут отключить приложение. Для запуска
  /// нужен ключ MapTiler (бесплатный тариф): cloud.maptiler.com → API keys.
  static const mapTilerKey = String.fromEnvironment('MAPTILER_KEY');

  static String get mapTilesUrl => mapTilerKey.isEmpty
      ? 'https://tile.openstreetmap.org/{z}/{x}/{y}.png'
      : 'https://api.maptiler.com/maps/streets-v2/256/{z}/{x}/{y}.png?key=$mapTilerKey';

  static String get mapAttribution =>
      mapTilerKey.isEmpty ? '© OpenStreetMap contributors' : '© MapTiler © OpenStreetMap contributors';

  static const mapUserAgent = 'com.zumi.app';

  /// Адрес сайта Zumi — для ссылок «Поделиться».
  /// В браузере берём адрес открытой страницы, в приложении — SITE_URL.
  static const _siteUrl = String.fromEnvironment('SITE_URL');

  static String? get siteUrl {
    if (_siteUrl.isNotEmpty) return _siteUrl;
    if (kIsWeb) {
      // адрес сайта без ?параметров (на GitHub Pages сайт лежит в папке /zumi/)
      final path = Uri.base.path.endsWith('/') ? Uri.base.path.substring(0, Uri.base.path.length - 1) : Uri.base.path;
      return '${Uri.base.origin}$path';
    }
    return null;
  }

  /// Почта для рекламодателей (кнопка на шаблоне «Your ad here»).
  /// Пусто — остаётся только «Написать команде» (обращение в поддержку).
  static const adsEmail = String.fromEnvironment('ADS_EMAIL');

  /// Центр Лусаки
  static const defaultLat = -15.4167;
  static const defaultLng = 28.2833;
}
