import 'package:flutter/material.dart';

// Кабинет команды и продвижение нужны немногим — их код скачивается только когда их открывают.
// Так первая загрузка сайта легче для всех остальных (важно на 3G).
import 'admin/admin_screen.dart' deferred as admin;
import 'promotion/promotion_screen.dart' deferred as promo;

Future<void> openAdminScreen(BuildContext context) =>
    _open(context, () => admin.loadLibrary(), () => admin.AdminScreen());

Future<void> openPromotionScreen(BuildContext context) =>
    _open(context, () => promo.loadLibrary(), () => promo.PromotionScreen());

Future<void> _open(BuildContext context, Future<void> Function() load, Widget Function() build) async {
  final nav = Navigator.of(context);
  try {
    await load();
  } catch (_) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not load this page. Check your internet and try again.')));
    }
    return;
  }
  await nav.push(MaterialPageRoute(builder: (_) => build()));
}
