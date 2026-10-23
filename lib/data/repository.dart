import 'dart:typed_data';

import '../models/models.dart';

/// Единый интерфейс данных. Две реализации:
///  - SupabaseRepository — настоящий сервер;
///  - DemoRepository — всё в памяти, чтобы приложение работало без сервера.
abstract class Repository {
  bool get isDemo;

  // --- авторизация
  AppUser? get currentUser;
  Stream<AppUser?> get userChanges;
  Future<void> signIn({required String email, required String password});
  Future<void> signUp({
    required String email,
    required String password,
    required String fullName,
    required String phone,
    required String role,
  });
  Future<void> signOut();

  /// Перечитать свой профиль с сервера (статусы проверок могли измениться)
  Future<void> refreshUser();

  /// Забыли пароль: код из письма → новый пароль
  Future<void> sendPasswordReset(String email);
  Future<void> resetPasswordWithCode({required String email, required String code, required String newPassword});

  /// Сменить пароль (пользователь вошёл)
  Future<void> changePassword(String newPassword);

  /// Удалить аккаунт и все данные (объявления, фото, чаты)
  Future<void> deleteAccount();

  // --- справочники и поиск
  Future<List<Area>> areas();
  /// Поиск порциями: limit объявлений начиная с offset
  Future<List<Property>> search(SearchFilters f, {int limit = 30, int offset = 0});

  /// Сколько всего объявлений подходит под фильтры
  Future<int> countListings(SearchFilters f);

  /// Цены подходящих объявлений — для гистограммы в фильтрах (только числа, это лёгкий запрос)
  Future<List<double>> priceSamples(SearchFilters f);

  /// Количество объявлений по районам
  Future<Map<int, int>> areaCounts();

  /// Самые просматриваемые
  Future<List<Property>> popular({String city = 'Lusaka', int limit = 8});

  Future<Property?> getProperty(String id);
  Future<List<Property>> byIds(List<String> ids);
  Future<void> incrementViews(String id);

  // --- избранное (на сервере, если пользователь вошёл)
  Future<Set<String>> favoriteIds();
  Future<void> setFavorite(String propertyId, bool value);

  // --- мои объявления
  Future<Quota> myQuota();
  Future<List<Property>> myListings();
  Future<Property> createListing(ListingDraft d);
  Future<Property> updateListing(String id, ListingDraft d);
  Future<void> setListingStatus(String id, String status);
  Future<void> deleteListing(String id);

  // --- ZumiCheck: доверие и жалобы
  /// Пожаловаться на объявление (мошенничество, предоплата и т.п.)
  Future<void> reportListing(String propertyId, String reason, String? details);

  /// Обновить профиль (имя, агентство, «о себе», рабочий WhatsApp)
  Future<void> updateProfile({String? fullName, String? agencyName, String? bio, String? whatsapp});

  /// Фото профиля
  Future<void> uploadAvatar(PickedPhoto photo);

  /// Публичная страница человека и его объявления
  Future<PublicProfile?> publicProfile(String userId);
  Future<List<Property>> listingsBy(String userId);

  /// Проверка личности: фото NRC/паспорта + селфи, с согласием на обработку данных
  Future<void> submitIdentity({required String docType, required PickedPhoto document, required PickedPhoto selfie});

  /// Агент: номер регистрации ZIEA (сверяет команда Zumi)
  Future<void> submitAgentLicence(String licenceNo);

  /// Отправить документы на проверку: kind = 'identity' | 'ownership'
  Future<void> requestVerification({
    required String kind,
    String? propertyId,
    required List<PickedPhoto> docs,
    String? note,
  });

  /// Статус последней заявки: 'pending' | 'approved' | 'rejected' | null
  Future<String?> verificationStatus({required String kind, String? propertyId});

  /// Property Verified: 3+ фото на месте и геолокация телефона (автоматически)
  Future<PropertyCheckResult> submitPropertyCheck(
    String propertyId,
    List<PickedPhoto> photos,
    double lat,
    double lng,
  );

  /// Телефон: отправить SMS-код и проверить его
  Future<void> sendPhoneCode(String phone);
  Future<void> verifyPhoneCode(String phone, String code);

  /// Автор подтверждает, что объект ещё доступен
  Future<void> confirmListing(String propertyId);

  // --- поддержка (пользователь)
  Future<List<SupportTicket>> myTickets();
  Future<String> openTicket({required String category, required String subject, required String message});
  Stream<List<SupportMessage>> ticketMessages(String ticketId);
  Future<void> sendTicketMessage(String ticketId, String body, {bool asStaff = false});

  // --- отзывы об авторах
  Future<List<Review>> reviewsAbout(String userId);
  Future<Rating> ratingOf(String userId);
  Future<void> writeReview({required String targetId, required int rating, String? body, String? propertyId});
  Future<void> flagReview(String reviewId);

  // --- кабинет команды Zumi (только role = admin)
  Future<AdminStats> adminStats();
  Future<List<AccountItem>> adminAccounts({bool onlyNew = true});
  Future<void> adminReviewAccount(String userId, String action, {String? note});
  Future<List<VerificationItem>> adminVerificationQueue({String status = 'pending'});
  Future<List<String>> adminDocUrls(List<String> paths);
  Future<void> adminReviewVerification(String id, bool approve, {String? note});
  Future<List<LicenceItem>> adminLicenceQueue();
  Future<void> adminReviewLicence(String userId, bool approve, {String? note});
  Future<List<ReportItem>> adminReports({bool onlyNew = true});
  Future<void> adminResolveReport(String id, String action, {String? note});
  Future<void> adminRestoreListing(String propertyId);
  Future<List<SupportTicket>> adminTickets({String? status});
  Future<void> adminSetTicketStatus(String id, String status);
  Future<List<Review>> adminReviews({bool flaggedOnly = false});
  Future<void> adminModerateReview(String id, String action, {String? reply});
  Future<List<AuditEntry>> adminAudit();

  // --- чаты
  Future<String> startConversation(String propertyId);
  Future<List<Conversation>> conversations();
  Stream<List<ChatMessage>> messages(String conversationId);
  Future<void> sendMessage(String conversationId, String body);
}

/// Фото, выбранные в демо-режиме, живут только в памяти (ключ 'mem:...').
class MemoryImages {
  static final Map<String, Uint8List> _store = {};
  static String put(String key, Uint8List bytes) {
    _store[key] = bytes;
    return 'mem:$key';
  }

  static Uint8List? get(String url) => _store[url.substring(4)];
}
