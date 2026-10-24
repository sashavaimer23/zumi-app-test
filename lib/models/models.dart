import 'dart:typed_data';

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
  final bool isPromoted;
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
  final DateTime? confirmedAt;          // автор подтвердил «ещё доступно»
  final String? agencyName;
  final String? highlights;             // «Gated street | Borehole | Solar backup»
  final String? ownerAvatarUrl;         // фото автора
  final List<String> thumbs;            // маленькие копии фото для карточек (экономия трафика)
  final bool isFresh;                   // подтверждено «ещё доступно» за последние 60 дней
  final String contactMode;             // 'phone' — номер можно показать, 'chat' — только чат
  final bool hasPhone;                  // у объявления есть номер (сам номер выдаёт сервер по кнопке)
  final String? moderationNote;         // почему модератор не одобрил

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
    this.isPromoted = false,
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
    this.confirmedAt,
    this.agencyName,
    this.highlights,
    this.ownerAvatarUrl,
    this.thumbs = const [],
    this.isFresh = true,
    this.contactMode = 'phone',
    bool? hasPhone,
    this.moderationNote,
  }) : hasPhone = hasPhone ?? (contactPhone != null && contactPhone != '');

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
        confirmedAt: DateTime.tryParse((m['confirmed_at'] as String?) ?? ''),
        agencyName: m['agency_name'] as String?,
        highlights: m['highlights'] as String?,
        ownerAvatarUrl: m['owner_avatar_url'] as String?,
        thumbs: _sl(m['thumb_urls']),
        isFresh: (m['is_fresh'] as bool?) ?? true,
        contactMode: (m['contact_mode'] as String?) ?? 'phone',
        hasPhone: m['has_phone'] as bool?,
        moderationNote: m['moderation_note'] as String?,
      );

  /// Плашка «Verified» — автор (собственник или агент) прошёл проверку личности
  bool get isVerified => ownerIdentityVerified;

  Property copyWith({
    String? status,
    bool? isPromoted,
    bool? propertyVerified,
    bool? ownerIdentityVerified,
    DateTime? confirmedAt,
    String? ownerAvatarUrl,
    String? contactName,
    String? contactMode,
  }) =>
      Property(
        id: id, ownerId: ownerId, title: title, description: description,
        dealType: dealType, propertyType: propertyType, price: price, currency: currency,
        rentPeriod: rentPeriod, bedrooms: bedrooms, bathrooms: bathrooms, areaSqm: areaSqm,
        plotSqm: plotSqm, amenities: amenities, areaId: areaId, areaName: areaName, city: city,
        address: address, lat: lat, lng: lng, status: status ?? this.status,
        isPromoted: isPromoted ?? this.isPromoted, images: images, listedBy: listedBy,
        contactName: contactName ?? this.contactName, contactPhone: contactPhone, renovation: renovation,
        kidsAllowed: kidsAllowed, petsAllowed: petsAllowed, leaseTerm: leaseTerm,
        viewsCount: viewsCount, createdAt: createdAt, isDemo: isDemo,
        propertyVerified: propertyVerified ?? this.propertyVerified,
        propertyVerifyMethod: propertyVerifyMethod,
        propertyVerifiedAt: (propertyVerified ?? false) ? DateTime.now() : propertyVerifiedAt,
        ownershipVerified: ownershipVerified,
        ownerIdentityVerified: ownerIdentityVerified ?? this.ownerIdentityVerified,
        ownerPhoneVerified: ownerPhoneVerified, confirmedAt: confirmedAt ?? this.confirmedAt,
        agencyName: agencyName, highlights: highlights,
        ownerAvatarUrl: ownerAvatarUrl ?? this.ownerAvatarUrl, thumbs: thumbs,
        isFresh: confirmedAt != null ? true : isFresh,
        contactMode: contactMode ?? this.contactMode, hasPhone: hasPhone, moderationNote: moderationNote,
      );

  bool get isPending => status == 'pending';
  bool get chatOnly => contactMode == 'chat';

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

  const AppUser({
    required this.id,
    this.email,
    this.fullName,
    this.phone,
    this.role = 'owner',
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
  });

  bool get profileComplete => (fullName ?? '').trim().length > 1;

  /// Команда Zumi (кабинет поддержки)
  bool get isAdmin => role == 'admin';

  /// Плашка Verified: профиль + телефон + документ (+ лицензия ZIEA у агентов)
  bool get identityVerified =>
      profileComplete && phoneVerified && idVerified && (!isAgent || licenceVerified);

  /// Шаги проверки: (сделано, всего)
  (int, int) get verificationProgress {
    final steps = [profileComplete, phoneVerified, idVerified, if (isAgent) licenceVerified];
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
  }) =>
      AppUser(
        id: id,
        email: email,
        fullName: fullName ?? this.fullName,
        phone: phone ?? this.phone,
        role: role,
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
  double? lat; // точка на карте (если не выбрана — центр района)
  double? lng;
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
  final String? whatsapp;
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
    this.whatsapp,
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
        whatsapp: m['whatsapp'] as String?,
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

  const Conversation({
    required this.id,
    this.propertyId,
    this.propertyTitle,
    this.propertyCover,
    this.otherName,
    this.lastMessage,
    required this.lastMessageAt,
  });

  factory Conversation.fromMap(Map<String, dynamic> m) => Conversation(
        id: m['id'] as String,
        propertyId: m['property_id'] as String?,
        propertyTitle: m['property_title'] as String?,
        propertyCover: m['property_cover'] as String?,
        otherName: m['other_name'] as String?,
        lastMessage: m['last_message'] as String?,
        lastMessageAt: DateTime.tryParse((m['last_message_at'] as String?) ?? '') ?? DateTime.now(),
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
  final int accounts, listingsNew, idChecks, ownership, licences, reports, tickets, reviews, listings, users;
  const AdminStats({
    this.accounts = 0,
    this.listingsNew = 0,
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
      accounts + listingsNew + idChecks + ownership + licences + reports + tickets + reviews;

  factory AdminStats.fromMap(Map<String, dynamic> m) {
    int n(String k) => ((m[k] as num?) ?? 0).toInt();
    return AdminStats(
      accounts: n('accounts'),
      listingsNew: n('listings_new'),
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
        createdAt: _dt(m['created_at']),
      );

  Campaign copyWith({String? status}) => Campaign(
        id: id, ownerId: ownerId, propertyId: propertyId, advertiser: advertiser, contact: contact,
        placement: placement, imageUrl: imageUrl, startsOn: startsOn, endsOn: endsOn,
        status: status ?? this.status, createdAt: createdAt,
      );

  static DateTime _day(DateTime d) => DateTime(d.year, d.month, d.day);

  /// Что происходит сейчас: scheduled · live · paused · finished · stopped
  String get phase {
    final today = _day(DateTime.now());
    if (status == 'stopped') return 'stopped';
    if (_day(endsOn).isBefore(today)) return 'finished';
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
