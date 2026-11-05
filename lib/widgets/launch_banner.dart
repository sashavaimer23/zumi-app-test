import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../features.dart';
import '../state/app_state.dart';
import '../theme.dart';
import 'zicons.dart';

/// «Zumi is free during launch» — пока платные функции выключены.
/// Тон: не «скоро будет платно», а «вы рано — и это выгодно». Можно закрыть (запоминается).
class LaunchBanner extends StatelessWidget {
  const LaunchBanner({super.key, this.margin = EdgeInsets.zero, this.compact = false});
  final EdgeInsets margin;
  final bool compact;

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
        decoration: BoxDecoration(
          gradient: const LinearGradient(colors: [Color(0xFFFFF1E6), Color(0xFFEAF5EE)]),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: const Color(0xFFF6D8BF)),
        ),
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
              const Text('Zumi is free during launch',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: Zc.text)),
              const SizedBox(height: 4),
              Text(
                agent
                    ? 'Post up to 25 listings, chat and get calls — all free. You are early, and that pays off: '
                        'agents who join now get founding-member perks when we add tools to grow your business — '
                        'boosts, featured spots and Pro features.'
                    : 'Post, search, chat and call — all free. We are just getting started: soon there will be '
                        'more ways to get your listing seen. Tell your friends and agents you know!',
                style: const TextStyle(fontSize: 13, color: Zc.text, height: 1.4),
              ),
              if (!compact) ...[
                const SizedBox(height: 6),
                const Text('Basic listings stay free — always.',
                    style: TextStyle(fontSize: 12, color: Zc.green, fontWeight: FontWeight.w600)),
              ],
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
