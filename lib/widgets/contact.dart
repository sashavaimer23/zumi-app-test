import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../models/models.dart';
import '../screens/auth_screen.dart';
import '../screens/chat_screen.dart';
import '../screens/verify/phone_verify_screen.dart';
import '../state/app_state.dart';
import '../theme.dart';
import 'common.dart';
import 'zicons.dart';

/// Связь с автором объявления.
/// Номер больше не приходит вместе с объявлением: его выдаёт сервер по кнопке,
/// только тому, кто вошёл и подтвердил свой телефон (не больше 15 номеров в сутки).
class Contact {
  /// Уже показанные номера в этом сеансе — повторно сервер не спрашиваем
  static final Map<String, String> _revealed = {};

  /// Получить номер: вход → подтверждение телефона → сервер
  static Future<String?> _number(BuildContext context, Property p) async {
    final cached = _revealed[p.id];
    if (cached != null) return cached;
    final app = context.read<AppState>();
    if (p.chatOnly) {
      showSnack(context, 'This author prefers chat — send a message instead');
      return null;
    }
    if (!p.hasPhone) {
      showSnack(context, 'No phone number in this listing — use chat');
      return null;
    }
    if (!app.signedIn) {
      final ok = await Navigator.push<bool>(
        context,
        MaterialPageRoute(builder: (_) => const AuthScreen(reason: 'Sign in to see the phone number.')),
      );
      if (ok != true || !context.mounted) return null;
    }
    if (!(app.user?.phoneVerified ?? false) && app.user?.id != p.ownerId) {
      final go = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Confirm your phone first'),
          content: const Text(
            'To protect agents and owners from spam, phone numbers are shown only to people with a confirmed '
            'phone. It takes a minute — we send a code by WhatsApp or SMS.',
            style: TextStyle(height: 1.4),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Not now')),
            TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Confirm phone')),
          ],
        ),
      );
      if (go != true || !context.mounted) return null;
      final ok = await Navigator.push<bool>(context, MaterialPageRoute(builder: (_) => const PhoneVerifyScreen()));
      if (ok != true || !context.mounted) return null;
    }
    try {
      final n = await app.repo.revealPhone(p.id);
      if (n.isEmpty) return null;
      _revealed[p.id] = n;
      return n;
    } on AppException catch (e) {
      if (context.mounted) showSnack(context, e.message);
      return null;
    } catch (e) {
      if (context.mounted) showSnack(context, '$e');
      return null;
    }
  }

  /// «Show number»: окно с номером и кнопками Call / WhatsApp / Copy
  static Future<void> showNumber(BuildContext context, Property p) async {
    final n = await _number(context, p);
    if (n == null || !context.mounted) return;
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: Zc.bg,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(22, 20, 22, 14),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Text(p.contactName ?? 'Seller', style: const TextStyle(color: Zc.grey)),
            const SizedBox(height: 6),
            SelectableText(n, style: const TextStyle(fontSize: 28, fontWeight: FontWeight.w600, color: Zc.green)),
            const SizedBox(height: 6),
            const Text('Say you found the listing on Zumi. Never pay before viewing.',
                textAlign: TextAlign.center, style: TextStyle(fontSize: 12, color: Zc.grey)),
            const SizedBox(height: 16),
            Row(children: [
              Expanded(
                child: FilledButton.icon(
                  style: FilledButton.styleFrom(backgroundColor: Zc.orange, padding: const EdgeInsets.symmetric(vertical: 14)),
                  onPressed: () {
                    Navigator.pop(ctx);
                    _dial(n);
                  },
                  icon: const Icon(ZI.phone),
                  label: const Text('Call'),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Zc.green,
                    side: const BorderSide(color: Zc.green),
                    padding: const EdgeInsets.symmetric(vertical: 14),
                  ),
                  onPressed: () {
                    Navigator.pop(ctx);
                    _wa(n, p);
                  },
                  icon: const Icon(ZI.whatsapp),
                  label: const Text('WhatsApp'),
                ),
              ),
            ]),
            TextButton.icon(
              onPressed: () async {
                await Clipboard.setData(ClipboardData(text: n));
                if (ctx.mounted) Navigator.pop(ctx);
                if (context.mounted) showSnack(context, 'Number copied');
              },
              icon: const Icon(ZI.copy, size: 18, color: Zc.grey),
              label: const Text('Copy number', style: TextStyle(color: Zc.grey)),
            ),
          ]),
        ),
      ),
    );
  }

  static Future<void> call(BuildContext context, Property p) async {
    final n = await _number(context, p);
    if (n != null) await _dial(n);
  }

  static Future<void> whatsapp(BuildContext context, Property p) async {
    final n = await _number(context, p);
    if (n != null) await _wa(n, p);
  }

  static Future<void> _dial(String n) => launchUrl(Uri(scheme: 'tel', path: n.replaceAll(' ', '')));

  static Future<void> _wa(String n, Property p) {
    final phone = n.replaceAll(RegExp(r'[^0-9]'), '');
    final text = Uri.encodeComponent('Hello! I saw your listing on Zumi: ${p.title}');
    return launchUrl(Uri.parse('https://wa.me/$phone?text=$text'), mode: LaunchMode.externalApplication);
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
