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
