-- =====================================================================
--  Zumi — 034: агентства
--  • Новый тип аккаунта «Agency»: компания с названием, номером регистрации фирмы в ZIEA, логотипом.
--  • Агенты вступают в агентство по ссылке-приглашению; владелец агентства управляет составом.
--  • ОБЩИЙ лимит объявлений на всё агентство (закрывает лазейку «6 сотрудников = 6 лимитов»):
--    бесплатно 30, у агентства с проверенной фирмой — 50; тариф Agency (150) и доп. объявления
--    покупает владелец агентства — и они действуют на всё агентство.
--  • Публичная страница агентства: агенты и все их объявления.
--  • Команда Zumi проверяет регистрацию фирмы (кабинет → Licences).
--  Запускать после 033. Можно запускать повторно.
-- =====================================================================

-- ---------- таблицы ----------
create table if not exists public.agencies (
  id                  uuid primary key default gen_random_uuid(),
  owner_id            uuid not null unique references public.profiles(id) on delete cascade,
  name                text not null check (length(trim(name)) between 2 and 80),
  firm_licence_no     text check (firm_licence_no is null or length(firm_licence_no) <= 40),
  licence_verified_at timestamptz,
  phone               text check (phone is null or length(phone) <= 30),
  about               text check (about is null or length(about) <= 600),
  logo_url            text,
  created_at          timestamptz not null default now(),
  updated_at          timestamptz not null default now()
);
alter table public.agencies enable row level security;
drop policy if exists "agencies readable" on public.agencies;
create policy "agencies readable" on public.agencies for select using (true);
grant select on public.agencies to anon, authenticated;

alter table public.profiles add column if not exists agency_id uuid references public.agencies(id) on delete set null;
create index if not exists profiles_agency_idx on public.profiles (agency_id) where agency_id is not null;
grant select (agency_id) on public.profiles to anon, authenticated;   -- кто в каком агентстве — публично

create table if not exists public.agency_invites (
  code       text primary key,
  agency_id  uuid not null references public.agencies(id) on delete cascade,
  created_at timestamptz not null default now(),
  expires_at timestamptz not null default now() + interval '14 days',
  used_by    uuid references public.profiles(id) on delete set null,
  used_at    timestamptz
);
alter table public.agency_invites enable row level security;   -- только через функции

-- лимиты агентства (общие на всех агентов)
alter table public.role_limits drop constraint if exists role_limits_role_check;
alter table public.role_limits add constraint role_limits_role_check check (role in ('agent', 'owner', 'agency'));
insert into public.role_limits (role, free_listings, free_promotions, free_listings_licensed)
values ('agency', 30, 0, 50) on conflict (role) do nothing;

-- вступить / выйти — только через функции ниже (нельзя самому вписать себе чужое агентство)
create or replace function public.agency_id_guard()
returns trigger language plpgsql security definer set search_path = public, extensions as $$
begin
  if new.agency_id is distinct from old.agency_id and auth.uid() is not null
     and coalesce(current_setting('zumi.agency', true), '') <> 'on' and not public.is_admin() then
    raise exception 'USE_INVITE';
  end if;
  return new;
end $$;
drop trigger if exists agency_id_guard on public.profiles;
create trigger agency_id_guard before update of agency_id on public.profiles
  for each row execute function public.agency_id_guard();

-- название агентства у агентов-сотрудников всегда берётся из агентства
create or replace function public.agency_name_sync()
returns trigger language plpgsql security definer set search_path = public, extensions as $$
begin
  if new.agency_id is not null then
    new.agency_name := (select name from agencies where id = new.agency_id);
  elsif tg_op = 'UPDATE' and old.agency_id is not null and new.agency_id is null then
    new.agency_name := null;
  end if;
  return new;
end $$;
drop trigger if exists zz_agency_name_sync on public.profiles;
create trigger zz_agency_name_sync before insert or update of agency_id, agency_name on public.profiles
  for each row execute function public.agency_name_sync();

create or replace function public.agency_renamed()
returns trigger language plpgsql security definer set search_path = public, extensions as $$
begin
  update profiles set agency_name = new.name where agency_id = new.id;
  return new;
end $$;
drop trigger if exists agency_renamed on public.agencies;
create trigger agency_renamed after update of name on public.agencies
  for each row execute function public.agency_renamed();

-- ---------- общий лимит ----------
create or replace function public.listing_quota(uid uuid)
returns table (used int, allowed int) language sql stable security definer
set search_path = public, extensions as $$
  with me as (select * from profiles where id = uid),
  ag as (select a.* from agencies a join me on me.agency_id = a.id),
  boss as (select p.* from profiles p join ag on p.id = ag.owner_id)
  select
    case when exists (select 1 from ag)
      -- в агентстве: считаем объявления всех агентов агентства
      then (select count(*)::int from properties pr join profiles m on m.id = pr.owner_id
             where m.agency_id = (select id from ag) and pr.status in ('active', 'draft', 'pending') and not pr.is_demo)
      else (select count(*)::int from properties
             where owner_id = uid and status in ('active', 'draft', 'pending') and not is_demo)
    end,
    case when exists (select 1 from ag)
      -- лимит агентства: бесплатный (30 / 50 с проверенной фирмой) или тариф владельца агентства + его доп. объявления
      then (select greatest(
                     case when (select licence_verified_at from ag) is not null
                          then coalesce(rl.free_listings_licensed, rl.free_listings) else rl.free_listings end,
                     coalesce((select pl.listings from plan_limits pl
                                where pl.plan = b.plan and b.plan_until > now()), 0))
                   + b.extra_listing_slots
                   + coalesce((select sum(g.slots)::int from listing_slot_grants g
                                where g.user_id = b.id and g.ends_at > now()), 0)
              from boss b, role_limits rl where rl.role = 'agency')
      else (select greatest(
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
              from me p left join role_limits rl on rl.role = p.role)
    end;
$$;

-- ---------- создать / изменить агентство ----------
create or replace function public.create_agency(p_name text, p_firm_no text default null, p_phone text default null)
returns uuid language plpgsql security definer set search_path = public, extensions as $$
declare uid uuid := auth.uid(); v_id uuid; v_role text;
begin
  if uid is null then raise exception 'AUTH'; end if;
  select role into v_role from profiles where id = uid;
  if v_role not in ('agent', 'admin') then raise exception 'AGENTS_ONLY'; end if;
  if exists (select 1 from profiles where id = uid and agency_id is not null) then raise exception 'ALREADY_IN_AGENCY'; end if;
  if length(trim(coalesce(p_name, ''))) < 2 then raise exception 'BAD_NAME'; end if;
  insert into agencies (owner_id, name, firm_licence_no, phone)
  values (uid, left(trim(p_name), 80), nullif(left(trim(coalesce(p_firm_no, '')), 40), ''),
          nullif(left(trim(coalesce(p_phone, '')), 30), ''))
  returning id into v_id;
  perform set_config('zumi.agency', 'on', true);
  update profiles set agency_id = v_id where id = uid;
  return v_id;
end $$;
revoke execute on function public.create_agency(text, text, text) from public, anon;
grant execute on function public.create_agency(text, text, text) to authenticated;

create or replace function public.update_agency(p_name text, p_firm_no text, p_phone text, p_about text, p_logo_url text default null)
returns void language plpgsql security definer set search_path = public, extensions as $$
declare uid uuid := auth.uid(); a agencies;
begin
  select * into a from agencies where owner_id = uid;
  if a is null then raise exception 'NOT_AGENCY_OWNER'; end if;
  if length(trim(coalesce(p_name, ''))) < 2 then raise exception 'BAD_NAME'; end if;
  update agencies set
    name = left(trim(p_name), 80),
    firm_licence_no = nullif(left(trim(coalesce(p_firm_no, '')), 40), ''),
    -- сменили номер фирмы — проверка заново
    licence_verified_at = case when nullif(trim(coalesce(p_firm_no, '')), '') is distinct from a.firm_licence_no
                               then null else a.licence_verified_at end,
    phone = nullif(left(trim(coalesce(p_phone, '')), 30), ''),
    about = nullif(left(trim(coalesce(p_about, '')), 600), ''),
    logo_url = coalesce(p_logo_url, a.logo_url),
    updated_at = now()
  where id = a.id;
end $$;
revoke execute on function public.update_agency(text, text, text, text, text) from public, anon;
grant execute on function public.update_agency(text, text, text, text, text) to authenticated;

-- ---------- приглашения ----------
create or replace function public.agency_invite()
returns text language plpgsql security definer set search_path = public, extensions as $$
declare uid uuid := auth.uid(); v_ag uuid; v_code text;
begin
  select id into v_ag from agencies where owner_id = uid;
  if v_ag is null then raise exception 'NOT_AGENCY_OWNER'; end if;
  if (select count(*) from agency_invites where agency_id = v_ag and created_at > now() - interval '1 day') >= 30 then
    raise exception 'TOO_MANY_INVITES';
  end if;
  v_code := upper(substr(md5(gen_random_uuid()::text), 1, 8));
  insert into agency_invites (code, agency_id) values (v_code, v_ag);
  return v_code;
end $$;
revoke execute on function public.agency_invite() from public, anon;
grant execute on function public.agency_invite() to authenticated;

-- что за приглашение (до входа: показать название агентства)
create or replace function public.agency_invite_info(p_code text)
returns jsonb language sql stable security definer set search_path = public, extensions as $$
  select jsonb_build_object('agency_id', a.id, 'name', a.name, 'logo_url', a.logo_url,
                            'valid', i.used_at is null and i.expires_at > now())
    from agency_invites i join agencies a on a.id = i.agency_id
   where i.code = upper(trim(p_code));
$$;
grant execute on function public.agency_invite_info(text) to anon, authenticated;

create or replace function public.join_agency(p_code text)
returns uuid language plpgsql security definer set search_path = public, extensions as $$
declare uid uuid := auth.uid(); i agency_invites; v_role text;
begin
  if uid is null then raise exception 'AUTH'; end if;
  select role into v_role from profiles where id = uid;
  if v_role not in ('agent', 'admin') then raise exception 'AGENTS_ONLY'; end if;
  if exists (select 1 from profiles where id = uid and agency_id is not null) then raise exception 'ALREADY_IN_AGENCY'; end if;
  select * into i from agency_invites where code = upper(trim(coalesce(p_code, ''))) for update;
  if i is null or i.used_at is not null or i.expires_at < now() then raise exception 'BAD_CODE'; end if;
  update agency_invites set used_by = uid, used_at = now() where code = i.code;
  perform set_config('zumi.agency', 'on', true);
  update profiles set agency_id = i.agency_id where id = uid;
  return i.agency_id;
end $$;
revoke execute on function public.join_agency(text) from public, anon;
grant execute on function public.join_agency(text) to authenticated;

create or replace function public.leave_agency()
returns void language plpgsql security definer set search_path = public, extensions as $$
declare uid uuid := auth.uid();
begin
  if exists (select 1 from agencies where owner_id = uid) then raise exception 'OWNER_CANNOT_LEAVE'; end if;
  perform set_config('zumi.agency', 'on', true);
  update profiles set agency_id = null where id = uid;
end $$;
revoke execute on function public.leave_agency() from public, anon;
grant execute on function public.leave_agency() to authenticated;

create or replace function public.agency_remove_member(p_user uuid)
returns void language plpgsql security definer set search_path = public, extensions as $$
declare uid uuid := auth.uid(); v_ag uuid;
begin
  select id into v_ag from agencies where owner_id = uid;
  if v_ag is null then raise exception 'NOT_AGENCY_OWNER'; end if;
  if p_user = uid then raise exception 'OWNER_CANNOT_LEAVE'; end if;
  perform set_config('zumi.agency', 'on', true);
  update profiles set agency_id = null where id = p_user and agency_id = v_ag;
  if not found then raise exception 'NOT_A_MEMBER'; end if;
end $$;
revoke execute on function public.agency_remove_member(uuid) from public, anon;
grant execute on function public.agency_remove_member(uuid) to authenticated;

-- ---------- что видно ----------
-- агентство целиком: публичная страница (и кабинет владельца — is_owner)
create or replace function public.agency_page(p_id uuid)
returns jsonb language sql stable security definer set search_path = public, extensions as $$
  select jsonb_build_object(
    'id', a.id, 'name', a.name, 'logo_url', a.logo_url, 'about', a.about, 'phone', a.phone,
    'firm_licence_no', case when a.owner_id = auth.uid() or public.is_admin() then a.firm_licence_no end,
    'verified', a.licence_verified_at is not null,
    'owner_id', a.owner_id,
    'is_owner', coalesce(a.owner_id = auth.uid(), false),
    'is_member', exists (select 1 from profiles where id = auth.uid() and agency_id = a.id),
    'created_at', a.created_at,
    'members', coalesce((
      select jsonb_agg(jsonb_build_object(
               'id', m.id, 'full_name', m.full_name, 'avatar_url', m.avatar_url,
               'licensed', m.licence_verified_at is not null, 'is_owner', m.id = a.owner_id,
               'listings', (select count(*) from properties p where p.owner_id = m.id and p.status = 'active'))
             order by (m.id = a.owner_id) desc, m.full_name)
        from profiles m where m.agency_id = a.id and m.banned_at is null), '[]'::jsonb),
    'active_listings', (select count(*) from properties p join profiles m on m.id = p.owner_id
                         where m.agency_id = a.id and p.status = 'active'))
  from agencies a where a.id = p_id;
$$;
grant execute on function public.agency_page(uuid) to anon, authenticated;

-- ---------- команда Zumi: проверка фирм ----------
create or replace function public.admin_agencies()
returns table (id uuid, name text, firm_licence_no text, verified boolean, owner_name text, owner_phone text,
               members int, active_listings int, created_at timestamptz)
language sql stable security definer set search_path = public, extensions as $$
  select a.id, a.name, a.firm_licence_no, a.licence_verified_at is not null, o.full_name, o.phone,
         (select count(*)::int from profiles m where m.agency_id = a.id),
         (select count(*)::int from properties p join profiles m on m.id = p.owner_id
           where m.agency_id = a.id and p.status = 'active'),
         a.created_at
    from agencies a join profiles o on o.id = a.owner_id
   where public.is_admin()
   order by (a.licence_verified_at is null and a.firm_licence_no is not null) desc, a.created_at desc
   limit 200;
$$;
revoke execute on function public.admin_agencies() from public, anon;
grant execute on function public.admin_agencies() to authenticated;

create or replace function public.admin_verify_agency(p_id uuid, p_ok boolean)
returns void language plpgsql security definer set search_path = public, extensions as $$
begin
  if not public.is_admin() then raise exception 'FORBIDDEN'; end if;
  update agencies set licence_verified_at = case when p_ok then now() end, updated_at = now() where id = p_id;
end $$;
revoke execute on function public.admin_verify_agency(uuid, boolean) from public, anon;
grant execute on function public.admin_verify_agency(uuid, boolean) to authenticated;

-- сотрудник агентства не покупает личный тариф и доп. объявления — их покупает владелец агентства
create or replace function public.agency_order_guard()
returns trigger language plpgsql security definer set search_path = public, extensions as $$
begin
  if exists (select 1 from profiles p join agencies a on a.id = p.agency_id
              where p.id = new.user_id and a.owner_id <> p.id)
     and exists (select 1 from price_list where code = new.item_code and kind in ('plan', 'slots')) then
    raise exception 'ASK_AGENCY_OWNER';
  end if;
  return new;
end $$;
drop trigger if exists agency_order_guard on public.orders;
create trigger agency_order_guard before insert on public.orders
  for each row execute function public.agency_order_guard();

-- ---------- регистрация «Agency»: агент + агентство сразу ----------
create or replace function public.handle_new_user()
returns trigger language plpgsql security definer set search_path = public, extensions as $$
declare
  v_agent boolean := new.raw_user_meta_data->>'role' in ('agent', 'agency');
  v_agency text := nullif(left(trim(coalesce(new.raw_user_meta_data->>'agency_name', '')), 80), '');
  v_id uuid;
begin
  insert into public.profiles (id, full_name, phone, role, terms_accepted_at, agent_licence_no,
                               marketing_email_at, marketing_whatsapp_at)
  values (
    new.id,
    new.raw_user_meta_data->>'full_name',
    new.raw_user_meta_data->>'phone',
    case when v_agent then 'agent' else 'owner' end,
    case when (new.raw_user_meta_data->>'terms_accepted') = 'true' then now() end,
    case when v_agent then nullif(left(trim(coalesce(new.raw_user_meta_data->>'licence_no', '')), 40), '') end,
    case when (new.raw_user_meta_data->>'marketing') = 'true' then now() end,
    case when (new.raw_user_meta_data->>'marketing') = 'true' then now() end
  );
  if new.raw_user_meta_data->>'role' = 'agency' and length(coalesce(v_agency, '')) >= 2 then
    insert into public.agencies (owner_id, name, firm_licence_no, phone)
    values (new.id, v_agency,
            nullif(left(trim(coalesce(new.raw_user_meta_data->>'firm_licence_no', '')), 40), ''),
            nullif(left(trim(coalesce(new.raw_user_meta_data->>'phone', '')), 30), ''))
    returning id into v_id;
    update public.profiles set agency_id = v_id where id = new.id;
  end if;
  return new;
end $$;

-- проверка: всё должно быть true
select
  exists (select 1 from information_schema.tables where table_name = 'agencies') as agencies_ok,
  exists (select 1 from role_limits where role = 'agency' and free_listings = 30 and free_listings_licensed = 50) as limits_ok,
  exists (select 1 from information_schema.columns where table_name = 'profiles' and column_name = 'agency_id') as members_ok;
