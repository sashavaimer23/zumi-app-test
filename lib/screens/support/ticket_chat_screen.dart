import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/models.dart';
import '../../state/app_state.dart';
import '../../theme.dart';
import '../../widgets/common.dart';
import '../../widgets/zicons.dart';

/// Переписка по обращению. asStaff = true — открыто из кабинета команды.
class TicketChatScreen extends StatefulWidget {
  const TicketChatScreen({super.key, required this.ticket, this.asStaff = false});
  final SupportTicket ticket;
  final bool asStaff;

  @override
  State<TicketChatScreen> createState() => _TicketChatScreenState();
}

class _TicketChatScreenState extends State<TicketChatScreen> {
  final _ctrl = TextEditingController();
  late final Stream<List<SupportMessage>> _stream =
      context.read<AppState>().repo.ticketMessages(widget.ticket.id);
  late String _status = widget.ticket.status;
  bool _sending = false;

  // быстрые ответы для команды — экономят время
  static const _templates = [
    'Thank you for your message! We are looking into it and will reply within 1–2 working days.',
    'Please never pay any deposit or fee before you have seen the property in person.',
    'We have hidden this listing and are checking the author. Thank you for reporting!',
    'Could you send us a screenshot of the problem, please?',
    'This should be fixed now — please try again and let us know.',
  ];

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    final text = _ctrl.text.trim();
    if (text.isEmpty || _sending) return;
    setState(() => _sending = true);
    try {
      await context.read<AppState>().repo.sendTicketMessage(widget.ticket.id, text, asStaff: widget.asStaff);
      _ctrl.clear();
      if (mounted) setState(() => _status = widget.asStaff ? 'answered' : 'open');
    } catch (e) {
      if (mounted) showSnack(context, '$e');
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  Future<void> _close() async {
    try {
      await context.read<AppState>().repo.adminSetTicketStatus(widget.ticket.id, 'closed');
      if (mounted) setState(() => _status = 'closed');
    } catch (e) {
      if (mounted) showSnack(context, '$e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = widget.ticket;
    return Scaffold(
      appBar: AppBar(
        title: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(t.subject, style: const TextStyle(fontSize: 16), maxLines: 1, overflow: TextOverflow.ellipsis),
          Text(
            widget.asStaff
                ? '${t.userName ?? 'User'} · ${ticketCategories[t.category] ?? t.category}'
                : 'Zumi support · ${_statusLabel(_status)}',
            style: const TextStyle(fontSize: 12, color: Zc.grey),
          ),
        ]),
        actions: [
          if (widget.asStaff && _status != 'closed')
            TextButton(onPressed: _close, child: const Text('Close ticket', style: TextStyle(color: Zc.green))),
        ],
      ),
      body: Column(children: [
        Expanded(
          child: StreamBuilder<List<SupportMessage>>(
            stream: _stream,
            builder: (context, snap) {
              if (!snap.hasData) return const Center(child: CircularProgressIndicator(color: Zc.orange));
              final msgs = snap.data!.reversed.toList();
              return ListView.builder(
                reverse: true,
                padding: const EdgeInsets.all(14),
                itemCount: msgs.length,
                itemBuilder: (_, i) {
                  final m = msgs[i];
                  // «мои» сообщения справа: для команды — ответы команды, для пользователя — его собственные
                  final mine = widget.asStaff ? m.isStaff : !m.isStaff;
                  return Align(
                    alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
                    child: Container(
                      constraints: BoxConstraints(maxWidth: MediaQuery.sizeOf(context).width * 0.72),
                      margin: const EdgeInsets.symmetric(vertical: 4),
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                      decoration: BoxDecoration(
                        color: mine ? Zc.green : Colors.white,
                        borderRadius: BorderRadius.circular(16),
                        border: mine ? null : Border.all(color: Zc.lightGrey),
                      ),
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        if (m.isStaff && !widget.asStaff)
                          const Padding(
                            padding: EdgeInsets.only(bottom: 4),
                            child: Text('Zumi support',
                                style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: Zc.orange)),
                          ),
                        Text(m.body, style: TextStyle(color: mine ? Colors.white : Zc.text, fontSize: 15)),
                        const SizedBox(height: 4),
                        Text(timeAgo(m.createdAt),
                            style: TextStyle(fontSize: 10, color: mine ? Zc.navInactive : Zc.grey)),
                      ]),
                    ),
                  );
                },
              );
            },
          ),
        ),
        if (widget.asStaff)
          SizedBox(
            height: 44,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 12),
              itemCount: _templates.length,
              separatorBuilder: (_, __) => const SizedBox(width: 8),
              itemBuilder: (_, i) => ActionChip(
                label: Text(_templates[i], maxLines: 1, overflow: TextOverflow.ellipsis),
                backgroundColor: Zc.chip,
                side: BorderSide.none,
                onPressed: () => setState(() => _ctrl.text = _templates[i]),
              ),
            ),
          ),
        SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 6, 12, 10),
            child: Row(children: [
              Expanded(
                child: TextField(
                  controller: _ctrl,
                  minLines: 1,
                  maxLines: 5,
                  textCapitalization: TextCapitalization.sentences,
                  decoration: InputDecoration(
                    hintText: widget.asStaff ? 'Reply as Zumi support…' : 'Write a message…',
                    contentPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(24),
                      borderSide: const BorderSide(color: Zc.lightGrey),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(24),
                      borderSide: const BorderSide(color: Zc.orange),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              GestureDetector(
                onTap: _send,
                child: Container(
                  width: 48,
                  height: 48,
                  decoration: const BoxDecoration(color: Zc.orange, shape: BoxShape.circle),
                  child: _sending
                      ? const Padding(
                          padding: EdgeInsets.all(14),
                          child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                        )
                      : const Icon(ZI.send, color: Colors.white, size: 22),
                ),
              ),
            ]),
          ),
        ),
      ]),
    );
  }
}

String _statusLabel(String s) => switch (s) {
      'answered' => 'answered',
      'closed' => 'closed',
      _ => 'waiting for reply',
    };
