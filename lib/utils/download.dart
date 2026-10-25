import 'download_stub.dart' if (dart.library.html) 'download_web.dart' as impl;

/// Сохранить текст в файл (CSV для Excel / Google Sheets).
/// На сайте — скачивание файла; в приложении — копия в буфер обмена (возвращает false).
Future<bool> saveTextFile(String fileName, String text, {String mime = 'text/csv'}) =>
    impl.saveTextFile(fileName, text, mime);
