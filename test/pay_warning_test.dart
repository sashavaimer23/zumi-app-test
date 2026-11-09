import 'package:flutter_test/flutter_test.dart';
import 'package:zumi/models/models.dart';

void main() {
  test('payment requests in chat are spotted', () {
    for (final t in [
      'Please send the deposit to my Airtel Money and I will send keys',
      'viewing fee is K100',
      'Pay first then I show you the house',
      'send me K500 to secure it',
      'MTN money number 097...',
      'you can use momo',
    ]) {
      expect(looksLikePaymentRequest(t), isTrue, reason: t);
    }
  });

  test('normal messages are not flagged', () {
    for (final t in [
      'Hello, is the house still available?',
      'Can I view it on Saturday at 10?',
      'Yes, there is parking and water all day',
      'Payment is monthly',
    ]) {
      expect(looksLikePaymentRequest(t), isFalse, reason: t);
    }
  });
}
