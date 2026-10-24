import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

/// Случайная метка этого устройства (без личных данных).
/// Нужна, чтобы гость считался в статистике рекламы один раз в день, а не на каждом обновлении.
class DeviceId {
  static String? _id;

  static Future<String> get() async {
    if (_id != null) return _id!;
    try {
      final prefs = await SharedPreferences.getInstance();
      _id = prefs.getString('zumi_device_id');
      if (_id == null) {
        _id = const Uuid().v4();
        await prefs.setString('zumi_device_id', _id!);
      }
    } catch (_) {
      _id ??= const Uuid().v4(); // без хранилища — метка живёт до закрытия
    }
    return _id!;
  }
}
