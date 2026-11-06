import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:zumi/data/demo_repository.dart';
import 'package:zumi/features.dart';
import 'package:zumi/models/models.dart';
import 'package:zumi/state/app_state.dart';
import 'package:zumi/widgets/common.dart';
import 'package:zumi/widgets/contact.dart';

Property sample({bool promoted = false}) => Property(
      id: 'p1',
      title: '3 bedroom apartment',
      dealType: DealType.rent,
      propertyType: PropertyType.apartment,
      price: 20000,
      rentPeriod: 'month',
      bedrooms: 3,
      areaName: 'Leopards Hill',
      city: 'Lusaka',
      lat: 0,
      lng: 0,
      createdAt: DateTime(2026, 10, 1),
      isPromoted: promoted,
    );

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    Features.promotion = false;
    Features.ads = false;
  });

  test('ad banners OFF: no banners at all', () async {
    final repo = DemoRepository();
    expect(await repo.liveAds('home_hero'), isEmpty);
    expect(await repo.liveAds('listing_block'), isEmpty);
    await repo.setAdsEnabled(true);
    expect((await repo.appFlags())['ads'], isTrue);
  });

  test('promotion OFF hides promoted badges and campaigns', () async {
    expect(sample(promoted: true).isPromoted, isFalse);
    final repo = DemoRepository();
    expect(await repo.liveCampaigns('home_featured'), isEmpty);

    await repo.setPromotionEnabled(true);
    expect(sample(promoted: true).isPromoted, isTrue);
    expect((await repo.appFlags())['promotion'], isTrue);
  });

  test('feedback card: after 7 minutes, then not again for 14 days, never after feedback', () async {
    final prefs = await SharedPreferences.getInstance();
    final app = AppState(DemoRepository(), prefs);
    app.addUsage(6 * 60);
    expect(app.feedbackPromptVisible, isFalse);
    app.addUsage(60);
    expect(app.feedbackPromptVisible, isTrue);

    app.hideFeedbackPrompt();
    app.addUsage(600);
    expect(app.feedbackPromptVisible, isFalse, reason: 'asked recently');

    app.hideFeedbackPrompt(given: true);
    await prefs.remove('fb_asked_at');
    app.addUsage(600);
    expect(app.feedbackPromptVisible, isFalse, reason: 'feedback already given');
  });

  test('WhatsApp message has the listing name, price and area', () {
    final text = Contact.whatsappTemplate(sample());
    expect(text, contains('found your listing on Zumi'));
    expect(text, contains('3 bedroom apartment'));
    expect(text, contains('20,000 ZMW per month'));
    expect(text, contains('Leopards Hill'));
    expect(text, contains('still available'));
  });

  testWidgets('unread badge shows 1…10 and then 10+', (tester) async {
    await tester.pumpWidget(const MaterialApp(
      home: Row(children: [CountBadge(3), CountBadge(10), CountBadge(12), CountBadge(0)]),
    ));
    expect(find.text('3'), findsOneWidget);
    expect(find.text('10'), findsOneWidget);
    expect(find.text('10+'), findsOneWidget);
    expect(find.text('0'), findsNothing);
  });

  test('Google sign-in: new account must finish setting up, only once', () async {
    final repo = DemoRepository();
    repo.debugSignInAsNewGoogleUser(name: 'Gina');
    expect(repo.currentUser!.needsOnboarding, isTrue);
    expect(
      () => repo.completeSignup(role: 'agent', fullName: 'Gina', phone: '+260971234567', termsAccepted: false),
      throwsA(isA<AppException>()),
    );
    await repo.completeSignup(
        role: 'agent', fullName: 'Gina Z', phone: '+260971234567', licenceNo: 'ZIEA-1', termsAccepted: true);
    final u = repo.currentUser!;
    expect(u.needsOnboarding, isFalse);
    expect(u.isAgent, isTrue);
    expect(u.licenceNo, 'ZIEA-1');
    expect(
      () => repo.completeSignup(role: 'owner', fullName: 'X', phone: '+260971234567', termsAccepted: true),
      throwsA(isA<AppException>()),
    );
  });

  test('paid features: off by default, then order → owner confirms → plan and boosts', () async {
    final repo = DemoRepository();
    await repo.signIn(email: 'agent@zumi.zm', password: 'secret1');
    expect((await repo.appFlags())['billing'], isFalse);
    await expectLater(repo.createOrder('plan_pro_m'), throwsA(isA<AppException>()));
    await repo.setBillingEnabled(true);
    expect((await repo.appFlags())['billing'], isTrue);
    expect((await repo.appFlags())['promotion'], isTrue);
    final o = await repo.createOrder('plan_pro_m', phone: '0971234567');
    expect(o.pending, isTrue);
    expect(o.ref, startsWith('Z-'));
    expect((await repo.myBilling()).plan, isNull); // до оплаты ничего не включено
    await repo.adminMarkOrder(o.id, 'paid', note: 'Airtel 123');
    final b = await repo.myBilling();
    expect(b.plan, 'pro');
    expect(b.boostCredits, 2);
    expect((await repo.myQuota()).allowed, greaterThanOrEqualTo(50));
    expect((await repo.billingStatus()).revenue30d, 250);
    // тариф арендодателя — только собственникам; агентам — Pro на 3 и 6 месяцев
    await expectLater(repo.createOrder('plan_landlord_m'), throwsA(isA<AppException>()));
    final codes = (await repo.priceList()).map((p) => p.code).toSet();
    expect(codes, containsAll(['plan_landlord_m', 'plan_landlord_3m', 'plan_pro_3m', 'plan_pro_6m', 'plan_agency_6m']));
  });

  test('money format', () {
    expect(money(60), 'K60');
    expect(money(2500), 'K2,500');
    expect(money(12.5), 'K12.50');
  });
}
