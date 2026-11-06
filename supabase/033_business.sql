-- =====================================================================
--  Zumi — 033: бизнес-модель, часть 1
--  • Тариф арендодателя (только для собственников): до 10 объявлений, K75 в месяц.
--  • Тарифы на 3 и 6 месяцев со скидкой (Pro, Agency, Landlord) — меньше ручных платежей.
--  • «Дом на несколько квартир»: одно объявление, «свободно 2 из 6» (units_total / units_available).
--  • Жалоба «агент выдаёт себя за собственника» + список подозрительных «собственников» для команды.
--  • Письмо-напоминание за 5 дней до конца тарифа.
--  Пока оплата выключена, всё это видит только команда. Запускать после 032. Можно запускать повторно.
-- =====================================================================

-- ---------- тариф арендодателя ----------
alter table public.price_list drop constraint if exists price_list_plan_check;
alter table public.price_list add constraint price_list_plan_check check (plan in ('pro', 'agency', 'landlord'));
alter table public.plan_limits drop constraint if exists plan_limits_plan_check;
alter table public.plan_limits add constraint plan_limits_plan_check check (plan in ('pro', 'agency', 'landlord'));
alter table public.profiles drop constraint if exists profiles_plan_check;
alter table public.profiles add constraint profiles_plan_check check (plan in ('pro', 'agency', 'landlord'));
alter table public.price_list add column if not exists owners_only boolean not null default false;

insert into public.plan_limits values ('landlord', 10) on conflict (plan) do update set listings = excluded.listings;

-- скидки: 3 мес. −10%, 6 мес. −15%, 12 мес. −17% (2 месяца в подарок)
insert into public.price_list (code, kind, title, description, amount, days, quantity, plan, agents_only, owners_only, sort) values
  ('plan_landlord_m', 'plan', 'Landlord — 1 month',  'Up to 10 listings for your own properties. 1 boost included.', 75, 30, 1, 'landlord', false, true, 64),
  ('plan_landlord_3m','plan', 'Landlord — 3 months', 'Up to 10 listings. Save 10%. 3 boosts included.', 200, 91, 3, 'landlord', false, true, 65),
  ('plan_landlord_6m','plan', 'Landlord — 6 months', 'Up to 10 listings. Save 15%. 6 boosts included.', 380, 182, 6, 'landlord', false, true, 66),
  ('plan_landlord_y', 'plan', 'Landlord — 12 months','Up to 10 listings for a year — 2 months free. 12 boosts included.', 750, 365, 12, 'landlord', false, true, 67),
  ('plan_pro_3m',     'plan', 'Pro — 3 months',      'Pro for 3 months. Save 10%. 6 boosts included.', 675, 91, 6, 'pro', true, false, 72),
  ('plan_pro_6m',     'plan', 'Pro — 6 months',      'Pro for 6 months. Save 15%. 12 boosts included.', 1275, 182, 12, 'pro', true, false, 74),
  ('plan_agency_3m',  'plan', 'Agency — 3 months',   'Agency for 3 months. Save 10%. 24 boosts included.', 2025, 91, 24, 'agency', true, false, 92),
  ('plan_agency_6m',  'plan', 'Agency — 6 months',   'Agency for 6 months. Save 15%. 48 boosts included.', 3825, 182, 48, 'agency', true, false, 94)
on conflict (code) do nothing;

-- заказ: тариф арендодателя — только собственникам, агентские — только агентам
create or replace function public.create_order(p_item text, p_property uuid default null, p_phone text default null)
returns jsonb language plpgsql security definer set search_path = public, extensions as $$
declare
  uid uuid := auth.uid();
  it price_list;
  v_role text;
  o orders;
begin
  if uid is null then raise exception 'AUTH'; end if;
  if not public.billing_on() and not public.is_owner() then raise exception 'BILLING_OFF'; end if;
  if exists (select 1 from profiles where id = uid and banned_at is not null) then raise exception 'ACCOUNT_BLOCKED'; end if;
  select * into it from price_list where code = p_item and active;
  if it is null then raise exception 'BAD_ITEM'; end if;
  select role into v_role from profiles where id = uid;
  if it.agents_only and v_role not in ('agent', 'admin') then raise exception 'AGENTS_ONLY'; end if;
  if it.owners_only and v_role not in ('owner', 'admin') then raise exception 'OWNERS_ONLY'; end if;
  if it.kind in ('boost', 'featured') then
    if p_property is null or not exists (select 1 from properties where id = p_property and owner_id = uid and status = 'active') then
      raise exception 'NOT_YOUR_LISTING';
    end if;
  end if;
  if p_phone is not null and length(public._norm_phone(p_phone)) < 9 then raise exception 'BAD_PHONE'; end if;
  if (select count(*) from orders where user_id = uid and status = 'pending') >= 5 then raise exception 'TOO_MANY_ORDERS'; end if;
  insert into orders (ref, user_id, item_code, property_id, amount, currency, pay_phone, provider)
  values (public._order_ref(), uid, it.code, case when it.kind in ('boost', 'featured') then p_property end,
          it.amount, it.currency, nullif(trim(coalesce(p_phone, '')), ''),
          coalesce(nullif((select value from app_settings where key = 'payment_mode'), ''), 'manual'))
  returning * into o;
  return jsonb_build_object(
    'id', o.id, 'ref', o.ref, 'amount', o.amount, 'currency', o.currency, 'status', o.status,
    'mode', o.provider,
    'payment_info', (select value from app_settings where key = 'manual_payment_info'));
end $$;
revoke execute on function public.create_order(text, uuid, text) from public, anon;
grant execute on function public.create_order(text, uuid, text) to authenticated;

-- ---------- «дом на несколько квартир» ----------
alter table public.properties add column if not exists units_total int;
alter table public.properties add column if not exists units_available int;
alter table public.properties drop constraint if exists properties_units_ok;
alter table public.properties add constraint properties_units_ok check (
  (units_total is null and units_available is null)
  or (units_total between 2 and 200 and units_available between 1 and units_total));

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
            now() - case when p.property_type = 'room' then interval '21 days' else interval '37 days' end) as is_fresh,
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
         p.units_total, p.units_available
    from properties p
    left join areas a     on a.id  = p.area_id
    left join profiles pr on pr.id = p.owner_id
   where (p.status = 'active' and (p.property_type <> 'room' or public.rooms_on()))
      or p.owner_id = auth.uid() or public.is_admin();
grant select on public.property_feed to anon, authenticated;

-- ---------- жалоба «агент выдаёт себя за собственника» ----------
alter table public.listing_reports drop constraint if exists listing_reports_reason_check;
alter table public.listing_reports add constraint listing_reports_reason_check check (reason in
  ('scam', 'asked_prepayment', 'not_available', 'wrong_info', 'duplicate', 'agent_as_owner', 'other'));

-- подозрительные «собственники»: объекты в 3+ районах, или 4+ активных объявления, или жалобы «это агент»
create or replace function public.admin_suspect_owners()
returns table (user_id uuid, full_name text, phone text, active_listings int, areas int, agent_reports int, plan text)
language sql stable security definer set search_path = public, extensions as $$
  select pr.id, pr.full_name, pr.phone,
         count(p.id) filter (where p.status = 'active')::int,
         count(distinct p.area_id) filter (where p.status = 'active')::int,
         (select count(*) from listing_reports r join properties q on q.id = r.property_id
           where q.owner_id = pr.id and r.reason = 'agent_as_owner' and r.status = 'new')::int,
         pr.plan
    from profiles pr
    join properties p on p.owner_id = pr.id and not p.is_demo
   where public.is_admin() and pr.role = 'owner' and pr.banned_at is null
   group by pr.id
  having count(distinct p.area_id) filter (where p.status = 'active') >= 3
      or count(p.id) filter (where p.status = 'active') >= 4
      or (select count(*) from listing_reports r join properties q on q.id = r.property_id
           where q.owner_id = pr.id and r.reason = 'agent_as_owner' and r.status = 'new') > 0
   order by 6 desc, 5 desc, 4 desc
   limit 100;
$$;
revoke execute on function public.admin_suspect_owners() from public, anon;
grant execute on function public.admin_suspect_owners() to authenticated;

-- ---------- письмо за 5 дней до конца тарифа ----------
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
  -- 5. тариф заканчивается через 5 дней или меньше — одно напоминание на срок
  plan_end as (
    select p.id, 'plan_ending'::text, p.id, 5,
           jsonb_build_object('plan', p.plan, 'until', to_char(p.plan_until, 'DD Mon YYYY'),
                              'days', greatest(1, ceil(extract(epoch from p.plan_until - now()) / 86400)::int))
      from profiles p
     where p.plan is not null and p.plan_until > now() and p.plan_until < now() + interval '5 days'
       and not exists (select 1 from email_log l
                        where l.user_id = p.id and l.kind = 'plan_ending' and l.ref_id = p.id
                          and l.sent_at > p.plan_until - interval '6 days')
  ),
  allx as (
    select * from chat union all select * from support union all select * from approved
    union all select * from not_approved union all select * from confirm union all select * from plan_end
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

-- проверка: всё должно быть true
select
  (select count(*) from price_list where code like 'plan_%') = 12 as prices_ok,
  exists (select 1 from plan_limits where plan = 'landlord' and listings = 10) as landlord_ok,
  exists (select 1 from information_schema.columns where table_name = 'property_feed' and column_name = 'units_available') as units_ok;
