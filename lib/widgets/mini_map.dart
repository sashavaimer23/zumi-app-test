import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import '../config.dart';
import '../theme.dart';
import 'zicons.dart';

/// Карта на странице объявления. Пакет карты скачивается отдельно (см. lazy_map.dart).
/// approximate — комната: только круг ~1 км, точное место — после разговора с хозяином.
Widget miniMap({required double lat, required double lng, required bool approximate}) => FlutterMap(
      options: MapOptions(
        initialCenter: LatLng(lat, lng),
        initialZoom: 14.5,
        interactionOptions: const InteractionOptions(flags: InteractiveFlag.pinchZoom | InteractiveFlag.drag),
      ),
      children: [
        TileLayer(urlTemplate: AppConfig.mapTilesUrl, userAgentPackageName: AppConfig.mapUserAgent),
        if (approximate)
          CircleLayer(circles: [
            CircleMarker(
              point: LatLng(lat, lng),
              radius: 700,
              useRadiusInMeter: true,
              color: const Color(0x2EFF7A59),
              borderColor: Zc.orange,
              borderStrokeWidth: 1.5,
            ),
          ])
        else
          MarkerLayer(markers: [
            Marker(
              point: LatLng(lat, lng),
              width: 44,
              height: 44,
              alignment: Alignment.topCenter,
              child: const Icon(ZI.pinFill, color: Zc.orange, size: 44),
            ),
          ]),
      ],
    );
