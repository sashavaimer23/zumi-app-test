import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../models/models.dart';
import '../screens/auth_screen.dart';
import '../screens/chat_screen.dart';
import '../state/app_state.dart';
import 'common.dart';

/// Связь с автором объявления: звонок, WhatsApp, чат внутри Zumi.
class Contact {
  static Future<void> call(BuildContext context, Property p) async {
    final phone = p.contactPhone;
    if (phone == null || phone.isEmpty) {
      showSnack(context, 'No phone number in this listing');
      return;
    }
    await launchUrl(Uri(scheme: 'tel', path: phone.replaceAll(' ', '')));
  }

  static Future<void> whatsapp(BuildContext context, Property p) async {
    final phone = (p.contactPhone ?? '').replaceAll(RegExp(r'[^0-9]'), '');
    if (phone.isEmpty) {
      showSnack(context, 'No phone number in this listing');
      return;
    }
    final text = Uri.encodeComponent('Hello! I saw your listing on Zumi: ${p.title}');
    await launchUrl(Uri.parse('https://wa.me/$phone?text=$text'), mode: LaunchMode.externalApplication);
  }

  static Future<void> message(BuildContext context, Property p) async {
    final app = context.read<AppState>();
    if (!app.signedIn) {
      final ok = await Navigator.push<bool>(context, MaterialPageRoute(builder: (_) => const AuthScreen()));
      if (ok != true || !context.mounted) return;
    }
    try {
      final id = await app.repo.startConversation(p.id);
      app.chatsChanged();
      if (!context.mounted) return;
      Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => ChatScreen(conversationId: id, title: p.contactName ?? p.title)),
      );
    } catch (e) {
      if (context.mounted) showSnack(context, '$e');
    }
  }
}
