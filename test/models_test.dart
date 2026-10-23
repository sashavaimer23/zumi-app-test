import 'package:flutter_test/flutter_test.dart';
import 'package:zumi/data/demo_repository.dart';
import 'package:zumi/models/models.dart';

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

    // продвинутые объявления идут первыми
    final all = await repo.search(SearchFilters());
    final firstNotPromoted = all.indexWhere((p) => !p.isPromoted);
    expect(all.skip(firstNotPromoted).any((p) => p.isPromoted), isFalse);
  });

  test('owner can post 2 listings, then limit is reached', () async {
    final repo = DemoRepository();
    await repo.signUp(email: 'o@x.zm', password: 'secret1', fullName: 'Owner', phone: '+260970000000', role: 'owner');
    ListingDraft draft() => ListingDraft()
      ..title = 'Test house'
      ..price = 1000;
    await repo.createListing(draft());
    await repo.createListing(draft());
    expect((await repo.myQuota()).reached, isTrue);
    expect(() => repo.createListing(draft()), throwsA(isA<AppException>()));
  });
}
