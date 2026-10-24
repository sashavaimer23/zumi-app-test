import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../models/models.dart';
import '../state/app_state.dart';
import '../theme.dart';
import 'common.dart';

// ======================================================================
// Реклама в приложении: большой баннер на главной (3:1), тонкая полоска
// в ленте (6:1, не чаще одной на 8 карточек) и блок на странице объявления (2:1).
// На каждом баннере — пометка «Sponsored». Пока место не продано —
// показывается готовый макет-образец. Размещает рекламу только команда Zumi.
// ======================================================================

/// Объявления о рекламе на 5 минут — чтобы не спрашивать сервер на каждой карточке
class AdCache {
  static final Map<String, (DateTime, Future<List<Ad>>)> _cache = {};

  static Future<List<Ad>> of(BuildContext context, String placement) {
    final hit = _cache[placement];
    if (hit != null && DateTime.now().difference(hit.$1).inMinutes < 5) return hit.$2;
    final f = context.read<AppState>().repo.liveAds(placement);
    _cache[placement] = (DateTime.now(), f);
    return f;
  }

  static void clear() => _cache.clear();
}

final Set<String> _seenAds = {};

void _logView(BuildContext context, Ad ad) {
  if (_seenAds.add(ad.id)) context.read<AppState>().repo.logAdEvent(ad.id, 'view');
}

Future<void> _openAd(BuildContext context, Ad ad) async {
  context.read<AppState>().repo.logAdEvent(ad.id, 'click');
  final t = ad.target.trim();
  final Uri uri = switch (ad.targetType) {
    'phone' => Uri(scheme: 'tel', path: t.replaceAll(RegExp(r'[^0-9+]'), '')),
    'whatsapp' => Uri.parse('https://wa.me/${t.replaceAll(RegExp(r'[^0-9]'), '')}'),
    _ => Uri.parse(t.startsWith('http') ? t : 'https://$t'),
  };
  await launchUrl(uri, mode: LaunchMode.externalApplication);
}

class SponsoredTag extends StatelessWidget {
  const SponsoredTag({super.key, this.small = false});
  final bool small;

  @override
  Widget build(BuildContext context) => Container(
        padding: EdgeInsets.symmetric(horizontal: small ? 6 : 8, vertical: small ? 2 : 3),
        decoration: BoxDecoration(color: const Color(0xCC000000), borderRadius: BorderRadius.circular(6)),
        child: Text('Sponsored',
            style: TextStyle(color: Colors.white, fontSize: small ? 10 : 11, fontWeight: FontWeight.w600)),
      );
}

/// Сам баннер: картинка + «Sponsored». preview = true — в мастере (ничего не считается)
class AdBanner extends StatelessWidget {
  const AdBanner({super.key, required this.ad, this.imageBytes, this.preview = false, this.radius = 14});
  final Ad ad;
  final Uint8List? imageBytes; // при предпросмотре в мастере
  final bool preview;
  final double radius;

  @override
  Widget build(BuildContext context) {
    if (!preview) _logView(context, ad);
    final small = ad.placement == 'feed_strip';
    return GestureDetector(
      onTap: preview ? null : () => _openAd(context, ad),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(radius),
        child: AspectRatio(
          aspectRatio: ad.place.ratio,
          child: Stack(fit: StackFit.expand, children: [
            imageBytes != null
                ? Image.memory(imageBytes!, fit: BoxFit.cover)
                : (ad.imageUrl != null
                    ? PropImage(ad.imageUrl)
                    : ColoredBox(
                        color: Zc.green,
                        child: Center(
                          child: Text(ad.title,
                              style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w600)),
                        ),
                      )),
            Positioned(top: small ? 6 : 10, left: small ? 6 : 10, child: SponsoredTag(small: small)),
          ]),
        ),
      ),
    );
  }
}

/// Пока место не занято — готовый рекламный макет (образец).
/// Рекламу размещает только команда Zumi по договору, через панель команды → Ads.
/// Команда видит на образце пометку «Sample», остальные — обычный баннер.
class AdPlaceholder extends StatelessWidget {
  const AdPlaceholder({super.key, required this.placement, this.radius = 14});
  final String placement;
  final double radius;

  @override
  Widget build(BuildContext context) {
    final place = adPlacements[placement]!;
    final strip = placement == 'feed_strip';
    final block = placement == 'listing_block';
    final team = context.select<AppState, bool>((a) => a.user?.isAdmin ?? false);
    return GestureDetector(
      onTap: team ? () => showSnack(context, 'Sample ad. Add a real one in the team panel → Ads.') : null,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(radius),
        child: AspectRatio(
          aspectRatio: place.ratio,
          child: Stack(fit: StackFit.expand, children: [
            Image.asset(strip ? 'assets/images/p5.jpg' : 'assets/images/p3.jpg', fit: BoxFit.cover),
            const DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.centerLeft,
                  end: Alignment.centerRight,
                  colors: [Color(0xF2163E35), Color(0xB3163E35), Color(0x10163E35)],
                  stops: [0, 0.55, 1],
                ),
              ),
            ),
            Padding(
              padding: EdgeInsets.fromLTRB(strip ? 14 : 22, strip ? 6 : 16, strip ? 14 : 22, strip ? 6 : 16),
              child: Row(children: [
                Expanded(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: strip
                        ? const [
                            Text('Kafue Living · Furniture for your new home',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w700)),
                            Text('20% off sofas & beds this month',
                                maxLines: 1, style: TextStyle(color: Color(0xE6FFFFFF), fontSize: 12)),
                          ]
                        : [
                            const Text('KAFUE LIVING',
                                style: TextStyle(
                                    color: Color(0xFFF4B88E), fontSize: 12, letterSpacing: 2, fontWeight: FontWeight.w700)),
                            const SizedBox(height: 6),
                            Text(block ? 'Furnish your new home' : 'Moving in? Furnish your new home for less',
                                maxLines: 2,
                                style: TextStyle(
                                    color: Colors.white, fontSize: block ? 20 : 26, fontWeight: FontWeight.w700, height: 1.15)),
                            const SizedBox(height: 6),
                            const Text('20% off sofas, beds and dining sets · Free delivery in Lusaka',
                                maxLines: 2, style: TextStyle(color: Color(0xE6FFFFFF), fontSize: 13)),
                          ],
                  ),
                ),
                const SizedBox(width: 10),
                Container(
                  padding: EdgeInsets.symmetric(horizontal: strip ? 10 : 16, vertical: strip ? 5 : 10),
                  decoration: BoxDecoration(color: Zc.orange, borderRadius: BorderRadius.circular(20)),
                  child: Text('Shop now',
                      style: TextStyle(color: Colors.white, fontSize: strip ? 12 : 14, fontWeight: FontWeight.w600)),
                ),
              ]),
            ),
            Positioned(top: strip ? 6 : 10, right: strip ? 6 : 10, child: SponsoredTag(small: strip)),
            if (team)
              Positioned(
                bottom: strip ? 4 : 10,
                right: strip ? 6 : 10,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(color: const Color(0xCCFFFFFF), borderRadius: BorderRadius.circular(6)),
                  child: const Text('Sample', style: TextStyle(fontSize: 10, color: Zc.green, fontWeight: FontWeight.w700)),
                ),
              ),
          ]),
        ),
      ),
    );
  }
}

/// Главная: большой баннер вверху. Несколько кампаний листаются сами.
class HomeHeroAds extends StatefulWidget {
  const HomeHeroAds({super.key});

  @override
  State<HomeHeroAds> createState() => _HomeHeroAdsState();
}

class _HomeHeroAdsState extends State<HomeHeroAds> {
  late final Future<List<Ad>> _future = AdCache.of(context, 'home_hero');
  final _page = PageController();
  Timer? _timer;
  int _i = 0;

  @override
  void dispose() {
    _timer?.cancel();
    _page.dispose();
    super.dispose();
  }

  void _auto(int n) {
    if (_timer != null || n < 2) return;
    _timer = Timer.periodic(const Duration(seconds: 5), (_) {
      if (!mounted || !_page.hasClients) return;
      _page.animateToPage((_i + 1) % n, duration: const Duration(milliseconds: 450), curve: Curves.easeOut);
    });
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<Ad>>(
      future: _future,
      builder: (context, snap) {
        if (snap.connectionState != ConnectionState.done) return const SizedBox.shrink();
        final ads = snap.data ?? const <Ad>[];
        if (ads.isEmpty) return const _HeroBox(child: AdPlaceholder(placement: 'home_hero'));
        _auto(ads.length);
        return _HeroBox(child: Column(children: [
          AspectRatio(
            aspectRatio: 3,
            child: PageView.builder(
              controller: _page,
              itemCount: ads.length,
              onPageChanged: (i) => setState(() => _i = i),
              itemBuilder: (_, i) => Padding(
                padding: const EdgeInsets.symmetric(horizontal: 2),
                child: AdBanner(ad: ads[i]),
              ),
            ),
          ),
          if (ads.length > 1)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                for (var i = 0; i < ads.length; i++)
                  AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    margin: const EdgeInsets.symmetric(horizontal: 3),
                    width: i == _i ? 16 : 6,
                    height: 6,
                    decoration: BoxDecoration(
                      color: i == _i ? Zc.orange : Zc.lightGrey,
                      borderRadius: BorderRadius.circular(3),
                    ),
                  ),
              ]),
            ),
        ]));
      },
    );
  }
}

/// На компьютере баннер не растягивается во всю ширину — иначе он слишком высокий
class _HeroBox extends StatelessWidget {
  const _HeroBox({required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) => Align(
        alignment: Alignment.centerLeft,
        child: ConstrainedBox(constraints: const BoxConstraints(maxWidth: 960), child: child),
      );
}

/// Лента: тонкая полоска между объявлениями. slot — номер полоски (0, 1, 2…) для ротации.
class FeedStripAd extends StatelessWidget {
  const FeedStripAd({super.key, required this.slot});
  final int slot;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 24),
      child: FutureBuilder<List<Ad>>(
        future: AdCache.of(context, 'feed_strip'),
        builder: (context, snap) {
          if (snap.connectionState != ConnectionState.done) return const SizedBox.shrink();
          final ads = snap.data ?? const <Ad>[];
          if (ads.isEmpty) return const AdPlaceholder(placement: 'feed_strip', radius: 12);
          return AdBanner(ad: ads[slot % ads.length], radius: 12);
        },
      ),
    );
  }
}

/// Страница объявления: блок под описанием
class ListingAdBlock extends StatelessWidget {
  const ListingAdBlock({super.key});

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<Ad>>(
      future: AdCache.of(context, 'listing_block'),
      builder: (context, snap) {
        if (snap.connectionState != ConnectionState.done) return const SizedBox.shrink();
        final ads = snap.data ?? const <Ad>[];
        return ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 640),
          child: ads.isEmpty ? const AdPlaceholder(placement: 'listing_block') : AdBanner(ad: ads.first),
        );
      },
    );
  }
}
