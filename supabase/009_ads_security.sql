-- =====================================================================
--  Zumi — 009: реклама, защита номеров, безопасность, коды подтверждения,
--  бесплатное продвижение от команды. Запускать после 008.
-- =====================================================================

-- =====================================================================
-- 1. РЕКЛАМА (баннеры от команды Zumi)
-- =====================================================================
create table if not exists public.ads (
  id           uuid primary key default gen_random_uuid(),
  advertiser   text not null check (length(trim(advertiser)) between 2 and 80),
  title        text not null check (length(trim(title)) between 2 and 80),
  target_type  text not null check (target_type in ('link', 'phone', 'whatsapp')),
  target       text not null check (length(target) <= 300),
  placement    text not null check (placement in ('home_hero', 'feed_strip', 'listing_block')),
  image_url    text,
  starts_on    date not null,
  ends_on      date not null,
  status       text not null default 'draft' check (status in ('draft', 'active', 'paused', 'stopped')),
  created_by   uuid references public.profiles(id) on delete set null,
  created_at   timestamptz not null default now(),
  check (ends_on >= starts_on)
);
create index if not exists ads_live_idx on public.ads (placement, status, starts_on, ends_on);

create table if not exists public.ad_stats (
  ad_id   uuid not null references public.ads(id) on delete cascade,
  day     date not null,
  views   int  not null default 0,
  clicks  int  not null default 0,
  primary key (ad_id, day)
);

-- Рекламу размещает только команда Zumi (по договору с рекламодателем).
-- Публичной формы заявок нет: никто, кроме админа, не может создать или изменить рекламу.
drop table if exists public.ad_requests cascade;
drop function if exists public.limit_ad_requests();

alter table public.ads         enable row level security;
alter table public.ad_stats    enable row level security;

drop policy if exists "live ads readable" on public.ads;
create policy "live ads readable" on public.ads for select
  using (status = 'active' and current_date between starts_on and ends_on);
drop policy if exists "admins manage ads" on public.ads;
create policy "admins manage ads" on public.ads for all
  using (public.is_admin()) with check (public.is_admin());
drop policy if exists "admins read ad stats" on public.ad_stats;
create policy "admins read ad stats" on public.ad_stats for select using (public.is_admin());

create or replace function public.log_ad_event(aid uuid, kind text)
returns void language plpgsql security definer set search_path = public, extensions as $$
begin
  if kind not in ('view', 'click') then return; end if;
  if not exists (select 1 from ads where id = aid and status = 'active'
                   and current_date between starts_on and ends_on) then
    return;
  end if;
  insert into ad_stats (ad_id, day, views, clicks)
  values (aid, current_date, (kind = 'view')::int, (kind = 'click')::int)
  on conflict (ad_id, day) do update
     set views = ad_stats.views + excluded.views, clicks = ad_stats.clicks + excluded.clicks;
end $$;
grant execute on function public.log_ad_event(uuid, text) to anon, authenticated;

insert into storage.buckets (id, name, public) values ('ad-images', 'ad-images', true) on conflict do nothing;
drop policy if exists "public read ad images" on storage.objects;
create policy "public read ad images" on storage.objects for select using (bucket_id = 'ad-images');
drop policy if exists "admins upload ad images" on storage.objects;
create policy "admins upload ad images" on storage.objects for insert to authenticated
  with check (bucket_id = 'ad-images' and public.is_admin());

-- =====================================================================
-- 2. ЗАЩИТА НОМЕРОВ ТЕЛЕФОНОВ
--    Номер больше не приходит вместе с объявлением. Его выдаёт сервер
--    по кнопке «Show number» — только тому, кто вошёл и подтвердил свой
--    телефон, не больше 15 номеров в сутки. Каждый показ записывается.
-- =====================================================================
alter table public.profiles
  add column if not exists contact_mode text not null default 'phone'
    check (contact_mode in ('phone', 'chat'));   -- 'chat' — «только чат», номер не показывается
grant select (contact_mode) on public.profiles to anon, authenticated;

create table if not exists public.phone_reveals (
  id          bigserial primary key,
  user_id     uuid not null references public.profiles(id) on delete cascade,
  property_id uuid references public.properties(id) on delete cascade,
  created_at  timestamptz not null default now()
);
create index if not exists phone_reveals_user_idx on public.phone_reveals (user_id, created_at desc);
alter table public.phone_reveals enable row level security;
drop policy if exists "admins read phone reveals" on public.phone_reveals;
create policy "admins read phone reveals" on public.phone_reveals for select using (public.is_admin());

-- колонку contact_phone больше нельзя прочитать напрямую
revoke select on public.properties from anon, authenticated;
grant select (id, owner_id, title, description, deal_type, property_type, price, currency, rent_period,
              bedrooms, bathrooms, area_sqm, plot_sqm, furnished, amenities, area_id, address, location,
              status, promoted_until, views_count, is_demo, created_at, updated_at, listed_by, contact_name,
              renovation, kids_allowed, pets_allowed, lease_term, property_verified_at,
              property_verify_method, ownership_verified_at, confirmed_at, highlights, reports_count)
  on public.properties to anon, authenticated;

-- =====================================================================
-- 3. ПЕРВЫЕ ОБЪЯВЛЕНИЯ — НА ПРОВЕРКУ
--    Первые 2 объявления нового человека сначала смотрит модератор.
-- =====================================================================
alter table public.properties drop constraint if exists properties_status_check;
alter table public.properties add constraint properties_status_check
  check (status in ('draft', 'pending', 'active', 'sold', 'rented', 'archived'));
alter table public.properties
  add column if not exists approved_at     timestamptz,   -- модератор одобрил (или автор уже проверен)
  add column if not exists moderation_note text;          -- почему не одобрено
grant select (approved_at, moderation_note) on public.properties to anon, authenticated;

-- уже опубликованные объявления считаем проверенными
update public.properties set approved_at = coalesce(approved_at, created_at) where status <> 'pending';

create or replace function public.moderate_new_listing()
returns trigger language plpgsql security definer set search_path = public, extensions as $$
declare v_role text;
begin
  if new.is_demo or new.owner_id is null then
    new.approved_at := coalesce(new.approved_at, now());
    return new;
  end if;
  select role into v_role from profiles where id = new.owner_id;
  if v_role = 'admin'
     or (select count(*) from properties where owner_id = new.owner_id and approved_at is not null) >= 2 then
    new.approved_at := now();
  else
    new.status := 'pending';
    new.approved_at := null;
  end if;
  new.moderation_note := null;
  return new;
end $$;
drop trigger if exists moderate_new_listing on public.properties;
create trigger moderate_new_listing before insert on public.properties
  for each row execute function public.moderate_new_listing();

-- автор не может сам вывести объявление из проверки
create or replace function public.protect_moderation()
returns trigger language plpgsql as $$
begin
  if current_user in ('authenticated', 'anon') then
    new.approved_at := old.approved_at;
    new.moderation_note := old.moderation_note;
    if old.approved_at is null and new.status = 'active' then
      new.status := 'pending';   -- снова на проверку
    end if;
  end if;
  return new;
end $$;
drop trigger if exists protect_moderation on public.properties;
create trigger protect_moderation before update on public.properties
  for each row execute function public.protect_moderation();

-- объявления на проверке занимают место в лимите
create or replace function public.listing_quota(uid uuid)
returns table (used int, allowed int) language sql stable security definer
set search_path = public, extensions as $$
  select
    (select count(*)::int from properties
      where owner_id = uid and status in ('active', 'draft', 'pending') and not is_demo),
    (select coalesce(rl.free_listings, 999999) + p.extra_listing_slots
       from profiles p left join role_limits rl on rl.role = p.role
      where p.id = uid);
$$;

create or replace function public.enforce_listing_limit()
returns trigger language plpgsql security definer set search_path = public, extensions as $$
declare q record;
begin
  if new.is_demo or new.owner_id is null then return new; end if;
  if tg_op = 'UPDATE' and not (new.status in ('active', 'draft', 'pending')
                               and old.status not in ('active', 'draft', 'pending')) then
    return new;
  end if;
  select * into q from public.listing_quota(new.owner_id);
  if q.used >= q.allowed then
    raise exception 'LISTING_LIMIT_REACHED' using hint = 'Buy an extra listing slot';
  end if;
  return new;
end $$;

create or replace function public.admin_review_listing(pid uuid, approve boolean, p_note text default null)
returns void language plpgsql security definer set search_path = public, extensions as $$
begin
  if not public.is_admin() then raise exception 'NOT_ADMIN'; end if;
  if approve then
    update properties set status = 'active', approved_at = now(), confirmed_at = now(), moderation_note = null
     where id = pid;
  else
    update properties set status = 'archived', moderation_note = coalesce(nullif(trim(p_note), ''), 'Not approved')
     where id = pid;
  end if;
  perform public._audit(case when approve then 'approve' else 'reject' end, 'listing', pid::text, p_note);
end $$;

-- =====================================================================
-- 4. ЛЕНТА ОБЪЯВЛЕНИЙ: без номера телефона
--    Вид работает с правами владельца, поэтому правила видимости
--    (активные — всем, свои — автору, все — команде) записаны прямо здесь.
-- =====================================================================
drop view if exists public.property_feed;
create view public.property_feed as
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
           '{}'::text[]) as thumb_urls
    from properties p
    left join areas a     on a.id  = p.area_id
    left join profiles pr on pr.id = p.owner_id
   where p.status = 'active' or p.owner_id = auth.uid() or public.is_admin();

grant select on public.property_feed to anon, authenticated;

-- номер для своего объявления (форма правки)
create or replace function public.my_listing_phone(pid uuid)
returns text language sql stable security definer set search_path = public, extensions as $$
  select contact_phone from properties where id = pid and owner_id = auth.uid();
$$;

-- =====================================================================
-- 5. ПРОДВИЖЕНИЕ: звонки и сообщения в статистике + бесплатно от команды
-- =====================================================================
alter table public.campaign_stats
  add column if not exists calls    int not null default 0,
  add column if not exists messages int not null default 0;
alter table public.campaigns
  add column if not exists granted_by uuid references public.profiles(id) on delete set null;

-- +1 звонок или сообщение у идущих сегодня кампаний этого объявления
create or replace function public._campaign_bump(pid uuid, kind text)
returns void language plpgsql security definer set search_path = public, extensions as $$
begin
  insert into campaign_stats (campaign_id, day, calls, messages)
  select c.id, current_date, (kind = 'call')::int, (kind = 'message')::int
    from campaigns c
   where c.property_id = pid and c.status = 'active' and current_date between c.starts_on and c.ends_on
  on conflict (campaign_id, day) do update
     set calls = campaign_stats.calls + excluded.calls,
         messages = campaign_stats.messages + excluded.messages;
end $$;
revoke execute on function public._campaign_bump(uuid, text) from public, anon, authenticated;

-- показать номер
create or replace function public.reveal_phone(pid uuid)
returns text language plpgsql security definer set search_path = public, extensions as $$
declare
  uid uuid := auth.uid();
  p record;
  me record;
begin
  if uid is null then raise exception 'AUTH'; end if;
  select pr.banned_at, pr.phone_verified_at into me from profiles pr where pr.id = uid;
  if me.banned_at is not null then raise exception 'ACCOUNT_BLOCKED'; end if;

  select pp.owner_id, pp.contact_phone, pp.status, pp.is_demo, coalesce(o.contact_mode, 'phone') as mode
    into p from properties pp left join profiles o on o.id = pp.owner_id where pp.id = pid;
  if p is null then raise exception 'NOT_FOUND'; end if;
  if p.owner_id = uid then return p.contact_phone; end if;           -- своё объявление
  if p.status <> 'active' then raise exception 'NOT_FOUND'; end if;
  if me.phone_verified_at is null then raise exception 'PHONE_NOT_VERIFIED'; end if;
  if p.mode = 'chat' then raise exception 'CHAT_ONLY'; end if;
  if coalesce(p.contact_phone, '') = '' then raise exception 'NO_PHONE'; end if;

  -- этот номер уже показывали за сутки — повторно не считаем
  if not exists (select 1 from phone_reveals where user_id = uid and property_id = pid
                   and created_at > now() - interval '1 day') then
    if (select count(*) from phone_reveals where user_id = uid and created_at > now() - interval '1 day') >= 15 then
      raise exception 'REVEAL_LIMIT';
    end if;
    insert into phone_reveals (user_id, property_id) values (uid, pid);
    perform public._campaign_bump(pid, 'call');
  end if;
  return p.contact_phone;
end $$;
grant execute on function public.reveal_phone(uuid) to authenticated;

-- кто чаще всех смотрит номера (по этому списку видно ботов)
create or replace function public.admin_phone_watchers(days int default 7)
returns table (user_id uuid, full_name text, email text, phone text, reveals int, listings int,
               last_at timestamptz, banned boolean)
language plpgsql stable security definer set search_path = public, extensions, auth as $$
begin
  if not public.is_admin() then raise exception 'NOT_ADMIN'; end if;
  return query
    select r.user_id, pr.full_name, u.email::text, pr.phone, count(*)::int, count(distinct r.property_id)::int,
           max(r.created_at), pr.banned_at is not null
      from phone_reveals r
      join profiles pr on pr.id = r.user_id
      left join auth.users u on u.id = r.user_id
     where r.created_at > now() - make_interval(days => days)
     group by r.user_id, pr.full_name, u.email, pr.phone, pr.banned_at
     order by count(*) desc
     limit 50;
end $$;

-- чат: + «сообщение» в статистике продвижения
create or replace function public.start_conversation(pid uuid)
returns uuid language plpgsql security definer set search_path = public, extensions as $$
declare v_seller uuid; v_id uuid;
begin
  if auth.uid() is null then raise exception 'NOT_AUTHENTICATED'; end if;
  if exists (select 1 from profiles where id = auth.uid() and banned_at is not null) then
    raise exception 'ACCOUNT_BLOCKED';
  end if;
  select owner_id into v_seller from properties where id = pid;
  if v_seller is null then raise exception 'NO_OWNER'; end if;
  if v_seller = auth.uid() then raise exception 'OWN_LISTING'; end if;

  select id into v_id from conversations where property_id = pid and buyer_id = auth.uid();
  if v_id is null then
    insert into conversations (property_id, buyer_id, seller_id)
    values (pid, auth.uid(), v_seller) returning id into v_id;
    perform public._campaign_bump(pid, 'message');
  end if;
  return v_id;
end $$;

-- команда дарит агенту продвижение на N дней (пока нет оплаты)
create or replace function public.admin_grant_promotion(agent uuid, pid uuid, days int, p_placement text default 'search_top')
returns uuid language plpgsql security definer set search_path = public, extensions as $$
declare v_id uuid; a record;
begin
  if not public.is_admin() then raise exception 'NOT_ADMIN'; end if;
  if days < 1 or days > 90 then raise exception 'BAD_DAYS'; end if;
  select full_name, agency_name, whatsapp, phone into a from profiles where id = agent;
  insert into campaigns (owner_id, property_id, advertiser, contact, placement, starts_on, ends_on, granted_by)
  values (agent, pid, left(coalesce(nullif(a.agency_name, ''), a.full_name, 'Agent'), 80), coalesce(a.whatsapp, a.phone),
          p_placement, current_date, current_date + days - 1, auth.uid())
  returning id into v_id;
  perform public._audit('grant_promotion', 'campaign', v_id::text, days || ' days');
  return v_id;
end $$;

-- =====================================================================
-- 6. БЕЗОПАСНОСТЬ
-- =====================================================================
-- заблокированный не пишет в чаты, не оставляет отзывы и жалобы
create or replace function public.block_banned_actions()
returns trigger language plpgsql security definer set search_path = public, extensions as $$
begin
  if exists (select 1 from profiles where id = auth.uid() and banned_at is not null) then
    raise exception 'ACCOUNT_BLOCKED';
  end if;
  return new;
end $$;
drop trigger if exists block_banned_messages on public.messages;
create trigger block_banned_messages before insert on public.messages
  for each row execute function public.block_banned_actions();
drop trigger if exists block_banned_reviews on public.reviews;
create trigger block_banned_reviews before insert on public.reviews
  for each row execute function public.block_banned_actions();
drop trigger if exists block_banned_reports on public.listing_reports;
create trigger block_banned_reports before insert on public.listing_reports
  for each row execute function public.block_banned_actions();

-- объявление скрывается само только по жалобам людей с подтверждённым телефоном
create or replace function public.on_listing_report()
returns trigger language plpgsql security definer set search_path = public, extensions as $$
begin
  update properties set reports_count = reports_count + 1 where id = new.property_id;
  if (select count(*) from listing_reports r join profiles pr on pr.id = r.reporter_id
       where r.property_id = new.property_id and r.reason in ('scam', 'asked_prepayment')
         and pr.phone_verified_at is not null) >= 3 then
    update properties set status = 'archived', property_verified_at = null where id = new.property_id;
  end if;
  return new;
end $$;

-- согласие при регистрации (дата записывается)
alter table public.profiles add column if not exists terms_accepted_at timestamptz;

create or replace function public.handle_new_user()
returns trigger language plpgsql security definer set search_path = public, extensions as $$
begin
  insert into public.profiles (id, full_name, phone, role, terms_accepted_at)
  values (
    new.id,
    new.raw_user_meta_data->>'full_name',
    new.raw_user_meta_data->>'phone',
    case when new.raw_user_meta_data->>'role' = 'agent' then 'agent' else 'owner' end,
    case when (new.raw_user_meta_data->>'terms_accepted') = 'true' then now() end
  );
  return new;
end $$;

-- ограничения на файлы: фото до 5 MB, документы для проверки до 10 MB
update storage.buckets set file_size_limit = 5242880,
       allowed_mime_types = array['image/jpeg', 'image/png', 'image/webp']
 where id in ('property-images', 'avatars', 'campaign-images', 'ad-images');
update storage.buckets set file_size_limit = 10485760,
       allowed_mime_types = array['image/jpeg', 'image/png', 'image/webp', 'application/pdf']
 where id = 'verification-docs';

-- =====================================================================
-- 7. КОДЫ ПОДТВЕРЖДЕНИЯ: WhatsApp, SMS или email
--    Пока провайдеры не подключены — тестовый режим, код всегда 123456.
--    Перед запуском: update app_settings set value = 'false' where key = 'otp_test_mode';
--    Значок «телефон подтверждён» — только за код через WhatsApp или SMS.
-- =====================================================================
create table if not exists public.app_settings (key text primary key, value text not null);
insert into public.app_settings values ('otp_test_mode', 'true') on conflict do nothing;
alter table public.app_settings enable row level security;   -- читают только функции сервера

alter table public.profiles
  add column if not exists phone_verify_channel text check (phone_verify_channel in ('whatsapp', 'sms')),
  add column if not exists email_verified_at    timestamptz;

create table if not exists public.verification_codes (
  id          bigserial primary key,
  user_id     uuid not null references public.profiles(id) on delete cascade,
  channel     text not null check (channel in ('whatsapp', 'sms', 'email')),
  destination text not null,
  code_hash   text not null,
  attempts    int  not null default 0,
  expires_at  timestamptz not null,
  used_at     timestamptz,
  sent_at     timestamptz,          -- заполнит отправщик (Edge Function), когда подключим провайдера
  created_at  timestamptz not null default now()
);
create index if not exists verification_codes_user_idx on public.verification_codes (user_id, created_at desc);
alter table public.verification_codes enable row level security;   -- только через функции

create or replace function public.request_verification_code(p_channel text, p_destination text)
returns jsonb language plpgsql security definer set search_path = public, extensions as $$
declare
  uid uuid := auth.uid();
  v_test boolean := coalesce((select value from app_settings where key = 'otp_test_mode'), 'true') = 'true';
  v_code text;
begin
  if uid is null then raise exception 'AUTH'; end if;
  if p_channel not in ('whatsapp', 'sms', 'email') then raise exception 'BAD_CHANNEL'; end if;
  if exists (select 1 from profiles where id = uid and banned_at is not null) then raise exception 'ACCOUNT_BLOCKED'; end if;
  if (select count(*) from verification_codes where user_id = uid and created_at > now() - interval '1 hour') >= 5 then
    raise exception 'TOO_MANY_CODES';
  end if;
  v_code := case when v_test then '123456' else lpad((floor(random() * 1000000))::int::text, 6, '0') end;
  insert into verification_codes (user_id, channel, destination, code_hash, expires_at)
  values (uid, p_channel, trim(p_destination), md5(v_code || uid::text), now() + interval '10 minutes');
  return jsonb_build_object('test_mode', v_test);
end $$;

-- ответ: 'ok' | 'wrong' (неверный код — попытка засчитана) ; ошибки — исключением
drop function if exists public.verify_verification_code(text, text, text);
create or replace function public.verify_verification_code(p_channel text, p_destination text, p_code text)
returns text language plpgsql security definer set search_path = public, extensions as $$
declare
  uid uuid := auth.uid();
  c record;
begin
  if uid is null then raise exception 'AUTH'; end if;
  select * into c from verification_codes
   where user_id = uid and channel = p_channel and destination = trim(p_destination)
     and used_at is null and expires_at > now()
   order by created_at desc limit 1;
  if c is null then raise exception 'CODE_EXPIRED'; end if;
  if c.attempts >= 5 then raise exception 'TOO_MANY_ATTEMPTS'; end if;
  update verification_codes set attempts = attempts + 1 where id = c.id;
  -- без исключения, чтобы счётчик попыток сохранился
  if c.code_hash <> md5(trim(p_code) || uid::text) then return 'wrong'; end if;
  update verification_codes set used_at = now() where id = c.id;
  if p_channel = 'email' then
    update profiles set email_verified_at = now() where id = uid;
  else
    update profiles set phone = c.destination, phone_verified_at = now(), phone_verify_channel = p_channel
     where id = uid;
  end if;
  return 'ok';
end $$;

-- статус своих проверок (+ телефон и способ подтверждения)
create or replace function public.my_verification()
returns jsonb language sql stable security definer set search_path = public, extensions as $$
  select jsonb_build_object(
    'id_status', (select status from verification_requests
                   where user_id = auth.uid() and kind = 'identity' order by created_at desc limit 1),
    'id_note',   (select reviewer_note from verification_requests
                   where user_id = auth.uid() and kind = 'identity' order by created_at desc limit 1),
    'licence_note', (select licence_note from profiles where id = auth.uid()),
    'phone', (select phone from profiles where id = auth.uid()),
    'phone_channel', (select phone_verify_channel from profiles where id = auth.uid()),
    'email_verified', (select email_verified_at is not null from profiles where id = auth.uid())
  );
$$;

-- =====================================================================
-- 8. Счётчики кабинета
-- =====================================================================
create or replace function public.admin_stats()
returns jsonb language plpgsql stable security definer set search_path = public, extensions as $$
begin
  if not public.is_admin() then raise exception 'NOT_ADMIN'; end if;
  return jsonb_build_object(
    'accounts',     (select count(*) from profiles where account_reviewed_at is null and role <> 'admin'),
    'listings_new', (select count(*) from properties where status = 'pending'),
    'id_checks',    (select count(*) from verification_requests where kind = 'identity'  and status = 'pending'),
    'ownership',    (select count(*) from verification_requests where kind = 'ownership' and status = 'pending'),
    'licences',     (select count(*) from profiles where agent_licence_no is not null and licence_verified_at is null),
    'reports',      (select count(*) from listing_reports where status = 'new'),
    'tickets',      (select count(*) from support_tickets where status = 'open'),
    'reviews',      (select count(*) from reviews where flags_count > 0 and status = 'published'),
    'listings',     (select count(*) from properties where status = 'active'),
    'users',        (select count(*) from profiles)
  );
end $$;
