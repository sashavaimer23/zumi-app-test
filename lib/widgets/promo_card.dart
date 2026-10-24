import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../models/models.dart';
import '../state/app_state.dart';
import '../theme.dart';
import 'common.dart';
import 'contact.dart';
import 'results.dart';
import 'trust.dart';
import 'wide_card.dart';
import 'zicons.dart';

/// Карточка продвигаемого объявления. Та же карточка в предпросмотре мастера
/// (тогда preview = true: ничего не считается и не открывается).
class PromotedCard extends StatefulWidget {
  const PromotedCard({
    super.key,
    required this.campaign,
    required this.property,
    this.imageBytes,
    this.wide = false,
    this.preview = false,
  });

  final Campaign campaign;
  final Property property;
  final Uint8List? imageBytes; // предпросмотр до загрузки
  final bool wide; // вариант для компьютера
  final bool preview;

  @override
  State<PromotedCard> createState() => _PromotedCardState();
}

/// Показ считается один раз за сеанс для каждой кампании
final Set<String> _seenCampaigns = {};

class _PromotedCardState extends State<PromotedCard> {
  @override
  void initState() {
    super.initState();
    if (!widget.preview && _seenCampaigns.add(widget.campaign.id)) {
      context.read<AppState>().repo.logCampaignEvent(widget.campaign.id, 'view');
    }
  }

  Campaign get c => widget.campaign;
  Property get p => widget.property;

  void _open() {
    if (widget.preview) return;
    context.read<AppState>().repo.logCampaignEvent(c.id, 'click');
    openProperty(context, p);
  }

  /// Ссылка на сайт рекламодателя (телефон в кампании больше не хранится)
  String? get _link {
    final link = (c.contact ?? '').trim();
    return link.isEmpty || !c.contactIsLink ? null : link;
  }

  Future<void> _visit() async {
    if (widget.preview) return;
    final link = _link;
    if (link == null) return;
    context.read<AppState>().repo.logCampaignEvent(c.id, 'click');
    await launchUrl(Uri.parse(link.startsWith('http') ? link : 'https://$link'), mode: LaunchMode.externalApplication);
  }

  /// Позвонить — через обычную кнопку «Show number» (вход, подтверждённый телефон, лимит)
  Future<void> _showNumber() async {
    if (widget.preview) return;
    context.read<AppState>().repo.logCampaignEvent(c.id, 'click');
    await Contact.showNumber(context, p);
  }

  Widget _image(double radius) {
    final Widget img = widget.imageBytes != null
        ? Image.memory(widget.imageBytes!, fit: BoxFit.cover)
        : PropImage(c.imageUrl ?? p.coverThumb);
    return ClipRRect(
      borderRadius: BorderRadius.circular(radius),
      child: Stack(fit: StackFit.expand, children: [
        img,
        const Positioned(top: 12, left: 12, child: PromotedTag()),
        if (p.isVerified) const Positioned(top: 12, right: 12, child: VerifiedBadge(compact: true)),
      ]),
    );
  }

  Widget _cta() {
    final style = FilledButton.styleFrom(
      backgroundColor: Zc.orange,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
    );
    if (_link != null) {
      return FilledButton.icon(
        style: style,
        onPressed: _visit,
        icon: const Icon(ZI.globe, size: 18),
        label: const Text('Visit website'),
      );
    }
    if (p.chatOnly || !p.hasPhone) return const SizedBox.shrink();
    return FilledButton.icon(
      style: style,
      onPressed: _showNumber,
      icon: const Icon(ZI.phone, size: 18),
      label: const Text('Show number'),
    );
  }

  Widget _texts({bool big = false}) => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(p.priceLabel, style: TextStyle(fontSize: big ? 24 : 22, fontWeight: FontWeight.w600, color: Zc.text)),
        const SizedBox(height: 6),
        Text(p.title,
            style: const TextStyle(fontSize: 17, color: Zc.text), maxLines: 1, overflow: TextOverflow.ellipsis),
        const SizedBox(height: 4),
        Text(p.specsLine, style: const TextStyle(fontSize: 15, color: Zc.text)),
        const SizedBox(height: 4),
        Text(p.locationLine,
            style: const TextStyle(fontSize: 14, color: Zc.grey), maxLines: 1, overflow: TextOverflow.ellipsis),
      ]);

  Widget _byLine() => Text('Promoted by ${c.advertiser}',
      maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12, color: Zc.grey));

  @override
  Widget build(BuildContext context) {
    if (widget.wide) {
      // компьютер: картинка слева, текст справа — как широкая карточка в ленте
      return GestureDetector(
        onTap: _open,
        behavior: HitTestBehavior.opaque,
        child: Container(
          margin: const EdgeInsets.only(bottom: 18),
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: Zc.orange.withAlpha(110), width: 1.2),
          ),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            SizedBox(width: 400, child: AspectRatio(aspectRatio: kPromoRatio, child: _image(14))),
            const SizedBox(width: 22),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  _texts(big: true),
                  const SizedBox(height: 18),
                  Row(children: [Expanded(child: _byLine()), _cta()]),
                ]),
              ),
            ),
          ]),
        ),
      );
    }
    // телефон: как обычная карточка, плюс метка «Promoted» и кнопка связи
    return GestureDetector(
      onTap: _open,
      behavior: HitTestBehavior.opaque,
      child: Padding(
        padding: const EdgeInsets.only(bottom: 28),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          AspectRatio(aspectRatio: kPromoRatio, child: _image(18)),
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 14, 14, 0),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              _texts(),
              const SizedBox(height: 10),
              Row(children: [Expanded(child: _byLine()), _cta()]),
            ]),
          ),
        ]),
      ),
    );
  }
}

/// Пропорции картинки продвижения (3:2)
const double kPromoRatio = 1.5;

class PromotedTag extends StatelessWidget {
  const PromotedTag({super.key});

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(color: Zc.orange, borderRadius: BorderRadius.circular(20)),
        child: const Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(ZI.bolt, size: 14, color: Colors.white),
          SizedBox(width: 3),
          Text('Promoted', style: TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w600)),
        ]),
      );
}

/// Ряд «Featured» на главной: продвигаемые объявления листаются вбок
class FeaturedRow extends StatefulWidget {
  const FeaturedRow({super.key, required this.city});
  final String city;

  @override
  State<FeaturedRow> createState() => _FeaturedRowState();
}

class _FeaturedRowState extends State<FeaturedRow> {
  late final Future<List<(Campaign, Property)>> _future =
      context.read<AppState>().repo.liveCampaigns('home_featured', filters: SearchFilters(city: widget.city));

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<(Campaign, Property)>>(
      future: _future,
      builder: (context, snap) {
        final list = (snap.data ?? const <(Campaign, Property)>[]).take(8).toList();
        if (list.isEmpty) return const SizedBox.shrink();
        final w = isDesktop(context) ? 340.0 : MediaQuery.sizeOf(context).width * 0.8;
        return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const SizedBox(height: 18),
          const SectionHeader('Featured'),
          SizedBox(
            height: w / kPromoRatio + 190,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 18),
              itemCount: list.length,
              separatorBuilder: (_, __) => const SizedBox(width: 12),
              itemBuilder: (_, i) => SizedBox(
                width: w,
                child: PromotedCard(campaign: list[i].$1, property: list[i].$2),
              ),
            ),
          ),
        ]);
      },
    );
  }
}
