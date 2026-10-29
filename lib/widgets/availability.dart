import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/models.dart';
import '../state/app_state.dart';
import '../theme.dart';
import 'common.dart';
import 'zicons.dart';

/// «Ещё доступно?» — один вопрос и две кнопки. Показывается автору на его объявлении и в «Мои объявления»,
/// когда с последнего подтверждения прошло 30 дней, и на объявлении, которое уже скрылось без ответа.
class StillAvailableCard extends StatefulWidget {
  const StillAvailableCard({super.key, required this.p, this.margin = EdgeInsets.zero});
  final Property p;
  final EdgeInsets margin;

  /// Нужен ли вопрос для этого объявления
  static bool shows(Property p) => !p.isDemo && (p.needsAvailabilityAnswer || p.expired);

  @override
  State<StillAvailableCard> createState() => _StillAvailableCardState();
}

class _StillAvailableCardState extends State<StillAvailableCard> {
  bool _busy = false;
  bool _answered = false; // ответили — карточка прячется сразу, не дожидаясь обновления списка

  Future<void> _answer(bool yes) async {
    setState(() => _busy = true);
    try {
      await context.read<AppState>().answerStillAvailable(widget.p.id, yes);
      if (!mounted) return;
      setState(() => _answered = true);
      showSnack(
        context,
        yes
            ? 'Thanks! The listing stays in search for another 30 days.'
            : 'Done — the listing is hidden. You can find it in My listings → Hidden.',
      );
    } catch (e) {
      if (mounted) showSnack(context, '$e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_answered) return const SizedBox.shrink();
    final p = widget.p;
    final expired = p.expired;
    final sale = p.dealType == DealType.sale;
    final left = p.daysUntilHidden;
    return Container(
      margin: widget.margin,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(color: Zc.orangeSoft, borderRadius: BorderRadius.circular(14)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          const Icon(ZI.clock, color: Zc.orange, size: 20),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              sale ? 'Is it still for sale?' : 'Is it still available?',
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: Zc.text),
            ),
          ),
        ]),
        const SizedBox(height: 4),
        Text(
          expired
              ? 'Hidden from search because nobody confirmed it. Answer to show it again.'
              : left <= 0
                  ? 'Please answer today, or the listing will be hidden from search.'
                  : 'Please confirm so people don\'t call about a home that is gone. '
                      'Without an answer it is hidden in $left ${left == 1 ? 'day' : 'days'}.',
          style: const TextStyle(fontSize: 13, color: Zc.text, height: 1.35),
        ),
        const SizedBox(height: 10),
        Wrap(spacing: 10, runSpacing: 8, children: [
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Zc.green,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
            ),
            onPressed: _busy ? null : () => _answer(true),
            child: Text(expired ? 'Yes — show it again' : 'Yes, still available'),
          ),
          OutlinedButton(
            style: OutlinedButton.styleFrom(
              foregroundColor: Zc.text,
              side: const BorderSide(color: Zc.lightGrey),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
            ),
            onPressed: _busy ? null : () => _answer(false),
            child: Text(sale ? 'No, it\'s sold' : 'No, it\'s rented'),
          ),
        ]),
      ]),
    );
  }
}
