import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../state/app_state.dart';
import '../theme.dart';
import '../widgets/common.dart';
import '../widgets/onboarding.dart';
import '../widgets/results.dart';
import '../widgets/wide_card.dart';
import '../widgets/zicons.dart';
import 'admin/admin_screen.dart';
import 'chats_screen.dart';
import 'home_screen.dart';
import 'post/post_wizard.dart';
import 'profile_screen.dart';
import 'public_profile_screen.dart';
import 'saved_screen.dart';

/// Вкладки: 0 Search · 1 Saved · 2 Post (без кнопки в меню) · 3 Chats · 4 Profile
class Shell extends StatefulWidget {
  const Shell({super.key});

  /// Переключить вкладку из любого места: Shell.of(context)?.go(0)
  static ShellState? of(BuildContext context) => context.findAncestorStateOfType<ShellState>();

  /// Главный экран, даже из открытого поверх экрана (например, из «Помощи»)
  static ShellState? current;

  /// Высота «острова» меню + отступ — чтобы контент не прятался под ним
  static const double navSpace = 104;

  @override
  State<Shell> createState() => ShellState();
}

class ShellState extends State<Shell> with WidgetsBindingObserver {
  int _index = 0;
  // ключ мастера, чтобы после закрытия начинать заново
  Key _postKey = UniqueKey();

  void go(int i) {
    setState(() => _index = i);
    if (i == 0) _scheduleTour(const Duration(milliseconds: 700));
  }

  AppState? _app;
  String _appKey = '';
  int _tourTries = 0;

  @override
  void initState() {
    super.initState();
    Shell.current = this;
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _openSharedLink();
      _app = context.read<AppState>()..addListener(_onAppChanged);
      _appKey = _keyOf(_app!);
      _app!.repo.logVisit(); // обезличенный счётчик посещений
      // первый тур — когда заставка закончилась и главная уже видна
      _scheduleTour(const Duration(milliseconds: 4200));
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _app?.removeListener(_onAppChanged);
    if (Shell.current == this) Shell.current = null;
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _app?.repo.logVisit();
      _app?.refreshUnread(); // вернулся в приложение — обновить значок сообщений
    }
  }

  // ---------- обучение ----------
  String _keyOf(AppState a) => '${a.user?.id}|${a.user?.role}|${a.tourRequest}';
  bool _forceNext = false;

  void _onAppChanged() {
    final app = _app;
    if (app == null) return;
    final key = _keyOf(app);
    if (key == _appKey) return;
    _forceNext = key.split('|').last != _appKey.split('|').last; // «показать ещё раз» / после первого объявления
    _appKey = key;
    _tourTries = 0;
    _scheduleTour(const Duration(milliseconds: 900));
  }

  void _scheduleTour(Duration delay) {
    Future.delayed(delay, () {
      if (!mounted) return;
      final onTop = ModalRoute.of(context)?.isCurrent ?? true;
      if (_index != 0 || !onTop) {
        // главная сейчас не видна — попробуем позже (не дольше пары минут)
        if (_tourTries++ < 60 && _index == 0) _scheduleTour(const Duration(seconds: 2));
        return;
      }
      final force = _forceNext;
      _forceNext = false;
      Onboarding.maybeShow(context, force: force);
    });
  }

  /// Ссылка «Поделиться»: сайт открывается сразу на объявлении (?listing=id)
  /// или на странице агента (?agent=id)
  Future<void> _openSharedLink() async {
    if (!kIsWeb) return;
    final q = Uri.base.queryParameters;
    final listing = q['listing'];
    final person = q['agent'] ?? q['profile'];
    try {
      if (listing != null && listing.isNotEmpty) {
        final p = await context.read<AppState>().repo.getProperty(listing);
        if (p != null && mounted) openProperty(context, p);
      } else if (person != null && person.isNotEmpty && mounted) {
        Navigator.push(context, MaterialPageRoute(builder: (_) => PublicProfileScreen(userId: person)));
      }
    } catch (_) {/* ссылка устарела — просто остаёмся на главной */}
  }

  void resetPost({int goTo = 0}) => setState(() {
        _postKey = UniqueKey();
        _index = goTo;
      });

  @override
  Widget build(BuildContext context) {
    final pages = IndexedStack(
      index: _index,
      children: [
        const HomeScreen(),
        const SavedScreen(),
        PostWizard(key: _postKey),
        const ChatsScreen(),
        const ProfileScreen(),
      ],
    );

    // компьютер: шапка сайта сверху, без «острова»
    if (isDesktop(context)) {
      return Scaffold(
        body: Column(children: [
          _TopBar(index: _index, onTap: go),
          Expanded(child: pages),
        ]),
      );
    }

    // телефон: меню-«остров» парит над контентом
    return Scaffold(
      extendBody: true,
      body: pages,
      bottomNavigationBar: _index == 2 ? null : _PillNavBar(index: _index, onTap: go),
    );
  }
}

/// Ключ тура для пункта меню (Saved, Chats, Profile)
GlobalKey? _tourKey(int tab) => switch (tab) {
      1 => TourKeys.saved,
      3 => TourKeys.chats,
      4 => TourKeys.profile,
      _ => null,
    };

/// Коралловое меню-«остров»: выбранный пункт — светлая плашка-овал с иконкой и подписью,
/// которая плавно переезжает между пунктами. Плашка рисуется отдельным слоем,
/// поэтому всегда остаётся ровным овалом и точно по центру.
class _PillNavBar extends StatelessWidget {
  const _PillNavBar({required this.index, required this.onTap});
  final int index;
  final ValueChanged<int> onTap;

  // (вкладка, иконка, подпись)
  static const _items = <(int, IconData, String)>[
    (0, ZI.search, 'Search'),
    (1, ZI.heart, 'Saved'),
    (3, ZI.chat, 'Chats'),
    (4, ZI.user, 'Profile'),
  ];

  static const _duration = Duration(milliseconds: 380);
  static const _curve = Curves.easeOutCubic;
  static const _pillColor = Color(0xFFF4F2EF);
  static const _inset = 6.0; // одинаковый отступ плашки от края со всех сторон

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      minimum: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 4),
        child: Container(
          height: 68,
          padding: const EdgeInsets.all(_inset),
          decoration: const ShapeDecoration(
            color: Zc.orange,
            shape: StadiumBorder(),
            shadows: [BoxShadow(color: Color(0x33000000), blurRadius: 18, offset: Offset(0, 6))],
          ),
          child: LayoutBuilder(builder: (context, c) {
            final n = _items.length;
            final sel = _items.indexWhere((e) => e.$1 == index);
            final unread = context.watch<AppState>().unreadChats;
            final has = sel >= 0;
            final selW = has ? c.maxWidth * 0.38 : 0.0;
            // -0.5 px: запас, чтобы при анимации сумма ширин не вылезла за край
            final otherW = has ? (c.maxWidth - selW - 0.5) / (n - 1) : (c.maxWidth - 0.5) / n;
            double widthOf(int i) => i == sel ? selW : otherW;
            final pillLeft = has ? List.generate(sel, widthOf).fold<double>(0, (a, b) => a + b) : 0.0;

            return Stack(children: [
              // плашка-овал
              if (has)
                AnimatedPositioned(
                  duration: _duration,
                  curve: _curve,
                  left: pillLeft,
                  top: 0,
                  bottom: 0,
                  width: selW,
                  child: const DecoratedBox(
                    decoration: ShapeDecoration(color: _pillColor, shape: StadiumBorder()),
                  ),
                ),
              // иконки и подпись
              Row(children: [
                for (var i = 0; i < n; i++)
                  KeyedSubtree(
                    key: _tourKey(_items[i].$1),
                    child: _NavItem(
                      width: widthOf(i),
                      icon: _items[i].$2,
                      label: _items[i].$3,
                      selected: i == sel,
                      badge: _items[i].$1 == 3 ? unread : 0,
                      onTap: () => onTap(_items[i].$1),
                    ),
                  ),
              ]),
            ]);
          }),
        ),
      ),
    );
  }
}

class _NavItem extends StatelessWidget {
  const _NavItem({
    required this.width,
    required this.icon,
    required this.label,
    required this.selected,
    required this.onTap,
    this.badge = 0,
  });
  final double width;
  final IconData icon;
  final String label;
  final bool selected;
  final VoidCallback onTap;
  final int badge; // непрочитанные сообщения

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: AnimatedContainer(
        duration: _PillNavBar._duration,
        curve: _PillNavBar._curve,
        width: width,
        alignment: Alignment.center,
        child: ClipRect(
          child: OverflowBox(
            maxWidth: double.infinity,
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              TweenAnimationBuilder<Color?>(
                duration: _PillNavBar._duration,
                curve: _PillNavBar._curve,
                tween: ColorTween(end: selected ? Zc.orange : Colors.white),
                builder: (_, color, __) => Stack(clipBehavior: Clip.none, children: [
                  Icon(icon, size: 26, color: color),
                  if (badge > 0)
                    Positioned(
                      right: -10,
                      top: -8,
                      child: CountBadge(badge, color: Zc.green, border: selected ? _PillNavBar._pillColor : Zc.orange),
                    ),
                ]),
              ),
              // подпись видна только у выбранного пункта
              AnimatedSize(
                duration: _PillNavBar._duration,
                curve: _PillNavBar._curve,
                child: selected
                    ? Padding(
                        padding: const EdgeInsets.only(left: 8),
                        child: Text(
                          label,
                          maxLines: 1,
                          softWrap: false,
                          style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w400, color: Zc.orange),
                        ),
                      )
                    : const SizedBox.shrink(),
              ),
            ]),
          ),
        ),
      ),
    );
  }
}

/// Шапка сайта для компьютера (временная — заменим на дизайн десктопа)
class _TopBar extends StatelessWidget {
  const _TopBar({required this.index, required this.onTap});
  final int index;
  final ValueChanged<int> onTap;

  static const _items = <(int, String)>[(0, 'Search'), (1, 'Saved'), (3, 'Chats'), (4, 'Profile')];

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 72,
      decoration: const BoxDecoration(
        color: Zc.bg,
        border: Border(bottom: BorderSide(color: Zc.chip)),
      ),
      child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 32),
            child: Row(children: [
              GestureDetector(
                onTap: () => onTap(0),
                child: const Row(children: [
                  ZLogo(size: 34),
                  SizedBox(width: 10),
                  Text('ZUMI', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700, color: Zc.green, letterSpacing: 2)),
                ]),
              ),
              const Spacer(),
              for (final (i, label) in _items)
                Padding(
                  key: _tourKey(i),
                  padding: const EdgeInsets.symmetric(horizontal: 6),
                  child: TextButton(
                    onPressed: () => onTap(i),
                    style: TextButton.styleFrom(
                      foregroundColor: i == index ? Zc.orange : Zc.text,
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                    ),
                    child: Column(mainAxisSize: MainAxisSize.min, children: [
                      Row(mainAxisSize: MainAxisSize.min, children: [
                        Text(label, style: const TextStyle(fontSize: 16)),
                        if (i == 3 && context.watch<AppState>().unreadChats > 0) ...[
                          const SizedBox(width: 6),
                          CountBadge(context.watch<AppState>().unreadChats),
                        ],
                      ]),
                      const SizedBox(height: 4),
                      AnimatedContainer(
                        duration: const Duration(milliseconds: 250),
                        height: 2,
                        width: i == index ? 24 : 0,
                        color: Zc.orange,
                      ),
                    ]),
                  ),
                ),
              if (context.watch<AppState>().user?.isAdmin ?? false)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 6),
                  child: TextButton.icon(
                    onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const AdminScreen())),
                    icon: const Icon(ZI.shieldFill, size: 18, color: Zc.green),
                    label: const Text('Team', style: TextStyle(color: Zc.green, fontSize: 16)),
                  ),
                ),
              const SizedBox(width: 14),
              FilledButton.icon(
                key: TourKeys.post,
                style: FilledButton.styleFrom(
                  backgroundColor: Zc.orange,
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
                ),
                onPressed: () => onTap(2),
                icon: const Icon(ZI.plusCircle, size: 20),
                label: const Text('Post a listing', style: TextStyle(fontWeight: FontWeight.w400)),
              ),
            ]),
      ),
    );
  }
}
