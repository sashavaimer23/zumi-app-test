import 'package:flutter/material.dart';

/// Цвета из макетов Zumi
class Zc {
  static const bg = Color(0xFFFFF8F1);          // Cream (бренд-бук)
  static const green = Color(0xFF0F5D4E);       // Deep Teal
  static const navGreen = Color(0xFF0F5D4E);    // нижнее меню
  static const orange = Color(0xFFFF7A59);      // Coral Orange
  static const orangeSoft = Color(0xFFFFE6DE);  // выбранная плашка
  static const field = Color(0xFFF6F6F3);       // поля ввода
  static const text = Color(0xFF2B2B2B);        // Charcoal
  static const sand = Color(0xFFE7D6C0);        // Sand
  static const grey = Color(0xFF7A7A7A);
  static const lightGrey = Color(0xFFD9D9D9);
  static const chip = Color(0xFFF4ECE1);        // светлый Sand
  static const white = Colors.white;
  static const shadow = Color(0x1A000000);
  static const scrim = Color(0x66000000);
  static const greenTint = Color(0x220F5D4E);
  static const orangeTint = Color(0x33FF7A59);
  static const navInactive = Color(0xB3FFFFFF);
  static const splash = Color(0xFF245045);      // фон заставки (бренд-бук)
  static const cream = Color(0xFFFEF8EE);       // светлая часть логотипа на зелёном
}

ThemeData buildTheme() {
  final base = ThemeData(
    useMaterial3: true,
    fontFamily: kBrandFont,
    scaffoldBackgroundColor: Zc.bg,
    colorScheme: ColorScheme.fromSeed(
      seedColor: Zc.green,
      primary: Zc.green,
      secondary: Zc.orange,
      surface: Zc.bg,
    ),
  );
  final text = _brandTextTheme(base.textTheme).apply(
    bodyColor: Zc.text,
    displayColor: Zc.green,
  );
  return base.copyWith(
    textTheme: text,
    appBarTheme: const AppBarTheme(
      backgroundColor: Zc.bg,
      foregroundColor: Zc.green,
      elevation: 0,
      scrolledUnderElevation: 0,
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: Zc.field,
      hintStyle: const TextStyle(color: Zc.grey, fontSize: 15),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: const BorderSide(color: Zc.green, width: 0.8),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: const BorderSide(color: Zc.green, width: 0.8),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: const BorderSide(color: Zc.orange, width: 1.4),
      ),
    ),
    snackBarTheme: const SnackBarThemeData(behavior: SnackBarBehavior.floating),
  );
}

/// Крупный заголовок экрана («List your property», «Saved»)
TextStyle zHeadline(BuildContext context, {double size = 40}) => _brandFont(
      TextStyle(fontSize: size, fontWeight: FontWeight.w700, color: Zc.green, height: 1.05),
    );

/// Любой текст шрифтом бренда
TextStyle zBrand(TextStyle style) => _brandFont(style);

/// Шрифт бренда — Onest, вшит в приложение (assets/fonts). Из интернета ничего не загружается.
const kBrandFont = 'Onest';

TextStyle _brandFont(TextStyle style) => style.copyWith(fontFamily: kBrandFont);

TextTheme _brandTextTheme(TextTheme base) => base.apply(fontFamily: kBrandFont);
