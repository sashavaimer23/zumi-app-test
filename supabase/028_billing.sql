-- =====================================================================
--  Zumi — 028: платные функции (готовы, но ВЫКЛЮЧЕНЫ)
--  • Прайс-лист (цены меняет владелец в кабинете): бусты, Featured, доп. места, тарифы Pro / Agency.
--  • Заказы: человек выбирает услугу → заказ «ждёт оплаты» → после оплаты услуга включается сама.
--  • Оплата: пока провайдера нет — «ручная»: человек переводит Mobile Money на номер Zumi
--    с кодом заказа, владелец нажимает «Paid» в кабинете. Когда будет компания и API
--    MTN / Airtel — функция mark_order_paid() вызывается автоматически (Edge Function).
--  • Выключатель billing_enabled (по умолчанию OFF) — пока выключен, купить ничего нельзя.
--  Запускать после 027. Можно запускать повторно.
-- =====================================================================

-- ---------- настройки ----------
insert into public.app_settings (key, value) values
  ('billing_enabled', 'false'),
  ('payment_mode', 'manual'),          -- manual | auto (когда подключим провайдера)
  ('manual_payment_info', '')          -- куда платить вручную, видят покупатели
on conflict (key) do nothing;

create or replace function public.billing_on()
returns boolean language sql stable security definer set search_path = public, extensions as $$
  select coalesce((select value from app_settings where key = 'billing_enabled'), 'false') = 'true';
$$;
grant execute on function public.billing_on() to anon, authenticated;

-- платные функции включают и продвижение (бусты и Featured должны быть видны)
create or replace function public.promotion_on()
returns boolean language sql stable security definer set search_path = public, extensions as $$
  select coalesce((select value from app_settings where key = 'promotion_enabled'), 'false') = 'true'
      or public.billing_on();
$$;

create or replace function public.app_flags()
returns jsonb language sql stable security definer set search_path = public, extensions as $$
  select jsonb_build_object('promotion', public.promotion_on(), 'ads', public.ads_on(),
                            'wa_verify', public._wa_verify_number(), 'billing', public.billing_on());
$$;
grant execute on function public.app_flags() to anon, authenticated;

-- ---------- прайс-лист ----------
create table if not exists public.price_list (
  code        text primary key,
  kind        text not null check (kind in ('boost', 'featured', 'boost_pack', 'slots', 'plan')),
  title       text not null,
  description text not null default '',
  amount      numeric(12,2) not null check (amount >= 0),
  currency    text not null default 'ZMW',
  days        int  not null default 0 check (days >= 0),   -- сколько дней действует
  quantity    int  not null default 1 check (quantity >= 1),-- кредитов / мест
  plan        text check (plan in ('pro', 'agency')),
  agents_only boolean not null default false,
  active      boolean not null default true,
  sort        int not null default 0
);
alter table public.price_list enable row level security;
drop policy if exists "prices readable" on public.price_list;
create policy "prices readable" on public.price_list for select using (true);
grant select on public.price_list to anon, authenticated;

insert into public.price_list (code, kind, title, description, amount, days, quantity, plan, agents_only, sort) values
  ('bump_3d',      'boost',      'Bump to top — 3 days',  'Your listing goes to the top of search results for 3 days.', 25, 3, 1, null, false, 10),
  ('boost_7d',     'boost',      'Boost — 7 days',        'Top of search results for 7 days with a "Promoted" mark.', 60, 7, 1, null, false, 20),
  ('featured_7d',  'featured',   'Featured on home — 7 days', 'Shown in the Featured row on the home page for 7 days.', 120, 7, 1, null, true, 30),
  ('boost_pack5',  'boost_pack', '5 boosts pack',         'Five 7-day boosts to use any time. Save K50.', 250, 0, 5, null, false, 40),
  ('slot_1',       'slots',      '1 extra listing — 30 days', 'Post one more listing above your free limit for 30 days.', 30, 30, 1, null, false, 50),
  ('slot_pack5',   'slots',      '5 extra listings — 30 days', 'Post five more listings for 30 days. Save K30.', 120, 30, 5, null, false, 60),
  ('plan_pro_m',   'plan',       'Pro — 1 month',         '50 listings, 2 boosts every month, Pro badge, full statistics.', 250, 30, 2, 'pro', true, 70),
  ('plan_pro_y',   'plan',       'Pro — 12 months',       'Pro for a year — 2 months free. 24 boosts included.', 2500, 365, 24, 'pro', true, 80),
  ('plan_agency_m','plan',       'Agency — 1 month',      '150 listings, 8 boosts every month, agency page.', 750, 30, 8, 'agency', true, 90),
  ('plan_agency_y','plan',       'Agency — 12 months',    'Agency for a year — 2 months free. 96 boosts included.', 7500, 365, 96, 'agency', true, 100)
on conflict (code) do nothing;

-- тарифы: сколько объявлений даёт тариф
create table if not exists public.plan_limits (
  plan     text primary key check (plan in ('pro', 'agency')),
  listings int not null check (listings > 0)
);
alter table public.plan_limits enable row level security;
drop policy if exists "plan limits readable" on public.plan_limits;
create policy "plan limits readable" on public.plan_limits for select using (true);
grant select on public.plan_limits to anon, authenticated;
insert into public.plan_limits values ('pro', 50), ('agency', 150)
on conflict (plan) do update set listings = excluded.listings;

-- бесплатные лимиты на период запуска: агент с лицензией 25, без лицензии 15, собственник 2
update public.role_limits set free_listings = 15, free_listings_licensed = 25 where role = 'agent';
update public.role_limits set free_listings = 2 where role = 'owner';

-- ---------- что купил человек ----------
alter table public.profiles add column if not exists plan text check (plan in ('pro', 'agency'));
alter table public.profiles add column if not exists plan_until timestamptz;
alter table public.profiles add column if not exists boost_credits int not null default 0 check (boost_credits >= 0);

-- доп. места на время (каждая покупка — своя запись со сроком)
create table if not exists public.listing_slot_grants (
  id       uuid primary key default gen_random_uuid(),
  user_id  uuid not null references public.profiles(id) on delete cascade,
  slots    int not null check (slots > 0),
  ends_at  timestamptz not null,
  order_id uuid
);
alter table public.listing_slot_grants enable row level security;
drop policy if exists "own slot grants" on public.listing_slot_grants;
create policy "own slot grants" on public.listing_slot_grants for select using (user_id = auth.uid() or public.is_admin());
create index if not exists listing_slot_grants_user_idx on public.listing_slot_grants (user_id, ends_at);

-- платные поля из приложения не изменить
create or replace function public.protect_profile_fields()
returns trigger language plpgsql as $$
begin
  if current_user in ('authenticated', 'anon') then
    new.role := old.role;
    new.extra_listing_slots := old.extra_listing_slots;
    new.is_verified := old.is_verified;
    new.banned_at := old.banned_at;
    new.ban_reason := old.ban_reason;
    new.account_reviewed_at := old.account_reviewed_at;
    new.plan := old.plan;
    new.plan_until := old.plan_until;
    new.boost_credits := old.boost_credits;
    new.legal_hold := old.legal_hold;
    if new.agent_licence_no is distinct from old.agent_licence_no then
      new.licence_note := null;
    else
      new.licence_note := old.licence_note;
    end if;
  end if;
  return new;
end $$;

-- лимит объявлений: бесплатный по роли (или тариф, если больше) + купленные места
create or replace function public.listing_quota(uid uuid)
returns table (used int, allowed int) language sql stable security definer
set search_path = public, extensions as $$
  select
    (select count(*)::int from properties
      where owner_id = uid and status in ('active', 'draft', 'pending') and not is_demo),
    (select greatest(
              coalesce(
                case when p.role = 'agent' and p.licence_verified_at is not null
                     then coalesce(rl.free_listings_licensed, rl.free_listings)
                     else rl.free_listings end,
                999999),
              coalesce((select pl.listings from plan_limits pl
                         where pl.plan = p.plan and p.plan_until > now()), 0))
            + p.extra_listing_slots
            + coalesce((select sum(g.slots)::int from listing_slot_grants g
                         where g.user_id = p.id and g.ends_at > now()), 0)
       from profiles p left join role_limits rl on rl.role = p.role
      where p.id = uid);
$$;

-- ---------- заказы ----------
create table if not exists public.orders (
  id           uuid primary key default gen_random_uuid(),
  ref          text unique not null,                    -- короткий код для перевода: Z-4F7K2Q
  user_id      uuid references public.profiles(id) on delete set null,
  item_code    text not null references public.price_list(code),
  property_id  uuid references public.properties(id) on delete set null,
  amount       numeric(12,2) not null,
  currency     text not null default 'ZMW',
  pay_phone    text,
  status       text not null default 'pending'
                 check (status in ('pending', 'paid', 'failed', 'cancelled', 'refunded')),
  provider     text,                                    -- manual | mtn_momo | airtel_money | ...
  provider_ref text,
  note         text,
  created_at   timestamptz not null default now(),
  paid_at      timestamptz,
  fulfilled_at timestamptz,
  fulfil_error text
);
alter table public.orders enable row level security;
drop policy if exists "own orders" on public.orders;
create policy "own orders" on public.orders for select using (user_id = auth.uid());
drop policy if exists "owner reads orders" on public.orders;
create policy "owner reads orders" on public.orders for select using (public.is_owner());
create index if not exists orders_user_idx on public.orders (user_id, created_at desc);
create index if not exists orders_status_idx on public.orders (status, created_at desc);

create or replace function public._order_ref()
returns text language plpgsql as $$
declare v text;
begin
  loop
    v := 'Z-' || upper(substr(md5(gen_random_uuid()::text || clock_timestamp()::text), 1, 6));
    exit when not exists (select 1 from orders where ref = v);
  end loop;
  return v;
end $$;

-- оформить заказ
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

create or replace function public.cancel_order(p_order uuid)
returns void language plpgsql security definer set search_path = public, extensions as $$
begin
  update orders set status = 'cancelled'
   where id = p_order and user_id = auth.uid() and status = 'pending';
end $$;
grant execute on function public.cancel_order(uuid) to authenticated;

-- ---------- выполнить оплаченный заказ ----------
create or replace function public._fulfil_order(p_order uuid)
returns void language plpgsql security definer set search_path = public, extensions as $$
declare
  o orders;
  it price_list;
  v_name text;
begin
  select * into o from orders where id = p_order for update;
  if o is null or o.status <> 'paid' or o.fulfilled_at is not null then return; end if;
  select * into it from price_list where code = o.item_code;
  begin
    if it.kind = 'boost' then
      if o.property_id is null then raise exception 'LISTING_GONE'; end if;
      insert into promotions (property_id, user_id, is_free, ends_at)
      values (o.property_id, o.user_id, false, now() + make_interval(days => it.days));
    elsif it.kind = 'featured' then
      if o.property_id is null then raise exception 'LISTING_GONE'; end if;
      select coalesce(nullif(agency_name, ''), full_name, 'Zumi agent') into v_name from profiles where id = o.user_id;
      perform set_config('zumi.fulfilling', 'on', true);
      insert into campaigns (owner_id, property_id, advertiser, placement, starts_on, ends_on)
      values (o.user_id, o.property_id, left(v_name, 80), 'home_featured', current_date, current_date + it.days - 1);
    elsif it.kind = 'boost_pack' then
      update profiles set boost_credits = boost_credits + it.quantity where id = o.user_id;
    elsif it.kind = 'slots' then
      insert into listing_slot_grants (user_id, slots, ends_at, order_id)
      values (o.user_id, it.quantity, now() + make_interval(days => it.days), o.id);
    elsif it.kind = 'plan' then
      update profiles set
        plan = it.plan,
        plan_until = (case when plan = it.plan and plan_until > now() then plan_until else now() end)
                     + make_interval(days => it.days),
        boost_credits = boost_credits + it.quantity
      where id = o.user_id;
    end if;
    update orders set fulfilled_at = now(), fulfil_error = null where id = o.id;
  exception when others then
    -- деньги получены, а услуга не включилась — видно в кабинете, команда решает вручную
    update orders set fulfil_error = left(sqlerrm, 200) where id = o.id;
  end;
end $$;
revoke execute on function public._fulfil_order(uuid) from public, anon, authenticated;

-- оплата подтверждена провайдером (вызывает только Edge Function с ключом сервиса)
create or replace function public.mark_order_paid(p_ref text, p_provider text, p_provider_ref text)
returns text language plpgsql security definer set search_path = public, extensions as $$
declare o orders;
begin
  select * into o from orders where ref = p_ref for update;
  if o is null then return 'unknown'; end if;
  if o.status = 'paid' then return 'already'; end if;
  if o.status not in ('pending', 'failed') then return 'bad_status'; end if;
  update orders set status = 'paid', paid_at = now(), provider = p_provider, provider_ref = p_provider_ref
   where id = o.id;
  perform public._fulfil_order(o.id);
  return 'ok';
end $$;
revoke execute on function public.mark_order_paid(text, text, text) from public, anon, authenticated;
grant execute on function public.mark_order_paid(text, text, text) to service_role;

-- ---------- использовать буст из запаса ----------
create or replace function public.use_boost_credit(p_property uuid)
returns void language plpgsql security definer set search_path = public, extensions as $$
declare uid uuid := auth.uid();
begin
  if uid is null then raise exception 'AUTH'; end if;
  if not exists (select 1 from properties where id = p_property and owner_id = uid and status = 'active') then
    raise exception 'NOT_YOUR_LISTING';
  end if;
  update profiles set boost_credits = boost_credits - 1 where id = uid and boost_credits > 0;
  if not found then raise exception 'NO_CREDITS'; end if;
  insert into promotions (property_id, user_id, is_free, ends_at) values (p_property, uid, false, now() + interval '7 days');
end $$;
grant execute on function public.use_boost_credit(uuid) to authenticated;

-- что у меня есть: тариф, кредиты, доп. места
create or replace function public.my_billing()
returns jsonb language sql stable security definer set search_path = public, extensions as $$
  select jsonb_build_object(
    'plan', case when p.plan_until > now() then p.plan end,
    'plan_until', case when p.plan_until > now() then p.plan_until end,
    'boost_credits', p.boost_credits,
    'extra_slots', coalesce((select sum(slots)::int from listing_slot_grants g where g.user_id = p.id and g.ends_at > now()), 0)
                   + p.extra_listing_slots,
    'billing', public.billing_on(),
    'payment_info', (select value from app_settings where key = 'manual_payment_info'))
  from profiles p where p.id = auth.uid();
$$;
grant execute on function public.my_billing() to authenticated;

-- пока платные функции включены, кампании агентов запускаются только через покупку (буст / Featured)
create or replace function public.promotion_switch()
returns trigger language plpgsql security definer set search_path = public, extensions as $$
begin
  if new.status = 'active' and not public.promotion_on()
     and (tg_op = 'INSERT' or old.status is distinct from 'active') then
    raise exception 'PROMOTION_OFF';
  end if;
  -- агент сам (не оплаченный заказ и не команда)
  if tg_op = 'INSERT' and public.billing_on() and auth.uid() is not null and not public.is_admin()
     and coalesce(current_setting('zumi.fulfilling', true), '') <> 'on' then
    raise exception 'USE_BOOST';
  end if;
  return new;
end $$;

-- статьи помощи: новые лимиты
update public.help_articles set body = replace(replace(body,
  'Agents can publish 5 listings for free. With a checked ZIEA licence — 10.',
  'Agents can publish 15 listings for free. With a checked ZIEA licence — 25.'),
  'With a checked ZIEA licence — 10.', 'With a checked ZIEA licence — 25.')
 where id = 'a44d1cea-2bb5-5fdc-81f2-6aea36e74198' and updated_by is null;

-- ---------- кабинет владельца ----------
create or replace function public.admin_set_setting(p_key text, p_value text)
returns void language plpgsql security definer set search_path = public, extensions as $$
begin
  if not public.is_admin() then raise exception 'NOT_ADMIN'; end if;
  if p_key not in ('otp_test_mode', 'require_licence_to_publish', 'promotion_enabled', 'ads_enabled',
                   'billing_enabled', 'manual_payment_info', 'payment_mode') then
    raise exception 'BAD_SETTING';
  end if;
  if p_key in ('promotion_enabled', 'ads_enabled', 'billing_enabled', 'manual_payment_info', 'payment_mode')
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

create or replace function public.admin_set_price(p_code text, p_amount numeric, p_active boolean)
returns void language plpgsql security definer set search_path = public, extensions as $$
begin
  if not public.is_owner() then raise exception 'OWNER_ONLY'; end if;
  if p_amount is null or p_amount < 0 or p_amount > 1000000 then raise exception 'BAD_PRICE'; end if;
  update price_list set amount = round(p_amount, 2), active = coalesce(p_active, active) where code = p_code;
  if not found then raise exception 'BAD_ITEM'; end if;
  perform public._audit('price', 'price_list', p_code, p_amount::text || case when p_active then '' else ' (off)' end);
end $$;
grant execute on function public.admin_set_price(text, numeric, boolean) to authenticated;

-- ручная оплата: владелец увидел перевод и подтверждает (или отменяет)
create or replace function public.admin_mark_order(p_order uuid, p_status text, p_note text default null)
returns void language plpgsql security definer set search_path = public, extensions as $$
declare o orders;
begin
  if not public.is_owner() then raise exception 'OWNER_ONLY'; end if;
  if p_status not in ('paid', 'cancelled', 'refunded', 'retry') then raise exception 'BAD_STATUS'; end if;
  select * into o from orders where id = p_order for update;
  if o is null then raise exception 'NOT_FOUND'; end if;
  if p_status = 'paid' then
    if o.status not in ('pending', 'failed') then raise exception 'BAD_STATUS'; end if;
    update orders set status = 'paid', paid_at = now(), provider = coalesce(provider, 'manual'),
                      note = nullif(left(coalesce(p_note, ''), 200), '') where id = o.id;
    perform public._fulfil_order(o.id);
  elsif p_status = 'retry' then
    perform public._fulfil_order(o.id);       -- повторить включение услуги после ошибки
  elsif p_status = 'cancelled' then
    if o.status <> 'pending' then raise exception 'BAD_STATUS'; end if;
    update orders set status = 'cancelled', note = nullif(left(coalesce(p_note, ''), 200), '') where id = o.id;
  else
    if o.status <> 'paid' then raise exception 'BAD_STATUS'; end if;
    update orders set status = 'refunded', note = nullif(left(coalesce(p_note, ''), 200), '') where id = o.id;
  end if;
  perform public._audit('order_' || p_status, 'orders', o.ref, p_note);
end $$;
grant execute on function public.admin_mark_order(uuid, text, text) to authenticated;

create or replace function public.admin_orders(p_status text default null, p_limit int default 100)
returns table (id uuid, ref text, user_name text, user_email text, item_code text, item_title text,
               property_title text, amount numeric, currency text, pay_phone text, status text,
               provider text, created_at timestamptz, paid_at timestamptz, fulfilled_at timestamptz,
               fulfil_error text, note text)
language plpgsql stable security definer set search_path = public, extensions as $$
begin
  if not public.is_owner() then raise exception 'OWNER_ONLY'; end if;
  return query
    select o.id, o.ref, p.full_name, u.email::text, o.item_code, pl.title, pr.title, o.amount, o.currency,
           o.pay_phone, o.status, o.provider, o.created_at, o.paid_at, o.fulfilled_at, o.fulfil_error, o.note
      from orders o
      left join profiles p on p.id = o.user_id
      left join auth.users u on u.id = o.user_id
      left join price_list pl on pl.code = o.item_code
      left join properties pr on pr.id = o.property_id
     where p_status is null or o.status = p_status
     order by o.created_at desc
     limit greatest(1, least(coalesce(p_limit, 100), 500));
end $$;
grant execute on function public.admin_orders(text, int) to authenticated;

create or replace function public.admin_billing_status()
returns jsonb language plpgsql stable security definer set search_path = public, extensions as $$
begin
  if not public.is_owner() then raise exception 'OWNER_ONLY'; end if;
  return jsonb_build_object(
    'enabled', public.billing_on(),
    'mode', (select value from app_settings where key = 'payment_mode'),
    'payment_info', (select value from app_settings where key = 'manual_payment_info'),
    'pending', (select count(*) from orders where status = 'pending'),
    'problems', (select count(*) from orders where status = 'paid' and fulfilled_at is null),
    'revenue_30d', (select coalesce(sum(amount), 0) from orders where status = 'paid' and paid_at > now() - interval '30 days'),
    'paid_30d', (select count(*) from orders where status = 'paid' and paid_at > now() - interval '30 days'),
    'active_plans', (select count(*) from profiles where plan_until > now()));
end $$;
grant execute on function public.admin_billing_status() to authenticated;

-- неоплаченные заказы старше 7 дней сами отменяются (в ежедневной уборке)
create or replace function public.cleanup_orders()
returns void language sql security definer set search_path = public, extensions as $$
  update orders set status = 'cancelled', note = coalesce(note, 'expired')
   where status = 'pending' and created_at < now() - interval '7 days';
  delete from listing_slot_grants where ends_at < now() - interval '30 days';
$$;
revoke execute on function public.cleanup_orders() from public, anon, authenticated;

do $$
begin
  if exists (select 1 from pg_extension where extname = 'pg_cron') then
    perform cron.unschedule(jobid) from cron.job where jobname = 'zumi-orders';
    perform cron.schedule('zumi-orders', '25 3 * * *', 'select public.cleanup_orders()');
  end if;
end $$;
