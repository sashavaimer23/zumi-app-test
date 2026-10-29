import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../data/repository.dart';
import '../features.dart';
import '../models/models.dart';
import '../utils/app_badge.dart';

/// Общее состояние приложения: пользователь, избранное, недавно просмотренные.
class AppState extends ChangeNotifier {
  AppState(this.repo, this._prefs) {
    _favorites = (_prefs.getStringList(_kFav) ?? []).toSet();
    _recent = _prefs.getStringList(_kRecent) ?? [];
    _hints = (_prefs.getStringList(_kHints) ?? []).toSet();
    _user = repo.currentUser;
    _sub = repo.userChanges.listen((u) {
      final changed = u?.id != _user?.id;
      _user = u;
      notifyListeners();
      if (u != null) _syncFavorites();
      if (changed) _watchUnread();
    });
    if (_user != null) _syncFavorites();
    _watchUnread();
    loadFlags();
  }

  // ---------- что включено (с сервера) ----------
  bool get promotionOn => Features.promotion;

  Future<void> loadFlags() async {
    final f = await repo.appFlags();
    final promo = (f['promotion'] as bool?) ?? false;
    if (promo == Features.promotion) return;
    Features.promotion = promo;
    notifyListeners();
  }

  Future<void> setPromotion(bool on) async {
    await repo.setPromotionEnabled(on);
    Features.promotion = on;
    dataChanged();
  }

  // ---------- «Как вам Zumi?» — мягкая просьба об отзыве ----------
  // Через 7 минут пользования (суммарно, за несколько визитов). Не чаще раза в 14 дней, не больше 3 раз,
  // и больше никогда — если человек уже оставил отзыв.
  static const _kUseSecs = 'fb_use_secs', _kAskedAt = 'fb_asked_at', _kAskedTimes = 'fb_asked_times', _kGiven = 'fb_given';
  static const feedbackAfterSecs = 7 * 60;
  bool _feedbackVisible = false;
  bool get feedbackPromptVisible => _feedbackVisible;

  /// Вызывается каждые 30 секунд, пока приложение открыто и на экране
  void addUsage(int secs) {
    final total = (_prefs.getInt(_kUseSecs) ?? 0) + secs;
    _prefs.setInt(_kUseSecs, total);
    if (_feedbackVisible || total < feedbackAfterSecs) return;
    if (_prefs.getBool(_kGiven) ?? false) return;
    if ((_prefs.getInt(_kAskedTimes) ?? 0) >= 3) return;
    final last = _prefs.getInt(_kAskedAt);
    if (last != null && DateTime.now().millisecondsSinceEpoch - last < const Duration(days: 14).inMilliseconds) return;
    _feedbackVisible = true;
    _prefs.setInt(_kAskedAt, DateTime.now().millisecondsSinceEpoch);
    _prefs.setInt(_kAskedTimes, (_prefs.getInt(_kAskedTimes) ?? 0) + 1);
    notifyListeners();
  }

  void hideFeedbackPrompt({bool given = false}) {
    if (given) _prefs.setBool(_kGiven, true);
    if (!_feedbackVisible) return;
    _feedbackVisible = false;
    notifyListeners();
  }

  final Repository repo;
  final SharedPreferences _prefs;
  StreamSubscription<AppUser?>? _sub;

  static const _kFav = 'favorites';
  static const _kRecent = 'recently_viewed';
  static const _kHints = 'seen_hints';

  AppUser? _user;
  AppUser? get user => _user;
  bool get signedIn => _user != null;

  // ---------- районы (кэш) ----------
  List<Area>? _areas;
  Future<List<Area>> areas() async => _areas ??= await repo.areas();

  // ---------- избранное ----------
  late Set<String> _favorites;
  Set<String> get favorites => _favorites;
  bool isFavorite(String id) => _favorites.contains(id);

  Future<void> toggleFavorite(String id) async {
    final value = !_favorites.contains(id);
    value ? _favorites.add(id) : _favorites.remove(id);
    await _prefs.setStringList(_kFav, _favorites.toList());
    notifyListeners();
    try {
      await repo.setFavorite(id, value);
    } catch (_) {/* локально уже сохранено */}
  }

  /// После входа объединяем локальное избранное с серверным
  Future<void> _syncFavorites() async {
    try {
      final server = await repo.favoriteIds();
      final localOnly = _favorites.difference(server);
      for (final id in localOnly) {
        await repo.setFavorite(id, true);
      }
      _favorites = {...server, ..._favorites};
      await _prefs.setStringList(_kFav, _favorites.toList());
      notifyListeners();
    } catch (_) {}
  }

  // ---------- недавно просмотренные ----------
  late List<String> _recent;
  List<String> get recentlyViewed => _recent;

  Future<void> markViewed(String id) async {
    _recent = [id, ..._recent.where((x) => x != id)].take(12).toList();
    await _prefs.setStringList(_kRecent, _recent);
    repo.incrementViews(id);
    notifyListeners();
  }

  // ---------- обучение: какие туры и подсказки уже показаны (хранится на устройстве) ----------
  late Set<String> _hints;
  bool hintSeen(String id) => _hints.contains(id);

  Future<void> markHint(String id) async {
    if (!_hints.add(id)) return;
    await _prefs.setStringList(_kHints, _hints.toList());
    notifyListeners();
  }

  /// «Показать обучение ещё раз» (Помощь)
  Future<void> resetHints() async {
    _hints.clear();
    await _prefs.setStringList(_kHints, const []);
    tourRequest++;
    notifyListeners();
  }

  /// Попросить показать тур (например, после первого объявления). Тур решает, какой показать.
  int tourRequest = 0;
  void requestTour() {
    tourRequest++;
    notifyListeners();
  }

  // ---------- сигнал «данные изменились» (новое объявление и т.п.) ----------
  int _dataVersion = 0;
  int get dataVersion => _dataVersion;
  void dataChanged() {
    _dataVersion++;
    notifyListeners();
    refreshToConfirm();
  }

  // ---------- «Ещё доступно?» — сколько объявлений ждут ответа (значок на «Профиль») ----------
  int _toConfirm = 0;
  int get listingsToConfirm => _toConfirm;

  Future<void> refreshToConfirm() async {
    final n = _user == null || _user!.isAdmin ? 0 : await repo.listingsToConfirm();
    if (n == _toConfirm) return;
    _toConfirm = n;
    notifyListeners();
  }

  /// Ответ одним нажатием
  Future<void> answerStillAvailable(String propertyId, bool available) async {
    await repo.answerStillAvailable(propertyId, available);
    dataChanged();
  }

  // ---------- сигнал для списка чатов ----------
  int _chatsVersion = 0;
  int get chatsVersion => _chatsVersion;
  void chatsChanged() {
    _chatsVersion++;
    notifyListeners();
  }

  // ---------- непрочитанные сообщения (значок «Chats») ----------
  int _unread = 0;
  int get unreadChats => _unread;

  /// Текст значка: 1…10, дальше «10+»
  String get unreadLabel => _unread > 10 ? '10+' : '$_unread';

  StreamSubscription<void>? _inboxSub;
  Timer? _unreadTimer;

  /// Вошёл / вышел — подписываемся на новые сообщения или всё выключаем
  void _watchUnread() {
    _inboxSub?.cancel();
    _unreadTimer?.cancel();
    if (_user == null) {
      _setUnread(0);
      return;
    }
    refreshUnread();
    refreshToConfirm();
    _inboxSub = repo.incomingMessages().listen((_) {
      // сообщение пришло — пересчитываем чуть позже (вдруг человек как раз в этом чате)
      Future.delayed(const Duration(milliseconds: 1200), () {
        refreshUnread();
        chatsChanged();
      });
    });
    // запасной вариант, если связь Realtime прервалась
    _unreadTimer = Timer.periodic(const Duration(seconds: 60), (_) => refreshUnread());
  }

  Future<void> refreshUnread() async {
    if (_user == null) return _setUnread(0);
    _setUnread(await repo.unreadCount());
  }

  /// Открыл переписку — она прочитана
  Future<void> markChatRead(String conversationId) async {
    await repo.markChatRead(conversationId);
    await refreshUnread();
  }

  void _setUnread(int n) {
    setAppBadge(n);
    if (n == _unread) return;
    _unread = n;
    notifyListeners();
  }

  @override
  void dispose() {
    _inboxSub?.cancel();
    _unreadTimer?.cancel();
    _sub?.cancel();
    super.dispose();
  }
}
