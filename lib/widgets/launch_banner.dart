import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../features.dart';
import '../state/app_state.dart';
import '../theme.dart';
import 'zicons.dart';

/// «Zumi is free during launch» — пока платные функции выключены.
/// Тон: не «скоро будет платно», а «вы рано — и это выгодно». Можно закрыть (запоминается).
class LaunchBanner extends StatelessWidget {
  const LaunchBanner({super.key, this.margin = EdgeInsets.zero});
  final EdgeInsets margin;

  static const _hint = 'launch_banner_v1';

  static bool shows(BuildContext context) {
    final app = context.watch<AppState>();
    return !Features.billing && !app.hintSeen(_hint);
  }

  @override
  Widget build(BuildContext context) {
    if (!shows(context)) return const SizedBox.shrink();
    final app = context.read<AppState>();
    final agent = app.user?.isAgent ?? false;
    return Padding(
      padding: margin,
      child: Container(
        padding: const EdgeInsets.fromLTRB(16, 14, 8, 14),
        decoration: BoxDecoration(color: Zc.orangeSoft, borderRadius: BorderRadius.circular(16)),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Container(
            width: 38,
            height: 38,
            alignment: Alignment.center,
            decoration: const BoxDecoration(color: Colors.white, shape: BoxShape.circle),
            child: const Icon(ZI.sparkle, color: Zc.orange, size: 20),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(agent ? 'Free for agents during launch' : 'Zumi is free',
                  style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: Zc.text)),
              const SizedBox(height: 4),
              Text(
                agent
                    ? 'Post up to 25 listings at no cost. Basic listings will always stay free, and agents who '
                        'join early will get special offers when we add tools to promote listings.'
                    : 'Posting listings, chats and calls cost nothing. Basic listings will always stay free.',
                style: const TextStyle(fontSize: 13, color: Zc.text, height: 1.4),
              ),
            ]),
          ),
          IconButton(
            tooltip: 'Hide',
            visualDensity: VisualDensity.compact,
            onPressed: () => app.markHint(_hint),
            icon: const Icon(ZI.close, size: 18, color: Zc.grey),
          ),
        ]),
      ),
    );
  }
}
