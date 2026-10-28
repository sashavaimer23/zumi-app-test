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
    bool termsAccepted = true,
    String? licenceNo, // агент может сразу указать номер ZIEA
    bool marketing = false, // согласие на новости и предложения (по умолчанию нет)
  });
  Future<void> signOut();

  /// Ещё раз отправить письмо «подтвердите почту»
  Future<void> resendConfirmation(String email);

  /// Новости и предложения Zumi: channel = 'email' | 'whatsapp', включить / выключить (Settings)
  Future<void> setMarketing(String channel, bool on);

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
  /// Просмотр объявления: сервер считает одного человека один раз в день, автора — не считает
  Future<void> incrementViews(String id);

  /// Цены похожих объявлений в районе (для подсказки в мастере)
  Future<PriceStats> areaPriceStats({
    required int areaId,
    required DealType deal,
    required PropertyType type,
    int? bedrooms,
    String? rentPeriod,
    String currency = 'ZMW',
    String? excludeId,
  });

  /// Статистика и советы по своим объявлениям (Мои объявления)
  Future<Map<String, ListingStats>> myListingAdvice();

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
  Future<void> updateProfile({
    String? fullName,
    String? agencyName,
    String? bio,
    String? whatsapp,
    String? contactMode, // 'phone' | 'chat'
  });

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

  /// Код подтверждения: channel = whatsapp | sms | email. Возвращает true в тестовом режиме (код 123456).
  /// Значок «телефон подтверждён» — только за WhatsApp или SMS.
  Future<bool> sendCode(String channel, String destination);
  Future<void> verifyCode(String channel, String destination, String code);

  /// Номер автора объявления: выдаёт сервер (вход + подтверждённый телефон, до 15 в сутки)
  Future<String> revealPhone(String propertyId);

  /// WhatsApp агента (страница агента): те же правила и тот же лимит, что у номера
  Future<String> revealAgentWhatsapp(String agentId);

  /// Номер из своего объявления (для правки)
  Future<String?> myListingPhone(String propertyId);

  /// Автор подтверждает, что объект ещё доступен
  Future<void> confirmListing(String propertyId);

  // --- поддержка (пользователь)
  Future<List<SupportTicket>> myTickets();
  Future<String> openTicket({
    required String category,
    required String subject,
    required String message,
    String? helpArticleId, // обращение из статьи помощи, которая не помогла
  });
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

  // --- продвижение (кабинет агента)
  Future<List<Campaign>> myCampaigns();
  Future<Campaign> createCampaign(CampaignDraft d);
  Future<void> setCampaignStatus(String id, String status);
  Future<CampaignStats> campaignStats(String id);

  /// Идущие сегодня кампании для места показа + их объявления
  Future<List<(Campaign, Property)>> liveCampaigns(String placement, {SearchFilters? filters});

  /// Показ или клик (для статистики)
  Future<void> logCampaignEvent(String campaignId, String kind);

  // --- реклама (баннеры)
  Future<List<Ad>> liveAds(String placement);
  Future<void> logAdEvent(String adId, String kind);

  // --- кабинет команды: реклама, проверка объявлений, номера, бесплатное продвижение
  Future<List<Ad>> adminAds();
  Future<Ad> adminSaveAd(AdDraft d, {required bool launch});
  Future<void> adminSetAdStatus(String id, String status);
  Future<CampaignStats> adStats(String id);
  Future<List<Property>> adminPendingListings();
  Future<void> adminReviewListing(String id, bool approve, {String? note});
  Future<List<PhoneWatcher>> adminPhoneWatchers({int days = 7});
  Future<List<Property>> adminAgentListings(String agentId);
  Future<void> adminGrantPromotion(String agentId, String propertyId, int days, {String placement = 'search_top'});
  /// Продвижение со своей картинкой, названием или ссылкой — ждёт проверки
  Future<List<(Campaign, Property?)>> adminPendingCampaigns();
  Future<void> adminReviewCampaign(String id, bool approve, {String? note});
  /// Тестовый режим кодов (123456 подходит всем) — включить/выключить
  Future<void> adminSetOtpTestMode(bool on);
  /// Агент публикует объявления только после проверки лицензии ZIEA — включить/выключить
  Future<void> adminSetRequireLicence(bool on);
  // --- помощь
  /// Опубликованные статьи (в приложениях — без статей «только для сайта»)
  Future<List<HelpArticle>> helpArticles();
  /// «Статья была полезной?» — один голос с человека (можно изменить)
  Future<void> voteHelp(String articleId, bool helpful, {String? comment});
  Future<List<HelpArticle>> adminHelpArticles();
  Future<HelpArticle> adminSaveHelpArticle(HelpArticle a, {bool isNew = false});
  Future<void> adminDeleteHelpArticle(String id);
  Future<List<HelpRating>> adminHelpRatings();

  // --- команда и статистика (владелец)
  Future<List<TeamMember>> adminTeam();
  /// level: 'moderator' | 'owner' | null — убрать из команды
  Future<void> adminSetTeam(String email, String? level);
  /// period: 'day' | 'week' | 'month'
  Future<Dashboard> ownerDashboard(String period);
  /// Обезличенный счётчик посещений (без имён) + платформа и версия приложения
  Future<void> logVisit();
  /// Ошибка приложения — только текст ошибки (цифры и почта вырезаются на сервере)
  Future<void> logError(String message);
  /// Отчёт по рекламе за days дней: баннеры и кампании продвижения (владелец)
  Future<List<AdReportItem>> ownerAdReport(int days);
  /// Раздел разработчика: активные, возвраты, воронки, платформы, ошибки (владелец)
  Future<DevStats> devStats(int days);

  /// Удалить из хранилища фото документов по решённым и старым (30 дней) заявкам. Возвращает число файлов.
  Future<int> adminPurgeDocs();

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
