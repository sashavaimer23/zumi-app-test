import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/models.dart';
import '../state/app_state.dart';
import '../theme.dart';
import 'common.dart';
import 'zicons.dart';

/// Маленькая плашка над меню: «Как вам Zumi?». Не закрывает экран, убирается одним нажатием.
class FeedbackPromptCard extends StatelessWidget {
  const FeedbackPromptCard({super.key});

  @override
  Widget build(BuildContext context) {
    final app = context.read<AppState>();
    return Material(
      color: Colors.white,
      elevation: 6,
      shadowColor: Zc.shadow,
      borderRadius: BorderRadius.circular(18),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 6, 12),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
          Row(children: [
            const Expanded(
              child: Text('How is Zumi working for you?',
                  style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: Zc.green)),
            ),
            IconButton(
              tooltip: 'Not now',
              visualDensity: VisualDensity.compact,
              icon: const Icon(ZI.close, size: 18, color: Zc.grey),
              onPressed: () => app.hideFeedbackPrompt(),
            ),
          ]),
          const Text(
            'We want Zumi to be easy for you. If something doesn\'t work well, tell us — it takes 20 seconds.',
            style: TextStyle(fontSize: 13, color: Zc.text, height: 1.35),
          ),
          const SizedBox(height: 8),
          _Stars(onPick: (r) {
            app.hideFeedbackPrompt();
            showAppFeedbackSheet(context, rating: r);
          }),
        ]),
      ),
    );
  }
}

class _Stars extends StatelessWidget {
  const _Stars({required this.onPick, this.value = 0});
  final ValueChanged<int> onPick;
  final int value;

  @override
  Widget build(BuildContext context) => Row(mainAxisSize: MainAxisSize.min, children: [
        for (var i = 1; i <= 5; i++)
          IconButton(
            tooltip: '$i of 5',
            visualDensity: VisualDensity.compact,
            onPressed: () => onPick(i),
            icon: Icon(i <= value ? ZI.star : ZI.starLine, size: 30, color: i <= value ? Zc.orange : Zc.lightGrey),
          ),
      ]);
}

/// Окно отзыва: оценка, что не работает, комментарий. Открывается из плашки и из Настроек.
Future<void> showAppFeedbackSheet(BuildContext context, {int rating = 0}) => showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      backgroundColor: Zc.bg,
      builder: (_) => Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
        child: _FeedbackForm(initial: rating),
      ),
    );

class _FeedbackForm extends StatefulWidget {
  const _FeedbackForm({required this.initial});
  final int initial;

  @override
  State<_FeedbackForm> createState() => _FeedbackFormState();
}

class _FeedbackFormState extends State<_FeedbackForm> {
  late int _rating = widget.initial;
  final _issues = <String>{};
  final _comment = TextEditingController();
  bool _sending = false;

  @override
  void dispose() {
    _comment.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    if (_rating == 0) {
      showSnack(context, 'Please choose from 1 to 5 stars');
      return;
    }
    setState(() => _sending = true);
    final app = context.read<AppState>();
    final nav = Navigator.of(context);
    final messenger = ScaffoldMessenger.of(context);
    try {
      await app.repo.sendAppFeedback(
        rating: _rating,
        issues: _issues.toList(),
        comment: _comment.text.trim().isEmpty ? null : _comment.text.trim(),
      );
      app.hideFeedbackPrompt(given: true);
      nav.pop();
      messenger.showSnackBar(const SnackBar(content: Text('Thank you! The Zumi team reads every message.')));
    } on AppException catch (e) {
      if (!mounted) return;
      showSnack(context, e.code == null && e.message.contains('Too many')
          ? 'You already sent feedback today — thank you!'
          : e.message);
    } catch (e) {
      if (mounted) showSnack(context, '$e');
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final low = _rating > 0 && _rating <= 3;
    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(22, 0, 22, 22),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('How is Zumi working for you?', style: zHeadline(context, size: 24)),
          const SizedBox(height: 6),
          const Text('Your answer helps us fix what bothers you first.',
              style: TextStyle(fontSize: 14, color: Zc.grey)),
          const SizedBox(height: 10),
          _Stars(value: _rating, onPick: (r) => setState(() => _rating = r)),
          const SizedBox(height: 12),
          Text(low ? 'What doesn\'t work well?' : 'Anything we can do better? (optional)',
              style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
          const SizedBox(height: 8),
          Wrap(spacing: 8, runSpacing: 8, children: [
            for (final e in kFeedbackIssues.entries)
              ZChip(
                label: e.value,
                selected: _issues.contains(e.key),
                onTap: () => setState(() => _issues.contains(e.key) ? _issues.remove(e.key) : _issues.add(e.key)),
              ),
          ]),
          const SizedBox(height: 14),
          TextField(
            controller: _comment,
            maxLength: 1000,
            minLines: 2,
            maxLines: 5,
            textCapitalization: TextCapitalization.sentences,
            decoration: const InputDecoration(
              hintText: 'Tell us more (optional). Please don\'t write passwords or phone numbers.',
            ),
          ),
          const SizedBox(height: 6),
          PrimaryButton(label: 'Send', loading: _sending, width: double.infinity, onPressed: _send),
        ]),
      ),
    );
  }
}
