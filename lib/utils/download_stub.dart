import 'package:flutter/services.dart';

/// Приложение на телефоне: кладём таблицу в буфер обмена — её можно вставить в Google Sheets или письмо
Future<bool> saveTextFile(String fileName, String text, String mime) async {
  await Clipboard.setData(ClipboardData(text: text));
  return false;
}
