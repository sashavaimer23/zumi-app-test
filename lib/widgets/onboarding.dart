import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:tutorial_coach_mark/tutorial_coach_mark.dart';

import '../state/app_state.dart';
import '../theme.dart';
import 'wide_card.dart';
import 'zicons.dart';

// ======================================================================
// Обучение при первом входе.
//
// Принципы, чтобы обучение не раздражало:
//  • тур короткий (2–4 шага), появляется не сразу, а когда главная уже открыта;
//  • на каждом шаге видно «1 из 4» и есть «Skip» — пропустить сразу весь тур;
//  • нажатие в любом месте листает дальше, ничего не нужно «искать»;
//  • каждый тур показывается один раз, и не два тура подряд;
//  • подсказки при первом использовании — небольшие карточки в самом экране
//    с кнопкой «Got it», а не окна поверх всего.
// ======================================================================

/// Элементы, которые подсвечивает тур. Каждый ключ висит ровно на одном виджете.
class TourKeys {
  static final search = GlobalKey(debugLabel: 'tour-search');
  static final map = GlobalKey(debugLabel: 'tour-map');
  static final saved = GlobalKey(debugLabel: 'tour-saved');
  static final post = GlobalKey(debugLabel: 'tour-post');
  static final chats = GlobalKey(debugLabel: 'tour-chats');
  static final profile = GlobalKey(debugLabel: 'tour-profile');

  /// Прокрутка главной: перед туром возвращаемся наверх, чтобы всё было видно
  static final homeScroll = ScrollController();
}

class _Step {
  const _Step(this.key, this.title, this.text, {this.round = false});
  final GlobalKey key;
  final String title;
  final String text;
  final bool round; // круглая подсветка (иконки меню)
}

/// Какие бывают туры
enum Tour { buyer, owner, agent }

class Onboarding {
  static bool _running = false;
  static DateTime? _lastShown;

  static String _id(Tour t) => 'tour_${t.name}';

  /// Какой тур сейчас уместен (или null)
  static Tour? pick(AppState app) {
    final u = app.user;
    if (u != null && u.isAdmin) return null; // команде Zumi туры не нужны
    if (u != null && u.isAgent) return app.hintSeen(_id(Tour.agent)) ? null : Tour.agent;
    if (!app.hintSeen(_id(Tour.buyer))) return Tour.buyer;
    // тур собственника — после первого опубликованного объявления
    if (u != null && app.hintSeen('posted_first') && !app.hintSeen(_id(Tour.owner))) return Tour.owner;
    return null;
  }

  static List<_Step> _steps(Tour t) => switch (t) {
        Tour.buyer => [
            _Step(TourKeys.search, 'Search', 'Type a neighbourhood, e.g. Kabulonga or Woodlands.'),
            _Step(TourKeys.map, 'Map', 'See homes on the map and look around an area.'),
            _Step(TourKeys.saved, 'Saved', 'Tap the heart on a home to keep it here and compare later.', round: true),
            _Step(TourKeys.post, 'List your property', 'Renting out or selling? Post a listing for free.'),
          ],
        Tour.owner => [
            _Step(TourKeys.profile, 'Your listings', 'Profile → My listings: edit, see views and confirm '
                'every 30 days answer "still available?" in one tap.', round: true),
            _Step(TourKeys.chats, 'Messages', 'Questions from tenants and buyers arrive here.', round: true),
          ],
        Tour.agent => [
            _Step(TourKeys.post, 'Add listings', 'Post homes for your clients — each one takes about 3 minutes.'),
            _Step(TourKeys.profile, 'Your agent cabinet', 'Profile: your listings, Promotion and the ZIEA licence '
                'check. Add your ZIEA number to unlock promotion.', round: true),
            _Step(TourKeys.chats, 'Messages', 'Enquiries from clients arrive here.', round: true),
          ],
      };

  /// Показать тур, если он уместен. force — «Показать обучение ещё раз».
  static Future<void> maybeShow(BuildContext context, {bool force = false}) async {
    if (_running) return;
    final app = context.read<AppState>();
    final tour = pick(app);
    if (tour == null) return;
    // не два тура подряд (кроме явной просьбы)
    if (!force && _lastShown != null && DateTime.now().difference(_lastShown!) < const Duration(minutes: 2)) return;

    if (TourKeys.homeScroll.hasClients && TourKeys.homeScroll.offset > 0) {
      await TourKeys.homeScroll.animateTo(0, duration: const Duration(milliseconds: 300), curve: Curves.easeOut);
    }
    if (!context.mounted) return;

    // только видимые на экране элементы
    final screen = MediaQuery.sizeOf(context);
    final steps = _steps(tour).where((s) {
      final box = s.key.currentContext?.findRenderObject() as RenderBox?;
      if (box == null || !box.attached || !box.hasSize) return false;
      final pos = box.localToGlobal(Offset.zero);
      return pos.dy >= 0 && pos.dy + box.size.height <= screen.height && pos.dx >= 0 && pos.dx <= screen.width;
    }).toList();
    if (steps.isEmpty) return;

    _running = true;
    _lastShown = DateTime.now();
    void done() {
      _running = false;
      app.markHint(_id(tour));
    }

    final targets = <TargetFocus>[
      for (var i = 0; i < steps.length; i++)
        TargetFocus(
          identify: steps[i].title,
          keyTarget: steps[i].key,
          shape: steps[i].round && !isDesktop(context) ? ShapeLightFocus.Circle : ShapeLightFocus.RRect,
          radius: 22,
          paddingFocus: steps[i].round ? 0 : 8, // иконку меню подсвечиваем аккуратным кругом
          enableOverlayTab: true,
          contents: [
            TargetContent(
              align: _below(steps[i].key, screen) ? ContentAlign.bottom : ContentAlign.top,
              builder: (ctx, controller) => _StepCard(
                step: steps[i],
                index: i,
                count: steps.length,
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
      onFinish: done,
      onSkip: () {
        done();
        return true;
      },
    ).show(context: context);
  }

  /// Подпись снизу, если элемент в верхней половине экрана
  static bool _below(GlobalKey key, Size screen) {
    final box = key.currentContext?.findRenderObject() as RenderBox?;
    if (box == null) return true;
    final y = box.localToGlobal(Offset.zero).dy + box.size.height / 2;
    return y < screen.height / 2;
  }
}

class _StepCard extends StatelessWidget {
  const _StepCard({
    required this.step,
    required this.index,
    required this.count,
    required this.onNext,
    required this.onSkip,
  });
  final _Step step;
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
              Text(step.title, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: Zc.green)),
              const SizedBox(height: 6),
              Text(step.text, style: const TextStyle(fontSize: 15, height: 1.4, color: Zc.text)),
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

/// Подсказка при первом использовании: небольшая карточка в самом экране, закрывается «Got it».
/// Показывается один раз (запоминается на устройстве).
class HintCard extends StatelessWidget {
  const HintCard({
    super.key,
    required this.id,
    required this.title,
    required this.text,
    this.icon = ZI.info,
    this.actionLabel,
    this.onAction,
    this.margin = EdgeInsets.zero,
  });
  final String id;
  final String title;
  final String text;
  final IconData icon;
  final String? actionLabel;
  final VoidCallback? onAction;
  final EdgeInsets margin;

  @override
  Widget build(BuildContext context) {
    final seen = context.select<AppState, bool>((a) => a.hintSeen(id));
    return AnimatedSize(
      duration: const Duration(milliseconds: 250),
      curve: Curves.easeOut,
      child: seen
          ? const SizedBox(width: double.infinity)
          : Container(
              margin: margin,
              padding: const EdgeInsets.fromLTRB(14, 12, 6, 8),
              decoration: BoxDecoration(
                color: const Color(0xFFEAF4F0),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: const Color(0xFFCFE5DD)),
              ),
              child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Padding(padding: const EdgeInsets.only(top: 2), child: Icon(icon, color: Zc.green, size: 20)),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(title, style: const TextStyle(fontWeight: FontWeight.w600, color: Zc.green)),
                    const SizedBox(height: 2),
                    Text(text, style: const TextStyle(fontSize: 13, height: 1.4, color: Zc.text)),
                    Row(mainAxisAlignment: MainAxisAlignment.end, children: [
                      if (actionLabel != null && onAction != null)
                        TextButton(
                          onPressed: () {
                            context.read<AppState>().markHint(id);
                            onAction!();
                          },
                          child: Text(actionLabel!, style: const TextStyle(color: Zc.orange, fontWeight: FontWeight.w600)),
                        ),
                      TextButton(
                        onPressed: () => context.read<AppState>().markHint(id),
                        child: const Text('Got it', style: TextStyle(color: Zc.green)),
                      ),
                    ]),
                  ]),
                ),
              ]),
            ),
    );
  }
}
