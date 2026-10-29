-- =====================================================================
--  Zumi — 023: лимит объявлений для агентов
--  Агент с проверенной лицензией ZIEA — 10 бесплатных объявлений, без проверки — 5.
--  Собственники — 2 (без изменений). Купленные места (extra_listing_slots) добавляются сверху.
--  Если лицензию сняли — уже опубликованные объявления остаются, новые сверх 5 не добавить.
--  Запускать после 022. Можно запускать повторно.
-- =====================================================================
alter table public.role_limits add column if not exists free_listings_licensed int;
update public.role_limits set free_listings = 5, free_listings_licensed = 10 where role = 'agent';
update public.role_limits set free_listings = 2, free_listings_licensed = null where role = 'owner';

create or replace function public.listing_quota(uid uuid)
returns table (used int, allowed int) language sql stable security definer
set search_path = public, extensions as $$
  select
    (select count(*)::int from properties
      where owner_id = uid and status in ('active', 'draft', 'pending') and not is_demo),
    (select coalesce(
              case when p.role = 'agent' and p.licence_verified_at is not null
                   then coalesce(rl.free_listings_licensed, rl.free_listings)
                   else rl.free_listings end,
              999999) + p.extra_listing_slots
       from profiles p left join role_limits rl on rl.role = p.role
      where p.id = uid);
$$;

-- статья помощи про лицензию: + про лимит (если команда её не меняла)
update public.help_articles set body = body || '

## More listings with a licence
Agents can publish 5 listings for free. With a checked ZIEA licence — 10.'
 where id = 'a44d1cea-2bb5-5fdc-81f2-6aea36e74198' and updated_by is null
   and body not like '%More listings with a licence%';
