import 'package:flutter/material.dart';
import 'package:tutorial_coach_mark/tutorial_coach_mark.dart';

import '../theme.dart';
import 'wide_card.dart';

// Тур-подсветка (пакет tutorial_coach_mark). Скачивается отдельно, только когда тур показывается,
// чтобы не утяжелять первую загрузку сайта (см. Onboarding.maybeShow).

void showTour(
  BuildContext context, {
  required List<GlobalKey> keys,
  required List<String> titles,
  required List<String> texts,
  required List<bool> rounds,
  required VoidCallback onDone,
}) {
    final screen = MediaQuery.sizeOf(context);
    final targets = <TargetFocus>[
      for (var i = 0; i < keys.length; i++)
        TargetFocus(
          identify: titles[i],
          keyTarget: keys[i],
          shape: rounds[i] && !isDesktop(context) ? ShapeLightFocus.Circle : ShapeLightFocus.RRect,
          radius: 22,
          paddingFocus: rounds[i] ? 0 : 8, // иконку меню подсвечиваем аккуратным кругом
          enableOverlayTab: true,
          contents: [
            TargetContent(
              align: _below(keys[i], screen) ? ContentAlign.bottom : ContentAlign.top,
              builder: (ctx, controller) => _StepCard(
                title: titles[i],
                text: texts[i],
                index: i,
                count: keys.length,
                onNext: controller.next,
                onSkip: controller.skip,
              ),
            ),
          ],
        ),
    ];

    TutorialCoachMark(
      targets: targets,
      colorShadow: const Color(0xFF0B2E28),
      opacityShadow: 0.72,
      paddingFocus: 8,
      hideSkip: true, // своя кнопка «Skip» на карточке — крупнее и понятнее
      pulseEnable: false, // без мигания — спокойнее
      onFinish: onDone,
      onSkip: () {
        onDone();
        return true;
      },
    ).show(context: context);
}

/// Подпись снизу, если элемент в верхней половине экрана
bool _below(GlobalKey key, Size screen) {
    final box = key.currentContext?.findRenderObject() as RenderBox?;
    if (box == null) return true;
    final y = box.localToGlobal(Offset.zero).dy + box.size.height / 2;
    return y < screen.height / 2;
}

class _StepCard extends StatelessWidget {
  const _StepCard({
    required this.title,
    required this.text,
    required this.index,
    required this.count,
    required this.onNext,
    required this.onSkip,
  });
  final String title;
  final String text;
  final int index;
  final int count;
  final VoidCallback onNext;
  final VoidCallback onSkip;

  @override
  Widget build(BuildContext context) {
    final last = index == count - 1;
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 360),
        child: Material(
          color: Colors.white,
          borderRadius: BorderRadius.circular(18),
          elevation: 6,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(18, 16, 10, 8),
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(title, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: Zc.green)),
              const SizedBox(height: 6),
              Text(text, style: const TextStyle(fontSize: 15, height: 1.4, color: Zc.text)),
              const SizedBox(height: 6),
              Row(children: [
                // точки прогресса
                for (var i = 0; i < count; i++)
                  Container(
                    margin: const EdgeInsets.only(right: 4),
                    width: i == index ? 14 : 6,
                    height: 6,
                    decoration: BoxDecoration(
                      color: i == index ? Zc.orange : Zc.lightGrey,
                      borderRadius: BorderRadius.circular(3),
                    ),
                  ),
                const Spacer(),
                if (!last) TextButton(onPressed: onSkip, child: const Text('Skip', style: TextStyle(color: Zc.grey))),
                TextButton(
                  onPressed: onNext,
                  child: Text(last ? 'Got it' : 'Next', style: const TextStyle(color: Zc.orange, fontWeight: FontWeight.w600)),
                ),
              ]),
            ]),
          ),
        ),
      ),
    );
  }
}
