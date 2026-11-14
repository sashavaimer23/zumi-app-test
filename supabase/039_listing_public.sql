-- =====================================================================
--  Zumi — 039: лёгкие страницы объявлений для всех (быстро на плохом интернете)
--  Страница объявления zumihome.com/l/<id> теперь открывается сразу (~100 КБ),
--  без загрузки всего сайта. Эта функция отдаёт ей карточку автора:
--  имя, агентство, значки, адрес каталога и — только у агентов с включённым
--  каталогом и подтверждённым номером — WhatsApp/телефон (как в каталоге).
--  У собственников номер на лёгкой странице НЕ показывается (только после входа на сайте).
--  Запускать после 038. Можно запускать повторно.
-- =====================================================================

create or replace function public.owner_card(p_owner uuid)
returns jsonb language sql stable security definer set search_path = public, extensions as $$
  select jsonb_build_object(
    'id', pr.id,
    'slug', pr.slug,
    'role', pr.role,
    'name', coalesce(nullif(trim(pr.full_name), ''), case when pr.role = 'agent' then 'Agent' else 'Owner' end),
    'agency_name', nullif(trim(pr.agency_name), ''),
    'agency_id', pr.agency_id,
    'avatar_url', pr.avatar_url,
    'bio', null,
    'areas', null,
    'licensed', pr.role = 'agent' and pr.licence_verified_at is not null,
    'phone_checked', pr.phone_verified_at is not null,
    'since', to_char(pr.created_at, 'YYYY'),
    'contact', case when pr.role = 'agent' and pr.slug is not null and pr.catalog_public_contact
                         and pr.phone_verified_at is not null
                    then nullif(regexp_replace(coalesce(nullif(pr.whatsapp, ''), pr.phone, ''), '[^0-9]', '', 'g'), '')
               end)
    from profiles pr
   where pr.id = p_owner and pr.banned_at is null;
$$;
grant execute on function public.owner_card(uuid) to anon, authenticated;

-- проверка
select (select count(*) from pg_proc where proname = 'owner_card') = 1 as owner_card_ok;
