/// Что включено в Zumi сейчас. Значения приходят с сервера при запуске (app_flags),
/// владелец меняет их в кабинете — без обновления приложения.
class Features {
  Features._();

  /// Продвижение объявлений агентов (кампании, «Promote», платные места).
  /// Выключено до запуска платных функций — включается в кабинете владельца → Ads.
  static bool promotion = false;

  /// Рекламные баннеры (главная, лента, страница объявления) и шаблон «Your ad here».
  /// Выключено, пока Zumi полностью бесплатный — включается в кабинете владельца → Ads.
  static bool ads = false;

  /// Кнопка «Continue with Facebook» — включаем, когда Facebook включён в Supabase (Authentication → Providers)
  static bool facebookLogin = false;

  /// Номер WhatsApp Zumi для подтверждения телефона (цифры с кодом страны).
  /// null — подтверждение через WhatsApp ещё не подключено (используется старый экран с кодом).
  static String? waVerifyNumber;
}
