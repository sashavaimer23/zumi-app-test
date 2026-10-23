import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/models.dart';
import '../../state/app_state.dart';
import '../../theme.dart';
import '../../widgets/common.dart';
import '../../widgets/zicons.dart';
import 'ticket_chat_screen.dart';

/// Help & support: мои обращения + новое обращение
class SupportScreen extends StatefulWidget {
  const SupportScreen({super.key});

  @override
  State<SupportScreen> createState() => _SupportScreenState();
}

class _SupportScreenState extends State<SupportScreen> {
  late Future<List<SupportTicket>> _future = context.read<AppState>().repo.myTickets();

  void _reload() => setState(() => _future = context.read<AppState>().repo.myTickets());

  Future<void> _newTicket() async {
    final ticket = await showModalBottomSheet<SupportTicket>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Zc.bg,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (_) => const _NewTicketSheet(),
    );
    if (ticket == null || !mounted) return;
    _reload();
    Navigator.push(context, MaterialPageRoute(builder: (_) => TicketChatScreen(ticket: ticket)));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Help & support')),
      floatingActionButton: FloatingActionButton.extended(
        backgroundColor: Zc.orange,
        foregroundColor: Colors.white,
        onPressed: _newTicket,
        icon: const Icon(ZI.plus),
        label: const Text('New request'),
      ),
      body: FutureBuilder<List<SupportTicket>>(
        future: _future,
        builder: (context, snap) {
          if (snap.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator(color: Zc.orange));
          }
          final list = snap.data ?? const <SupportTicket>[];
          return ListView(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 100),
            children: [
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(color: Zc.chip, borderRadius: BorderRadius.circular(16)),
                child: const Row(children: [
                  Icon(ZI.chat, color: Zc.green, size: 28),
                  SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      'Questions, problems or a suspicious listing? Write to us — the Zumi team replies within 1–2 working days.',
                      style: TextStyle(fontSize: 14, height: 1.4),
                    ),
                  ),
                ]),
              ),
              const SizedBox(height: 18),
              if (list.isEmpty)
                const EmptyState(icon: ZI.chat, title: 'No requests yet', subtitle: 'Tap “New request” to write to us.')
              else
                for (final t in list)
                  ListTile(
                    contentPadding: const EdgeInsets.symmetric(vertical: 4),
                    leading: CircleAvatar(
                      backgroundColor: t.status == 'answered' ? Zc.orangeSoft : Zc.chip,
                      child: Icon(t.status == 'answered' ? ZI.chatFill : ZI.chat,
                          color: t.status == 'answered' ? Zc.orange : Zc.green),
                    ),
                    title: Text(t.subject, maxLines: 1, overflow: TextOverflow.ellipsis),
                    subtitle: Text(t.lastMessage ?? '', maxLines: 1, overflow: TextOverflow.ellipsis),
                    trailing: Column(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.end, children: [
                      Text(timeAgo(t.lastMessageAt), style: const TextStyle(fontSize: 11, color: Zc.grey)),
                      if (t.status == 'answered')
                        const Text('New reply', style: TextStyle(fontSize: 11, color: Zc.orange, fontWeight: FontWeight.w600)),
                    ]),
                    onTap: () async {
                      await Navigator.push(context, MaterialPageRoute(builder: (_) => TicketChatScreen(ticket: t)));
                      _reload();
                    },
                  ),
            ],
          );
        },
      ),
    );
  }
}

class _NewTicketSheet extends StatefulWidget {
  const _NewTicketSheet();

  @override
  State<_NewTicketSheet> createState() => _NewTicketSheetState();
}

class _NewTicketSheetState extends State<_NewTicketSheet> {
  String _category = 'question';
  final _subject = TextEditingController();
  final _message = TextEditingController();
  bool _sending = false;

  @override
  void dispose() {
    _subject.dispose();
    _message.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    if (_subject.text.trim().length < 3 || _message.text.trim().isEmpty) {
      showSnack(context, 'Please add a short subject and your message');
      return;
    }
    setState(() => _sending = true);
    final app = context.read<AppState>();
    try {
      final id = await app.repo.openTicket(
        category: _category,
        subject: _subject.text,
        message: _message.text,
      );
      if (!mounted) return;
      Navigator.pop(
        context,
        SupportTicket(
          id: id,
          userId: app.user!.id,
          userName: app.user!.fullName,
          category: _category,
          subject: _subject.text.trim(),
          status: 'open',
          lastMessage: _message.text.trim(),
          lastMessageAt: DateTime.now(),
        ),
      );
    } catch (e) {
      if (mounted) showSnack(context, '$e');
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: SafeArea(
        child: ListView(
          shrinkWrap: true,
          padding: const EdgeInsets.fromLTRB(22, 20, 22, 20),
          children: [
            const Text('New request', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w600, color: Zc.green)),
            const SizedBox(height: 14),
            Wrap(spacing: 8, runSpacing: 8, children: [
              for (final e in ticketCategories.entries)
                ZChip(label: e.value, selected: _category == e.key, onTap: () => setState(() => _category = e.key)),
            ]),
            const SizedBox(height: 16),
            TextField(controller: _subject, decoration: const InputDecoration(hintText: 'Subject')),
            const SizedBox(height: 12),
            TextField(
              controller: _message,
              minLines: 4,
              maxLines: 8,
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(hintText: 'Describe your question or problem'),
            ),
            const SizedBox(height: 20),
            PrimaryButton(label: 'Send', width: double.infinity, loading: _sending, onPressed: _send),
          ],
        ),
      ),
    );
  }
}
