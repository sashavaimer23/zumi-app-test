// Настраивает Android и iOS после `flutter create .`:
//   dart run tool/setup_platforms.dart
//
// Добавляет: доступ в интернет (Android), открытие ссылок tel:/WhatsApp,
// разрешения на галерею и камеру (iOS), название приложения «Zumi».
import 'dart:io';

void main() {
  _android();
  _ios();
  stdout.writeln('Done. Now run: flutter pub get && flutter run');
}

void _android() {
  final f = File('android/app/src/main/AndroidManifest.xml');
  if (!f.existsSync()) {
    stdout.writeln('! android/ not found — run `flutter create .` first');
    return;
  }
  var s = f.readAsStringSync();
  for (final perm in const [
    'android.permission.INTERNET',
    'android.permission.ACCESS_FINE_LOCATION',
    'android.permission.ACCESS_COARSE_LOCATION',
  ]) {
    if (!s.contains(perm)) {
      s = s.replaceFirstMapped(
        RegExp(r'<manifest[^>]*>'),
        (m) => '${m[0]}\n    <uses-permission android:name="$perm"/>',
      );
    }
  }
  const intents = '''
        <intent><action android:name="android.intent.action.DIAL"/><data android:scheme="tel"/></intent>
        <intent><action android:name="android.intent.action.VIEW"/><data android:scheme="https"/></intent>''';
  if (!s.contains('android.intent.action.DIAL')) {
    if (s.contains('<queries>')) {
      s = s.replaceFirst('<queries>', '<queries>$intents');
    } else {
      s = s.replaceFirst('</manifest>', '    <queries>$intents\n    </queries>\n</manifest>');
    }
  }
  s = s.replaceFirst(RegExp(r'android:label="[^"]*"'), 'android:label="Zumi"');
  f.writeAsStringSync(s);
  stdout.writeln('✓ Android manifest updated');
}

void _ios() {
  final f = File('ios/Runner/Info.plist');
  if (!f.existsSync()) {
    stdout.writeln('- ios/ not found (skipped)');
    return;
  }
  var s = f.readAsStringSync();
  final entries = <String, String>{
    'NSPhotoLibraryUsageDescription': 'Zumi needs access to your photos to add them to your listing.',
    'NSCameraUsageDescription': 'Zumi needs the camera to take photos of your property.',
    'NSLocationWhenInUseUsageDescription':
        'Zumi uses your location once to confirm that you are at the property you want to verify.',
  };
  final buf = StringBuffer();
  entries.forEach((k, v) {
    if (!s.contains(k)) buf.write('\t<key>$k</key>\n\t<string>$v</string>\n');
  });
  if (!s.contains('LSApplicationQueriesSchemes')) {
    buf.write('\t<key>LSApplicationQueriesSchemes</key>\n\t<array>\n\t\t<string>tel</string>\n'
        '\t\t<string>whatsapp</string>\n\t\t<string>https</string>\n\t</array>\n');
  }
  final idx = s.lastIndexOf('</dict>');
  if (idx > 0 && buf.isNotEmpty) s = s.substring(0, idx) + buf.toString() + s.substring(idx);
  s = s.replaceFirstMapped(
    RegExp(r'(<key>CFBundleDisplayName</key>\s*<string>)[^<]*(</string>)'),
    (m) => '${m[1]}Zumi${m[2]}',
  );
  f.writeAsStringSync(s);
  stdout.writeln('✓ iOS Info.plist updated');
}
