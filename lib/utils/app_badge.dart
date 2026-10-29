import 'app_badge_stub.dart' if (dart.library.js_interop) 'app_badge_web.dart' as impl;

/// Число на значке приложения (сайт, добавленный на экран «Домой» / установленный в Chrome)
/// и в заголовке вкладки браузера: «(3) Zumi». 0 — убрать.
void setAppBadge(int count) => impl.setAppBadge(count);
