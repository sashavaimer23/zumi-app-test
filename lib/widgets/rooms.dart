import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../features.dart';
import '../models/models.dart';
import '../state/app_state.dart';
import '../theme.dart';
import 'common.dart';
import 'zicons.dart';

/// Rooms & budget: компактная карточка комнаты — лёгкая (маленькое фото), крупная цена, район, удобства.
class RoomCard extends StatelessWidget {
  const RoomCard({super.key, required this.p, required this.onTap});
  final Property p;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final r = p.roomInfo;
    final facts = (r?.facts ?? const <String>[]).take(3).toList();
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Material(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(10),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: SizedBox(
                  width: 104,
                  height: 104,
                  child: p.thumbs.isNotEmpty || p.images.isNotEmpty
                      ? PropImage(p.thumbs.isNotEmpty ? p.thumbs.first : p.images.first)
                      : Container(
                          color: Zc.chip,
                          alignment: Alignment.center,
                          child: const Icon(ZI.house, color: Zc.green, size: 34),
                        ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text((r?.kindLabel ?? 'Room').toUpperCase(),
                      style: const TextStyle(
                          fontSize: 11, letterSpacing: 0.6, color: Zc.orange, fontWeight: FontWeight.w700)),
                  const SizedBox(height: 3),
                  Text(p.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: Zc.text)),
                  const SizedBox(height: 4),
                  Text.rich(TextSpan(children: [
                    TextSpan(
                        text: money(p.price, p.currency),
                        style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: Zc.green)),
                    const TextSpan(text: ' / month', style: TextStyle(fontSize: 13, color: Zc.grey)),
                  ])),
                  const SizedBox(height: 2),
                  Row(children: [
                    const Icon(ZI.pin, size: 14, color: Zc.grey),
                    const SizedBox(width: 3),
                    Expanded(
                      child: Text(p.areaName ?? p.city ?? '',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontSize: 13, color: Zc.grey)),
                    ),
                    if (p.isVerified) const Icon(ZI.check, size: 14, color: Zc.green),
                  ]),
                  if (facts.isNotEmpty) ...[
                    const SizedBox(height: 6),
                    Wrap(spacing: 6, runSpacing: 4, children: [
                      for (final f in facts)
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                          decoration: BoxDecoration(color: Zc.chip, borderRadius: BorderRadius.circular(10)),
                          child: Text(f, style: const TextStyle(fontSize: 11, color: Zc.green)),
                        ),
                    ]),
                  ],
                ]),
              ),
            ]),
          ),
        ),
      ),
    );
  }
}

/// «Never pay to view a room» — главное правило раздела
class RoomSafetyNote extends StatelessWidget {
  const RoomSafetyNote({super.key, this.margin = EdgeInsets.zero});
  final EdgeInsets margin;

  @override
  Widget build(BuildContext context) => Padding(
        padding: margin,
        child: Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(color: Zc.greenTint, borderRadius: BorderRadius.circular(14)),
          child: const Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Icon(ZI.shield, color: Zc.green, size: 22),
            SizedBox(width: 10),
            Expanded(
              child: Text.rich(
                TextSpan(children: [
                  TextSpan(text: 'Never pay to view a room. ', style: TextStyle(fontWeight: FontWeight.w700)),
                  TextSpan(
                      text: 'See the room in person and meet the landlord before you pay rent or a deposit. '
                          'If anyone asks for a viewing fee, report the listing.'),
                ]),
                style: TextStyle(fontSize: 13, color: Zc.text, height: 1.4),
              ),
            ),
          ]),
        ),
      );
}

/// Вводный блок раздела: название, пометка «видит только команда», безопасность
class RoomsIntro extends StatelessWidget {
  const RoomsIntro({super.key});

  @override
  Widget build(BuildContext context) {
    final hidden = !Features.rooms && (context.watch<AppState>().user?.isAdmin ?? false);
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      if (hidden)
        Container(
          margin: const EdgeInsets.only(bottom: 10),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(color: Zc.orangeSoft, borderRadius: BorderRadius.circular(10)),
          child: const Row(children: [
            Icon(ZI.lock, size: 16, color: Zc.orange),
            SizedBox(width: 8),
            Expanded(
              child: Text('Hidden — only the Zumi team sees this section. Turn it on in the team panel → Ads.',
                  style: TextStyle(fontSize: 12, color: Zc.text)),
            ),
          ]),
        ),
      Text('Rooms & budget', style: zHeadline(context, size: 28)),
      const SizedBox(height: 4),
      const Text("Rooms, boys' quarters, bedsitters and student hostels — for rent.",
          style: TextStyle(fontSize: 14, color: Zc.grey)),
      const RoomSafetyNote(margin: EdgeInsets.only(top: 12)),
    ]);
  }
}

/// Страница комнаты: блок «Room details»
class RoomDetails extends StatelessWidget {
  const RoomDetails({super.key, required this.info});
  final RoomInfo info;

  @override
  Widget build(BuildContext context) {
    Widget row(IconData icon, String text) => Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: Row(children: [
            Icon(icon, size: 20, color: Zc.green),
            const SizedBox(width: 10),
            Expanded(child: Text(text, style: const TextStyle(fontSize: 15, color: Zc.text))),
          ]),
        );
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      row(ZI.house, info.kindLabel),
      if (info.bathroom != null) row(ZI.bath, kRoomBathroom[info.bathroom]!),
      if (info.kitchen != null) row(ZI.house, kRoomKitchen[info.kitchen]!),
      if (info.water != null) row(ZI.wave, kRoomWater[info.water]!),
      if (info.power != null) row(ZI.bolt, kRoomPower[info.power]!),
      if (info.wall != null) row(ZI.shield, info.wall! ? 'Walled yard' : 'No wall around the yard'),
    ]);
  }
}
