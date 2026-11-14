-- =====================================================================
--  Zumi — сделать витриной аккаунт zumi.team.zm+agent@gmail.com
--  Переносит на него всё от тестового агента Mwila Banda: профиль агента
--  (агентство, проверенный номер, лицензия, «о себе», каталог zumihome.com/mwila-banda)
--  и все объявления. Старый тестовый аккаунт после этого удаляется.
--  Запускать, когда ты уже вошла (зарегистрировалась) с этой почтой.
--  Можно запускать повторно.
-- =====================================================================

do $$
declare
  old_id uuid := '7e570000-0000-4000-8000-000000000001';
  new_id uuid;
  o profiles%rowtype;
begin
  select id into new_id from auth.users where lower(email) = 'zumi.team.zm+agent@gmail.com';
  if new_id is null then
    raise exception 'Нет аккаунта с почтой zumi.team.zm+agent@gmail.com — сначала зарегистрируйся с ней на сайте';
  end if;

  if new_id <> old_id then
    select * into o from profiles where id = old_id;
    if found then
      -- освобождаем номер и адрес каталога (они должны быть уникальными)
      update profiles set phone = null, whatsapp = null, phone_verified_at = null, slug = null where id = old_id;

      update profiles set
        role = 'agent',
        full_name = o.full_name,
        agency_name = o.agency_name,
        phone = o.phone,
        whatsapp = o.whatsapp,
        phone_verified_at = now(),
        agent_licence_no = o.agent_licence_no,
        licence_verified_at = now(),
        bio = o.bio,
        slug = o.slug,
        catalog_areas = o.catalog_areas,
        catalog_public_contact = true,
        created_at = least(created_at, now() - interval '20 days')
      where id = new_id;

      -- объявления — новому владельцу
      update properties set owner_id = new_id where owner_id = old_id;

      -- старый тестовый аккаунт больше не нужен
      delete from auth.users where id = old_id;
    end if;
  end if;

  -- все объявления витрины — опубликованы
  update properties set status = 'active', approved_at = coalesce(approved_at, now()), confirmed_at = now(),
                        listed_by = 'agent', moderation_note = null
   where owner_id = new_id and not is_demo;
end $$;

-- проверка
select u.email,
       p.role, p.full_name, p.slug,
       (select count(*) from property_feed f where f.owner_id = u.id and f.status = 'active' and f.is_fresh) as listings_visible
  from auth.users u join profiles p on p.id = u.id
 where lower(u.email) = 'zumi.team.zm+agent@gmail.com';

-- =====================================================================
--  УДАЛИТЬ витрину перед запуском сайта (аккаунт и все его объявления):
--  delete from auth.users where lower(email) = 'zumi.team.zm+agent@gmail.com';
-- =====================================================================
