-- =====================================================================
--  Zambia Real Estate App — Supabase schema (v1)
--  Запускать в Supabase: Dashboard → SQL Editor → New query → Run
-- =====================================================================

-- расширения ставим в схему extensions (так рекомендует Supabase); функции ищут их там же
create schema if not exists extensions;
create extension if not exists postgis with schema extensions;
-- в этом окне SQL функции PostGIS и типы ищутся и в public, и в extensions
set search_path = public, extensions;

-- ---------------------------------------------------------------------
-- 1. Настройки лимитов (меняются без изменения кода)
-- ---------------------------------------------------------------------
create table public.role_limits (
  role               text primary key check (role in ('agent','owner')),
  free_listings      int  not null,   -- сколько активных объявлений бесплатно
  free_promotions    int  not null    -- сколько продвижений бесплатно
);
insert into public.role_limits values
  ('agent', 5, 0),
  ('owner', 2, 0);

-- ---------------------------------------------------------------------
-- 2. Профили пользователей
-- ---------------------------------------------------------------------
create table public.profiles (
  id            uuid primary key references auth.users(id) on delete cascade,
  role          text not null default 'owner' check (role in ('agent','owner','admin')),
  full_name     text,
  phone         text,
  whatsapp      text,
  agency_name   text,
  avatar_url    text,
  is_verified   boolean not null default false,
  extra_listing_slots int not null default 0,   -- куплено доп. слотов
  created_at    timestamptz not null default now()
);

-- автосоздание профиля при регистрации
create or replace function public.handle_new_user()
returns trigger language plpgsql security definer set search_path = public, extensions as $$
begin
  insert into public.profiles (id, full_name, phone, role)
  values (
    new.id,
    new.raw_user_meta_data->>'full_name',
    new.raw_user_meta_data->>'phone',
    coalesce(new.raw_user_meta_data->>'role','owner')
  );
  return new;
end $$;

create trigger on_auth_user_created
  after insert on auth.users
  for each row execute function public.handle_new_user();

-- ---------------------------------------------------------------------
-- 3. Города и районы
-- ---------------------------------------------------------------------
create table public.areas (
  id         serial primary key,
  city       text not null,
  name       text not null,
  center     geography(point, 4326) not null,
  boundary   geography(multipolygon, 4326),     -- можно добавить позже
  unique (city, name)
);

-- ---------------------------------------------------------------------
-- 4. Объявления
-- ---------------------------------------------------------------------
create table public.properties (
  id              uuid primary key default gen_random_uuid(),
  owner_id        uuid not null references public.profiles(id) on delete cascade,
  title           text not null,
  description     text,
  deal_type       text not null check (deal_type in ('sale','rent')),
  property_type   text not null check (property_type in
                    ('house','apartment','townhouse','land','commercial','office','room')),
  price           numeric(14,2) not null check (price >= 0),
  currency        text not null default 'ZMW' check (currency in ('ZMW','USD')),
  rent_period     text check (rent_period in ('month','day')),
  bedrooms        int,
  bathrooms       int,
  area_sqm        numeric(10,2),
  plot_sqm        numeric(10,2),
  furnished       boolean,
  amenities       text[] default '{}',          -- 'parking','pool','borehole','solar','security'...
  area_id         int references public.areas(id),
  address         text,
  location        geography(point, 4326) not null,
  status          text not null default 'active'
                    check (status in ('draft','active','sold','rented','archived')),
  promoted_until  timestamptz,
  views_count     int not null default 0,
  is_demo         boolean not null default false,
  created_at      timestamptz not null default now(),
  updated_at      timestamptz not null default now()
);

create index properties_location_idx on public.properties using gist (location);
create index properties_filter_idx   on public.properties (status, deal_type, property_type, price);
create index properties_area_idx     on public.properties (area_id);

create table public.property_images (
  id           uuid primary key default gen_random_uuid(),
  property_id  uuid not null references public.properties(id) on delete cascade,
  url          text not null,
  sort_order   int not null default 0
);

create table public.favorites (
  user_id      uuid references public.profiles(id) on delete cascade,
  property_id  uuid references public.properties(id) on delete cascade,
  created_at   timestamptz not null default now(),
  primary key (user_id, property_id)
);

-- ---------------------------------------------------------------------
-- 5. Платежи и продвижения (структура готова, провайдер подключим позже)
-- ---------------------------------------------------------------------
create table public.payments (
  id              uuid primary key default gen_random_uuid(),
  user_id         uuid not null references public.profiles(id),
  purpose         text not null check (purpose in ('promotion','listing_slot')),
  property_id     uuid references public.properties(id),
  amount          numeric(12,2) not null,
  currency        text not null default 'ZMW',
  provider        text,                 -- 'mtn_momo','airtel_money','card', ...
  provider_ref    text,
  status          text not null default 'pending'
                    check (status in ('pending','paid','failed','refunded')),
  created_at      timestamptz not null default now(),
  paid_at         timestamptz
);

create table public.promotions (
  id            uuid primary key default gen_random_uuid(),
  property_id   uuid not null references public.properties(id) on delete cascade,
  user_id       uuid not null references public.profiles(id),
  payment_id    uuid references public.payments(id),
  is_free       boolean not null default false,
  starts_at     timestamptz not null default now(),
  ends_at       timestamptz not null
);

-- после оплаты: продвижение продлевает promoted_until у объявления
create or replace function public.apply_promotion()
returns trigger language plpgsql security definer set search_path = public, extensions as $$
begin
  update public.properties
     set promoted_until = greatest(coalesce(promoted_until, now()), new.ends_at)
   where id = new.property_id;
  return new;
end $$;

create trigger on_promotion_created
  after insert on public.promotions
  for each row execute function public.apply_promotion();

-- ---------------------------------------------------------------------
-- 6. Лимит объявлений: агент 5, собственник 2, дальше — купленные слоты
-- ---------------------------------------------------------------------
create or replace function public.listing_quota(uid uuid)
returns table (used int, allowed int) language sql stable security definer
set search_path = public, extensions as $$
  select
    (select count(*)::int from properties
      where owner_id = uid and status in ('active','draft') and not is_demo),
    (select coalesce(rl.free_listings, 999999) + p.extra_listing_slots
       from profiles p left join role_limits rl on rl.role = p.role
      where p.id = uid);
$$;

create or replace function public.enforce_listing_limit()
returns trigger language plpgsql security definer set search_path = public, extensions as $$
declare q record;
begin
  if new.is_demo then return new; end if;
  select * into q from public.listing_quota(new.owner_id);
  if q.used >= q.allowed then
    raise exception 'LISTING_LIMIT_REACHED' using hint = 'Buy an extra listing slot';
  end if;
  return new;
end $$;

create trigger check_listing_limit
  before insert on public.properties
  for each row execute function public.enforce_listing_limit();

-- ---------------------------------------------------------------------
-- 7. Поиск: фильтры + карта (bbox) + продвинутые первыми
-- ---------------------------------------------------------------------
create or replace function public.search_properties(
  p_deal_type     text    default null,
  p_property_type text    default null,
  p_min_price     numeric default null,
  p_max_price     numeric default null,
  p_bedrooms      int     default null,
  p_area_id       int     default null,
  p_min_lat double precision default null, p_min_lng double precision default null,
  p_max_lat double precision default null, p_max_lng double precision default null,
  p_limit int default 50, p_offset int default 0
)
returns table (
  id uuid, title text, deal_type text, property_type text, price numeric,
  currency text, rent_period text, bedrooms int, bathrooms int, area_sqm numeric,
  area_name text, lat double precision, lng double precision,
  is_promoted boolean, cover_url text, created_at timestamptz
) language sql stable as $$
  select p.id, p.title, p.deal_type, p.property_type, p.price, p.currency,
         p.rent_period, p.bedrooms, p.bathrooms, p.area_sqm, a.name,
         st_y(p.location::geometry), st_x(p.location::geometry),
         coalesce(p.promoted_until > now(), false),
         (select url from property_images i where i.property_id = p.id
           order by sort_order limit 1),
         p.created_at
    from properties p
    left join areas a on a.id = p.area_id
   where p.status = 'active'
     and (p_deal_type     is null or p.deal_type = p_deal_type)
     and (p_property_type is null or p.property_type = p_property_type)
     and (p_min_price     is null or p.price >= p_min_price)
     and (p_max_price     is null or p.price <= p_max_price)
     and (p_bedrooms      is null or p.bedrooms >= p_bedrooms)
     and (p_area_id       is null or p.area_id = p_area_id)
     and (p_min_lat is null or
          p.location::geometry && st_makeenvelope(p_min_lng, p_min_lat, p_max_lng, p_max_lat, 4326))
   order by coalesce(p.promoted_until > now(), false) desc, p.created_at desc
   limit p_limit offset p_offset;
$$;

-- статистика по районам для слоя на карте
create or replace view public.area_stats as
  select a.id, a.city, a.name,
         st_y(a.center::geometry) as lat, st_x(a.center::geometry) as lng,
         count(p.id) filter (where p.deal_type = 'sale') as for_sale,
         count(p.id) filter (where p.deal_type = 'rent') as for_rent,
         round(avg(p.price) filter (where p.deal_type = 'rent' and p.currency = 'ZMW')) as avg_rent_zmw
    from areas a
    left join properties p on p.area_id = a.id and p.status = 'active'
   group by a.id;

-- ---------------------------------------------------------------------
-- 8. Безопасность (RLS)
-- ---------------------------------------------------------------------
alter table public.profiles        enable row level security;
alter table public.properties      enable row level security;
alter table public.property_images enable row level security;
alter table public.favorites       enable row level security;
alter table public.payments        enable row level security;
alter table public.promotions      enable row level security;
alter table public.areas           enable row level security;
alter table public.role_limits     enable row level security;

create policy "areas readable"       on public.areas       for select using (true);
create policy "limits readable"      on public.role_limits for select using (true);

create policy "profiles readable"    on public.profiles for select using (true);
create policy "own profile update"   on public.profiles for update using (auth.uid() = id)
  with check (auth.uid() = id);   -- role/слоты меняет только сервер (см. ниже)

create policy "active props readable" on public.properties for select
  using (status = 'active' or owner_id = auth.uid());
create policy "own props insert" on public.properties for insert with check (owner_id = auth.uid());
create policy "own props update" on public.properties for update using (owner_id = auth.uid());
create policy "own props delete" on public.properties for delete using (owner_id = auth.uid());

create policy "images readable" on public.property_images for select using (true);
create policy "own images write" on public.property_images for all
  using (exists (select 1 from properties p where p.id = property_id and p.owner_id = auth.uid()))
  with check (exists (select 1 from properties p where p.id = property_id and p.owner_id = auth.uid()));

create policy "own favorites" on public.favorites for all
  using (user_id = auth.uid()) with check (user_id = auth.uid());

create policy "own payments read"   on public.payments   for select using (user_id = auth.uid());
create policy "own promotions read" on public.promotions for select using (user_id = auth.uid());
-- платежи и продвижения создаются только сервером (Edge Function с service key)

-- пользователь не может сам поменять себе роль, слоты, верификацию
revoke update (role, extra_listing_slots, is_verified) on public.profiles from authenticated;

-- ---------------------------------------------------------------------
-- 9. Хранилище фото
-- ---------------------------------------------------------------------
insert into storage.buckets (id, name, public) values ('property-images','property-images', true)
  on conflict do nothing;

create policy "public read images" on storage.objects for select
  using (bucket_id = 'property-images');
create policy "users upload to own folder" on storage.objects for insert to authenticated
  with check (bucket_id = 'property-images' and (storage.foldername(name))[1] = auth.uid()::text);
create policy "users delete own files" on storage.objects for delete to authenticated
  using (bucket_id = 'property-images' and (storage.foldername(name))[1] = auth.uid()::text);

-- ---------------------------------------------------------------------
-- 10. Районы Лусаки (координаты центров приблизительные, уточним позже)
-- ---------------------------------------------------------------------
insert into public.areas (city, name, center) values
  ('Lusaka','Kabulonga',     st_point(28.335,-15.425)::geography),
  ('Lusaka','Woodlands',     st_point(28.320,-15.435)::geography),
  ('Lusaka','Roma',          st_point(28.310,-15.370)::geography),
  ('Lusaka','Ibex Hill',     st_point(28.370,-15.440)::geography),
  ('Lusaka','Rhodes Park',   st_point(28.305,-15.405)::geography),
  ('Lusaka','Olympia',       st_point(28.310,-15.385)::geography),
  ('Lusaka','Northmead',     st_point(28.300,-15.400)::geography),
  ('Lusaka','Longacres',     st_point(28.312,-15.412)::geography),
  ('Lusaka','Chelston',      st_point(28.370,-15.370)::geography),
  ('Lusaka','Avondale',      st_point(28.355,-15.375)::geography),
  ('Lusaka','Meanwood',      st_point(28.330,-15.355)::geography),
  ('Lusaka','Chalala',       st_point(28.330,-15.470)::geography),
  ('Lusaka','Leopards Hill', st_point(28.390,-15.460)::geography),
  ('Lusaka','New Kasama',    st_point(28.400,-15.430)::geography),
  ('Lusaka','Makeni',        st_point(28.250,-15.460)::geography);
