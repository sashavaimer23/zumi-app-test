import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../features.dart';
import '../models/models.dart';
import '../screens/filters_sheet.dart';
import '../screens/map_screen.dart';
import '../screens/property_screen.dart';
import '../state/app_state.dart';
import '../theme.dart';
import 'ads.dart';
import 'common.dart';
import 'promo_card.dart';
import 'wide_card.dart';
import 'zicons.dart';

/// «230 apartments», «18 listings»
String countLabel(int n, PropertyType? type) {
  final noun = type == null ? (n == 1 ? 'listing' : 'listings') : type.plural;
  return '$n $noun';
}

void openProperty(BuildContext context, Property p) {
  Navigator.push(context, MaterialPageRoute(builder: (_) => PropertyScreen(property: p)));
}

/// Строка «136 houses   [Sort] [Filter]»
class ResultsHeader extends StatelessWidget {
  const ResultsHeader({super.key, required this.label, required this.filters, required this.onChanged});
  final String label;
  final SearchFilters filters;
  final ValueChanged<SearchFilters> onChanged;

  @override
  Widget build(BuildContext context) {
    final active = filters.activeCount;
    final desk = isDesktop(context);
    final side = desk ? desktopSide(context) : 26.0;
    return Padding(
      padding: EdgeInsets.fromLTRB(side, 18, desk ? side : 18, 18),
      child: Row(children: [
        Expanded(child: Text(label, style: const TextStyle(fontSize: 21, color: Zc.text))),
        _OutlineBtn(
          icon: ZI.sort,
          label: 'Sort',
          onTap: () async {
            final s = await showSortSheet(context, filters.sort);
            if (s != null) onChanged(filters.copy()..sort = s);
          },
        ),
        const SizedBox(width: 10),
        _OutlineBtn(
          icon: ZI.filter,
          label: active > 0 ? 'Filter · $active' : 'Filter',
          highlighted: active > 0,
          onTap: () async {
            final f = await showFiltersSheet(context, filters);
            if (f != null) onChanged(f);
          },
        ),
      ]),
    );
  }
}

class _OutlineBtn extends StatelessWidget {
  const _OutlineBtn({required this.icon, required this.label, required this.onTap, this.highlighted = false});
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool highlighted;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 8),
        decoration: BoxDecoration(
          color: highlighted ? Zc.orangeSoft : null,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: highlighted ? Zc.orange : Zc.green, width: 0.8),
        ),
        child: Row(children: [
          Icon(icon, size: 16, color: Zc.green),
          const SizedBox(width: 6),
          Text(label, style: const TextStyle(fontSize: 13, color: Zc.green)),
        ]),
      ),
    );
  }
}

/// Список карточек как sliver (для CustomScrollView).
/// Грузит объявления порциями: следующая порция подгружается, когда долистали до конца.
/// Чтобы начать заново (новые фильтры), родитель меняет key.
class ResultsSliver extends StatefulWidget {
  const ResultsSliver({super.key, required this.filters, this.pageSize = 24});
  final SearchFilters filters;
  final int pageSize;

  @override
  State<ResultsSliver> createState() => _ResultsSliverState();
}

class _ResultsSliverState extends State<ResultsSliver> {
  final List<Property> _items = [];
  List<(Campaign, Property)> _promo = const []; // продвигаемые — первыми в списке
  bool _loading = false;
  bool _end = false;
  Object? _error;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _loadMore();
      context.read<AppState>().repo.liveCampaigns('search_top', filters: widget.filters).then((list) {
        if (mounted) setState(() => _promo = list.take(2).toList());
      });
    });
  }

  Future<void> _loadMore() async {
    if (_loading || _end) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final page = await context
          .read<AppState>()
          .repo
          .search(widget.filters, limit: widget.pageSize, offset: _items.length);
      if (!mounted) return;
      setState(() {
        _items.addAll(page);
        _end = page.length < widget.pageSize;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e;
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_items.isEmpty) {
      if (_error != null) {
        return SliverToBoxAdapter(
          child: EmptyState(
            icon: ZI.offline,
            title: 'Could not load listings',
            subtitle: '$_error',
            action: OutlinedButton(onPressed: _loadMore, child: const Text('Try again')),
          ),
        );
      }
      if (_end) {
        return const SliverToBoxAdapter(
          child: EmptyState(
            icon: ZI.search,
            title: 'Nothing found',
            subtitle: 'Try changing the filters or searching another neighbourhood.',
          ),
        );
      }
      return const SliverToBoxAdapter(
        child: Padding(
          padding: EdgeInsets.all(40),
          child: Center(child: CircularProgressIndicator(color: Zc.orange)),
        ),
      );
    }

    final desk = isDesktop(context);
    final promoIds = {for (final (_, p) in _promo) p.id};
    final items = promoIds.isEmpty ? _items : _items.where((p) => !promoIds.contains(p.id)).toList();
    // лента: продвигаемые первыми, затем объявления; после каждой 8-й карточки — рекламная полоска
    final entries = <Object>[
      for (final pr in _promo) pr,
      for (var k = 0; k < items.length; k++) ...[
        items[k],
        // полоска рекламы — каждые 8 карточек, только если баннеры включены
        if (Features.ads && (k + 1) % 8 == 0 && k != items.length - 1) (k + 1) ~/ 8 - 1,
      ],
    ];
    return SliverPadding(
      padding: EdgeInsets.symmetric(horizontal: desk ? desktopSide(context) : 16),
      sliver: SliverList.builder(
        itemCount: entries.length + 1,
        itemBuilder: (_, i) {
          if (i == entries.length) return _footer();
          final e = entries[i];
          if (e is (Campaign, Property)) return PromotedCard(campaign: e.$1, property: e.$2, wide: desk);
          if (e is int) return FeedStripAd(slot: e);
          final p = e as Property;
          return desk
              ? PropertyWideCard(p: p, onTap: () => openProperty(context, p))
              : PropertyCard(p: p, onTap: () => openProperty(context, p));
        },
      ),
    );
  }

  Widget _footer() {
    if (_end) return const SizedBox(height: 8);
    if (_error != null) {
      return Center(
        child: TextButton(onPressed: _loadMore, child: const Text('Could not load more — try again')),
      );
    }
    // долистали до конца — подгружаем следующую порцию
    if (!_loading) WidgetsBinding.instance.addPostFrameCallback((_) => _loadMore());
    return const Padding(
      padding: EdgeInsets.symmetric(vertical: 24),
      child: Center(
        child: SizedBox(width: 26, height: 26, child: CircularProgressIndicator(strokeWidth: 2.5, color: Zc.orange)),
      ),
    );
  }
}

/// Кнопка «Map» внизу экрана
class MapFab extends StatelessWidget {
  const MapFab({super.key, required this.filters});
  final SearchFilters filters;

  @override
  Widget build(BuildContext context) {
    return FloatingActionButton.extended(
      heroTag: null,
      backgroundColor: Zc.green,
      foregroundColor: Colors.white,
      icon: const Icon(ZI.map),
      label: const Text('Map'),
      onPressed: () => Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => MapScreen(initial: filters.copy())),
      ),
    );
  }
}
