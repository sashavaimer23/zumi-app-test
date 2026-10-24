-- =====================================================================
--  Zumi — 010: исправления безопасности
--  1. WhatsApp агентов больше не открыт всем (только по кнопке, как номер)
--     + в кампаниях продвижения нельзя указать телефон (только сайт)
--  2. Тестовый режим кодов виден команде (красная плашка) и выключается кнопкой
--  3. Один подтверждённый номер — только у одного аккаунта
--  4. (в приложении) честный шаблон «Здесь может быть ваша реклама»
--  5. Продвижение с своей картинкой/текстом/ссылкой — сначала проверка командой
--  6. Показы и клики считаются не чаще 1 раза в день с человека
--  Запускать после 009. Можно запускать повторно.
-- =====================================================================

-- =====================================================================
-- 1. WHATSAPP АГЕНТОВ
-- =====================================================================
revoke select (whatsapp) on public.profiles from anon, authenticated;

-- публичная карточка: вместо номера — только «есть ли WhatsApp»
drop function if exists public.public_profile(uuid);
create function public.public_profile(uid uuid)
returns table (
  id uuid, role text, full_name text, agency_name text, avatar_url text, bio text,
  has_whatsapp boolean, contact_mode text, verified boolean, phone_verified boolean, licence_verified boolean,
  member_since timestamptz, active_listings int
) language sql stable security definer set search_path = public as $$
  select pr.id, pr.role, pr.full_name, pr.agency_name, pr.avatar_url, pr.bio,
         pr.role = 'agent' and coalesce(pr.whatsapp, '') <> '',
         coalesce(pr.contact_mode, 'phone'),
         coalesce(public.person_verified(pr.id), false),
         pr.phone_verified_at is not null,
         pr.licence_verified_at is not null,
         pr.created_at,
         (select count(*) from properties p where p.owner_id = pr.id and p.status = 'active')::int
    from profiles pr
   where pr.id = uid and pr.banned_at is null;
$$;
grant execute on function public.public_profile(uuid) to anon, authenticated;

-- свой WhatsApp человек видит в настройках
create or replace function public.my_verification()
returns jsonb language sql stable security definer set search_path = public as $$
  select jsonb_build_object(
    'id_status', (select status from verification_requests
                   where user_id = auth.uid() and kind = 'identity' order by created_at desc limit 1),
    'id_note',   (select reviewer_note from verification_requests
                   where user_id = auth.uid() and kind = 'identity' order by created_at desc limit 1),
    'licence_note', (select licence_note from profiles where id = auth.uid()),
    'phone', (select phone from profiles where id = auth.uid()),
    'whatsapp', (select whatsapp from profiles where id = auth.uid()),
    'phone_channel', (select phone_verify_channel from profiles where id = auth.uid()),
    'email_verified', (select email_verified_at is not null from profiles where id = auth.uid())
  );
$$;

-- показы WhatsApp агента учитываются в том же лимите 15 в сутки
alter table public.phone_reveals add column if not exists agent_id uuid references public.profiles(id) on delete cascade;

create or replace function public.reveal_agent_whatsapp(agent uuid)
returns text language plpgsql security definer set search_path = public as $$
declare
  uid uuid := auth.uid();
  a record;
  me record;
begin
  if uid is null then raise exception 'AUTH'; end if;
  select pr.banned_at, pr.phone_verified_at into me from profiles pr where pr.id = uid;
  if me.banned_at is not null then raise exception 'ACCOUNT_BLOCKED'; end if;

  select pr.role, pr.whatsapp, pr.banned_at, coalesce(pr.contact_mode, 'phone') as mode
    into a from profiles pr where pr.id = agent;
  if a is null or a.role <> 'agent' or a.banned_at is not null then raise exception 'NOT_FOUND'; end if;
  if agent = uid then return a.whatsapp; end if;
  if me.phone_verified_at is null then raise exception 'PHONE_NOT_VERIFIED'; end if;
  if a.mode = 'chat' then raise exception 'CHAT_ONLY'; end if;
  if coalesce(a.whatsapp, '') = '' then raise exception 'NO_PHONE'; end if;

  if not exists (select 1 from phone_reveals where user_id = uid and agent_id = agent
                   and created_at > now() - interval '1 day') then
    if (select count(*) from phone_reveals where user_id = uid and created_at > now() - interval '1 day') >= 15 then
      raise exception 'REVEAL_LIMIT';
    end if;
    insert into phone_reveals (user_id, agent_id) values (uid, agent);
  end if;
  return a.whatsapp;
end $$;
grant execute on function public.reveal_agent_whatsapp(uuid) to authenticated;

-- «кто смотрит номера»: считаем и объявления, и страницы агентов
create or replace function public.admin_phone_watchers(days int default 7)
returns table (user_id uuid, full_name text, email text, phone text, reveals int, listings int,
               last_at timestamptz, banned boolean)
language plpgsql stable security definer set search_path = public, auth as $$
begin
  if not public.is_admin() then raise exception 'NOT_ADMIN'; end if;
  return query
    select r.user_id, pr.full_name, u.email::text, pr.phone, count(*)::int,
           count(distinct coalesce(r.property_id::text, 'a:' || r.agent_id::text))::int,
           max(r.created_at), pr.banned_at is not null
      from phone_reveals r
      join profiles pr on pr.id = r.user_id
      left join auth.users u on u.id = r.user_id
     where r.created_at > now() - make_interval(days => days)
     group by r.user_id, pr.full_name, u.email, pr.phone, pr.banned_at
     order by count(*) desc
     limit 50;
end $$;

-- кампании видны всем — поэтому телефон в них больше не пишем, только ссылку на сайт.
-- Позвонить можно через «Show number» объявления (с проверками и лимитом).
update public.campaigns set contact = null where contact ~ '^[+0-9 ()./-]+$';
alter table public.campaigns drop constraint if exists campaigns_contact_link_only;
alter table public.campaigns add constraint campaigns_contact_link_only
  check (contact is null or contact !~ '^[+0-9 ()./-]+$');

-- =====================================================================
-- 5. ПРОДВИЖЕНИЕ: СВОЯ КАРТИНКА, ТЕКСТ ИЛИ ССЫЛКА — СНАЧАЛА ПРОВЕРКА
--    Сразу (без проверки) идёт только кампания с фото из объявления,
--    своим именем/агентством и без ссылки.
-- =====================================================================
alter table public.campaigns
  add column if not exists review_status text not null default 'approved'
    check (review_status in ('pending', 'approved', 'rejected')),
  add column if not exists review_note text;

-- без security definer: внутри нужно видеть, кто на самом деле меняет запись
create or replace function public.review_campaign()
returns trigger language plpgsql set search_path = public as $$
declare
  me record;
  v_plain boolean;
begin
  if current_user not in ('authenticated', 'anon') or public.is_admin() then return new; end if;
  if tg_op = 'UPDATE'
     and new.image_url is not distinct from old.image_url
     and new.advertiser is not distinct from old.advertiser
     and new.contact is not distinct from old.contact then
    new.review_status := old.review_status;     -- сам себе одобрить нельзя
    new.review_note := old.review_note;
    return new;
  end if;
  select full_name, agency_name into me from profiles where id = new.owner_id;
  v_plain := new.image_url is null and new.contact is null
             and lower(trim(new.advertiser)) in (lower(trim(coalesce(me.full_name, ''))),
                                                 lower(trim(coalesce(me.agency_name, ''))));
  new.review_status := case when v_plain then 'approved' else 'pending' end;
  new.review_note := null;
  return new;
end $$;
drop trigger if exists review_campaign on public.campaigns;
create trigger review_campaign before insert or update on public.campaigns
  for each row execute function public.review_campaign();

drop policy if exists "live campaigns readable" on public.campaigns;
create policy "live campaigns readable" on public.campaigns for select
  using (status = 'active' and review_status = 'approved' and current_date between starts_on and ends_on);

create or replace function public.admin_review_campaign(cid uuid, approve boolean, note text default null)
returns void language plpgsql security definer set search_path = public as $$
begin
  if not public.is_admin() then raise exception 'NOT_ADMIN'; end if;
  update campaigns
     set review_status = case when approve then 'approved' else 'rejected' end,
         review_note = case when approve then null else left(note, 300) end
   where id = cid;
  perform public._audit(case when approve then 'approve_campaign' else 'reject_campaign' end,
                        'campaign', cid::text, note);
end $$;

-- бесплатное продвижение от команды: без телефона, одобрено сразу
create or replace function public.admin_grant_promotion(agent uuid, pid uuid, days int, p_placement text default 'search_top')
returns uuid language plpgsql security definer set search_path = public as $$
declare v_id uuid; a record;
begin
  if not public.is_admin() then raise exception 'NOT_ADMIN'; end if;
  if days < 1 or days > 90 then raise exception 'BAD_DAYS'; end if;
  select full_name, agency_name into a from profiles where id = agent;
  insert into campaigns (owner_id, property_id, advertiser, contact, placement, starts_on, ends_on, granted_by,
                         review_status)
  values (agent, pid, left(coalesce(nullif(a.agency_name, ''), a.full_name, 'Agent'), 80), null,
          p_placement, current_date, current_date + days - 1, auth.uid(), 'approved')
  returning id into v_id;
  perform public._audit('grant_promotion', 'campaign', v_id::text, days || ' days');
  return v_id;
end $$;

-- =====================================================================
-- 6. ПОКАЗЫ И КЛИКИ: НЕ ЧАЩЕ 1 РАЗА В ДЕНЬ С ЧЕЛОВЕКА
--    Вошедший — по аккаунту; гость — по метке устройства,
--    и не больше 20 гостей в день с одного IP-адреса.
-- =====================================================================
create table if not exists public.event_seen (
  target  uuid not null,
  kind    text not null,
  day     date not null default current_date,
  viewer  text not null,
  ip      text,
  primary key (target, kind, day, viewer)
);
create index if not exists event_seen_ip_idx on public.event_seen (target, kind, day, ip);
create index if not exists event_seen_day_idx on public.event_seen (day);
alter table public.event_seen enable row level security;   -- только через функции

create or replace function public._first_event(p_target uuid, p_kind text, p_device text)
returns boolean language plpgsql security definer set search_path = public as $$
declare
  v_ip text := trim(split_part(coalesce(
                 nullif(current_setting('request.headers', true), '')::json ->> 'x-forwarded-for', ''), ',', 1));
  v_viewer text;
begin
  if auth.uid() is not null then
    v_viewer := 'u:' || auth.uid()::text;
  elsif coalesce(trim(p_device), '') <> '' then
    v_viewer := 'd:' || left(trim(p_device), 64);
    if v_ip <> '' and (select count(*) from event_seen
                        where target = p_target and kind = p_kind and day = current_date and ip = v_ip) >= 20 then
      return false;
    end if;
  else
    v_viewer := 'ip:' || v_ip;
  end if;
  insert into event_seen (target, kind, viewer, ip) values (p_target, p_kind, v_viewer, nullif(v_ip, ''))
  on conflict do nothing;
  if not found then return false; end if;
  if random() < 0.01 then delete from event_seen where day < current_date - 2; end if;   -- уборка
  return true;
end $$;
revoke execute on function public._first_event(uuid, text, text) from public, anon, authenticated;

drop function if exists public.log_ad_event(uuid, text);
create or replace function public.log_ad_event(aid uuid, kind text, device text default null)
returns void language plpgsql security definer set search_path = public as $$
begin
  if kind not in ('view', 'click') then return; end if;
  if not exists (select 1 from ads where id = aid and status = 'active'
                   and current_date between starts_on and ends_on) then
    return;
  end if;
  if not public._first_event(aid, kind, device) then return; end if;
  insert into ad_stats (ad_id, day, views, clicks)
  values (aid, current_date, (kind = 'view')::int, (kind = 'click')::int)
  on conflict (ad_id, day) do update
     set views = ad_stats.views + excluded.views, clicks = ad_stats.clicks + excluded.clicks;
end $$;
grant execute on function public.log_ad_event(uuid, text, text) to anon, authenticated;

drop function if exists public.log_campaign_event(uuid, text);
create or replace function public.log_campaign_event(cid uuid, kind text, device text default null)
returns void language plpgsql security definer set search_path = public as $$
begin
  if kind not in ('view', 'click') then return; end if;
  if not exists (select 1 from campaigns where id = cid and status = 'active' and review_status = 'approved'
                   and current_date between starts_on and ends_on) then
    return;
  end if;
  if not public._first_event(cid, kind, device) then return; end if;
  insert into campaign_stats (campaign_id, day, views, clicks)
  values (cid, current_date, (kind = 'view')::int, (kind = 'click')::int)
  on conflict (campaign_id, day) do update
     set views  = campaign_stats.views  + excluded.views,
         clicks = campaign_stats.clicks + excluded.clicks;
end $$;
grant execute on function public.log_campaign_event(uuid, text, text) to anon, authenticated;

-- =====================================================================
-- 3. ОДИН ПОДТВЕРЖДЁННЫЙ НОМЕР — ОДИН АККАУНТ
-- =====================================================================
-- «+260 97 123 4567», «0971234567», «260971234567» — один и тот же номер
create or replace function public._norm_phone(p text)
returns text language sql immutable as $$
  select case
           when d ~ '^0[0-9]{9}$' then '260' || substr(d, 2)
           else d
         end
    from (select regexp_replace(coalesce(p, ''), '[^0-9]', '', 'g') as d) x;
$$;

-- если номер уже подтверждён на нескольких аккаунтах — оставляем самый первый
update public.profiles p
   set phone_verified_at = null, phone_verify_channel = null
 where p.phone_verified_at is not null
   and exists (select 1 from public.profiles q
                where q.id <> p.id and q.phone_verified_at is not null
                  and public._norm_phone(q.phone) = public._norm_phone(p.phone)
                  and (q.phone_verified_at, q.id) < (p.phone_verified_at, p.id));

create unique index if not exists profiles_verified_phone_uniq
  on public.profiles (public._norm_phone(phone))
  where phone_verified_at is not null and phone is not null;

-- сменил номер в профиле — подтверждение снимается
create or replace function public.protect_profile_verification()
returns trigger language plpgsql as $$
begin
  if current_user in ('authenticated', 'anon') then
    new.phone_verified_at := old.phone_verified_at;
    new.id_verified_at := old.id_verified_at;
    new.licence_verified_at := old.licence_verified_at;
    if new.phone_verify_channel is distinct from old.phone_verify_channel then
      new.phone_verify_channel := old.phone_verify_channel;
    end if;
    if public._norm_phone(new.phone) is distinct from public._norm_phone(old.phone) then
      new.phone_verified_at := null;
      new.phone_verify_channel := null;
    end if;
    -- сменил номер лицензии — нужна новая сверка
    if new.agent_licence_no is distinct from old.agent_licence_no then
      new.licence_verified_at := null;
    end if;
  end if;
  return new;
end $$;

create or replace function public._phone_taken(p_phone text, p_uid uuid)
returns boolean language sql stable security definer set search_path = public as $$
  select exists (select 1 from profiles
                  where id <> p_uid and phone_verified_at is not null
                    and public._norm_phone(phone) = public._norm_phone(p_phone));
$$;
revoke execute on function public._phone_taken(text, uuid) from public, anon, authenticated;

create or replace function public.request_verification_code(p_channel text, p_destination text)
returns jsonb language plpgsql security definer set search_path = public as $$
declare
  uid uuid := auth.uid();
  v_test boolean := coalesce((select value from app_settings where key = 'otp_test_mode'), 'true') = 'true';
  v_code text;
begin
  if uid is null then raise exception 'AUTH'; end if;
  if p_channel not in ('whatsapp', 'sms', 'email') then raise exception 'BAD_CHANNEL'; end if;
  if exists (select 1 from profiles where id = uid and banned_at is not null) then raise exception 'ACCOUNT_BLOCKED'; end if;
  if p_channel <> 'email' then
    if length(public._norm_phone(p_destination)) < 9 then raise exception 'BAD_PHONE'; end if;
    if public._phone_taken(p_destination, uid) then raise exception 'PHONE_TAKEN'; end if;
  end if;
  if (select count(*) from verification_codes where user_id = uid and created_at > now() - interval '1 hour') >= 5 then
    raise exception 'TOO_MANY_CODES';
  end if;
  v_code := case when v_test then '123456' else lpad((floor(random() * 1000000))::int::text, 6, '0') end;
  insert into verification_codes (user_id, channel, destination, code_hash, expires_at)
  values (uid, p_channel, trim(p_destination), md5(v_code || uid::text), now() + interval '10 minutes');
  return jsonb_build_object('test_mode', v_test);
end $$;

-- ответ: 'ok' | 'wrong' | 'taken'
create or replace function public.verify_verification_code(p_channel text, p_destination text, p_code text)
returns text language plpgsql security definer set search_path = public as $$
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
  if c.code_hash <> md5(trim(p_code) || uid::text) then return 'wrong'; end if;
  update verification_codes set used_at = now() where id = c.id;
  if p_channel = 'email' then
    update profiles set email_verified_at = now() where id = uid;
  else
    if public._phone_taken(c.destination, uid) then return 'taken'; end if;
    update profiles set phone = c.destination, phone_verified_at = now(), phone_verify_channel = p_channel
     where id = uid;
  end if;
  return 'ok';
end $$;

-- =====================================================================
-- 2. ТЕСТОВЫЙ РЕЖИМ КОДОВ: видно команде + кнопка «выключить»
-- =====================================================================
create or replace function public.admin_set_otp_test_mode(p_on boolean)
returns void language plpgsql security definer set search_path = public as $$
begin
  if not public.is_admin() then raise exception 'NOT_ADMIN'; end if;
  insert into app_settings (key, value) values ('otp_test_mode', case when p_on then 'true' else 'false' end)
  on conflict (key) do update set value = excluded.value;
  perform public._audit('otp_test_mode', 'settings', 'otp_test_mode', case when p_on then 'on' else 'off' end);
end $$;

create or replace function public.admin_stats()
returns jsonb language plpgsql stable security definer set search_path = public as $$
begin
  if not public.is_admin() then raise exception 'NOT_ADMIN'; end if;
  return jsonb_build_object(
    'accounts',     (select count(*) from profiles where account_reviewed_at is null and role <> 'admin'),
    'listings_new', (select count(*) from properties where status = 'pending'),
    'campaigns_new',(select count(*) from campaigns where review_status = 'pending' and status <> 'stopped'
                       and ends_on >= current_date),
    'id_checks',    (select count(*) from verification_requests where kind = 'identity'  and status = 'pending'),
    'ownership',    (select count(*) from verification_requests where kind = 'ownership' and status = 'pending'),
    'licences',     (select count(*) from profiles where agent_licence_no is not null and licence_verified_at is null),
    'reports',      (select count(*) from listing_reports where status = 'new'),
    'tickets',      (select count(*) from support_tickets where status = 'open'),
    'reviews',      (select count(*) from reviews where flags_count > 0 and status = 'published'),
    'listings',     (select count(*) from properties where status = 'active'),
    'users',        (select count(*) from profiles),
    'otp_test_mode', coalesce((select value from app_settings where key = 'otp_test_mode'), 'true') = 'true'
  );
end $$;
