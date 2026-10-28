// ignore: avoid_web_libraries_in_flutter, deprecated_member_use
import 'dart:html' as html;
// ignore: deprecated_member_use
import 'dart:js_util' as js;

String? _baseTitle;

void setAppBadge(int count) {
  try {
    final nav = html.window.navigator;
    if (js.hasProperty(nav, 'setAppBadge')) {
      final p = count > 0 ? js.callMethod(nav, 'setAppBadge', [count]) : js.callMethod(nav, 'clearAppBadge', []);
      // ошибки браузера (нет разрешения и т.п.) не важны
      js.promiseToFuture<void>(p).catchError((_) {});
    }
  } catch (_) {}
  try {
    final doc = html.document;
    final current = doc.title ?? '';
    _baseTitle ??= current.replaceFirst(RegExp(r'^\(\d+\+?\) '), '');
    final base = _baseTitle!.isEmpty ? 'Zumi' : _baseTitle!;
    doc.title = count > 0 ? '(${count > 10 ? '10+' : count}) $base' : base;
  } catch (_) {}
}
