import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/models.dart';
import '../state/app_state.dart';
import '../theme.dart';
import '../widgets/common.dart';
import 'auth_screen.dart';
import 'chat_screen.dart';
import 'shell.dart';
import '../widgets/zicons.dart';

/// Список переписок с продавцами / покупателями
class ChatsScreen extends StatefulWidget {
  const ChatsScreen({super.key});

  @override
  State<ChatsScreen> createState() => _ChatsScreenState();
}

class _ChatsScreenState extends State<ChatsScreen> {
  Future<List<Conversation>>? _future;
  String _key = '';

  void _reload(AppState app) {
    _future = app.repo.conversations();
  }

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    if (!app.signedIn) {
      return Scaffold(
        body: SafeArea(
          child: EmptyState(
            icon: ZI.chat,
            title: 'Your chats',
            subtitle: 'Sign in to message agents and owners about their listings.',
            action: PrimaryButton(
              label: 'Sign in',
              onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const AuthScreen())),
            ),
          ),
        ),
      );
    }
    final key = '${app.user!.id}#${app.chatsVersion}';
    if (key != _key) {
      _key = key;
      _reload(app);
    }

    return Scaffold(
      body: SafeArea(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(26, 18, 26, 10),
            child: Text('Chats', style: zHeadline(context, size: 40)),
          ),
          Expanded(
            child: RefreshIndicator(
              color: Zc.orange,
              onRefresh: () async {
                setState(() => _reload(app));
                await _future;
              },
              child: FutureBuilder<List<Conversation>>(
                future: _future,
                builder: (context, snap) {
                  if (snap.connectionState != ConnectionState.done) {
                    return const Center(child: CircularProgressIndicator(color: Zc.orange));
                  }
                  final list = snap.data ?? const <Conversation>[];
                  if (list.isEmpty) {
                    return ListView(children: const [
                      SizedBox(height: 60),
                      EmptyState(
                        icon: ZI.chat,
                        title: 'No messages yet',
                        subtitle: 'Open a listing and tap “Message” to start a conversation.',
                      ),
                    ]);
                  }
                  return ListView.separated(
                    padding: const EdgeInsets.fromLTRB(14, 0, 14, Shell.navSpace),
                    itemCount: list.length,
                    separatorBuilder: (_, __) => const Divider(height: 1, color: Zc.chip),
                    itemBuilder: (_, i) {
                      final c = list[i];
                      return ListTile(
                        contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                        leading: SizedBox(width: 56, height: 56, child: PropImage(c.propertyCover, radius: 12)),
                        title: Text(c.otherName ?? 'User', style: const TextStyle(fontWeight: FontWeight.w600)),
                        subtitle: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Text(c.propertyTitle ?? '',
                              maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Zc.green, fontSize: 12)),
                          Text(c.lastMessage ?? 'No messages yet',
                              maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Zc.grey)),
                        ]),
                        trailing: Text(_time(c.lastMessageAt), style: const TextStyle(color: Zc.grey, fontSize: 12)),
                        onTap: () async {
                          await Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => ChatScreen(conversationId: c.id, title: c.otherName ?? 'Chat'),
                            ),
                          );
                          if (mounted) setState(() => _reload(app));
                        },
                      );
                    },
                  );
                },
              ),
            ),
          ),
        ]),
      ),
    );
  }
}

String _time(DateTime t) {
  final local = t.toLocal();
  final now = DateTime.now();
  if (local.year == now.year && local.month == now.month && local.day == now.day) {
    return '${local.hour.toString().padLeft(2, '0')}:${local.minute.toString().padLeft(2, '0')}';
  }
  return '${local.day}.${local.month.toString().padLeft(2, '0')}';
}
