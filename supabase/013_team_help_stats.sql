-- =====================================================================
--  Zumi — 013: роли команды, раздел «Помощь», статистика владельца
--  1. Роли: модератор (проверки, жалобы, поддержка) и владелец (всё это +
--     статистика, реклама, деньги, настройки, выдача ролей, журнал действий).
--     Права проверяет сервер.
--  2. «Помощь»: статьи в базе (правятся из кабинета), оценки «полезно / нет»,
--     обращение в поддержку с пометкой статьи.
--  3. Посещаемость — только обезличенные числа по часам и дням;
--     поиски — только счётчики по району и фильтрам.
--  Запускать после 012. Можно запускать повторно.
-- =====================================================================

-- =====================================================================
-- 1. РОЛИ КОМАНДЫ
-- =====================================================================
alter table public.profiles
  add column if not exists team_level text check (team_level in ('moderator', 'owner'));
-- все, кто уже в команде, — владельцы (новый админ, назначенный через SQL, тоже владелец)
update public.profiles set team_level = 'owner' where role = 'admin' and team_level is null;
grant select (team_level) on public.profiles to authenticated;
revoke update (team_level) on public.profiles from authenticated;

-- is_admin() = любой член команды (модератор или владелец) — проверки, жалобы, поддержка
create or replace function public.is_owner()
returns boolean language sql stable security definer set search_path = public as $$
  select exists (select 1 from profiles where id = auth.uid() and role = 'admin'
                  and coalesce(team_level, 'owner') = 'owner');
$$;

-- список команды и выдача ролей — только владелец
create or replace function public.admin_team()
returns table (user_id uuid, full_name text, email text, level text, since timestamptz)
language plpgsql stable security definer set search_path = public, auth as $$
begin
  if not public.is_owner() then raise exception 'OWNER_ONLY'; end if;
  return query
    select pr.id, pr.full_name, u.email::text, coalesce(pr.team_level, 'owner'), pr.created_at
      from profiles pr left join auth.users u on u.id = pr.id
     where pr.role = 'admin'
     order by coalesce(pr.team_level, 'owner') desc, pr.full_name;
end $$;

-- p_level: 'moderator' | 'owner' | null (убрать из команды)
create or replace function public.admin_set_team(p_email text, p_level text)
returns void language plpgsql security definer set search_path = public, auth as $$
declare v_id uuid; v_role text;
begin
  if not public.is_owner() then raise exception 'OWNER_ONLY'; end if;
  if p_level is not null and p_level not in ('moderator', 'owner') then raise exception 'BAD_LEVEL'; end if;
  select u.id into v_id from auth.users u where lower(u.email) = lower(trim(p_email));
  if v_id is null then raise exception 'USER_NOT_FOUND'; end if;
  if v_id = auth.uid() then raise exception 'NOT_YOURSELF'; end if;
  select role into v_role from profiles where id = v_id;
  if p_level is null then
    update profiles set role = case when role = 'admin' then 'owner' else role end, team_level = null where id = v_id;
  else
    update profiles set role = 'admin', team_level = p_level where id = v_id;
  end if;
  perform public._audit('team_role', 'profile', v_id::text, coalesce(p_level, 'removed'));
end $$;

-- ---- что доступно только владельцу ----
-- реклама
drop policy if exists "admins manage ads" on public.ads;
create policy "admins manage ads" on public.ads for all
  using (public.is_owner()) with check (public.is_owner());
drop policy if exists "admins read ad stats" on public.ad_stats;
create policy "admins read ad stats" on public.ad_stats for select using (public.is_owner());
drop policy if exists "admins upload ad images" on storage.objects;
create policy "admins upload ad images" on storage.objects for insert to authenticated
  with check (bucket_id = 'ad-images' and public.is_owner());
-- журнал действий модераторов
drop policy if exists "admins read audit" on public.admin_audit;
create policy "admins read audit" on public.admin_audit for select using (public.is_owner());
-- деньги
drop policy if exists "owners read payments" on public.payments;
create policy "owners read payments" on public.payments for select using (public.is_owner());

-- настройки
create or replace function public.admin_set_otp_test_mode(p_on boolean)
returns void language plpgsql security definer set search_path = public as $$
begin
  if not public.is_owner() then raise exception 'OWNER_ONLY'; end if;
  insert into app_settings (key, value) values ('otp_test_mode', case when p_on then 'true' else 'false' end)
  on conflict (key) do update set value = excluded.value;
  perform public._audit('otp_test_mode', 'settings', 'otp_test_mode', case when p_on then 'on' else 'off' end);
end $$;

create or replace function public.admin_set_setting(p_key text, p_value text)
returns void language plpgsql security definer set search_path = public as $$
begin
  if not public.is_owner() then raise exception 'OWNER_ONLY'; end if;
  if p_key not in ('otp_test_mode', 'require_licence_to_publish') then raise exception 'BAD_SETTING'; end if;
  if p_value not in ('true', 'false') then raise exception 'BAD_SETTING'; end if;
  insert into app_settings (key, value) values (p_key, p_value)
  on conflict (key) do update set value = excluded.value;
  perform public._audit('setting', 'settings', p_key, p_value);
end $$;

-- бесплатное продвижение (это деньги) — только владелец
create or replace function public.admin_grant_promotion(agent uuid, pid uuid, days int, p_placement text default 'search_top')
returns uuid language plpgsql security definer set search_path = public as $$
declare v_id uuid; a record;
begin
  if not public.is_owner() then raise exception 'OWNER_ONLY'; end if;
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

-- список для рассылки — только владелец
create or replace function public.admin_marketing_list()
returns table (user_id uuid, full_name text, role text, email text, whatsapp text,
               email_since timestamptz, whatsapp_since timestamptz)
language plpgsql stable security definer set search_path = public, auth as $$
begin
  if not public.is_owner() then raise exception 'OWNER_ONLY'; end if;
  return query
    select pr.id, pr.full_name, pr.role,
           case when pr.marketing_email_at is not null then u.email::text end,
           case when pr.marketing_whatsapp_at is not null and pr.phone_verified_at is not null then pr.phone end,
           pr.marketing_email_at, pr.marketing_whatsapp_at
      from profiles pr join auth.users u on u.id = pr.id
     where (pr.marketing_email_at is not null or pr.marketing_whatsapp_at is not null) and pr.banned_at is null
     order by greatest(pr.marketing_email_at, pr.marketing_whatsapp_at) desc;
end $$;

-- =====================================================================
-- 2. ПОМОЩЬ
-- =====================================================================
create table if not exists public.help_articles (
  id          uuid primary key default gen_random_uuid(),
  category    text not null check (category in
                ('account', 'listings', 'contact', 'verification', 'promotion', 'safety', 'technical')),
  title       text not null check (length(trim(title)) between 3 and 140),
  body        text not null check (length(body) <= 20000),
  sort        int  not null default 100,
  published   boolean not null default true,
  -- только на сайте: статьи про оплату не показываем в приложениях (правила Apple и Google)
  web_only    boolean not null default false,
  updated_by  uuid references public.profiles(id) on delete set null,
  created_at  timestamptz not null default now(),
  updated_at  timestamptz not null default now()
);
alter table public.help_articles enable row level security;
drop policy if exists "published help readable" on public.help_articles;
create policy "published help readable" on public.help_articles for select
  using (published or public.is_admin());
drop policy if exists "team edits help" on public.help_articles;
create policy "team edits help" on public.help_articles for all
  using (public.is_admin()) with check (public.is_admin());
grant select on public.help_articles to anon, authenticated;
grant insert, update, delete on public.help_articles to authenticated;

create or replace function public.touch_help_article()
returns trigger language plpgsql as $$
begin
  new.updated_at := now();
  new.updated_by := coalesce(auth.uid(), new.updated_by);
  return new;
end $$;
drop trigger if exists touch_help_article on public.help_articles;
create trigger touch_help_article before insert or update on public.help_articles
  for each row execute function public.touch_help_article();

-- оценки: один голос с человека (вошедший — по аккаунту, гость — по метке устройства)
create table if not exists public.help_votes (
  article_id uuid not null references public.help_articles(id) on delete cascade,
  voter      text not null,
  user_id    uuid references public.profiles(id) on delete set null,
  helpful    boolean not null,
  comment    text check (comment is null or length(comment) <= 1000),
  created_at timestamptz not null default now(),
  primary key (article_id, voter)
);
alter table public.help_votes enable row level security;   -- только через функции

create or replace function public.vote_help(aid uuid, p_helpful boolean, p_comment text default null,
                                            device text default null)
returns void language plpgsql security definer set search_path = public as $$
declare v_voter text;
begin
  if auth.uid() is not null then v_voter := 'u:' || auth.uid()::text;
  elsif coalesce(trim(device), '') <> '' then v_voter := 'd:' || md5(left(trim(device), 64));
  else raise exception 'NO_VOTER';
  end if;
  if not exists (select 1 from help_articles where id = aid and published) then raise exception 'NOT_FOUND'; end if;
  insert into help_votes (article_id, voter, user_id, helpful, comment)
  values (aid, v_voter, auth.uid(), p_helpful, nullif(left(trim(coalesce(p_comment, '')), 1000), ''))
  on conflict (article_id, voter) do update
     set helpful = excluded.helpful,
         comment = excluded.comment,
         created_at = now();
end $$;
grant execute on function public.vote_help(uuid, boolean, text, text) to anon, authenticated;

-- оценки статей для команды: худшие сверху
create or replace function public.admin_help_ratings()
returns table (article_id uuid, title text, category text, yes int, no int, comments jsonb)
language plpgsql stable security definer set search_path = public as $$
begin
  if not public.is_admin() then raise exception 'NOT_ADMIN'; end if;
  return query
    select a.id, a.title, a.category,
           count(*) filter (where v.helpful)::int,
           count(*) filter (where v.helpful = false)::int,
           coalesce((select jsonb_agg(jsonb_build_object('text', c.comment, 'at', c.created_at) order by c.created_at desc)
                       from (select v2.comment, v2.created_at from help_votes v2
                              where v2.article_id = a.id and v2.comment is not null
                              order by v2.created_at desc limit 20) c), '[]'::jsonb)
      from help_articles a
      left join help_votes v on v.article_id = a.id
     group by a.id
     order by (count(*) filter (where v.helpful = false) - count(*) filter (where v.helpful)) desc,
              count(*) filter (where v.helpful = false) desc, a.title;
end $$;

-- обращение в поддержку с пометкой, какая статья не помогла
alter table public.support_tickets
  add column if not exists help_article_id uuid references public.help_articles(id) on delete set null;

-- =====================================================================
-- 3. СТАТИСТИКА (обезличенно: только числа)
-- =====================================================================
create table if not exists public.traffic_hourly (
  hour      timestamptz primary key,      -- начало часа
  visits    int not null default 0,       -- посещения (сеансы)
  visitors  int not null default 0,       -- разные люди за этот час
  signed_in int not null default 0        -- из них вошедших
);
create table if not exists public.traffic_daily (
  day       date primary key,             -- день по времени Лусаки
  visitors  int not null default 0,
  signed_in int not null default 0
);
-- служебные метки (зашифрованы md5, удаляются через 2 дня) — нужны только чтобы не считать человека дважды
create table if not exists public.visit_seen (
  viewer text not null,
  period text not null,                   -- 'h' час / 'd' день / 's' последний сеанс
  at     timestamptz not null,
  primary key (viewer, period, at)
);
create table if not exists public.visit_last (
  viewer  text primary key,
  last_at timestamptz not null
);
create table if not exists public.search_stats (
  day   date not null,
  dim   text not null,                    -- area · deal · type · beds · price · verified · …
  value text not null,
  n     int  not null default 0,
  primary key (day, dim, value)
);
alter table public.traffic_hourly enable row level security;
alter table public.traffic_daily  enable row level security;
alter table public.visit_seen     enable row level security;
alter table public.visit_last     enable row level security;
alter table public.search_stats   enable row level security;

-- приложение сообщает «я открыто»: новый сеанс — если с прошлого прошло больше 30 минут
create or replace function public.log_visit(device text default null)
returns void language plpgsql security definer set search_path = public as $$
declare
  v_viewer text;
  v_hour timestamptz := date_trunc('hour', now());
  v_day date := (now() at time zone 'Africa/Lusaka')::date;
  v_signed boolean := auth.uid() is not null;
  v_last timestamptz;
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

  insert into visit_seen (viewer, period, at) values (v_viewer, 'h', v_hour) on conflict do nothing;
  if found then
    update traffic_hourly set visitors = visitors + 1, signed_in = signed_in + v_signed::int where hour = v_hour;
  end if;
  insert into visit_seen (viewer, period, at) values (v_viewer, 'd', v_day::timestamptz) on conflict do nothing;
  if found then
    insert into traffic_daily (day, visitors, signed_in) values (v_day, 1, v_signed::int)
    on conflict (day) do update set visitors = traffic_daily.visitors + 1,
                                    signed_in = traffic_daily.signed_in + excluded.signed_in;
  end if;
end $$;
grant execute on function public.log_visit(text) to anon, authenticated;

-- поиск: только счётчики (район (id), тип сделки, тип жилья, спальни, цена, фильтры) — без людей
create or replace function public.log_search(p jsonb)
returns void language plpgsql security definer set search_path = public as $$
declare k text; v text;
begin
  if p is null or jsonb_typeof(p) <> 'object' then return; end if;
  for k, v in select key, left(value #>> '{}', 40) from jsonb_each(p) loop
    continue when k not in ('area', 'city', 'deal', 'type', 'beds', 'price', 'verified', 'furnished', 'query');
    continue when coalesce(v, '') = '';
    insert into search_stats (day, dim, value, n)
    values ((now() at time zone 'Africa/Lusaka')::date, k, case when k in ('area', 'query') then v else lower(v) end, 1)
    on conflict (day, dim, value) do update set n = search_stats.n + 1;
  end loop;
end $$;
grant execute on function public.log_search(jsonb) to anon, authenticated;

-- ежедневная уборка: + служебные метки посещений (не дольше 2 дней)
create or replace function public.cleanup_daily()
returns void language plpgsql security definer set search_path = public as $$
begin
  if not public._is_admin_or_service() and current_user not in ('postgres', 'supabase_admin') then
    raise exception 'NOT_ADMIN';
  end if;
  delete from event_seen where day < current_date - 1;
  delete from visit_seen where at < now() - interval '2 days';
  delete from visit_last where last_at < now() - interval '2 days';
  delete from verification_codes where created_at < now() - interval '30 days';
  update verification_requests
     set status = 'expired', reviewed_at = now(),
         reviewer_note = coalesce(reviewer_note, 'No decision within 30 days — documents deleted. Please send again.')
   where status = 'pending' and created_at < now() - interval '30 days';
end $$;

-- панель владельца: p_period = 'day' (сегодня по часам) | 'week' | 'month' (по дням), время Лусаки
create or replace function public.owner_dashboard(p_period text default 'day')
returns jsonb language plpgsql stable security definer set search_path = public as $$
declare
  tz constant text := 'Africa/Lusaka';
  v_today date := (now() at time zone tz)::date;
  v_days int := case p_period when 'week' then 7 when 'month' then 30 else 1 end;
  v_from_day date := v_today - (v_days - 1);
  v_from timestamptz := (v_from_day::timestamp at time zone tz);
  v_to timestamptz := ((v_today + 1)::timestamp at time zone tz);
  v_hourly boolean := p_period not in ('week', 'month');
  v_series jsonb;
  v_totals jsonb;
begin
  if not public.is_owner() then raise exception 'OWNER_ONLY'; end if;

  with buckets as (
    select b as t_start, b + case when v_hourly then interval '1 hour' else interval '1 day' end as t_end
      from generate_series(v_from, v_to - interval '1 second',
                           case when v_hourly then interval '1 hour' else interval '1 day' end) b
  )
  select jsonb_agg(jsonb_build_object(
           't', to_char(t_start at time zone tz, case when v_hourly then 'HH24:00' else 'YYYY-MM-DD' end),
           'visits',   (select coalesce(sum(visits), 0) from traffic_hourly where hour >= t_start and hour < t_end),
           'visitors', case when v_hourly
                         then (select coalesce(sum(visitors), 0) from traffic_hourly where hour >= t_start and hour < t_end)
                         else (select coalesce(sum(visitors), 0) from traffic_daily
                                where day = (t_start at time zone tz)::date) end,
           'contacts', (select count(*) from phone_reveals where created_at >= t_start and created_at < t_end)
                     + (select count(*) from conversations where created_at >= t_start and created_at < t_end),
           'new_users', (select count(*) from profiles where created_at >= t_start and created_at < t_end),
           'new_listings', (select count(*) from properties where not is_demo and created_at >= t_start and created_at < t_end)
         ) order by t_start)
    into v_series from buckets;

  v_totals := jsonb_build_object(
    'visits',        (select coalesce(sum(visits), 0) from traffic_hourly where hour >= v_from and hour < v_to),
    'visitors_avg',  (select coalesce(round(avg(visitors)), 0) from traffic_daily where day between v_from_day and v_today),
    'visitors_today',(select coalesce(visitors, 0) from traffic_daily where day = v_today),
    'new_users',     (select count(*) from profiles where created_at >= v_from and created_at < v_to),
    'new_listings',  (select count(*) from properties where not is_demo and created_at >= v_from and created_at < v_to),
    'phone_views',   (select count(*) from phone_reveals where created_at >= v_from and created_at < v_to),
    'new_chats',     (select count(*) from conversations where created_at >= v_from and created_at < v_to),
    'ad_views',      (select coalesce(sum(views), 0) from ad_stats where day between v_from_day and v_today),
    'ad_clicks',     (select coalesce(sum(clicks), 0) from ad_stats where day between v_from_day and v_today),
    'promo_views',   (select coalesce(sum(views), 0) from campaign_stats where day between v_from_day and v_today),
    'promo_clicks',  (select coalesce(sum(clicks), 0) from campaign_stats where day between v_from_day and v_today),
    'reports',       (select count(*) from listing_reports where created_at >= v_from and created_at < v_to),
    'bans',          (select count(*) from profiles where banned_at >= v_from and banned_at < v_to),
    'active_listings', (select count(*) from properties where status = 'active'),
    'users_total',   (select count(*) from profiles)
  );

  return jsonb_build_object(
    'period', case when v_hourly then 'day' else p_period end,
    'from', v_from_day, 'to', v_today,
    'totals', v_totals,
    'series', coalesce(v_series, '[]'::jsonb),
    'top_areas', coalesce((select jsonb_agg(x) from (
        select coalesce(ar.name, s.value) as name, sum(s.n)::int as n from search_stats s
          left join areas ar on ar.id::text = s.value
         where s.dim = 'area' and s.day between v_from_day and v_today
         group by coalesce(ar.name, s.value) order by sum(s.n) desc limit 8) x), '[]'::jsonb),
    'top_filters', coalesce((select jsonb_agg(x) from (
        select s.dim, s.value, sum(s.n)::int as n from search_stats s
         where s.dim not in ('area', 'query', 'city') and s.day between v_from_day and v_today
         group by s.dim, s.value order by sum(s.n) desc limit 12) x), '[]'::jsonb)
  );
end $$;

-- счётчики кабинета: + уровень и оценки помощи
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
    'otp_test_mode', coalesce((select value from app_settings where key = 'otp_test_mode'), 'true') = 'true',
    'require_licence', coalesce((select value from app_settings where key = 'require_licence_to_publish'), 'false') = 'true',
    'help_unhelpful', (select count(*) from help_votes where helpful = false and created_at > now() - interval '7 days'),
    'is_owner', public.is_owner()
  );
end $$;

-- =====================================================================
-- 4. ПЕРВЫЕ СТАТЬИ ПОМОЩИ (повторный запуск их не дублирует и не перезаписывает)
-- =====================================================================
insert into public.help_articles (id, category, title, body, sort, web_only) values
  ('e2bf5b54-9919-58d0-9461-2de87c71309d', 'account', 'Signing in and confirmation codes',
   'You sign in to Zumi with your email and password.

## Confirming your phone
To see phone numbers in listings, and to get the "Phone confirmed" mark, confirm your own phone once:
- Open Profile → Settings → Phone & verification.
- Choose WhatsApp or SMS and enter your number with the country code, e.g. +260 97 123 4567.
- Type the 6-digit code you receive. It works for 10 minutes.

You can also confirm your email with a code, but only a WhatsApp or SMS code gives the "Phone confirmed" mark.

## Good to know
- One phone number can be confirmed on only one Zumi account.
- If you change your number in the profile, you need to confirm the new one.
- Forgot your password? On the sign-in screen tap "Forgot password?" — we send a code to your email.',
   10, false),
  ('ad9879b4-2ae6-5057-8ebb-2bbb2ce2ff58', 'account', 'I did not get a confirmation code',
   'Most codes arrive within a minute. If yours did not:
- Check that the number starts with the country code (+260 for Zambia) and has no mistakes.
- For WhatsApp: make sure WhatsApp is installed and active on this number.
- For SMS: check that your phone has signal and the inbox is not full.
- Wait one minute, then tap "Change number, method or resend code" and send a new code.

For safety you can request up to 5 codes per hour and try a code up to 5 times. If you reach the limit, wait an hour.

Still nothing? Write to us in Help → Contact support and tell us the number and the channel (WhatsApp or SMS).',
   20, false),
  ('b33e4063-ac2c-58a5-9255-2ec89a350c92', 'account', 'How to delete my account',
   'You can delete your account at any time:
- Open Profile → Settings → Delete my account.
- Type DELETE to confirm.

This deletes your profile, listings, photos and chats. Records of payments may be kept without your name where the law requires it. Deleting cannot be undone — if you only want a break, you can archive your listings instead.',
   30, false),
  ('e2232f2d-41f2-569a-a8f0-f3ebc63e88b5', 'listings', 'How to post a listing',
   'Tap "Post" on the home screen (or "Post a listing" on the website) and follow the steps:
- Choose rent or sale and the type of property.
- Add a clear title, the price and the main details (bedrooms, bathrooms, size).
- Put the pin exactly on the property on the map.
- Add good photos: daylight, every room, the outside and the street. Listings with 5+ photos get many more messages.
- Check the preview and publish.

## Tips
- Write the real price. Listings with "price on request" get fewer calls.
- Do not put phone numbers or links inside photos or the description — use the contact settings instead.
- Confirm "still available" every 60 days, otherwise the listing is hidden from search.',
   10, false),
  ('8e7d414f-d7f6-5b5a-aa35-b1190d136b1b', 'listings', 'Why is my listing under review?',
   'The first 2 listings of every new person are checked by the Zumi team before they appear in search. This keeps fake listings away from buyers and tenants.

The check usually takes less than a day. You will see the status in Profile → My listings:
- "Under review" — waiting for the team.
- "Not approved" — the reason is shown. Fix it and tap "Send for review again".

After 2 approved listings, your new listings go live right away.',
   20, false),
  ('ce7fd462-5a6c-59d9-be2a-337af0146f09', 'listings', 'Why is my listing hidden from search?',
   'A listing is hidden from search when:
- It was not confirmed as "still available" for 60 days. Open Profile → My listings, tap ⋯ → "Confirm still available".
- It is waiting for review or was not approved (see "Why is my listing under review?").
- People reported it and the team is checking it.
- You archived it or marked it as rented or sold.

You can always see your own listings in Profile → My listings, whatever their status.',
   30, false),
  ('08de150a-c4e6-5fbc-8d43-3c77fae76f95', 'contact', 'Why can''t I see the phone number?',
   'To protect agents and owners from spam and scammers, phone numbers are not shown to everyone.

To see a number:
- Sign in to Zumi.
- Confirm your own phone with a WhatsApp or SMS code (it takes a minute).
- Tap "Show number" or "WhatsApp" on the listing.

You can see up to 15 numbers a day. Every view is recorded, so bots and spammers can be blocked.

If there is no "Show number" button, the author chose "Chat only" — send a message in Zumi chat instead.',
   10, false),
  ('1327cf06-e22d-54f0-9536-b8668049f1be', 'contact', 'Chat only: hiding my phone number',
   'If you do not want to receive calls, choose "Chat only":
- Open Profile → Settings → How people contact you.
- Select "Chat only".

Your number will not be shown on any of your listings or on your agent page. People write to you in Zumi chat, and you get a notification for every new message. You can switch back at any time.',
   20, false),
  ('f131b212-3739-54b4-8711-d0657f8640a7', 'verification', 'How to get the Verified badge',
   'The Verified badge shows that Zumi checked who you are. Listings with the badge get more trust and more messages.

Steps (about 3 minutes):
- Confirm your phone with a WhatsApp or SMS code.
- Take a photo of your NRC or passport and a selfie.
- Agents also add their ZIEA registration number.

The Zumi team checks the documents, usually within the same day. As soon as the team approves or rejects the check, the photos of your documents and selfie are deleted. We keep only the result.

If there is no decision within 30 days, the photos are deleted and you need to send them again.',
   10, false),
  ('a44d1cea-2bb5-5fdc-81f2-6aea36e74198', 'verification', 'ZIEA licence for agents',
   'Estate agents in Zambia are registered with the Zambia Institute of Estate Agents (ZIEA). Zumi checks your registration number with the register.

- Add the number when you sign up as an agent, or later in Profile → Get verified.
- Until it is checked, your listings and agent page show "ZIEA licence not verified".
- Promotion of listings is available only to agents with a checked licence.

If your number was not approved, the reason is shown in Get verified. Check the number and send it again.',
   20, false),
  ('4f3404db-0d48-5bab-bdf2-af48ecc8e760', 'promotion', 'How promotion works',
   'Agents with a checked ZIEA licence can promote their listings:
- "Top of search results" — your listing is shown first in the list.
- "Featured on the home page" — your listing appears in the Featured row.

Open Profile → Promotion → New campaign, choose a listing, the place and the dates. The campaign starts and ends by itself. You can pause or stop it at any time and see views, clicks, calls and messages.

If you add your own picture, name or website link, the Zumi team checks the campaign first (usually within a day). A campaign with a photo from the listing and your own name starts right away.',
   10, false),
  ('92e9e1e2-0b00-5793-ac95-3fc27a6d1090', 'safety', 'How to spot a scam',
   'Most people on Zumi are honest, but be careful. Warning signs:
- The price is much lower than similar homes in the area.
- The person asks for a deposit or "booking fee" before you see the property.
- They say they are abroad and will send the keys after payment.
- They push you to decide today or to pay by mobile money to a private number.
- They refuse a video call or a viewing.

## Stay safe
- Never pay before you have seen the property and the documents.
- Meet in daylight and bring someone with you.
- Prefer listings with the Verified badge and photos taken on site.
- Keep the conversation in Zumi chat — it helps us if something goes wrong.

If something feels wrong, report the listing. It takes 10 seconds.',
   10, false),
  ('5f6f67c6-529b-5862-9ff4-bca216e0806c', 'safety', 'How to report a listing or a person',
   '- Open the listing and tap "Report this listing" at the bottom.
- Choose the reason (scam, wrong price, already rented, fake photos…) and add details if you can.

The Zumi team checks every report, scam reports first. A listing reported by several people with confirmed phones is hidden automatically until the team checks it.

You can also report a review, and contact support from Help → Contact support. We do not tell the author who reported them.',
   20, false),
  ('e9048006-4de9-53bc-9049-4d6fa4b6a2e8', 'technical', 'The app is slow or photos do not load',
   'Try these steps:
- Check your internet connection. Photos need more data than text.
- Pull down on the list to refresh.
- Close the app (or browser tab) and open it again.
- Update the app or, on the website, refresh the page.
- Free some space on your phone if it is almost full.

If it still does not work, write to us in Help → Contact support. Tell us your phone model and what you were doing — a screenshot helps a lot.',
   10, false)
on conflict (id) do nothing;
