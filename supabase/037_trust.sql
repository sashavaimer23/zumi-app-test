-- =====================================================================
--  Zumi — 037: защита от «спящих» мошенников и от уже сданных объявлений
--  1. Новый аккаунт: ВСЕ объявления проверяет команда первые 14 дней
--     (раньше — только первые 2, дальше публиковалось сразу).
--     После 14 дней и 2 одобренных объявлений — публикуется сразу, как раньше.
--  2. Жалоба «Property is not available» от 2 разных людей → автор сразу получает
--     вопрос «Still available?» (в приложении и письмом). Не ответил — объявление
--     само уходит в паузу через несколько дней (агент 3 дня, собственник/комната 7).
--     Объявление НЕ скрывается сразу — чтобы конкуренты не могли «гасить» чужие объявления жалобами.
--  3. Новое поле «сколько месяцев платить вперёд» + фильтр. «Свет и вода» — без изменений в базе.
--  Запускать после 036. Можно запускать повторно.
-- =====================================================================

-- 1. проверка новых аккаунтов
create or replace function public.moderate_new_listing()
returns trigger language plpgsql security definer set search_path = public, extensions as $$
begin
  if new.is_demo or new.owner_id is null then
    new.approved_at := coalesce(new.approved_at, now());
    return new;
  end if;
  if (select count(*) from properties where owner_id = new.owner_id and approved_at is not null) >= 2
     and coalesce((select created_at from profiles where id = new.owner_id), now()) < now() - interval '14 days' then
    new.approved_at := now();
  else
    new.status := 'pending';
    new.approved_at := null;
  end if;
  new.moderation_note := null;
  return new;
end $$;

-- 2. жалобы
create or replace function public.on_listing_report()
returns trigger language plpgsql security definer set search_path = public, extensions as $$
declare
  p properties%rowtype;
  v_since timestamptz;
begin
  update properties set reports_count = reports_count + 1 where id = new.property_id;

  -- мошенничество: 3 жалобы от людей с подтверждённым телефоном → скрыть до проверки
  if (select count(*) from listing_reports r join profiles pr on pr.id = r.reporter_id
       where r.property_id = new.property_id and r.reason in ('scam', 'asked_prepayment')
         and pr.phone_verified_at is not null) >= 3 then
    update properties set status = 'archived', property_verified_at = null where id = new.property_id;
  end if;

  -- «уже сдан»: 2 разных человека после последнего подтверждения → спросить автора прямо сейчас
  if new.reason = 'not_available' then
    select * into p from properties where id = new.property_id;
    v_since := coalesce(p.confirmed_at, p.approved_at, p.created_at);
    if p.status = 'active'
       and (select count(distinct r.reporter_id) from listing_reports r
             where r.property_id = p.id and r.reason = 'not_available' and r.created_at > v_since) >= 2 then
      update properties
         set confirmed_at = least(v_since, now() - public._ask_interval(p.property_type, p.listed_by))
       where id = p.id;
    end if;
  end if;
  return new;
end $$;


-- 3. аренда: сколько месяцев платить вперёд (по желанию автора) — для фильтра «Rent paid upfront»
alter table public.properties add column if not exists advance_months smallint;
alter table public.properties drop constraint if exists properties_advance_ok;
alter table public.properties add constraint properties_advance_ok
  check (advance_months is null or (advance_months between 1 and 24 and deal_type = 'rent'));

create or replace view public.property_feed as
  select p.id, p.owner_id, p.title, p.description, p.deal_type, p.property_type, p.price, p.currency,
         p.rent_period, p.bedrooms, p.bathrooms, p.area_sqm, p.plot_sqm, p.furnished, p.amenities,
         p.area_id, p.address,
         -- комната: точное место видят только автор и команда, остальным — примерно (~1 км)
         (case when p.property_type = 'room' and not coalesce(p.owner_id = auth.uid(), false) and not public.is_admin()
              then st_snaptogrid(p.location::geometry, 0.01)::geography(point, 4326)
              else p.location end)::geography(point, 4326) as location,
         p.status, p.promoted_until, p.views_count, p.is_demo,
         p.created_at, p.updated_at, p.listed_by, p.contact_name, p.renovation, p.kids_allowed,
         p.pets_allowed, p.lease_term, p.property_verified_at, p.property_verify_method,
         p.ownership_verified_at, p.confirmed_at, p.highlights, p.reports_count,
         p.approved_at, p.moderation_note,
         st_y(case when p.property_type = 'room' and not coalesce(p.owner_id = auth.uid(), false) and not public.is_admin()
                   then st_snaptogrid(p.location::geometry, 0.01) else p.location::geometry end) as lat,
         st_x(case when p.property_type = 'room' and not coalesce(p.owner_id = auth.uid(), false) and not public.is_admin()
                   then st_snaptogrid(p.location::geometry, 0.01) else p.location::geometry end) as lng,
         a.name  as area_name,
         a.city  as city,
         coalesce(p.promoted_until > now(), false)  as is_promoted,
         (p.property_verified_at is not null)       as property_verified,
         (p.ownership_verified_at is not null)      as ownership_verified,
         (pr.phone_verified_at is not null)         as owner_phone_verified,
         coalesce(public.person_verified(p.owner_id), p.is_demo and p.listed_by = 'agent') as owner_identity_verified,
         pr.full_name   as owner_name,
         pr.agency_name as agency_name,
         pr.avatar_url  as owner_avatar_url,
         pr.role        as owner_role,
         coalesce(pr.contact_mode, 'phone') as contact_mode,
         (coalesce(p.contact_phone, '') <> '') as has_phone,
         (p.is_demo or coalesce(p.confirmed_at, p.created_at) >
            now() - public._hide_interval(p.property_type, p.listed_by)) as is_fresh,
         coalesce(
           (select array_agg(i.url order by i.sort_order)
              from property_images i where i.property_id = p.id),
           '{}'::text[]) as image_urls,
         coalesce(
           (select array_agg(coalesce(i.thumb_url, i.url) order by i.sort_order)
              from property_images i where i.property_id = p.id),
           '{}'::text[]) as thumb_urls,
         (p.is_demo or pr.role is distinct from 'agent' or pr.licence_verified_at is not null) as owner_licence_verified,
         p.nearby,
         (pr.role = 'agent' and pr.licence_verified_at is not null) as owner_licensed,
         p.hidden_by, p.hidden_reason, p.hidden_at,
         p.room_info,
         p.units_total, p.units_available,
         p.advance_months
    from properties p
    left join areas a     on a.id  = p.area_id
    left join profiles pr on pr.id = p.owner_id
   where (p.status = 'active' and (p.property_type <> 'room' or public.rooms_on()))
      or p.owner_id = auth.uid() or public.is_admin();
grant select on public.property_feed to anon, authenticated;

-- проверка
select
  (select count(*) from pg_proc where proname = 'moderate_new_listing') = 1 as moderation_ok,
  (select prosrc like '%not_available%' from pg_proc where proname = 'on_listing_report') as reports_ok,
  exists (select 1 from information_schema.columns where table_name = 'property_feed' and column_name = 'advance_months') as upfront_ok;
