import 'dart:typed_data';

import '../features.dart';

// Модели данных Zumi. Поля совпадают с колонками view `property_feed` в Supabase.

double? _d(dynamic v) => v == null ? null : (v as num).toDouble();
int? _i(dynamic v) => v == null ? null : (v as num).toInt();
List<String> _sl(dynamic v) => v == null ? <String>[] : List<String>.from(v as List);

enum DealType { rent, sale }

enum PropertyType { house, apartment, land, commercial }

extension PropertyTypeX on PropertyType {
  String get label => switch (this) {
        PropertyType.house => 'House',
        PropertyType.apartment => 'Apartment',
        PropertyType.land => 'Land',
        PropertyType.commercial => 'Commercial',
      };
  String get plural => switch (this) {
        PropertyType.house => 'houses',
        PropertyType.apartment => 'apartments',
        PropertyType.land => 'plots',
        PropertyType.commercial => 'commercial',
      };
}

PropertyType parsePropertyType(String s) => switch (s) {
      'apartment' => PropertyType.apartment,
      'land' => PropertyType.land,
      'commercial' || 'office' => PropertyType.commercial,
      _ => PropertyType.house,
    };

/// Удобства: ключ в базе → подпись в интерфейсе
const amenityLabels = <String, String>{
  'parking': 'Parking',
  'furnished': 'Furnished',
  'garden': 'Garden',
  'pool': 'Swimming pool',
  'ac': 'Air conditioning',
  'fridge': 'Fridge',
  'washing_machine': 'Washing machine',
  'dishwasher': 'Dishwasher',
  'internet': 'Internet',
  'tv': 'TV',
  'garage': 'Garage',
};

const renovationLabels = <String, String>{
  'cosmetic': 'Cosmetic',
  'designer': 'Designer',
  'none': 'No renovation',
};

class Area {
  final int id;
  final String city;
  final String name;
  final double lat;
  final double lng;
  final String? tagline;
  final String? imageUrl;

  const Area({
    required this.id,
    required this.city,
    required this.name,
    required this.lat,
    required this.lng,
    this.tagline,
    this.imageUrl,
  });

  factory Area.fromMap(Map<String, dynamic> m) => Area(
        id: _i(m['id'])!,
        city: m['city'] as String,
        name: m['name'] as String,
        lat: _d(m['lat'])!,
        lng: _d(m['lng'])!,
        tagline: m['tagline'] as String?,
        imageUrl: m['image_url'] as String?,
      );
}

class Property {
  final String id;
  final String? ownerId;
  final String title;
  final String? description;
  final DealType dealType;
  final PropertyType propertyType;
  final double price;
  final String currency;
  final String? rentPeriod; // 'month' | 'day'
  final int? bedrooms;
  final int? bathrooms;
  final double? areaSqm;
  final double? plotSqm;
  final List<String> amenities;
  final int? areaId;
  final String? areaName;
  final String? city;
  final String? address;
  final double lat;
  final double lng;
  final String status;
  final bool promoted; // продвигается (видно, только если продвижение включено — Features.promotion)
  bool get isPromoted => promoted && Features.promotion;
  final List<String> images;
  final String? listedBy; // 'agent' | 'owner'
  final String? contactName;
  final String? contactPhone;
  final String? renovation;
  final bool? kidsAllowed;
  final bool? petsAllowed;
  final String? leaseTerm; // 'year' | 'months'
  final int viewsCount;
  final DateTime createdAt;
  final bool isDemo;
  // Verification — три уровня проверки
  final bool propertyVerified;          // объект существует (фото на месте + геолокация / визит)
  final String? propertyVerifyMethod;   // 'geo_photos' | 'visit' | 'video'
  final DateTime? propertyVerifiedAt;
  final bool ownershipVerified;         // документы о собственности / полномочия агента
  final bool ownerIdentityVerified;     // телефон по SMS + документ
  final bool ownerPhoneVerified;        // телефон подтверждён SMS-кодом
  final bool ownerLicenceVerified;      // у агента сверена лицензия ZIEA
  final DateTime? confirmedAt;          // автор подтвердил «ещё доступно»
  final String? agencyName;
  final String? highlights;             // «Gated street | Borehole | Solar backup»
  final String? ownerAvatarUrl;         // фото автора
  final List<String> thumbs;            // маленькие копии фото для карточек (экономия трафика)
  final bool isFresh;                   // подтверждено «ещё доступно» за последние 37 дней (спросим через 30)
  final String contactMode;             // 'phone' — номер можно показать, 'chat' — только чат
  final bool hasPhone;                  // у объявления есть номер (сам номер выдаёт сервер по кнопке)
  final String? moderationNote;         // почему модератор не одобрил
  final Map<String, String> nearby;     // что рядом: shop/school/hospital/main_road → lt1/1_3/3_5/gt5
  final bool ownerLicensed;             // автор — агент с проверенной лицензией ZIEA
  final String? hiddenBy;               // кто скрыл: owner · team · expired
  final String? hiddenReason;           // почему скрыла команда Zumi
  final DateTime? approvedAt;

  const Property({
    required this.id,
    this.ownerId,
    required this.title,
    this.description,
    required this.dealType,
    required this.propertyType,
    required this.price,
    this.currency = 'ZMW',
    this.rentPeriod,
    this.bedrooms,
    this.bathrooms,
    this.areaSqm,
    this.plotSqm,
    this.amenities = const [],
    this.areaId,
    this.areaName,
    this.city,
    this.address,
    required this.lat,
    required this.lng,
    this.status = 'active',
    bool isPromoted = false,
    this.images = const [],
    this.listedBy,
    this.contactName,
    this.contactPhone,
    this.renovation,
    this.kidsAllowed,
    this.petsAllowed,
    this.leaseTerm,
    this.viewsCount = 0,
    required this.createdAt,
    this.isDemo = false,
    this.propertyVerified = false,
    this.propertyVerifyMethod,
    this.propertyVerifiedAt,
    this.ownershipVerified = false,
    this.ownerIdentityVerified = false,
    this.ownerPhoneVerified = false,
    this.ownerLicenceVerified = true,
    this.confirmedAt,
    this.agencyName,
    this.highlights,
    this.ownerAvatarUrl,
    this.thumbs = const [],
    this.isFresh = true,
    this.contactMode = 'phone',
    bool? hasPhone,
    this.moderationNote,
    this.nearby = const {},
    this.ownerLicensed = false,
    this.hiddenBy,
    this.hiddenReason,
    this.approvedAt,
  }) : promoted = isPromoted,
       hasPhone = hasPhone ?? (contactPhone != null && contactPhone != '');

  factory Property.fromMap(Map<String, dynamic> m) => Property(
        id: m['id'] as String,
        ownerId: m['owner_id'] as String?,
        title: m['title'] as String,
        description: m['description'] as String?,
        dealType: m['deal_type'] == 'sale' ? DealType.sale : DealType.rent,
        propertyType: parsePropertyType(m['property_type'] as String),
        price: _d(m['price']) ?? 0,
        currency: (m['currency'] as String?) ?? 'ZMW',
        rentPeriod: m['rent_period'] as String?,
        bedrooms: _i(m['bedrooms']),
        bathrooms: _i(m['bathrooms']),
        areaSqm: _d(m['area_sqm']),
        plotSqm: _d(m['plot_sqm']),
        amenities: _sl(m['amenities']),
        areaId: _i(m['area_id']),
        areaName: m['area_name'] as String?,
        city: m['city'] as String?,
        address: m['address'] as String?,
        lat: _d(m['lat']) ?? 0,
        lng: _d(m['lng']) ?? 0,
        status: (m['status'] as String?) ?? 'active',
        isPromoted: (m['is_promoted'] as bool?) ?? false,
        images: _sl(m['image_urls']),
        listedBy: m['listed_by'] as String?,
        contactName: m['contact_name'] as String?,
        contactPhone: m['contact_phone'] as String?,
        renovation: m['renovation'] as String?,
        kidsAllowed: m['kids_allowed'] as bool?,
        petsAllowed: m['pets_allowed'] as bool?,
        leaseTerm: m['lease_term'] as String?,
        viewsCount: _i(m['views_count']) ?? 0,
        createdAt: DateTime.tryParse((m['created_at'] as String?) ?? '') ?? DateTime.now(),
        isDemo: (m['is_demo'] as bool?) ?? false,
        propertyVerified: (m['property_verified'] as bool?) ?? false,
        propertyVerifyMethod: m['property_verify_method'] as String?,
        propertyVerifiedAt: DateTime.tryParse((m['property_verified_at'] as String?) ?? ''),
        ownershipVerified: (m['ownership_verified'] as bool?) ?? false,
        ownerIdentityVerified: (m['owner_identity_verified'] as bool?) ?? false,
        ownerPhoneVerified: (m['owner_phone_verified'] as bool?) ?? false,
        ownerLicenceVerified: (m['owner_licence_verified'] as bool?) ?? true,
        confirmedAt: DateTime.tryParse((m['confirmed_at'] as String?) ?? ''),
        agencyName: m['agency_name'] as String?,
        highlights: m['highlights'] as String?,
        ownerAvatarUrl: m['owner_avatar_url'] as String?,
        thumbs: _sl(m['thumb_urls']),
        isFresh: (m['is_fresh'] as bool?) ?? true,
        contactMode: (m['contact_mode'] as String?) ?? 'phone',
        hasPhone: m['has_phone'] as bool?,
        moderationNote: m['moderation_note'] as String?,
        nearby: _nearby(m['nearby']),
        ownerLicensed: (m['owner_licensed'] as bool?) ?? false,
        hiddenBy: m['hidden_by'] as String?,
        hiddenReason: m['hidden_reason'] as String?,
        approvedAt: DateTime.tryParse((m['approved_at'] as String?) ?? ''),
      );

  static Map<String, String> _nearby(Object? v) {
    if (v is! Map) return const {};
    return {
      for (final e in v.entries)
        if (kNearbyPlaces.containsKey(e.key) && kNearbyDistances.containsKey(e.value)) '${e.key}': '${e.value}',
    };
  }

  /// Плашка на фото: агент с проверенной лицензией — «Licensed agent», иначе подтверждённый номер — «Number checked»
  bool get isVerified => ownerLicensed || ownerPhoneVerified;
  String get badgeLabel => ownerLicensed ? 'Licensed agent' : 'Number checked';

  Property copyWith({
    String? status,
    bool? isPromoted,
    bool? propertyVerified,
    bool? ownerIdentityVerified,
    DateTime? confirmedAt,
    String? ownerAvatarUrl,
    String? contactName,
    String? contactMode,
    bool? ownerLicenceVerified,
    String? hiddenBy,
    bool clearHidden = false,
  }) =>
      Property(
        id: id, ownerId: ownerId, title: title, description: description,
        dealType: dealType, propertyType: propertyType, price: price, currency: currency,
        rentPeriod: rentPeriod, bedrooms: bedrooms, bathrooms: bathrooms, areaSqm: areaSqm,
        plotSqm: plotSqm, amenities: amenities, areaId: areaId, areaName: areaName, city: city,
        address: address, lat: lat, lng: lng, status: status ?? this.status,
        isPromoted: isPromoted ?? promoted, images: images, listedBy: listedBy,
        contactName: contactName ?? this.contactName, contactPhone: contactPhone, renovation: renovation,
        kidsAllowed: kidsAllowed, petsAllowed: petsAllowed, leaseTerm: leaseTerm,
        viewsCount: viewsCount, createdAt: createdAt, isDemo: isDemo,
        propertyVerified: propertyVerified ?? this.propertyVerified,
        propertyVerifyMethod: propertyVerifyMethod,
        propertyVerifiedAt: (propertyVerified ?? false) ? DateTime.now() : propertyVerifiedAt,
        ownershipVerified: ownershipVerified,
        ownerIdentityVerified: ownerIdentityVerified ?? this.ownerIdentityVerified,
        ownerPhoneVerified: ownerPhoneVerified, ownerLicenceVerified: ownerLicenceVerified ?? this.ownerLicenceVerified,
        confirmedAt: confirmedAt ?? this.confirmedAt,
        agencyName: agencyName, highlights: highlights,
        ownerAvatarUrl: ownerAvatarUrl ?? this.ownerAvatarUrl, thumbs: thumbs,
        isFresh: confirmedAt != null ? true : isFresh,
        contactMode: contactMode ?? this.contactMode, hasPhone: hasPhone, moderationNote: moderationNote,
        nearby: nearby, ownerLicensed: ownerLicensed,
        hiddenBy: clearHidden ? null : (hiddenBy ?? this.hiddenBy),
        hiddenReason: clearHidden ? null : hiddenReason,
        approvedAt: approvedAt,
      );

  bool get isPending => status == 'pending';

  // ---------- «Ещё доступно?» и скрытые объявления ----------
  /// Через сколько дней спросить «ещё доступно?» и через сколько скрыть без ответа
  static const askAfterDays = 30;
  static const hideAfterDays = 37;

  /// Дней с последнего подтверждения
  int get daysSinceConfirmed =>
      DateTime.now().difference(confirmedAt ?? approvedAt ?? createdAt).inDays;

  /// Пора спросить автора «ещё доступно?» (объявление ещё в поиске)
  bool get needsAvailabilityAnswer => status == 'active' && !isDemo && daysSinceConfirmed >= askAfterDays;

  /// Дней до скрытия, если не ответить
  int get daysUntilHidden => (hideAfterDays - daysSinceConfirmed).clamp(0, hideAfterDays);

  /// Не видно в поиске: скрыто, продано/сдано или не подтверждено вовремя
  bool get hiddenFromSearch =>
      const {'archived', 'sold', 'rented'}.contains(status) || (status == 'active' && !isFresh);

  /// Скрыто командой Zumi (вернуть можно только через проверку)
  bool get hiddenByTeam => status == 'archived' && hiddenBy == 'team';

  /// Не ответил «ещё доступно?» вовремя
  bool get expired => status == 'active' && !isFresh;
  bool get chatOnly => contactMode == 'chat';

  /// Агент без сверенной лицензии ZIEA — на объявлении пометка
  bool get unlicensedAgent => listedBy == 'agent' && !ownerLicenceVerified;

  String? get cover => images.isEmpty ? null : images.first;

  /// Фото для карточек: маленькая копия, если есть
  String? thumbAt(int i) {
    if (i < thumbs.length && thumbs[i].isNotEmpty) return thumbs[i];
    return i < images.length ? images[i] : null;
  }

  String? get coverThumb => thumbAt(0);

  /// Ссылка, которой можно поделиться (сайт открывает объявление по ?listing=id)
  String shareText(String? siteUrl) {
    final link = siteUrl == null ? '' : '\n$siteUrl/?listing=$id';
    return '$title — $priceLabel\n${locationLine.isEmpty ? 'Zambia' : locationLine}\nSee it on Zumi$link';
  }

  /// «45,000 ZMW per month»
  String get priceLabel {
    final p = formatMoney(price, currency);
    if (dealType == DealType.sale) return p;
    return rentPeriod == 'day' ? '$p per day' : '$p per month';
  }

  /// «3-bedroom house ,  70,8m»
  String get specsLine {
    final parts = <String>[];
    final type = propertyType == PropertyType.commercial ? 'Commercial' : propertyType.label.toLowerCase();
    if (bedrooms != null && bedrooms! > 0) {
      parts.add('$bedrooms-bedroom $type');
    } else {
      parts.add(propertyType.label);
    }
    final size = areaSqm ?? plotSqm;
    if (size != null) parts.add('${_num(size)} m²');
    return parts.join(',  ');
  }

  /// «Lusaka, Ibex Hill, The 3rd street»
  String get locationLine => [city, areaName, address].whereType<String>().where((s) => s.isNotEmpty).join(', ');
}

/// Что рядом с жильём: ключ → подпись
const kNearbyPlaces = <String, String>{
  'shop': 'Shops',
  'school': 'School',
  'hospital': 'Hospital / clinic',
  'main_road': 'Main road',
};

/// Расстояние: ключ → подпись
const kNearbyDistances = <String, String>{
  'lt1': 'Under 1 km',
  '1_3': '1–3 km',
  '3_5': '3–5 km',
  'gt5': 'Over 5 km',
};

String _num(double v) => v == v.roundToDouble() ? v.toInt().toString() : v.toStringAsFixed(1);

String formatMoney(double v, [String currency = 'ZMW']) {
  final s = v.round().toString();
  final b = StringBuffer();
  for (var i = 0; i < s.length; i++) {
    if (i > 0 && (s.length - i) % 3 == 0) b.write(',');
    b.write(s[i]);
  }
  return '$b $currency';
}

enum SortBy { newest, priceAsc, priceDesc }

extension SortByX on SortBy {
  String get label => switch (this) {
        SortBy.newest => 'Newest first',
        SortBy.priceAsc => 'Price: low to high',
        SortBy.priceDesc => 'Price: high to low',
      };
}

/// Все фильтры поиска (экран Filters + строка поиска + категории)
class SearchFilters {
  DealType? dealType;
  String? rentPeriod; // 'month' (надолго) | 'day' (посуточно)
  PropertyType? propertyType;
  String city;
  String query; // поиск по району / названию
  int? areaId;
  double? minPrice;
  double? maxPrice;
  int? minBedrooms;
  int? minBathrooms;
  Set<String> renovation;
  bool kidsAllowed;
  bool petsAllowed;
  Set<String> amenities;
  bool onlyOwner;
  bool onlyAgent;
  String? leaseTerm;
  double? minSqm;
  double? maxSqm;
  bool onlyVerified;          // только с плашкой Verified (проверенный автор)
  bool onlyLocationVerified;  // объект подтверждён на месте (фото + геолокация)
  String currency;            // валюта ценового фильтра: 'ZMW' | 'USD'
  SortBy sort;

  SearchFilters({
    this.dealType,
    this.rentPeriod,
    this.propertyType,
    this.city = 'Lusaka',
    this.query = '',
    this.areaId,
    this.minPrice,
    this.maxPrice,
    this.minBedrooms,
    this.minBathrooms,
    Set<String>? renovation,
    this.kidsAllowed = false,
    this.petsAllowed = false,
    Set<String>? amenities,
    this.onlyOwner = false,
    this.onlyAgent = false,
    this.leaseTerm,
    this.minSqm,
    this.maxSqm,
    this.onlyVerified = false,
    this.onlyLocationVerified = false,
    this.currency = 'ZMW',
    this.sort = SortBy.newest,
  })  : renovation = renovation ?? {},
        amenities = amenities ?? {};

  SearchFilters copy() => SearchFilters(
        dealType: dealType, rentPeriod: rentPeriod, propertyType: propertyType, city: city,
        query: query, areaId: areaId, minPrice: minPrice, maxPrice: maxPrice,
        minBedrooms: minBedrooms, minBathrooms: minBathrooms, renovation: {...renovation},
        kidsAllowed: kidsAllowed, petsAllowed: petsAllowed, amenities: {...amenities},
        onlyOwner: onlyOwner, onlyAgent: onlyAgent, leaseTerm: leaseTerm,
        minSqm: minSqm, maxSqm: maxSqm, onlyVerified: onlyVerified,
        onlyLocationVerified: onlyLocationVerified, currency: currency, sort: sort,
      );

  /// Ценовой фильтр включён — тогда показываем только объявления в выбранной валюте
  bool get hasPrice => minPrice != null || maxPrice != null;

  /// Сколько «дополнительных» фильтров включено (для значка на кнопке Filter)
  int get activeCount {
    var n = 0;
    if (dealType != null) n++;
    if (rentPeriod != null) n++;
    if (minPrice != null || maxPrice != null) n++;
    if (minBedrooms != null) n++;
    if (minBathrooms != null) n++;
    if (renovation.isNotEmpty) n++;
    if (kidsAllowed) n++;
    if (petsAllowed) n++;
    n += amenities.length;
    if (onlyOwner || onlyAgent) n++;
    if (leaseTerm != null) n++;
    if (minSqm != null || maxSqm != null) n++;
    if (onlyVerified) n++;
    if (onlyLocationVerified) n++;
    return n;
  }

  /// Проверка объявления (используется в демо-режиме)
  bool matches(Property p) {
    if (p.status != 'active' || !p.isFresh) return false;
    if (dealType != null && p.dealType != dealType) return false;
    if (rentPeriod != null && p.dealType == DealType.rent && p.rentPeriod != rentPeriod) return false;
    if (propertyType != null && p.propertyType != propertyType) return false;
    if (city.isNotEmpty && p.city != null && p.city != city) return false;
    if (areaId != null && p.areaId != areaId) return false;
    final q = query.trim().toLowerCase();
    if (q.isNotEmpty) {
      final hay = '${p.title} ${p.areaName ?? ''} ${p.address ?? ''}'.toLowerCase();
      if (!hay.contains(q)) return false;
    }
    if (hasPrice && p.currency != currency) return false;
    if (minPrice != null && p.price < minPrice!) return false;
    if (maxPrice != null && p.price > maxPrice!) return false;
    if (minBedrooms != null && (p.bedrooms ?? 0) < minBedrooms!) return false;
    if (minBathrooms != null && (p.bathrooms ?? 0) < minBathrooms!) return false;
    if (renovation.isNotEmpty && !renovation.contains(p.renovation)) return false;
    if (kidsAllowed && p.kidsAllowed != true) return false;
    if (petsAllowed && p.petsAllowed != true) return false;
    if (amenities.isNotEmpty && !amenities.every(p.amenities.contains)) return false;
    if (onlyOwner && !onlyAgent && p.listedBy != 'owner') return false;
    if (onlyAgent && !onlyOwner && p.listedBy != 'agent') return false;
    if (leaseTerm != null && p.leaseTerm != leaseTerm) return false;
    if (onlyVerified && !p.isVerified) return false;
    if (onlyLocationVerified && !p.propertyVerified) return false;
    final size = p.areaSqm ?? p.plotSqm;
    if (minSqm != null && (size ?? 0) < minSqm!) return false;
    if (maxSqm != null && (size ?? double.infinity) > maxSqm!) return false;
    return true;
  }
}

void sortProperties(List<Property> list, SortBy sort) {
  list.sort((a, b) {
    if (a.isPromoted != b.isPromoted) return a.isPromoted ? -1 : 1;
    return switch (sort) {
      SortBy.newest => b.createdAt.compareTo(a.createdAt),
      SortBy.priceAsc => a.price.compareTo(b.price),
      SortBy.priceDesc => b.price.compareTo(a.price),
    };
  });
}

class AppUser {
  final String id;
  final String? email;
  final String? fullName;
  final String? phone;
  final String role; // 'agent' | 'owner' | 'admin'
  final String? teamLevel; // команда Zumi: 'moderator' | 'owner'
  final String? agencyName;
  final bool phoneVerified;   // телефон подтверждён SMS-кодом
  final bool idVerified;      // NRC/паспорт + селфи проверены командой Zumi
  final String? licenceNo;    // номер регистрации ZIEA (агенты)
  final bool licenceVerified; // номер сверен с реестром ZIEA
  final String? avatarUrl;    // фото профиля
  final String? bio;          // «о себе» (агенты)
  final String? whatsapp;     // рабочий WhatsApp агента — виден на его странице
  final DateTime? createdAt;
  final String? idStatus;     // последняя заявка на проверку документа: pending | approved | rejected
  final String? idNote;       // причина отказа по документу
  final String? licenceNote;  // причина отказа по лицензии ZIEA
  final String contactMode;   // 'phone' | 'chat' — показывать ли номер в объявлениях
  final String? phoneChannel; // чем подтверждён телефон: whatsapp | sms
  final bool emailVerified;   // почта подтверждена кодом
  final bool marketingEmail;    // новости и предложения Zumi на почту
  final bool marketingWhatsapp; // новости и предложения Zumi в WhatsApp

  const AppUser({
    required this.id,
    this.email,
    this.fullName,
    this.phone,
    this.role = 'owner',
    this.teamLevel,
    this.agencyName,
    this.phoneVerified = false,
    this.idVerified = false,
    this.licenceNo,
    this.licenceVerified = false,
    this.avatarUrl,
    this.bio,
    this.whatsapp,
    this.createdAt,
    this.idStatus,
    this.idNote,
    this.licenceNote,
    this.contactMode = 'phone',
    this.phoneChannel,
    this.emailVerified = false,
    this.marketingEmail = false,
    this.marketingWhatsapp = false,
  });

  bool get profileComplete => (fullName ?? '').trim().length > 1;

  /// Команда Zumi (кабинет поддержки): модератор или владелец
  bool get isAdmin => role == 'admin';

  /// Владелец Zumi: + статистика, реклама, деньги, настройки, роли, журнал действий
  bool get isOwner => isAdmin && (teamLevel ?? 'owner') == 'owner';

  /// Проверен: имя + телефон (+ лицензия ZIEA у агентов). Документы больше не проверяем.
  bool get identityVerified => profileComplete && phoneVerified && (!isAgent || licenceVerified);

  /// Шаги проверки: (сделано, всего)
  (int, int) get verificationProgress {
    final steps = [profileComplete, phoneVerified, if (isAgent) licenceVerified];
    return (steps.where((s) => s).length, steps.length);
  }

  AppUser copyWith({
    String? fullName,
    String? phone,
    bool? phoneVerified,
    bool? idVerified,
    String? licenceNo,
    bool? licenceVerified,
    String? agencyName,
    String? avatarUrl,
    String? bio,
    String? whatsapp,
    String? idStatus,
    String? idNote,
    String? licenceNote,
    bool clearLicence = false,
    String? contactMode,
    String? phoneChannel,
    bool? emailVerified,
    bool? marketingEmail,
    bool? marketingWhatsapp,
  }) =>
      AppUser(
        id: id,
        email: email,
        fullName: fullName ?? this.fullName,
        phone: phone ?? this.phone,
        role: role,
        teamLevel: teamLevel,
        agencyName: agencyName ?? this.agencyName,
        phoneVerified: phoneVerified ?? this.phoneVerified,
        idVerified: idVerified ?? this.idVerified,
        licenceNo: clearLicence ? null : (licenceNo ?? this.licenceNo),
        licenceVerified: licenceVerified ?? this.licenceVerified,
        avatarUrl: avatarUrl ?? this.avatarUrl,
        bio: bio ?? this.bio,
        whatsapp: whatsapp ?? this.whatsapp,
        createdAt: createdAt,
        idStatus: idStatus ?? this.idStatus,
        idNote: idNote ?? this.idNote,
        licenceNote: clearLicence ? licenceNote : (licenceNote ?? this.licenceNote),
        contactMode: contactMode ?? this.contactMode,
        phoneChannel: phoneChannel ?? this.phoneChannel,
        emailVerified: emailVerified ?? this.emailVerified,
        marketingEmail: marketingEmail ?? this.marketingEmail,
        marketingWhatsapp: marketingWhatsapp ?? this.marketingWhatsapp,
      );

  bool get isAgent => role == 'agent';
}

class Quota {
  final int used;
  final int allowed;
  const Quota(this.used, this.allowed);
  int get left => used >= allowed ? 0 : allowed - used;
  bool get reached => used >= allowed;
}

/// Черновик объявления (мастер постинга). При правке заполняется из объявления.
class ListingDraft {
  ListingDraft();

  /// Правка существующего объявления
  factory ListingDraft.fromProperty(Property p) {
    final d = ListingDraft()
      ..dealType = p.dealType
      ..propertyType = p.propertyType
      ..title = p.title
      ..bedrooms = p.bedrooms ?? 1
      ..bathrooms = p.bathrooms ?? 1
      ..areaSqm = p.areaSqm ?? p.plotSqm
      ..description = p.description ?? ''
      ..amenities = {...p.amenities}
      ..photos = [for (final u in p.images) PickedPhoto.existing(u)]
      ..price = p.price
      ..currency = p.currency
      ..rentPeriod = p.rentPeriod ?? 'month'
      ..lat = p.lat
      ..lng = p.lng
      ..pinned = true
      ..address = p.address ?? ''
      ..nearby = {...p.nearby}
      ..contactPhone = p.contactPhone ?? '';
    return d;
  }

  DealType dealType = DealType.rent;
  PropertyType propertyType = PropertyType.house;
  String title = '';
  int bedrooms = 1;
  int bathrooms = 1;
  double? areaSqm;
  String description = '';
  Set<String> amenities = {};
  List<PickedPhoto> photos = [];
  double? price;
  String currency = 'ZMW';
  String rentPeriod = 'month';
  Area? area;
  double? lat; // точка на карте — обязательна при публикации
  double? lng;
  bool pinned = false; // человек сам поставил точку на карте
  String address = ''; // улица / номер участка — по желанию
  Map<String, String> nearby = {}; // что рядом (kNearbyPlaces → kNearbyDistances)
  String contactPhone = '';
}

/// Фото: новое (байты с телефона) или уже загруженное (url) — при правке объявления
class PickedPhoto {
  final String name;
  final Uint8List bytes;
  final String? url;
  PickedPhoto(this.name, this.bytes, {this.url});
  PickedPhoto.existing(String this.url)
      : name = 'existing',
        bytes = Uint8List(0);

  bool get isExisting => url != null;
}

/// Публичная страница человека: агент — с каталогом и отзывами, собственник — коротко
class PublicProfile {
  final String id;
  final String role;
  final String? fullName;
  final String? agencyName;
  final String? avatarUrl;
  final String? bio;
  final bool hasWhatsapp;   // сам номер выдаёт сервер по кнопке (как номер в объявлении)
  final String contactMode; // phone | chat
  final bool verified;
  final bool phoneVerified;
  final bool licenceVerified;
  final DateTime? memberSince;
  final int activeListings;

  const PublicProfile({
    required this.id,
    this.role = 'owner',
    this.fullName,
    this.agencyName,
    this.avatarUrl,
    this.bio,
    this.hasWhatsapp = false,
    this.contactMode = 'phone',
    this.verified = false,
    this.phoneVerified = false,
    this.licenceVerified = false,
    this.memberSince,
    this.activeListings = 0,
  });

  bool get isAgent => role == 'agent';
  String get displayName => (fullName ?? '').trim().isEmpty ? (isAgent ? 'Agent' : 'Owner') : fullName!.trim();

  factory PublicProfile.fromMap(Map<String, dynamic> m) => PublicProfile(
        id: m['id'] as String,
        role: (m['role'] as String?) ?? 'owner',
        fullName: m['full_name'] as String?,
        agencyName: m['agency_name'] as String?,
        avatarUrl: m['avatar_url'] as String?,
        bio: m['bio'] as String?,
        hasWhatsapp: (m['has_whatsapp'] as bool?) ?? ((m['whatsapp'] as String?)?.isNotEmpty ?? false),
        contactMode: (m['contact_mode'] as String?) ?? 'phone',
        verified: (m['verified'] as bool?) ?? false,
        phoneVerified: (m['phone_verified'] as bool?) ?? false,
        licenceVerified: (m['licence_verified'] as bool?) ?? false,
        memberSince: DateTime.tryParse((m['member_since'] as String?) ?? ''),
        activeListings: ((m['active_listings'] as num?) ?? 0).toInt(),
      );
}

/// «March 2026»
String formatMonthYear(DateTime d) {
  const months = ['January', 'February', 'March', 'April', 'May', 'June', 'July', 'August',
      'September', 'October', 'November', 'December'];
  return '${months[d.month - 1]} ${d.year}';
}

class Conversation {
  final String id;
  final String? propertyId;
  final String? propertyTitle;
  final String? propertyCover;
  final String? otherName;
  final String? lastMessage;
  final DateTime lastMessageAt;
  final int unread; // непрочитанные сообщения собеседника

  const Conversation({
    required this.id,
    this.propertyId,
    this.propertyTitle,
    this.propertyCover,
    this.otherName,
    this.lastMessage,
    required this.lastMessageAt,
    this.unread = 0,
  });

  factory Conversation.fromMap(Map<String, dynamic> m) => Conversation(
        id: m['id'] as String,
        propertyId: m['property_id'] as String?,
        propertyTitle: m['property_title'] as String?,
        propertyCover: m['property_cover'] as String?,
        otherName: m['other_name'] as String?,
        lastMessage: m['last_message'] as String?,
        lastMessageAt: DateTime.tryParse((m['last_message_at'] as String?) ?? '') ?? DateTime.now(),
        unread: (m['unread'] as num?)?.toInt() ?? 0,
      );
}

class ChatMessage {
  final String id;
  final String senderId;
  final String body;
  final DateTime createdAt;

  const ChatMessage({required this.id, required this.senderId, required this.body, required this.createdAt});

  factory ChatMessage.fromMap(Map<String, dynamic> m) => ChatMessage(
        id: m['id'] as String,
        senderId: m['sender_id'] as String,
        body: m['body'] as String,
        createdAt: DateTime.tryParse((m['created_at'] as String?) ?? '') ?? DateTime.now(),
      );
}

/// Понятная ошибка для пользователя
class AppException implements Exception {
  final String message;
  final String? code;
  AppException(this.message, {this.code});
  @override
  String toString() => message;
}

/// Причины жалобы на объявление
const reportReasons = <String, String>{
  'scam': 'Looks like a scam',
  'asked_prepayment': 'Asked to pay before viewing',
  'not_available': 'Property is not available',
  'wrong_info': 'Wrong price, photos or details',
  'duplicate': 'Duplicate listing',
  'other': 'Something else',
};

/// «16th of October»
String formatDayMonth(DateTime d) {
  const months = ['January', 'February', 'March', 'April', 'May', 'June', 'July', 'August',
      'September', 'October', 'November', 'December'];
  final day = d.day;
  final suffix = (day >= 11 && day <= 13)
      ? 'th'
      : switch (day % 10) { 1 => 'st', 2 => 'nd', 3 => 'rd', _ => 'th' };
  return '$day$suffix of ${months[d.month - 1]}';
}

/// «today», «yesterday», «3 days ago»
String daysAgo(DateTime d) {
  final n = DateTime.now().difference(d).inDays;
  if (n <= 0) return 'today';
  if (n == 1) return 'yesterday';
  return '$n days ago';
}

/// Результат автоматической проверки объекта (фото на месте + геолокация)
class PropertyCheckResult {
  final bool verified;
  final int distanceM;
  const PropertyCheckResult(this.verified, this.distanceM);
}

// ======================================================================
// Поддержка, отзывы, кабинет команды
// ======================================================================
DateTime _dt(dynamic v) => DateTime.tryParse((v as String?) ?? '') ?? DateTime.now();

const ticketCategories = <String, String>{
  'question': 'Question',
  'problem': 'Something is not working',
  'scam': 'Scam or fraud',
  'payment': 'Payments',
  'account': 'My account',
  'other': 'Other',
};

class SupportTicket {
  final String id;
  final String userId;
  final String? userName;
  final String category;
  final String subject;
  final String status; // open | answered | closed
  final String? lastMessage;
  final DateTime lastMessageAt;

  const SupportTicket({
    required this.id,
    required this.userId,
    this.userName,
    required this.category,
    required this.subject,
    required this.status,
    this.lastMessage,
    required this.lastMessageAt,
  });

  factory SupportTicket.fromMap(Map<String, dynamic> m) => SupportTicket(
        id: m['id'] as String,
        userId: m['user_id'] as String,
        userName: m['user_name'] as String?,
        category: (m['category'] as String?) ?? 'question',
        subject: m['subject'] as String,
        status: (m['status'] as String?) ?? 'open',
        lastMessage: m['last_message'] as String?,
        lastMessageAt: _dt(m['last_message_at']),
      );
}

class SupportMessage {
  final String id;
  final String senderId;
  final bool isStaff;
  final String body;
  final DateTime createdAt;

  const SupportMessage({
    required this.id,
    required this.senderId,
    required this.isStaff,
    required this.body,
    required this.createdAt,
  });

  factory SupportMessage.fromMap(Map<String, dynamic> m) => SupportMessage(
        id: m['id'] as String,
        senderId: m['sender_id'] as String,
        isStaff: (m['is_staff'] as bool?) ?? false,
        body: m['body'] as String,
        createdAt: _dt(m['created_at']),
      );
}

class Review {
  final String id;
  final String targetId;
  final String authorId;
  final String? authorName;
  final int rating;
  final String? body;
  final String status; // published | hidden
  final int flagsCount;
  final String? zumiReply;
  final DateTime createdAt;

  const Review({
    required this.id,
    required this.targetId,
    required this.authorId,
    this.authorName,
    required this.rating,
    this.body,
    this.status = 'published',
    this.flagsCount = 0,
    this.zumiReply,
    required this.createdAt,
  });

  factory Review.fromMap(Map<String, dynamic> m) => Review(
        id: m['id'] as String,
        targetId: m['target_id'] as String,
        authorId: m['author_id'] as String,
        authorName: m['author_name'] as String?,
        rating: (m['rating'] as num).toInt(),
        body: m['body'] as String?,
        status: (m['status'] as String?) ?? 'published',
        flagsCount: ((m['flags_count'] as num?) ?? 0).toInt(),
        zumiReply: m['zumi_reply'] as String?,
        createdAt: _dt(m['created_at']),
      );

  Review copyWith({String? status, int? flagsCount, String? zumiReply}) => Review(
        id: id,
        targetId: targetId,
        authorId: authorId,
        authorName: authorName,
        rating: rating,
        body: body,
        status: status ?? this.status,
        flagsCount: flagsCount ?? this.flagsCount,
        zumiReply: zumiReply ?? this.zumiReply,
        createdAt: createdAt,
      );
}

class Rating {
  final double average;
  final int count;
  const Rating(this.average, this.count);
}

class AdminStats {
  final int accounts, listingsNew, campaignsNew, idChecks, ownership, licences, reports, tickets, reviews, listings, users;
  final bool otpTestMode; // коды подтверждения в тестовом режиме (123456 подходит всем)
  final bool requireLicence; // агенты публикуют только после проверки лицензии ZIEA
  final int helpUnhelpful; // «не помогло» в статьях помощи за 7 дней
  const AdminStats({
    this.accounts = 0,
    this.listingsNew = 0,
    this.campaignsNew = 0,
    this.otpTestMode = false,
    this.requireLicence = false,
    this.helpUnhelpful = 0,
    this.idChecks = 0,
    this.ownership = 0,
    this.licences = 0,
    this.reports = 0,
    this.tickets = 0,
    this.reviews = 0,
    this.listings = 0,
    this.users = 0,
  });

  int get total =>
      accounts + listingsNew + campaignsNew + idChecks + ownership + licences + reports + tickets + reviews;

  /// Сколько ждёт решения: модератору — без кампаний агентов (их решает владелец во вкладке «Реклама»)
  int totalFor({required bool owner}) => owner ? total : total - campaignsNew;

  factory AdminStats.fromMap(Map<String, dynamic> m) {
    int n(String k) => ((m[k] as num?) ?? 0).toInt();
    return AdminStats(
      accounts: n('accounts'),
      listingsNew: n('listings_new'),
      campaignsNew: n('campaigns_new'),
      otpTestMode: (m['otp_test_mode'] as bool?) ?? false,
      requireLicence: (m['require_licence'] as bool?) ?? false,
      helpUnhelpful: n('help_unhelpful'),
      idChecks: n('id_checks'),
      ownership: n('ownership'),
      licences: n('licences'),
      reports: n('reports'),
      tickets: n('tickets'),
      reviews: n('reviews'),
      listings: n('listings'),
      users: n('users'),
    );
  }
}

class VerificationItem {
  final String id;
  final String userId;
  final String? userName;
  final String? userRole;
  final String kind; // identity | ownership | property
  final String? docType;
  final List<String> docPaths;
  final String? note;
  final String status;
  final String? reviewerNote;
  final String? propertyTitle;
  final DateTime createdAt;

  const VerificationItem({
    required this.id,
    required this.userId,
    this.userName,
    this.userRole,
    required this.kind,
    this.docType,
    this.docPaths = const [],
    this.note,
    this.status = 'pending',
    this.reviewerNote,
    this.propertyTitle,
    required this.createdAt,
  });

  factory VerificationItem.fromMap(Map<String, dynamic> m) => VerificationItem(
        id: m['id'] as String,
        userId: m['user_id'] as String,
        userName: m['user_name'] as String?,
        userRole: m['user_role'] as String?,
        kind: m['kind'] as String,
        docType: m['doc_type'] as String?,
        docPaths: _sl(m['doc_paths']),
        note: m['note'] as String?,
        status: (m['status'] as String?) ?? 'pending',
        reviewerNote: m['reviewer_note'] as String?,
        propertyTitle: m['property_title'] as String?,
        createdAt: _dt(m['created_at']),
      );
}

/// Новый аккаунт в кабинете команды: кто зарегистрировался и как далеко прошёл проверку
class AccountItem {
  final String id;
  final String? fullName;
  final String? email;
  final String role;
  final String? phone;
  final String? avatarUrl;
  final bool phoneVerified;
  final String? idStatus; // null | pending | approved | rejected
  final String? licenceNo;
  final bool licenceVerified;
  final int listings;
  final DateTime createdAt;
  final DateTime? reviewedAt;
  final bool banned;

  const AccountItem({
    required this.id,
    this.fullName,
    this.email,
    this.role = 'owner',
    this.phone,
    this.avatarUrl,
    this.phoneVerified = false,
    this.idStatus,
    this.licenceNo,
    this.licenceVerified = false,
    this.listings = 0,
    required this.createdAt,
    this.reviewedAt,
    this.banned = false,
  });

  bool get isAgent => role == 'agent';

  factory AccountItem.fromMap(Map<String, dynamic> m) => AccountItem(
        id: m['id'] as String,
        fullName: m['full_name'] as String?,
        email: m['email'] as String?,
        role: (m['role'] as String?) ?? 'owner',
        phone: m['phone'] as String?,
        avatarUrl: m['avatar_url'] as String?,
        phoneVerified: (m['phone_verified'] as bool?) ?? false,
        idStatus: m['id_status'] as String?,
        licenceNo: m['licence_no'] as String?,
        licenceVerified: (m['licence_verified'] as bool?) ?? false,
        listings: ((m['listings'] as num?) ?? 0).toInt(),
        createdAt: _dt(m['created_at']),
        reviewedAt: DateTime.tryParse((m['reviewed_at'] as String?) ?? ''),
        banned: (m['banned'] as bool?) ?? false,
      );
}

class LicenceItem {
  final String userId;
  final String? userName;
  final String licenceNo;
  const LicenceItem({required this.userId, this.userName, required this.licenceNo});
}

class ReportItem {
  final String id;
  final String propertyId;
  final String reason;
  final String? details;
  final String status; // new | reviewed | action_taken
  final String? reporterName;
  final String? propertyTitle;
  final String? propertyStatus;
  final String? propertyCover;
  final String? ownerId;
  final String? ownerName;
  final int totalReports;
  final DateTime createdAt;

  const ReportItem({
    required this.id,
    required this.propertyId,
    required this.reason,
    this.details,
    this.status = 'new',
    this.reporterName,
    this.propertyTitle,
    this.propertyStatus,
    this.propertyCover,
    this.ownerId,
    this.ownerName,
    this.totalReports = 1,
    required this.createdAt,
  });

  factory ReportItem.fromMap(Map<String, dynamic> m) => ReportItem(
        id: m['id'] as String,
        propertyId: m['property_id'] as String,
        reason: m['reason'] as String,
        details: m['details'] as String?,
        status: (m['status'] as String?) ?? 'new',
        reporterName: m['reporter_name'] as String?,
        propertyTitle: m['property_title'] as String?,
        propertyStatus: m['property_status'] as String?,
        propertyCover: m['property_cover'] as String?,
        ownerId: m['owner_id'] as String?,
        ownerName: m['owner_name'] as String?,
        totalReports: ((m['total_reports'] as num?) ?? 1).toInt(),
        createdAt: _dt(m['created_at']),
      );
}

class AuditEntry {
  final String action;
  final String targetType;
  final String targetId;
  final String? note;
  final String? adminName;
  final DateTime createdAt;

  const AuditEntry({
    required this.action,
    required this.targetType,
    required this.targetId,
    this.note,
    this.adminName,
    required this.createdAt,
  });

  factory AuditEntry.fromMap(Map<String, dynamic> m) => AuditEntry(
        action: m['action'] as String,
        targetType: m['target_type'] as String,
        targetId: '${m['target_id']}',
        note: m['note'] as String?,
        adminName: m['admin_name'] as String?,
        createdAt: _dt(m['created_at']),
      );
}

/// «5 min ago», «3 h ago», «2 d ago»
String timeAgo(DateTime t) {
  final d = DateTime.now().difference(t);
  if (d.inMinutes < 1) return 'just now';
  if (d.inMinutes < 60) return '${d.inMinutes} min ago';
  if (d.inHours < 24) return '${d.inHours} h ago';
  return '${d.inDays} d ago';
}

/// Кому принадлежат отзывы для объявления (автор). Демо-объявления — по имени контакта.
String? reviewTargetFor(Property p) => p.ownerId ?? (p.isDemo ? 'demo:${p.contactName}' : null);

// ======================================================================
// Продвижение: кампании агента
// ======================================================================

/// Где показывается продвигаемое объявление
const campaignPlacements = <String, (String, String)>{
  'search_top': ('Top of search results', 'First in the list of listings — on the home page and in search'),
  'home_featured': ('Featured on the home page', 'In the "Featured" row on the home page'),
};

class Campaign {
  final String id;
  final String ownerId;
  final String propertyId;
  final String advertiser;
  final String? contact; // ссылка или телефон
  final String placement;
  final String? imageUrl;
  final DateTime startsOn;
  final DateTime endsOn;
  final String status; // active | paused | stopped
  final String reviewStatus; // approved | pending (ждёт команду) | rejected
  final String? reviewNote;
  final DateTime createdAt;

  const Campaign({
    required this.id,
    required this.ownerId,
    required this.propertyId,
    required this.advertiser,
    this.contact,
    required this.placement,
    this.imageUrl,
    required this.startsOn,
    required this.endsOn,
    this.status = 'active',
    this.reviewStatus = 'approved',
    this.reviewNote,
    required this.createdAt,
  });

  factory Campaign.fromMap(Map<String, dynamic> m) => Campaign(
        id: m['id'] as String,
        ownerId: m['owner_id'] as String,
        propertyId: m['property_id'] as String,
        advertiser: m['advertiser'] as String,
        contact: m['contact'] as String?,
        placement: m['placement'] as String,
        imageUrl: m['image_url'] as String?,
        startsOn: DateTime.parse(m['starts_on'] as String),
        endsOn: DateTime.parse(m['ends_on'] as String),
        status: (m['status'] as String?) ?? 'active',
        reviewStatus: (m['review_status'] as String?) ?? 'approved',
        reviewNote: m['review_note'] as String?,
        createdAt: _dt(m['created_at']),
      );

  Campaign copyWith({String? status, String? reviewStatus, String? reviewNote}) => Campaign(
        id: id, ownerId: ownerId, propertyId: propertyId, advertiser: advertiser, contact: contact,
        placement: placement, imageUrl: imageUrl, startsOn: startsOn, endsOn: endsOn,
        status: status ?? this.status, reviewStatus: reviewStatus ?? this.reviewStatus,
        reviewNote: reviewStatus == 'approved' ? null : (reviewNote ?? this.reviewNote), createdAt: createdAt,
      );

  static DateTime _day(DateTime d) => DateTime(d.year, d.month, d.day);

  /// Что происходит сейчас: review · rejected · scheduled · live · paused · finished · stopped
  String get phase {
    final today = _day(DateTime.now());
    if (status == 'stopped') return 'stopped';
    if (_day(endsOn).isBefore(today)) return 'finished';
    if (reviewStatus == 'pending') return 'review';
    if (reviewStatus == 'rejected') return 'rejected';
    if (status == 'paused') return 'paused';
    if (_day(startsOn).isAfter(today)) return 'scheduled';
    return 'live';
  }

  bool get isLive => phase == 'live';
  int get days => _day(endsOn).difference(_day(startsOn)).inDays + 1;
  String get placementLabel => campaignPlacements[placement]?.$1 ?? placement;

  /// Контакт — ссылка на сайт или телефон
  bool get contactIsLink {
    final c = (contact ?? '').trim().toLowerCase();
    return c.startsWith('http') || c.startsWith('www.') || (c.contains('.') && !RegExp(r'^[+\d\s()-]+$').hasMatch(c));
  }
}

/// Черновик новой кампании (мастер «New campaign»)
class CampaignDraft {
  Property? property;
  String advertiser = '';
  String contact = '';
  String placement = 'search_top';
  Uint8List? image; // уже обрезано 3:2 и сжато
  DateTime? startsOn;
  DateTime? endsOn;
}

class CampaignDay {
  final DateTime day;
  final int views;
  final int clicks;
  final int calls;    // показали номер / нажали «Call»
  final int messages; // начали чат
  const CampaignDay(this.day, this.views, this.clicks, [this.calls = 0, this.messages = 0]);
}

class CampaignStats {
  final List<CampaignDay> days;
  const CampaignStats(this.days);
  int get views => days.fold(0, (a, d) => a + d.views);
  int get clicks => days.fold(0, (a, d) => a + d.clicks);
  int get calls => days.fold(0, (a, d) => a + d.calls);
  int get messages => days.fold(0, (a, d) => a + d.messages);
  double get ctr => views == 0 ? 0 : clicks * 100 / views;
}

/// «2.4%»
String formatCtr(double v) => '${v.toStringAsFixed(v >= 10 || v == 0 ? 0 : 1)}%';

/// «24 Oct 2026»
String formatShortDate(DateTime d) {
  const m = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
  return '${d.day} ${m[d.month - 1]} ${d.year}';
}

/// Подходит ли продвигаемое объявление к тому, что человек сейчас смотрит
bool campaignFits(Property p, SearchFilters? f) {
  if (p.status != 'active') return false;
  if (f == null) return true;
  if (f.dealType != null && p.dealType != f.dealType) return false;
  if (f.propertyType != null && p.propertyType != f.propertyType) return false;
  if (f.areaId != null && p.areaId != f.areaId) return false;
  if (f.city.isNotEmpty && p.city != null && p.city != f.city) return false;
  return true;
}

String isoDay(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

// ======================================================================
// Реклама (баннеры от команды Zumi)
// ======================================================================

/// Место показа → (название, описание, пропорции, мин. ширина, мин. высота, ширина после сжатия)
class AdPlacement {
  final String key, label, hint;
  final double ratio;
  final int minW, minH, outW;
  const AdPlacement(this.key, this.label, this.hint, this.ratio, this.minW, this.minH, this.outW);
  int get outH => (outW / ratio).round();
  String get ratioLabel => ratio == 3 ? '3:1' : (ratio == 6 ? '6:1' : (ratio == 2 ? '2:1' : ratio.toString()));
}

const adPlacements = <String, AdPlacement>{
  'home_hero': AdPlacement('home_hero', 'Home — big banner', 'Top of the home page. Several banners slide.',
      3, 1200, 400, 1500),
  'feed_strip': AdPlacement('feed_strip', 'Listings — thin strip', 'Between listings, at most one per 8 cards.',
      6, 1200, 200, 1500),
  'listing_block': AdPlacement('listing_block', 'Listing page — block', 'Under the description on every listing.',
      2, 1000, 500, 1400),
};

class Ad {
  final String id;
  final String advertiser;
  final String title;
  final String targetType; // link | phone | whatsapp
  final String target;
  final String placement;
  final String? imageUrl;
  final DateTime startsOn;
  final DateTime endsOn;
  final String status; // draft | active | paused | stopped
  final DateTime createdAt;

  const Ad({
    required this.id,
    required this.advertiser,
    required this.title,
    required this.targetType,
    required this.target,
    required this.placement,
    this.imageUrl,
    required this.startsOn,
    required this.endsOn,
    this.status = 'draft',
    required this.createdAt,
  });

  factory Ad.fromMap(Map<String, dynamic> m) => Ad(
        id: m['id'] as String,
        advertiser: m['advertiser'] as String,
        title: m['title'] as String,
        targetType: m['target_type'] as String,
        target: m['target'] as String,
        placement: m['placement'] as String,
        imageUrl: m['image_url'] as String?,
        startsOn: DateTime.parse(m['starts_on'] as String),
        endsOn: DateTime.parse(m['ends_on'] as String),
        status: (m['status'] as String?) ?? 'draft',
        createdAt: _dt(m['created_at']),
      );

  Ad copyWith({String? status}) => Ad(
        id: id, advertiser: advertiser, title: title, targetType: targetType, target: target,
        placement: placement, imageUrl: imageUrl, startsOn: startsOn, endsOn: endsOn,
        status: status ?? this.status, createdAt: createdAt,
      );

  static DateTime _day(DateTime d) => DateTime(d.year, d.month, d.day);

  /// draft · scheduled · live · paused · finished · stopped
  String get phase {
    final today = _day(DateTime.now());
    if (status == 'draft') return 'draft';
    if (status == 'stopped') return 'stopped';
    if (_day(endsOn).isBefore(today)) return 'finished';
    if (status == 'paused') return 'paused';
    if (_day(startsOn).isAfter(today)) return 'scheduled';
    return 'live';
  }

  bool get isLive => phase == 'live';
  AdPlacement get place => adPlacements[placement]!;
}

class AdDraft {
  String? id; // если задан — правка черновика
  String advertiser = '';
  String title = '';
  String targetType = 'link';
  String target = '';
  String placement = 'home_hero';
  Uint8List? image;
  String? imageUrl;
  DateTime? startsOn;
  DateTime? endsOn;
}

/// Кто чаще всех смотрит номера (кабинет команды)
class PhoneWatcher {
  final String userId;
  final String? fullName;
  final String? email;
  final String? phone;
  final int reveals;
  final int listings;
  final DateTime lastAt;
  final bool banned;

  const PhoneWatcher({
    required this.userId,
    this.fullName,
    this.email,
    this.phone,
    required this.reveals,
    required this.listings,
    required this.lastAt,
    this.banned = false,
  });

  factory PhoneWatcher.fromMap(Map<String, dynamic> m) => PhoneWatcher(
        userId: m['user_id'] as String,
        fullName: m['full_name'] as String?,
        email: m['email'] as String?,
        phone: m['phone'] as String?,
        reveals: ((m['reveals'] as num?) ?? 0).toInt(),
        listings: ((m['listings'] as num?) ?? 0).toInt(),
        lastAt: _dt(m['last_at']),
        banned: (m['banned'] as bool?) ?? false,
      );
}

/// Лимиты размера файлов (такие же стоят на сервере)
const kMaxImageBytes = 5 * 1024 * 1024; // фото — до 5 MB
const kMaxDocBytes = 10 * 1024 * 1024; // документы для проверки — до 10 MB

// ======================================================================
// Помощь: статьи (хранятся в базе, правятся из кабинета)
// ======================================================================
/// Разделы помощи: ключ → (название, иконка задаётся в экране)
const helpCategories = <String, String>{
  'account': 'Account and sign-in',
  'listings': 'Listings',
  'contact': 'Contacts and chats',
  'verification': 'Number checked and licences',
  'promotion': 'Promotion',
  'payments': 'Payments and refunds',
  'safety': 'Safety and scams',
  'technical': 'Technical problems',
};

class HelpArticle {
  final String id;
  final String category;
  final String title;
  final String body; // абзацы через пустую строку, «- » — пункт списка, «## » — подзаголовок
  final int sort;
  final bool published;
  final bool webOnly; // только на сайте (про оплату — правила Apple и Google)
  final DateTime? updatedAt;

  const HelpArticle({
    required this.id,
    required this.category,
    required this.title,
    required this.body,
    this.sort = 100,
    this.published = true,
    this.webOnly = false,
    this.updatedAt,
  });

  String get categoryLabel => helpCategories[category] ?? category;

  factory HelpArticle.fromMap(Map<String, dynamic> m) => HelpArticle(
        id: m['id'] as String,
        category: (m['category'] as String?) ?? 'account',
        title: m['title'] as String,
        body: (m['body'] as String?) ?? '',
        sort: ((m['sort'] as num?) ?? 100).toInt(),
        published: (m['published'] as bool?) ?? true,
        webOnly: (m['web_only'] as bool?) ?? false,
        updatedAt: DateTime.tryParse((m['updated_at'] as String?) ?? ''),
      );

  Map<String, dynamic> toMap() => {
        'category': category,
        'title': title.trim(),
        'body': body.trim(),
        'sort': sort,
        'published': published,
        'web_only': webOnly,
      };

  HelpArticle copyWith({String? id, String? category, String? title, String? body, int? sort, bool? published, bool? webOnly}) =>
      HelpArticle(
        id: id ?? this.id,
        category: category ?? this.category,
        title: title ?? this.title,
        body: body ?? this.body,
        sort: sort ?? this.sort,
        published: published ?? this.published,
        webOnly: webOnly ?? this.webOnly,
        updatedAt: DateTime.now(),
      );

  /// Поиск: все слова запроса есть в заголовке или тексте
  bool matches(String query) {
    final words = query.toLowerCase().split(RegExp(r'\s+')).where((w) => w.length > 1);
    final text = '${title.toLowerCase()} ${body.toLowerCase()} ${categoryLabel.toLowerCase()}';
    return words.every(text.contains);
  }
}

/// Оценки статьи для команды
class HelpRating {
  final String articleId;
  final String title;
  final String category;
  final int yes;
  final int no;
  final List<(String, DateTime)> comments;

  const HelpRating({
    required this.articleId,
    required this.title,
    required this.category,
    required this.yes,
    required this.no,
    this.comments = const [],
  });

  int get total => yes + no;
  double get helpfulShare => total == 0 ? 1 : yes / total;

  factory HelpRating.fromMap(Map<String, dynamic> m) => HelpRating(
        articleId: m['article_id'] as String,
        title: m['title'] as String,
        category: (m['category'] as String?) ?? '',
        yes: ((m['yes'] as num?) ?? 0).toInt(),
        no: ((m['no'] as num?) ?? 0).toInt(),
        comments: [
          for (final c in (m['comments'] as List? ?? const []))
            ((c as Map)['text'] as String, DateTime.tryParse(c['at'] as String? ?? '') ?? DateTime.now()),
        ],
      );
}

// ======================================================================
// Команда Zumi и панель владельца
// ======================================================================
class TeamMember {
  final String userId;
  final String? fullName;
  final String? email;
  final String level; // moderator | owner

  const TeamMember({required this.userId, this.fullName, this.email, required this.level});

  factory TeamMember.fromMap(Map<String, dynamic> m) => TeamMember(
        userId: m['user_id'] as String,
        fullName: m['full_name'] as String?,
        email: m['email'] as String?,
        level: (m['level'] as String?) ?? 'owner',
      );
}

/// Одна точка графика (час или день)
class DashPoint {
  final String t; // «14:00» или «2026-10-25»
  final int visits, visitors, contacts, newUsers, newListings;
  const DashPoint(this.t, this.visits, this.visitors, this.contacts, this.newUsers, this.newListings);
}

/// Главные цифры за день / неделю / месяц
class Dashboard {
  final String period; // day | week | month
  final DateTime from;
  final DateTime to;
  final Map<String, int> totals;
  final List<DashPoint> series;
  final List<(String, int)> topAreas;
  final List<(String, String, int)> topFilters; // (фильтр, значение, сколько раз)

  const Dashboard({
    required this.period,
    required this.from,
    required this.to,
    required this.totals,
    required this.series,
    required this.topAreas,
    required this.topFilters,
  });

  int t(String key) => totals[key] ?? 0;
  int get contacts => t('phone_views') + t('new_chats');

  factory Dashboard.fromMap(Map<String, dynamic> m) {
    int n(dynamic v) => ((v as num?) ?? 0).toInt();
    final totals = <String, int>{
      for (final e in (Map<String, dynamic>.from(m['totals'] as Map? ?? const {})).entries) e.key: n(e.value),
    };
    return Dashboard(
      period: (m['period'] as String?) ?? 'day',
      from: DateTime.tryParse('${m['from']}') ?? DateTime.now(),
      to: DateTime.tryParse('${m['to']}') ?? DateTime.now(),
      totals: totals,
      series: [
        for (final p in (m['series'] as List? ?? const []))
          DashPoint('${(p as Map)['t']}', n(p['visits']), n(p['visitors']), n(p['contacts']), n(p['new_users']),
              n(p['new_listings'])),
      ],
      topAreas: [for (final a in (m['top_areas'] as List? ?? const [])) ('${(a as Map)['name']}', n(a['n']))],
      topFilters: [
        for (final f in (m['top_filters'] as List? ?? const [])) ('${(f as Map)['dim']}', '${f['value']}', n(f['n'])),
      ],
    );
  }

  /// Таблица для выгрузки (CSV, открывается в Excel / Google Sheets)
  String toCsv() {
    String q(Object v) {
      final s = '$v';
      return s.contains(',') || s.contains('"') ? '"${s.replaceAll('"', '""')}"' : s;
    }

    final b = StringBuffer()
      ..writeln('Zumi statistics,${q(period)},${isoDay(from)},${isoDay(to)}')
      ..writeln()
      ..writeln('Metric,Value');
    for (final e in totals.entries) {
      b.writeln('${q(e.key)},${e.value}');
    }
    b
      ..writeln()
      ..writeln('${period == 'day' ? 'Hour' : 'Day'},Visits,Visitors,Contacts,New users,New listings');
    for (final p in series) {
      b.writeln('${q(p.t)},${p.visits},${p.visitors},${p.contacts},${p.newUsers},${p.newListings}');
    }
    b
      ..writeln()
      ..writeln('Popular area,Searches');
    for (final (name, n) in topAreas) {
      b.writeln('${q(name)},$n');
    }
    b
      ..writeln()
      ..writeln('Filter,Value,Searches');
    for (final (dim, value, n) in topFilters) {
      b.writeln('${q(dim)},${q(value)},$n');
    }
    return b.toString();
  }
}

// ======================================================================
// Отчёт по рекламе (владелец): баннеры и кампании продвижения по дням
// ======================================================================
class AdReportDay {
  final DateTime day;
  final int views, clicks, calls, messages;
  const AdReportDay(this.day, this.views, this.clicks, this.calls, this.messages);
}

class AdReportItem {
  final String kind; // banner | campaign
  final String id;
  final String title;
  final String advertiser;
  final String placement;
  final String status;
  final DateTime? startsOn;
  final DateTime? endsOn;
  final int views, clicks, calls, messages;
  final List<AdReportDay> days;

  const AdReportItem({
    required this.kind,
    required this.id,
    required this.title,
    required this.advertiser,
    required this.placement,
    required this.status,
    this.startsOn,
    this.endsOn,
    required this.views,
    required this.clicks,
    this.calls = 0,
    this.messages = 0,
    this.days = const [],
  });

  bool get isBanner => kind == 'banner';
  double get ctr => views == 0 ? 0 : clicks * 100 / views;
  String get placementLabel => isBanner
      ? (adPlacements[placement]?.label ?? placement)
      : (campaignPlacements[placement]?.$1 ?? placement);

  factory AdReportItem.fromMap(Map<String, dynamic> m) {
    int n(dynamic v) => ((v as num?) ?? 0).toInt();
    return AdReportItem(
      kind: (m['kind'] as String?) ?? 'banner',
      id: '${m['id']}',
      title: (m['title'] as String?) ?? '',
      advertiser: (m['advertiser'] as String?) ?? '',
      placement: (m['placement'] as String?) ?? '',
      status: (m['status'] as String?) ?? '',
      startsOn: DateTime.tryParse('${m['starts_on']}'),
      endsOn: DateTime.tryParse('${m['ends_on']}'),
      views: n(m['views']),
      clicks: n(m['clicks']),
      calls: n(m['calls']),
      messages: n(m['messages']),
      days: [
        for (final d in (m['days'] as List? ?? const []))
          AdReportDay(DateTime.tryParse('${(d as Map)['day']}') ?? DateTime.now(), n(d['views']), n(d['clicks']),
              n(d['calls']), n(d['messages'])),
      ],
    );
  }

  /// Отчёт для рекламодателя (CSV — открывается в Excel / Google Sheets)
  static String csv(List<AdReportItem> items) {
    String q(Object v) {
      final s = '$v';
      return s.contains(',') || s.contains('"') ? '"${s.replaceAll('"', '""')}"' : s;
    }

    final b = StringBuffer()
      ..writeln('Zumi advertising report')
      ..writeln()
      ..writeln('Type,Advertiser,Title,Placement,Dates,Views,Clicks,Click rate %,Calls,Messages');
    for (final i in items) {
      b.writeln([
        i.isBanner ? 'Banner' : 'Listing promotion',
        q(i.advertiser),
        q(i.title),
        q(i.placementLabel),
        '${i.startsOn == null ? '' : isoDay(i.startsOn!)} – ${i.endsOn == null ? '' : isoDay(i.endsOn!)}',
        i.views,
        i.clicks,
        i.ctr.toStringAsFixed(1),
        i.calls,
        i.messages,
      ].join(','));
    }
    for (final i in items) {
      b
        ..writeln()
        ..writeln('${q(i.advertiser)} — ${q(i.title)}')
        ..writeln('Day,Views,Clicks,Click rate %,Calls,Messages');
      for (final d in i.days) {
        final ctr = d.views == 0 ? 0 : d.clicks * 100 / d.views;
        b.writeln('${isoDay(d.day)},${d.views},${d.clicks},${ctr.toStringAsFixed(1)},${d.calls},${d.messages}');
      }
    }
    return b.toString();
  }
}

// ======================================================================
// Раздел разработчика: только числа
// ======================================================================
class DevStats {
  final DateTime from, to;
  final int dauToday, dauAvg, mau, returningShare;
  final List<(DateTime, int, int)> daily; // (день, посетители, вернулись)
  final List<(DateTime, int)> months;
  final Map<String, int> funnelSeller; // signups, phone, listing, contact
  final Map<String, int> funnelBuyer; // signups, phone, contact
  final List<(String, String, int, int)> platforms; // (платформа, версия, посещения, люди)
  final List<(String, String, String, int, DateTime?)> errors; // (платформа, версия, текст, раз, последний)

  const DevStats({
    required this.from,
    required this.to,
    required this.dauToday,
    required this.dauAvg,
    required this.mau,
    required this.returningShare,
    required this.daily,
    required this.months,
    required this.funnelSeller,
    required this.funnelBuyer,
    required this.platforms,
    required this.errors,
  });

  factory DevStats.fromMap(Map<String, dynamic> m) {
    int n(dynamic v) => ((v as num?) ?? 0).toInt();
    Map<String, int> f(dynamic v) => {for (final e in (v as Map? ?? const {}).entries) '${e.key}': n(e.value)};
    return DevStats(
      from: DateTime.tryParse('${m['from']}') ?? DateTime.now(),
      to: DateTime.tryParse('${m['to']}') ?? DateTime.now(),
      dauToday: n(m['dau_today']),
      dauAvg: n(m['dau_avg']),
      mau: n(m['mau']),
      returningShare: n(m['returning_share']),
      daily: [
        for (final d in (m['daily'] as List? ?? const []))
          (DateTime.tryParse('${(d as Map)['day']}') ?? DateTime.now(), n(d['visitors']), n(d['returning'])),
      ],
      months: [
        for (final d in (m['months'] as List? ?? const []))
          (DateTime.tryParse('${(d as Map)['month']}') ?? DateTime.now(), n(d['visitors'])),
      ],
      funnelSeller: f(m['funnel_seller']),
      funnelBuyer: f(m['funnel_buyer']),
      platforms: [
        for (final p in (m['platforms'] as List? ?? const []))
          ('${(p as Map)['platform']}', '${p['version']}', n(p['visits']), n(p['visitors'])),
      ],
      errors: [
        for (final e in (m['errors'] as List? ?? const []))
          ('${(e as Map)['platform']}', '${e['version']}', '${e['message']}', n(e['n']),
              DateTime.tryParse('${e['last_at']}')),
      ],
    );
  }
}

// ======================================================================
// Помощь продавцу: цены похожих объявлений и советы после публикации
// ======================================================================
/// Цены похожих объявлений в районе (только если их не меньше 5)
class PriceStats {
  final int n;
  final double? p25, median, p75;
  const PriceStats(this.n, [this.p25, this.median, this.p75]);
  bool get enough => n >= 5 && p25 != null && p75 != null;

  factory PriceStats.fromMap(Map<String, dynamic> m) {
    double? d(dynamic v) => (v as num?)?.toDouble();
    return PriceStats(((m['n'] as num?) ?? 0).toInt(), d(m['p25']), d(m['median']), d(m['p75']));
  }
}

/// Совет по объявлению: код и числа (текст — в приложении)
class ListingTip {
  final String code;
  final Map<String, dynamic> params;
  const ListingTip(this.code, [this.params = const {}]);

  int n(String k) => ((params[k] as num?) ?? 0).toInt();

  /// Текст совета; currency — валюта объявления (для цен)
  String text(String currency) => switch (code) {
        'confirm' => 'Confirm it is still available — otherwise it will be hidden from search in ${n('days_left')} days.',
        'no_contacts' => '${n('views')} people viewed it this week, but nobody contacted you. '
            'Check the price and add details people ask about: water, power, security.',
        'saved_no_contact' => '${n('saves')} people saved it, but nobody contacted you yet. '
            'Add more details or check the price.',
        'price_high' => 'The price is higher than most similar homes in this area '
            '(usually ${formatMoney(n('p25').toDouble(), currency)}–${formatMoney(n('p75').toDouble(), currency)}).',
        'price_low' => 'The price is much lower than similar homes '
            '(usually ${formatMoney(n('p25').toDouble(), currency)}–${formatMoney(n('p75').toDouble(), currency)}). '
            'Check for a typo — a very low price can look like a scam.',
        'photos' => n('photos') == 0
            ? 'No photos yet. Add at least 5: every room, the outside and the street.'
            : 'Only ${n('photos')} ${n('photos') == 1 ? 'photo' : 'photos'}. Add at least 5: every room, the outside and the street.',
        'description' => 'Add details people ask about: water, power, security, schools and roads.',
        'few_views' => 'Few views this week (${n('views')}). Try a clearer title and a bright cover photo.',
        'doing_well' => 'Doing well: ${n('contacts')} contacts this week.',
        _ => code,
      };

  /// Что нажать: edit · confirm · verify · null
  String? get action => switch (code) {
        'confirm' => 'confirm',
        'doing_well' => null,
        _ => 'edit',
      };

  bool get positive => code == 'doing_well';
}

class ListingStats {
  final String id;
  final int views7, contacts7, saves7;
  final List<(DateTime, int, int)> days; // (день, просмотры, контакты) — 14 дней
  final List<ListingTip> tips;

  const ListingStats({
    required this.id,
    this.views7 = 0,
    this.contacts7 = 0,
    this.saves7 = 0,
    this.days = const [],
    this.tips = const [],
  });

  factory ListingStats.fromMap(Map<String, dynamic> m) {
    int n(dynamic v) => ((v as num?) ?? 0).toInt();
    return ListingStats(
      id: '${m['id']}',
      views7: n(m['views7']),
      contacts7: n(m['contacts7']),
      saves7: n(m['saves7']),
      days: [
        for (final d in (m['days'] as List? ?? const []))
          (DateTime.tryParse('${(d as Map)['day']}') ?? DateTime.now(), n(d['views']), n(d['contacts'])),
      ],
      tips: [
        for (final t in (m['tips'] as List? ?? const []))
          // проверку на месте больше не делаем — старый совет не показываем
          // «подтвердите» показывает отдельная карточка «Ещё доступно?»; проверки на месте больше нет
          if (!const {'verify_onsite', 'confirm'}.contains('${(t as Map)['code']}')) ListingTip('${t['code']}', Map<String, dynamic>.from(t)),
      ],
    );
  }
}

// ======================================================================
// Отзывы о приложении (кабинет разработчика)
// ======================================================================

/// Что не работает — варианты в окне отзыва (коды совпадают с сервером)
const kFeedbackIssues = <String, String>{
  'slow': 'Slow or freezes',
  'photos': 'Photos don\'t load',
  'login': 'Sign-in or codes',
  'search': 'Hard to find homes',
  'post': 'Posting a listing',
  'chat': 'Chats and contacts',
  'confusing': 'Confusing to use',
  'crash': 'Errors or crashes',
  'other': 'Something else',
};

class AppFeedbackItem {
  final int rating;
  final List<String> issues;
  final String? comment;
  final String? platform;
  final String? version;
  final DateTime at;
  final String who;

  const AppFeedbackItem({
    required this.rating,
    this.issues = const [],
    this.comment,
    this.platform,
    this.version,
    required this.at,
    this.who = 'Guest',
  });

  factory AppFeedbackItem.fromMap(Map<String, dynamic> m) => AppFeedbackItem(
        rating: ((m['rating'] as num?) ?? 0).toInt(),
        issues: _sl(m['issues']),
        comment: m['comment'] as String?,
        platform: m['platform'] as String?,
        version: m['version'] as String?,
        at: DateTime.tryParse('${m['at']}') ?? DateTime.now(),
        who: (m['who'] as String?) ?? 'Guest',
      );
}

class AppFeedbackReport {
  final int count;
  final double? average;
  final Map<int, int> byRating;
  final Map<String, int> issues;
  final List<AppFeedbackItem> items;

  const AppFeedbackReport({
    this.count = 0,
    this.average,
    this.byRating = const {},
    this.issues = const {},
    this.items = const [],
  });

  factory AppFeedbackReport.fromMap(Map<String, dynamic> m) => AppFeedbackReport(
        count: ((m['count'] as num?) ?? 0).toInt(),
        average: (m['average'] as num?)?.toDouble(),
        byRating: {
          for (final e in Map<String, dynamic>.from((m['by_rating'] as Map?) ?? const {}).entries)
            int.tryParse(e.key) ?? 0: ((e.value as num?) ?? 0).toInt(),
        },
        issues: {
          for (final e in Map<String, dynamic>.from((m['issues'] as Map?) ?? const {}).entries)
            e.key: ((e.value as num?) ?? 0).toInt(),
        },
        items: [
          for (final i in (m['items'] as List? ?? const []))
            AppFeedbackItem.fromMap(Map<String, dynamic>.from(i as Map)),
        ],
      );
}
