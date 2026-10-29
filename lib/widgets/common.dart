import 'dart:math' as math;

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../data/repository.dart';
import '../models/models.dart';
import '../state/app_state.dart';
import '../theme.dart';
import 'trust.dart';
import 'zicons.dart';

// ======================================================================
// Логотип Zumi: зелёная и оранжевая «крыша»
// ======================================================================
class ZLogo extends StatelessWidget {
  const ZLogo({super.key, this.size = 40, this.mono});
  final double size;

  /// Одноцветный вариант (например, кремовый на зелёном фоне)
  final Color? mono;

  @override
  Widget build(BuildContext context) =>
      SizedBox(width: size, height: size * 0.8, child: CustomPaint(painter: _LogoPainter(mono)));
}

/// Финальный логотип из бренд-бука: бирюзовый «лист» слева и коралловая крыша справа.
class _LogoPainter extends CustomPainter {
  _LogoPainter(this.mono);
  final Color? mono;

  @override
  void paint(Canvas canvas, Size s) {
    final (left, right) = zumiLogoPaths(s);
    canvas.drawPath(left, Paint()..color = mono ?? Zc.green);
    canvas.drawPath(right, Paint()..color = mono ?? Zc.orange);
  }

  @override
  bool shouldRepaint(covariant _LogoPainter old) => old.mono != mono;
}

/// Две части логотипа (лист и крыша) в прямоугольнике размера [s]
(Path, Path) zumiLogoPaths(Size s) {
  double x(double v) => v * s.width;
  double y(double v) => v * s.height;

  final left = Path()
    ..moveTo(x(0.37), y(0.13))
    ..lineTo(x(0.37), y(0.78))
    ..quadraticBezierTo(x(0.37), y(1.0), x(0.185), y(1.0))
    ..quadraticBezierTo(x(0.0), y(1.0), x(0.0), y(0.78))
    ..lineTo(x(0.0), y(0.64))
    ..quadraticBezierTo(x(0.0), y(0.53), x(0.08), y(0.44))
    ..close();

  final right = Path()
    ..moveTo(x(0.39), y(0.12))
    ..quadraticBezierTo(x(0.45), y(0.0), x(0.53), y(0.0))
    ..quadraticBezierTo(x(0.59), y(0.0), x(0.64), y(0.06))
    ..lineTo(x(0.97), y(0.47))
    ..quadraticBezierTo(x(1.0), y(0.52), x(1.0), y(0.58))
    ..lineTo(x(1.0), y(0.92))
    ..quadraticBezierTo(x(1.0), y(1.02), x(0.93), y(0.96))
    ..lineTo(x(0.39), y(0.24))
    ..close();
  return (left, right);
}

// ======================================================================
// Фото профиля: картинка или первая буква имени
// ======================================================================
class ZAvatar extends StatelessWidget {
  const ZAvatar({super.key, this.url, this.name, this.size = 48});
  final String? url;
  final String? name;
  final double size;

  @override
  Widget build(BuildContext context) {
    final n = (name ?? '').trim();
    return SizedBox(
      width: size,
      height: size,
      child: ClipOval(
        child: (url ?? '').isNotEmpty
            ? PropImage(url)
            : ColoredBox(
                color: Zc.green,
                child: Center(
                  child: Text(
                    n.isEmpty ? '?' : n.characters.first.toUpperCase(),
                    style: TextStyle(color: Colors.white, fontSize: size * 0.42, fontWeight: FontWeight.w500),
                  ),
                ),
              ),
      ),
    );
  }
}

// ======================================================================
// Картинка объявления: asset:..., mem:... (демо) или https://...
// ======================================================================
class PropImage extends StatelessWidget {
  const PropImage(this.url, {super.key, this.fit = BoxFit.cover, this.radius = 0});
  final String? url;
  final BoxFit fit;
  final double radius;

  @override
  Widget build(BuildContext context) {
    final u = url;
    Widget child;
    if (u == null || u.isEmpty) {
      child = const ColoredBox(
        color: Zc.chip,
        child: Center(child: Icon(ZI.house, color: Zc.grey, size: 40)),
      );
    } else if (u.startsWith('asset:')) {
      child = _sized((w) => Image.asset('assets/images/${u.substring(6)}', fit: fit, cacheWidth: w));
    } else if (u.startsWith('mem:')) {
      final bytes = MemoryImages.get(u);
      child = bytes == null ? const ColoredBox(color: Zc.chip) : Image.memory(bytes, fit: fit);
    } else if (kIsWeb) {
      // На сайте: если браузер не смог расшифровать фото сам (так бывает на iPhone),
      // Flutter показывает его обычным <img> браузера — так фото видно всегда.
      child = _sized((w) => Image.network(
        u,
        fit: fit,
        cacheWidth: w,
        webHtmlElementStrategy: WebHtmlElementStrategy.fallback,
        frameBuilder: (_, img, frame, sync) =>
            (frame == null && !sync) ? const ColoredBox(color: Zc.chip, child: SizedBox.expand()) : img,
        errorBuilder: (ctx, error, _) {
          _reportImageError(ctx, error);
          return const ColoredBox(
            color: Zc.chip,
            child: Center(child: Icon(ZI.brokenImage, color: Zc.grey)),
          );
        },
      ));
    } else {
      child = _sized((w) => CachedNetworkImage(
        imageUrl: u,
        fit: fit,
        memCacheWidth: w,
        placeholder: (_, __) => const ColoredBox(color: Zc.chip),
        errorWidget: (ctx, __, error) {
          _reportImageError(ctx, error);
          return const ColoredBox(
            color: Zc.chip,
            child: Center(child: Icon(ZI.brokenImage, color: Zc.grey)),
          );
        },
      ));
    }
    return ClipRRect(borderRadius: BorderRadius.circular(radius), child: child);
  }

  /// Расшифровывать фото в размере экрана, а не в полном: на дешёвых телефонах меньше памяти и рывков
  Widget _sized(Widget Function(int? width) build) => LayoutBuilder(builder: (context, c) {
        if (!c.hasBoundedWidth || c.maxWidth <= 0) return build(null);
        final dpr = MediaQuery.maybeDevicePixelRatioOf(context) ?? 2;
        // при «cover» широкое фото в высоком окне растягивается по высоте — берём запас (фото ~3:2)
        final h = c.hasBoundedHeight ? c.maxHeight * 1.5 : 0.0;
        final need = (fit == BoxFit.cover ? math.max(c.maxWidth, h) : c.maxWidth) * dpr;
        // шаг 160 px — чтобы при мелких изменениях ширины не расшифровывать фото заново
        final px = ((need / 160).ceil() * 160).clamp(160, 2048);
        return build(px);
      });

  /// Причина, по которой фото не показалось, — в статистику ошибок (раз за сеанс, без адреса фото)
  static final _reported = <String>{};
  static void _reportImageError(BuildContext context, Object error) {
    final text = 'image: ${'$error'.split('\n').first.replaceAll(RegExp(r'https?://\S+'), '[url]')}';
    if (_reported.length >= 5 || !_reported.add(text)) return;
    try {
      context.read<AppState>().repo.logError(text);
    } catch (_) {}
  }
}

// ======================================================================
// Что рядом с жильём
// ======================================================================
IconData nearbyIcon(String key) => switch (key) {
      'shop' => ZI.shoppingCart,
      'school' => ZI.school,
      'hospital' => ZI.hospital,
      _ => ZI.road,
    };

/// Список «Shops — under 1 km» на странице объявления
class NearbyList extends StatelessWidget {
  const NearbyList(this.nearby, {super.key});
  final Map<String, String> nearby;

  @override
  Widget build(BuildContext context) {
    final items = [for (final k in kNearbyPlaces.keys) if (nearby[k] != null) k];
    if (items.isEmpty) return const SizedBox.shrink();
    return Wrap(spacing: 10, runSpacing: 10, children: [
      for (final k in items)
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
          decoration: BoxDecoration(color: Zc.chip, borderRadius: BorderRadius.circular(12)),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Icon(nearbyIcon(k), size: 18, color: Zc.green),
            const SizedBox(width: 8),
            Text(kNearbyPlaces[k]!, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
            Text(' · ${kNearbyDistances[nearby[k]]!.toLowerCase()}',
                style: const TextStyle(color: Zc.grey, fontSize: 14)),
          ]),
        ),
    ]);
  }
}

// ======================================================================
// Кружок с числом непрочитанных: 1…10, дальше «10+»
// ======================================================================
class CountBadge extends StatelessWidget {
  const CountBadge(this.count, {super.key, this.color = Zc.orange, this.textColor = Colors.white, this.border});
  final int count;
  final Color color;
  final Color textColor;
  final Color? border; // обводка, чтобы кружок читался поверх иконки

  @override
  Widget build(BuildContext context) {
    if (count <= 0) return const SizedBox.shrink();
    final text = count > 10 ? '10+' : '$count';
    return Container(
      constraints: const BoxConstraints(minWidth: 20, minHeight: 20),
      padding: const EdgeInsets.symmetric(horizontal: 5),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(10),
        border: border == null ? null : Border.all(color: border!, width: 2),
      ),
      // Align с widthFactor 1: кружок по размеру числа, а не на всю доступную ширину
      child: Align(
        widthFactor: 1,
        heightFactor: 1,
        child: Text(text,
            style: TextStyle(color: textColor, fontSize: 11, fontWeight: FontWeight.w700, height: 1.1)),
      ),
    );
  }
}

// ======================================================================
// Кнопки
// ======================================================================
class PrimaryButton extends StatelessWidget {
  const PrimaryButton({super.key, required this.label, this.onPressed, this.loading = false, this.width = 230});
  final String label;
  final VoidCallback? onPressed;
  final bool loading;
  final double? width;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: width,
      height: 56,
      child: FilledButton(
        style: FilledButton.styleFrom(
          backgroundColor: Zc.orange,
          disabledBackgroundColor: Zc.orangeTint,
          foregroundColor: Colors.white,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
          textStyle: const TextStyle(fontSize: 18, fontWeight: FontWeight.w400, letterSpacing: 0.2),
        ),
        onPressed: loading ? null : onPressed,
        child: loading
            ? const SizedBox(
                width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 2.5, color: Colors.white))
            : Text(label),
      ),
    );
  }
}

class FavButton extends StatelessWidget {
  const FavButton({super.key, required this.propertyId, this.size = 40});
  final String propertyId;
  final double size;

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final fav = app.isFavorite(propertyId);
    return GestureDetector(
      onTap: () => app.toggleFavorite(propertyId),
      child: Container(
        width: size,
        height: size,
        decoration: const BoxDecoration(color: Color(0xCCFFFFFF), shape: BoxShape.circle),
        child: Icon(
          fav ? ZI.heartFill : ZI.heart,
          size: size * 0.55,
          color: fav ? Zc.orange : Zc.green,
        ),
      ),
    );
  }
}

// ======================================================================
// Карточка объявления (большая, как в макете Search / Saved)
// ======================================================================
class PropertyCard extends StatelessWidget {
  const PropertyCard({super.key, required this.p, required this.onTap});
  final Property p;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Padding(
        padding: const EdgeInsets.only(bottom: 28),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            AspectRatio(
              aspectRatio: 1.53,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  PropImage(p.coverThumb, radius: 18),
                  Positioned(top: 12, right: 12, child: FavButton(propertyId: p.id)),
                  if (p.isVerified || p.isPromoted)
                    Positioned(
                      top: 12,
                      left: 12,
                      child: Row(children: [
                        if (p.isVerified) VerifiedBadge(label: p.badgeLabel),
                        if (p.isVerified && p.isPromoted) const SizedBox(width: 6),
                        if (p.isPromoted) const PromotedBadge(),
                      ]),
                    ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 14, 14, 0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(p.priceLabel, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w600, color: Zc.text)),
                  const SizedBox(height: 6),
                  Text(p.title, style: const TextStyle(fontSize: 17, color: Zc.text), maxLines: 1, overflow: TextOverflow.ellipsis),
                  const SizedBox(height: 4),
                  Text(p.specsLine, style: const TextStyle(fontSize: 15, color: Zc.text)),
                  const SizedBox(height: 4),
                  Text(p.locationLine,
                      style: const TextStyle(fontSize: 14, color: Zc.grey), maxLines: 1, overflow: TextOverflow.ellipsis),
                  if (p.unlicensedAgent) ...[const SizedBox(height: 6), const LicenceWarning(compact: true)],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class PromotedBadge extends StatelessWidget {
  const PromotedBadge({super.key});

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(color: Zc.orange, borderRadius: BorderRadius.circular(20)),
        child: const Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(ZI.bolt, size: 14, color: Colors.white),
          SizedBox(width: 2),
          Text('Top', style: TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w600)),
        ]),
      );
}

/// Маленькая карточка (Recently viewed / Popular on Zumi)
class PropertySmallCard extends StatelessWidget {
  const PropertySmallCard({super.key, required this.p, required this.onTap, this.width = 170});
  final Property p;
  final VoidCallback onTap;
  final double width;

  @override
  Widget build(BuildContext context) {
    final type = p.propertyType == PropertyType.house ? 'house' : p.propertyType.label.toLowerCase();
    final sub = p.bedrooms != null ? '${p.bedrooms} bed. $type' : p.propertyType.label;
    return GestureDetector(
      onTap: onTap,
      child: SizedBox(
        width: width,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              height: width * 0.95,
              width: width,
              child: Stack(fit: StackFit.expand, children: [
                PropImage(p.coverThumb, radius: 10),
                Positioned(top: 6, right: 6, child: FavButton(propertyId: p.id, size: 26)),
              ]),
            ),
            const SizedBox(height: 6),
            Text('${p.city ?? 'Lusaka'}, ${p.areaName ?? ''}',
                maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 13, color: Zc.text)),
            Text(sub, style: const TextStyle(fontSize: 13, color: Zc.grey)),
          ],
        ),
      ),
    );
  }
}

// ======================================================================
// Категории (All / Houses / Apartments / Land / Commercial)
// ======================================================================
class CategoryChips extends StatelessWidget {
  const CategoryChips({super.key, required this.selected, required this.onChanged, this.padding});
  final PropertyType? selected;
  final ValueChanged<PropertyType?> onChanged;
  final EdgeInsets? padding;

  static const _items = <(PropertyType?, String, IconData)>[
    (null, 'All', ZI.more),
    (PropertyType.house, 'Houses', ZI.house),
    (PropertyType.apartment, 'Apartments', ZI.apartment),
    (PropertyType.land, 'Land', ZI.land),
    (PropertyType.commercial, 'Commercial', ZI.commercial),
  ];

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 48,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: padding ?? const EdgeInsets.symmetric(horizontal: 14),
        itemCount: _items.length,
        separatorBuilder: (_, __) => const SizedBox(width: 10),
        itemBuilder: (_, i) {
          final (type, label, icon) = _items[i];
          final on = type == selected;
          return GestureDetector(
            onTap: () => onChanged(type),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 180),
              padding: const EdgeInsets.symmetric(horizontal: 18),
              decoration: BoxDecoration(
                color: on ? Zc.orange : Zc.chip,
                borderRadius: BorderRadius.circular(24),
              ),
              child: Row(children: [
                Icon(icon, size: 20, color: on ? Colors.white : Zc.green),
                const SizedBox(width: 8),
                Text(label,
                    style: TextStyle(fontSize: 16, color: on ? Colors.white : Zc.green, fontWeight: FontWeight.w400)),
              ]),
            ),
          );
        },
      ),
    );
  }
}

// ======================================================================
// Плашка-переключатель для фильтров («To rent», «2+», «Garage»)
// ======================================================================
class ZChip extends StatelessWidget {
  const ZChip({super.key, required this.label, required this.selected, required this.onTap});
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 10),
        decoration: BoxDecoration(
          color: selected ? Zc.orangeSoft : Zc.bg,
          borderRadius: BorderRadius.circular(22),
          border: Border.all(color: selected ? Zc.orange : Zc.lightGrey),
        ),
        child: Text(label, style: const TextStyle(fontSize: 14, color: Zc.text)),
      ),
    );
  }
}

/// Оранжевая точка-радиокнопка из макетов
class RadioDot extends StatelessWidget {
  const RadioDot({super.key, required this.selected, this.size = 22});
  final bool selected;
  final double size;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(color: selected ? Zc.orange : Zc.grey, width: selected ? 2 : 1),
        color: Colors.white,
      ),
      padding: const EdgeInsets.all(3),
      child: selected ? const DecoratedBox(decoration: BoxDecoration(color: Zc.orange, shape: BoxShape.circle)) : null,
    );
  }
}

/// Прогресс «Step 1 of 5»
class StepProgress extends StatelessWidget {
  const StepProgress({super.key, required this.step, this.total = 5});
  final int step; // 1..total
  final int total;

  @override
  Widget build(BuildContext context) {
    return Column(children: [
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 36),
        child: Row(
          children: [
            for (var i = 1; i <= total; i++) ...[
              Container(
                width: 18,
                height: 18,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: i <= step ? Zc.orange : Zc.lightGrey,
                ),
              ),
              if (i < total)
                Expanded(child: Container(height: 2, color: i < step ? Zc.orange : Zc.lightGrey)),
            ],
          ],
        ),
      ),
      const SizedBox(height: 14),
      Text('Step $step of $total', style: const TextStyle(fontSize: 17, color: Zc.grey)),
    ]);
  }
}

class SectionHeader extends StatelessWidget {
  const SectionHeader(this.title, {super.key, this.onSeeAll});
  final String title;
  final VoidCallback? onSeeAll;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 0, 16, 12),
      child: Row(children: [
        Expanded(
          child: Text(title, style: const TextStyle(fontSize: 21, fontWeight: FontWeight.w500, color: Zc.green)),
        ),
        if (onSeeAll != null)
          TextButton(
            onPressed: onSeeAll,
            style: TextButton.styleFrom(foregroundColor: Zc.orange),
            child: const Row(children: [
              Text('See all', style: TextStyle(fontSize: 15)),
              SizedBox(width: 8),
              Icon(ZI.forward, size: 18),
            ]),
          ),
      ]),
    );
  }
}

class EmptyState extends StatelessWidget {
  const EmptyState({super.key, required this.icon, required this.title, this.subtitle, this.action});
  final IconData icon;
  final String title;
  final String? subtitle;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Icon(icon, size: 56, color: Zc.lightGrey),
          const SizedBox(height: 16),
          Text(title,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w600, color: Zc.green)),
          if (subtitle != null) ...[
            const SizedBox(height: 8),
            Text(subtitle!, textAlign: TextAlign.center, style: const TextStyle(color: Zc.grey, fontSize: 15)),
          ],
          if (action != null) ...[const SizedBox(height: 20), action!],
        ]),
      ),
    );
  }
}

void showSnack(BuildContext context, String message) {
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(message)));
}
