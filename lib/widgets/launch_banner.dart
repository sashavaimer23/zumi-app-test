import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../features.dart';
import '../models/models.dart';
import '../state/app_state.dart';
import '../theme.dart';
import 'zicons.dart';

/// «Zumi is free during launch» — пока платные функции выключены.
/// Тон: не «скоро будет платно», а «вы рано — и это выгодно». Можно закрыть (запоминается).
/// Агентам — отдельный текст «для первых агентов»: их личный бесплатный лимит (берём с сервера,
/// чтобы число всегда совпадало с настоящим) и обещание, что объявления потом не удалятся.
class LaunchBanner extends StatefulWidget {
  const LaunchBanner({super.key, this.margin = EdgeInsets.zero});
  final EdgeInsets margin;

  static const _hint = 'launch_banner_v3'; // новая версия текста — показать снова тем, кто закрыл старую

  static bool shows(BuildContext context) {
    final app = context.watch<AppState>();
    return !Features.billing && !app.hintSeen(_hint);
  }

  @override
  State<LaunchBanner> createState() => _LaunchBannerState();
}

class _LaunchBannerState extends State<LaunchBanner> {
  Future<Quota>? _quota;
  String? _quotaUser;

  @override
  Widget build(BuildContext context) {
    if (!LaunchBanner.shows(context)) return const SizedBox.shrink();
    final app = context.read<AppState>();
    final user = app.user;
    final agent = user?.isAgent ?? false;
    if (agent && _quotaUser != user!.id) {
      _quotaUser = user.id;
      _quota = app.repo.myQuota();
    }
    return Padding(
      padding: widget.margin,
      child: Container(
        padding: const EdgeInsets.fromLTRB(16, 14, 8, 14),
        decoration: BoxDecoration(color: Zc.orangeSoft, borderRadius: BorderRadius.circular(16)),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Container(
            width: 38,
            height: 38,
            alignment: Alignment.center,
            decoration: const BoxDecoration(color: Colors.white, shape: BoxShape.circle),
            child: Icon(agent ? ZI.crown : ZI.sparkle, color: Zc.orange, size: 20),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: agent
                ? FutureBuilder<Quota>(
                    future: _quota,
                    builder: (context, snap) => _AgentText(
                      allowed: snap.data?.allowed,
                      licensed: user!.licenceVerified,
                    ),
                  )
                : const _OwnerText(),
          ),
          IconButton(
            tooltip: 'Hide',
            visualDensity: VisualDensity.compact,
            onPressed: () => app.markHint(LaunchBanner._hint),
            icon: const Icon(ZI.close, size: 18, color: Zc.grey),
          ),
        ]),
      ),
    );
  }
}

const _title = TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: Zc.text);
const _body = TextStyle(fontSize: 13, color: Zc.text, height: 1.4);

class _OwnerText extends StatelessWidget {
  const _OwnerText();

  @override
  Widget build(BuildContext context) => const Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('Zumi is free for you', style: _title),
        SizedBox(height: 4),
        Text(
          'Post your property, chat and take calls — all at no cost. Later we will add optional extras '
          'to help your listing reach the top and get seen faster. Your basic listings will always stay free.',
          style: _body,
        ),
      ]);
}

class _AgentText extends StatelessWidget {
  const _AgentText({required this.allowed, required this.licensed});
  final int? allowed;
  final bool licensed;

  @override
  Widget build(BuildContext context) {
    final n = allowed == null ? 'your' : '$allowed';
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      const Text('A thank-you for our first agents', style: _title),
      const SizedBox(height: 4),
      Text(
        'While Zumi is launching, you can post up to $n listings for free. '
        'Everything you post now stays up — when paid plans start later, we will not remove your listings. '
        'Early agents will also get special offers.',
        style: _body,
      ),
      if (!licensed) ...[
        const SizedBox(height: 6),
        const Text('Confirm your ZIEA licence to get a higher free limit and the "Licensed" badge.',
            style: TextStyle(fontSize: 13, color: Zc.orange, fontWeight: FontWeight.w600, height: 1.4)),
      ],
    ]);
  }
}
