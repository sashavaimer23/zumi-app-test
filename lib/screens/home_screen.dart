import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/models.dart';
import '../state/app_state.dart';
import '../theme.dart';
import '../widgets/ads.dart';
import '../widgets/common.dart';
import '../widgets/onboarding.dart';
import '../widgets/promo_card.dart';
import '../widgets/results.dart';
import '../widgets/wide_card.dart';
import 'neighborhoods_screen.dart';
import 'search_screen.dart';
import 'shell.dart';
import '../widgets/zicons.dart';

/// Главная: hero «Explore Homes in Zambia», категории, районы, недавние, популярные, лента.
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  SearchFilters _filters = SearchFilters();
  Future<int>? _countFuture;
  Future<List<dynamic>>? _sectionsFuture; // районы, счётчики районов, популярное
  int _loadedVersion = -1;
  int _token = 0; // меняется при каждой перезагрузке — список начинает заново

  void _reload() {
    final app = context.read<AppState>();
    _token++;
    _countFuture = app.repo.countListings(_filters);
    _sectionsFuture = Future.wait<dynamic>([
      app.areas(),
      app.repo.areaCounts(),
      app.repo.popular(city: _filters.city),
    ]);
  }

  bool get _isPlainHome => _filters.propertyType == null && _filters.activeCount == 0;

  @override
  Widget build(BuildContext context) {
    final version = context.select<AppState, int>((s) => s.dataVersion);
    if (version != _loadedVersion) {
      _loadedVersion = version;
      _reload();
    }

    return Scaffold(
      floatingActionButton: Padding(
        padding: const EdgeInsets.only(bottom: Shell.navSpace - 16),
        child: KeyedSubtree(key: TourKeys.map, child: MapFab(filters: _filters)),
      ),
      body: RefreshIndicator(
        color: Zc.orange,
        onRefresh: () async {
          setState(_reload);
          await _countFuture;
        },
        child: CustomScrollView(
          controller: TourKeys.homeScroll,
          slivers: [
            SliverToBoxAdapter(child: _Hero(city: _filters.city, onSearch: _openSearch)),
            SliverToBoxAdapter(
              child: Transform.translate(
                offset: const Offset(0, -22),
                child: Container(
                  decoration: const BoxDecoration(
                    color: Zc.bg,
                    borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
                  ),
                  padding: const EdgeInsets.only(top: 44),
                  child: CategoryChips(
                    selected: _filters.propertyType,
                    onChanged: (t) => setState(() {
                      _filters = _filters.copy()..propertyType = t;
                      _reload();
                    }),
                  ),
                ),
              ),
            ),
            // напоминание автору: «ещё доступно?» (то же число — на значке «Профиль»)
            if (context.watch<AppState>().listingsToConfirm > 0)
              SliverToBoxAdapter(
                child: Padding(
                  padding: EdgeInsets.fromLTRB(isDesktop(context) ? desktopSide(context) : 16, 0,
                      isDesktop(context) ? desktopSide(context) : 16, 16),
                  child: Material(
                    color: Zc.orangeSoft,
                    borderRadius: BorderRadius.circular(14),
                    child: InkWell(
                      borderRadius: BorderRadius.circular(14),
                      onTap: () => Shell.of(context)?.go(4),
                      child: Padding(
                        padding: const EdgeInsets.all(14),
                        child: Row(children: [
                          const Icon(ZI.clock, color: Zc.orange),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              context.watch<AppState>().listingsToConfirm == 1
                                  ? 'Is your listing still available? Tap to answer — it takes one tap.'
                                  : '${context.watch<AppState>().listingsToConfirm} listings: are they still available? '
                                      'Tap to answer.',
                              style: const TextStyle(fontSize: 14, height: 1.35),
                            ),
                          ),
                          const Icon(ZI.caretRight, color: Zc.orange),
                        ]),
                      ),
                    ),
                  ),
                ),
              ),
            // реклама: большой баннер вверху главной
            if (_isPlainHome)
              SliverToBoxAdapter(
                child: Padding(
                  padding: EdgeInsets.fromLTRB(isDesktop(context) ? desktopSide(context) : 16, 0,
                      isDesktop(context) ? desktopSide(context) : 16, 8),
                  child: HomeHeroAds(key: ValueKey('ads$_token')),
                ),
              ),
            if (_isPlainHome) ..._sections(),
            ..._results(),
            const SliverToBoxAdapter(child: SizedBox(height: Shell.navSpace + 70)),
          ],
        ),
      ),
    );
  }

  void _openSearch(String query) {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => SearchScreen(initial: _filters.copy()..query = query)),
    );
  }

  // --------------------- блоки главной ---------------------
  List<Widget> _sections() {
    return [
      SliverToBoxAdapter(
        child: FutureBuilder<List<dynamic>>(
          future: _sectionsFuture,
          builder: (context, snap) {
            if (!snap.hasData) return const SizedBox(height: 8);
            final areas = snap.data![0] as List<Area>;
            final counts = snap.data![1] as Map<int, int>;
            final mostViewed = snap.data![2] as List<Property>;
            // популярные районы: сначала с фото, затем по количеству объявлений
            final popular = [...areas]..sort((a, b) {
                final ai = a.imageUrl != null ? 1 : 0, bi = b.imageUrl != null ? 1 : 0;
                if (ai != bi) return bi - ai;
                return (counts[b.id] ?? 0) - (counts[a.id] ?? 0);
              });

            return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              FeaturedRow(key: ValueKey('featured$_token'), city: _filters.city),
              const SizedBox(height: 6),
              SectionHeader('Popular neighbourhoods', onSeeAll: () {
                Navigator.push(context, MaterialPageRoute(builder: (_) => const NeighborhoodsScreen()));
              }),
              SizedBox(
                height: 190,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  itemCount: popular.take(8).length,
                  separatorBuilder: (_, __) => const SizedBox(width: 8),
                  itemBuilder: (_, i) => NeighborhoodCard(
                    area: popular[i],
                    count: counts[popular[i].id] ?? 0,
                    onTap: () => _openArea(popular[i]),
                  ),
                ),
              ),
              _RecentlyViewed(onOpen: (p) => openProperty(context, p)),
              const SizedBox(height: 16),
              const SectionHeader('Popular on Zumi'),
              SizedBox(
                height: 215,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: 18),
                  itemCount: mostViewed.length,
                  separatorBuilder: (_, __) => const SizedBox(width: 8),
                  itemBuilder: (_, i) => PropertySmallCard(p: mostViewed[i], onTap: () => openProperty(context, mostViewed[i])),
                ),
              ),
              const SizedBox(height: 28),
            ]);
          },
        ),
      ),
    ];
  }

  void _openArea(Area a) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => SearchScreen(initial: SearchFilters(city: a.city, areaId: a.id), title: a.name),
      ),
    );
  }

  // --------------------- лента результатов ---------------------
  List<Widget> _results() {
    return [
      SliverToBoxAdapter(
        child: FutureBuilder<int>(
          future: _countFuture,
          builder: (context, snap) {
            final n = snap.data;
            return ResultsHeader(
              label: n == null ? 'Loading…' : countLabel(n, _filters.propertyType),
              filters: _filters,
              onChanged: (f) => setState(() {
                _filters = f;
                _reload();
              }),
            );
          },
        ),
      ),
      ResultsSliver(key: ValueKey('home$_token'), filters: _filters),
    ];
  }
}

// ======================================================================
// Hero-блок
// ======================================================================
class _Hero extends StatefulWidget {
  const _Hero({required this.city, required this.onSearch});
  final String city;
  final ValueChanged<String> onSearch;

  @override
  State<_Hero> createState() => _HeroState();
}

class _HeroState extends State<_Hero> {
  final _ctrl = TextEditingController();

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final top = MediaQuery.paddingOf(context).top;
    final desk = isDesktop(context);
    final side = desk ? desktopSide(context) : 22.0;
    final screenW = MediaQuery.sizeOf(context).width;
    final titleSize = desk ? 60.0 : 44.0;

    return SizedBox(
      height: desk ? 460 : 380 + top,
      child: Stack(fit: StackFit.expand, children: [
        // обложка: на телефоне сдвигаем кадр вправо, чтобы был виден дом
        Image.asset(
          'assets/images/hero.jpg',
          fit: BoxFit.cover,
          alignment: desk ? const Alignment(0.2, 0.1) : const Alignment(0.62, 0),
          filterQuality: FilterQuality.high,
        ),
        // светлый градиент под текстом, чтобы он читался
        DecoratedBox(
          decoration: BoxDecoration(
            gradient: desk
                ? const LinearGradient(
                    begin: Alignment.centerLeft,
                    end: Alignment.centerRight,
                    colors: [Color(0xF2FFF8F1), Color(0xD9FFF8F1), Color(0x66FFF8F1), Color(0x00FFF8F1)],
                    stops: [0.0, 0.30, 0.50, 0.68],
                  )
                : const LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [Color(0xF2FFF8F1), Color(0xCCFFF8F1), Color(0x40FFF8F1), Color(0x1AFFF8F1)],
                    stops: [0.0, 0.42, 0.68, 1.0],
                  ),
          ),
        ),
        Padding(
          padding: EdgeInsets.fromLTRB(side, desk ? 64 : top + 14, side, 0),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            // на компьютере логотип и «Post» уже есть в шапке сайта
            if (!desk) Row(children: [
              const ZLogo(size: 40),
              const Spacer(),
              // подать объявление
              GestureDetector(
                key: TourKeys.post,
                onTap: () => Shell.of(context)?.go(2),
                child: Container(
                  padding: const EdgeInsets.fromLTRB(10, 8, 14, 8),
                  decoration: BoxDecoration(
                    color: const Color(0xE6FFFFFF),
                    borderRadius: BorderRadius.circular(22),
                  ),
                  child: const Row(children: [
                    Icon(ZI.plusCircle, color: Zc.orange, size: 22),
                    SizedBox(width: 6),
                    Text('Post', style: TextStyle(color: Zc.orange, fontSize: 15)),
                  ]),
                ),
              ),
            ]),
            SizedBox(height: desk ? 0 : 22),
            Text('Explore homes', style: zHeadline(context, size: titleSize).copyWith(fontWeight: FontWeight.w600)),
            Text('in Zambia',
                style: zHeadline(context, size: titleSize).copyWith(color: Zc.orange, fontWeight: FontWeight.w600)),
            const SizedBox(height: 12),
            Text('Beautiful homes. Great communities.\nA brighter tomorrow.',
                style: TextStyle(fontSize: desk ? 17 : 14, color: const Color(0xFF5E5E5E), height: 1.35)),
          ]),
        ),
        Positioned(
          left: desk ? side : 16,
          right: desk ? (screenW - side - 760).clamp(side, double.infinity) : 16,
          bottom: desk ? 70 : 48,
          child: Container(
            key: TourKeys.search,
            height: 62,
            padding: const EdgeInsets.only(left: 18, right: 6),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(31),
              boxShadow: const [BoxShadow(color: Zc.shadow, blurRadius: 18, offset: Offset(0, 6))],
            ),
            child: Row(children: [
              const Icon(ZI.pinFill, color: Zc.orange),
              const SizedBox(width: 8),
              Text(widget.city, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15)),
              Container(width: 1, height: 28, margin: const EdgeInsets.symmetric(horizontal: 14), color: Zc.lightGrey),
              Expanded(
                child: TextField(
                  controller: _ctrl,
                  textInputAction: TextInputAction.search,
                  onSubmitted: widget.onSearch,
                  decoration: const InputDecoration(
                    hintText: 'Search neighbourhoods…',
                    filled: false,
                    border: InputBorder.none,
                    enabledBorder: InputBorder.none,
                    focusedBorder: InputBorder.none,
                    contentPadding: EdgeInsets.zero,
                    isDense: true,
                  ),
                ),
              ),
              GestureDetector(
                onTap: () => widget.onSearch(_ctrl.text),
                child: Container(
                  width: 50,
                  height: 50,
                  decoration: const BoxDecoration(color: Zc.orange, shape: BoxShape.circle),
                  child: const Icon(ZI.caretRight, color: Colors.white, size: 32),
                ),
              ),
            ]),
          ),
        ),
      ]),
    );
  }
}

// ======================================================================
// Недавно просмотренные
// ======================================================================
class _RecentlyViewed extends StatefulWidget {
  const _RecentlyViewed({required this.onOpen});
  final ValueChanged<Property> onOpen;

  @override
  State<_RecentlyViewed> createState() => _RecentlyViewedState();
}

class _RecentlyViewedState extends State<_RecentlyViewed> {
  String _key = '';
  Future<List<Property>>? _future;

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final key = app.recentlyViewed.join(',');
    if (key != _key || _future == null) {
      _key = key;
      _future = app.repo.byIds(app.recentlyViewed);
    }
    return FutureBuilder<List<Property>>(
      future: _future,
      builder: (context, snap) {
        final list = snap.data ?? const <Property>[];
        if (list.isEmpty) return const SizedBox.shrink();
        return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const SizedBox(height: 28),
          const SectionHeader('Recently viewed'),
          SizedBox(
            height: 215,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 18),
              itemCount: list.length,
              separatorBuilder: (_, __) => const SizedBox(width: 8),
              itemBuilder: (_, i) => PropertySmallCard(p: list[i], onTap: () => widget.onOpen(list[i])),
            ),
          ),
        ]);
      },
    );
  }
}

// ======================================================================
// Карточка района
// ======================================================================
class NeighborhoodCard extends StatelessWidget {
  const NeighborhoodCard({super.key, required this.area, required this.count, required this.onTap, this.width = 120});
  final Area area;
  final int count;
  final VoidCallback onTap;
  final double width;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: SizedBox(
        width: width,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(10),
          child: Stack(fit: StackFit.expand, children: [
            area.imageUrl != null
                ? PropImage(area.imageUrl)
                : const ColoredBox(color: Zc.green, child: Icon(ZI.apartment, color: Zc.greenTint, size: 80)),
            const DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [Color(0x00000000), Color(0xCC0B4F44)],
                  stops: [0.35, 1.0],
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  Text(area.name,
                      style: const TextStyle(color: Colors.white, fontSize: 17, fontWeight: FontWeight.w600)),
                  if (area.tagline != null)
                    Text(area.tagline!,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(color: Colors.white, fontSize: 10, height: 1.2)),
                  const SizedBox(height: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
                    decoration: BoxDecoration(color: const Color(0x55FFFFFF), borderRadius: BorderRadius.circular(12)),
                    child: Text('$count homes', style: const TextStyle(color: Colors.white, fontSize: 10)),
                  ),
                ],
              ),
            ),
          ]),
        ),
      ),
    );
  }
}
