// Этот файл нужен, чтобы `flutter create .` не создал стандартный тест-шаблон
// со ссылкой на несуществующий MyApp. Основные тесты — в models_test.dart.
import 'package:flutter_test/flutter_test.dart';
import 'package:zumi/models/models.dart';

void main() {
  test('price label', () {
    final p = Property(
      id: '1',
      title: 'Test',
      dealType: DealType.rent,
      propertyType: PropertyType.house,
      price: 45000,
      rentPeriod: 'month',
      lat: 0,
      lng: 0,
      createdAt: DateTime(2026),
    );
    expect(p.priceLabel, '45,000 ZMW per month');
  });
}
