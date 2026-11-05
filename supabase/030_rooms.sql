-- =====================================================================
--  Zumi — 030: раздел «Rooms & budget» (комнаты, boys' quarters, bedsitters, хостелы)
--  • Тип объявления 'room' + room_info: вид жилья, ванная, кухня, вода, свет, забор.
--  • Отдельная лента: в обычном поиске и на главной комнат нет — только в своём разделе.
--  • Точное место комнаты не показывается (только примерно, ~1 км) — кроме автора и команды.
--  • «Ещё сдаётся?» для комнат — через 14 дней, без ответа скрывается через 21.
--  • Выключатель rooms_enabled (по умолчанию OFF): пока выключен, раздел видит только команда.
--  Запускать после 029. Можно запускать повторно.
-- =====================================================================

insert into public.app_settings (key, value) values ('rooms_enabled', 'false') on conflict (key) do nothing;

create or replace function public.rooms_on()
returns boolean language sql stable security definer set search_path = public, extensions as $$
  select coalesce((select value from app_settings where key = 'rooms_enabled'), 'false') = 'true';
$$;
grant execute on function public.rooms_on() to anon, authenticated;

create or replace function public.app_flags()
returns jsonb language sql stable security definer set search_path = public, extensions as $$
  select jsonb_build_object('promotion', public.promotion_on(), 'ads', public.ads_on(),
                            'wa_verify', public._wa_verify_number(), 'billing', public.billing_on(),
                            'rooms', public.rooms_on());
$$;
grant execute on function public.app_flags() to anon, authenticated;

-- ---------- данные комнаты ----------
create or replace function public._room_info_ok(r jsonb)
returns boolean language sql immutable as $$
  select r is null or (
    jsonb_typeof(r) = 'object'
    and (select bool_and(k in ('kind', 'bathroom', 'kitchen', 'water', 'power', 'wall')) from jsonb_object_keys(r) k)
    and coalesce(r->>'kind', 'room') in ('room', 'boys_quarters', 'bedsitter', 'shared', 'hostel')
    and coalesce(r->>'bathroom', 'own') in ('own', 'shared')
    and coalesce(r->>'kitchen', 'own') in ('own', 'shared', 'none')
    and coalesce(r->>'water', 'council') in ('borehole', 'council', 'tank', 'none')
    and coalesce(r->>'power', 'own_prepaid') in ('own_prepaid', 'shared', 'none')
    and (r->'wall' is null or jsonb_typeof(r->'wall') = 'boolean')
  );
$$;

alter table public.properties add column if not exists room_info jsonb;
alter table public.properties drop constraint if exists properties_room_info_ok;
alter table public.properties add constraint properties_room_info_ok check (public._room_info_ok(room_info));

-- пока раздел выключен, комнату может разместить только команда (для проверки, как всё выглядит)
create or replace function public.rooms_switch()
returns trigger language plpgsql security definer set search_path = public, extensions as $$
begin
  if new.property_type = 'room' and not public.rooms_on() and not public.is_admin()
     and auth.uid() is not null and not new.is_demo
     and (tg_op = 'INSERT' or old.property_type is distinct from 'room') then
    raise exception 'ROOMS_OFF';
  end if;
  if new.property_type = 'room' then
    new.deal_type := 'rent';                 -- комнаты только в аренду
  else
    new.room_info := null;
  end if;
  return new;
end $$;
drop trigger if exists rooms_switch on public.properties;
create trigger rooms_switch before insert or update of property_type, room_info on public.properties
  for each row execute function public.rooms_switch();

-- ---------- лента ----------
create or replace view public.property_feed as
  select p.id, p.owner_id, p.title, p.description, p.deal_type, p.property_type, p.price, p.currency,
         p.rent_period, p.bedrooms, p.bathrooms, p.area_sqm, p.plot_sqm, p.furnished, p.amenities,
         p.area_id, p.address,
         -- комната: точное место видят только автор и команда, остальным — примерно (~1 км)
         case when p.property_type = 'room' and not coalesce(p.owner_id = auth.uid(), false) and not public.is_admin()
              then st_snaptogrid(p.location::geometry, 0.01)::geography else p.location end as location,
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
         p.room_info
    from properties p
    left join areas a     on a.id  = p.area_id
    left join profiles pr on pr.id = p.owner_id
   where (p.status = 'active' and (p.property_type <> 'room' or public.rooms_on()))
      or p.owner_id = auth.uid() or public.is_admin();
grant select on public.property_feed to anon, authenticated;

-- статистика районов (средняя аренда и т. п.) — без комнат, чтобы не путать цены
create or replace view public.area_stats as
  select a.id, a.city, a.name,
         st_y(a.center::geometry) as lat, st_x(a.center::geometry) as lng,
         count(p.id) filter (where p.deal_type = 'sale') as for_sale,
         count(p.id) filter (where p.deal_type = 'rent') as for_rent,
         round(avg(p.price) filter (where p.deal_type = 'rent' and p.currency = 'ZMW')) as avg_rent_zmw,
         count(p.id) as listings_count
    from areas a
    left join properties p on p.area_id = a.id and p.status = 'active' and p.property_type <> 'room'
         and (p.is_demo or coalesce(p.confirmed_at, p.created_at) > now() - interval '60 days')
   group by a.id;
grant select on public.area_stats to anon, authenticated;

-- «ещё сдаётся?»: комнаты спрашиваем через 14 дней
create or replace function public.my_listings_to_confirm()
returns int language sql stable security definer set search_path = public, extensions as $$
  select count(*)::int from properties
   where owner_id = auth.uid() and status = 'active' and not is_demo
     and coalesce(confirmed_at, approved_at, created_at)
         < now() - case when property_type = 'room' then interval '14 days' else interval '30 days' end;
$$;

-- выключатель — только владелец
create or replace function public.admin_set_setting(p_key text, p_value text)
returns void language plpgsql security definer set search_path = public, extensions as $$
begin
  if not public.is_admin() then raise exception 'NOT_ADMIN'; end if;
  if p_key not in ('otp_test_mode', 'require_licence_to_publish', 'promotion_enabled', 'ads_enabled',
                   'billing_enabled', 'manual_payment_info', 'payment_mode', 'rooms_enabled') then
    raise exception 'BAD_SETTING';
  end if;
  if p_key in ('promotion_enabled', 'ads_enabled', 'billing_enabled', 'manual_payment_info', 'payment_mode',
               'rooms_enabled')
     and not public.is_owner() then
    raise exception 'OWNER_ONLY';
  end if;
  if p_key = 'manual_payment_info' then
    if length(p_value) > 500 then raise exception 'TOO_LONG'; end if;
  elsif p_key = 'payment_mode' then
    if p_value not in ('manual', 'auto') then raise exception 'BAD_SETTING'; end if;
  elsif p_value not in ('true', 'false') then
    raise exception 'BAD_SETTING';
  end if;
  insert into app_settings (key, value) values (p_key, p_value)
  on conflict (key) do update set value = excluded.value;
  perform public._audit('setting', 'settings', p_key, left(p_value, 100));
end $$;

-- ---------- районы: compounds, где больше всего комнат ----------
alter table public.areas add column if not exists kind text not null default 'suburb';
alter table public.areas drop constraint if exists areas_kind_check;
alter table public.areas add constraint areas_kind_check check (kind in ('suburb', 'compound'));
insert into public.areas (city, name, center, kind)
select 'Lusaka', v.name, st_point(v.lng, v.lat)::geography, 'compound'
  from (values
    ('Kalingalinga', 28.3290, -15.4080), ('Mtendere', 28.3500, -15.4170), ('Bauleni', 28.3560, -15.4440),
    ('Chilenje', 28.3030, -15.4430), ('Kabwata', 28.2960, -15.4300), ('Matero', 28.2420, -15.3830),
    ('Chawama', 28.2780, -15.4560), ('Kanyama', 28.2400, -15.4330), ('Garden', 28.2700, -15.3880),
    ('George', 28.2500, -15.4000)
  ) as v(name, lng, lat)
 where not exists (select 1 from public.areas a where a.city = 'Lusaka' and a.name = v.name);

-- ---------- демо-комнаты: чтобы команда увидела раздел, пока он выключен (удалятся вместе с демо) ----------
insert into public.properties (id, title, description, deal_type, property_type, price, currency, rent_period,
                               bedrooms, bathrooms, area_id, location, status, listed_by, contact_name,
                               is_demo, created_at, room_info)
select v.id::uuid, v.title, v.descr, 'rent', 'room', v.price, 'ZMW', 'month', v.beds, null,
       (select id from areas where city = 'Lusaka' and name = v.area), st_point(v.lng, v.lat)::geography,
       'active', 'owner', 'Demo landlord', true, now() - (v.age || ' days')::interval, v.info::jsonb
  from (values
    ('00000000-0000-0000-0000-0000000000a1', 'Self-contained room with own toilet',
     'Clean room in a walled yard. Own toilet and shower, shared kitchen. Borehole water, own ZESCO prepaid meter. 5 minutes to the bus stop.',
     1200, 1, 'Kalingalinga', 28.3291, -15.4086, 2,
     '{"kind":"room","bathroom":"own","kitchen":"shared","water":"borehole","power":"own_prepaid","wall":true}'),
    ('00000000-0000-0000-0000-0000000000a2', 'Boys'' quarters for a single person',
     'Small cottage behind the main house. Own entrance, own bathroom. Water from council, shared electricity.',
     1800, 1, 'Kabwata', 28.2965, -15.4306, 5,
     '{"kind":"boys_quarters","bathroom":"own","kitchen":"own","water":"council","power":"shared","wall":true}'),
    ('00000000-0000-0000-0000-0000000000a3', 'Bedsitter near the main road',
     'One room with a small kitchen corner and own bathroom. Tiled floor, security bars. Close to shops and minibuses.',
     2300, 1, 'Mtendere', 28.3507, -15.4175, 1,
     '{"kind":"bedsitter","bathroom":"own","kitchen":"own","water":"tank","power":"own_prepaid","wall":false}'),
    ('00000000-0000-0000-0000-0000000000a4', 'Student bed space near UNZA',
     'Shared room for two students, ten minutes'' walk to UNZA. Shared kitchen and bathroom, water and electricity included.',
     650, 1, 'Kalingalinga', 28.3285, -15.4070, 3,
     '{"kind":"hostel","bathroom":"shared","kitchen":"shared","water":"borehole","power":"shared","wall":true}')
  ) as v(id, title, descr, price, beds, area, lng, lat, age, info)
on conflict (id) do nothing;

-- статья помощи для раздела
insert into public.help_articles (id, category, title, body, sort)
values ('7a1d2c3e-4b5f-4a6b-9c7d-8e9f0a1b2c3d', 'safety', 'Renting a room safely',
'Rooms, boys'' quarters and bedsitters are in their own section: Rooms & budget.

## Never pay to view a room
Nobody on Zumi may ask you for money to see a room — not before, not during and not after the viewing. If someone asks, don''t pay and report the listing.

## Before you pay rent or a deposit
- Go and see the room in person, in daylight.
- Meet the landlord, not only a "broker".
- Ask about water, electricity (own ZESCO prepaid meter or shared) and the bathroom.
- Get a written receipt for any money you pay.

## Why the map shows only the area
To protect landlords and tenants, the exact place of a room is shown only after you talk to the owner.', 15)
on conflict (id) do nothing;
