import 'package:flutter/material.dart';

import '../models/models.dart';
import '../theme.dart';
import 'common.dart';
import 'contact.dart';
import 'trust.dart';
import 'zicons.dart';

/// С какой ширины экрана включается «компьютерная» раскладка
const double kDesktopWidth = 900;

bool isDesktop(BuildContext context) => MediaQuery.sizeOf(context).width >= kDesktopWidth;

/// Ширина контента на компьютере (как у крупных порталов) и боковой отступ
const double kContentMaxWidth = 1320;

double desktopSide(BuildContext context) {
  final w = MediaQuery.sizeOf(context).width;
  return ((w - kContentMaxWidth) / 2).clamp(32.0, double.infinity);
}

/// Карточка объявления для компьютера: фото + миниатюры слева, информация и контакты справа.
class PropertyWideCard extends StatelessWidget {
  const PropertyWideCard({super.key, required this.p, required this.onTap});
  final Property p;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 18),
      child: Material(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: Zc.lightGrey),
            ),
            child: IntrinsicHeight(
              child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                SizedBox(width: 400, child: _Gallery(p: p)),
                Expanded(child: _Info(p: p)),
              ]),
            ),
          ),
        ),
      ),
    );
  }
}

class _Gallery extends StatelessWidget {
  const _Gallery({required this.p});
  final Property p;

  @override
  Widget build(BuildContext context) {
    final thumbs = [for (var i = 1; i < p.images.length; i++) p.thumbAt(i)!];
    final shown = thumbs.take(4).toList();
    final more = thumbs.length - shown.length;

    return Column(children: [
      AspectRatio(
        aspectRatio: 1.45,
        child: Stack(fit: StackFit.expand, children: [
          PropImage(p.coverThumb),
          if (p.isVerified) const Positioned(top: 14, left: 14, child: VerifiedBadge()),
          Positioned(
            right: 14,
            bottom: 14,
            child: FavButton(propertyId: p.id, size: 38),
          ),
          if (p.isPromoted) const Positioned(left: 14, bottom: 14, child: PromotedBadge()),
        ]),
      ),
      if (shown.isNotEmpty)
        Padding(
          padding: const EdgeInsets.only(top: 4),
          child: SizedBox(
            height: 66,
            child: Row(children: [
              for (var i = 0; i < 4; i++) ...[
                if (i > 0) const SizedBox(width: 4),
                Expanded(
                  child: i < shown.length
                      ? Stack(fit: StackFit.expand, children: [
                          PropImage(shown[i]),
                          if (i == shown.length - 1 && more > 0)
                            ColoredBox(
                              color: Zc.scrim,
                              child: Center(
                                child: Text('+$more',
                                    style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w600)),
                              ),
                            ),
                        ])
                      : const ColoredBox(color: Zc.chip),
                ),
              ],
            ]),
          ),
        ),
    ]);
  }
}

class _Info extends StatelessWidget {
  const _Info({required this.p});
  final Property p;

  @override
  Widget build(BuildContext context) {
    final priceNum = formatMoney(p.price, '').trim();
    final period = p.dealType == DealType.rent ? (p.rentPeriod == 'day' ? ' / day' : ' / month') : '';

    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Colors.white, Color(0xFFF7F4EF)],
        ),
      ),
      padding: const EdgeInsets.fromLTRB(22, 18, 22, 16),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        // цена + пометка
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Expanded(
            child: Text.rich(
              TextSpan(children: [
                TextSpan(text: '${p.currency} ', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w500)),
                TextSpan(text: priceNum, style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w700)),
                TextSpan(text: period, style: const TextStyle(fontSize: 14, color: Zc.grey)),
              ]),
              style: const TextStyle(color: Zc.text),
            ),
          ),
          Text(
            p.dealType == DealType.sale ? 'FOR SALE' : 'FOR RENT',
            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Zc.green, letterSpacing: 0.6),
          ),
        ]),
        const SizedBox(height: 10),
        // тип | спальни | санузлы | площадь
        Wrap(crossAxisAlignment: WrapCrossAlignment.center, spacing: 14, runSpacing: 8, children: [
          Text(p.propertyType.label, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
          if (p.bedrooms != null) ...[_sep(), _spec(ZI.bed, '${p.bedrooms}')],
          if (p.bathrooms != null) _spec(ZI.bath, '${p.bathrooms}'),
          if ((p.areaSqm ?? p.plotSqm) != null) ...[
            _sep(),
            Text.rich(TextSpan(children: [
              const TextSpan(text: 'Area: ', style: TextStyle(fontWeight: FontWeight.w600)),
              TextSpan(text: '${(p.areaSqm ?? p.plotSqm)!.round()} m²'),
            ]), style: const TextStyle(fontSize: 15)),
          ],
        ]),
        const SizedBox(height: 10),
        Text(
          p.highlights ?? p.title,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontSize: 16, color: Zc.green),
        ),
        const SizedBox(height: 8),
        Row(children: [
          const Icon(ZI.pin, size: 16, color: Zc.text),
          const SizedBox(width: 6),
          Expanded(
            child: Text(p.locationLine,
                maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 15)),
          ),
        ]),
        const SizedBox(height: 10),
        TrustLine(p: p),
        if (p.unlicensedAgent) ...[const SizedBox(height: 6), const LicenceWarning(compact: true)],
        const Spacer(),
        const Divider(height: 20, color: Zc.lightGrey),
        // автор
        Row(children: [
          CircleAvatar(
            radius: 18,
            backgroundColor: Zc.green,
            child: Text(
              (p.contactName ?? '').isEmpty ? '?' : p.contactName!.characters.first.toUpperCase(),
              style: const TextStyle(color: Colors.white, fontSize: 15),
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Text('Listed by', style: TextStyle(fontSize: 12, color: Zc.grey)),
              Row(children: [
                Flexible(
                  child: Text(p.contactName ?? 'Seller',
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
                ),
                if (p.ownerIdentityVerified) ...[const SizedBox(width: 6), const VerifiedMark()],
              ]),
            ]),
          ),
          if (p.agencyName != null)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
              decoration: BoxDecoration(color: Zc.text, borderRadius: BorderRadius.circular(8)),
              child: Text(p.agencyName!,
                  style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w600)),
            ),
        ]),
        const Divider(height: 20, color: Zc.lightGrey),
        // контакты
        Row(children: [
          _ContactBtn(icon: ZI.chat, label: 'Message', onTap: () => Contact.message(context, p)),
          if (!p.chatOnly && p.hasPhone) ...[
            const SizedBox(width: 10),
            _ContactBtn(icon: ZI.phone, label: 'Show number', onTap: () => Contact.showNumber(context, p)),
            const SizedBox(width: 10),
            _ContactBtn(
              icon: ZI.whatsapp,
              onTap: () => Contact.whatsapp(context, p),
              bg: const Color(0xFFE6F4EA),
              fg: const Color(0xFF1E8E4A),
            ),
          ],
        ]),
      ]),
    );
  }

  Widget _sep() => Container(width: 1, height: 18, color: Zc.lightGrey);

  Widget _spec(IconData i, String t) => Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(i, size: 19, color: Zc.text),
        const SizedBox(width: 5),
        Text(t, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
      ]);
}

class _ContactBtn extends StatelessWidget {
  const _ContactBtn({required this.icon, this.label, required this.onTap, this.bg, this.fg});
  final IconData icon;
  final String? label;
  final VoidCallback onTap;
  final Color? bg;
  final Color? fg;

  @override
  Widget build(BuildContext context) {
    final color = fg ?? Zc.green;
    return Material(
      color: bg ?? const Color(0xFFE9EFEE),
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Padding(
          padding: EdgeInsets.symmetric(horizontal: label == null ? 22 : 16, vertical: 10),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Icon(icon, size: 19, color: color),
            if (label != null) ...[
              const SizedBox(width: 8),
              Text(label!, style: TextStyle(fontSize: 14, fontWeight: FontWeight.w500, color: color)),
            ],
          ]),
        ),
      ),
    );
  }
}
