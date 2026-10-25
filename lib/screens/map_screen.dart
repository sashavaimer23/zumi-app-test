import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:provider/provider.dart';

import '../config.dart';
import '../models/models.dart';
import '../state/app_state.dart';
import '../theme.dart';
import '../widgets/common.dart';
import '../widgets/onboarding.dart';
import '../widgets/results.dart';
import 'filters_sheet.dart';
import '../widgets/zicons.dart';

/// Карта: районы (круги с количеством объявлений) и сами объекты (метки с ценой).
/// При отдалении видны районы, при приближении — отдельные объекты.
class MapScreen extends StatefulWidget {
  const MapScreen({super.key, required this.initial});
  final SearchFilters initial;

  @override
  State<MapScreen> createState() => _MapScreenState();
}

class _MapScreenState extends State<MapScreen> {
  late SearchFilters _filters = widget.initial;
  final _map = MapController();
  List<Property> _props = [];
  List<Area> _areas = [];
  bool _loading = true;
  double _zoom = 12.3;
  Property? _selected;

  static const _detailZoom = 13.2; // с этого зума показываем отдельные объекты

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final app = context.read<AppState>();
    try {
      final res = await Future.wait<dynamic>([app.repo.search(_filters, limit: 500), app.areas()]);
      if (!mounted) return;
      setState(() {
        _props = res[0] as List<Property>;
        _areas = res[1] as List<Area>;
        _loading = false;
        _selected = null;
      });
      // если выбран район — показываем его крупно
      final areaId = _filters.areaId;
      if (areaId != null) {
        for (final a in _areas) {
          if (a.id == areaId) _map.move(LatLng(a.lat, a.lng), _detailZoom + 0.6);
        }
      }
    } catch (e) {
      if (!mounted) return;
      setState(() => _loading = false);
      showSnack(context, 'Could not load the map: $e');
    }
  }

  Map<int, int> get _countByArea {
    final m = <int, int>{};
    for (final p in _props) {
      if (p.areaId != null) m[p.areaId!] = (m[p.areaId!] ?? 0) + 1;
    }
    return m;
  }

  @override
  Widget build(BuildContext context) {
    final counts = _countByArea;
    final showProps = _zoom >= _detailZoom;
    final areasWithListings = _areas.where((a) => (counts[a.id] ?? 0) > 0).toList();

    return Scaffold(
      body: Stack(children: [
        FlutterMap(
          mapController: _map,
          options: MapOptions(
            initialCenter: _initialCenter(),
            initialZoom: _zoom,
            minZoom: 9,
            maxZoom: 18,
            onTap: (_, __) => setState(() => _selected = null),
            onPositionChanged: (camera, _) {
              if ((camera.zoom >= _detailZoom) != (_zoom >= _detailZoom)) {
                setState(() => _zoom = camera.zoom);
              } else {
                _zoom = camera.zoom;
              }
            },
          ),
          children: [
            TileLayer(
              urlTemplate: AppConfig.mapTilesUrl,
              userAgentPackageName: AppConfig.mapUserAgent,
            ),
            // районы — полупрозрачные круги
            CircleLayer(circles: [
              for (final a in areasWithListings)
                CircleMarker(
                  point: LatLng(a.lat, a.lng),
                  radius: 900,
                  useRadiusInMeter: true,
                  color: showProps ? const Color(0x110B4F44) : const Color(0x330B4F44),
                  borderColor: Zc.green,
                  borderStrokeWidth: 1,
                ),
            ]),
            MarkerLayer(markers: [
              if (!showProps)
                for (final a in areasWithListings)
                  Marker(
                    point: LatLng(a.lat, a.lng),
                    width: 130,
                    height: 44,
                    child: GestureDetector(
                      onTap: () => _map.move(LatLng(a.lat, a.lng), _detailZoom + 0.6),
                      child: _AreaBubble(name: a.name, count: counts[a.id] ?? 0),
                    ),
                  ),
              if (showProps)
                for (final p in _props)
                  Marker(
                    point: LatLng(p.lat, p.lng),
                    width: 84,
                    height: 34,
                    child: GestureDetector(
                      onTap: () => setState(() => _selected = p),
                      child: _PricePin(p: p, selected: _selected?.id == p.id),
                    ),
                  ),
            ]),
            RichAttributionWidget(attributions: [TextSourceAttribution(AppConfig.mapAttribution)]),
          ],
        ),

        // верхняя панель
        SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Row(children: [
              _RoundBtn(icon: ZI.back, onTap: () => Navigator.pop(context)),
              const SizedBox(width: 10),
              Expanded(
                child: Container(
                  height: 48,
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(24),
                    boxShadow: const [BoxShadow(color: Zc.shadow, blurRadius: 10)],
                  ),
                  alignment: Alignment.centerLeft,
                  child: Text(
                    _loading ? 'Loading…' : '${countLabel(_props.length, _filters.propertyType)} in ${_filters.city}',
                    style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w500),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              _RoundBtn(
                icon: ZI.filter,
                badge: _filters.activeCount,
                onTap: () async {
                  final f = await showFiltersSheet(context, _filters);
                  if (f != null) {
                    _filters = f;
                    _load();
                  }
                },
              ),
            ]),
          ),
        ),

        // подсказка при первом заходе на карту
        SafeArea(
          child: Align(
            alignment: Alignment.topCenter,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 70, 12, 0),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 420),
                child: const HintCard(
                  id: 'hint_map',
                  icon: ZI.map,
                  title: 'How the map works',
                  text: 'Circles show neighbourhoods with homes. Zoom in or tap a circle to see prices; '
                      'tap a price to open the home. Use the filter button to narrow down.',
                ),
              ),
            ),
          ),
        ),

        // подсказка по зуму
        if (!showProps && !_loading)
          Positioned(
            left: 0,
            right: 0,
            bottom: 28,
            child: Center(
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                decoration: BoxDecoration(color: Zc.green, borderRadius: BorderRadius.circular(20)),
                child: const Text('Tap a neighbourhood or zoom in to see homes',
                    style: TextStyle(color: Colors.white, fontSize: 13)),
              ),
            ),
          ),

        // карточка выбранного объекта
        if (_selected != null)
          Positioned(
            left: 12,
            right: 12,
            bottom: 20,
            child: SafeArea(top: false, child: _MiniCard(p: _selected!)),
          ),
      ]),
    );
  }

  LatLng _initialCenter() {
    if (_filters.areaId != null) {
      for (final a in _areas) {
        if (a.id == _filters.areaId) return LatLng(a.lat, a.lng);
      }
    }
    return const LatLng(AppConfig.defaultLat + 0.004, AppConfig.defaultLng + 0.05);
  }
}

String _shortPrice(Property p) {
  final v = p.price;
  final s = v >= 1000000
      ? '${(v / 1000000).toStringAsFixed(v >= 10000000 ? 0 : 1)}M'
      : v >= 1000
          ? '${(v / 1000).round()}K'
          : v.round().toString();
  return 'K$s'; // K — сокращение квачи (ZMW)
}

class _PricePin extends StatelessWidget {
  const _PricePin({required this.p, required this.selected});
  final Property p;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    final bg = selected ? Zc.orange : (p.isPromoted ? Zc.green : Colors.white);
    final fg = selected || p.isPromoted ? Colors.white : Zc.green;
    return Center(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Zc.green, width: 1),
          boxShadow: const [BoxShadow(color: Zc.shadow, blurRadius: 6, offset: Offset(0, 2))],
        ),
        child: Text(_shortPrice(p), style: TextStyle(color: fg, fontWeight: FontWeight.w600, fontSize: 13)),
      ),
    );
  }
}

class _AreaBubble extends StatelessWidget {
  const _AreaBubble({required this.name, required this.count});
  final String name;
  final int count;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Container(
        padding: const EdgeInsets.fromLTRB(12, 6, 6, 6),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(20),
          boxShadow: const [BoxShadow(color: Zc.shadow, blurRadius: 6)],
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Flexible(
            child: Text(name,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Zc.green)),
          ),
          const SizedBox(width: 6),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
            decoration: BoxDecoration(color: Zc.orange, borderRadius: BorderRadius.circular(10)),
            child: Text('$count', style: const TextStyle(color: Colors.white, fontSize: 11)),
          ),
        ]),
      ),
    );
  }
}

class _RoundBtn extends StatelessWidget {
  const _RoundBtn({required this.icon, required this.onTap, this.badge = 0});
  final IconData icon;
  final VoidCallback onTap;
  final int badge;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 48,
        height: 48,
        decoration: const BoxDecoration(
          color: Colors.white,
          shape: BoxShape.circle,
          boxShadow: [BoxShadow(color: Zc.shadow, blurRadius: 10)],
        ),
        child: Badge(
          isLabelVisible: badge > 0,
          backgroundColor: Zc.orange,
          label: Text('$badge'),
          child: Icon(icon, color: Zc.green),
        ),
      ),
    );
  }
}

class _MiniCard extends StatelessWidget {
  const _MiniCard({required this.p});
  final Property p;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => openProperty(context, p),
      child: Container(
        height: 120,
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(18),
          boxShadow: const [BoxShadow(color: Zc.shadow, blurRadius: 16, offset: Offset(0, 4))],
        ),
        child: Row(children: [
          AspectRatio(aspectRatio: 1.1, child: PropImage(p.coverThumb, radius: 12)),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(p.priceLabel,
                    style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: Zc.orange)),
                const SizedBox(height: 4),
                Text(p.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 15)),
                Text(p.specsLine, style: const TextStyle(fontSize: 13, color: Zc.grey)),
                Text(p.locationLine,
                    maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12, color: Zc.grey)),
              ],
            ),
          ),
          FavButton(propertyId: p.id, size: 34),
        ]),
      ),
    );
  }
}
