import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import '../theme.dart';
import 'common.dart';
import 'zicons.dart';

/// Поделиться объявлением или страницей агента: WhatsApp, Facebook, SMS, скопировать ссылку.
/// В Замбии объявления чаще всего пересылают в WhatsApp — он первый.
Future<void> showShareSheet(BuildContext context, {required String text, String? link}) {
  final full = link == null ? text : '$text\n$link';
  Future<void> open(Uri uri) async {
    final ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!ok && context.mounted) showSnack(context, 'Could not open the app');
  }

  return showModalBottomSheet<void>(
    context: context,
    backgroundColor: Zc.bg,
    shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
    builder: (ctx) => SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(8, 18, 8, 12),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const Text('Share', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w600, color: Zc.green)),
          const SizedBox(height: 8),
          _tile(ctx, ZI.whatsapp, 'WhatsApp', () => open(Uri.parse('https://wa.me/?text=${Uri.encodeComponent(full)}'))),
          if (link != null)
            _tile(ctx, ZI.globe, 'Facebook',
                () => open(Uri.parse('https://www.facebook.com/sharer/sharer.php?u=${Uri.encodeComponent(link)}'))),
          _tile(ctx, ZI.chat, 'SMS', () => open(Uri.parse('sms:?body=${Uri.encodeComponent(full)}'))),
          _tile(ctx, link != null ? ZI.link : ZI.copy, link != null ? 'Copy link' : 'Copy text', () async {
            await Clipboard.setData(ClipboardData(text: link ?? full));
            if (context.mounted) showSnack(context, link != null ? 'Link copied' : 'Text copied');
          }),
        ]),
      ),
    ),
  );
}

Widget _tile(BuildContext ctx, IconData icon, String label, Future<void> Function() onTap) => ListTile(
      leading: Icon(icon, color: Zc.green),
      title: Text(label, style: const TextStyle(fontSize: 16)),
      onTap: () {
        Navigator.pop(ctx);
        onTap();
      },
    );
