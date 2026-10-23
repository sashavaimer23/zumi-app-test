import 'dart:async';

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
        role: e.contains('admin') ? 'admin' : (e.contains('agent') ? 'agent' : 'owner'),
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
  }) async {
    await _lag();
    if (password.length < 6) throw AppException('Password must be at least 6 characters');
    final u = AppUser(
      id: 'demo-${email.toLowerCase().hashCode}',
      email: email,
      fullName: fullName,
      phone: phone,
      role: email.toLowerCase().contains('admin') ? 'admin' : role,
      createdAt: DateTime.now(),
    );
    _known[u.id] = u;
    if (!u.isAdmin) _newAccounts.add(u.id);
    _user = u;
    _userCtrl.add(_user);
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
  Future<void> incrementViews(String id) async {}

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

  @override
  Future<Property> createListing(ListingDraft d) async {
    final u = _requireUser();
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
      ownerIdentityVerified: u.identityVerified,
      ownerAvatarUrl: u.avatarUrl,
      agencyName: u.agencyName,
    );
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
    if (i >= 0) _props[i] = _props[i].copyWith(status: status);
  }

  @override
  Future<void> deleteListing(String id) async => _props.removeWhere((p) => p.id == id);

  // ---------------- ZumiCheck ----------------
  final Set<String> _reported = {};
  final Map<String, String> _verification = {}; // ключ: propertyId или 'identity'

  @override
  Future<void> reportListing(String propertyId, String reason, String? details) async {
    _requireUser();
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
  Future<void> updateProfile({String? fullName, String? agencyName, String? bio, String? whatsapp}) async {
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
    );
    _known[u.id] = _user!;
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
        whatsapp: u.isAgent ? u.whatsapp : null,
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
        whatsapp: agent ? '+260 97 000 0000' : null,
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

  String? _pendingPhone;

  @override
  Future<void> sendPhoneCode(String phone) async {
    _requireUser();
    await _lag();
    _pendingPhone = phone; // демо: код всегда 123456
  }

  @override
  Future<void> verifyPhoneCode(String phone, String code) async {
    final u = _requireUser();
    await _lag();
    if (_pendingPhone != phone || code.trim() != '123456') {
      throw AppException('Wrong code. In demo mode the code is 123456');
    }
    _setUser(u.copyWith(phone: phone, phoneVerified: true));
    _syncMyBadge();
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

  @override
  Future<List<SupportTicket>> myTickets() async {
    final u = _requireUser();
    return _tickets.where((t) => t.userId == u.id).toList();
  }

  @override
  Future<String> openTicket({required String category, required String subject, required String message}) async {
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
      if (_props[i].ownerId == userId) _props[i] = _props[i].copyWith(ownerIdentityVerified: u.identityVerified);
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
    _requireAdmin();
    return List.of(_audit);
  }

  // ---------------- чаты ----------------
  @override
  Future<String> startConversation(String propertyId) async {
    final u = _requireUser();
    final p = await getProperty(propertyId);
    if (p == null) throw AppException('Listing not found');
    if (p.ownerId == u.id) throw AppException('This is your own listing');
    final existing = _convs.values.where((c) => c.propertyId == propertyId);
    if (existing.isNotEmpty) return existing.first.id;
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
