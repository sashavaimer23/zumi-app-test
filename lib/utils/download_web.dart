// ignore: avoid_web_libraries_in_flutter, deprecated_member_use
import 'dart:html' as html;

/// Сайт: настоящий файл скачивается в браузере
Future<bool> saveTextFile(String fileName, String text, String mime) async {
  final blob = html.Blob(['﻿$text'], '$mime;charset=utf-8'); // BOM — чтобы Excel понял кодировку
  final url = html.Url.createObjectUrlFromBlob(blob);
  html.AnchorElement(href: url)
    ..download = fileName
    ..click();
  html.Url.revokeObjectUrl(url);
  return true;
}
