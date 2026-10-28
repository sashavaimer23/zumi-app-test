-- =====================================================================
--  Zumi — 014: аккаунт команды без «личных» функций, реклама и
--  статистика для владельца, раздел разработчика (только числа)
--  1. Аккаунт команды не публикует объявления и не запускает продвижение
--     (раньше объявления админа шли без проверки и без лимита — лазейка).
--  2. Проверка кампаний агентов со своей картинкой — во вкладке «Реклама» (владелец).
--  3. Отчёт по рекламе: показы, клики, % кликов по каждому баннеру и кампании, по дням.
--  4. Раздел разработчика: активные за день и месяц, возвраты, воронки,
--     платформы и версии приложения, ошибки. Без данных конкретных людей.
--  Запускать после 013. Можно запускать повторно.
-- =====================================================================

-- =====================================================================
-- 1. АККАУНТ КОМАНДЫ — НЕ ДЛЯ ОБЪЯВЛЕНИЙ
-- =====================================================================
create or replace function public.no_team_listings()
returns trigger language plpgsql security definer set search_path = public, extensions as $$
begin
  if not new.is_demo and exists (select 1 from profiles where id = new.owner_id and role = 'admin') then
    raise exception 'TEAM_ACCOUNT';
  end if;
  return new;
end $$;
drop trigger if exists no_team_listings on public.properties;
create trigger no_team_listings before insert on public.properties
  for each row execute function public.no_team_listings();

-- первые 2 объявления — на проверку; исключения для админа больше нет
create or replace function public.moderate_new_listing()
returns trigger language plpgsql security definer set search_path = public, extensions as $$
begin
  if new.is_demo or new.owner_id is null then
    new.approved_at := coalesce(new.approved_at, now());
    return new;
  end if;
  if (select count(*) from properties where owner_id = new.owner_id and approved_at is not null) >= 2 then
    new.approved_at := now();
  else
    new.status := 'pending';
    new.approved_at := null;
  end if;
  new.moderation_note := null;
  return new;
end $$;

-- продвижение — только агенты с проверенной лицензией (команда — нет)
create or replace function public.check_campaign()
returns trigger language plpgsql security definer set search_path = public, extensions as $$
declare
  v_role text;
  v_licence timestamptz;
  v_live int;
begin
  select role, licence_verified_at into v_role, v_licence from profiles where id = new.owner_id;
  if v_role is distinct from 'agent' then raise exception 'AGENTS_ONLY'; end if;
  if v_licence is null and new.status = 'active' then raise exception 'LICENCE_NOT_VERIFIED'; end if;
  if new.status = 'active' and not exists (select 1 from properties p where p.id = new.property_id
                   and p.owner_id = new.owner_id and p.status = 'active') then
    raise exception 'NOT_YOUR_LISTING';
  end if;
  if tg_op = 'UPDATE' and old.status = 'stopped' and new.status <> 'stopped' then
    raise exception 'CAMPAIGN_STOPPED';
  end if;
  if tg_op = 'INSERT' and new.starts_on < current_date then
    raise exception 'START_IN_PAST';
  end if;
  if new.status = 'active' then
    select count(*) into v_live from campaigns c
     where c.owner_id = new.owner_id and c.status = 'active' and c.ends_on >= current_date
       and c.id <> new.id;
    if v_live >= 3 then raise exception 'CAMPAIGN_LIMIT'; end if;
  end if;
  return new;
end $$;

-- =====================================================================
-- 2. КАМПАНИИ АГЕНТОВ СО СВОЕЙ КАРТИНКОЙ — РЕШАЕТ ВЛАДЕЛЕЦ (вкладка «Реклама»)
-- =====================================================================
create or replace function public.admin_review_campaign(cid uuid, approve boolean, note text default null)
returns void language plpgsql security definer set search_path = public, extensions as $$
begin
  if not public.is_owner() then raise exception 'OWNER_ONLY'; end if;
  update campaigns
     set review_status = case when approve then 'approved' else 'rejected' end,
         review_note = case when approve then null else left(note, 300) end
   where id = cid;
  perform public._audit(case when approve then 'approve_campaign' else 'reject_campaign' end,
                        'campaign', cid::text, note);
end $$;

-- =====================================================================
-- 3. ОТЧЁТ ПО РЕКЛАМЕ: баннеры и кампании продвижения, по дням
-- =====================================================================
create or replace function public.owner_ad_report(p_days int default 30)
returns jsonb language plpgsql stable security definer set search_path = public, extensions as $$
declare v_from date := current_date - greatest(least(p_days, 366), 1) + 1;
begin
  if not public.is_owner() then raise exception 'OWNER_ONLY'; end if;
  return coalesce((
    select jsonb_agg(x order by x->>'kind', (x->>'views')::int desc) from (
      -- баннеры
      select jsonb_build_object(
               'kind', 'banner', 'id', a.id, 'title', a.title, 'advertiser', a.advertiser,
               'placement', a.placement, 'status', a.status, 'starts_on', a.starts_on, 'ends_on', a.ends_on,
               'views',  coalesce((select sum(s.views)  from ad_stats s where s.ad_id = a.id and s.day >= v_from), 0),
               'clicks', coalesce((select sum(s.clicks) from ad_stats s where s.ad_id = a.id and s.day >= v_from), 0),
               'calls', 0, 'messages', 0,
               'days', coalesce((select jsonb_agg(jsonb_build_object('day', s.day, 'views', s.views, 'clicks', s.clicks,
                                                                     'calls', 0, 'messages', 0) order by s.day)
                                   from ad_stats s where s.ad_id = a.id and s.day >= v_from), '[]'::jsonb)) as x
        from ads a
       where a.ends_on >= v_from and a.status <> 'draft'
      union all
      -- продвижение объявлений агентов
      select jsonb_build_object(
               'kind', 'campaign', 'id', c.id,
               'title', coalesce((select p.title from properties p where p.id = c.property_id), 'Listing'),
               'advertiser', c.advertiser, 'placement', c.placement, 'status', c.status,
               'starts_on', c.starts_on, 'ends_on', c.ends_on,
               'views',    coalesce((select sum(s.views)    from campaign_stats s where s.campaign_id = c.id and s.day >= v_from), 0),
               'clicks',   coalesce((select sum(s.clicks)   from campaign_stats s where s.campaign_id = c.id and s.day >= v_from), 0),
               'calls',    coalesce((select sum(s.calls)    from campaign_stats s where s.campaign_id = c.id and s.day >= v_from), 0),
               'messages', coalesce((select sum(s.messages) from campaign_stats s where s.campaign_id = c.id and s.day >= v_from), 0),
               'days', coalesce((select jsonb_agg(jsonb_build_object('day', s.day, 'views', s.views, 'clicks', s.clicks,
                                                                     'calls', s.calls, 'messages', s.messages) order by s.day)
                                   from campaign_stats s where s.campaign_id = c.id and s.day >= v_from), '[]'::jsonb))
        from campaigns c
       where c.ends_on >= v_from and c.review_status = 'approved'
    ) t(x)), '[]'::jsonb);
end $$;

-- =====================================================================
-- 4. РАЗДЕЛ РАЗРАБОТЧИКА — только числа
-- =====================================================================
alter table public.traffic_daily add column if not exists returners int not null default 0;

create table if not exists public.traffic_monthly (
  month    date primary key,                -- первое число месяца (время Лусаки)
  visitors int not null default 0
);
-- платформа (web / android / ios) и версия приложения — по дням
create table if not exists public.traffic_platform (
  day      date not null,
  platform text not null,
  version  text not null,
  visits   int  not null default 0,
  visitors int  not null default 0,
  primary key (day, platform, version)
);
-- ошибки приложения: текст ошибки (без цифр и почты), сколько раз — по дням
create table if not exists public.error_stats (
  day       date not null,
  platform  text not null,
  version   text not null,
  message   text not null,
  n         int  not null default 0,
  last_at   timestamptz not null default now(),
  primary key (day, platform, version, message)
);
alter table public.traffic_monthly  enable row level security;
alter table public.traffic_platform enable row level security;
alter table public.error_stats      enable row level security;

-- посещение: + платформа и версия, + «вернулся» и активные за месяц
drop function if exists public.log_visit(text);
create or replace function public.log_visit(device text default null, p_platform text default null,
                                            p_version text default null)
returns void language plpgsql security definer set search_path = public, extensions as $$
declare
  v_viewer text;
  v_hour timestamptz := date_trunc('hour', now());
  v_day date := (now() at time zone 'Africa/Lusaka')::date;
  v_month date := date_trunc('month', (now() at time zone 'Africa/Lusaka'))::date;
  v_signed boolean := auth.uid() is not null;
  v_platform text := case when p_platform in ('web', 'android', 'ios') then p_platform else 'other' end;
  v_version text := coalesce(nullif(left(regexp_replace(coalesce(p_version, ''), '[^0-9A-Za-z.+-]', '', 'g'), 20), ''), '?');
  v_last timestamptz;
  v_returning boolean;
begin
  if v_signed then v_viewer := md5('u:' || auth.uid()::text);
  elsif coalesce(trim(device), '') <> '' then v_viewer := md5('d:' || left(trim(device), 64));
  else return;
  end if;

  select last_at into v_last from visit_last where viewer = v_viewer;
  if v_last is not null and v_last > now() - interval '30 minutes' then
    update visit_last set last_at = now() where viewer = v_viewer;
    return;                                   -- тот же сеанс
  end if;
  insert into visit_last (viewer, last_at) values (v_viewer, now())
  on conflict (viewer) do update set last_at = excluded.last_at;

  insert into traffic_hourly (hour, visits) values (v_hour, 1)
  on conflict (hour) do update set visits = traffic_hourly.visits + 1;
  insert into traffic_platform (day, platform, version, visits) values (v_day, v_platform, v_version, 1)
  on conflict (day, platform, version) do update set visits = traffic_platform.visits + 1;

  insert into visit_seen (viewer, period, at) values (v_viewer, 'h', v_hour) on conflict do nothing;
  if found then
    update traffic_hourly set visitors = visitors + 1, signed_in = signed_in + v_signed::int where hour = v_hour;
  end if;

  insert into visit_seen (viewer, period, at) values (v_viewer, 'd', v_day::timestamptz) on conflict do nothing;
  if found then
    -- «вернулся»: этот человек уже заходил в предыдущие 30 дней
    v_returning := exists (select 1 from visit_seen where viewer = v_viewer and period = 'd'
                            and at < v_day::timestamptz and at >= (v_day - 30)::timestamptz);
    insert into traffic_daily (day, visitors, signed_in, returners) values (v_day, 1, v_signed::int, v_returning::int)
    on conflict (day) do update set visitors = traffic_daily.visitors + 1,
                                    signed_in = traffic_daily.signed_in + excluded.signed_in,
                                    returners = traffic_daily.returners + excluded.returners;
    update traffic_platform set visitors = visitors + 1
     where day = v_day and platform = v_platform and version = v_version;
  end if;

  insert into visit_seen (viewer, period, at) values (v_viewer, 'm', v_month::timestamptz) on conflict do nothing;
  if found then
    insert into traffic_monthly (month, visitors) values (v_month, 1)
    on conflict (month) do update set visitors = traffic_monthly.visitors + 1;
  end if;
end $$;
grant execute on function public.log_visit(text, text, text) to anon, authenticated;

-- ошибка приложения (без личных данных: цифры и почта вырезаются)
create or replace function public.log_error(p_platform text, p_version text, p_message text)
returns void language plpgsql security definer set search_path = public, extensions as $$
declare
  v_day date := (now() at time zone 'Africa/Lusaka')::date;
  v_platform text := case when p_platform in ('web', 'android', 'ios') then p_platform else 'other' end;
  v_version text := coalesce(nullif(left(regexp_replace(coalesce(p_version, ''), '[^0-9A-Za-z.+-]', '', 'g'), 20), ''), '?');
  v_msg text := left(trim(regexp_replace(regexp_replace(regexp_replace(coalesce(p_message, ''),
                  '[^\s@]+@[^\s@]+', '[email]', 'g'), '[0-9]{3,}', '#', 'g'), '\s+', ' ', 'g')), 200);
begin
  if v_msg = '' then return; end if;
  -- защита от потока: не больше 300 разных ошибок в день
  if not exists (select 1 from error_stats where day = v_day and platform = v_platform and version = v_version
                  and message = v_msg)
     and (select count(*) from error_stats where day = v_day) >= 300 then
    return;
  end if;
  insert into error_stats (day, platform, version, message, n) values (v_day, v_platform, v_version, v_msg, 1)
  on conflict (day, platform, version, message) do update set n = error_stats.n + 1, last_at = now();
end $$;
grant execute on function public.log_error(text, text, text) to anon, authenticated;

-- ежедневная уборка: метки часа — 2 дня; метки дня и месяца (зашифрованы) — до 35 дней (нужны для «вернулся» и «за месяц»)
create or replace function public.cleanup_daily()
returns void language plpgsql security definer set search_path = public, extensions as $$
begin
  if not public._is_admin_or_service() and current_user not in ('postgres', 'supabase_admin') then
    raise exception 'NOT_ADMIN';
  end if;
  delete from event_seen where day < current_date - 1;
  delete from visit_seen where period = 'h' and at < now() - interval '2 days';
  delete from visit_seen where period in ('d', 'm') and at < now() - interval '35 days';
  delete from visit_last where last_at < now() - interval '2 days';
  delete from error_stats where day < current_date - 90;
  delete from verification_codes where created_at < now() - interval '30 days';
  update verification_requests
     set status = 'expired', reviewed_at = now(),
         reviewer_note = coalesce(reviewer_note, 'No decision within 30 days — documents deleted. Please send again.')
   where status = 'pending' and created_at < now() - interval '30 days';
end $$;

-- сводка для разработчика за p_days дней
create or replace function public.dev_stats(p_days int default 30)
returns jsonb language plpgsql stable security definer set search_path = public, extensions as $$
declare
  v_days int := greatest(least(p_days, 90), 1);
  v_today date := (now() at time zone 'Africa/Lusaka')::date;
  v_from date := v_today - v_days + 1;
  v_from_ts timestamptz := (v_from::timestamp at time zone 'Africa/Lusaka');
begin
  if not public.is_owner() then raise exception 'OWNER_ONLY'; end if;
  return jsonb_build_object(
    'from', v_from, 'to', v_today,
    'dau_today', coalesce((select visitors from traffic_daily where day = v_today), 0),
    'dau_avg', coalesce((select round(avg(visitors)) from traffic_daily where day between v_from and v_today), 0),
    'mau', coalesce((select visitors from traffic_monthly
                      where month = date_trunc('month', v_today)::date), 0),
    'returning_share', coalesce((select round(100.0 * sum(returners) / nullif(sum(visitors), 0))
                                   from traffic_daily where day between v_from and v_today), 0),
    'daily', coalesce((select jsonb_agg(jsonb_build_object('day', d::date,
                         'visitors', coalesce(t.visitors, 0), 'returning', coalesce(t.returners, 0),
                         'signed_in', coalesce(t.signed_in, 0)) order by d)
                        from generate_series(v_from, v_today, interval '1 day') d
                        left join traffic_daily t on t.day = d::date), '[]'::jsonb),
    'months', coalesce((select jsonb_agg(jsonb_build_object('month', month, 'visitors', visitors) order by month)
                         from traffic_monthly where month >= date_trunc('month', v_today)::date - interval '11 months'),
                       '[]'::jsonb),
    -- воронка того, кто размещает: регистрация → телефон → объявление → по объявлению связались
    'funnel_seller', (
      with c as (select id, phone_verified_at is not null as phone from profiles
                  where created_at >= v_from_ts and role <> 'admin'),
           l as (select c.*, exists (select 1 from properties p where p.owner_id = c.id and not p.is_demo) as listing from c),
           k as (select l.*, l.phone and l.listing and (
                   exists (select 1 from phone_reveals r join properties p on p.id = r.property_id where p.owner_id = l.id)
                   or exists (select 1 from conversations v where v.seller_id = l.id)) as contact from l)
      select jsonb_build_object('signups', count(*), 'phone', count(*) filter (where phone),
                                'listing', count(*) filter (where phone and listing),
                                'contact', count(*) filter (where contact)) from k),
    -- воронка того, кто ищет: регистрация → телефон → связался с автором
    'funnel_buyer', (
      with c as (select id, phone_verified_at is not null as phone from profiles
                  where created_at >= v_from_ts and role <> 'admin')
      select jsonb_build_object('signups', count(*), 'phone', count(*) filter (where phone),
                                'contact', count(*) filter (where phone and (
                                   exists (select 1 from phone_reveals r where r.user_id = c.id)
                                   or exists (select 1 from conversations v where v.buyer_id = c.id)))) from c),
    'platforms', coalesce((select jsonb_agg(x order by (x->>'visits')::int desc) from (
        select jsonb_build_object('platform', platform, 'version', version,
                                  'visits', sum(visits), 'visitors', sum(visitors)) x
          from traffic_platform where day between v_from and v_today
         group by platform, version) t), '[]'::jsonb),
    'errors', coalesce((select jsonb_agg(x order by (x->>'n')::int desc) from (
        select jsonb_build_object('platform', platform, 'version', version, 'message', message,
                                  'n', sum(n), 'last_at', max(last_at)) x
          from error_stats where day between v_from and v_today
         group by platform, version, message
         order by sum(n) desc limit 50) t), '[]'::jsonb)
  );
end $$;

-- =====================================================================
-- 5. СТАТЬИ ПОМОЩИ: убираем неизмеренные обещания (если команда статью ещё не правила)
-- =====================================================================
update public.help_articles set body = 'Tap "Post" on the home screen (or "Post a listing" on the website) and follow the steps:
- Choose rent or sale and the type of property.
- Add a clear title, the price and the main details (bedrooms, bathrooms, size).
- Put the pin exactly on the property on the map.
- Add good photos: daylight, every room, the outside and the street. 5 or more photos give people a clear picture.
- Check the preview and publish.

## Tips
- Write the real price, so people know right away if the home fits their budget.
- Do not put phone numbers or links inside photos or the description — use the contact settings instead.
- Confirm "still available" every 60 days, otherwise the listing is hidden from search.'
 where id = 'e2232f2d-41f2-569a-a8f0-f3ebc63e88b5' and updated_by is null;
update public.help_articles set body = 'The Verified badge shows that Zumi checked who you are.

Steps (about 3 minutes):
- Confirm your phone with a WhatsApp or SMS code.
- Take a photo of your NRC or passport and a selfie.
- Agents also add their ZIEA registration number.

The Zumi team checks the documents, usually within the same day. As soon as the team approves or rejects the check, the photos of your documents and selfie are deleted. We keep only the result.

If there is no decision within 30 days, the photos are deleted and you need to send them again.'
 where id = 'f131b212-3739-54b4-8711-d0657f8640a7' and updated_by is null;
