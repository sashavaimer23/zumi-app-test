import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/models.dart';
import '../screens/auth_screen.dart';
import '../state/app_state.dart';
import '../theme.dart';
import 'common.dart';
import 'zicons.dart';

/// Звёзды рейтинга
class Stars extends StatelessWidget {
  const Stars({super.key, required this.value, this.size = 16, this.onTap});
  final double value;
  final double size;
  final ValueChanged<int>? onTap;

  @override
  Widget build(BuildContext context) {
    return Row(mainAxisSize: MainAxisSize.min, children: [
      for (var i = 1; i <= 5; i++)
        GestureDetector(
          onTap: onTap == null ? null : () => onTap!(i),
          child: Padding(
            padding: EdgeInsets.only(right: onTap == null ? 1 : 6),
            child: Icon(
              i <= value.round() ? Icons.star_rounded : Icons.star_outline_rounded,
              size: size,
              color: const Color(0xFFF5A623),
            ),
          ),
        ),
    ]);
  }
}

/// Отзывы об авторе объявления (агенте или собственнике)
class ReviewsSection extends StatefulWidget {
  const ReviewsSection({super.key, required this.targetId, required this.name, this.propertyId});
  final String targetId;
  final String name;
  final String? propertyId;

  @override
  State<ReviewsSection> createState() => _ReviewsSectionState();
}

class _ReviewsSectionState extends State<ReviewsSection> {
  late Future<List<dynamic>> _future;
  bool _showAll = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  void _load() {
    final repo = context.read<AppState>().repo;
    _future = Future.wait<dynamic>([repo.ratingOf(widget.targetId), repo.reviewsAbout(widget.targetId)]);
  }

  Future<void> _write() async {
    final app = context.read<AppState>();
    if (!app.signedIn) {
      final ok = await Navigator.push<bool>(
        context,
        MaterialPageRoute(builder: (_) => const AuthScreen(reason: 'Sign in to write a review.')),
      );
      if (ok != true || !mounted) return;
    }
    final sent = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Zc.bg,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (_) => _WriteReviewSheet(targetId: widget.targetId, name: widget.name, propertyId: widget.propertyId),
    );
    if (sent == true && mounted) setState(_load);
  }

  Future<void> _flag(Review r) async {
    final app = context.read<AppState>();
    if (!app.signedIn) {
      showSnack(context, 'Sign in to report a review');
      return;
    }
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Report this review?'),
        content: const Text('Our team will check if it breaks the rules (insults, fake, personal data).'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Report')),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await app.repo.flagReview(r.id);
      if (mounted) showSnack(context, 'Thank you, we will check it.');
    } catch (e) {
      if (mounted) showSnack(context, '$e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final me = context.watch<AppState>().user?.id;
    return FutureBuilder<List<dynamic>>(
      future: _future,
      builder: (context, snap) {
        if (!snap.hasData) return const SizedBox(height: 40);
        final rating = snap.data![0] as Rating;
        final reviews = snap.data![1] as List<Review>;
        final shown = _showAll ? reviews : reviews.take(3).toList();

        return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Expanded(
              child: Text('Reviews about ${widget.name}',
                  style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w600, color: Zc.green)),
            ),
            if (me != widget.targetId)
              TextButton.icon(
                onPressed: _write,
                icon: const Icon(ZI.plus, size: 16, color: Zc.orange),
                label: const Text('Write', style: TextStyle(color: Zc.orange)),
              ),
          ]),
          const SizedBox(height: 6),
          if (rating.count == 0)
            const Text('No reviews yet. Be the first after your viewing.', style: TextStyle(color: Zc.grey))
          else ...[
            Row(children: [
              Text(rating.average.toStringAsFixed(1),
                  style: const TextStyle(fontSize: 28, fontWeight: FontWeight.w700)),
              const SizedBox(width: 10),
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Stars(value: rating.average, size: 18),
                Text('${rating.count} review${rating.count == 1 ? '' : 's'}',
                    style: const TextStyle(fontSize: 12, color: Zc.grey)),
              ]),
            ]),
            const SizedBox(height: 10),
            for (final r in shown)
              Container(
                width: double.infinity,
                margin: const EdgeInsets.only(bottom: 10),
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: Zc.chip),
                ),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Row(children: [
                    Stars(value: r.rating.toDouble(), size: 14),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text('${r.authorName ?? 'User'} · ${timeAgo(r.createdAt)}',
                          style: const TextStyle(fontSize: 12, color: Zc.grey)),
                    ),
                    if (r.authorId != me)
                      InkWell(
                        onTap: () => _flag(r),
                        child: const Padding(
                          padding: EdgeInsets.all(4),
                          child: Icon(ZI.flag, size: 16, color: Zc.grey),
                        ),
                      ),
                  ]),
                  if ((r.body ?? '').isNotEmpty) ...[
                    const SizedBox(height: 6),
                    Text(r.body!, style: const TextStyle(fontSize: 14, height: 1.4)),
                  ],
                  if (r.zumiReply != null) ...[
                    const SizedBox(height: 8),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(color: Zc.chip, borderRadius: BorderRadius.circular(10)),
                      child: Text.rich(TextSpan(children: [
                        const TextSpan(text: 'Zumi team: ', style: TextStyle(fontWeight: FontWeight.w600, color: Zc.green)),
                        TextSpan(text: r.zumiReply),
                      ]), style: const TextStyle(fontSize: 13)),
                    ),
                  ],
                ]),
              ),
            if (reviews.length > 3 && !_showAll)
              TextButton(
                onPressed: () => setState(() => _showAll = true),
                child: Text('Show all ${reviews.length} reviews', style: const TextStyle(color: Zc.green)),
              ),
          ],
        ]);
      },
    );
  }
}

class _WriteReviewSheet extends StatefulWidget {
  const _WriteReviewSheet({required this.targetId, required this.name, this.propertyId});
  final String targetId;
  final String name;
  final String? propertyId;

  @override
  State<_WriteReviewSheet> createState() => _WriteReviewSheetState();
}

class _WriteReviewSheetState extends State<_WriteReviewSheet> {
  int _rating = 0;
  final _body = TextEditingController();
  bool _sending = false;

  @override
  void dispose() {
    _body.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    if (_rating == 0) {
      showSnack(context, 'Please choose a rating');
      return;
    }
    setState(() => _sending = true);
    try {
      await context.read<AppState>().repo.writeReview(
            targetId: widget.targetId,
            rating: _rating,
            body: _body.text,
            propertyId: widget.propertyId,
          );
      if (mounted) Navigator.pop(context, true);
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
            Text('Review ${widget.name}',
                style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w600, color: Zc.green)),
            const SizedBox(height: 6),
            const Text('How was your experience — viewing, communication, honesty?',
                style: TextStyle(color: Zc.grey)),
            const SizedBox(height: 16),
            Stars(value: _rating.toDouble(), size: 36, onTap: (v) => setState(() => _rating = v)),
            const SizedBox(height: 16),
            TextField(
              controller: _body,
              minLines: 3,
              maxLines: 6,
              maxLength: 2000,
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(hintText: 'Tell others what happened (optional)'),
            ),
            const Text('Please be respectful and do not share phone numbers or personal data.',
                style: TextStyle(fontSize: 12, color: Zc.grey)),
            const SizedBox(height: 18),
            PrimaryButton(label: 'Publish review', width: double.infinity, loading: _sending, onPressed: _send),
          ],
        ),
      ),
    );
  }
}
