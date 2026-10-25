import 'dart:async';

import 'package:flutter/foundation.dart' show kIsWeb;

import 'package:supabase_flutter/supabase_flutter.dart' hide SortBy;

import '../models/models.dart';
import 'device_id.dart';
import 'images.dart';
import 'repository.dart';

/// Работа с настоящим сервером Supabase (таблицы из supabase/*.sql).
class SupabaseRepository implements Repository {
  SupabaseRepository() {
    _authSub = _db.auth.onAuthStateChange.listen((state) async {
      _user = state.session?.user == null ? null : await _loadProfile(state.session!.user);
      _userCtrl.add(_user);
    });
  }

  SupabaseClient get _db => Supabase.instance.client;
  final _userCtrl = StreamController<AppUser?>.broadcast();
  AppUser? _user;
  // ignore: unused_field
  StreamSubscription<AuthState>? _authSub;
  List<Area>? _areasCache;

  static const _bucket = 'property-images';

  @override
  bool get isDemo => false;

  // ---------------- авторизация ----------------
  @override
  AppUser? get currentUser => _user;

  @override
  Stream<AppUser?> get userChanges => _userCtrl.stream;

  Future<AppUser> _loadProfile(User u) async {
    try {
      // телефон в таблице профилей скрыт от всех — свой номер берём из Auth
      final row = await _db
          .from('profiles')
          .select('id, role, full_name, agency_name, phone_verified_at, id_verified_at, '
              'agent_licence_no, licence_verified_at, avatar_url, bio, created_at, contact_mode, team_level')
          .eq('id', u.id)
          .maybeSingle();
      Map<String, dynamic>? ver;
      try {
        ver = Map<String, dynamic>.from(await _db.rpc('my_verification') as Map);
      } catch (_) {/* не критично */}
      return AppUser(
        id: u.id,
        email: u.email,
        fullName: row?['full_name'] as String? ?? u.userMetadata?['full_name'] as String?,
        phone: (ver?['phone'] as String?) ??
            ((u.phone?.isNotEmpty ?? false) ? '+${u.phone!.replaceAll('+', '')}' : u.userMetadata?['phone'] as String?),
        role: (row?['role'] as String?) ?? 'owner',
        teamLevel: row?['team_level'] as String?,
        agencyName: row?['agency_name'] as String?,
        phoneVerified: row?['phone_verified_at'] != null,
        idVerified: row?['id_verified_at'] != null,
        licenceNo: row?['agent_licence_no'] as String?,
        licenceVerified: row?['licence_verified_at'] != null,
        avatarUrl: row?['avatar_url'] as String?,
        bio: row?['bio'] as String?,
        whatsapp: ver?['whatsapp'] as String?,
        createdAt: DateTime.tryParse((row?['created_at'] as String?) ?? ''),
        idStatus: ver?['id_status'] as String?,
        idNote: ver?['id_note'] as String?,
        licenceNote: ver?['licence_note'] as String?,
        contactMode: (row?['contact_mode'] as String?) ?? 'phone',
        phoneChannel: ver?['phone_channel'] as String?,
        emailVerified: (ver?['email_verified'] as bool?) ?? false,
        marketingEmail: (ver?['marketing_email'] as bool?) ?? false,
        marketingWhatsapp: (ver?['marketing_whatsapp'] as bool?) ?? false,
      );
    } catch (_) {
      return AppUser(id: u.id, email: u.email);
    }
  }

  Future<T> _guard<T>(Future<T> Function() fn) async {
    try {
      return await fn();
    } on AuthException catch (e) {
      throw AppException(e.message);
    } on PostgrestException catch (e) {
      if (e.message.contains('LISTING_LIMIT_REACHED')) {
        throw AppException('Listing limit reached', code: 'LISTING_LIMIT_REACHED');
      }
      if (e.message.contains('OWN_LISTING')) throw AppException('This is your own listing');
      if (e.message.contains('ACCOUNT_BLOCKED')) {
        throw AppException('Your account is blocked. Please contact Zumi support.', code: 'BLOCKED');
      }
      if (e.message.contains('NOT_ADMIN')) throw AppException('Only the Zumi team can do this');
      if (e.message.contains('PHONE_NOT_VERIFIED')) {
        throw AppException('Confirm your phone to see numbers', code: 'PHONE_NOT_VERIFIED');
      }
      if (e.message.contains('CHAT_ONLY')) {
        throw AppException('This author prefers chat — send a message instead', code: 'CHAT_ONLY');
      }
      if (e.message.contains('REVEAL_LIMIT')) {
        throw AppException('You have seen 15 numbers today. Please use chat or try again tomorrow.', code: 'LIMIT');
      }
      if (e.message.contains('NO_PHONE')) throw AppException('No phone number here — use chat');
      if (e.message.contains('OWNER_ONLY')) throw AppException('Only the Zumi owner can do this', code: 'OWNER_ONLY');
      if (e.message.contains('USER_NOT_FOUND')) throw AppException('No Zumi account with this email');
      if (e.message.contains('NOT_YOURSELF')) throw AppException('You cannot change your own role');
      if (e.message.contains('PHONE_TAKEN')) {
        throw AppException('This number is already confirmed on another Zumi account. '
            'One number can belong to one account — sign in to that account or contact support.', code: 'PHONE_TAKEN');
      }
      if (e.message.contains('BAD_PHONE')) throw AppException('Please enter the full phone number, e.g. +260 97 123 4567');
      if (e.message.contains('TOO_MANY_REQUESTS')) throw AppException('Too many requests. Please try again later.');
      if (e.message.contains('TOO_MANY_CODES')) throw AppException('Too many codes. Please wait an hour and try again.');
      if (e.message.contains('TOO_MANY_ATTEMPTS')) throw AppException('Too many wrong codes. Request a new code.');
      if (e.message.contains('CODE_EXPIRED')) throw AppException('The code has expired. Request a new one.');
      if (e.message.contains('CAMPAIGN_LIMIT')) {
        throw AppException('You can run up to 3 campaigns at the same time. Stop one to start a new one.');
      }
      if (e.message.contains('AGENTS_ONLY')) throw AppException('Promotion campaigns are for agents');
      if (e.message.contains('LICENCE_NOT_VERIFIED')) {
        throw AppException('Promotion is available after the Zumi team checks your ZIEA licence.', code: 'LICENCE');
      }
      if (e.message.contains('LICENCE_REQUIRED')) {
        throw AppException('Agents can publish listings after the Zumi team checks their ZIEA licence. '
            'Add your licence number in Profile → Get verified.', code: 'LICENCE');
      }
      if (e.message.contains('NOT_YOUR_LISTING')) throw AppException('Choose one of your active listings');
      if (e.message.contains('START_IN_PAST')) throw AppException('The start date cannot be in the past');
      if (e.message.contains('CAMPAIGN_STOPPED')) throw AppException('A stopped campaign cannot be started again');
      if (e.message.contains('NO_OWNER')) {
        throw AppException('This is a demo listing — chat is not available', code: 'NO_OWNER');
      }
      throw AppException(e.message, code: e.code);
    } on StorageException catch (e) {
      throw AppException('Photo upload failed: ${e.message}');
    }
  }

  @override
  Future<void> signIn({required String email, required String password}) => _guard(() async {
        final res = await _db.auth.signInWithPassword(email: email, password: password);
        if (res.user != null) {
          _user = await _loadProfile(res.user!);
          _userCtrl.add(_user);
        }
      });

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
  }) =>
      _guard(() async {
        final res = await _db.auth.signUp(
          email: email,
          password: password,
          data: {
            'full_name': fullName,
            'phone': phone,
            'role': role,
            'terms_accepted': termsAccepted,
            'marketing': marketing,
            if (role == 'agent' && (licenceNo ?? '').trim().isNotEmpty) 'licence_no': licenceNo!.trim(),
          },
        );
        if (res.session == null) {
          throw AppException('Check your email to confirm the account, then sign in.', code: 'CONFIRM_EMAIL');
        }
        _user = await _loadProfile(res.user!);
        _userCtrl.add(_user);
      });

  @override
  Future<void> signOut() => _db.auth.signOut();

  @override
  Future<void> setMarketing(String channel, bool on) => _guard(() async {
        _requireUserId();
        await _db.rpc('set_marketing', params: {'p_channel': channel, 'p_on': on});
        await _reloadUser();
      });

  @override
  Future<void> refreshUser() => _reloadUser();

  @override
  Future<void> sendPasswordReset(String email) => _guard(() async {
        // письмо «Reset Password» должно содержать код {{ .Token }} (см. README)
        await _db.auth.resetPasswordForEmail(email.trim());
      });

  @override
  Future<void> resetPasswordWithCode({required String email, required String code, required String newPassword}) =>
      _guard(() async {
        await _db.auth.verifyOTP(type: OtpType.recovery, email: email.trim(), token: code.trim());
        await _db.auth.updateUser(UserAttributes(password: newPassword));
        await _reloadUser();
      });

  @override
  Future<void> changePassword(String newPassword) => _guard(() async {
        _requireUserId();
        await _db.auth.updateUser(UserAttributes(password: newPassword));
      });

  @override
  Future<void> deleteAccount() => _guard(() async {
        final uid = _requireUserId();
        // файлы удаляем через Storage API (из SQL их удалить нельзя)
        for (final bucket in const [_bucket, 'avatars', 'verification-docs', 'campaign-images']) {
          try {
            await _removeFolder(bucket, uid);
          } catch (_) {/* не критично */}
        }
        await _db.rpc('delete_my_account');
        await _db.auth.signOut();
        _user = null;
        _userCtrl.add(null);
      });

  Future<void> _removeFolder(String bucket, String prefix) async {
    final store = _db.storage.from(bucket);
    final items = await store.list(path: prefix);
    final files = <String>[];
    for (final it in items) {
      final path = '$prefix/${it.name}';
      if (it.id == null) {
        await _removeFolder(bucket, path); // это папка
      } else {
        files.add(path);
      }
    }
    if (files.isNotEmpty) await store.remove(files);
  }

  /// Путь файла внутри bucket по его публичной ссылке
  String? _pathIn(String url, String bucket) {
    final marker = '/object/public/$bucket/';
    final i = url.indexOf(marker);
    return i < 0 ? null : Uri.decodeComponent(url.substring(i + marker.length).split('?').first);
  }

  String _requireUserId() {
    final id = _db.auth.currentUser?.id;
    if (id == null) throw AppException('Please sign in first', code: 'AUTH');
    return id;
  }

  // ---------------- поиск ----------------
  @override
  Future<List<Area>> areas() => _guard(() async {
        if (_areasCache != null) return _areasCache!;
        // центр района отдаём как lat/lng через area_stats
        final rows = await _db.from('area_stats').select('id, city, name, lat, lng');
        final extra = await _db.from('areas').select('id, tagline, image_url');
        final byId = {for (final r in extra) r['id']: r};
        _areasCache = rows.map((r) {
          final e = byId[r['id']];
          return Area.fromMap({...r, 'tagline': e?['tagline'], 'image_url': e?['image_url']});
        }).toList()
          ..sort((a, b) => a.name.compareTo(b.name));
        return _areasCache!;
      });

  /// Общие фильтры поиска. Объявления, не подтверждённые 60 дней, не показываются.
  PostgrestFilterBuilder<PostgrestList> _filtered(SearchFilters f, {String columns = '*', bool withPrice = true}) {
    var q = _db.from('property_feed').select(columns).eq('status', 'active').eq('is_fresh', true);
    if (f.dealType != null) q = q.eq('deal_type', f.dealType == DealType.sale ? 'sale' : 'rent');
    if (f.rentPeriod != null && f.dealType != DealType.sale) q = q.eq('rent_period', f.rentPeriod!);
    if (f.propertyType != null) q = q.eq('property_type', f.propertyType!.name);
    if (f.city.isNotEmpty) q = q.eq('city', f.city);
    if (f.areaId != null) q = q.eq('area_id', f.areaId!);
    final text = f.query.trim().replaceAll(RegExp(r'[,()%*\\]'), ' ');
    if (text.isNotEmpty) {
      q = q.or('title.ilike.%$text%,area_name.ilike.%$text%,address.ilike.%$text%');
    }
    if (withPrice && f.hasPrice) q = q.eq('currency', f.currency);
    if (withPrice && f.minPrice != null) q = q.gte('price', f.minPrice!);
    if (withPrice && f.maxPrice != null) q = q.lte('price', f.maxPrice!);
    if (f.minBedrooms != null) q = q.gte('bedrooms', f.minBedrooms!);
    if (f.minBathrooms != null) q = q.gte('bathrooms', f.minBathrooms!);
    if (f.renovation.isNotEmpty) q = q.inFilter('renovation', f.renovation.toList());
    if (f.kidsAllowed) q = q.eq('kids_allowed', true);
    if (f.petsAllowed) q = q.eq('pets_allowed', true);
    if (f.amenities.isNotEmpty) q = q.contains('amenities', f.amenities.toList());
    if (f.onlyOwner && !f.onlyAgent) q = q.eq('listed_by', 'owner');
    if (f.onlyAgent && !f.onlyOwner) q = q.eq('listed_by', 'agent');
    if (f.leaseTerm != null) q = q.eq('lease_term', f.leaseTerm!);
    if (f.onlyVerified) q = q.eq('owner_identity_verified', true);
    if (f.onlyLocationVerified) q = q.eq('property_verified', true);
    if (f.minSqm != null) q = q.gte('area_sqm', f.minSqm!);
    if (f.maxSqm != null) q = q.lte('area_sqm', f.maxSqm!);
    return q;
  }

  @override
  Future<List<Property>> search(SearchFilters f, {int limit = 30, int offset = 0}) => _guard(() async {
        if (offset == 0) _logSearch(f);
        final ordered = _filtered(f).order('is_promoted', ascending: false);
        final PostgrestTransformBuilder<PostgrestList> sorted = switch (f.sort) {
          SortBy.newest => ordered.order('created_at', ascending: false),
          SortBy.priceAsc => ordered.order('price', ascending: true),
          SortBy.priceDesc => ordered.order('price', ascending: false),
        };
        final rows = await sorted.range(offset, offset + limit - 1);
        return rows.map(Property.fromMap).toList();
      });

  @override
  Future<int> countListings(SearchFilters f) => _guard(() async {
        final res = await _filtered(f, columns: 'id').count(CountOption.exact);
        return res.count;
      });

  @override
  Future<List<double>> priceSamples(SearchFilters f) => _guard(() async {
        final rows = await _filtered(f, columns: 'price', withPrice: false).eq('currency', f.currency).limit(2000);
        return rows.map((r) => ((r['price'] as num?) ?? 0).toDouble()).toList();
      });

  @override
  Future<Map<int, int>> areaCounts() => _guard(() async {
        final rows = await _db.from('area_stats').select('id, listings_count');
        return {for (final r in rows) (r['id'] as num).toInt(): ((r['listings_count'] as num?) ?? 0).toInt()};
      });

  @override
  Future<List<Property>> popular({String city = 'Lusaka', int limit = 8}) => _guard(() async {
        final rows = await _filtered(SearchFilters(city: city)).order('views_count', ascending: false).limit(limit);
        return rows.map(Property.fromMap).toList();
      });

  @override
  Future<Property?> getProperty(String id) => _guard(() async {
        final row = await _db.from('property_feed').select().eq('id', id).maybeSingle();
        return row == null ? null : Property.fromMap(row);
      });

  @override
  Future<List<Property>> byIds(List<String> ids) => _guard(() async {
        if (ids.isEmpty) return <Property>[];
        final rows = await _db.from('property_feed').select().inFilter('id', ids);
        final map = {for (final r in rows) r['id'] as String: Property.fromMap(r)};
        return ids.map((id) => map[id]).whereType<Property>().toList();
      });

  @override
  Future<void> incrementViews(String id) async {
    try {
      await _db.rpc('increment_views', params: {'pid': id});
    } catch (_) {/* не критично */}
  }

  // ---------------- избранное ----------------
  @override
  Future<Set<String>> favoriteIds() async {
    if (_db.auth.currentUser == null) return {};
    return _guard(() async {
      final rows = await _db.from('favorites').select('property_id');
      return rows.map((r) => r['property_id'] as String).toSet();
    });
  }

  @override
  Future<void> setFavorite(String propertyId, bool value) async {
    final uid = _db.auth.currentUser?.id;
    if (uid == null) return; // без входа избранное хранится только на телефоне
    await _guard(() async {
      if (value) {
        await _db.from('favorites').upsert({'user_id': uid, 'property_id': propertyId});
      } else {
        await _db.from('favorites').delete().eq('user_id', uid).eq('property_id', propertyId);
      }
    });
  }

  // ---------------- мои объявления ----------------
  @override
  Future<Quota> myQuota() => _guard(() async {
        _requireUserId();
        final res = await _db.rpc('my_listing_quota');
        final row = (res as List).first as Map<String, dynamic>;
        return Quota((row['used'] as num).toInt(), (row['allowed'] as num).toInt());
      });

  @override
  Future<List<Property>> myListings() => _guard(() async {
        final uid = _requireUserId();
        final rows = await _db
            .from('property_feed')
            .select()
            .eq('owner_id', uid)
            .order('created_at', ascending: false);
        return rows.map(Property.fromMap).toList();
      });

  @override
  Future<Property> createListing(ListingDraft d) => _guard(() async {
        final uid = _requireUserId();
        final area = d.area;
        final lat = d.lat ?? area?.lat ?? -15.4167;
        final lng = d.lng ?? area?.lng ?? 28.2833;

        final inserted = await _db
            .from('properties')
            .insert({
              'owner_id': uid,
              'title': d.title.trim(),
              'description': d.description.trim(),
              'deal_type': d.dealType == DealType.sale ? 'sale' : 'rent',
              'property_type': d.propertyType.name,
              'price': d.price ?? 0,
              'currency': d.currency,
              'rent_period': d.dealType == DealType.rent ? d.rentPeriod : null,
              'bedrooms': d.propertyType == PropertyType.land ? null : d.bedrooms,
              'bathrooms': d.propertyType == PropertyType.land ? null : d.bathrooms,
              'area_sqm': d.areaSqm,
              'amenities': d.amenities.toList(),
              'area_id': area?.id,
              'location': 'SRID=4326;POINT($lng $lat)',
              'contact_phone': d.contactPhone.trim(),
              'contact_name': _user?.fullName,
              'status': 'active',
            })
            .select('id')
            .single();
        final id = inserted['id'] as String;

        // фото → Storage (оригинал + маленькая копия), ссылки → property_images
        final imageRows = await _photoRows(uid, id, d.photos, const {});
        if (imageRows.isNotEmpty) await _db.from('property_images').insert(imageRows);

        final p = await getProperty(id);
        if (p == null) throw AppException('Listing was saved but could not be loaded');
        return p;
      });

  /// Строки property_images по порядку фото. Новые фото загружаются, старые остаются как были.
  Future<List<Map<String, dynamic>>> _photoRows(
    String uid,
    String propertyId,
    List<PickedPhoto> photos,
    Map<String, String?> thumbOf,
  ) async {
    final store = _db.storage.from(_bucket);
    final rows = <Map<String, dynamic>>[];
    for (var i = 0; i < photos.length; i++) {
      final ph = photos[i];
      if (ph.isExisting) {
        final t = thumbOf[ph.url];
        rows.add({'property_id': propertyId, 'url': ph.url, 'thumb_url': t == ph.url ? null : t, 'sort_order': i});
        continue;
      }
      final base = '$uid/$propertyId/${DateTime.now().millisecondsSinceEpoch}_$i';
      await store.uploadBinary('$base.jpg', ph.bytes,
          fileOptions: const FileOptions(contentType: 'image/jpeg', upsert: false));
      String? thumbUrl;
      final thumb = await makeThumb(ph.bytes);
      if (thumb != null) {
        await store.uploadBinary('${base}_t.jpg', thumb,
            fileOptions: const FileOptions(contentType: 'image/jpeg', upsert: false));
        thumbUrl = store.getPublicUrl('${base}_t.jpg');
      }
      rows.add({'property_id': propertyId, 'url': store.getPublicUrl('$base.jpg'), 'thumb_url': thumbUrl, 'sort_order': i});
    }
    return rows;
  }

  @override
  Future<Property> updateListing(String id, ListingDraft d) => _guard(() async {
        final uid = _requireUserId();
        final old = await getProperty(id);
        if (old == null) throw AppException('Listing not found');
        final lat = d.lat ?? d.area?.lat ?? old.lat;
        final lng = d.lng ?? d.area?.lng ?? old.lng;
        final moved = (lat - old.lat).abs() > 1e-7 || (lng - old.lng).abs() > 1e-7;

        await _db.from('properties').update({
          'title': d.title.trim(),
          'description': d.description.trim(),
          'deal_type': d.dealType == DealType.sale ? 'sale' : 'rent',
          'property_type': d.propertyType.name,
          'price': d.price ?? old.price,
          'currency': d.currency,
          'rent_period': d.dealType == DealType.rent ? d.rentPeriod : null,
          'bedrooms': d.propertyType == PropertyType.land ? null : d.bedrooms,
          'bathrooms': d.propertyType == PropertyType.land ? null : d.bathrooms,
          'area_sqm': d.areaSqm,
          'amenities': d.amenities.toList(),
          if (d.area != null) 'area_id': d.area!.id,
          // точку меняем только если её сдвинули — иначе проверка места сохраняется
          if (moved) 'location': 'SRID=4326;POINT($lng $lat)',
          'contact_phone': d.contactPhone.trim(),
          'updated_at': DateTime.now().toUtc().toIso8601String(),
        }).eq('id', id);

        // фото: собираем новый порядок, лишние файлы удаляем
        final thumbOf = <String, String?>{
          for (var i = 0; i < old.images.length; i++) old.images[i]: old.thumbAt(i),
        };
        final rows = await _photoRows(uid, id, d.photos, thumbOf);
        await _db.from('property_images').delete().eq('property_id', id);
        if (rows.isNotEmpty) await _db.from('property_images').insert(rows);

        final kept = {for (final ph in d.photos) if (ph.isExisting) ph.url!};
        final removed = <String>[];
        for (var i = 0; i < old.images.length; i++) {
          if (kept.contains(old.images[i])) continue;
          removed.add(old.images[i]);
          final t = old.thumbAt(i);
          if (t != null && t != old.images[i]) removed.add(t);
        }
        final paths = removed.map((u) => _pathIn(u, _bucket)).whereType<String>().toList();
        if (paths.isNotEmpty) {
          try {
            await _db.storage.from(_bucket).remove(paths);
          } catch (_) {/* не критично */}
        }
        await _db.rpc('touch_listing', params: {'pid': id});

        final p = await getProperty(id);
        if (p == null) throw AppException('Listing was saved but could not be loaded');
        return p;
      });

  @override
  Future<void> setListingStatus(String id, String status) => _guard(() async {
        await _db.from('properties').update({'status': status}).eq('id', id);
      });

  @override
  Future<void> deleteListing(String id) => _guard(() async {
        await _db.from('properties').delete().eq('id', id);
      });

  // ---------------- ZumiCheck ----------------
  @override
  Future<void> reportListing(String propertyId, String reason, String? details) => _guard(() async {
        final uid = _requireUserId();
        try {
          await _db.from('listing_reports').insert({
            'property_id': propertyId,
            'reporter_id': uid,
            'reason': reason,
            'details': details,
          });
        } on PostgrestException catch (e) {
          if (e.code == '23505') throw AppException('You have already reported this listing');
          rethrow;
        }
      });

  Future<void> _reloadUser() async {
    final u = _db.auth.currentUser;
    if (u == null) return;
    _user = await _loadProfile(u);
    _userCtrl.add(_user);
  }

  @override
  Future<void> updateProfile({
    String? fullName,
    String? agencyName,
    String? bio,
    String? whatsapp,
    String? contactMode,
  }) =>
      _guard(() async {
        final uid = _requireUserId();
        String? clean(String v) => v.trim().isEmpty ? null : v.trim();
        await _db.from('profiles').update({
          if (fullName != null) 'full_name': fullName.trim(),
          if (agencyName != null) 'agency_name': clean(agencyName),
          if (bio != null) 'bio': clean(bio),
          if (whatsapp != null) 'whatsapp': clean(whatsapp),
          if (contactMode != null) 'contact_mode': contactMode,
        }).eq('id', uid);
        await _reloadUser();
      });

  @override
  Future<void> uploadAvatar(PickedPhoto photo) => _guard(() async {
        final uid = _requireUserId();
        final bytes = await makeAvatar(photo.bytes) ?? photo.bytes;
        final path = '$uid/avatar_${DateTime.now().millisecondsSinceEpoch}.jpg';
        final store = _db.storage.from('avatars');
        await store.uploadBinary(path, bytes, fileOptions: const FileOptions(contentType: 'image/jpeg', upsert: true));
        final oldUrl = _user?.avatarUrl;
        await _db.from('profiles').update({'avatar_url': store.getPublicUrl(path)}).eq('id', uid);
        final oldPath = oldUrl == null ? null : _pathIn(oldUrl, 'avatars');
        if (oldPath != null) {
          try {
            await store.remove([oldPath]);
          } catch (_) {/* не критично */}
        }
        await _reloadUser();
      });

  @override
  Future<PublicProfile?> publicProfile(String userId) => _guard(() async {
        final res = await _db.rpc('public_profile', params: {'uid': userId}) as List;
        if (res.isEmpty) return null;
        return PublicProfile.fromMap(Map<String, dynamic>.from(res.first as Map));
      });

  @override
  Future<List<Property>> listingsBy(String userId) => _guard(() async {
        final rows = await _db
            .from('property_feed')
            .select()
            .eq('owner_id', userId)
            .eq('status', 'active')
            .eq('is_fresh', true)
            .order('created_at', ascending: false)
            .limit(60);
        return rows.map(Property.fromMap).toList();
      });

  @override
  Future<void> submitIdentity({
    required String docType,
    required PickedPhoto document,
    required PickedPhoto selfie,
  }) =>
      _guard(() async {
        final uid = _requireUserId();
        final paths = await _uploadPrivate(uid, 'identity', docType, [document, selfie]);
        await _db.from('verification_requests').insert({
          'user_id': uid,
          'kind': 'identity',
          'doc_type': docType,
          'doc_paths': paths,
          'consent_at': DateTime.now().toUtc().toIso8601String(),
        });
        await _reloadUser(); // статус «на проверке»
      });

  @override
  Future<void> submitAgentLicence(String licenceNo) => _guard(() async {
        final uid = _requireUserId();
        await _db.from('profiles').update({'agent_licence_no': licenceNo.trim()}).eq('id', uid);
        await _reloadUser();
      });

  @override
  Future<void> requestVerification({
    required String kind,
    String? propertyId,
    required List<PickedPhoto> docs,
    String? note,
  }) =>
      _guard(() async {
        final uid = _requireUserId();
        final paths = await _uploadPrivate(uid, propertyId ?? 'identity', kind, docs);
        await _db.from('verification_requests').insert({
          'user_id': uid,
          'property_id': propertyId,
          'kind': kind,
          'doc_paths': paths,
          'note': note,
        });
      });

  Future<List<String>> _uploadPrivate(String uid, String folder, String prefix, List<PickedPhoto> files) async {
    final paths = <String>[];
    for (var i = 0; i < files.length; i++) {
      final path = '$uid/$folder/${prefix}_${DateTime.now().millisecondsSinceEpoch}_$i.jpg';
      await _db.storage.from('verification-docs').uploadBinary(
            path,
            files[i].bytes,
            fileOptions: const FileOptions(contentType: 'image/jpeg'),
          );
      paths.add(path);
    }
    return paths;
  }

  @override
  Future<String?> verificationStatus({required String kind, String? propertyId}) async {
    if (_db.auth.currentUser == null) return null;
    return _guard(() async {
      var q = _db.from('verification_requests').select('status').eq('kind', kind);
      q = propertyId == null ? q.isFilter('property_id', null) : q.eq('property_id', propertyId);
      final rows = await q.order('created_at', ascending: false).limit(1);
      return rows.isEmpty ? null : rows.first['status'] as String?;
    });
  }

  @override
  Future<PropertyCheckResult> submitPropertyCheck(
    String propertyId,
    List<PickedPhoto> photos,
    double lat,
    double lng,
  ) =>
      _guard(() async {
        final uid = _requireUserId();
        final paths = await _uploadPrivate(uid, propertyId, 'onsite', photos);
        final res = await _db.rpc('submit_property_check', params: {
          'pid': propertyId,
          'dev_lat': lat,
          'dev_lng': lng,
          'photo_paths': paths,
        }) as Map<String, dynamic>;
        // решение принято сразу — фото с места больше не нужны, удаляем
        try {
          await _db.storage.from('verification-docs').remove(paths);
        } catch (_) {/* не успели — уберёт ежедневная уборка */}
        return PropertyCheckResult(res['verified'] == true, (res['distance_m'] as num?)?.round() ?? 0);
      });

  @override
  Future<bool> sendCode(String channel, String destination) => _guard(() async {
        _requireUserId();
        // код создаёт сервер; в тестовом режиме он всегда 123456
        final res = await _db.rpc('request_verification_code', params: {'p_channel': channel, 'p_destination': destination});
        return (Map<String, dynamic>.from(res as Map)['test_mode'] as bool?) ?? false;
      });

  @override
  Future<void> verifyCode(String channel, String destination, String code) => _guard(() async {
        final res = await _db.rpc('verify_verification_code',
            params: {'p_channel': channel, 'p_destination': destination, 'p_code': code});
        if (res == 'taken') {
          throw AppException('This number is already confirmed on another Zumi account.', code: 'PHONE_TAKEN');
        }
        if (res != 'ok') throw AppException('Wrong code. Please check and try again.');
        await _reloadUser();
      });

  @override
  Future<String> revealPhone(String propertyId) => _guard(() async {
        _requireUserId();
        final res = await _db.rpc('reveal_phone', params: {'pid': propertyId});
        return (res as String?) ?? '';
      });

  @override
  Future<String> revealAgentWhatsapp(String agentId) => _guard(() async {
        _requireUserId();
        final res = await _db.rpc('reveal_agent_whatsapp', params: {'agent': agentId});
        return (res as String?) ?? '';
      });

  @override
  Future<String?> myListingPhone(String propertyId) async {
    try {
      return await _db.rpc('my_listing_phone', params: {'pid': propertyId}) as String?;
    } catch (_) {
      return null;
    }
  }

  @override
  Future<void> confirmListing(String propertyId) => _guard(() async {
        await _db.rpc('confirm_listing', params: {'pid': propertyId});
      });

  // ---------------- поддержка ----------------
  @override
  Future<List<SupportTicket>> myTickets() => _guard(() async {
        final uid = _requireUserId();
        final rows = await _db.from('ticket_feed').select().eq('user_id', uid).order('last_message_at', ascending: false);
        return rows.map(SupportTicket.fromMap).toList();
      });

  @override
  Future<String> openTicket({
    required String category,
    required String subject,
    required String message,
    String? helpArticleId,
  }) =>
      _guard(() async {
        final uid = _requireUserId();
        final t = await _db
            .from('support_tickets')
            .insert({
              'user_id': uid,
              'category': category,
              'subject': subject.trim(),
              if (helpArticleId != null) 'help_article_id': helpArticleId,
            })
            .select('id')
            .single();
        final id = t['id'] as String;
        await _db.from('support_messages').insert({'ticket_id': id, 'sender_id': uid, 'body': message.trim()});
        return id;
      });

  @override
  Stream<List<SupportMessage>> ticketMessages(String ticketId) => _db
      .from('support_messages')
      .stream(primaryKey: ['id'])
      .eq('ticket_id', ticketId)
      .order('created_at', ascending: true)
      .map((rows) => rows.map(SupportMessage.fromMap).toList());

  @override
  Future<void> sendTicketMessage(String ticketId, String body, {bool asStaff = false}) => _guard(() async {
        final uid = _requireUserId();
        await _db.from('support_messages').insert({
          'ticket_id': ticketId,
          'sender_id': uid,
          'body': body.trim(),
          'is_staff': asStaff,
        });
      });

  // ---------------- отзывы ----------------
  @override
  Future<List<Review>> reviewsAbout(String userId) => _guard(() async {
        final rows = await _db
            .from('review_feed')
            .select()
            .eq('target_id', userId)
            .eq('status', 'published')
            .order('created_at', ascending: false)
            .limit(50);
        return rows.map(Review.fromMap).toList();
      });

  @override
  Future<Rating> ratingOf(String userId) => _guard(() async {
        final res = await _db.rpc('rating_of', params: {'uid': userId}) as List;
        if (res.isEmpty) return const Rating(0, 0);
        final r = res.first as Map<String, dynamic>;
        return Rating(((r['avg_rating'] as num?) ?? 0).toDouble(), ((r['reviews_count'] as num?) ?? 0).toInt());
      });

  @override
  Future<void> writeReview({required String targetId, required int rating, String? body, String? propertyId}) =>
      _guard(() async {
        final uid = _requireUserId();
        try {
          await _db.from('reviews').insert({
            'target_id': targetId,
            'author_id': uid,
            'rating': rating,
            'body': body?.trim(),
            'property_id': propertyId,
          });
        } on PostgrestException catch (e) {
          if (e.code == '23505') throw AppException('You have already reviewed this person');
          if (e.code == '23514') throw AppException('You cannot review yourself');
          rethrow;
        }
      });

  @override
  Future<void> flagReview(String reviewId) => _guard(() async {
        _requireUserId();
        await _db.rpc('flag_review', params: {'rid': reviewId});
      });

  // ---------------- кабинет команды ----------------
  @override
  Future<AdminStats> adminStats() => _guard(() async {
        final res = await _db.rpc('admin_stats');
        return AdminStats.fromMap(Map<String, dynamic>.from(res as Map));
      });

  @override
  Future<List<AccountItem>> adminAccounts({bool onlyNew = true}) => _guard(() async {
        final rows = await _db.rpc('admin_accounts', params: {'only_new': onlyNew}) as List;
        return rows.map((r) => AccountItem.fromMap(Map<String, dynamic>.from(r as Map))).toList();
      });

  @override
  Future<void> adminReviewAccount(String userId, String action, {String? note}) => _guard(() async {
        await _db.rpc('admin_review_account', params: {'uid': userId, 'p_action': action, 'p_note': note});
      });

  @override
  Future<List<VerificationItem>> adminVerificationQueue({String status = 'pending'}) => _guard(() async {
        final rows = await _db
            .from('admin_verification_queue')
            .select()
            .eq('status', status)
            .neq('kind', 'property')
            .order('created_at', ascending: status == 'pending')
            .limit(100);
        return rows.map(VerificationItem.fromMap).toList();
      });

  @override
  Future<List<String>> adminDocUrls(List<String> paths) => _guard(() async {
        if (paths.isEmpty) return <String>[];
        final signed = await _db.storage.from('verification-docs').createSignedUrls(paths, 600);
        return signed.map((s) => s.signedUrl).toList();
      });

  @override
  Future<void> adminReviewVerification(String id, bool approve, {String? note}) => _guard(() async {
        await _db.rpc('admin_review_verification', params: {'rid': id, 'approve': approve, 'p_note': note});
        // решение есть — фото документа и селфи удаляем из хранилища
        await adminPurgeDocs();
      });

  // ---------------- помощь ----------------
  @override
  Future<List<HelpArticle>> helpArticles() => _guard(() async {
        var q = _db.from('help_articles').select().eq('published', true);
        if (!kIsWeb) q = q.eq('web_only', false); // правила Apple и Google: про оплату — только на сайте
        final rows = await q.order('category').order('sort').order('title');
        return rows.map(HelpArticle.fromMap).toList();
      });

  @override
  Future<void> voteHelp(String articleId, bool helpful, {String? comment}) => _guard(() async {
        await _db.rpc('vote_help', params: {
          'aid': articleId,
          'p_helpful': helpful,
          'p_comment': comment,
          'device': await DeviceId.get(),
        });
      });

  @override
  Future<List<HelpArticle>> adminHelpArticles() => _guard(() async {
        final rows = await _db.from('help_articles').select().order('category').order('sort').order('title');
        return rows.map(HelpArticle.fromMap).toList();
      });

  @override
  Future<HelpArticle> adminSaveHelpArticle(HelpArticle a, {bool isNew = false}) => _guard(() async {
        final row = isNew
            ? await _db.from('help_articles').insert(a.toMap()).select().single()
            : await _db.from('help_articles').update(a.toMap()).eq('id', a.id).select().single();
        return HelpArticle.fromMap(row);
      });

  @override
  Future<void> adminDeleteHelpArticle(String id) => _guard(() async {
        await _db.from('help_articles').delete().eq('id', id);
      });

  @override
  Future<List<HelpRating>> adminHelpRatings() => _guard(() async {
        final rows = await _db.rpc('admin_help_ratings') as List;
        return rows.map((r) => HelpRating.fromMap(Map<String, dynamic>.from(r as Map))).toList();
      });

  // ---------------- команда и статистика ----------------
  @override
  Future<List<TeamMember>> adminTeam() => _guard(() async {
        final rows = await _db.rpc('admin_team') as List;
        return rows.map((r) => TeamMember.fromMap(Map<String, dynamic>.from(r as Map))).toList();
      });

  @override
  Future<void> adminSetTeam(String email, String? level) => _guard(() async {
        await _db.rpc('admin_set_team', params: {'p_email': email.trim(), 'p_level': level});
      });

  @override
  Future<Dashboard> ownerDashboard(String period) => _guard(() async {
        final res = await _db.rpc('owner_dashboard', params: {'p_period': period});
        return Dashboard.fromMap(Map<String, dynamic>.from(res as Map));
      });

  @override
  Future<void> logVisit() async {
    try {
      await _db.rpc('log_visit', params: {'device': await DeviceId.get()});
    } catch (_) {/* статистика не должна мешать */}
  }

  /// Счётчики поиска: только какие фильтры выбирали (без людей)
  Future<void> _logSearch(SearchFilters f) async {
    final p = <String, String>{
      if (f.areaId != null) 'area': '${f.areaId}',
      if (f.query.trim().isNotEmpty) 'query': f.query.trim(),
      if (f.dealType != null) 'deal': f.dealType!.name,
      if (f.propertyType != null) 'type': f.propertyType!.name,
      if (f.minBedrooms != null) 'beds': '${f.minBedrooms}+',
      if (f.maxPrice != null) 'price': 'up to ${f.maxPrice!.round()} ${f.currency}',
      if (f.onlyVerified) 'verified': 'yes',
    };
    if (p.isEmpty) return;
    try {
      await _db.rpc('log_search', params: {'p': p});
    } catch (_) {/* не критично */}
  }

  @override
  Future<int> adminPurgeDocs() async {
    var total = 0;
    try {
      for (var round = 0; round < 10; round++) {
        final names = ((await _db.rpc('docs_purge_list')) as List? ?? const []).cast<String>();
        if (names.isEmpty) break;
        await _db.storage.from('verification-docs').remove(names);
        await _db.rpc('docs_purge_done', params: {'names': names});
        total += names.length;
      }
    } catch (_) {/* не критично: повторим при следующем открытии кабинета или ежедневной уборкой */}
    return total;
  }

  @override
  Future<void> adminSetRequireLicence(bool on) => _guard(() async {
        await _db.rpc('admin_set_setting', params: {'p_key': 'require_licence_to_publish', 'p_value': '$on'});
      });

  @override
  Future<List<LicenceItem>> adminLicenceQueue() => _guard(() async {
        final rows = await _db
            .from('profiles')
            .select('id, full_name, agent_licence_no')
            .not('agent_licence_no', 'is', null)
            .isFilter('licence_verified_at', null)
            .limit(100);
        return rows
            .map((r) => LicenceItem(
                  userId: r['id'] as String,
                  userName: r['full_name'] as String?,
                  licenceNo: r['agent_licence_no'] as String,
                ))
            .toList();
      });

  @override
  Future<void> adminReviewLicence(String userId, bool approve, {String? note}) => _guard(() async {
        await _db.rpc('admin_review_licence', params: {'uid': userId, 'approve': approve, 'p_note': note});
      });

  @override
  Future<List<ReportItem>> adminReports({bool onlyNew = true}) => _guard(() async {
        var q = _db.from('admin_report_queue').select();
        if (onlyNew) q = q.eq('status', 'new');
        final rows = await q.order('created_at', ascending: false).limit(100);
        return rows.map(ReportItem.fromMap).toList();
      });

  @override
  Future<void> adminResolveReport(String id, String action, {String? note}) => _guard(() async {
        await _db.rpc('admin_resolve_report', params: {'rep_id': id, 'p_action': action, 'p_note': note});
      });

  @override
  Future<void> adminRestoreListing(String propertyId) => _guard(() async {
        await _db.rpc('admin_restore_listing', params: {'pid': propertyId});
      });

  @override
  Future<List<SupportTicket>> adminTickets({String? status}) => _guard(() async {
        var q = _db.from('ticket_feed').select();
        if (status != null) q = q.eq('status', status);
        final rows = await q.order('last_message_at', ascending: false).limit(100);
        return rows.map(SupportTicket.fromMap).toList();
      });

  @override
  Future<void> adminSetTicketStatus(String id, String status) => _guard(() async {
        await _db.rpc('admin_set_ticket_status', params: {'tid': id, 'new_status': status});
      });

  @override
  Future<List<Review>> adminReviews({bool flaggedOnly = false}) => _guard(() async {
        var q = _db.from('review_feed').select();
        if (flaggedOnly) q = q.gt('flags_count', 0);
        final rows = await q.order('created_at', ascending: false).limit(100);
        return rows.map(Review.fromMap).toList();
      });

  @override
  Future<void> adminModerateReview(String id, String action, {String? reply}) => _guard(() async {
        await _db.rpc('admin_moderate_review', params: {'rid': id, 'p_action': action, 'p_reply': reply});
      });

  @override
  Future<List<AuditEntry>> adminAudit() => _guard(() async {
        final rows = await _db.from('admin_audit_feed').select().order('id', ascending: false).limit(100);
        return rows.map(AuditEntry.fromMap).toList();
      });

  // ---------------- продвижение ----------------
  static const _campaignBucket = 'campaign-images';

  @override
  Future<List<Campaign>> myCampaigns() => _guard(() async {
        final uid = _requireUserId();
        final rows = await _db.from('campaigns').select().eq('owner_id', uid).order('created_at', ascending: false);
        return rows.map(Campaign.fromMap).toList();
      });

  @override
  Future<Campaign> createCampaign(CampaignDraft d) => _guard(() async {
        final uid = _requireUserId();
        String? imageUrl;
        if (d.image != null) {
          final path = '$uid/${DateTime.now().millisecondsSinceEpoch}.jpg';
          final store = _db.storage.from(_campaignBucket);
          await store.uploadBinary(path, d.image!, fileOptions: const FileOptions(contentType: 'image/jpeg'));
          imageUrl = store.getPublicUrl(path);
        }
        final row = await _db
            .from('campaigns')
            .insert({
              'owner_id': uid,
              'property_id': d.property!.id,
              'advertiser': d.advertiser.trim(),
              'contact': d.contact.trim().isEmpty ? null : d.contact.trim(),
              'placement': d.placement,
              'image_url': imageUrl,
              'starts_on': isoDay(d.startsOn!),
              'ends_on': isoDay(d.endsOn!),
            })
            .select()
            .single();
        return Campaign.fromMap(row);
      });

  @override
  Future<void> setCampaignStatus(String id, String status) => _guard(() async {
        await _db.from('campaigns').update({'status': status}).eq('id', id);
      });

  @override
  Future<CampaignStats> campaignStats(String id) => _guard(() async {
        final rows = await _db
            .from('campaign_stats')
            .select('day, views, clicks, calls, messages')
            .eq('campaign_id', id)
            .order('day');
        return CampaignStats([
          for (final r in rows)
            CampaignDay(DateTime.parse(r['day'] as String), (r['views'] as num).toInt(), (r['clicks'] as num).toInt(),
                ((r['calls'] as num?) ?? 0).toInt(), ((r['messages'] as num?) ?? 0).toInt()),
        ]);
      });

  @override
  Future<List<(Campaign, Property)>> liveCampaigns(String placement, {SearchFilters? filters}) async {
    try {
      final today = isoDay(DateTime.now());
      final rows = await _db
          .from('campaigns')
          .select()
          .eq('placement', placement)
          .eq('status', 'active')
          .eq('review_status', 'approved')
          .lte('starts_on', today)
          .gte('ends_on', today)
          .limit(30);
      final campaigns = rows.map(Campaign.fromMap).toList();
      if (campaigns.isEmpty) return const [];
      final props = {for (final p in await byIds(campaigns.map((c) => c.propertyId).toSet().toList())) p.id: p};
      final out = <(Campaign, Property)>[
        for (final c in campaigns)
          if (props[c.propertyId] != null && campaignFits(props[c.propertyId]!, filters)) (c, props[c.propertyId]!),
      ]..shuffle(); // честная ротация, если кампаний больше, чем мест
      return out;
    } catch (_) {
      return const []; // реклама не должна ломать ленту
    }
  }

  @override
  Future<void> logCampaignEvent(String campaignId, String kind) async {
    try {
      await _db.rpc('log_campaign_event', params: {'cid': campaignId, 'kind': kind, 'device': await DeviceId.get()});
    } catch (_) {/* не критично */}
  }

  // ---------------- реклама ----------------
  @override
  Future<List<Ad>> liveAds(String placement) async {
    try {
      final today = isoDay(DateTime.now());
      final rows = await _db
          .from('ads')
          .select()
          .eq('placement', placement)
          .eq('status', 'active')
          .lte('starts_on', today)
          .gte('ends_on', today)
          .limit(10);
      return rows.map(Ad.fromMap).toList()..shuffle();
    } catch (_) {
      return const []; // реклама не должна ломать экран
    }
  }

  @override
  Future<void> logAdEvent(String adId, String kind) async {
    try {
      await _db.rpc('log_ad_event', params: {'aid': adId, 'kind': kind, 'device': await DeviceId.get()});
    } catch (_) {/* не критично */}
  }

  @override
  Future<List<Ad>> adminAds() => _guard(() async {
        final rows = await _db.from('ads').select().order('created_at', ascending: false).limit(200);
        return rows.map(Ad.fromMap).toList();
      });

  @override
  Future<Ad> adminSaveAd(AdDraft d, {required bool launch}) => _guard(() async {
        _requireUserId();
        var imageUrl = d.imageUrl;
        if (d.image != null) {
          final path = 'ads/${DateTime.now().millisecondsSinceEpoch}.jpg';
          final store = _db.storage.from('ad-images');
          await store.uploadBinary(path, d.image!, fileOptions: const FileOptions(contentType: 'image/jpeg'));
          imageUrl = store.getPublicUrl(path);
        }
        final today = DateTime.now();
        final values = {
          'advertiser': d.advertiser.trim(),
          'title': d.title.trim(),
          'target_type': d.targetType,
          'target': d.target.trim(),
          'placement': d.placement,
          'image_url': imageUrl,
          'starts_on': isoDay(d.startsOn ?? today),
          'ends_on': isoDay(d.endsOn ?? today.add(const Duration(days: 6))),
          'status': launch ? 'active' : 'draft',
        };
        final row = d.id == null
            ? await _db.from('ads').insert({...values, 'created_by': _db.auth.currentUser?.id}).select().single()
            : await _db.from('ads').update(values).eq('id', d.id!).select().single();
        return Ad.fromMap(row);
      });

  @override
  Future<void> adminSetAdStatus(String id, String status) => _guard(() async {
        await _db.from('ads').update({'status': status}).eq('id', id);
      });

  @override
  Future<CampaignStats> adStats(String id) => _guard(() async {
        final rows = await _db.from('ad_stats').select('day, views, clicks').eq('ad_id', id).order('day');
        return CampaignStats([
          for (final r in rows)
            CampaignDay(DateTime.parse(r['day'] as String), (r['views'] as num).toInt(), (r['clicks'] as num).toInt()),
        ]);
      });

  @override
  Future<List<Property>> adminPendingListings() => _guard(() async {
        final rows = await _db.from('property_feed').select().eq('status', 'pending').order('created_at').limit(100);
        return rows.map(Property.fromMap).toList();
      });

  @override
  Future<void> adminReviewListing(String id, bool approve, {String? note}) => _guard(() async {
        await _db.rpc('admin_review_listing', params: {'pid': id, 'approve': approve, 'p_note': note});
      });

  @override
  Future<List<PhoneWatcher>> adminPhoneWatchers({int days = 7}) => _guard(() async {
        final rows = await _db.rpc('admin_phone_watchers', params: {'days': days}) as List;
        return rows.map((r) => PhoneWatcher.fromMap(Map<String, dynamic>.from(r as Map))).toList();
      });

  @override
  Future<List<Property>> adminAgentListings(String agentId) => _guard(() async {
        final rows = await _db
            .from('property_feed')
            .select()
            .eq('owner_id', agentId)
            .eq('status', 'active')
            .order('created_at', ascending: false);
        return rows.map(Property.fromMap).toList();
      });

  @override
  Future<void> adminGrantPromotion(String agentId, String propertyId, int days, {String placement = 'search_top'}) =>
      _guard(() async {
        await _db.rpc('admin_grant_promotion',
            params: {'agent': agentId, 'pid': propertyId, 'days': days, 'p_placement': placement});
      });

  @override
  Future<List<(Campaign, Property?)>> adminPendingCampaigns() => _guard(() async {
        final rows = await _db
            .from('campaigns')
            .select()
            .eq('review_status', 'pending')
            .neq('status', 'stopped')
            .gte('ends_on', isoDay(DateTime.now()))
            .order('created_at')
            .limit(100);
        final list = rows.map(Campaign.fromMap).toList();
        final props = {
          for (final p in await byIds(list.map((c) => c.propertyId).toSet().toList())) p.id: p,
        };
        return [for (final c in list) (c, props[c.propertyId])];
      });

  @override
  Future<void> adminReviewCampaign(String id, bool approve, {String? note}) => _guard(() async {
        await _db.rpc('admin_review_campaign', params: {'cid': id, 'approve': approve, 'note': note});
      });

  @override
  Future<void> adminSetOtpTestMode(bool on) => _guard(() async {
        await _db.rpc('admin_set_otp_test_mode', params: {'p_on': on});
      });

  // ---------------- чаты ----------------
  @override
  Future<String> startConversation(String propertyId) => _guard(() async {
        _requireUserId();
        final id = await _db.rpc('start_conversation', params: {'pid': propertyId});
        return id as String;
      });

  @override
  Future<List<Conversation>> conversations() => _guard(() async {
        _requireUserId();
        final rows = await _db.from('conversation_list').select().order('last_message_at', ascending: false);
        return rows.map(Conversation.fromMap).toList();
      });

  @override
  Stream<List<ChatMessage>> messages(String conversationId) => _db
      .from('messages')
      .stream(primaryKey: ['id'])
      .eq('conversation_id', conversationId)
      .order('created_at', ascending: true)
      .map((rows) => rows.map(ChatMessage.fromMap).toList());

  @override
  Future<void> sendMessage(String conversationId, String body) => _guard(() async {
        final uid = _requireUserId();
        await _db.from('messages').insert({
          'conversation_id': conversationId,
          'sender_id': uid,
          'body': body.trim(),
        });
      });
}
