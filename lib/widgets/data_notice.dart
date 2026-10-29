import 'package:flutter/material.dart';

import '../screens/legal_screen.dart';
import '../theme.dart';
import 'zicons.dart';

/// Где и как хранятся данные — простыми словами (регистрация и Настройки).
/// Полный текст — в Privacy Policy → Storage and security.
class DataNotice extends StatelessWidget {
  const DataNotice({super.key, this.compact = false});
  final bool compact;

  static const points = <(IconData, String)>[
    (ZI.globe, 'Stored on secure Supabase servers in the European Union (Ireland) — outside Zambia.'),
    (ZI.lock, 'Encrypted on the way and on the servers. Only you and, when needed, the Zumi team can see your private details.'),
    (ZI.mobile, 'Your phone number is never public — people see it only after they confirm their own number, '
        'or not at all if you choose "Chat only".'),
    (ZI.shield, 'We never sell your data. Ask for a copy in Help & support, or delete your account any time in Settings.'),
  ];

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(color: Zc.greenTint, borderRadius: BorderRadius.circular(14)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Row(children: [
          Icon(ZI.shieldFill, size: 18, color: Zc.green),
          SizedBox(width: 8),
          Text('Your data on Zumi', style: TextStyle(fontWeight: FontWeight.w700, color: Zc.green, fontSize: 15)),
        ]),
        const SizedBox(height: 8),
        for (final (icon, text) in compact ? points.take(2) : points)
          Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Padding(padding: const EdgeInsets.only(top: 2), child: Icon(icon, size: 15, color: Zc.green)),
              const SizedBox(width: 8),
              Expanded(child: Text(text, style: const TextStyle(fontSize: 13, color: Zc.text, height: 1.35))),
            ]),
          ),
        GestureDetector(
          onTap: () => openLegal(context, LegalDoc.privacy),
          child: const Text('Read more in the Privacy Policy',
              style: TextStyle(fontSize: 13, color: Zc.green, decoration: TextDecoration.underline)),
        ),
      ]),
    );
  }
}

/// Тот же текст отдельным окном (Настройки → Your data)
void showDataNotice(BuildContext context) => showModalBottomSheet(
      context: context,
      showDragHandle: true,
      backgroundColor: Zc.bg,
      builder: (_) => const SafeArea(
        child: Padding(padding: EdgeInsets.fromLTRB(20, 0, 20, 20), child: DataNotice()),
      ),
    );
