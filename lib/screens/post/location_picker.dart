import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import '../../config.dart';
import '../../theme.dart';
import '../../widgets/common.dart';
import '../../widgets/zicons.dart';

/// Выбор точного места объекта: двигаешь карту, булавка в центре.
class LocationPickerScreen extends StatefulWidget {
  const LocationPickerScreen({super.key, required this.start});
  final LatLng start;

  @override
  State<LocationPickerScreen> createState() => _LocationPickerScreenState();
}

class _LocationPickerScreenState extends State<LocationPickerScreen> {
  late LatLng _center = widget.start;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Pin the location')),
      body: Stack(children: [
        FlutterMap(
          options: MapOptions(
            initialCenter: widget.start,
            initialZoom: 15,
            onPositionChanged: (camera, _) => _center = camera.center,
          ),
          children: [
            TileLayer(urlTemplate: AppConfig.mapTilesUrl, userAgentPackageName: AppConfig.mapUserAgent),
          ],
        ),
        const IgnorePointer(
          child: Center(
            child: Padding(
              padding: EdgeInsets.only(bottom: 48),
              child: Icon(ZI.pinFill, size: 52, color: Zc.orange),
            ),
          ),
        ),
        Positioned(
          left: 24,
          right: 24,
          bottom: 30,
          child: SafeArea(
            top: false,
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12)),
                child: const Text('Move the map so the pin is on the property',
                    style: TextStyle(fontSize: 13, color: Zc.grey)),
              ),
              const SizedBox(height: 12),
              PrimaryButton(
                label: 'Use this location',
                width: double.infinity,
                onPressed: () => Navigator.pop(context, _center),
              ),
            ]),
          ),
        ),
      ]),
    );
  }
}
