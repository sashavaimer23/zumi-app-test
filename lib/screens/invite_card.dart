import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../config.dart';
import '../models/models.dart';
import '../state/app_state.dart';
import '../theme.dart';
import '../widgets/share.dart';
import '../widgets/zicons.dart';

/// «Пригласить друга» в профиле агента и собственника: личная ссылка + «Вы пригласили N»
class InviteCard extends StatefulWidget {
  const InviteCard({super.key, required this.user});
  final AppUser user;

  @override
  State<InviteCard> createState() => _InviteCardState();
}

class _InviteCardState extends State<InviteCard> {
  InviteInfo? _i;
  bool _failed = false;

  @override
  void initState() {
    super.initState();
    context.read<AppState>().repo.myInvite().then((i) {
      if (mounted) setState(() => _i = i);
    }).catchError((_) {
      if (mounted) setState(() => _failed = true); // база ещё без 041 — карточку не показываем
    });
  }

  String _link(String code) {
    final site = AppConfig.siteUrl ?? 'https://zumihome.com';
    // агент зовёт коллег — на страницу для агентов; собственник — сразу в регистрацию собственника
    return widget.user.isAgent ? '$site/agents?i=$code' : '$site/?signup=owner&invite=$code';
  }

  void _share(InviteInfo i) {
    final text = widget.user.isAgent
        ? 'I list my properties on Zumi — free listings, clients message you directly. Join here:'
        : 'I rent out my place on Zumi — it\'s free to post and tenants contact you directly. Try it:';
    showShareSheet(context, text: text, link: _link(i.code));
  }

  @override
  Widget build(BuildContext context) {
    final i = _i;
    if (_failed) return const SizedBox.shrink();
    final agent = widget.user.isAgent;
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(color: Zc.greenTint, borderRadius: BorderRadius.circular(18)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          const Icon(ZI.users, color: Zc.green),
          const SizedBox(width: 8),
          Expanded(
            child: Text(agent ? 'Invite a colleague' : 'Invite a friend',
                style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w600, color: Zc.green)),
          ),
        ]),
        const SizedBox(height: 6),
        Text(
          agent
              ? 'Know agents who would like free listings? Send them your personal link.'
              : 'Know someone with a place to rent out or sell? Send them your personal link.',
          style: const TextStyle(fontSize: 13.5, height: 1.4),
        ),
        const SizedBox(height: 12),
        Row(children: [
          Expanded(
            child: FilledButton.icon(
              style: FilledButton.styleFrom(
                backgroundColor: Zc.green,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
              ),
              onPressed: i == null ? null : () => _share(i),
              icon: const Icon(ZI.share, size: 18),
              label: const Text('Send invite'),
            ),
          ),
          const SizedBox(width: 14),
          Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
            Text(i == null ? '—' : '${i.invited}',
                style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w600, color: Zc.green)),
            Text(i != null && i.invited == 1 ? 'person joined' : 'people joined',
                style: const TextStyle(fontSize: 12, color: Zc.grey)),
          ]),
        ]),
      ]),
    );
  }
}
