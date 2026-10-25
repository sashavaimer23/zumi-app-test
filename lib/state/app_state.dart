import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../data/repository.dart';
import '../models/models.dart';

/// Общее состояние приложения: пользователь, избранное, недавно просмотренные.
class AppState extends ChangeNotifier {
  AppState(this.repo, this._prefs) {
    _favorites = (_prefs.getStringList(_kFav) ?? []).toSet();
    _recent = _prefs.getStringList(_kRecent) ?? [];
    _hints = (_prefs.getStringList(_kHints) ?? []).toSet();
    _user = repo.currentUser;
    _sub = repo.userChanges.listen((u) {
      _user = u;
      notifyListeners();
      if (u != null) _syncFavorites();
    });
    if (_user != null) _syncFavorites();
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
  }

  // ---------- сигнал для списка чатов ----------
  int _chatsVersion = 0;
  int get chatsVersion => _chatsVersion;
  void chatsChanged() {
    _chatsVersion++;
    notifyListeners();
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }
}
