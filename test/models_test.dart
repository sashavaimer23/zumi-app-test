import 'package:flutter_test/flutter_test.dart';
import 'package:zumi/data/demo_repository.dart';
import 'package:zumi/models/models.dart';

/// Демо-аккаунт владельца с подтверждённым телефоном (без телефона публиковать нельзя)
Future<DemoRepository> ownerWithPhone({String email = 'o@x.zm', String phone = '+260970000000'}) async {
  final repo = DemoRepository();
  await repo.signUp(email: email, password: 'secret1', fullName: 'Owner', phone: phone, role: 'owner');
  await repo.verifyCode('sms', phone, '123456');
  return repo;
}

ListingDraft draft() => ListingDraft()
  ..title = 'Test house'
  ..price = 1000
  ..lat = -15.4
  ..lng = 28.3
  ..pinned = true;

void main() {
  test('formatMoney adds thousands separators', () {
    expect(formatMoney(45000), '45,000 ZMW');
    expect(formatMoney(2850000, 'USD'), '2,850,000 USD');
  });

  test('demo search filters by deal, type and price', () async {
    final repo = DemoRepository();
    final rentHouses = await repo.search(SearchFilters(dealType: DealType.rent, propertyType: PropertyType.house));
    expect(rentHouses, isNotEmpty);
    expect(rentHouses.every((p) => p.dealType == DealType.rent && p.propertyType == PropertyType.house), isTrue);

    final cheap = await repo.search(SearchFilters(maxPrice: 10000));
    expect(cheap.every((p) => p.price <= 10000), isTrue);
  });

  test('a phone number must be confirmed before publishing', () async {
    final repo = DemoRepository();
    await repo.signUp(email: 'p@x.zm', password: 'secret1', fullName: 'Owner', phone: '+260971111111', role: 'owner');
    await expectLater(
      repo.createListing(draft()),
      throwsA(isA<AppException>().having((e) => e.code, 'code', 'PHONE_REQUIRED')),
    );
    await repo.verifyCode('sms', '+260971111111', '123456');
    final p = await repo.createListing(draft());
    expect(p.title, 'Test house');
  });

  test('owner can post 2 listings, then the limit is reached', () async {
    final repo = await ownerWithPhone();
    await repo.createListing(draft());
    await repo.createListing(draft());
    expect((await repo.myQuota()).reached, isTrue);
    expect(() => repo.createListing(draft()), throwsA(isA<AppException>()));
  });

  test('hide from search and show again', () async {
    final repo = await ownerWithPhone(email: 'h@x.zm', phone: '+260972222222');
    final p = await repo.createListing(draft());
    await repo.setListingStatus(p.id, 'archived');
    var mine = (await repo.myListings()).firstWhere((x) => x.id == p.id);
    expect(mine.hiddenFromSearch, isTrue);
    expect(mine.hiddenBy, 'owner');
    expect(mine.hiddenByTeam, isFalse);

    await repo.setListingStatus(p.id, 'active');
    mine = (await repo.myListings()).firstWhere((x) => x.id == p.id);
    expect(mine.hiddenFromSearch, isFalse);
    expect(mine.hiddenBy, isNull);
  });

  test('"still available?" — no moves the listing to rented', () async {
    final repo = await ownerWithPhone(email: 's@x.zm', phone: '+260973333333');
    final p = await repo.createListing(draft());
    await repo.answerStillAvailable(p.id, false);
    final mine = (await repo.myListings()).firstWhere((x) => x.id == p.id);
    expect(mine.status, 'rented');
    expect(mine.hiddenFromSearch, isTrue);
  });

  group('availability timing', () {
    Property listing(int daysAgo, {bool fresh = true}) => Property(
          id: 'x',
          title: 'T',
          dealType: DealType.rent,
          propertyType: PropertyType.house,
          price: 1,
          lat: 0,
          lng: 0,
          createdAt: DateTime.now().subtract(Duration(days: daysAgo)),
          confirmedAt: DateTime.now().subtract(Duration(days: daysAgo)),
          isFresh: fresh,
        );

    test('no question before 30 days', () {
      expect(listing(10).needsAvailabilityAnswer, isFalse);
    });
    test('question after 30 days, hidden after 37', () {
      final p = listing(31);
      expect(p.needsAvailabilityAnswer, isTrue);
      expect(p.daysUntilHidden, 6);
      expect(listing(38, fresh: false).expired, isTrue);
      expect(listing(38, fresh: false).hiddenFromSearch, isTrue);
    });
  });

  test('nearby: unknown places and distances are ignored', () {
    final p = Property.fromMap({
      'id': '1',
      'title': 'T',
      'deal_type': 'rent',
      'property_type': 'house',
      'price': 1,
      'nearby': {'shop': 'lt1', 'pool': 'lt1', 'school': 'far'},
    });
    expect(p.nearby, {'shop': 'lt1'});
  });

  test('badges: licensed agent vs number checked', () {
    Property p(bool licensed, bool phone) => Property.fromMap({
          'id': '1',
          'title': 'T',
          'deal_type': 'rent',
          'property_type': 'house',
          'price': 1,
          'owner_licensed': licensed,
          'owner_phone_verified': phone,
        });
    expect(p(true, true).badgeLabel, 'Licensed agent');
    expect(p(false, true).badgeLabel, 'Number checked');
    expect(p(false, false).isVerified, isFalse);
  });

  test('tips: "confirm" and on-site check are not shown as tips', () {
    final s = ListingStats.fromMap({
      'id': '1',
      'tips': [
        {'code': 'confirm'},
        {'code': 'verify_onsite'},
        {'code': 'photos', 'photos': 2},
      ],
    });
    expect(s.tips.map((t) => t.code), ['photos']);
  });

  test('app feedback report is parsed', () {
    final r = AppFeedbackReport.fromMap({
      'count': 2,
      'average': 3.5,
      'by_rating': {'2': 1, '5': 1},
      'issues': {'slow': 1},
      'items': [
        {'rating': 2, 'issues': ['slow'], 'comment': 'Slow on 3G', 'at': '2026-10-29T10:00:00Z', 'who': 'Guest'},
      ],
    });
    expect(r.byRating[2], 1);
    expect(r.items.single.comment, 'Slow on 3G');
  });
}
