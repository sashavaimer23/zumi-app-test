import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../config.dart';
import '../theme.dart';
import 'zicons.dart';

/// «Are you an agent? List your properties for free →» — ведёт на zumihome.com/agents
class AgentsLink extends StatelessWidget {
  const AgentsLink({super.key, this.compact = false});
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final site = AppConfig.siteUrl ?? 'https://zumihome.com';
    return InkWell(
      borderRadius: BorderRadius.circular(16),
      onTap: () => launchUrl(Uri.parse('$site/agents'), webOnlyWindowName: '_self'),
      child: Container(
        padding: EdgeInsets.symmetric(horizontal: 16, vertical: compact ? 12 : 16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Zc.chip),
        ),
        child: Row(children: [
          const Icon(ZI.users, color: Zc.green),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(compact ? 'Agent? See what Zumi gives agents' : 'Are you an agent? List your properties for free',
                  style: const TextStyle(fontWeight: FontWeight.w600, color: Zc.green)),
              if (!compact)
                const Text('Free listings, your own catalogue page, clients message you directly.',
                    style: TextStyle(fontSize: 12.5, color: Zc.grey)),
            ]),
          ),
          const Icon(ZI.caretRight, size: 18, color: Zc.green),
        ]),
      ),
    );
  }
}
