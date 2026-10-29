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
}
