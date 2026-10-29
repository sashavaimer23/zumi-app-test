-- =====================================================================
--  Zumi — 018: проверка только по телефону и лицензии, телефон обязателен
--  для публикации, точка на карте и что рядом с жильём.
--  1. Проверку документов (NRC/паспорт + селфи), документы о собственности и
--     проверку на месте (фото + геолокация) выключаем. Новые заявки принять нельзя,
--     незавершённые закрываются, фото удаляются обычной уборкой.
--  2. «Проверенный» = подтверждён телефон (+ у агентов — лицензия ZIEA).
--  3. Опубликовать объявление можно только с подтверждённым телефоном.
--  4. У объявления: что рядом (магазины, школа, больница, главная дорога).
--  Запускать после 017. Можно запускать повторно.
-- =====================================================================

-- ---------------------------------------------------------------------
-- 1. Документы больше не принимаем
-- ---------------------------------------------------------------------
drop policy if exists "own requests create" on public.verification_requests;   -- нет политики = вставка запрещена
drop policy if exists "upload own verification docs" on storage.objects;

create or replace function public.submit_property_check(
  pid uuid, dev_lat double precision, dev_lng double precision, photo_paths text[]
)
returns jsonb language plpgsql security definer set search_path = public, extensions as $$
begin
  raise exception 'FEATURE_OFF';
end $$;

-- незавершённые заявки закрываем; фото удалит уборка (docs_purge_list / cleanup_daily)
update public.verification_requests
   set status = 'expired', reviewed_at = now(),
       reviewer_note = coalesce(reviewer_note, 'Document checks are no longer used. Nothing to do.')
 where status = 'pending' and kind in ('identity', 'ownership', 'property');

-- ---------------------------------------------------------------------
-- 2. Проверенный человек: имя + телефон (+ лицензия ZIEA у агентов)
-- ---------------------------------------------------------------------
create or replace function public.person_verified(uid uuid)
returns boolean language sql stable security definer set search_path = public, extensions as $$
  select pr.full_name is not null and length(trim(pr.full_name)) > 1
     and pr.phone_verified_at is not null
     and (pr.role <> 'agent' or pr.licence_verified_at is not null)
    from profiles pr where pr.id = uid;
$$;

-- ---------------------------------------------------------------------
-- 3. Публикация — только с подтверждённым телефоном
-- ---------------------------------------------------------------------
create or replace function public.require_phone_to_publish()
returns trigger language plpgsql security definer set search_path = public, extensions as $$
begin
  if new.is_demo or new.owner_id is null then return new; end if;
  if auth.uid() is null then return new; end if;   -- SQL Editor / сервис (не пользователь приложения)
  if new.status not in ('active', 'pending') then return new; end if;
  if tg_op = 'UPDATE' and old.status in ('active', 'pending') then return new; end if;   -- уже опубликовано
  if not exists (select 1 from profiles where id = new.owner_id and phone_verified_at is not null) then
    raise exception 'PHONE_REQUIRED';
  end if;
  return new;
end $$;
drop trigger if exists require_phone_to_publish on public.properties;
create trigger require_phone_to_publish before insert or update of status on public.properties
  for each row execute function public.require_phone_to_publish();

-- ---------------------------------------------------------------------
-- 4. Что рядом: {"shop":"lt1","school":"1_3","hospital":"3_5","main_road":"gt5"}
--    lt1 — до 1 км, 1_3 — 1–3 км, 3_5 — 3–5 км, gt5 — больше 5 км
-- ---------------------------------------------------------------------
alter table public.properties add column if not exists nearby jsonb not null default '{}'::jsonb;

create or replace function public._nearby_ok(j jsonb)
returns boolean language sql immutable as $$
  select jsonb_typeof(j) = 'object'
     and not exists (
       select 1 from jsonb_each_text(j) e
        where e.key not in ('shop', 'school', 'hospital', 'main_road')
           or e.value not in ('lt1', '1_3', '3_5', 'gt5'));
$$;
alter table public.properties drop constraint if exists properties_nearby_ok;
alter table public.properties add constraint properties_nearby_ok check (public._nearby_ok(nearby));
alter table public.properties drop constraint if exists properties_address_len;
alter table public.properties add constraint properties_address_len check (address is null or length(address) <= 120);

-- лента: + что рядом и «лицензированный агент»
create or replace view public.property_feed as
  select p.id, p.owner_id, p.title, p.description, p.deal_type, p.property_type, p.price, p.currency,
         p.rent_period, p.bedrooms, p.bathrooms, p.area_sqm, p.plot_sqm, p.furnished, p.amenities,
         p.area_id, p.address, p.location, p.status, p.promoted_until, p.views_count, p.is_demo,
         p.created_at, p.updated_at, p.listed_by, p.contact_name, p.renovation, p.kids_allowed,
         p.pets_allowed, p.lease_term, p.property_verified_at, p.property_verify_method,
         p.ownership_verified_at, p.confirmed_at, p.highlights, p.reports_count,
         p.approved_at, p.moderation_note,
         st_y(p.location::geometry) as lat,
         st_x(p.location::geometry) as lng,
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
         (p.is_demo or coalesce(p.confirmed_at, p.created_at) > now() - interval '60 days') as is_fresh,
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
         (pr.role = 'agent' and pr.licence_verified_at is not null) as owner_licensed
    from properties p
    left join areas a     on a.id  = p.area_id
    left join profiles pr on pr.id = p.owner_id
   where p.status = 'active' or p.owner_id = auth.uid() or public.is_admin();

grant select on public.property_feed to anon, authenticated;

-- ---------------------------------------------------------------------
-- 5. Статьи помощи (только если команда их ещё не меняла)
-- ---------------------------------------------------------------------
update public.help_articles set
  title = 'Number checked and Licensed agent badges',
  body = 'Zumi shows two simple badges:
- Number checked — the owner or agent confirmed their phone number with a code.
- Licensed agent — the Zumi team checked the agent''s registration with the Zambia Institute of Estate Agents (ZIEA).

## How to get them
- Profile → Get verified → confirm your phone with a WhatsApp or SMS code. You do it once.
- Agents: add your ZIEA registration number. We check it with ZIEA — you don''t upload any documents.

You need a confirmed phone number to publish a listing.

Badges show what Zumi checked at that time. They are not a guarantee — always view the property and check the documents yourself.'
 where id = 'f131b212-3739-54b4-8711-d0657f8640a7' and updated_by is null;

update public.help_articles set
  body = replace(replace(body,
    'The person asks for a deposit or "booking fee" before you see the property.',
    'The person asks for a "viewing fee" or "booking fee". On Zumi nobody may charge for a viewing — not before, during or after it.'),
    'Prefer listings with the Verified badge and photos taken on site.',
    'Prefer listings with the Number checked or Licensed agent badge.')
 where id = '92e9e1e2-0b00-5793-ac95-3fc27a6d1090' and updated_by is null;
