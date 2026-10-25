import 'package:flutter/material.dart';

import '../../models/models.dart';
import '../../theme.dart';
import '../../widgets/zicons.dart';

// ======================================================================
// Помощь продавцу в мастере объявления:
//  • советы к фото;
//  • шкала «объявление заполнено на 70%» с подсказкой, что добавить;
//  • подсказки к описанию: вода, свет, охрана, школы, дороги, магазины;
//  • мягкая проверка фото (темно, мало пикселей, вертикальное, повтор);
//  • подсказка цены похожих объявлений в районе.
// ======================================================================

/// Советы к фото — раскрывающийся список
class PhotoTipsCard extends StatelessWidget {
  const PhotoTipsCard({super.key});

  static const _tips = <(IconData, String)>[
    (ZI.sparkle, 'Shoot in daylight, with lights on and curtains open'),
    (ZI.photos, 'Hold the phone horizontally'),
    (ZI.house, 'Every room: living room, kitchen, each bedroom, bathroom'),
    (ZI.pin, 'The outside, the yard and the street'),
    (ZI.checkCircle, 'Tidy up first: no clutter, toilet lid down'),
    (ZI.close, 'No phone numbers, logos or text on the photos'),
    (ZI.star, 'Put the best photo first — it is the cover'),
  ];

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(14)),
      child: Theme(
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          leading: const Icon(ZI.camera, color: Zc.green),
          title: const Text('How to take good photos', style: TextStyle(fontWeight: FontWeight.w600)),
          subtitle: const Text('7 quick tips', style: TextStyle(fontSize: 12, color: Zc.grey)),
          childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
          children: [
            for (final (icon, text) in _tips)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 5),
                child: Row(children: [
                  Icon(icon, size: 18, color: Zc.orange),
                  const SizedBox(width: 10),
                  Expanded(child: Text(text, style: const TextStyle(fontSize: 14))),
                ]),
              ),
          ],
        ),
      ),
    );
  }
}

/// Темы, о которых чаще всего спрашивают в Замбии
class DescTopic {
  const DescTopic(this.label, this.prompt, this.words);
  final String label;
  final String prompt; // что добавить в текст по нажатию
  final List<String> words; // как понять, что тема уже есть
  bool mentioned(String text) {
    final t = text.toLowerCase();
    return words.any(t.contains);
  }
}

const descTopics = <DescTopic>[
  DescTopic('Water', 'Water: ', ['water', 'borehole', 'tank', 'lwsc', 'council']),
  DescTopic('Power', 'Power: ', ['power', 'zesco', 'solar', 'electric', 'inverter', 'generator', 'load']),
  DescTopic('Security', 'Security: ', ['security', 'guard', 'wall', 'fence', 'gate', 'alarm', 'cctv']),
  DescTopic('Schools', 'Schools nearby: ', ['school', 'college', 'university']),
  DescTopic('Roads', 'Road access: ', ['road', 'tar', 'gravel', 'access', 'bus', 'transport']),
  DescTopic('Shops', 'Shops and clinics nearby: ', ['shop', 'mall', 'market', 'clinic', 'hospital']),
];

/// Подсказки к описанию: какие темы уже есть, какие можно добавить одним нажатием
class DescriptionHints extends StatelessWidget {
  const DescriptionHints({super.key, required this.controller});
  final TextEditingController controller;

  void _add(DescTopic t) {
    final text = controller.text.trimRight();
    final add = '${text.isEmpty ? '' : '\n'}${t.prompt}';
    controller.text = '$text$add';
    controller.selection = TextSelection.collapsed(offset: controller.text.length);
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<TextEditingValue>(
      valueListenable: controller,
      builder: (context, v, _) {
        final missing = descTopics.where((t) => !t.mentioned(v.text)).toList();
        final len = v.text.trim().length;
        return Padding(
          padding: const EdgeInsets.only(top: 8),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(
              len < 150
                  ? 'People often ask about these — tap to add a line ($len / 150 characters recommended):'
                  : (missing.isEmpty ? 'Great — all the usual questions are answered.' : 'You could also mention:'),
              style: const TextStyle(fontSize: 12, color: Zc.grey),
            ),
            const SizedBox(height: 6),
            Wrap(spacing: 8, runSpacing: 6, children: [
              for (final t in descTopics)
                t.mentioned(v.text)
                    ? Chip(
                        avatar: const Icon(ZI.check, size: 14, color: Zc.green),
                        label: Text(t.label, style: const TextStyle(fontSize: 12, color: Zc.green)),
                        backgroundColor: Zc.greenTint,
                        side: BorderSide.none,
                        visualDensity: VisualDensity.compact,
                      )
                    : ActionChip(
                        avatar: const Icon(ZI.plus, size: 14, color: Zc.orange),
                        label: Text(t.label, style: const TextStyle(fontSize: 12)),
                        onPressed: () => _add(t),
                        backgroundColor: Colors.white,
                        side: const BorderSide(color: Zc.lightGrey),
                        visualDensity: VisualDensity.compact,
                      ),
            ]),
          ]),
        );
      },
    );
  }
}

/// Насколько заполнено объявление: (проценты, чего не хватает — по важности)
(int, List<String>) listingScore({
  required ListingDraft d,
  required String title,
  required String description,
  required String size,
  required String price,
  required String phone,
}) {
  final isLand = d.propertyType == PropertyType.land;
  var score = 0;
  final missing = <String>[];
  void check(bool ok, int points, String hint, {int partial = 0, bool half = false}) {
    if (ok) {
      score += points;
    } else {
      if (half) score += partial;
      missing.add(hint);
    }
  }

  final photos = d.photos.length;
  check(photos >= 5, 25, photos == 0 ? 'Add photos (5 or more)' : 'Add ${5 - photos} more ${5 - photos == 1 ? 'photo' : 'photos'}',
      partial: photos * 4, half: photos > 0);
  final desc = description.trim();
  check(desc.length >= 150, 20, 'Write a longer description (150+ characters)', partial: desc.length ~/ 15, half: desc.isNotEmpty);
  final topics = descTopics.where((t) => t.mentioned(desc)).length;
  check(topics >= 3, 10, 'Mention water, power and security in the description', partial: topics * 3, half: topics > 0);
  check(title.trim().length >= 15, 10, 'Make the title clearer, e.g. "3-bedroom house with borehole in Kabulonga"',
      partial: 5, half: title.trim().length >= 5);
  check((double.tryParse(price.replaceAll(',', '')) ?? 0) > 0, 10, 'Add the price');
  check(d.area != null, 5, 'Choose the neighbourhood');
  check(d.lat != null, 5, 'Pin the exact location on the map');
  check((double.tryParse(size.replaceAll(',', '.')) ?? 0) > 0, 5, 'Add the size in m²');
  check(isLand || d.amenities.length >= 3, 5, 'Tick what the property offers (amenities)');
  check(phone.replaceAll(RegExp(r'\D'), '').length >= 9, 5, 'Add a contact number');
  return (score.clamp(0, 100), missing);
}

/// Шкала «Listing filled 70%» и что добавить
class CompletenessCard extends StatelessWidget {
  const CompletenessCard({super.key, required this.score, required this.missing});
  final int score;
  final List<String> missing;

  @override
  Widget build(BuildContext context) {
    final color = score >= 85 ? Zc.green : (score >= 60 ? Zc.orange : const Color(0xFFD64545));
    return Container(
      margin: const EdgeInsets.only(bottom: 18),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(14)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Expanded(
            child: Text('Listing filled $score%', style: TextStyle(fontWeight: FontWeight.w700, color: color)),
          ),
          if (score >= 85) const Icon(ZI.checkCircle, color: Zc.green, size: 20),
        ]),
        const SizedBox(height: 8),
        ClipRRect(
          borderRadius: BorderRadius.circular(5),
          child: LinearProgressIndicator(value: score / 100, minHeight: 8, color: color, backgroundColor: Zc.chip),
        ),
        if (missing.isNotEmpty) ...[
          const SizedBox(height: 8),
          for (final m in missing.take(2))
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Row(children: [
                const Icon(ZI.plus, size: 14, color: Zc.orange),
                const SizedBox(width: 6),
                Expanded(child: Text(m, style: const TextStyle(fontSize: 13))),
              ]),
            ),
        ],
      ]),
    );
  }
}

/// Текст мягкой проверки фото
String photoWarningText(String code) => switch (code) {
      'dark' => 'looks dark — retake in daylight with lights on',
      'small' => 'is small — it may look blurry on big screens',
      'portrait' => 'is vertical — horizontal photos show rooms better',
      'duplicate' => 'is the same as another photo',
      _ => code,
    };

/// Подсказка цены похожих объявлений
class PriceHint extends StatelessWidget {
  const PriceHint({super.key, required this.stats, required this.price, required this.currency, required this.areaName, this.perLabel = ''});
  final PriceStats stats;
  final double price;
  final String currency;
  final String areaName;
  final String perLabel; // ' per month' / ' per day' / ''

  @override
  Widget build(BuildContext context) {
    if (!stats.enough) {
      return Padding(
        padding: const EdgeInsets.only(top: 8),
        child: Text(
          stats.n == 0
              ? 'No similar listings in $areaName yet to compare prices.'
              : 'Too few similar listings in $areaName to show a price range.',
          style: const TextStyle(fontSize: 12, color: Zc.grey),
        ),
      );
    }
    final low = price > 0 && price < stats.p25! * 0.5;
    final high = price > 0 && price > stats.p75! * 1.3;
    return Container(
      margin: const EdgeInsets.only(top: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: low || high ? Zc.orangeSoft : Zc.greenTint,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(
          'Similar homes in $areaName: ${formatMoney(stats.p25!, currency)}–${formatMoney(stats.p75!, currency)}$perLabel '
          '(typical ${formatMoney(stats.median!, currency)}, ${stats.n} listings)',
          style: const TextStyle(fontSize: 13, height: 1.35, color: Zc.green),
        ),
        if (low)
          const Padding(
            padding: EdgeInsets.only(top: 4),
            child: Text('Your price is much lower — check for a typo. A very low price can look like a scam.',
                style: TextStyle(fontSize: 13, color: Zc.orange)),
          ),
        if (high)
          const Padding(
            padding: EdgeInsets.only(top: 4),
            child: Text('Your price is higher than most similar homes. Explain why in the description.',
                style: TextStyle(fontSize: 13, color: Zc.orange)),
          ),
      ]),
    );
  }
}
