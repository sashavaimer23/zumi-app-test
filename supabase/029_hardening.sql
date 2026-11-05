-- =====================================================================
--  Zumi — 029: мелкая защита после проверки 05.11
--  • служебные функции уборки нельзя вызвать из приложения (только расписание pg_cron / команда)
--  Запускать после 028. Можно запускать повторно.
-- =====================================================================
revoke execute on function public.cleanup_feedback() from public, anon, authenticated;
revoke execute on function public.cleanup_orders() from public, anon, authenticated;
revoke execute on function public._wa_verify_number() from public, anon, authenticated;
grant execute on function public._wa_verify_number() to service_role;
