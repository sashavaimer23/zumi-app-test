-- =====================================================================
--  Zumi — 004: Verification (три уровня проверки) и жалобы
--  Запускать после 003.
--
--  ПЛАШКА «VERIFIED» = проверенный ЧЕЛОВЕК (собственник или агент):
--    • профиль заполнен (имя)
--    • телефон подтверждён SMS-кодом
--    • NRC/паспорт + селфи проверены (с согласием по Data Protection Act 2021)
--    • у агентов — номер лицензии ZIEA (Estate Agents Act No. 21 of 2000) сверен
--  Все объявления проверенного человека показывают плашку Verified.
--
--  Дополнительно (необязательно, для ещё большего доверия):
--    Property Verified  — 3 фото на месте + геолокация рядом с точкой (авто)
--    Ownership Verified — документы о собственности / мандат от владельца
--
--  Всё добровольно. Статусы меняют только сервер и команда Zumi.
-- =====================================================================

-- ---------------------------------------------------------------------
-- 1. Поля
-- ---------------------------------------------------------------------
alter table public.profiles
  add column if not exists phone_verified_at   timestamptz,  -- из Supabase Auth после SMS-кода
  add column if not exists id_verified_at      timestamptz,  -- документ + селфи проверены командой
  add column if not exists agent_licence_no    text,         -- номер регистрации ZIEA (агенты)
  add column if not exists licence_verified_at timestamptz;  -- номер сверен с реестром ZIEA

-- проверенный человек: телефон + документ (+ лицензия ZIEA у агентов)
create or replace function public.person_verified(uid uuid)
returns boolean language sql stable security definer set search_path = public as $$
  select pr.full_name is not null and length(trim(pr.full_name)) > 1
     and pr.phone_verified_at is not null
     and pr.id_verified_at is not null
     and (pr.role <> 'agent' or pr.licence_verified_at is not null)
    from profiles pr where pr.id = uid;
$$;

-- Приватность: телефон в профиле не виден другим пользователям
-- (контактный номер автор сам указывает в объявлении)
revoke select on public.profiles from anon, authenticated;
grant select (id, role, full_name, agency_name, avatar_url, is_verified, extra_listing_slots,
              phone_verified_at, id_verified_at, agent_licence_no, licence_verified_at, created_at)
  on public.profiles to anon, authenticated;

alter table public.properties
  add column if not exists property_verified_at   timestamptz,
  add column if not exists property_verify_method text check (property_verify_method in ('geo_photos','visit','video')),
  add column if not exists ownership_verified_at  timestamptz,
  add column if not exists confirmed_at           timestamptz,   -- автор подтвердил «ещё доступно»
  add column if not exists highlights             text,          -- «Gated street | Borehole | Solar»
  add column if not exists reports_count          int not null default 0;

-- ---------------------------------------------------------------------
-- 2. Телефон: когда пользователь вводит SMS-код, Supabase Auth ставит
--    auth.users.phone_confirmed_at — копируем это в профиль
-- ---------------------------------------------------------------------
create or replace function public.sync_phone_verified()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  update profiles
     set phone = coalesce(new.phone, phone),
         phone_verified_at = new.phone_confirmed_at
   where id = new.id;
  return new;
end $$;

drop trigger if exists on_auth_phone_confirmed on auth.users;
create trigger on_auth_phone_confirmed
  after update of phone_confirmed_at on auth.users
  for each row when (new.phone_confirmed_at is not null)
  execute function public.sync_phone_verified();

-- ---------------------------------------------------------------------
-- 3. Заявки на проверку (документы и фото — в приватном хранилище)
-- ---------------------------------------------------------------------
create table if not exists public.verification_requests (
  id            uuid primary key default gen_random_uuid(),
  user_id       uuid not null references public.profiles(id) on delete cascade,
  property_id   uuid references public.properties(id) on delete cascade,
  kind          text not null check (kind in ('identity','ownership','property')),
  doc_paths     text[] not null default '{}',     -- пути в bucket 'verification-docs'
  doc_type      text check (doc_type in ('nrc','passport')),
  consent_at    timestamptz,                      -- согласие на обработку данных
  note          text,
  status        text not null default 'pending' check (status in ('pending','approved','rejected')),
  reviewer_note text,
  created_at    timestamptz not null default now(),
  reviewed_at   timestamptz
);
create index if not exists verification_requests_status_idx on public.verification_requests (status, created_at);

alter table public.verification_requests enable row level security;

create policy "own requests read" on public.verification_requests for select
  using (user_id = auth.uid());
create policy "own requests create" on public.verification_requests for insert
  with check (
    user_id = auth.uid() and status = 'pending' and kind in ('identity','ownership')
    and (kind <> 'identity' or consent_at is not null)
    and (property_id is null or exists (
      select 1 from properties p where p.id = property_id and p.owner_id = auth.uid()))
  );

-- ---------------------------------------------------------------------
-- 4. Property Verified автоматически: фото на месте + геолокация
--    Возвращает {"verified": true/false, "distance_m": 120}
-- ---------------------------------------------------------------------
create or replace function public.submit_property_check(
  pid uuid, dev_lat double precision, dev_lng double precision, photo_paths text[]
)
returns jsonb language plpgsql security definer set search_path = public as $$
declare v_loc geography; v_dist double precision; v_ok boolean;
begin
  if auth.uid() is null then raise exception 'NOT_AUTHENTICATED'; end if;
  select location into v_loc from properties where id = pid and owner_id = auth.uid();
  if v_loc is null then raise exception 'NOT_YOUR_LISTING'; end if;
  if coalesce(array_length(photo_paths, 1), 0) < 3 then raise exception 'NEED_3_PHOTOS'; end if;

  v_dist := st_distance(v_loc, st_point(dev_lng, dev_lat)::geography);
  v_ok := v_dist <= 300;   -- в пределах 300 м от точки объявления

  insert into verification_requests (user_id, property_id, kind, doc_paths, status, note, reviewed_at)
  values (auth.uid(), pid, 'property', photo_paths,
          case when v_ok then 'approved' else 'rejected' end,
          format('Auto geo-check: %s m from the pin', round(v_dist)), now());

  if v_ok then
    update properties set property_verified_at = now(), property_verify_method = 'geo_photos'
     where id = pid;
  end if;
  return jsonb_build_object('verified', v_ok, 'distance_m', round(v_dist));
end $$;

-- лицензия агента сверена с реестром ZIEA (вызывает команда Zumi)
create or replace function public.approve_licence(uid uuid)
returns void language sql security definer set search_path = public as $$
  update profiles set licence_verified_at = now() where id = uid and agent_licence_no is not null;
$$;
revoke execute on function public.approve_licence(uuid) from public, anon, authenticated;

-- ---------------------------------------------------------------------
-- 5. Одобрение заявки командой Zumi (из SQL Editor):
--    select approve_verification('<id заявки>');            -- identity / ownership
--    select approve_verification('<id заявки>', 'visit');   -- property после визита
-- ---------------------------------------------------------------------
create or replace function public.approve_verification(rid uuid, method text default 'visit')
returns void language plpgsql security definer set search_path = public as $$
declare r record;
begin
  select * into r from verification_requests where id = rid;
  if r is null then raise exception 'REQUEST_NOT_FOUND'; end if;
  update verification_requests set status = 'approved', reviewed_at = now() where id = rid;
  if r.kind = 'identity' then
    update profiles set id_verified_at = now(), is_verified = true where id = r.user_id;
  elsif r.kind = 'ownership' then
    update properties set ownership_verified_at = now() where id = r.property_id;
  else
    update properties set property_verified_at = now(), property_verify_method = method
     where id = r.property_id;
  end if;
end $$;

revoke execute on function public.approve_verification(uuid, text) from public, anon, authenticated;

-- ---------------------------------------------------------------------
-- 6. Жалобы на объявления
-- ---------------------------------------------------------------------
create table if not exists public.listing_reports (
  id           uuid primary key default gen_random_uuid(),
  property_id  uuid not null references public.properties(id) on delete cascade,
  reporter_id  uuid references public.profiles(id) on delete set null,
  reason       text not null check (reason in
                 ('scam','asked_prepayment','not_available','wrong_info','duplicate','other')),
  details      text,
  status       text not null default 'new' check (status in ('new','reviewed','action_taken')),
  created_at   timestamptz not null default now(),
  unique (property_id, reporter_id)
);

alter table public.listing_reports enable row level security;
create policy "signed-in users report" on public.listing_reports for insert
  with check (reporter_id = auth.uid());
create policy "own reports read" on public.listing_reports for select
  using (reporter_id = auth.uid());

-- 3 жалобы на мошенничество → объявление скрывается до проверки
create or replace function public.on_listing_report()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  update properties set reports_count = reports_count + 1 where id = new.property_id;
  if (select count(*) from listing_reports
       where property_id = new.property_id and reason in ('scam','asked_prepayment')) >= 3 then
    update properties set status = 'archived', property_verified_at = null where id = new.property_id;
  end if;
  return new;
end $$;

drop trigger if exists on_listing_report on public.listing_reports;
create trigger on_listing_report
  after insert on public.listing_reports
  for each row execute function public.on_listing_report();

-- автор подтверждает «объект ещё доступен»
create or replace function public.confirm_listing(pid uuid)
returns void language sql security definer set search_path = public as $$
  update properties set confirmed_at = now()
   where id = pid and owner_id = auth.uid() and status = 'active';
$$;

-- ---------------------------------------------------------------------
-- 7. Защита: пользователь не может сам поставить себе «Verified»
-- ---------------------------------------------------------------------
create or replace function public.protect_verification_fields()
returns trigger language plpgsql as $$
begin
  if current_user in ('authenticated', 'anon') then
    if tg_op = 'INSERT' then
      new.property_verified_at := null; new.property_verify_method := null;
      new.ownership_verified_at := null; new.reports_count := 0; new.confirmed_at := now();
    else
      new.property_verified_at := old.property_verified_at;
      new.property_verify_method := old.property_verify_method;
      new.ownership_verified_at := old.ownership_verified_at;
      new.reports_count := old.reports_count;
      new.confirmed_at := old.confirmed_at;
      -- если автор сдвинул точку на карте — проверку объекта нужно пройти заново
      if new.location is distinct from old.location then
        new.property_verified_at := null; new.property_verify_method := null;
      end if;
    end if;
  end if;
  return new;
end $$;

drop trigger if exists protect_verification_fields on public.properties;
create trigger protect_verification_fields
  before insert or update on public.properties
  for each row execute function public.protect_verification_fields();

create or replace function public.protect_profile_verification()
returns trigger language plpgsql as $$
begin
  if current_user in ('authenticated', 'anon') then
    new.phone_verified_at := old.phone_verified_at;
    new.id_verified_at := old.id_verified_at;
    new.licence_verified_at := old.licence_verified_at;
    -- сменил номер лицензии — нужна новая сверка
    if new.agent_licence_no is distinct from old.agent_licence_no then
      new.licence_verified_at := null;
    end if;
  end if;
  return new;
end $$;

drop trigger if exists protect_profile_verification on public.profiles;
create trigger protect_profile_verification
  before update on public.profiles
  for each row execute function public.protect_profile_verification();

-- ---------------------------------------------------------------------
-- 8. Лента с признаками проверки
-- ---------------------------------------------------------------------
drop view if exists public.property_feed;
create view public.property_feed
with (security_invoker = true) as
  select p.*,
         st_y(p.location::geometry) as lat,
         st_x(p.location::geometry) as lng,
         a.name  as area_name,
         a.city  as city,
         coalesce(p.promoted_until > now(), false)  as is_promoted,
         (p.property_verified_at is not null)       as property_verified,
         (p.ownership_verified_at is not null)      as ownership_verified,
         (pr.phone_verified_at is not null)         as owner_phone_verified,
         -- плашка Verified; демо-объявления агентов считаем проверенными для показа
         coalesce(public.person_verified(p.owner_id), p.is_demo and p.listed_by = 'agent') as owner_identity_verified,
         pr.full_name   as owner_name,
         pr.agency_name as agency_name,
         coalesce(
           (select array_agg(i.url order by i.sort_order)
              from property_images i where i.property_id = p.id),
           '{}'::text[]) as image_urls
    from properties p
    left join areas a     on a.id  = p.area_id
    left join profiles pr on pr.id = p.owner_id;

-- ---------------------------------------------------------------------
-- 9. Приватное хранилище документов и проверочных фото
-- ---------------------------------------------------------------------
insert into storage.buckets (id, name, public) values ('verification-docs','verification-docs', false)
  on conflict do nothing;

create policy "upload own verification docs" on storage.objects for insert to authenticated
  with check (bucket_id = 'verification-docs' and (storage.foldername(name))[1] = auth.uid()::text);
create policy "read own verification docs" on storage.objects for select to authenticated
  using (bucket_id = 'verification-docs' and (storage.foldername(name))[1] = auth.uid()::text);

-- ---------------------------------------------------------------------
-- 10. Демо: часть демо-объявлений отмечаем как проверенные
-- ---------------------------------------------------------------------
update public.properties set confirmed_at = now() - interval '2 days' where is_demo;

update public.properties set highlights = 'Gated street | Borehole | Solar backup'
 where is_demo and title = 'Cosy family house';
update public.properties set highlights = 'Fibre internet | Secure parking'
 where is_demo and title = 'Cosy apartment';
update public.properties set highlights = 'Pool | Fully furnished | Big garden'
 where is_demo and title = 'Luxury villa with pool';
update public.properties set highlights = 'Double garage | Balcony'
 where is_demo and title = 'Contemporary townhouse';
update public.properties set highlights = 'Pool | Staff quarters | Big plot'
 where is_demo and title = 'Family home with big garden';
