import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../config.dart';
import '../models/models.dart';
import '../screens/auth_screen.dart';
import '../screens/support/support_screen.dart';
import '../state/app_state.dart';
import '../theme.dart';
import 'common.dart';
import 'zicons.dart';

// ======================================================================
// Реклама в приложении: большой баннер на главной (3:1), тонкая полоска
// в ленте (6:1, не чаще одной на 8 карточек) и блок на странице объявления (2:1).
// На каждом баннере — пометка «Sponsored». Пока место не продано —
// честный шаблон «Your ad here» с контактом команды. Размещает рекламу только команда Zumi.
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

/// Пока место не занято — честный шаблон «Здесь может быть ваша реклама».
/// Это не реклама (нет пометки «Sponsored»). По нажатию — как связаться с командой Zumi:
/// рекламу размещает только команда, по договору с рекламодателем.
class AdPlaceholder extends StatelessWidget {
  const AdPlaceholder({super.key, required this.placement, this.radius = 14});
  final String placement;
  final double radius;

  @override
  Widget build(BuildContext context) {
    final place = adPlacements[placement]!;
    final strip = placement == 'feed_strip';
    return GestureDetector(
      onTap: () => showAdvertiseInfo(context),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(radius),
        child: AspectRatio(
          aspectRatio: place.ratio,
          child: Container(
            decoration: const BoxDecoration(
              gradient: LinearGradient(colors: [Color(0xFF245045), Color(0xFF0F5D4E)]),
            ),
            padding: EdgeInsets.symmetric(horizontal: strip ? 14 : 22, vertical: strip ? 6 : 16),
            child: Row(children: [
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Your ad here',
                        maxLines: 1,
                        style: TextStyle(color: Colors.white, fontSize: strip ? 14 : 22, fontWeight: FontWeight.w700)),
                    if (!strip) ...[
                      const SizedBox(height: 4),
                      const Text('Reach people looking for homes in Zambia.',
                          maxLines: 2, style: TextStyle(color: Color(0xCCFFFFFF), fontSize: 13)),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: 10),
              Container(
                padding: EdgeInsets.symmetric(horizontal: strip ? 10 : 14, vertical: strip ? 5 : 9),
                decoration: BoxDecoration(color: Zc.orange, borderRadius: BorderRadius.circular(20)),
                child: Text('Contact Zumi',
                    style: TextStyle(color: Colors.white, fontSize: strip ? 12 : 14, fontWeight: FontWeight.w600)),
              ),
            ]),
          ),
        ),
      ),
    );
  }
}

/// Как разместить рекламу: только через команду Zumi
Future<void> showAdvertiseInfo(BuildContext context) {
  return showModalBottomSheet<void>(
    context: context,
    backgroundColor: Zc.bg,
    shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
    builder: (ctx) => SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(22, 20, 22, 16),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('Advertise on Zumi', style: zHeadline(ctx, size: 26)),
          const SizedBox(height: 8),
          const Text(
            'Banners on Zumi are placed by our team under an agreement with the advertiser. '
            'Write to us — we will reply with prices and free dates.',
            style: TextStyle(color: Zc.grey, height: 1.4),
          ),
          const SizedBox(height: 18),
          if (AppConfig.adsEmail.isNotEmpty) ...[
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                style: FilledButton.styleFrom(backgroundColor: Zc.orange, padding: const EdgeInsets.symmetric(vertical: 14)),
                onPressed: () {
                  Navigator.pop(ctx);
                  launchUrl(Uri(scheme: 'mailto', path: AppConfig.adsEmail, query: 'subject=Advertising on Zumi'));
                },
                icon: const Icon(ZI.envelope),
                label: Text('Email ${AppConfig.adsEmail}'),
              ),
            ),
            const SizedBox(height: 10),
          ],
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              style: OutlinedButton.styleFrom(
                foregroundColor: Zc.green,
                side: const BorderSide(color: Zc.green),
                padding: const EdgeInsets.symmetric(vertical: 14),
              ),
              onPressed: () async {
                Navigator.pop(ctx);
                final app = context.read<AppState>();
                if (!app.signedIn) {
                  final ok = await Navigator.push<bool>(
                    context,
                    MaterialPageRoute(builder: (_) => const AuthScreen(reason: 'Sign in to write to the Zumi team.')),
                  );
                  if (ok != true || !context.mounted) return;
                }
                if (!context.mounted) return;
                Navigator.push(context, MaterialPageRoute(builder: (_) => const SupportScreen()));
              },
              icon: const Icon(ZI.chat),
              label: const Text('Write to the Zumi team'),
            ),
          ),
        ]),
      ),
    ),
  );
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
