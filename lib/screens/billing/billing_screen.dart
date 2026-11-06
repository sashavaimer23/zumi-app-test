import 'dart:async';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../features.dart';
import '../../models/models.dart';
import '../../state/app_state.dart';
import '../../theme.dart';
import '../../widgets/common.dart';
import '../../widgets/zicons.dart';

/// Платные функции: тариф, пакеты, доп. места, история заказов.
/// Покупать можно только на сайте (в приложениях из магазинов — правила Apple и Google).
Future<void> openPlans(BuildContext context) =>
    Navigator.push(context, MaterialPageRoute(builder: (_) => const PlansScreen()));

class PlansScreen extends StatefulWidget {
  const PlansScreen({super.key});

  @override
  State<PlansScreen> createState() => _PlansScreenState();
}

class _PlansScreenState extends State<PlansScreen> {
  late Future<(BillingInfo, List<PriceItem>, List<OrderInfo>)> _data = _load();

  Future<(BillingInfo, List<PriceItem>, List<OrderInfo>)> _load() async {
    final repo = context.read<AppState>().repo;
    final r = await Future.wait([repo.myBilling(), repo.priceList(), repo.myOrders()]);
    return (r[0] as BillingInfo, r[1] as List<PriceItem>, r[2] as List<OrderInfo>);
  }

  void _reload() => setState(() => _data = _load());

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final agent = app.user?.isAgent ?? false;
    return Scaffold(
      appBar: AppBar(title: const Text('Plans & payments')),
      body: FutureBuilder<(BillingInfo, List<PriceItem>, List<OrderInfo>)>(
        future: _data,
        builder: (context, snap) {
          if (snap.hasError) return Center(child: Text('${snap.error}'));
          if (!snap.hasData) return const Center(child: CircularProgressIndicator());
          final (b, prices, orders) = snap.data!;
          // агентам — Pro и Agency, собственникам — тариф арендодателя
          final plans = prices.where((p) => p.kind == 'plan' && (agent ? !p.ownersOnly : !p.agentsOnly)).toList();
          final slots = prices.where((p) => p.kind == 'slots').toList();
          final packs = prices.where((p) => p.kind == 'boost_pack').toList();
          return RefreshIndicator(
            onRefresh: () async => _reload(),
            child: ListView(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 60),
              children: [
                _MyPlanCard(b: b),
                if (!kIsWeb) ...[
                  const SizedBox(height: 14),
                  const _Note('To buy boosts, extra listings or a plan, open Zumi in your browser — '
                      'payments are made on the Zumi website.'),
                ] else if (!Features.billing) ...[
                  const SizedBox(height: 14),
                  const _Note('Zumi is free during launch. Plans and boosts will appear here later.'),
                ],
                if (app.canBuy && plans.isNotEmpty) ...[
                  agent
                      ? _title('Plans for agents', 'More listings, boosts every month and a Pro badge. Pay for 3, 6 or 12 months and save.')
                      : _title('Landlord plan', 'Have more than 2 properties? Post up to 10 — from K75 a month. Pay for longer and save.'),
                  for (final p in plans) _PriceCard(item: p, onBuy: () => _buy(p)),
                ],
                if (app.canBuy && packs.isNotEmpty) ...[
                  _title('Boost packs', 'Buy boosts in advance and use them on any listing.'),
                  for (final p in packs) _PriceCard(item: p, onBuy: () => _buy(p)),
                ],
                if (app.canBuy && slots.isNotEmpty) ...[
                  _title('Extra listings', 'Post more than your free limit.'),
                  for (final p in slots) _PriceCard(item: p, onBuy: () => _buy(p)),
                ],
                if (orders.isNotEmpty) ...[
                  _title('My orders', null),
                  for (final o in orders) _OrderTile(o: o, onChanged: _reload),
                ],
              ],
            ),
          );
        },
      ),
    );
  }

  Future<void> _buy(PriceItem item) async {
    final done = await showCheckout(context, item);
    if (done == true && mounted) _reload();
  }

  Widget _title(String t, String? sub) => Padding(
        padding: const EdgeInsets.only(top: 26, bottom: 10),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(t, style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w700, color: Zc.text)),
          if (sub != null) ...[
            const SizedBox(height: 2),
            Text(sub, style: const TextStyle(fontSize: 13, color: Zc.grey)),
          ],
        ]),
      );
}

class _MyPlanCard extends StatelessWidget {
  const _MyPlanCard({required this.b});
  final BillingInfo b;

  @override
  Widget build(BuildContext context) {
    final until = b.planUntil;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(color: Zc.greenTint, borderRadius: BorderRadius.circular(16)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          const Icon(ZI.crown, color: Zc.green),
          const SizedBox(width: 8),
          Text('Your plan: ${b.planLabel}', style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
        ]),
        if (until != null) ...[
          const SizedBox(height: 4),
          Text('Active until ${until.day}.${until.month}.${until.year}', style: const TextStyle(color: Zc.text)),
        ],
        const SizedBox(height: 10),
        Wrap(spacing: 16, runSpacing: 6, children: [
          Text('Boosts left: ${b.boostCredits}', style: const TextStyle(fontWeight: FontWeight.w600)),
          if (b.extraSlots > 0) Text('Extra listings: +${b.extraSlots}', style: const TextStyle(fontWeight: FontWeight.w600)),
        ]),
        if (b.boostCredits > 0) ...[
          const SizedBox(height: 6),
          const Text('Use a boost from the ⋯ menu of your listing in Profile.',
              style: TextStyle(fontSize: 12, color: Zc.grey)),
        ],
      ]),
    );
  }
}

class _Note extends StatelessWidget {
  const _Note(this.text);
  final String text;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(color: Zc.orangeSoft, borderRadius: BorderRadius.circular(12)),
        child: Text(text, style: const TextStyle(fontSize: 13, height: 1.35)),
      );
}

class _PriceCard extends StatelessWidget {
  const _PriceCard({required this.item, required this.onBuy});
  final PriceItem item;
  final VoidCallback onBuy;

  @override
  Widget build(BuildContext context) => Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: Zc.lightGrey),
        ),
        child: Row(children: [
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(item.title, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
              const SizedBox(height: 3),
              Text(item.description, style: const TextStyle(fontSize: 13, color: Zc.grey, height: 1.3)),
            ]),
          ),
          const SizedBox(width: 10),
          Column(children: [
            Text(item.priceLabel, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800, color: Zc.green)),
            const SizedBox(height: 6),
            FilledButton(
              onPressed: onBuy,
              style: FilledButton.styleFrom(backgroundColor: Zc.orange, visualDensity: VisualDensity.compact),
              child: const Text('Buy'),
            ),
          ]),
        ]),
      );
}

class _OrderTile extends StatelessWidget {
  const _OrderTile({required this.o, required this.onChanged});
  final OrderInfo o;
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context) {
    final color = o.done ? Zc.green : (o.pending ? Zc.orange : Zc.grey);
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Zc.lightGrey),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Expanded(
            child: Text(o.itemTitle ?? o.itemCode, style: const TextStyle(fontWeight: FontWeight.w700)),
          ),
          Text(money(o.amount, o.currency), style: const TextStyle(fontWeight: FontWeight.w700)),
        ]),
        const SizedBox(height: 4),
        Text('${o.ref} · ${o.statusLabel}', style: TextStyle(fontSize: 13, color: color)),
        if (o.propertyTitle != null)
          Text(o.propertyTitle!, style: const TextStyle(fontSize: 12, color: Zc.grey)),
        if (o.pending)
          Row(children: [
            TextButton(
              onPressed: () => showOrderPayment(context, o),
              child: const Text('How to pay', style: TextStyle(color: Zc.green)),
            ),
            TextButton(
              onPressed: () async {
                try {
                  await context.read<AppState>().repo.cancelOrder(o.id);
                  onChanged();
                } catch (e) {
                  if (context.mounted) showSnack(context, '$e');
                }
              },
              child: const Text('Cancel', style: TextStyle(color: Zc.grey)),
            ),
          ]),
      ]),
    );
  }
}

// ======================================================================
// Буст своего объявления: из запаса или купить
// ======================================================================
Future<void> showBoostSheet(BuildContext context, Property p) async {
  final app = context.read<AppState>();
  final agent = app.user?.isAgent ?? false;
  final (BillingInfo b, List<PriceItem> prices) = await (app.repo.myBilling(), app.repo.priceList()).wait;
  if (!context.mounted) return;
  final items = prices.where((i) => (i.kind == 'boost' || i.kind == 'featured') && (agent || !i.agentsOnly)).toList();
  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (ctx) => SafeArea(
      child: ListView(
        shrinkWrap: true,
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
        children: [
          Text('Get more views', style: zHeadline(ctx, size: 26)),
          const SizedBox(height: 4),
          Text(p.title, style: const TextStyle(color: Zc.grey)),
          const SizedBox(height: 16),
          if (b.boostCredits > 0)
            _BoostOption(
              title: 'Use a boost from your pack',
              sub: '7 days at the top of search · ${b.boostCredits} left',
              price: 'Free',
              onTap: () async {
                try {
                  await app.repo.useBoostCredit(p.id);
                  app.dataChanged();
                  if (ctx.mounted) Navigator.pop(ctx);
                  if (context.mounted) showSnack(context, 'Boosted for 7 days 🚀');
                } catch (e) {
                  if (ctx.mounted) showSnack(ctx, '$e');
                }
              },
            ),
          if (app.canBuy)
            for (final i in items)
              _BoostOption(
                title: i.title,
                sub: i.description,
                price: i.priceLabel,
                onTap: () async {
                  Navigator.pop(ctx);
                  await showCheckout(context, i, propertyId: p.id, propertyTitle: p.title);
                },
              )
          else if (b.boostCredits == 0)
            const _Note('Boosts are bought on the Zumi website.'),
          const SizedBox(height: 8),
          const Text('Boosted listings show a "Promoted" mark. You can see the extra views in your listing statistics.',
              style: TextStyle(fontSize: 12, color: Zc.grey)),
        ],
      ),
    ),
  );
}

class _BoostOption extends StatelessWidget {
  const _BoostOption({required this.title, required this.sub, required this.price, required this.onTap});
  final String title, sub, price;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: Material(
          color: Colors.white,
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14), side: const BorderSide(color: Zc.lightGrey)),
          child: InkWell(
            borderRadius: BorderRadius.circular(14),
            onTap: onTap,
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Row(children: [
                const Icon(ZI.bolt, color: Zc.orange),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(title, style: const TextStyle(fontWeight: FontWeight.w700)),
                    Text(sub, style: const TextStyle(fontSize: 12, color: Zc.grey)),
                  ]),
                ),
                const SizedBox(width: 8),
                Text(price, style: const TextStyle(fontWeight: FontWeight.w800, color: Zc.green)),
              ]),
            ),
          ),
        ),
      );
}

// ======================================================================
// Оформление: номер Mobile Money → заказ → как оплатить
// ======================================================================
Future<bool?> showCheckout(BuildContext context, PriceItem item, {String? propertyId, String? propertyTitle}) {
  return showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (ctx) => Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(ctx).bottom),
      child: _Checkout(item: item, propertyId: propertyId, propertyTitle: propertyTitle),
    ),
  );
}

class _Checkout extends StatefulWidget {
  const _Checkout({required this.item, this.propertyId, this.propertyTitle});
  final PriceItem item;
  final String? propertyId;
  final String? propertyTitle;

  @override
  State<_Checkout> createState() => _CheckoutState();
}

class _CheckoutState extends State<_Checkout> {
  late final _phone = TextEditingController(text: context.read<AppState>().user?.phone ?? '');
  bool _loading = false;

  @override
  void dispose() {
    _phone.dispose();
    super.dispose();
  }

  Future<void> _order() async {
    setState(() => _loading = true);
    final nav = Navigator.of(context);
    final outer = Navigator.of(context).context;
    try {
      final o = await context.read<AppState>().repo
          .createOrder(widget.item.code, propertyId: widget.propertyId, phone: _phone.text);
      nav.pop(true);
      if (outer.mounted) await showOrderPayment(outer, o);
    } on AppException catch (e) {
      if (mounted) showSnack(context, e.message);
    } catch (e) {
      if (mounted) showSnack(context, '$e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final i = widget.item;
    return SafeArea(
      child: ListView(
        shrinkWrap: true,
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
        children: [
          Text(i.title, style: zHeadline(context, size: 24)),
          if (widget.propertyTitle != null) ...[
            const SizedBox(height: 4),
            Text(widget.propertyTitle!, style: const TextStyle(color: Zc.grey)),
          ],
          const SizedBox(height: 8),
          Text(i.description, style: const TextStyle(fontSize: 14, height: 1.35)),
          const SizedBox(height: 16),
          Row(children: [
            const Text('To pay', style: TextStyle(fontSize: 16)),
            const Spacer(),
            Text(i.priceLabel, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800, color: Zc.green)),
          ]),
          const SizedBox(height: 16),
          const Text('Your Mobile Money number', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
          const SizedBox(height: 6),
          TextField(
            controller: _phone,
            keyboardType: TextInputType.phone,
            decoration: const InputDecoration(hintText: '+260 97 123 4567'),
          ),
          const SizedBox(height: 6),
          const Text('Airtel Money, MTN MoMo or Zamtel Kwacha. We use it only to match your payment.',
              style: TextStyle(fontSize: 12, color: Zc.grey)),
          const SizedBox(height: 20),
          PrimaryButton(label: 'Continue to payment', width: double.infinity, loading: _loading, onPressed: _order),
        ],
      ),
    );
  }
}

/// Как оплатить заказ (ручная оплата: перевод на номер Zumi с кодом заказа)
Future<void> showOrderPayment(BuildContext context, OrderInfo o) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (ctx) => SafeArea(
      child: ListView(
        shrinkWrap: true,
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
        children: [
          Text('Pay ${money(o.amount, o.currency)}', style: zHeadline(ctx, size: 28)),
          const SizedBox(height: 4),
          Text(o.itemTitle ?? '', style: const TextStyle(color: Zc.grey)),
          const SizedBox(height: 16),
          if (o.mode == 'auto') ...[
            const Text('Approve the payment on your phone. Your purchase switches on as soon as it goes through.',
                style: TextStyle(fontSize: 15, height: 1.4)),
          ] else ...[
            const Text('Send the money by Mobile Money:', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(color: Zc.greenTint, borderRadius: BorderRadius.circular(12)),
              child: Text(
                (o.paymentInfo ?? '').trim().isEmpty
                    ? 'The Zumi team will send you the payment details.'
                    : o.paymentInfo!.trim(),
                style: const TextStyle(fontSize: 15, height: 1.4),
              ),
            ),
            const SizedBox(height: 14),
            const Text('Reference (write it in the payment message):', style: TextStyle(fontSize: 14)),
            const SizedBox(height: 6),
            Row(children: [
              Text(o.ref, style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w800, letterSpacing: 1.5)),
              IconButton(
                tooltip: 'Copy',
                onPressed: () {
                  Clipboard.setData(ClipboardData(text: o.ref));
                  showSnack(ctx, 'Copied');
                },
                icon: const Icon(ZI.copy, color: Zc.green),
              ),
            ]),
            const SizedBox(height: 10),
            const Text(
              'We switch your purchase on as soon as we see the payment — usually within a few hours. '
              'You can follow it in Profile → Plans & payments. Never pay anyone who contacts you privately.',
              style: TextStyle(fontSize: 13, color: Zc.grey, height: 1.4),
            ),
          ],
          const SizedBox(height: 18),
          PrimaryButton(label: 'Done', width: double.infinity, onPressed: () => Navigator.pop(ctx)),
        ],
      ),
    ),
  );
}
