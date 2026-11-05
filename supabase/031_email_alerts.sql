-- =====================================================================
--  Zumi — 031: письма-уведомления (email alerts)
--  • Новое сообщение в чате, которое не прочитали 10 минут → одно письмо на переписку
--    (следующее — только после того, как человек её откроет).
--  • Ответ поддержки → письмо.
--  • Объявление одобрено / не одобрено модератором → письмо.
--  • «Still available?» — пора подтвердить объявление → одно письмо.
--  Отправляет функция email-notify (Supabase → Edge Functions), её раз в 10 минут
--  будит pg_cron. Пока функция не создана — ничего не происходит, ошибок нет.
--  Человек может выключить письма в Settings или по ссылке в письме.
--  Запускать после 030. Можно запускать повторно.
-- =====================================================================

-- ---------- настройки ----------
insert into public.app_settings (key, value) values
  ('site_url', 'https://sashavaimer23.github.io/zumi-app-test'),
  ('functions_url', 'https://gkfymizapojpxbwjurdv.supabase.co/functions/v1'),
  ('email_cron_secret', replace(gen_random_uuid()::text, '-', '') || replace(gen_random_uuid()::text, '-', ''))
on conflict (key) do nothing;

-- выключил письма: время (null = письма приходят)
alter table public.profiles add column if not exists email_alerts_off_at timestamptz;

-- ---------- журнал отправленного ----------
create table if not exists public.email_log (
  id       bigserial primary key,
  user_id  uuid not null references public.profiles(id) on delete cascade,
  kind     text not null,          -- chat | support | approved | not_approved | confirm
  ref_id   uuid not null,          -- переписка / обращение / объявление
  sent_at  timestamptz not null default now(),
  ok       boolean not null default true,
  error    text
);
create index if not exists email_log_key_idx on public.email_log (user_id, kind, ref_id, sent_at);
alter table public.email_log enable row level security;   -- только сервер

-- ссылка «отписаться» в письме: подпись, которую нельзя подделать без секрета
create or replace function public._email_token(uid uuid)
returns text language sql stable security definer set search_path = public, extensions as $$
  select md5(uid::text || ':' || (select value from app_settings where key = 'email_cron_secret'));
$$;
revoke execute on function public._email_token(uuid) from public, anon, authenticated;

-- ---------- что пора отправить ----------
create or replace function public.email_due(p_limit int default 40)
returns jsonb language plpgsql security definer set search_path = public, extensions as $$
declare
  v jsonb;
begin
  insert into app_settings (key, value) values ('email_last_run', now()::text)
  on conflict (key) do update set value = excluded.value;
  delete from email_log where sent_at < now() - interval '90 days';

  with people as (
    select p.id, u.email,
           coalesce(nullif(trim(p.full_name), ''), 'there') as name
      from profiles p
      join auth.users u on u.id = p.id
     where p.email_alerts_off_at is null
       and p.banned_at is null
       and u.email is not null
       and u.email_confirmed_at is not null
  ),
  -- 1. непрочитанные сообщения (старше 10 минут, за последние 2 дня)
  chat as (
    select v.uid as user_id, 'chat'::text as kind, c.id as ref_id, 1 as prio,
           jsonb_build_object(
             'from', coalesce(nullif(trim(case when s.role = 'agent' and coalesce(s.agency_name, '') <> ''
                                              then s.agency_name else s.full_name end), ''), 'Someone'),
             'title', coalesce(pr.title, 'your listing'),
             'count', (select count(*) from messages m
                        where m.conversation_id = c.id and m.sender_id = v.other
                          and m.created_at > coalesce(cr.read_at, '-infinity')),
             'snippet', (select left(m.body, 160) from messages m
                          where m.conversation_id = c.id and m.sender_id = v.other
                          order by m.created_at desc limit 1)) as data
      from conversations c
      cross join lateral (values (c.buyer_id, c.seller_id), (c.seller_id, c.buyer_id)) v(uid, other)
      left join chat_reads cr on cr.conversation_id = c.id and cr.user_id = v.uid
      left join profiles s on s.id = v.other
      left join properties pr on pr.id = c.property_id
     where c.last_message_at > now() - interval '2 days'
       and exists (select 1 from messages m
                    where m.conversation_id = c.id and m.sender_id = v.other
                      and m.created_at > coalesce(cr.read_at, '-infinity')
                      and m.created_at > now() - interval '2 days'
                      and m.created_at < now() - interval '10 minutes')
       and not exists (select 1 from email_log l
                        where l.user_id = v.uid and l.kind = 'chat' and l.ref_id = c.id
                          and l.sent_at > coalesce(cr.read_at, '-infinity'))
  ),
  -- 2. ответ поддержки
  support as (
    select t.user_id, 'support'::text, t.id, 2,
           jsonb_build_object('subject', t.subject, 'snippet', left(sm.body, 160))
      from support_tickets t
      cross join lateral (select body, created_at from support_messages
                           where ticket_id = t.id and is_staff order by created_at desc limit 1) sm
     where sm.created_at > now() - interval '2 days'
       and sm.created_at < now() - interval '3 minutes'
       and not exists (select 1 from email_log l
                        where l.user_id = t.user_id and l.kind = 'support' and l.ref_id = t.id
                          and l.sent_at > sm.created_at)
  ),
  -- 3. модерация: одобрено (только то, что ждало модератора) / не одобрено
  approved as (
    select p.owner_id, 'approved'::text, p.id, 3,
           jsonb_build_object('title', p.title, 'listing_id', p.id)
      from properties p
     where p.owner_id is not null and not p.is_demo and p.status = 'active'
       and p.approved_at > now() - interval '2 days'
       and p.approved_at > p.created_at + interval '5 minutes'
       and not exists (select 1 from email_log l
                        where l.user_id = p.owner_id and l.kind = 'approved' and l.ref_id = p.id)
  ),
  not_approved as (
    select p.owner_id, 'not_approved'::text, p.id, 3,
           jsonb_build_object('title', p.title, 'note', p.moderation_note)
      from properties p
     where p.owner_id is not null and not p.is_demo and p.status = 'archived'
       and p.moderation_note is not null
       and coalesce(p.updated_at, p.created_at) > now() - interval '2 days'
       and not exists (select 1 from email_log l
                        where l.user_id = p.owner_id and l.kind = 'not_approved' and l.ref_id = p.id
                          and l.sent_at > coalesce(p.updated_at, p.created_at) - interval '1 minute')
  ),
  -- 4. «Still available?» — пора подтвердить (как в my_listings_to_confirm)
  confirm as (
    select p.owner_id, 'confirm'::text, p.id, 4,
           jsonb_build_object('title', p.title, 'listing_id', p.id,
                              'hide_in', greatest(1, (case when p.property_type = 'room' then 21 else 37 end)
                                - extract(day from now() - coalesce(p.confirmed_at, p.approved_at, p.created_at))::int))
      from properties p
     where p.owner_id is not null and not p.is_demo and p.status = 'active'
       and coalesce(p.confirmed_at, p.approved_at, p.created_at)
           < now() - case when p.property_type = 'room' then interval '14 days' else interval '30 days' end
       and not exists (select 1 from email_log l
                        where l.user_id = p.owner_id and l.kind = 'confirm' and l.ref_id = p.id
                          and l.sent_at > coalesce(p.confirmed_at, p.approved_at, p.created_at))
  ),
  allx as (
    select * from chat union all select * from support union all select * from approved
    union all select * from not_approved union all select * from confirm
  )
  select coalesce(jsonb_agg(x order by x.prio), '[]'::jsonb) into v from (
    select a.user_id, a.kind, a.ref_id, a.prio, a.data, pe.email, pe.name,
           public._email_token(a.user_id) as token
      from allx a join people pe on pe.id = a.user_id
     order by a.prio
     limit greatest(1, least(p_limit, 200))
  ) x;
  return v;
end $$;
revoke execute on function public.email_due(int) from public, anon, authenticated;
grant execute on function public.email_due(int) to service_role;

-- отметить: отправлено (или ошибка — повторно не шлём, чтобы не засыпать человека)
create or replace function public.email_mark(p_user uuid, p_kind text, p_ref uuid, p_ok boolean, p_error text default null)
returns void language sql security definer set search_path = public, extensions as $$
  insert into email_log (user_id, kind, ref_id, ok, error) values (p_user, p_kind, p_ref, p_ok, left(p_error, 300));
$$;
revoke execute on function public.email_mark(uuid, text, uuid, boolean, text) from public, anon, authenticated;
grant execute on function public.email_mark(uuid, text, uuid, boolean, text) to service_role;

-- ссылка «Unsubscribe» в письме
create or replace function public.email_unsubscribe(p_user uuid, p_token text)
returns boolean language plpgsql security definer set search_path = public, extensions as $$
begin
  if p_token is null or p_token <> public._email_token(p_user) then return false; end if;
  update profiles set email_alerts_off_at = coalesce(email_alerts_off_at, now()) where id = p_user;
  return found;
end $$;
revoke execute on function public.email_unsubscribe(uuid, text) from public, anon, authenticated;
grant execute on function public.email_unsubscribe(uuid, text) to service_role;

-- ---------- настройка в приложении ----------
create or replace function public.my_email_alerts()
returns boolean language sql stable security definer set search_path = public, extensions as $$
  select email_alerts_off_at is null from profiles where id = auth.uid();
$$;
revoke execute on function public.my_email_alerts() from public, anon;
grant execute on function public.my_email_alerts() to authenticated;

create or replace function public.set_marketing(p_channel text, p_on boolean)
returns void language plpgsql security definer set search_path = public, extensions as $$
begin
  if auth.uid() is null then raise exception 'AUTH'; end if;
  if p_channel = 'email' then
    update profiles set marketing_email_at = case when p_on then now() end where id = auth.uid();
  elsif p_channel = 'whatsapp' then
    update profiles set marketing_whatsapp_at = case when p_on then now() end where id = auth.uid();
  elsif p_channel = 'alerts' then
    update profiles set email_alerts_off_at = case when p_on then null else now() end where id = auth.uid();
  else
    raise exception 'BAD_CHANNEL';
  end if;
end $$;
revoke execute on function public.set_marketing(text, boolean) from public, anon;
grant execute on function public.set_marketing(text, boolean) to authenticated;

-- для владельца: работает ли рассылка
create or replace function public.admin_email_status()
returns jsonb language sql stable security definer set search_path = public, extensions as $$
  select case when not public.is_admin() then null else jsonb_build_object(
    'last_run', (select value from app_settings where key = 'email_last_run'),
    'sent_24h', (select count(*) from email_log where ok and sent_at > now() - interval '24 hours'),
    'failed_24h', (select count(*) from email_log where not ok and sent_at > now() - interval '24 hours'),
    'last_error', (select error from email_log where not ok order by sent_at desc limit 1),
    'turned_off', (select count(*) from profiles where email_alerts_off_at is not null)
  ) end;
$$;
grant execute on function public.admin_email_status() to authenticated;

-- ---------- будильник: раз в 10 минут зовём функцию email-notify ----------
do $$
begin
  begin
    create extension if not exists pg_net;
  exception when others then
    raise notice 'pg_net not available: %', sqlerrm;
  end;
  if exists (select 1 from pg_extension where extname = 'pg_cron')
     and exists (select 1 from pg_extension where extname = 'pg_net') then
    perform cron.unschedule(jobid) from cron.job where jobname = 'zumi-email';
    perform cron.schedule('zumi-email', '*/10 * * * *', $c$
      select net.http_post(
        url := (select value from public.app_settings where key = 'functions_url') || '/email-notify',
        headers := jsonb_build_object('Content-Type', 'application/json',
                     'x-cron-secret', (select value from public.app_settings where key = 'email_cron_secret')),
        body := '{}'::jsonb)
    $c$);
  end if;
end $$;

-- проверка: всё должно быть true
select
  exists (select 1 from app_settings where key = 'email_cron_secret') as secret_ok,
  exists (select 1 from information_schema.columns where table_name = 'profiles' and column_name = 'email_alerts_off_at') as column_ok,
  exists (select 1 from pg_extension where extname = 'pg_net') as pg_net_ok,
  exists (select 1 from pg_extension where extname = 'pg_cron') as cron_ok;
