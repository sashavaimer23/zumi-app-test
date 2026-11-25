import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart';

import '../models/models.dart';
import '../theme.dart';
import '../widgets/zicons.dart';

// Карта нужна не всем и не сразу — её код (пакет flutter_map) скачивается отдельно,
// когда человек открывает карту или доходит до карты в объявлении.
// Так первая загрузка сайта легче (важно на 3G и слабых телефонах).
import '../widgets/mini_map.dart' deferred as mini;
import 'map_screen.dart' deferred as mapscreen;
import 'post/location_picker.dart' deferred as picker;

Future<bool> _load(BuildContext context, Future<void> Function() load) async {
  try {
    await load();
    return true;
  } catch (_) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not load the map. Check your internet and try again.')));
    }
    return false;
  }
}

/// Полноэкранная карта с поиском
Future<void> openMapScreen(BuildContext context, SearchFilters filters) async {
  final nav = Navigator.of(context);
  if (!await _load(context, mapscreen.loadLibrary)) return;
  await nav.push(MaterialPageRoute(builder: (_) => mapscreen.MapScreen(initial: filters)));
}

/// Выбор точки на карте при подаче объявления
Future<LatLng?> pickLocation(BuildContext context, LatLng start) async {
  final nav = Navigator.of(context);
  if (!await _load(context, picker.loadLibrary)) return null;
  return nav.push<LatLng>(MaterialPageRoute(builder: (_) => picker.LocationPickerScreen(start: start)));
}

/// Карта в объявлении: пока код карты грузится — спокойная заглушка
class LazyMiniMap extends StatefulWidget {
  const LazyMiniMap({super.key, required this.lat, required this.lng, required this.approximate});
  final double lat;
  final double lng;
  final bool approximate;

  @override
  State<LazyMiniMap> createState() => _LazyMiniMapState();
}

class _LazyMiniMapState extends State<LazyMiniMap> {
  late final Future<void> _ready = mini.loadLibrary();

  @override
  Widget build(BuildContext context) => FutureBuilder<void>(
        future: _ready,
        builder: (context, snap) {
          if (snap.connectionState == ConnectionState.done && !snap.hasError) {
            return mini.miniMap(lat: widget.lat, lng: widget.lng, approximate: widget.approximate);
          }
          return Container(
            color: Zc.chip,
            alignment: Alignment.center,
            child: snap.hasError
                ? const Text('Map is not available right now', style: TextStyle(color: Zc.grey))
                : const Icon(ZI.map, color: Zc.grey, size: 32),
          );
        },
      );
}
