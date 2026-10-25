import 'dart:async';
import 'dart:convert';
import 'dart:math' show Random;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/services.dart' show rootBundle;

import 'package:uuid/uuid.dart';

import '../models/models.dart';
import 'demo_data.dart';
import 'repository.dart';

/// Работает полностью в памяти. Нужен, чтобы приложение можно было
/// открыть и показать ещё до подключения Supabase.
class DemoRepository implements Repository {
  DemoRepository() {
    _areas = demoAreas.map(Area.fromMap).toList();
    _props = demoProperties.map((m) => Property.fromMap(Map<String, dynamic>.from(m))).toList();
  }

  static const _uuid = Uuid();
  late final List<Area> _areas;
  late final List<Property> _props;
  final Set<String> _favorites = {};
  final _userCtrl = StreamController<AppUser?>.broadcast();
  AppUser? _user;

  /// Все аккаунты этого демо (по id) — чтобы после выхода и входа всё сохранялось,
  /// а команда Zumi (вход с почтой со словом admin) могла одобрять проверки.
  final Map<String, AppUser> _known = {};

  void _setUser(AppUser u) {
    _known[u.id] = u;
    if (_user?.id == u.id) {
      _user = u;
      _userCtrl.add(_user);
    }
  }

  // чаты
  final Map<String, Conversation> _convs = {};
  final Map<String, List<ChatMessage>> _msgs = {};
  final Map<String, StreamController<List<ChatMessage>>> _msgCtrls = {};

  static const _limits = {'agent': 5, 'owner': 2};

  Future<void> _lag() => Future.delayed(const Duration(milliseconds: 250));

  @override
  bool get isDemo => true;

  // ---------------- авторизация ----------------
  @override
  AppUser? get currentUser => _user;

  @override
  Stream<AppUser?> get userChanges => _userCtrl.stream;

  @override
  Future<void> signIn({required String email, required String password}) async {
    await _lag();
    if (password.length < 6) throw AppException('Password must be at least 6 characters');
    // демо: email со словом admin открывает кабинет команды Zumi
    // демо: email со словом agent входит как агент, со словом admin — как команда Zumi
    final e = email.toLowerCase();
    final id = 'demo-${e.hashCode}';
    final known = _known[id];
    if (known == null) {
      final u = AppUser(
        id: id,
        email: email,
        fullName: email.split('@').first,
        // демо: «moderator» в почте — модератор команды, «admin» — владелец
        role: e.contains('admin') || e.contains('moderator') ? 'admin' : (e.contains('agent') ? 'agent' : 'owner'),
        teamLevel: e.contains('moderator') ? 'moderator' : (e.contains('admin') ? 'owner' : null),
        // демо: agent@test.com — агент с уже проверенной лицензией; другие «agent…» — без проверки
        licenceNo: e == 'agent@test.com' ? 'ZIEA/2019/0417' : null,
        licenceVerified: e == 'agent@test.com',
        createdAt: DateTime.now(),
      );
      _known[id] = u;
      if (!u.isAdmin) _newAccounts.add(id);
    }
    _user = _known[id];
    _userCtrl.add(_user);
  }

  @override
  Future<void> signUp({
    required String email,
    required String password,
    required String fullName,
    required String phone,
    required String role,
    bool termsAccepted = true,
    String? licenceNo,
    bool marketing = false,
  }) async {
    await _lag();
    if (password.length < 6) throw AppException('Password must be at least 6 characters');
    final u = AppUser(
      id: 'demo-${email.toLowerCase().hashCode}',
      email: email,
      fullName: fullName,
      phone: phone,
      role: email.toLowerCase().contains('admin') ? 'admin' : role,
      licenceNo: role == 'agent' && (licenceNo ?? '').trim().isNotEmpty ? licenceNo!.trim() : null,
      marketingEmail: marketing,
      marketingWhatsapp: marketing,
      createdAt: DateTime.now(),
    );
    _known[u.id] = u;
    if (!u.isAdmin) _newAccounts.add(u.id);
    if (u.licenceNo != null) {
      _licences.add(LicenceItem(userId: u.id, userName: u.fullName, licenceNo: u.licenceNo!));
    }
    _user = u;
    _userCtrl.add(_user);
  }

  @override
  Future<void> setMarketing(String channel, bool on) async {
    final u = _requireUser();
    _setUser(channel == 'whatsapp' ? u.copyWith(marketingWhatsapp: on) : u.copyWith(marketingEmail: on));
  }

  @override
  Future<void> refreshUser() async {
    final u = _user;
    if (u == null) return;
    _user = _known[u.id] ?? u;
    _userCtrl.add(_user);
  }

  @override
  Future<void> signOut() async {
    _user = null;
    _userCtrl.add(null);
  }

  @override
  Future<void> sendPasswordReset(String email) async {
    await _lag(); // демо: письмо не отправляется, код — 123456
  }

  @override
  Future<void> resetPasswordWithCode({required String email, required String code, required String newPassword}) async {
    await _lag();
    if (code.trim() != '123456') throw AppException('Wrong code. In demo mode the code is 123456');
    if (newPassword.length < 6) throw AppException('Password must be at least 6 characters');
    await signIn(email: email, password: newPassword);
  }

  @override
  Future<void> changePassword(String newPassword) async {
    _requireUser();
    await _lag();
    if (newPassword.length < 6) throw AppException('Password must be at least 6 characters');
  }

  @override
  Future<void> deleteAccount() async {
    final u = _requireUser();
    await _lag();
    _props.removeWhere((p) => p.ownerId == u.id);
    await signOut();
  }

  AppUser _requireUser() {
    final u = _user;
    if (u == null) throw AppException('Please sign in first', code: 'AUTH');
    return u;
  }

  // ---------------- поиск ----------------
  @override
  Future<List<Area>> areas() async => _areas;

  @override
  Future<List<Property>> search(SearchFilters f, {int limit = 30, int offset = 0}) async {
    await _lag();
    final list = _props.where(f.matches).toList();
    sortProperties(list, f.sort);
    return list.skip(offset).take(limit).toList();
  }

  @override
  Future<int> countListings(SearchFilters f) async => _props.where(f.matches).length;

  @override
  Future<List<double>> priceSamples(SearchFilters f) async {
    final probe = f.copy()
      ..minPrice = null
      ..maxPrice = null;
    return _props.where((p) => probe.matches(p) && p.currency == f.currency).map((p) => p.price).toList();
  }

  @override
  Future<Map<int, int>> areaCounts() async {
    final all = SearchFilters(city: '');
    final m = <int, int>{};
    for (final p in _props.where(all.matches)) {
      if (p.areaId != null) m[p.areaId!] = (m[p.areaId!] ?? 0) + 1;
    }
    return m;
  }

  @override
  Future<List<Property>> popular({String city = 'Lusaka', int limit = 8}) async {
    final list = _props.where(SearchFilters(city: city).matches).toList()
      ..sort((a, b) => b.viewsCount - a.viewsCount);
    return list.take(limit).toList();
  }

  @override
  Future<Property?> getProperty(String id) async {
    for (final p in _props) {
      if (p.id == id) return p;
    }
    return null;
  }

  @override
  Future<List<Property>> byIds(List<String> ids) async {
    final map = {for (final p in _props) p.id: p};
    return ids.map((id) => map[id]).whereType<Property>().toList();
  }

  @override
  Future<void> incrementViews(String id) async {
    // как на сервере: один человек — один просмотр в день, свои просмотры не считаются
    final p = await getProperty(id);
    if (p == null || p.ownerId == _user?.id) return;
    final key = '$id|${isoDay(DateTime.now())}|${_user?.id ?? 'guest'}';
    if (!_viewSeen.add(key)) return;
    final m = _viewsByDay.putIfAbsent(id, () => {});
    final day = isoDay(DateTime.now());
    m[day] = (m[day] ?? 0) + 1;
  }

  final Set<String> _viewSeen = {};
  final Map<String, Map<String, int>> _viewsByDay = {};

  @override
  Future<PriceStats> areaPriceStats({
    required int areaId,
    required DealType deal,
    required PropertyType type,
    int? bedrooms,
    String? rentPeriod,
    String currency = 'ZMW',
    String? excludeId,
  }) async {
    final prices = [
      for (final p in _props)
        if (p.status == 'active' &&
            p.areaId == areaId &&
            p.dealType == deal &&
            p.propertyType == type &&
            p.currency == currency &&
            p.id != excludeId &&
            (deal != DealType.rent || (p.rentPeriod ?? 'month') == (rentPeriod ?? 'month')) &&
            (bedrooms == null || type == PropertyType.land || ((p.bedrooms ?? 0) - bedrooms).abs() <= 1) &&
            p.price > 0)
          p.price,
    ]..sort();
    if (prices.length < 5) return PriceStats(prices.length);
    double q(double f) {
      final i = (prices.length - 1) * f;
      final lo = i.floor(), hi = i.ceil();
      return prices[lo] + (prices[hi] - prices[lo]) * (i - lo);
    }

    return PriceStats(prices.length, q(0.25), q(0.5), q(0.75));
  }

  @override
  Future<Map<String, ListingStats>> myListingAdvice() async {
    final u = _user;
    if (u == null) return const {};
    final out = <String, ListingStats>{};
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    for (final p in _props.where((p) => p.ownerId == u.id && (p.status == 'active' || p.status == 'pending'))) {
      final m = _viewsByDay[p.id] ?? const {};
      final days = <(DateTime, int, int)>[];
      for (var i = 13; i >= 0; i--) {
        final d = today.subtract(Duration(days: i));
        final contacts = _reveals.where((r) => r.$2 == p.id && isoDay(r.$3) == isoDay(d)).length +
            _convs.values.where((c) => c.propertyId == p.id && isoDay(c.lastMessageAt) == isoDay(d)).length;
        days.add((d, m[isoDay(d)] ?? 0, contacts));
      }
      final last7 = days.skip(7);
      final views7 = last7.fold<int>(0, (a, d) => a + d.$2);
      final contacts7 = last7.fold<int>(0, (a, d) => a + d.$3);
      final liveDays = today.difference(DateTime(p.createdAt.year, p.createdAt.month, p.createdAt.day)).inDays;
      final ps = p.areaId == null
          ? const PriceStats(0)
          : await areaPriceStats(
              areaId: p.areaId!, deal: p.dealType, type: p.propertyType, bedrooms: p.bedrooms,
              rentPeriod: p.rentPeriod, currency: p.currency, excludeId: p.id);
      final tips = <ListingTip>[];
      if (p.status == 'active') {
        final since = today.difference(p.confirmedAt ?? p.createdAt).inDays;
        if (since >= 50) tips.add(ListingTip('confirm', {'days_left': (60 - since).clamp(0, 60)}));
        if (liveDays >= 7 && views7 >= 30 && contacts7 == 0) tips.add(ListingTip('no_contacts', {'views': views7}));
        if (ps.enough && p.price > ps.p75! * 1.3) {
          tips.add(ListingTip('price_high', {'p25': ps.p25!.round(), 'p75': ps.p75!.round(), 'n': ps.n}));
        }
        if (ps.enough && p.price < ps.p25! * 0.5) {
          tips.add(ListingTip('price_low', {'p25': ps.p25!.round(), 'p75': ps.p75!.round(), 'n': ps.n}));
        }
        if (p.images.length < 5) tips.add(ListingTip('photos', {'photos': p.images.length}));
        if ((p.description ?? '').length < 150) tips.add(const ListingTip('description'));
        if (liveDays >= 7 && views7 < 10) tips.add(ListingTip('few_views', {'views': views7}));
        if (!p.propertyVerified && liveDays >= 3) tips.add(const ListingTip('verify_onsite'));
        if (tips.isEmpty && contacts7 >= 3) tips.add(ListingTip('doing_well', {'contacts': contacts7}));
      }
      out[p.id] = ListingStats(
        id: p.id, views7: views7, contacts7: contacts7, days: days, tips: tips.take(3).toList(),
      );
    }
    return out;
  }

  // ---------------- избранное ----------------
  @override
  Future<Set<String>> favoriteIds() async => {..._favorites};

  @override
  Future<void> setFavorite(String propertyId, bool value) async {
    value ? _favorites.add(propertyId) : _favorites.remove(propertyId);
  }

  // ---------------- мои объявления ----------------
  @override
  Future<Quota> myQuota() async {
    final u = _requireUser();
    final used = _props.where((p) => p.ownerId == u.id && (p.status == 'active' || p.status == 'draft')).length;
    return Quota(used, _limits[u.role] ?? 999);
  }

  @override
  Future<List<Property>> myListings() async {
    final u = _requireUser();
    return _props.where((p) => p.ownerId == u.id).toList()
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
  }

  /// Объявления, одобренные модератором (или опубликованные уже проверенным автором)
  final Set<String> _approved = {};
  int _approvedCount(String userId) => _props.where((p) => p.ownerId == userId && _approved.contains(p.id)).length;

  @override
  Future<Property> createListing(ListingDraft d) async {
    final u = _requireUser();
    if (u.isAdmin) {
      throw AppException('Team accounts do not post listings — use your personal Zumi account.', code: 'TEAM');
    }
    if (_requireLicence && u.isAgent && !u.licenceVerified) {
      throw AppException('Agents can publish listings after the Zumi team checks their ZIEA licence. '
          'Add your licence number in Profile → Get verified.', code: 'LICENCE');
    }
    final q = await myQuota();
    if (q.reached) throw AppException('Listing limit reached', code: 'LISTING_LIMIT_REACHED');
    await _lag();
    final id = _uuid.v4();
    final images = [
      for (var i = 0; i < d.photos.length; i++) MemoryImages.put('$id-$i', d.photos[i].bytes),
    ];
    final area = d.area;
    final p = Property(
      id: id,
      ownerId: u.id,
      title: d.title,
      description: d.description,
      dealType: d.dealType,
      propertyType: d.propertyType,
      price: d.price ?? 0,
      currency: d.currency,
      rentPeriod: d.dealType == DealType.rent ? d.rentPeriod : null,
      bedrooms: d.propertyType == PropertyType.land ? null : d.bedrooms,
      bathrooms: d.propertyType == PropertyType.land ? null : d.bathrooms,
      areaSqm: d.areaSqm,
      amenities: d.amenities.toList(),
      areaId: area?.id,
      areaName: area?.name,
      city: area?.city ?? 'Lusaka',
      lat: d.lat ?? area?.lat ?? -15.4167,
      lng: d.lng ?? area?.lng ?? 28.2833,
      images: images,
      listedBy: u.isAgent ? 'agent' : 'owner',
      contactName: u.fullName,
      contactPhone: d.contactPhone,
      createdAt: DateTime.now(),
      confirmedAt: DateTime.now(),
      ownerPhoneVerified: u.phoneVerified,
      ownerLicenceVerified: !u.isAgent || u.licenceVerified,
      ownerIdentityVerified: u.identityVerified,
      ownerAvatarUrl: u.avatarUrl,
      agencyName: u.agencyName,
      contactMode: u.contactMode,
      // первые 2 объявления нового человека сначала смотрит модератор
      status: u.isAdmin || _approvedCount(u.id) >= 2 ? 'active' : 'pending',
    );
    if (p.status == 'active') _approved.add(p.id);
    _props.insert(0, p);
    return p;
  }

  @override
  Future<Property> updateListing(String id, ListingDraft d) async {
    final u = _requireUser();
    final i = _props.indexWhere((p) => p.id == id && p.ownerId == u.id);
    if (i < 0) throw AppException('Listing not found');
    await _lag();
    final old = _props[i];
    final images = [
      for (var k = 0; k < d.photos.length; k++)
        d.photos[k].isExisting ? d.photos[k].url! : MemoryImages.put('$id-${DateTime.now().millisecondsSinceEpoch}-$k', d.photos[k].bytes),
    ];
    final area = d.area;
    final p = Property(
      id: id,
      ownerId: u.id,
      title: d.title,
      description: d.description,
      dealType: d.dealType,
      propertyType: d.propertyType,
      price: d.price ?? old.price,
      currency: d.currency,
      rentPeriod: d.dealType == DealType.rent ? d.rentPeriod : null,
      bedrooms: d.propertyType == PropertyType.land ? null : d.bedrooms,
      bathrooms: d.propertyType == PropertyType.land ? null : d.bathrooms,
      areaSqm: d.areaSqm,
      amenities: d.amenities.toList(),
      areaId: area?.id ?? old.areaId,
      areaName: area?.name ?? old.areaName,
      city: area?.city ?? old.city,
      lat: d.lat ?? area?.lat ?? old.lat,
      lng: d.lng ?? area?.lng ?? old.lng,
      status: old.status,
      images: images,
      listedBy: old.listedBy,
      contactName: u.fullName,
      contactPhone: d.contactPhone,
      viewsCount: old.viewsCount,
      createdAt: old.createdAt,
      confirmedAt: DateTime.now(),
      propertyVerified: old.propertyVerified,
      ownerPhoneVerified: u.phoneVerified,
      ownerLicenceVerified: !u.isAgent || u.licenceVerified,
      ownerIdentityVerified: u.identityVerified,
      ownerAvatarUrl: u.avatarUrl,
      agencyName: u.agencyName,
    );
    _props[i] = p;
    return p;
  }

  @override
  Future<void> setListingStatus(String id, String status) async {
    final i = _props.indexWhere((p) => p.id == id);
    if (i >= 0 && status == 'active' && _props[i].status != 'active' && (await myQuota()).reached) {
      throw AppException('Listing limit reached — buy an extra slot to publish again',
          code: 'LISTING_LIMIT_REACHED');
    }
    if (i < 0) return;
    // без одобрения модератора объявление снова уходит на проверку
    final s = status == 'active' && !_approved.contains(id) && _props[i].ownerId != null ? 'pending' : status;
    _props[i] = _props[i].copyWith(status: s);
  }

  @override
  Future<void> deleteListing(String id) async => _props.removeWhere((p) => p.id == id);

  // ---------------- ZumiCheck ----------------
  final Set<String> _reported = {};
  final Map<String, String> _verification = {}; // ключ: propertyId или 'identity'

  @override
  Future<void> reportListing(String propertyId, String reason, String? details) async {
    _checkNotBanned(_requireUser());
    await _lag();
    if (!_reported.add(propertyId)) throw AppException('You have already reported this listing');
  }

  /// Плашка Verified на моих объявлениях — по текущему статусу пользователя
  void _syncMyBadge() {
    final u = _user;
    if (u == null) return;
    for (var i = 0; i < _props.length; i++) {
      if (_props[i].ownerId == u.id) {
        _props[i] = _props[i].copyWith(
        ownerIdentityVerified: u.identityVerified,
        ownerAvatarUrl: u.avatarUrl,
        contactName: u.fullName,
      );
      }
    }
  }

  // В демо-режиме проверки одобряются сразу, чтобы можно было посмотреть весь путь
  @override
  Future<void> updateProfile({
    String? fullName,
    String? agencyName,
    String? bio,
    String? whatsapp,
    String? contactMode,
  }) async {
    final u = _requireUser();
    await _lag();
    _user = AppUser(
      id: u.id,
      email: u.email,
      fullName: fullName?.trim() ?? u.fullName,
      phone: u.phone,
      role: u.role,
      agencyName: agencyName == null ? u.agencyName : (agencyName.trim().isEmpty ? null : agencyName.trim()),
      phoneVerified: u.phoneVerified,
      idVerified: u.idVerified,
      licenceNo: u.licenceNo,
      licenceVerified: u.licenceVerified,
      avatarUrl: u.avatarUrl,
      bio: bio == null ? u.bio : (bio.trim().isEmpty ? null : bio.trim()),
      whatsapp: whatsapp == null ? u.whatsapp : (whatsapp.trim().isEmpty ? null : whatsapp.trim()),
      createdAt: u.createdAt,
      idStatus: u.idStatus,
      idNote: u.idNote,
      licenceNote: u.licenceNote,
      contactMode: contactMode ?? u.contactMode,
      phoneChannel: u.phoneChannel,
      emailVerified: u.emailVerified,
    );
    _known[u.id] = _user!;
    for (var i = 0; i < _props.length; i++) {
      if (_props[i].ownerId == u.id) _props[i] = _props[i].copyWith(contactMode: _user!.contactMode);
    }
    _syncMyBadge();
    _userCtrl.add(_user);
  }

  @override
  Future<void> uploadAvatar(PickedPhoto photo) async {
    final u = _requireUser();
    await _lag();
    final url = MemoryImages.put('avatar-${u.id}-${DateTime.now().millisecondsSinceEpoch}', photo.bytes);
    _setUser(u.copyWith(avatarUrl: url));
    _syncMyBadge();
  }

  @override
  Future<PublicProfile?> publicProfile(String userId) async {
    await _lag();
    final u = _user;
    if (u != null && u.id == userId) {
      return PublicProfile(
        id: u.id,
        role: u.role,
        fullName: u.fullName,
        agencyName: u.agencyName,
        avatarUrl: u.avatarUrl,
        bio: u.bio,
        hasWhatsapp: u.isAgent && (u.whatsapp ?? '').isNotEmpty,
        contactMode: u.contactMode,
        verified: u.identityVerified,
        phoneVerified: u.phoneVerified,
        licenceVerified: u.licenceVerified,
        memberSince: u.createdAt ?? DateTime.now(),
        activeListings: _props.where((p) => p.ownerId == u.id && p.status == 'active').length,
      );
    }
    if (userId.startsWith('demo:')) {
      final name = userId.substring(5);
      final mine = _props.where((p) => p.ownerId == null && p.contactName == name).toList();
      if (mine.isEmpty) return null;
      final agent = mine.first.listedBy == 'agent';
      return PublicProfile(
        id: userId,
        role: agent ? 'agent' : 'owner',
        fullName: name,
        agencyName: agent ? name : null,
        bio: agent
            ? 'Demo agency on Zumi. We help families find homes in Lusaka — viewings 7 days a week, '
                'honest prices and help with the lease.'
            : null,
        hasWhatsapp: agent,
        verified: mine.first.ownerIdentityVerified,
        phoneVerified: true,
        licenceVerified: agent,
        memberSince: DateTime(2026, 3),
        activeListings: mine.where((p) => p.status == 'active').length,
      );
    }
    return null;
  }

  @override
  Future<List<Property>> listingsBy(String userId) async {
    await _lag();
    final list = userId.startsWith('demo:')
        ? _props.where((p) => p.ownerId == null && p.contactName == userId.substring(5))
        : _props.where((p) => p.ownerId == userId);
    return list.where((p) => p.status == 'active').toList()..sort((a, b) => b.createdAt.compareTo(a.createdAt));
  }

  @override
  Future<void> submitIdentity({
    required String docType,
    required PickedPhoto document,
    required PickedPhoto selfie,
  }) async {
    final u = _requireUser();
    await _lag();
    // как на сервере: заявка уходит команде Zumi и ждёт проверки
    _vQueue.insert(
      0,
      VerificationItem(
        id: _uuid.v4(),
        userId: u.id,
        userName: u.fullName,
        userRole: u.role,
        kind: 'identity',
        docType: docType,
        docPaths: [
          MemoryImages.put('doc-${u.id}-${DateTime.now().millisecondsSinceEpoch}', document.bytes),
          MemoryImages.put('selfie-${u.id}-${DateTime.now().millisecondsSinceEpoch}', selfie.bytes),
        ],
        createdAt: DateTime.now(),
      ),
    );
    _setUser(u.copyWith(idStatus: 'pending'));
  }

  @override
  Future<void> submitAgentLicence(String licenceNo) async {
    final u = _requireUser();
    await _lag();
    _licences.removeWhere((l) => l.userId == u.id);
    _licences.add(LicenceItem(userId: u.id, userName: u.fullName, licenceNo: licenceNo.trim()));
    _setUser(u.copyWith(licenceNo: licenceNo.trim(), licenceVerified: false, clearLicence: false, licenceNote: ''));
  }

  @override
  Future<void> requestVerification({
    required String kind,
    String? propertyId,
    required List<PickedPhoto> docs,
    String? note,
  }) async {
    _requireUser();
    await _lag();
    _verification['$kind:${propertyId ?? ''}'] = 'pending';
  }

  @override
  Future<String?> verificationStatus({required String kind, String? propertyId}) async {
    final u = _user;
    if (u == null) return null;
    if (kind == 'identity' && propertyId == null) return u.idVerified ? 'approved' : u.idStatus;
    return _verification['$kind:${propertyId ?? ''}'];
  }

  @override
  Future<PropertyCheckResult> submitPropertyCheck(
    String propertyId,
    List<PickedPhoto> photos,
    double lat,
    double lng,
  ) async {
    _requireUser();
    if (photos.length < 3) throw AppException('Please take at least 3 photos at the property');
    await _lag();
    // В демо-режиме проверка расстояния не выполняется — объект считается подтверждённым
    final i = _props.indexWhere((p) => p.id == propertyId);
    if (i >= 0) _props[i] = _props[i].copyWith(propertyVerified: true);
    _verification['property:$propertyId'] = 'approved';
    return const PropertyCheckResult(true, 0);
  }

  @override
  Future<bool> sendCode(String channel, String destination) async {
    final u = _requireUser();
    await _lag();
    if (channel != 'email' && _phoneTaken(destination, u.id)) {
      throw AppException('This number is already confirmed on another Zumi account. '
          'One number can belong to one account — sign in to that account or contact support.', code: 'PHONE_TAKEN');
    }
    return true; // демо: код всегда 123456, ничего не отправляется
  }

  /// «+260 97 123 4567» и «0971234567» — один номер
  static String _normPhone(String? p) {
    final d = (p ?? '').replaceAll(RegExp(r'[^0-9]'), '');
    return RegExp(r'^0\d{9}$').hasMatch(d) ? '260${d.substring(1)}' : d;
  }

  bool _phoneTaken(String phone, String uid) => _known.values.any(
      (k) => k.id != uid && k.phoneVerified && _normPhone(k.phone) == _normPhone(phone) && _normPhone(phone).isNotEmpty);

  bool _otpTestMode = true;
  bool _requireLicence = false;

  @override
  Future<void> verifyCode(String channel, String destination, String code) async {
    final u = _requireUser();
    await _lag();
    if (code.trim() != '123456') throw AppException('Wrong code. In test mode the code is 123456');
    if (channel != 'email' && _phoneTaken(destination, u.id)) {
      throw AppException('This number is already confirmed on another Zumi account.', code: 'PHONE_TAKEN');
    }
    if (channel == 'email') {
      _setUser(u.copyWith(emailVerified: true));
    } else {
      _setUser(u.copyWith(phone: destination, phoneVerified: true, phoneChannel: channel));
      _syncMyBadge();
    }
  }

  /// Кто смотрел номера: (кто, объявление, когда)
  final List<(String, String, DateTime)> _reveals = [];

  void _checkNotBanned(AppUser u) {
    if (_bannedAccounts.contains(u.id)) {
      throw AppException('Your account is blocked. Please contact Zumi support.', code: 'BLOCKED');
    }
  }

  @override
  Future<String> revealPhone(String propertyId) async {
    final u = _requireUser();
    _checkNotBanned(u);
    await _lag();
    final p = await getProperty(propertyId);
    if (p == null) throw AppException('Listing not found');
    if (p.ownerId == u.id) return p.contactPhone ?? '';
    if (!u.phoneVerified) throw AppException('Confirm your phone to see numbers', code: 'PHONE_NOT_VERIFIED');
    if (p.chatOnly) throw AppException('This author prefers chat — send a message instead', code: 'CHAT_ONLY');
    if ((p.contactPhone ?? '').isEmpty) throw AppException('No phone number in this listing — use chat');
    final dayAgo = DateTime.now().subtract(const Duration(days: 1));
    final mine = _reveals.where((r) => r.$1 == u.id && r.$3.isAfter(dayAgo));
    if (!mine.any((r) => r.$2 == propertyId)) {
      if (mine.length >= 15) {
        throw AppException('You have seen 15 numbers today. Please use chat or try again tomorrow.', code: 'LIMIT');
      }
      _reveals.add((u.id, propertyId, DateTime.now()));
      _bumpCampaigns(propertyId, call: true);
    }
    return p.contactPhone!;
  }

  @override
  Future<String> revealAgentWhatsapp(String agentId) async {
    final u = _requireUser();
    _checkNotBanned(u);
    await _lag();
    final pr = await publicProfile(agentId);
    if (pr == null || !pr.isAgent) throw AppException('Agent not found');
    final own = agentId == u.id;
    if (!own && !u.phoneVerified) throw AppException('Confirm your phone to see numbers', code: 'PHONE_NOT_VERIFIED');
    if (!own && pr.contactMode == 'chat') {
      throw AppException('This agent prefers chat — send a message instead', code: 'CHAT_ONLY');
    }
    if (!pr.hasWhatsapp) throw AppException('No WhatsApp number — use chat');
    final number = own ? (u.whatsapp ?? '') : '+260 97 000 0000';
    if (!own) {
      final dayAgo = DateTime.now().subtract(const Duration(days: 1));
      final mine = _reveals.where((r) => r.$1 == u.id && r.$3.isAfter(dayAgo));
      if (!mine.any((r) => r.$2 == 'agent:$agentId')) {
        if (mine.length >= 15) {
          throw AppException('You have seen 15 numbers today. Please use chat or try again tomorrow.', code: 'LIMIT');
        }
        _reveals.add((u.id, 'agent:$agentId', DateTime.now()));
      }
    }
    return number;
  }

  @override
  Future<String?> myListingPhone(String propertyId) async {
    final p = await getProperty(propertyId);
    return p != null && p.ownerId == _user?.id ? p.contactPhone : null;
  }

  @override
  Future<void> confirmListing(String propertyId) async {
    final i = _props.indexWhere((p) => p.id == propertyId);
    if (i >= 0) _props[i] = _props[i].copyWith(confirmedAt: DateTime.now());
  }

  // ---------------- поддержка, отзывы, кабинет (демо) ----------------
  DateTime _ago(int minutes) => DateTime.now().subtract(Duration(minutes: minutes));

  late final List<SupportTicket> _tickets = [
    SupportTicket(
      id: 't1', userId: 'u-mwila', userName: 'Mwila Banda', category: 'scam',
      subject: 'Agent asked me to pay before viewing', status: 'open',
      lastMessage: 'He wants K2,000 "booking fee" by Airtel Money before showing the house.',
      lastMessageAt: _ago(25),
    ),
    SupportTicket(
      id: 't2', userId: 'u-chanda', userName: 'Chanda Phiri', category: 'problem',
      subject: 'Photos do not upload', status: 'open',
      lastMessage: 'Step 3 keeps spinning when I add photos from my gallery.', lastMessageAt: _ago(140),
    ),
    SupportTicket(
      id: 't3', userId: 'u-joseph', userName: 'Joseph Tembo', category: 'account',
      subject: 'How do I become Verified?', status: 'answered',
      lastMessage: 'Open Profile → Get the Verified badge, it takes 3 minutes.', lastMessageAt: _ago(60 * 26),
    ),
  ];

  late final Map<String, List<SupportMessage>> _ticketMsgs = {
    't1': [SupportMessage(id: 'm1', senderId: 'u-mwila', isStaff: false, createdAt: _ago(25),
        body: 'He wants K2,000 "booking fee" by Airtel Money before showing the house.')],
    't2': [SupportMessage(id: 'm2', senderId: 'u-chanda', isStaff: false, createdAt: _ago(140),
        body: 'Step 3 keeps spinning when I add photos from my gallery.')],
    't3': [
      SupportMessage(id: 'm3', senderId: 'u-joseph', isStaff: false, createdAt: _ago(60 * 27),
          body: 'How do I get the Verified badge on my listings?'),
      SupportMessage(id: 'm4', senderId: 'staff', isStaff: true, createdAt: _ago(60 * 26),
          body: 'Open Profile → Get the Verified badge, it takes 3 minutes.'),
    ],
  };
  final Map<String, StreamController<List<SupportMessage>>> _ticketCtrls = {};

  late final List<Review> _reviews = [
    Review(id: 'r1', targetId: 'demo:Zumi Realty', authorId: 'u-mwila', authorName: 'Mwila B.', rating: 5,
        body: 'Very professional, showed us 3 houses in one day and helped with the lease.', createdAt: _ago(60 * 24 * 3)),
    Review(id: 'r2', targetId: 'demo:Zumi Realty', authorId: 'u-chanda', authorName: 'Chanda P.', rating: 4,
        body: 'Good agent, answered quickly on WhatsApp.', createdAt: _ago(60 * 24 * 9)),
    Review(id: 'r3', targetId: 'demo:Private owner', authorId: 'u-joseph', authorName: 'Joseph T.', rating: 2,
        body: 'The house was not as in the photos. This person is a liar!!!', flagsCount: 2, createdAt: _ago(60 * 5)),
  ];

  late final List<VerificationItem> _vQueue = [
    VerificationItem(id: 'v1', userId: 'u-chanda', userName: 'Chanda Phiri', userRole: 'owner', kind: 'identity',
        docType: 'nrc', docPaths: const ['asset:p6.jpg', 'asset:n1.jpg'], createdAt: _ago(50)),
    VerificationItem(id: 'v2', userId: 'u-joseph', userName: 'Joseph Tembo', userRole: 'agent', kind: 'identity',
        docType: 'passport', docPaths: const ['asset:p2.jpg', 'asset:n3.jpg'], createdAt: _ago(180)),
    VerificationItem(id: 'v3', userId: 'u-mwila', userName: 'Mwila Banda', userRole: 'owner', kind: 'ownership',
        docPaths: const ['asset:p4.jpg'], propertyTitle: 'Starter house in New Kasama', note: 'Title deed attached',
        createdAt: _ago(300)),
  ];
  final List<VerificationItem> _vDone = [];

  final List<LicenceItem> _licences = [
    const LicenceItem(userId: 'u-joseph', userName: 'Joseph Tembo', licenceNo: 'ZIEA/2024/0417'),
  ];

  late final List<ReportItem> _reports = [
    ReportItem(id: 'rep1', propertyId: demoProperties[14]['id'] as String, reason: 'asked_prepayment',
        details: 'Asked for K1,500 viewing fee by mobile money.', reporterName: 'Mwila Banda',
        propertyTitle: demoProperties[14]['title'] as String, propertyStatus: 'active',
        propertyCover: (demoProperties[14]['image_urls'] as List).first as String,
        ownerName: 'Private owner', totalReports: 2, createdAt: _ago(35)),
    ReportItem(id: 'rep2', propertyId: demoProperties[9]['id'] as String, reason: 'not_available',
        details: 'Owner said it was rented 2 months ago.', reporterName: 'Chanda Phiri',
        propertyTitle: demoProperties[9]['title'] as String, propertyStatus: 'active',
        propertyCover: (demoProperties[9]['image_urls'] as List).first as String,
        ownerName: 'Private owner', createdAt: _ago(60 * 7)),
  ];

  final List<AuditEntry> _audit = [];

  void _log(String action, String type, String target, [String? note]) => _audit.insert(
        0,
        AuditEntry(action: action, targetType: type, targetId: target, note: note,
            adminName: _user?.fullName, createdAt: DateTime.now()),
      );

  AppUser _requireAdmin() {
    final u = _requireUser();
    if (!u.isAdmin) throw AppException('Only the Zumi team can do this');
    return u;
  }

  /// Владелец: статистика, реклама, деньги, настройки, роли, журнал
  AppUser _requireOwner() {
    final u = _requireAdmin();
    if (!u.isOwner) throw AppException('Only the Zumi owner can do this', code: 'OWNER_ONLY');
    return u;
  }

  @override
  Future<List<SupportTicket>> myTickets() async {
    final u = _requireUser();
    return _tickets.where((t) => t.userId == u.id).toList();
  }

  @override
  Future<String> openTicket({
    required String category,
    required String subject,
    required String message,
    String? helpArticleId,
  }) async {
    final u = _requireUser();
    await _lag();
    final id = _uuid.v4();
    _tickets.insert(0, SupportTicket(id: id, userId: u.id, userName: u.fullName, category: category,
        subject: subject, status: 'open', lastMessage: message, lastMessageAt: DateTime.now()));
    _ticketMsgs[id] = [SupportMessage(id: _uuid.v4(), senderId: u.id, isStaff: false, body: message,
        createdAt: DateTime.now())];
    return id;
  }

  StreamController<List<SupportMessage>> _tctrl(String id) =>
      _ticketCtrls.putIfAbsent(id, () => StreamController<List<SupportMessage>>.broadcast());

  @override
  Stream<List<SupportMessage>> ticketMessages(String ticketId) async* {
    yield List.of(_ticketMsgs[ticketId] ?? const []);
    yield* _tctrl(ticketId).stream;
  }

  @override
  Future<void> sendTicketMessage(String ticketId, String body, {bool asStaff = false}) async {
    final u = asStaff ? _requireAdmin() : _requireUser();
    final list = _ticketMsgs.putIfAbsent(ticketId, () => []);
    list.add(SupportMessage(id: _uuid.v4(), senderId: u.id, isStaff: asStaff, body: body, createdAt: DateTime.now()));
    final i = _tickets.indexWhere((t) => t.id == ticketId);
    if (i >= 0) {
      final t = _tickets[i];
      _tickets[i] = SupportTicket(id: t.id, userId: t.userId, userName: t.userName, category: t.category,
          subject: t.subject, status: asStaff ? 'answered' : 'open', lastMessage: body, lastMessageAt: DateTime.now());
    }
    if (asStaff) _log('reply', 'ticket', ticketId);
    _tctrl(ticketId).add(List.of(list));
  }

  @override
  Future<List<Review>> reviewsAbout(String userId) async =>
      _reviews.where((r) => r.targetId == userId && r.status == 'published').toList();

  @override
  Future<Rating> ratingOf(String userId) async {
    final list = await reviewsAbout(userId);
    if (list.isEmpty) return const Rating(0, 0);
    final avg = list.map((r) => r.rating).reduce((a, b) => a + b) / list.length;
    return Rating(double.parse(avg.toStringAsFixed(1)), list.length);
  }

  @override
  Future<void> writeReview({required String targetId, required int rating, String? body, String? propertyId}) async {
    final u = _requireUser();
    _checkNotBanned(u);
    if (targetId == u.id) throw AppException('You cannot review yourself');
    if (_reviews.any((r) => r.targetId == targetId && r.authorId == u.id)) {
      throw AppException('You have already reviewed this person');
    }
    await _lag();
    _reviews.insert(0, Review(id: _uuid.v4(), targetId: targetId, authorId: u.id, authorName: u.fullName,
        rating: rating, body: body, createdAt: DateTime.now()));
  }

  @override
  Future<void> flagReview(String reviewId) async {
    _requireUser();
    final i = _reviews.indexWhere((r) => r.id == reviewId);
    if (i < 0) return;
    final n = _reviews[i].flagsCount + 1;
    _reviews[i] = _reviews[i].copyWith(flagsCount: n, status: n >= 3 ? 'hidden' : null);
  }

  @override
  Future<AdminStats> adminStats() async {
    _requireAdmin();
    return AdminStats(
      accounts: _newAccounts.length + _demoNewAccounts.where((a) => a.reviewedAt == null).length,
      listingsNew: _props.where((p) => p.status == 'pending').length,
      campaignsNew: _campaigns.where((c) => c.phase == 'review').length,
      helpUnhelpful: _myVotes.values.where((v) => !v.$1).length +
          _otherVotes.values.fold<int>(0, (a, l) => a + l.where((v) => !v.$1).length),
      otpTestMode: _otpTestMode,
      requireLicence: _requireLicence,
      idChecks: _vQueue.where((v) => v.kind == 'identity').length,
      ownership: _vQueue.where((v) => v.kind == 'ownership').length,
      licences: _licences.length,
      reports: _reports.where((r) => r.status == 'new').length,
      tickets: _tickets.where((t) => t.status == 'open').length,
      reviews: _reviews.where((r) => r.flagsCount > 0 && r.status == 'published').length,
      listings: _props.where((p) => p.status == 'active').length,
      users: 128 + _known.length,
    );
  }

  @override
  Future<List<VerificationItem>> adminVerificationQueue({String status = 'pending'}) async {
    _requireAdmin();
    await _lag();
    return status == 'pending' ? List.of(_vQueue) : _vDone.where((v) => v.status == status).toList();
  }

  @override
  Future<List<String>> adminDocUrls(List<String> paths) async => paths;

  @override
  Future<void> adminReviewVerification(String id, bool approve, {String? note}) async {
    _requireAdmin();
    final i = _vQueue.indexWhere((v) => v.id == id);
    if (i < 0) return;
    final v = _vQueue.removeAt(i);
    _vDone.insert(0, VerificationItem(id: v.id, userId: v.userId, userName: v.userName, userRole: v.userRole,
        kind: v.kind, docType: v.docType, status: approve ? 'approved' : 'rejected', reviewerNote: note,
        propertyTitle: v.propertyTitle, createdAt: v.createdAt));
    _log(approve ? 'approve' : 'reject', v.kind, v.userName ?? v.id, note);
    final target = _known[v.userId];
    if (target != null && v.kind == 'identity') {
      _setUser(approve
          ? target.copyWith(idVerified: true, idStatus: 'approved')
          : target.copyWith(idStatus: 'rejected', idNote: note ?? ''));
      _syncBadgeFor(v.userId);
    }
  }

  /// Плашка Verified на объявлениях конкретного человека
  void _syncBadgeFor(String userId) {
    final u = _known[userId];
    if (u == null) return;
    for (var i = 0; i < _props.length; i++) {
      if (_props[i].ownerId == userId) {
        _props[i] = _props[i].copyWith(
          ownerIdentityVerified: u.identityVerified,
          ownerLicenceVerified: !u.isAgent || u.licenceVerified,
        );
      }
    }
  }

  // ---------------- новые аккаунты (кабинет) ----------------
  final List<String> _newAccounts = [];
  final Set<String> _reviewedAccounts = {};
  final Set<String> _bannedAccounts = {};
  late final List<AccountItem> _demoNewAccounts = [
    AccountItem(id: 'u-chanda', fullName: 'Chanda Phiri', email: 'chanda.phiri@gmail.com', role: 'owner',
        phone: '+260 97 555 0101', phoneVerified: true, idStatus: 'pending', createdAt: _ago(55)),
    AccountItem(id: 'u-joseph', fullName: 'Joseph Tembo', email: 'joseph@lusakahomes.co.zm', role: 'agent',
        phone: '+260 96 555 0202', phoneVerified: true, idStatus: 'pending', licenceNo: 'ZIEA/2024/0417',
        listings: 3, createdAt: _ago(200)),
    AccountItem(id: 'u-new', fullName: 'Grace Mulenga', email: 'grace.m@yahoo.com', role: 'owner',
        createdAt: _ago(12)),
  ];

  AccountItem _accountOf(AppUser u) => AccountItem(
        id: u.id,
        fullName: u.fullName,
        email: u.email,
        role: u.role,
        phone: u.phone,
        avatarUrl: u.avatarUrl,
        phoneVerified: u.phoneVerified,
        idStatus: u.idVerified ? 'approved' : u.idStatus,
        licenceNo: u.licenceNo,
        licenceVerified: u.licenceVerified,
        listings: _props.where((p) => p.ownerId == u.id).length,
        createdAt: u.createdAt ?? DateTime.now(),
        reviewedAt: _reviewedAccounts.contains(u.id) ? DateTime.now() : null,
        banned: _bannedAccounts.contains(u.id),
      );

  @override
  Future<List<AccountItem>> adminAccounts({bool onlyNew = true}) async {
    _requireAdmin();
    await _lag();
    final real = [
      for (final id in _known.keys)
        if (!_known[id]!.isAdmin && (!onlyNew || _newAccounts.contains(id))) _accountOf(_known[id]!),
    ];
    final demo = _demoNewAccounts.where((a) => !onlyNew || a.reviewedAt == null);
    return [...real, ...demo]..sort((a, b) => b.createdAt.compareTo(a.createdAt));
  }

  @override
  Future<void> adminReviewAccount(String userId, String action, {String? note}) async {
    _requireAdmin();
    _newAccounts.remove(userId);
    _reviewedAccounts.add(userId);
    if (action == 'ban') {
      _bannedAccounts.add(userId);
      for (var i = 0; i < _props.length; i++) {
        if (_props[i].ownerId == userId && _props[i].status == 'active') {
          _props[i] = _props[i].copyWith(status: 'archived');
        }
      }
    }
    final i = _demoNewAccounts.indexWhere((a) => a.id == userId);
    if (i >= 0) {
      final a = _demoNewAccounts[i];
      _demoNewAccounts[i] = AccountItem(id: a.id, fullName: a.fullName, email: a.email, role: a.role, phone: a.phone,
          phoneVerified: a.phoneVerified, idStatus: a.idStatus, licenceNo: a.licenceNo, listings: a.listings,
          createdAt: a.createdAt, reviewedAt: DateTime.now(), banned: action == 'ban');
    }
    _log(action, 'account', _known[userId]?.fullName ?? (i >= 0 ? _demoNewAccounts[i].fullName ?? userId : userId), note);
  }

  @override
  Future<List<LicenceItem>> adminLicenceQueue() async {
    _requireAdmin();
    return List.of(_licences);
  }

  @override
  Future<void> adminReviewLicence(String userId, bool approve, {String? note}) async {
    _requireAdmin();
    final l = _licences.where((x) => x.userId == userId).toList();
    _licences.removeWhere((x) => x.userId == userId);
    final target = _known[userId];
    if (target != null) {
      _setUser(approve
          ? target.copyWith(licenceVerified: true, licenceNote: '')
          : target.copyWith(clearLicence: true, licenceVerified: false, licenceNote: note ?? 'Licence could not be confirmed'));
      _syncBadgeFor(userId);
    }
    _log(approve ? 'approve' : 'reject', 'licence', l.isEmpty ? userId : '${l.first.userName} ${l.first.licenceNo}', note);
  }

  @override
  Future<List<ReportItem>> adminReports({bool onlyNew = true}) async {
    _requireAdmin();
    await _lag();
    return _reports.where((r) => !onlyNew || r.status == 'new').toList();
  }

  @override
  Future<void> adminResolveReport(String id, String action, {String? note}) async {
    _requireAdmin();
    final i = _reports.indexWhere((r) => r.id == id);
    if (i < 0) return;
    final r = _reports[i];
    if (action != 'dismiss') await setListingStatus(r.propertyId, 'archived');
    _reports[i] = ReportItem(id: r.id, propertyId: r.propertyId, reason: r.reason, details: r.details,
        status: action == 'dismiss' ? 'reviewed' : 'action_taken', reporterName: r.reporterName,
        propertyTitle: r.propertyTitle, propertyStatus: action == 'dismiss' ? r.propertyStatus : 'archived',
        propertyCover: r.propertyCover, ownerName: r.ownerName, totalReports: r.totalReports, createdAt: r.createdAt);
    _log(action, 'report', r.propertyTitle ?? id, note);
  }

  @override
  Future<void> adminRestoreListing(String propertyId) async {
    _requireAdmin();
    final i = _props.indexWhere((p) => p.id == propertyId);
    if (i >= 0) _props[i] = _props[i].copyWith(status: 'active');
    _log('restore', 'listing', propertyId);
  }

  @override
  Future<List<SupportTicket>> adminTickets({String? status}) async {
    _requireAdmin();
    return _tickets.where((t) => status == null || t.status == status).toList()
      ..sort((a, b) => b.lastMessageAt.compareTo(a.lastMessageAt));
  }

  @override
  Future<void> adminSetTicketStatus(String id, String status) async {
    _requireAdmin();
    final i = _tickets.indexWhere((t) => t.id == id);
    if (i < 0) return;
    final t = _tickets[i];
    _tickets[i] = SupportTicket(id: t.id, userId: t.userId, userName: t.userName, category: t.category,
        subject: t.subject, status: status, lastMessage: t.lastMessage, lastMessageAt: t.lastMessageAt);
    _log(status, 'ticket', t.subject);
  }

  @override
  Future<List<Review>> adminReviews({bool flaggedOnly = false}) async {
    _requireAdmin();
    return _reviews.where((r) => !flaggedOnly || r.flagsCount > 0).toList();
  }

  @override
  Future<void> adminModerateReview(String id, String action, {String? reply}) async {
    _requireAdmin();
    final i = _reviews.indexWhere((r) => r.id == id);
    if (i < 0) return;
    _reviews[i] = switch (action) {
      'hide' => _reviews[i].copyWith(status: 'hidden'),
      'publish' => _reviews[i].copyWith(status: 'published', flagsCount: 0),
      _ => _reviews[i].copyWith(zumiReply: reply),
    };
    _log(action, 'review', _reviews[i].authorName ?? id, reply);
  }

  @override
  Future<List<AuditEntry>> adminAudit() async {
    _requireOwner();
    return List.of(_audit);
  }

  // ---------------- продвижение (демо: всё в памяти) ----------------
  final List<Campaign> _campaigns = [];
  final Map<String, Map<String, (int, int, int, int)>> _campStats = {}; // id → день → (показы, клики, звонки, сообщения)

  /// +1 звонок или сообщение у идущих кампаний этого объявления
  void _bumpCampaigns(String propertyId, {bool call = false}) {
    final day = isoDay(DateTime.now());
    for (final c in _campaigns.where((c) => c.propertyId == propertyId && c.isLive)) {
      final m = _campStats.putIfAbsent(c.id, () => {});
      final (v, k, calls, msgs) = m[day] ?? (0, 0, 0, 0);
      m[day] = call ? (v, k, calls + 1, msgs) : (v, k, calls, msgs + 1);
    }
  }

  @override
  Future<List<Campaign>> myCampaigns() async {
    final u = _requireUser();
    await _lag();
    return _campaigns.where((c) => c.ownerId == u.id).toList()..sort((a, b) => b.createdAt.compareTo(a.createdAt));
  }

  @override
  Future<Campaign> createCampaign(CampaignDraft d) async {
    final u = _requireUser();
    if (!u.isAgent && !u.isAdmin) throw AppException('Promotion campaigns are for agents');
    if (u.isAgent && !u.licenceVerified) {
      throw AppException('Promotion is available after the Zumi team checks your ZIEA licence.', code: 'LICENCE');
    }
    await _lag();
    final live = _campaigns.where((c) => c.ownerId == u.id && c.status == 'active' && c.phase != 'finished').length;
    if (live >= 3) {
      throw AppException('You can run up to 3 campaigns at the same time. Stop one to start a new one.');
    }
    final id = _uuid.v4();
    // своя картинка, ссылка или чужое название — сначала проверка командой
    final names = {u.fullName, u.agencyName}.whereType<String>().map((n) => n.trim().toLowerCase());
    final plain = d.image == null && d.contact.trim().isEmpty && names.contains(d.advertiser.trim().toLowerCase());
    final c = Campaign(
      id: id,
      reviewStatus: plain || u.isAdmin ? 'approved' : 'pending',
      ownerId: u.id,
      propertyId: d.property!.id,
      advertiser: d.advertiser.trim(),
      contact: d.contact.trim().isEmpty ? null : d.contact.trim(),
      placement: d.placement,
      imageUrl: d.image == null ? null : MemoryImages.put('campaign-$id', d.image!),
      startsOn: d.startsOn!,
      endsOn: d.endsOn!,
      createdAt: DateTime.now(),
    );
    _campaigns.add(c);
    return c;
  }

  @override
  Future<void> setCampaignStatus(String id, String status) async {
    final i = _campaigns.indexWhere((c) => c.id == id);
    if (i < 0) return;
    if (_campaigns[i].status == 'stopped' && status != 'stopped') {
      throw AppException('A stopped campaign cannot be started again');
    }
    _campaigns[i] = _campaigns[i].copyWith(status: status);
  }

  @override
  Future<CampaignStats> campaignStats(String id) async {
    final m = _campStats[id] ?? const {};
    final keys = m.keys.toList()..sort();
    return CampaignStats([
      for (final k in keys) CampaignDay(DateTime.parse(k), m[k]!.$1, m[k]!.$2, m[k]!.$3, m[k]!.$4),
    ]);
  }

  @override
  Future<List<(Campaign, Property)>> liveCampaigns(String placement, {SearchFilters? filters}) async {
    final out = <(Campaign, Property)>[];
    for (final c in _campaigns) {
      if (c.placement != placement || !c.isLive) continue;
      final p = await getProperty(c.propertyId);
      if (p != null && campaignFits(p, filters)) out.add((c, p));
    }
    return out..shuffle();
  }

  /// Показ/клик считается один раз в день с человека (как на сервере)
  final Set<String> _seenEvents = {};
  bool _firstToday(String id, String kind) =>
      _seenEvents.add('$id|$kind|${isoDay(DateTime.now())}|${_user?.id ?? 'guest'}');

  @override
  Future<void> logCampaignEvent(String campaignId, String kind) async {
    final i = _campaigns.indexWhere((c) => c.id == campaignId);
    if (i < 0 || !_campaigns[i].isLive) return;
    if (!_firstToday(campaignId, kind)) return;
    final day = isoDay(DateTime.now());
    final m = _campStats.putIfAbsent(campaignId, () => {});
    final (v, c, calls, msgs) = m[day] ?? (0, 0, 0, 0);
    m[day] = kind == 'click' ? (v, c + 1, calls, msgs) : (v + 1, c, calls, msgs);
  }

  // ---------------- реклама (демо) ----------------
  final List<Ad> _ads = [];
  final Map<String, Map<String, (int, int)>> _adStats = {};

  @override
  Future<List<Ad>> liveAds(String placement) async =>
      _ads.where((a) => a.placement == placement && a.isLive).toList()..shuffle();

  @override
  Future<void> logAdEvent(String adId, String kind) async {
    final i = _ads.indexWhere((a) => a.id == adId);
    if (i < 0 || !_ads[i].isLive) return;
    if (!_firstToday(adId, kind)) return;
    final m = _adStats.putIfAbsent(adId, () => {});
    final day = isoDay(DateTime.now());
    final (v, c) = m[day] ?? (0, 0);
    m[day] = kind == 'click' ? (v, c + 1) : (v + 1, c);
  }

  @override
  Future<List<Ad>> adminAds() async {
    _requireOwner();
    await _lag();
    return List.of(_ads)..sort((a, b) => b.createdAt.compareTo(a.createdAt));
  }

  @override
  Future<Ad> adminSaveAd(AdDraft d, {required bool launch}) async {
    _requireOwner();
    await _lag();
    final id = d.id ?? _uuid.v4();
    final today = DateTime.now();
    final ad = Ad(
      id: id,
      advertiser: d.advertiser.trim(),
      title: d.title.trim(),
      targetType: d.targetType,
      target: d.target.trim(),
      placement: d.placement,
      imageUrl: d.image != null ? MemoryImages.put('ad-$id-${today.millisecondsSinceEpoch}', d.image!) : d.imageUrl,
      startsOn: d.startsOn ?? today,
      endsOn: d.endsOn ?? today.add(const Duration(days: 6)),
      status: launch ? 'active' : 'draft',
      createdAt: today,
    );
    _ads.removeWhere((a) => a.id == id);
    _ads.add(ad);
    _log(launch ? 'launch' : 'draft', 'ad', ad.title);
    return ad;
  }

  @override
  Future<void> adminSetAdStatus(String id, String status) async {
    _requireOwner();
    final i = _ads.indexWhere((a) => a.id == id);
    if (i >= 0) _ads[i] = _ads[i].copyWith(status: status);
    _log(status, 'ad', i >= 0 ? _ads[i].title : id);
  }

  @override
  Future<CampaignStats> adStats(String id) async {
    _requireOwner();
    final m = _adStats[id] ?? const {};
    final keys = m.keys.toList()..sort();
    return CampaignStats([for (final k in keys) CampaignDay(DateTime.parse(k), m[k]!.$1, m[k]!.$2)]);
  }

  // ---------------- проверка объявлений, номера, бесплатное продвижение ----------------
  @override
  Future<List<Property>> adminPendingListings() async {
    _requireAdmin();
    await _lag();
    return _props.where((p) => p.status == 'pending').toList();
  }

  @override
  Future<void> adminReviewListing(String id, bool approve, {String? note}) async {
    _requireAdmin();
    final i = _props.indexWhere((p) => p.id == id);
    if (i < 0) return;
    if (approve) {
      _approved.add(id);
      _props[i] = _props[i].copyWith(status: 'active', confirmedAt: DateTime.now());
    } else {
      final p = _props[i];
      _props[i] = Property(
        id: p.id, ownerId: p.ownerId, title: p.title, description: p.description, dealType: p.dealType,
        propertyType: p.propertyType, price: p.price, currency: p.currency, rentPeriod: p.rentPeriod,
        bedrooms: p.bedrooms, bathrooms: p.bathrooms, areaSqm: p.areaSqm, amenities: p.amenities, areaId: p.areaId,
        areaName: p.areaName, city: p.city, lat: p.lat, lng: p.lng, status: 'archived', images: p.images,
        listedBy: p.listedBy, contactName: p.contactName, contactPhone: p.contactPhone, createdAt: p.createdAt,
        ownerAvatarUrl: p.ownerAvatarUrl, contactMode: p.contactMode,
        moderationNote: (note ?? '').trim().isEmpty ? 'Not approved' : note!.trim(),
      );
    }
    _log(approve ? 'approve' : 'reject', 'listing', _props[i].title, note);
  }

  @override
  Future<List<PhoneWatcher>> adminPhoneWatchers({int days = 7}) async {
    _requireAdmin();
    final since = DateTime.now().subtract(Duration(days: days));
    final byUser = <String, List<(String, String, DateTime)>>{};
    for (final r in _reveals.where((r) => r.$3.isAfter(since))) {
      byUser.putIfAbsent(r.$1, () => []).add(r);
    }
    final list = [
      for (final e in byUser.entries)
        PhoneWatcher(
          userId: e.key,
          fullName: _known[e.key]?.fullName,
          email: _known[e.key]?.email,
          phone: _known[e.key]?.phone,
          reveals: e.value.length,
          listings: e.value.map((r) => r.$2).toSet().length,
          lastAt: e.value.map((r) => r.$3).reduce((a, b) => a.isAfter(b) ? a : b),
          banned: _bannedAccounts.contains(e.key),
        ),
      // пример «подозрительного» — так выглядит бот
      PhoneWatcher(userId: 'u-bot', fullName: 'John K', email: 'jk2026@mail.com', phone: '+260 95 555 0909',
          reveals: 15, listings: 15, lastAt: _ago(8)),
    ]..sort((a, b) => b.reveals - a.reveals);
    return list;
  }

  @override
  Future<List<Property>> adminAgentListings(String agentId) async {
    _requireAdmin();
    return _props.where((p) => p.ownerId == agentId && p.status == 'active').toList();
  }

  @override
  Future<void> adminGrantPromotion(String agentId, String propertyId, int days, {String placement = 'search_top'}) async {
    _requireOwner();
    final agent = _known[agentId];
    final t = DateTime.now();
    final start = DateTime(t.year, t.month, t.day);
    _campaigns.add(Campaign(
      id: _uuid.v4(),
      ownerId: agentId,
      propertyId: propertyId,
      advertiser: agent?.agencyName ?? agent?.fullName ?? 'Agent',
      placement: placement,
      startsOn: start,
      endsOn: start.add(Duration(days: days - 1)),
      createdAt: t,
    ));
    _log('grant_promotion', 'campaign', '${agent?.fullName ?? agentId} · $days days');
  }

  @override
  Future<List<(Campaign, Property?)>> adminPendingCampaigns() async {
    _requireAdmin();
    await _lag();
    return [
      for (final c in _campaigns.where((c) => c.phase == 'review')) (c, await getProperty(c.propertyId)),
    ];
  }

  @override
  Future<void> adminReviewCampaign(String id, bool approve, {String? note}) async {
    _requireAdmin();
    final i = _campaigns.indexWhere((c) => c.id == id);
    if (i < 0) return;
    _campaigns[i] = _campaigns[i].copyWith(reviewStatus: approve ? 'approved' : 'rejected', reviewNote: note);
    _log(approve ? 'approve_campaign' : 'reject_campaign', 'campaign', _campaigns[i].advertiser);
  }

  @override
  Future<void> adminSetRequireLicence(bool on) async {
    _requireOwner();
    _requireLicence = on;
    _log('setting', 'settings', 'require_licence_to_publish = $on');
  }

  // ---------------- помощь (демо: статьи из assets/help/articles.json) ----------------
  List<HelpArticle>? _help;
  final Map<String, (bool, String?)> _myVotes = {};
  final Map<String, List<(bool, String?, DateTime)>> _otherVotes = {};

  Future<List<HelpArticle>> _loadHelp() async {
    if (_help != null) return _help!;
    try {
      final raw = jsonDecode(await rootBundle.loadString('assets/help/articles.json')) as List;
      _help = [for (final m in raw) HelpArticle.fromMap(Map<String, dynamic>.from(m as Map))];
    } catch (_) {
      _help = [];
    }
    // пара голосов для примера в кабинете
    if (_help!.isNotEmpty && _otherVotes.isEmpty) {
      _otherVotes[_help![1].id] = [
        (false, 'I chose SMS but the code never came. What now?', _ago(300)),
        (false, null, _ago(800)),
        (true, null, _ago(1400)),
      ];
      _otherVotes[_help![6].id] = [(true, null, _ago(200)), (true, null, _ago(900))];
    }
    return _help!;
  }

  @override
  Future<List<HelpArticle>> helpArticles() async {
    await _lag();
    final all = await _loadHelp();
    return all.where((a) => a.published && (kIsWeb || !a.webOnly)).toList()
      ..sort((a, b) => a.category != b.category ? a.category.compareTo(b.category) : a.sort.compareTo(b.sort));
  }

  @override
  Future<void> voteHelp(String articleId, bool helpful, {String? comment}) async {
    await _lag();
    _myVotes[articleId] = (helpful, (comment ?? '').trim().isEmpty ? null : comment!.trim());
  }

  @override
  Future<List<HelpArticle>> adminHelpArticles() async {
    _requireAdmin();
    return List.of(await _loadHelp());
  }

  @override
  Future<HelpArticle> adminSaveHelpArticle(HelpArticle a, {bool isNew = false}) async {
    _requireAdmin();
    final list = await _loadHelp();
    final saved = isNew ? a.copyWith(id: _uuid.v4()) : a.copyWith();
    final i = list.indexWhere((x) => x.id == saved.id);
    i < 0 ? list.add(saved) : list[i] = saved;
    _log(isNew ? 'help_create' : 'help_edit', 'help', saved.title);
    return saved;
  }

  @override
  Future<void> adminDeleteHelpArticle(String id) async {
    _requireAdmin();
    (await _loadHelp()).removeWhere((a) => a.id == id);
  }

  @override
  Future<List<HelpRating>> adminHelpRatings() async {
    _requireAdmin();
    final list = await _loadHelp();
    final out = <HelpRating>[];
    for (final a in list) {
      final votes = [...?_otherVotes[a.id], if (_myVotes[a.id] != null) (_myVotes[a.id]!.$1, _myVotes[a.id]!.$2, DateTime.now())];
      out.add(HelpRating(
        articleId: a.id,
        title: a.title,
        category: a.category,
        yes: votes.where((v) => v.$1).length,
        no: votes.where((v) => !v.$1).length,
        comments: [for (final v in votes) if (v.$2 != null) (v.$2!, v.$3)],
      ));
    }
    out.sort((a, b) => (b.no - b.yes).compareTo(a.no - a.yes));
    return out;
  }

  // ---------------- команда и статистика (демо) ----------------
  final Map<String, String> _demoTeam = {'moderator@test.com': 'moderator'};

  @override
  Future<List<TeamMember>> adminTeam() async {
    final me = _requireOwner();
    return [
      TeamMember(userId: me.id, fullName: me.fullName, email: me.email, level: 'owner'),
      for (final e in _demoTeam.entries)
        if (e.key != me.email) TeamMember(userId: 'demo-${e.key.hashCode}', fullName: e.key.split('@').first, email: e.key, level: e.value),
    ];
  }

  @override
  Future<void> adminSetTeam(String email, String? level) async {
    final me = _requireOwner();
    final e = email.trim().toLowerCase();
    if (e == me.email?.toLowerCase()) throw AppException('You cannot change your own role');
    level == null ? _demoTeam.remove(e) : _demoTeam[e] = level;
    _log('team_role', 'profile', e, level ?? 'removed');
  }

  int _visits = 0;

  @override
  Future<void> logVisit() async => _visits++;

  @override
  Future<Dashboard> ownerDashboard(String period) async {
    _requireOwner();
    await _lag();
    // демо: правдоподобные числа (на сервере — настоящие счётчики)
    final now = DateTime.now();
    final hourly = period == 'day';
    final n = hourly ? 24 : (period == 'week' ? 7 : 30);
    final rnd = Random(period.hashCode ^ now.day);
    final series = <DashPoint>[];
    for (var i = 0; i < n; i++) {
      final wave = hourly ? (i < 6 ? 0.15 : (i < 9 ? 0.6 : (i < 18 ? 1.0 : (i < 22 ? 1.3 : 0.5)))) : 1.0;
      final future = hourly && i > now.hour;
      final visits = future ? 0 : (wave * (hourly ? 40 : 700) * (0.8 + rnd.nextDouble() * 0.4)).round();
      final label = hourly
          ? '${i.toString().padLeft(2, '0')}:00'
          : isoDay(DateTime(now.year, now.month, now.day).subtract(Duration(days: n - 1 - i)));
      series.add(DashPoint(label, visits + ((hourly ? i == now.hour : i == n - 1) ? _visits : 0), (visits * 0.72).round(),
          (visits * 0.06).round(), (visits * 0.015).round(), (visits * 0.008).round()));
    }
    int sum(int Function(DashPoint) f) => series.fold(0, (a, p) => a + f(p));
    final days = hourly ? 1 : n;
    return Dashboard(
      period: period,
      from: DateTime(now.year, now.month, now.day).subtract(Duration(days: days - 1)),
      to: now,
      totals: {
        'visits': sum((p) => p.visits),
        'visitors_avg': (sum((p) => p.visitors) / days).round(),
        'visitors_today': hourly ? sum((p) => p.visitors) : series.last.visitors,
        'new_users': sum((p) => p.newUsers),
        'new_listings': sum((p) => p.newListings),
        'phone_views': (sum((p) => p.contacts) * 0.6).round() + _reveals.length,
        'new_chats': (sum((p) => p.contacts) * 0.4).round(),
        'ad_views': _adStats.values.fold<int>(0, (a, m) => a + m.values.fold<int>(0, (x, v) => x + v.$1)),
        'ad_clicks': _adStats.values.fold<int>(0, (a, m) => a + m.values.fold<int>(0, (x, v) => x + v.$2)),
        'promo_views': _campStats.values.fold<int>(0, (a, m) => a + m.values.fold<int>(0, (x, v) => x + v.$1)),
        'promo_clicks': _campStats.values.fold<int>(0, (a, m) => a + m.values.fold<int>(0, (x, v) => x + v.$2)),
        'reports': _reports.length,
        'bans': _bannedAccounts.length,
        'active_listings': _props.where((p) => p.status == 'active').length,
        'users_total': 128 + _known.length,
      },
      series: series,
      topAreas: const [('Kabulonga', 182), ('Woodlands', 141), ('Rhodes Park', 97), ('Ibex Hill', 88), ('Roma', 64)],
      topFilters: const [
        ('deal', 'rent', 402),
        ('type', 'house', 260),
        ('beds', '3+', 190),
        ('price', 'up to 15000 ZMW', 120),
        ('verified', 'yes', 75),
      ],
    );
  }

  final Map<String, int> _errors = {};

  @override
  Future<void> logError(String message) async {
    final m = message.replaceAll(RegExp(r'[0-9]{3,}'), '#');
    _errors[m.length > 200 ? m.substring(0, 200) : m] = (_errors[m] ?? 0) + 1;
  }

  @override
  Future<List<AdReportItem>> ownerAdReport(int days) async {
    _requireOwner();
    await _lag();
    final from = DateTime.now().subtract(Duration(days: days));
    final out = <AdReportItem>[];
    for (final a in _ads.where((a) => a.status != 'draft')) {
      final m = _adStats[a.id] ?? const {};
      final ds = [
        for (final k in (m.keys.toList()..sort()))
          if (DateTime.parse(k).isAfter(from)) AdReportDay(DateTime.parse(k), m[k]!.$1, m[k]!.$2, 0, 0),
      ];
      out.add(AdReportItem(
        kind: 'banner', id: a.id, title: a.title, advertiser: a.advertiser, placement: a.placement, status: a.status,
        startsOn: a.startsOn, endsOn: a.endsOn,
        views: ds.fold(0, (x, d) => x + d.views), clicks: ds.fold(0, (x, d) => x + d.clicks), days: ds,
      ));
    }
    for (final c in _campaigns.where((c) => c.reviewStatus == 'approved')) {
      final m = _campStats[c.id] ?? const {};
      final ds = [
        for (final k in (m.keys.toList()..sort()))
          if (DateTime.parse(k).isAfter(from)) AdReportDay(DateTime.parse(k), m[k]!.$1, m[k]!.$2, m[k]!.$3, m[k]!.$4),
      ];
      final p = await getProperty(c.propertyId);
      out.add(AdReportItem(
        kind: 'campaign', id: c.id, title: p?.title ?? 'Listing', advertiser: c.advertiser, placement: c.placement,
        status: c.status, startsOn: c.startsOn, endsOn: c.endsOn,
        views: ds.fold(0, (x, d) => x + d.views), clicks: ds.fold(0, (x, d) => x + d.clicks),
        calls: ds.fold(0, (x, d) => x + d.calls), messages: ds.fold(0, (x, d) => x + d.messages), days: ds,
      ));
    }
    return out;
  }

  @override
  Future<DevStats> devStats(int days) async {
    _requireOwner();
    await _lag();
    // демо: правдоподобные числа (на сервере — настоящие счётчики)
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final rnd = Random(days ^ now.day);
    final daily = [
      for (var i = days - 1; i >= 0; i--)
        () {
          final v = 380 + rnd.nextInt(160) + (days - i) * 3;
          return (today.subtract(Duration(days: i)), v, (v * (0.38 + rnd.nextDouble() * 0.08)).round());
        }(),
    ];
    final avg = (daily.fold<int>(0, (a, d) => a + d.$2) / daily.length).round();
    final ret = daily.fold<int>(0, (a, d) => a + d.$3) * 100 ~/ daily.fold<int>(1, (a, d) => a + d.$2);
    return DevStats(
      from: daily.first.$1,
      to: today,
      dauToday: daily.last.$2,
      dauAvg: avg,
      mau: avg * 6,
      returningShare: ret,
      daily: daily,
      months: [for (var i = 5; i >= 0; i--) (DateTime(now.year, now.month - i), 1800 + (5 - i) * 420)],
      funnelSeller: const {'signups': 240, 'phone': 168, 'listing': 74, 'contact': 51},
      funnelBuyer: const {'signups': 240, 'phone': 168, 'contact': 97},
      platforms: const [('web', '0.1.0', 6400, 4100), ('android', '0.1.0', 3900, 2600), ('ios', '0.1.0', 1200, 800)],
      errors: [
        for (final e in _errors.entries) ('web', '0.1.0', e.key, e.value, now),
        if (_errors.isEmpty) ('android', '0.1.0', 'Example: SocketException: Failed host lookup', 3, now),
      ],
    );
  }

  @override
  Future<int> adminPurgeDocs() async => 0; // в демо файлы не хранятся

  @override
  Future<void> adminSetOtpTestMode(bool on) async {
    _requireOwner();
    _otpTestMode = on;
    _log('otp_test_mode', 'settings', on ? 'on' : 'off');
  }

  // ---------------- чаты ----------------
  @override
  Future<String> startConversation(String propertyId) async {
    final u = _requireUser();
    final p = await getProperty(propertyId);
    if (p == null) throw AppException('Listing not found');
    if (p.ownerId == u.id) throw AppException('This is your own listing');
    _checkNotBanned(u);
    final existing = _convs.values.where((c) => c.propertyId == propertyId);
    if (existing.isNotEmpty) return existing.first.id;
    _bumpCampaigns(propertyId);
    final id = _uuid.v4();
    _convs[id] = Conversation(
      id: id,
      propertyId: p.id,
      propertyTitle: p.title,
      propertyCover: p.cover,
      otherName: p.contactName ?? 'Seller',
      lastMessageAt: DateTime.now(),
    );
    _msgs[id] = [];
    return id;
  }

  @override
  Future<List<Conversation>> conversations() async {
    _requireUser();
    return _convs.values.toList()..sort((a, b) => b.lastMessageAt.compareTo(a.lastMessageAt));
  }

  StreamController<List<ChatMessage>> _ctrl(String id) =>
      _msgCtrls.putIfAbsent(id, () => StreamController<List<ChatMessage>>.broadcast());

  @override
  Stream<List<ChatMessage>> messages(String conversationId) async* {
    yield List.of(_msgs[conversationId] ?? const []);
    yield* _ctrl(conversationId).stream;
  }

  @override
  Future<void> sendMessage(String conversationId, String body) async {
    final u = _requireUser();
    _checkNotBanned(u);
    final list = _msgs.putIfAbsent(conversationId, () => []);
    list.add(ChatMessage(id: _uuid.v4(), senderId: u.id, body: body, createdAt: DateTime.now()));
    _touch(conversationId, body);
    _ctrl(conversationId).add(List.of(list));

    // в демо продавец отвечает автоматически
    Future.delayed(const Duration(seconds: 2), () {
      list.add(ChatMessage(
        id: _uuid.v4(),
        senderId: 'seller',
        body: 'Thanks for your message! This is a demo chat — real replies will work once Supabase is connected.',
        createdAt: DateTime.now(),
      ));
      _touch(conversationId, list.last.body);
      _ctrl(conversationId).add(List.of(list));
    });
  }

  void _touch(String id, String last) {
    final c = _convs[id];
    if (c == null) return;
    _convs[id] = Conversation(
      id: c.id,
      propertyId: c.propertyId,
      propertyTitle: c.propertyTitle,
      propertyCover: c.propertyCover,
      otherName: c.otherName,
      lastMessage: last,
      lastMessageAt: DateTime.now(),
    );
  }
}
