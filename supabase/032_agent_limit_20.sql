-- =====================================================================
--  Zumi — 032: бесплатный лимит агента с лицензией ZIEA — 20 (было 25). Без лицензии — 15, собственник — 2.
--  Уже размещённые объявления не трогаем: лимит действует только на новые и на возврат скрытых.
--  Запускать после 031. Можно запускать повторно.
-- =====================================================================
update public.role_limits set free_listings = 15, free_listings_licensed = 20 where role = 'agent';

-- проверка: 15 и 20
select role, free_listings, free_listings_licensed from public.role_limits where role in ('agent', 'owner') order by role;
