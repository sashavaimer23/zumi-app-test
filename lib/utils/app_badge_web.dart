import 'dart:js_interop';
import 'dart:js_interop_unsafe';

String? _baseTitle;

/// Число на значке установленного сайта (navigator.setAppBadge) и в заголовке вкладки
void setAppBadge(int count) {
  try {
    final nav = globalContext['navigator'] as JSObject?;
    if (nav != null && nav.has('setAppBadge')) {
      final p = count > 0
          ? nav.callMethod<JSPromise<JSAny?>?>('setAppBadge'.toJS, count.toJS)
          : nav.callMethod<JSPromise<JSAny?>?>('clearAppBadge'.toJS);
      // ошибки браузера (нет разрешения и т.п.) не важны
      p?.toDart.catchError((_) => null);
    }
  } catch (_) {}
  try {
    final doc = globalContext['document'] as JSObject?;
    if (doc == null) return;
    final current = (doc['title'] as JSString?)?.toDart ?? '';
    _baseTitle ??= current.replaceFirst(RegExp(r'^\(\d+\+?\) '), '');
    final base = _baseTitle!.isEmpty ? 'Zumi' : _baseTitle!;
    doc['title'] = (count > 0 ? '(${count > 10 ? '10+' : count}) $base' : base).toJS;
  } catch (_) {}
}
