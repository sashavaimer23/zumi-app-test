-- =====================================================================
--  Zumi — ВСЯ БАЗА ОДНИМ ФАЙЛОМ (файлы 001–015 подряд)
--
--  Как запустить: Supabase → SQL Editor → New query → вставить ВЕСЬ файл → Run.
--  Запускать один раз на новом, пустом проекте. Если что-то пошло не так —
--  пришлите текст ошибки (сам ключ service_role никому не отправляйте).
--
--  Что внутри: таблицы, защита (RLS), проверки, кабинет команды, реклама,
--  продвижение, помощь, статистика. Плюс демо-объявления для теста (003) —
--  перед запуском их удаляют: delete from public.properties where is_demo;
-- =====================================================================



-- #####################################################################
-- ##### 001_schema.sql
-- #####################################################################

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



-- #####################################################################
-- ##### 002_features.sql
-- #####################################################################

-- =====================================================================
--  Zumi — миграция 002: поля из макетов, лента объявлений, чаты
--  Запускать ПОСЛЕ 001_schema.sql
-- =====================================================================

-- ---------------------------------------------------------------------
-- 1. Дополнительные поля объявления (из экрана фильтров и постинга)
-- ---------------------------------------------------------------------
alter table public.properties alter column owner_id drop not null;   -- демо-объявления без владельца

alter table public.properties
  add column if not exists listed_by     text check (listed_by in ('agent','owner')),
  add column if not exists contact_name  text,
  add column if not exists contact_phone text,
  add column if not exists renovation    text check (renovation in ('cosmetic','designer','none')),
  add column if not exists kids_allowed  boolean,
  add column if not exists pets_allowed  boolean,
  add column if not exists lease_term    text check (lease_term in ('year','months'));

-- amenities: parking, furnished, garden, pool, ac, fridge, washing_machine,
--            dishwasher, internet, tv, garage

-- кто подаёт объявление (агент/собственник) — берём из профиля автоматически
create or replace function public.set_listed_by()
returns trigger language plpgsql security definer set search_path = public, extensions as $$
begin
  if new.owner_id is not null then
    select case when role = 'agent' then 'agent' else 'owner' end
      into new.listed_by from profiles where id = new.owner_id;
  end if;
  new.updated_at := now();
  return new;
end $$;

drop trigger if exists set_listed_by on public.properties;
create trigger set_listed_by
  before insert or update on public.properties
  for each row execute function public.set_listed_by();

-- районы: описание и фото для блока «Popular neighborhoods»
alter table public.areas
  add column if not exists tagline   text,
  add column if not exists image_url text;

-- ---------------------------------------------------------------------
-- 2. Лента объявлений: всё, что нужно карточке и карте, одним запросом
-- ---------------------------------------------------------------------
create or replace view public.property_feed
with (security_invoker = true) as
  select p.*,
         st_y(p.location::geometry) as lat,
         st_x(p.location::geometry) as lng,
         a.name  as area_name,
         a.city  as city,
         coalesce(p.promoted_until > now(), false) as is_promoted,
         coalesce(
           (select array_agg(i.url order by i.sort_order)
              from property_images i where i.property_id = p.id),
           '{}'::text[]) as image_urls
    from properties p
    left join areas a on a.id = p.area_id;

-- счётчик просмотров (может вызывать кто угодно, но только +1)
create or replace function public.increment_views(pid uuid)
returns void language sql security definer set search_path = public, extensions as $$
  update properties set views_count = views_count + 1 where id = pid and status = 'active';
$$;

-- квота текущего пользователя
create or replace function public.my_listing_quota()
returns table (used int, allowed int) language sql stable security definer
set search_path = public, extensions as $$
  select * from public.listing_quota(auth.uid());
$$;

-- ---------------------------------------------------------------------
-- 3. Чаты между покупателем/арендатором и автором объявления
-- ---------------------------------------------------------------------
create table if not exists public.conversations (
  id               uuid primary key default gen_random_uuid(),
  property_id      uuid references public.properties(id) on delete set null,
  buyer_id         uuid not null references public.profiles(id) on delete cascade,
  seller_id        uuid not null references public.profiles(id) on delete cascade,
  last_message     text,
  last_message_at  timestamptz not null default now(),
  created_at       timestamptz not null default now(),
  unique (property_id, buyer_id)
);

create table if not exists public.messages (
  id               uuid primary key default gen_random_uuid(),
  conversation_id  uuid not null references public.conversations(id) on delete cascade,
  sender_id        uuid not null references public.profiles(id) on delete cascade,
  body             text not null check (length(body) between 1 and 4000),
  created_at       timestamptz not null default now()
);
create index if not exists messages_conv_idx on public.messages (conversation_id, created_at);

alter table public.conversations enable row level security;
alter table public.messages      enable row level security;

create policy "participants read conversations" on public.conversations for select
  using (auth.uid() in (buyer_id, seller_id));

create policy "participants read messages" on public.messages for select
  using (exists (select 1 from conversations c
                  where c.id = conversation_id and auth.uid() in (c.buyer_id, c.seller_id)));

create policy "participants send messages" on public.messages for insert
  with check (sender_id = auth.uid() and exists (
    select 1 from conversations c
     where c.id = conversation_id and auth.uid() in (c.buyer_id, c.seller_id)));

-- начать (или открыть существующий) чат по объявлению
create or replace function public.start_conversation(pid uuid)
returns uuid language plpgsql security definer set search_path = public, extensions as $$
declare v_seller uuid; v_id uuid;
begin
  if auth.uid() is null then raise exception 'NOT_AUTHENTICATED'; end if;
  select owner_id into v_seller from properties where id = pid;
  if v_seller is null then raise exception 'NO_OWNER'; end if;          -- демо-объявление
  if v_seller = auth.uid() then raise exception 'OWN_LISTING'; end if;

  select id into v_id from conversations where property_id = pid and buyer_id = auth.uid();
  if v_id is null then
    insert into conversations (property_id, buyer_id, seller_id)
    values (pid, auth.uid(), v_seller) returning id into v_id;
  end if;
  return v_id;
end $$;

-- последнее сообщение в списке чатов
create or replace function public.touch_conversation()
returns trigger language plpgsql security definer set search_path = public, extensions as $$
begin
  update conversations set last_message = left(new.body, 200), last_message_at = new.created_at
   where id = new.conversation_id;
  return new;
end $$;

drop trigger if exists on_message_created on public.messages;
create trigger on_message_created
  after insert on public.messages
  for each row execute function public.touch_conversation();

-- список чатов с данными собеседника и объявления
create or replace view public.conversation_list
with (security_invoker = true) as
  select c.*,
         p.title as property_title,
         (select url from property_images i where i.property_id = p.id order by sort_order limit 1) as property_cover,
         case when c.buyer_id = auth.uid() then s.full_name else b.full_name end as other_name
    from conversations c
    left join properties p on p.id = c.property_id
    left join profiles  b on b.id = c.buyer_id
    left join profiles  s on s.id = c.seller_id;

-- сообщения приходят в приложение мгновенно (Realtime)
alter publication supabase_realtime add table public.messages;

-- ---------------------------------------------------------------------
-- 4. Лимит действует и при повторной публикации (sold/archived → active)
-- ---------------------------------------------------------------------
create or replace function public.enforce_listing_limit()
returns trigger language plpgsql security definer set search_path = public, extensions as $$
declare q record;
begin
  if new.is_demo or new.owner_id is null then return new; end if;
  if tg_op = 'UPDATE' and not (new.status in ('active','draft')
                               and old.status not in ('active','draft')) then
    return new;
  end if;
  select * into q from public.listing_quota(new.owner_id);
  if q.used >= q.allowed then
    raise exception 'LISTING_LIMIT_REACHED' using hint = 'Buy an extra listing slot';
  end if;
  return new;
end $$;

drop trigger if exists check_listing_limit_update on public.properties;
create trigger check_listing_limit_update
  before update of status on public.properties
  for each row execute function public.enforce_listing_limit();

-- ---------------------------------------------------------------------
-- 5. Защита платных полей: из приложения их изменить нельзя,
--    только сервером (SQL Editor, Edge Function с service key, функции security definer)
-- ---------------------------------------------------------------------
create or replace function public.protect_profile_fields()
returns trigger language plpgsql as $$
begin
  if current_user in ('authenticated', 'anon') then
    new.role := old.role;
    new.extra_listing_slots := old.extra_listing_slots;
    new.is_verified := old.is_verified;
  end if;
  return new;
end $$;

drop trigger if exists protect_profile_fields on public.profiles;
create trigger protect_profile_fields
  before update on public.profiles
  for each row execute function public.protect_profile_fields();

create or replace function public.protect_property_fields()
returns trigger language plpgsql as $$
begin
  if current_user in ('authenticated', 'anon') then
    if tg_op = 'INSERT' then
      new.promoted_until := null;
      new.is_demo := false;
      new.views_count := 0;
    else
      new.promoted_until := old.promoted_until;
      new.is_demo := old.is_demo;
      new.views_count := old.views_count;
      new.owner_id := old.owner_id;
    end if;
  end if;
  return new;
end $$;

drop trigger if exists protect_property_fields on public.properties;
create trigger protect_property_fields
  before insert or update on public.properties
  for each row execute function public.protect_property_fields();



-- #####################################################################
-- ##### 003_demo_seed.sql
-- #####################################################################

-- =====================================================================
--  Zumi — 003: демо-объявления (is_demo = true). Запускать после 002.
--  Удалить все демо одной командой:  delete from public.properties where is_demo;
--  Фото демо лежат в приложении (asset:...). Реальные фото — в Storage.
-- =====================================================================

update public.areas set tagline = 'Leafy streets & top schools', image_url = 'asset:area_kabulonga.jpg' where city = 'Lusaka' and name = 'Kabulonga';
update public.areas set tagline = 'Central, calm and green', image_url = 'asset:area_woodlands.jpg' where city = 'Lusaka' and name = 'Woodlands';
update public.areas set tagline = 'Vibrant community & city access', image_url = 'asset:area_roma.jpg' where city = 'Lusaka' and name = 'Roma';
update public.areas set tagline = 'Modern homes & green spaces', image_url = 'asset:area_ibex_hill.jpg' where city = 'Lusaka' and name = 'Ibex Hill';
update public.areas set tagline = 'Walk to everything', image_url = 'asset:area_rhodes_park.jpg' where city = 'Lusaka' and name = 'Rhodes Park';
update public.areas set tagline = 'Close to UNZA & malls', image_url = 'asset:area_olympia.jpg' where city = 'Lusaka' and name = 'Olympia';
update public.areas set tagline = 'Shops, cafes and nightlife', image_url = 'asset:area_northmead.jpg' where city = 'Lusaka' and name = 'Northmead';
update public.areas set tagline = 'Business district living', image_url = 'asset:area_longacres.jpg' where city = 'Lusaka' and name = 'Longacres';
update public.areas set tagline = 'Affordable family homes', image_url = 'asset:area_chelston.jpg' where city = 'Lusaka' and name = 'Chelston';
update public.areas set tagline = 'Quiet residential area', image_url = 'asset:area_avondale.jpg' where city = 'Lusaka' and name = 'Avondale';
update public.areas set tagline = 'Peaceful living and family-friendly', image_url = 'asset:area_meanwood.jpg' where city = 'Lusaka' and name = 'Meanwood';
update public.areas set tagline = 'Growing suburb, great value', image_url = 'asset:area_chalala.jpg' where city = 'Lusaka' and name = 'Chalala';
update public.areas set tagline = 'Big plots and views', image_url = 'asset:area_leopards_hill.jpg' where city = 'Lusaka' and name = 'Leopards Hill';
update public.areas set tagline = 'New developments', image_url = 'asset:area_new_kasama.jpg' where city = 'Lusaka' and name = 'New Kasama';
update public.areas set tagline = 'Space to build', image_url = 'asset:area_makeni.jpg' where city = 'Lusaka' and name = 'Makeni';

insert into public.properties (id, title, description, deal_type, property_type, price, currency, rent_period, bedrooms, bathrooms, area_sqm, plot_sqm, amenities, area_id, address, location, status, promoted_until, listed_by, contact_name, contact_phone, renovation, kids_allowed, pets_allowed, lease_term, views_count, created_at, is_demo) values
  ('00000000-0000-0000-0000-00000000d000', 'Cosy family house', 'Bright 3-bedroom family house in a quiet gated street of Ibex Hill. Fitted kitchen, borehole, solar backup and a private garden.', 'rent', 'house', 45000, 'ZMW', 'month', 3, 2, 70.8, null, array['parking','garden','ac']::text[], (select id from public.areas where city='Lusaka' and name='Ibex Hill'), 'The 3rd street', st_point(28.367181,-15.445586)::geography, 'active', now() + interval '30 days', 'agent', 'Zumi Realty', '+260 97 000 0000', 'designer', true, false, 'year', 353, '2026-10-20T10:00:00Z', true),
  ('00000000-0000-0000-0000-00000000d001', 'Cosy apartment', 'Modern 2-bedroom apartment with open-plan living area, fibre internet and secure parking.', 'rent', 'apartment', 40000, 'ZMW', 'month', 2, 1, 65.8, null, array['parking','furnished','ac','internet']::text[], (select id from public.areas where city='Lusaka' and name='Ibex Hill'), 'The 2nd street', st_point(28.362773,-15.43486)::geography, 'active', now() + interval '30 days', 'agent', 'Zumi Realty', '+260 97 000 0001', 'designer', true, true, 'year', 68, '2026-10-19T10:00:00Z', true),
  ('00000000-0000-0000-0000-00000000d002', 'Commercial for rent', 'Warehouse / showroom space on the main road with loading area and parking.', 'rent', 'commercial', 38000, 'ZMW', 'month', null, 1, 65.8, null, array['parking']::text[], (select id from public.areas where city='Lusaka' and name='Meanwood'), 'The Meanwood road', st_point(28.327851,-15.362072)::geography, 'active', null, 'agent', 'Zumi Realty', '+260 97 000 0002', 'cosmetic', null, null, 'year', 279, '2026-10-18T10:00:00Z', true),
  ('00000000-0000-0000-0000-00000000d003', 'Modern 3 bedroom house in Ibex Hill', 'Newly built 3-bedroom house with en-suite master bedroom and covered veranda.', 'rent', 'house', 45000, 'ZMW', 'month', 3, 2, 68, null, array['parking','garden']::text[], (select id from public.areas where city='Lusaka' and name='Ibex Hill'), 'Bishops road', st_point(28.365435,-15.446625)::geography, 'active', null, 'owner', 'Private owner', '+260 97 000 0003', 'designer', true, true, 'year', 234, '2026-10-17T10:00:00Z', true),
  ('00000000-0000-0000-0000-00000000d004', 'Contemporary townhouse', 'Double-storey townhouse with balcony, double garage and landscaped garden.', 'sale', 'house', 2850000, 'ZMW', null, 4, 3, 210, null, array['parking','garden','garage','ac']::text[], (select id from public.areas where city='Lusaka' and name='Roma'), 'Kasama road', st_point(28.303118,-15.376549)::geography, 'active', now() + interval '30 days', 'agent', 'Zumi Realty', '+260 97 000 0004', 'designer', null, null, null, 237, '2026-10-16T10:00:00Z', true),
  ('00000000-0000-0000-0000-00000000d005', 'Family home with big garden', 'Spacious 5-bedroom home on a large plot, swimming pool and staff quarters.', 'sale', 'house', 4200000, 'ZMW', null, 5, 4, 320, 1800, array['parking','garden','pool','garage']::text[], (select id from public.areas where city='Lusaka' and name='Kabulonga'), 'Ngwee road', st_point(28.327946,-15.423953)::geography, 'active', null, 'agent', 'Zumi Realty', '+260 97 000 0005', 'designer', null, null, null, 134, '2026-10-15T10:00:00Z', true),
  ('00000000-0000-0000-0000-00000000d006', 'Furnished apartment, daily', 'Fully furnished 1-bedroom apartment for short stays. Wi-Fi and Netflix included.', 'rent', 'apartment', 1500, 'ZMW', 'day', 1, 1, 48, null, array['furnished','ac','internet','tv','fridge','washing_machine']::text[], (select id from public.areas where city='Lusaka' and name='Rhodes Park'), 'Lagos road', st_point(28.30709,-15.403672)::geography, 'active', null, 'owner', 'Private owner', '+260 97 000 0006', 'designer', true, false, 'months', 51, '2026-10-14T10:00:00Z', true),
  ('00000000-0000-0000-0000-00000000d007', '3 bedroom house near Arcades', 'Comfortable family house close to Arcades and schools.', 'rent', 'house', 18000, 'ZMW', 'month', 3, 2, 120, null, array['parking','garden']::text[], (select id from public.areas where city='Lusaka' and name='Woodlands'), 'Kabelenga road', st_point(28.321234,-15.436653)::geography, 'active', null, 'owner', 'Private owner', '+260 97 000 0007', 'cosmetic', true, true, 'year', 133, '2026-10-13T10:00:00Z', true),
  ('00000000-0000-0000-0000-00000000d008', 'Residential plot, 2000 m²', 'Title-deeded residential plot with water and electricity nearby.', 'sale', 'land', 650000, 'ZMW', null, null, null, null, 2000, '{}'::text[], (select id from public.areas where city='Lusaka' and name='Leopards Hill'), 'Leopards Hill road', st_point(28.382745,-15.454265)::geography, 'active', null, 'agent', 'Zumi Realty', '+260 97 000 0008', null, null, null, null, 168, '2026-10-12T10:00:00Z', true),
  ('00000000-0000-0000-0000-00000000d009', '2 bedroom flat', 'Affordable 2-bedroom flat in a secure complex.', 'rent', 'apartment', 9500, 'ZMW', 'month', 2, 1, 70, null, array['parking']::text[], (select id from public.areas where city='Lusaka' and name='Chalala'), 'Chalala main road', st_point(28.328706,-15.469349)::geography, 'active', null, 'owner', 'Private owner', '+260 97 000 0009', 'none', true, true, 'year', 312, '2026-10-11T10:00:00Z', true),
  ('00000000-0000-0000-0000-00000000d00a', '4 bedroom house', 'Solid 4-bedroom house with borehole and solar geyser.', 'sale', 'house', 1950000, 'ZMW', null, 4, 3, 190, 900, array['parking','garden','garage']::text[], (select id from public.areas where city='Lusaka' and name='Meanwood'), 'Mutumbi road', st_point(28.326936,-15.349942)::geography, 'active', null, 'agent', 'Zumi Realty', '+260 97 000 0010', 'cosmetic', null, null, null, 112, '2026-10-10T10:00:00Z', true),
  ('00000000-0000-0000-0000-00000000d00b', 'Roma Park apartment', '3-bedroom apartment in Roma Park, gym and 24/7 security.', 'rent', 'apartment', 22000, 'ZMW', 'month', 3, 2, 110, null, array['parking','ac','internet','dishwasher']::text[], (select id from public.areas where city='Lusaka' and name='Roma'), 'Roma Park', st_point(28.303649,-15.368861)::geography, 'active', null, 'agent', 'Zumi Realty', '+260 97 000 0011', 'designer', true, false, 'year', 116, '2026-10-09T10:00:00Z', true),
  ('00000000-0000-0000-0000-00000000d00c', 'Office space', 'Open-plan office with meeting room, close to UNZA.', 'rent', 'commercial', 30000, 'ZMW', 'month', null, 2, 140, null, array['parking','internet','ac']::text[], (select id from public.areas where city='Lusaka' and name='Olympia'), 'Great East road', st_point(28.307958,-15.384236)::geography, 'active', null, 'agent', 'Zumi Realty', '+260 97 000 0012', 'cosmetic', null, null, 'year', 52, '2026-10-08T10:00:00Z', true),
  ('00000000-0000-0000-0000-00000000d00d', 'Plot in Makeni', 'Residential plot in a fast-growing area.', 'sale', 'land', 250000, 'ZMW', null, null, null, null, 1200, '{}'::text[], (select id from public.areas where city='Lusaka' and name='Makeni'), 'Makeni', st_point(28.25103,-15.458096)::geography, 'active', null, 'owner', 'Private owner', '+260 97 000 0013', null, null, null, null, 274, '2026-10-07T10:00:00Z', true),
  ('00000000-0000-0000-0000-00000000d00e', 'Starter house in New Kasama', 'Neat 3-bedroom house, newly painted.', 'rent', 'house', 12000, 'ZMW', 'month', 3, 1, 95, null, array['parking']::text[], (select id from public.areas where city='Lusaka' and name='New Kasama'), 'New Kasama', st_point(28.402886,-15.431159)::geography, 'active', null, 'owner', 'Private owner', '+260 97 000 0014', 'cosmetic', true, true, 'year', 180, '2026-10-06T10:00:00Z', true),
  ('00000000-0000-0000-0000-00000000d00f', 'Chelston bungalow', '2-bedroom bungalow, ideal first home or rental investment.', 'sale', 'house', 900000, 'ZMW', null, 2, 1, 85, 600, array['garden']::text[], (select id from public.areas where city='Lusaka' and name='Chelston'), 'Chelston', st_point(28.36945,-15.363225)::geography, 'active', null, 'owner', 'Private owner', '+260 97 000 0015', 'none', null, null, null, 205, '2026-10-05T10:00:00Z', true),
  ('00000000-0000-0000-0000-00000000d010', 'Luxury villa with pool', 'Executive 5-bedroom villa with pool, fully furnished.', 'rent', 'house', 75000, 'ZMW', 'month', 5, 5, 400, 2500, array['parking','garden','pool','garage','furnished','ac','internet']::text[], (select id from public.areas where city='Lusaka' and name='Kabulonga'), 'Kabulonga road', st_point(28.331796,-15.42029)::geography, 'active', now() + interval '30 days', 'agent', 'Zumi Realty', '+260 97 000 0016', 'designer', true, true, 'year', 377, '2026-10-04T10:00:00Z', true),
  ('00000000-0000-0000-0000-00000000d011', 'Northmead 1 bedroom', 'Compact 1-bedroom flat near shops and cafes.', 'rent', 'apartment', 7000, 'ZMW', 'month', 1, 1, 45, null, array['internet']::text[], (select id from public.areas where city='Lusaka' and name='Northmead'), 'Northmead', st_point(28.304477,-15.40669)::geography, 'active', null, 'owner', 'Private owner', '+260 97 000 0017', 'cosmetic', false, false, 'months', 173, '2026-10-03T10:00:00Z', true)
on conflict (id) do nothing;

insert into public.property_images (property_id, url, sort_order) values
  ('00000000-0000-0000-0000-00000000d000', 'asset:p1.jpg', 0),
  ('00000000-0000-0000-0000-00000000d000', 'asset:p6.jpg', 1),
  ('00000000-0000-0000-0000-00000000d001', 'asset:p2.jpg', 0),
  ('00000000-0000-0000-0000-00000000d001', 'asset:p7.jpg', 1),
  ('00000000-0000-0000-0000-00000000d002', 'asset:p3.jpg', 0),
  ('00000000-0000-0000-0000-00000000d003', 'asset:p6.jpg', 0),
  ('00000000-0000-0000-0000-00000000d003', 'asset:p1.jpg', 1),
  ('00000000-0000-0000-0000-00000000d004', 'asset:p4.jpg', 0),
  ('00000000-0000-0000-0000-00000000d004', 'asset:n2.jpg', 1),
  ('00000000-0000-0000-0000-00000000d005', 'asset:p5.jpg', 0),
  ('00000000-0000-0000-0000-00000000d005', 'asset:p4.jpg', 1),
  ('00000000-0000-0000-0000-00000000d006', 'asset:p7.jpg', 0),
  ('00000000-0000-0000-0000-00000000d007', 'asset:n1.jpg', 0),
  ('00000000-0000-0000-0000-00000000d007', 'asset:p1.jpg', 1),
  ('00000000-0000-0000-0000-00000000d008', 'asset:p5.jpg', 0),
  ('00000000-0000-0000-0000-00000000d009', 'asset:p6.jpg', 0),
  ('00000000-0000-0000-0000-00000000d00a', 'asset:n3.jpg', 0),
  ('00000000-0000-0000-0000-00000000d00a', 'asset:p4.jpg', 1),
  ('00000000-0000-0000-0000-00000000d00b', 'asset:n2.jpg', 0),
  ('00000000-0000-0000-0000-00000000d00b', 'asset:p2.jpg', 1),
  ('00000000-0000-0000-0000-00000000d00c', 'asset:p3.jpg', 0),
  ('00000000-0000-0000-0000-00000000d00d', 'asset:n1.jpg', 0),
  ('00000000-0000-0000-0000-00000000d00e', 'asset:p1.jpg', 0),
  ('00000000-0000-0000-0000-00000000d00f', 'asset:p4.jpg', 0),
  ('00000000-0000-0000-0000-00000000d010', 'asset:p5.jpg', 0),
  ('00000000-0000-0000-0000-00000000d010', 'asset:p7.jpg', 1),
  ('00000000-0000-0000-0000-00000000d011', 'asset:p2.jpg', 0);



-- #####################################################################
-- ##### 004_verification.sql
-- #####################################################################

-- =====================================================================
--  Zumi — 004: Verification (три уровня проверки) и жалобы
--  Запускать после 003.
--
--  ПЛАШКА «VERIFIED» = проверенный ЧЕЛОВЕК (собственник или агент):
--    • профиль заполнен (имя)
--    • телефон подтверждён SMS-кодом
--    • NRC/паспорт + селфи проверены (с согласием по Data Protection Act 2021)
--    • у агентов — номер лицензии ZIEA (Estate Agents Act No. 21 of 2000) сверен
--  Все объявления проверенного человека показывают плашку Verified.
--
--  Дополнительно (необязательно, для ещё большего доверия):
--    Property Verified  — 3 фото на месте + геолокация рядом с точкой (авто)
--    Ownership Verified — документы о собственности / мандат от владельца
--
--  Всё добровольно. Статусы меняют только сервер и команда Zumi.
-- =====================================================================

-- ---------------------------------------------------------------------
-- 1. Поля
-- ---------------------------------------------------------------------
alter table public.profiles
  add column if not exists phone_verified_at   timestamptz,  -- из Supabase Auth после SMS-кода
  add column if not exists id_verified_at      timestamptz,  -- документ + селфи проверены командой
  add column if not exists agent_licence_no    text,         -- номер регистрации ZIEA (агенты)
  add column if not exists licence_verified_at timestamptz;  -- номер сверен с реестром ZIEA

-- проверенный человек: телефон + документ (+ лицензия ZIEA у агентов)
create or replace function public.person_verified(uid uuid)
returns boolean language sql stable security definer set search_path = public, extensions as $$
  select pr.full_name is not null and length(trim(pr.full_name)) > 1
     and pr.phone_verified_at is not null
     and pr.id_verified_at is not null
     and (pr.role <> 'agent' or pr.licence_verified_at is not null)
    from profiles pr where pr.id = uid;
$$;

-- Приватность: телефон в профиле не виден другим пользователям
-- (контактный номер автор сам указывает в объявлении)
revoke select on public.profiles from anon, authenticated;
grant select (id, role, full_name, agency_name, avatar_url, is_verified, extra_listing_slots,
              phone_verified_at, id_verified_at, agent_licence_no, licence_verified_at, created_at)
  on public.profiles to anon, authenticated;

alter table public.properties
  add column if not exists property_verified_at   timestamptz,
  add column if not exists property_verify_method text check (property_verify_method in ('geo_photos','visit','video')),
  add column if not exists ownership_verified_at  timestamptz,
  add column if not exists confirmed_at           timestamptz,   -- автор подтвердил «ещё доступно»
  add column if not exists highlights             text,          -- «Gated street | Borehole | Solar»
  add column if not exists reports_count          int not null default 0;

-- ---------------------------------------------------------------------
-- 2. Телефон: когда пользователь вводит SMS-код, Supabase Auth ставит
--    auth.users.phone_confirmed_at — копируем это в профиль
-- ---------------------------------------------------------------------
create or replace function public.sync_phone_verified()
returns trigger language plpgsql security definer set search_path = public, extensions as $$
begin
  update profiles
     set phone = coalesce(new.phone, phone),
         phone_verified_at = new.phone_confirmed_at
   where id = new.id;
  return new;
end $$;

drop trigger if exists on_auth_phone_confirmed on auth.users;
create trigger on_auth_phone_confirmed
  after update of phone_confirmed_at on auth.users
  for each row when (new.phone_confirmed_at is not null)
  execute function public.sync_phone_verified();

-- ---------------------------------------------------------------------
-- 3. Заявки на проверку (документы и фото — в приватном хранилище)
-- ---------------------------------------------------------------------
create table if not exists public.verification_requests (
  id            uuid primary key default gen_random_uuid(),
  user_id       uuid not null references public.profiles(id) on delete cascade,
  property_id   uuid references public.properties(id) on delete cascade,
  kind          text not null check (kind in ('identity','ownership','property')),
  doc_paths     text[] not null default '{}',     -- пути в bucket 'verification-docs'
  doc_type      text check (doc_type in ('nrc','passport')),
  consent_at    timestamptz,                      -- согласие на обработку данных
  note          text,
  status        text not null default 'pending' check (status in ('pending','approved','rejected')),
  reviewer_note text,
  created_at    timestamptz not null default now(),
  reviewed_at   timestamptz
);
create index if not exists verification_requests_status_idx on public.verification_requests (status, created_at);

alter table public.verification_requests enable row level security;

create policy "own requests read" on public.verification_requests for select
  using (user_id = auth.uid());
create policy "own requests create" on public.verification_requests for insert
  with check (
    user_id = auth.uid() and status = 'pending' and kind in ('identity','ownership')
    and (kind <> 'identity' or consent_at is not null)
    and (property_id is null or exists (
      select 1 from properties p where p.id = property_id and p.owner_id = auth.uid()))
  );

-- ---------------------------------------------------------------------
-- 4. Property Verified автоматически: фото на месте + геолокация
--    Возвращает {"verified": true/false, "distance_m": 120}
-- ---------------------------------------------------------------------
create or replace function public.submit_property_check(
  pid uuid, dev_lat double precision, dev_lng double precision, photo_paths text[]
)
returns jsonb language plpgsql security definer set search_path = public, extensions as $$
declare v_loc geography; v_dist double precision; v_ok boolean;
begin
  if auth.uid() is null then raise exception 'NOT_AUTHENTICATED'; end if;
  select location into v_loc from properties where id = pid and owner_id = auth.uid();
  if v_loc is null then raise exception 'NOT_YOUR_LISTING'; end if;
  if coalesce(array_length(photo_paths, 1), 0) < 3 then raise exception 'NEED_3_PHOTOS'; end if;

  v_dist := st_distance(v_loc, st_point(dev_lng, dev_lat)::geography);
  v_ok := v_dist <= 300;   -- в пределах 300 м от точки объявления

  insert into verification_requests (user_id, property_id, kind, doc_paths, status, note, reviewed_at)
  values (auth.uid(), pid, 'property', photo_paths,
          case when v_ok then 'approved' else 'rejected' end,
          format('Auto geo-check: %s m from the pin', round(v_dist)), now());

  if v_ok then
    update properties set property_verified_at = now(), property_verify_method = 'geo_photos'
     where id = pid;
  end if;
  return jsonb_build_object('verified', v_ok, 'distance_m', round(v_dist));
end $$;

-- лицензия агента сверена с реестром ZIEA (вызывает команда Zumi)
create or replace function public.approve_licence(uid uuid)
returns void language sql security definer set search_path = public, extensions as $$
  update profiles set licence_verified_at = now() where id = uid and agent_licence_no is not null;
$$;
revoke execute on function public.approve_licence(uuid) from public, anon, authenticated;

-- ---------------------------------------------------------------------
-- 5. Одобрение заявки командой Zumi (из SQL Editor):
--    select approve_verification('<id заявки>');            -- identity / ownership
--    select approve_verification('<id заявки>', 'visit');   -- property после визита
-- ---------------------------------------------------------------------
create or replace function public.approve_verification(rid uuid, method text default 'visit')
returns void language plpgsql security definer set search_path = public, extensions as $$
declare r record;
begin
  select * into r from verification_requests where id = rid;
  if r is null then raise exception 'REQUEST_NOT_FOUND'; end if;
  update verification_requests set status = 'approved', reviewed_at = now() where id = rid;
  if r.kind = 'identity' then
    update profiles set id_verified_at = now(), is_verified = true where id = r.user_id;
  elsif r.kind = 'ownership' then
    update properties set ownership_verified_at = now() where id = r.property_id;
  else
    update properties set property_verified_at = now(), property_verify_method = method
     where id = r.property_id;
  end if;
end $$;

revoke execute on function public.approve_verification(uuid, text) from public, anon, authenticated;

-- ---------------------------------------------------------------------
-- 6. Жалобы на объявления
-- ---------------------------------------------------------------------
create table if not exists public.listing_reports (
  id           uuid primary key default gen_random_uuid(),
  property_id  uuid not null references public.properties(id) on delete cascade,
  reporter_id  uuid references public.profiles(id) on delete set null,
  reason       text not null check (reason in
                 ('scam','asked_prepayment','not_available','wrong_info','duplicate','other')),
  details      text,
  status       text not null default 'new' check (status in ('new','reviewed','action_taken')),
  created_at   timestamptz not null default now(),
  unique (property_id, reporter_id)
);

alter table public.listing_reports enable row level security;
create policy "signed-in users report" on public.listing_reports for insert
  with check (reporter_id = auth.uid());
create policy "own reports read" on public.listing_reports for select
  using (reporter_id = auth.uid());

-- 3 жалобы на мошенничество → объявление скрывается до проверки
create or replace function public.on_listing_report()
returns trigger language plpgsql security definer set search_path = public, extensions as $$
begin
  update properties set reports_count = reports_count + 1 where id = new.property_id;
  if (select count(*) from listing_reports
       where property_id = new.property_id and reason in ('scam','asked_prepayment')) >= 3 then
    update properties set status = 'archived', property_verified_at = null where id = new.property_id;
  end if;
  return new;
end $$;

drop trigger if exists on_listing_report on public.listing_reports;
create trigger on_listing_report
  after insert on public.listing_reports
  for each row execute function public.on_listing_report();

-- автор подтверждает «объект ещё доступен»
create or replace function public.confirm_listing(pid uuid)
returns void language sql security definer set search_path = public, extensions as $$
  update properties set confirmed_at = now()
   where id = pid and owner_id = auth.uid() and status = 'active';
$$;

-- ---------------------------------------------------------------------
-- 7. Защита: пользователь не может сам поставить себе «Verified»
-- ---------------------------------------------------------------------
create or replace function public.protect_verification_fields()
returns trigger language plpgsql as $$
begin
  if current_user in ('authenticated', 'anon') then
    if tg_op = 'INSERT' then
      new.property_verified_at := null; new.property_verify_method := null;
      new.ownership_verified_at := null; new.reports_count := 0; new.confirmed_at := now();
    else
      new.property_verified_at := old.property_verified_at;
      new.property_verify_method := old.property_verify_method;
      new.ownership_verified_at := old.ownership_verified_at;
      new.reports_count := old.reports_count;
      new.confirmed_at := old.confirmed_at;
      -- если автор сдвинул точку на карте — проверку объекта нужно пройти заново
      if new.location is distinct from old.location then
        new.property_verified_at := null; new.property_verify_method := null;
      end if;
    end if;
  end if;
  return new;
end $$;

drop trigger if exists protect_verification_fields on public.properties;
create trigger protect_verification_fields
  before insert or update on public.properties
  for each row execute function public.protect_verification_fields();

create or replace function public.protect_profile_verification()
returns trigger language plpgsql as $$
begin
  if current_user in ('authenticated', 'anon') then
    new.phone_verified_at := old.phone_verified_at;
    new.id_verified_at := old.id_verified_at;
    new.licence_verified_at := old.licence_verified_at;
    -- сменил номер лицензии — нужна новая сверка
    if new.agent_licence_no is distinct from old.agent_licence_no then
      new.licence_verified_at := null;
    end if;
  end if;
  return new;
end $$;

drop trigger if exists protect_profile_verification on public.profiles;
create trigger protect_profile_verification
  before update on public.profiles
  for each row execute function public.protect_profile_verification();

-- ---------------------------------------------------------------------
-- 8. Лента с признаками проверки
-- ---------------------------------------------------------------------
drop view if exists public.property_feed;
create view public.property_feed
with (security_invoker = true) as
  select p.*,
         st_y(p.location::geometry) as lat,
         st_x(p.location::geometry) as lng,
         a.name  as area_name,
         a.city  as city,
         coalesce(p.promoted_until > now(), false)  as is_promoted,
         (p.property_verified_at is not null)       as property_verified,
         (p.ownership_verified_at is not null)      as ownership_verified,
         (pr.phone_verified_at is not null)         as owner_phone_verified,
         -- плашка Verified; демо-объявления агентов считаем проверенными для показа
         coalesce(public.person_verified(p.owner_id), p.is_demo and p.listed_by = 'agent') as owner_identity_verified,
         pr.full_name   as owner_name,
         pr.agency_name as agency_name,
         coalesce(
           (select array_agg(i.url order by i.sort_order)
              from property_images i where i.property_id = p.id),
           '{}'::text[]) as image_urls
    from properties p
    left join areas a     on a.id  = p.area_id
    left join profiles pr on pr.id = p.owner_id;

-- ---------------------------------------------------------------------
-- 9. Приватное хранилище документов и проверочных фото
-- ---------------------------------------------------------------------
insert into storage.buckets (id, name, public) values ('verification-docs','verification-docs', false)
  on conflict do nothing;

create policy "upload own verification docs" on storage.objects for insert to authenticated
  with check (bucket_id = 'verification-docs' and (storage.foldername(name))[1] = auth.uid()::text);
create policy "read own verification docs" on storage.objects for select to authenticated
  using (bucket_id = 'verification-docs' and (storage.foldername(name))[1] = auth.uid()::text);

-- ---------------------------------------------------------------------
-- 10. Демо: часть демо-объявлений отмечаем как проверенные
-- ---------------------------------------------------------------------
update public.properties set confirmed_at = now() - interval '2 days' where is_demo;

update public.properties set highlights = 'Gated street | Borehole | Solar backup'
 where is_demo and title = 'Cosy family house';
update public.properties set highlights = 'Fibre internet | Secure parking'
 where is_demo and title = 'Cosy apartment';
update public.properties set highlights = 'Pool | Fully furnished | Big garden'
 where is_demo and title = 'Luxury villa with pool';
update public.properties set highlights = 'Double garage | Balcony'
 where is_demo and title = 'Contemporary townhouse';
update public.properties set highlights = 'Pool | Staff quarters | Big plot'
 where is_demo and title = 'Family home with big garden';



-- #####################################################################
-- ##### 005_admin.sql
-- #####################################################################

-- =====================================================================
--  Zumi — 005: кабинет команды поддержки
--  Роль admin, обращения в поддержку, отзывы об авторах, блокировка,
--  журнал действий. Запускать после 004.
--
--  Сделать себя администратором (один раз, в SQL Editor):
--    update public.profiles set role = 'admin'
--     where id = (select id from auth.users where email = 'you@example.com');
-- =====================================================================

-- ---------------------------------------------------------------------
-- 1. Кто администратор
-- ---------------------------------------------------------------------
create or replace function public.is_admin()
returns boolean language sql stable security definer set search_path = public, extensions as $$
  select exists (select 1 from profiles where id = auth.uid() and role = 'admin');
$$;

alter table public.profiles
  add column if not exists banned_at  timestamptz,
  add column if not exists ban_reason text;

grant select (banned_at) on public.profiles to authenticated;

-- заблокированный пользователь не может публиковать объявления
create or replace function public.block_banned_posting()
returns trigger language plpgsql security definer set search_path = public, extensions as $$
begin
  if new.owner_id is not null and exists (select 1 from profiles where id = new.owner_id and banned_at is not null) then
    raise exception 'ACCOUNT_BLOCKED';
  end if;
  return new;
end $$;

drop trigger if exists block_banned_posting on public.properties;
create trigger block_banned_posting
  before insert on public.properties
  for each row execute function public.block_banned_posting();

-- ---------------------------------------------------------------------
-- 2. Журнал действий команды
-- ---------------------------------------------------------------------
create table if not exists public.admin_audit (
  id          bigserial primary key,
  admin_id    uuid references public.profiles(id),
  action      text not null,
  target_type text not null,
  target_id   text not null,
  note        text,
  created_at  timestamptz not null default now()
);
alter table public.admin_audit enable row level security;
create policy "admins read audit" on public.admin_audit for select using (public.is_admin());

create or replace function public._audit(p_action text, p_type text, p_target text, p_note text)
returns void language sql security definer set search_path = public, extensions as $$
  insert into admin_audit (admin_id, action, target_type, target_id, note)
  values (auth.uid(), p_action, p_type, p_target, p_note);
$$;
revoke execute on function public._audit(text, text, text, text) from public, anon, authenticated;

-- ---------------------------------------------------------------------
-- 3. Админу видно всё нужное для проверки
-- ---------------------------------------------------------------------
create policy "admins read requests" on public.verification_requests for select using (public.is_admin());
create policy "admins read reports"  on public.listing_reports      for select using (public.is_admin());
create policy "admins read all props" on public.properties          for select using (public.is_admin());
create policy "admins read docs" on storage.objects for select to authenticated
  using (bucket_id = 'verification-docs' and public.is_admin());

-- ---------------------------------------------------------------------
-- 4. Обращения в поддержку
-- ---------------------------------------------------------------------
create table if not exists public.support_tickets (
  id              uuid primary key default gen_random_uuid(),
  user_id         uuid not null references public.profiles(id) on delete cascade,
  category        text not null default 'question'
                    check (category in ('question','problem','scam','payment','account','other')),
  subject         text not null check (length(subject) between 2 and 140),
  status          text not null default 'open' check (status in ('open','answered','closed')),
  property_id     uuid references public.properties(id) on delete set null,
  last_message    text,
  last_message_at timestamptz not null default now(),
  created_at      timestamptz not null default now()
);

create table if not exists public.support_messages (
  id          uuid primary key default gen_random_uuid(),
  ticket_id   uuid not null references public.support_tickets(id) on delete cascade,
  sender_id   uuid not null references public.profiles(id) on delete cascade,
  is_staff    boolean not null default false,
  body        text not null check (length(body) between 1 and 4000),
  created_at  timestamptz not null default now()
);
create index if not exists support_messages_ticket_idx on public.support_messages (ticket_id, created_at);

alter table public.support_tickets  enable row level security;
alter table public.support_messages enable row level security;

create policy "own or admin tickets read" on public.support_tickets for select
  using (user_id = auth.uid() or public.is_admin());
create policy "users open tickets" on public.support_tickets for insert
  with check (user_id = auth.uid() and status = 'open');

create policy "ticket messages read" on public.support_messages for select
  using (public.is_admin() or exists (
    select 1 from support_tickets t where t.id = ticket_id and t.user_id = auth.uid()));
create policy "ticket messages write" on public.support_messages for insert
  with check (
    sender_id = auth.uid()
    and (
      (is_staff and public.is_admin())
      or (not is_staff and exists (
            select 1 from support_tickets t where t.id = ticket_id and t.user_id = auth.uid()))
    ));

-- новое сообщение обновляет обращение: ответ команды → 'answered', ответ пользователя → 'open'
create or replace function public.on_support_message()
returns trigger language plpgsql security definer set search_path = public, extensions as $$
begin
  update support_tickets
     set last_message = left(new.body, 200),
         last_message_at = new.created_at,
         status = case when new.is_staff then 'answered' else 'open' end
   where id = new.ticket_id;
  return new;
end $$;

drop trigger if exists on_support_message on public.support_messages;
create trigger on_support_message
  after insert on public.support_messages
  for each row execute function public.on_support_message();

alter publication supabase_realtime add table public.support_messages;

-- ---------------------------------------------------------------------
-- 5. Отзывы об агентах и собственниках
-- ---------------------------------------------------------------------
create table if not exists public.reviews (
  id           uuid primary key default gen_random_uuid(),
  target_id    uuid not null references public.profiles(id) on delete cascade,  -- о ком
  author_id    uuid not null references public.profiles(id) on delete cascade,  -- кто написал
  property_id  uuid references public.properties(id) on delete set null,
  rating       int  not null check (rating between 1 and 5),
  body         text check (length(body) <= 2000),
  status       text not null default 'published' check (status in ('published','hidden')),
  flags_count  int  not null default 0,          -- сколько раз пожаловались на отзыв
  zumi_reply   text,                             -- публичный ответ команды Zumi
  created_at   timestamptz not null default now(),
  unique (target_id, author_id),
  check (target_id <> author_id)
);
create index if not exists reviews_target_idx on public.reviews (target_id, created_at desc);

alter table public.reviews enable row level security;

create policy "published reviews readable" on public.reviews for select
  using (status = 'published' or author_id = auth.uid() or public.is_admin());
create policy "signed-in users write reviews" on public.reviews for insert
  with check (author_id = auth.uid() and status = 'published' and flags_count = 0 and zumi_reply is null);

-- пожаловаться на отзыв (после 3 жалоб отзыв скрывается до проверки)
create or replace function public.flag_review(rid uuid)
returns void language plpgsql security definer set search_path = public, extensions as $$
begin
  if auth.uid() is null then raise exception 'NOT_AUTHENTICATED'; end if;
  update reviews set flags_count = flags_count + 1,
                     status = case when flags_count + 1 >= 3 then 'hidden' else status end
   where id = rid;
end $$;

-- отзывы вместе с именем автора
create or replace view public.review_feed
with (security_invoker = true) as
  select r.*, a.full_name as author_name
    from reviews r left join profiles a on a.id = r.author_id;

-- рейтинг автора объявлений
create or replace function public.rating_of(uid uuid)
returns table (avg_rating numeric, reviews_count int) language sql stable security definer
set search_path = public, extensions as $$
  select round(avg(rating)::numeric, 1), count(*)::int
    from reviews where target_id = uid and status = 'published';
$$;

-- ---------------------------------------------------------------------
-- 6. Решения команды (все — только для admin, всё пишется в журнал)
-- ---------------------------------------------------------------------
create or replace function public.admin_stats()
returns jsonb language plpgsql stable security definer set search_path = public, extensions as $$
begin
  if not public.is_admin() then raise exception 'NOT_ADMIN'; end if;
  return jsonb_build_object(
    'id_checks',  (select count(*) from verification_requests where kind = 'identity'  and status = 'pending'),
    'ownership',  (select count(*) from verification_requests where kind = 'ownership' and status = 'pending'),
    'licences',   (select count(*) from profiles where agent_licence_no is not null and licence_verified_at is null),
    'reports',    (select count(*) from listing_reports where status = 'new'),
    'tickets',    (select count(*) from support_tickets where status = 'open'),
    'reviews',    (select count(*) from reviews where flags_count > 0 and status = 'published'),
    'listings',   (select count(*) from properties where status = 'active'),
    'users',      (select count(*) from profiles)
  );
end $$;

-- одобрить / отклонить заявку (identity / ownership / property)
create or replace function public.admin_review_verification(rid uuid, approve boolean, p_note text default null)
returns void language plpgsql security definer set search_path = public, extensions as $$
declare r record;
begin
  if not public.is_admin() then raise exception 'NOT_ADMIN'; end if;
  select * into r from verification_requests where id = rid;
  if r is null then raise exception 'REQUEST_NOT_FOUND'; end if;

  update verification_requests
     set status = case when approve then 'approved' else 'rejected' end,
         reviewer_note = p_note, reviewed_at = now(),
         doc_paths = case when approve then '{}' else doc_paths end   -- после одобрения ссылки на фото убираем
   where id = rid;

  if approve then
    if r.kind = 'identity' then
      update profiles set id_verified_at = now(), is_verified = true where id = r.user_id;
    elsif r.kind = 'ownership' then
      update properties set ownership_verified_at = now() where id = r.property_id;
    else
      update properties set property_verified_at = now(), property_verify_method = 'visit' where id = r.property_id;
    end if;
  end if;
  perform public._audit(case when approve then 'approve' else 'reject' end, r.kind, rid::text, p_note);
end $$;

-- лицензия ZIEA
create or replace function public.admin_review_licence(uid uuid, approve boolean, p_note text default null)
returns void language plpgsql security definer set search_path = public, extensions as $$
begin
  if not public.is_admin() then raise exception 'NOT_ADMIN'; end if;
  if approve then
    update profiles set licence_verified_at = now() where id = uid;
  else
    update profiles set agent_licence_no = null, licence_verified_at = null where id = uid;
  end if;
  perform public._audit(case when approve then 'approve' else 'reject' end, 'licence', uid::text, p_note);
end $$;

-- жалоба: 'dismiss' — всё в порядке, 'hide' — скрыть объявление, 'ban' — заблокировать автора
create or replace function public.admin_resolve_report(rep_id uuid, p_action text, p_note text default null)
returns void language plpgsql security definer set search_path = public, extensions as $$
declare v_prop uuid; v_owner uuid;
begin
  if not public.is_admin() then raise exception 'NOT_ADMIN'; end if;
  select property_id into v_prop from listing_reports where id = rep_id;
  if v_prop is null then raise exception 'REPORT_NOT_FOUND'; end if;
  select owner_id into v_owner from properties where id = v_prop;

  if p_action = 'dismiss' then
    update listing_reports set status = 'reviewed' where property_id = v_prop and status = 'new';
  elsif p_action = 'hide' then
    update properties set status = 'archived' where id = v_prop;
    update listing_reports set status = 'action_taken' where property_id = v_prop and status = 'new';
  elsif p_action = 'ban' then
    update listing_reports set status = 'action_taken' where property_id = v_prop and status = 'new';
    if v_owner is not null then
      update profiles set banned_at = now(), ban_reason = p_note where id = v_owner;
      update properties set status = 'archived' where owner_id = v_owner and status = 'active';
    else
      update properties set status = 'archived' where id = v_prop;
    end if;
  else
    raise exception 'UNKNOWN_ACTION';
  end if;
  perform public._audit(p_action, 'report', rep_id::text, p_note);
end $$;

-- вернуть объявление (если скрыли по ошибке) и снять блокировку
create or replace function public.admin_restore_listing(pid uuid)
returns void language plpgsql security definer set search_path = public, extensions as $$
begin
  if not public.is_admin() then raise exception 'NOT_ADMIN'; end if;
  update properties set status = 'active' where id = pid;
  perform public._audit('restore', 'listing', pid::text, null);
end $$;

create or replace function public.admin_unban(uid uuid)
returns void language plpgsql security definer set search_path = public, extensions as $$
begin
  if not public.is_admin() then raise exception 'NOT_ADMIN'; end if;
  update profiles set banned_at = null, ban_reason = null where id = uid;
  perform public._audit('unban', 'user', uid::text, null);
end $$;

-- обращения
create or replace function public.admin_set_ticket_status(tid uuid, new_status text)
returns void language plpgsql security definer set search_path = public, extensions as $$
begin
  if not public.is_admin() then raise exception 'NOT_ADMIN'; end if;
  update support_tickets set status = new_status where id = tid;
  perform public._audit(new_status, 'ticket', tid::text, null);
end $$;

-- отзывы: скрыть / вернуть / ответить от имени Zumi
create or replace function public.admin_moderate_review(rid uuid, p_action text, p_reply text default null)
returns void language plpgsql security definer set search_path = public, extensions as $$
begin
  if not public.is_admin() then raise exception 'NOT_ADMIN'; end if;
  if p_action = 'hide' then
    update reviews set status = 'hidden' where id = rid;
  elsif p_action = 'publish' then
    update reviews set status = 'published', flags_count = 0 where id = rid;
  elsif p_action = 'reply' then
    update reviews set zumi_reply = nullif(trim(p_reply), '') where id = rid;
  else
    raise exception 'UNKNOWN_ACTION';
  end if;
  perform public._audit(p_action, 'review', rid::text, p_reply);
end $$;

-- ---------------------------------------------------------------------
-- 7. Очереди для кабинета (видны только admin благодаря RLS)
-- ---------------------------------------------------------------------
create or replace view public.admin_verification_queue
with (security_invoker = true) as
  select v.*, pr.full_name as user_name, pr.role as user_role, pr.agent_licence_no,
         p.title as property_title
    from verification_requests v
    join profiles pr on pr.id = v.user_id
    left join properties p on p.id = v.property_id;

create or replace view public.admin_report_queue
with (security_invoker = true) as
  select r.*, rp.full_name as reporter_name,
         p.title as property_title, p.status as property_status, p.owner_id,
         o.full_name as owner_name,
         (select url from property_images i where i.property_id = p.id order by sort_order limit 1) as property_cover,
         (select count(*) from listing_reports r2 where r2.property_id = r.property_id)::int as total_reports
    from listing_reports r
    left join profiles rp on rp.id = r.reporter_id
    left join properties p on p.id = r.property_id
    left join profiles o on o.id = p.owner_id;

create or replace view public.ticket_feed
with (security_invoker = true) as
  select t.*, u.full_name as user_name
    from support_tickets t left join profiles u on u.id = t.user_id;

create or replace view public.admin_audit_feed
with (security_invoker = true) as
  select a.*, pr.full_name as admin_name
    from admin_audit a left join profiles pr on pr.id = a.admin_id;



-- #####################################################################
-- ##### 006_profiles_scale.sql
-- #####################################################################

-- =====================================================================
--  Zumi — 006: профили, правка объявлений, превью фото, удаление
--  аккаунта, «свежесть» объявлений, индексы для роста.
--  Запускать после 005 (SQL Editor → New query → вставить → Run).
-- =====================================================================

-- ---------------------------------------------------------------------
-- 0. Безопасность (исправления)
-- ---------------------------------------------------------------------
-- при регистрации можно выбрать только owner или agent (не admin)
create or replace function public.handle_new_user()
returns trigger language plpgsql security definer set search_path = public, extensions as $$
begin
  insert into public.profiles (id, full_name, phone, role)
  values (
    new.id,
    new.raw_user_meta_data->>'full_name',
    new.raw_user_meta_data->>'phone',
    case when new.raw_user_meta_data->>'role' = 'agent' then 'agent' else 'owner' end
  );
  return new;
end $$;

-- пользователь не может сам снять с себя блокировку
create or replace function public.protect_profile_fields()
returns trigger language plpgsql as $$
begin
  if current_user in ('authenticated', 'anon') then
    new.role := old.role;
    new.extra_listing_slots := old.extra_listing_slots;
    new.is_verified := old.is_verified;
    new.banned_at := old.banned_at;
    new.ban_reason := old.ban_reason;
  end if;
  return new;
end $$;

-- ---------------------------------------------------------------------
-- 1. Профиль: аватар, «о себе», рабочий WhatsApp (для агентов)
-- ---------------------------------------------------------------------
alter table public.profiles
  add column if not exists bio text check (bio is null or length(bio) <= 600);

-- avatar_url и whatsapp уже есть (001). Делаем их и bio видимыми всем:
-- это публичная страница агента. Личный телефон по-прежнему скрыт.
grant select (bio, whatsapp) on public.profiles to anon, authenticated;

-- публичные аватары
insert into storage.buckets (id, name, public) values ('avatars', 'avatars', true)
  on conflict do nothing;

drop policy if exists "public read avatars" on storage.objects;
create policy "public read avatars" on storage.objects for select
  using (bucket_id = 'avatars');
drop policy if exists "users upload own avatar" on storage.objects;
create policy "users upload own avatar" on storage.objects for insert to authenticated
  with check (bucket_id = 'avatars' and (storage.foldername(name))[1] = auth.uid()::text);
drop policy if exists "users delete own avatar" on storage.objects;
create policy "users delete own avatar" on storage.objects for delete to authenticated
  using (bucket_id = 'avatars' and (storage.foldername(name))[1] = auth.uid()::text);

-- свои документы проверки тоже можно удалить (при удалении аккаунта)
drop policy if exists "users delete own verification docs" on storage.objects;
create policy "users delete own verification docs" on storage.objects for delete to authenticated
  using (bucket_id = 'verification-docs' and (storage.foldername(name))[1] = auth.uid()::text);

-- публичная карточка человека (без телефона и документов)
create or replace function public.public_profile(uid uuid)
returns table (
  id uuid, role text, full_name text, agency_name text, avatar_url text, bio text,
  whatsapp text, verified boolean, phone_verified boolean, licence_verified boolean,
  member_since timestamptz, active_listings int
) language sql stable security definer set search_path = public, extensions as $$
  select pr.id, pr.role, pr.full_name, pr.agency_name, pr.avatar_url, pr.bio,
         case when pr.role = 'agent' then pr.whatsapp end,
         coalesce(public.person_verified(pr.id), false),
         pr.phone_verified_at is not null,
         pr.licence_verified_at is not null,
         pr.created_at,
         (select count(*) from properties p where p.owner_id = pr.id and p.status = 'active')::int
    from profiles pr
   where pr.id = uid and pr.banned_at is null;
$$;

-- ---------------------------------------------------------------------
-- 2. Превью фото (маленькая копия для карточек — экономит трафик)
-- ---------------------------------------------------------------------
alter table public.property_images add column if not exists thumb_url text;

-- ---------------------------------------------------------------------
-- 3. Лента: + аватар автора, превью фото, «свежесть»
--    Объявление без подтверждения «ещё доступно» дольше 60 дней
--    скрывается из поиска (автор видит его у себя и может подтвердить).
-- ---------------------------------------------------------------------
drop view if exists public.property_feed;
create view public.property_feed
with (security_invoker = true) as
  select p.*,
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
    left join profiles pr on pr.id = p.owner_id;

-- счётчики по районам — только живые объявления (+ общий итог в конце)
create or replace view public.area_stats as
  select a.id, a.city, a.name,
         st_y(a.center::geometry) as lat, st_x(a.center::geometry) as lng,
         count(p.id) filter (where p.deal_type = 'sale') as for_sale,
         count(p.id) filter (where p.deal_type = 'rent') as for_rent,
         round(avg(p.price) filter (where p.deal_type = 'rent' and p.currency = 'ZMW')) as avg_rent_zmw,
         count(p.id) as listings_count
    from areas a
    left join properties p on p.area_id = a.id and p.status = 'active'
         and (p.is_demo or coalesce(p.confirmed_at, p.created_at) > now() - interval '60 days')
   group by a.id;

-- правка объявления автором = объявление актуально
create or replace function public.touch_listing(pid uuid)
returns void language sql security definer set search_path = public, extensions as $$
  update properties set confirmed_at = now(), updated_at = now()
   where id = pid and owner_id = auth.uid();
$$;

-- подтверждать можно и «скрытое за давностью» объявление
create or replace function public.confirm_listing(pid uuid)
returns void language sql security definer set search_path = public, extensions as $$
  update properties set confirmed_at = now()
   where id = pid and owner_id = auth.uid() and status = 'active';
$$;

-- ---------------------------------------------------------------------
-- 4. Удаление аккаунта (Google Play / App Store + Data Protection Act)
--    Платежи остаются в учёте, но без привязки к человеку.
-- ---------------------------------------------------------------------
alter table public.payments   alter column user_id drop not null;
alter table public.promotions alter column user_id drop not null;

alter table public.payments   drop constraint if exists payments_user_id_fkey;
alter table public.payments   add  constraint payments_user_id_fkey
  foreign key (user_id) references public.profiles(id) on delete set null;
alter table public.payments   drop constraint if exists payments_property_id_fkey;
alter table public.payments   add  constraint payments_property_id_fkey
  foreign key (property_id) references public.properties(id) on delete set null;
alter table public.promotions drop constraint if exists promotions_user_id_fkey;
alter table public.promotions add  constraint promotions_user_id_fkey
  foreign key (user_id) references public.profiles(id) on delete set null;
alter table public.admin_audit drop constraint if exists admin_audit_admin_id_fkey;
alter table public.admin_audit add  constraint admin_audit_admin_id_fkey
  foreign key (admin_id) references public.profiles(id) on delete set null;

create or replace function public.delete_my_account()
returns void language plpgsql security definer set search_path = public, extensions, auth as $$
declare
  uid uuid := auth.uid();
begin
  if uid is null then raise exception 'AUTH'; end if;
  -- профиль, объявления, фото-ссылки, чаты, отзывы, обращения удаляются каскадом
  delete from auth.users where id = uid;
end $$;

revoke execute on function public.delete_my_account() from public, anon;
grant execute on function public.delete_my_account() to authenticated;

-- ---------------------------------------------------------------------
-- 5. Индексы — чтобы поиск не тормозил, когда объявлений станет много
-- ---------------------------------------------------------------------
create extension if not exists pg_trgm with schema extensions;

create index if not exists properties_owner_idx    on public.properties (owner_id);
create index if not exists properties_feed_idx     on public.properties (status, created_at desc);
create index if not exists properties_price_idx    on public.properties (status, currency, price);
create index if not exists properties_title_trgm   on public.properties using gin (title extensions.gin_trgm_ops);
create index if not exists property_images_prop_idx on public.property_images (property_id, sort_order);
create index if not exists favorites_property_idx  on public.favorites (property_id);
create index if not exists conversations_buyer_idx on public.conversations (buyer_id);
create index if not exists conversations_seller_idx on public.conversations (seller_id);
create index if not exists listing_reports_prop_idx on public.listing_reports (property_id);
create index if not exists reviews_author_idx      on public.reviews (author_id);
create index if not exists support_tickets_user_idx on public.support_tickets (user_id, last_message_at desc);
create index if not exists verification_user_idx   on public.verification_requests (user_id, kind, created_at desc);



-- #####################################################################
-- ##### 007_account_review.sql
-- #####################################################################

-- =====================================================================
--  Zumi — 007: каждый новый аккаунт попадает в кабинет команды
--  («New accounts»), причина отказа по лицензии видна пользователю.
--  Запускать после 006.
-- =====================================================================

alter table public.profiles
  add column if not exists account_reviewed_at timestamptz,  -- команда посмотрела аккаунт
  add column if not exists licence_note        text;         -- почему номер ZIEA не принят

-- пользователь не может сам отметить аккаунт проверенным или стереть причину отказа
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
    -- новый номер лицензии — старая причина отказа больше не актуальна
    if new.agent_licence_no is distinct from old.agent_licence_no then
      new.licence_note := null;
    else
      new.licence_note := old.licence_note;
    end if;
  end if;
  return new;
end $$;

-- лицензия ZIEA: при отказе сохраняем причину, чтобы человек её увидел
create or replace function public.admin_review_licence(uid uuid, approve boolean, p_note text default null)
returns void language plpgsql security definer set search_path = public, extensions as $$
begin
  if not public.is_admin() then raise exception 'NOT_ADMIN'; end if;
  if approve then
    update profiles set licence_verified_at = now(), licence_note = null where id = uid;
  else
    update profiles set agent_licence_no = null, licence_verified_at = null,
                        licence_note = coalesce(nullif(trim(p_note), ''), 'Licence could not be confirmed')
     where id = uid;
  end if;
  perform public._audit(case when approve then 'approve' else 'reject' end, 'licence', uid::text, p_note);
end $$;

-- статус своих проверок (для экрана «Get verified»)
create or replace function public.my_verification()
returns jsonb language sql stable security definer set search_path = public, extensions as $$
  select jsonb_build_object(
    'id_status', (select status from verification_requests
                   where user_id = auth.uid() and kind = 'identity'
                   order by created_at desc limit 1),
    'id_note',   (select reviewer_note from verification_requests
                   where user_id = auth.uid() and kind = 'identity'
                   order by created_at desc limit 1),
    'licence_note', (select licence_note from profiles where id = auth.uid())
  );
$$;

-- ---------------------------------------------------------------------
-- Кабинет: новые аккаунты
-- ---------------------------------------------------------------------
create or replace function public.admin_accounts(only_new boolean default true)
returns table (
  id uuid, full_name text, email text, role text, phone text, avatar_url text,
  phone_verified boolean, id_status text, licence_no text, licence_verified boolean,
  listings int, created_at timestamptz, reviewed_at timestamptz, banned boolean
) language plpgsql stable security definer set search_path = public, extensions, auth as $$
begin
  if not public.is_admin() then raise exception 'NOT_ADMIN'; end if;
  return query
    select pr.id, pr.full_name, u.email::text, pr.role, pr.phone, pr.avatar_url,
           pr.phone_verified_at is not null,
           case when pr.id_verified_at is not null then 'approved'
                else (select v.status from verification_requests v
                       where v.user_id = pr.id and v.kind = 'identity'
                       order by v.created_at desc limit 1) end,
           pr.agent_licence_no,
           pr.licence_verified_at is not null,
           (select count(*) from properties p where p.owner_id = pr.id)::int,
           pr.created_at, pr.account_reviewed_at, pr.banned_at is not null
      from profiles pr
      left join auth.users u on u.id = pr.id
     where pr.role <> 'admin'
       and (not only_new or pr.account_reviewed_at is null)
     order by pr.created_at desc
     limit 200;
end $$;

-- 'ok' — аккаунт в порядке; 'ban' — заблокировать (объявления скрываются)
create or replace function public.admin_review_account(uid uuid, p_action text, p_note text default null)
returns void language plpgsql security definer set search_path = public, extensions as $$
begin
  if not public.is_admin() then raise exception 'NOT_ADMIN'; end if;
  if p_action = 'ok' then
    update profiles set account_reviewed_at = now() where id = uid;
  elsif p_action = 'ban' then
    update profiles set account_reviewed_at = now(), banned_at = now(), ban_reason = p_note where id = uid;
    update properties set status = 'archived' where owner_id = uid and status = 'active';
  else
    raise exception 'UNKNOWN_ACTION';
  end if;
  perform public._audit(p_action, 'account', uid::text, p_note);
end $$;

-- счётчики кабинета: + новые аккаунты
create or replace function public.admin_stats()
returns jsonb language plpgsql stable security definer set search_path = public, extensions as $$
begin
  if not public.is_admin() then raise exception 'NOT_ADMIN'; end if;
  return jsonb_build_object(
    'accounts',   (select count(*) from profiles where account_reviewed_at is null and role <> 'admin'),
    'id_checks',  (select count(*) from verification_requests where kind = 'identity'  and status = 'pending'),
    'ownership',  (select count(*) from verification_requests where kind = 'ownership' and status = 'pending'),
    'licences',   (select count(*) from profiles where agent_licence_no is not null and licence_verified_at is null),
    'reports',    (select count(*) from listing_reports where status = 'new'),
    'tickets',    (select count(*) from support_tickets where status = 'open'),
    'reviews',    (select count(*) from reviews where flags_count > 0 and status = 'published'),
    'listings',   (select count(*) from properties where status = 'active'),
    'users',      (select count(*) from profiles)
  );
end $$;

revoke execute on function public.admin_accounts(boolean) from public, anon;
revoke execute on function public.admin_review_account(uuid, text, text) from public, anon;

create index if not exists profiles_new_accounts_idx on public.profiles (created_at desc) where account_reviewed_at is null;



-- #####################################################################
-- ##### 008_campaigns.sql
-- #####################################################################

-- =====================================================================
--  Zumi — 008: кампании продвижения объявлений (кабинет агента)
--  Агент выбирает своё объявление, место показа, картинку и даты.
--  В первый день кампания появляется сама, после последнего дня — исчезает
--  (никаких расписаний: показ просто проверяет сегодняшнюю дату).
--  Показы и клики считаются по дням — для отчёта рекламодателю.
--  Запускать после 007.
-- =====================================================================

create table if not exists public.campaigns (
  id           uuid primary key default gen_random_uuid(),
  owner_id     uuid not null references public.profiles(id) on delete cascade,
  property_id  uuid not null references public.properties(id) on delete cascade,
  advertiser   text not null check (length(trim(advertiser)) between 2 and 80),
  contact      text check (contact is null or length(contact) <= 200),   -- ссылка или телефон
  placement    text not null check (placement in ('search_top', 'home_featured')),
  image_url    text,                                                     -- своя картинка 3:2
  starts_on    date not null,
  ends_on      date not null,
  status       text not null default 'active' check (status in ('active', 'paused', 'stopped')),
  created_at   timestamptz not null default now(),
  check (ends_on >= starts_on)
);

create index if not exists campaigns_live_idx  on public.campaigns (placement, status, starts_on, ends_on);
create index if not exists campaigns_owner_idx on public.campaigns (owner_id, created_at desc);

-- статистика по дням
create table if not exists public.campaign_stats (
  campaign_id uuid not null references public.campaigns(id) on delete cascade,
  day         date not null,
  views       int  not null default 0,
  clicks      int  not null default 0,
  primary key (campaign_id, day)
);

alter table public.campaigns      enable row level security;
alter table public.campaign_stats enable row level security;

-- идущие сегодня кампании видны всем (чтобы показывать их в списках)
drop policy if exists "live campaigns readable" on public.campaigns;
create policy "live campaigns readable" on public.campaigns for select
  using (status = 'active' and current_date between starts_on and ends_on);
drop policy if exists "own campaigns" on public.campaigns;
create policy "own campaigns" on public.campaigns for all
  using (owner_id = auth.uid()) with check (owner_id = auth.uid());
drop policy if exists "admins read campaigns" on public.campaigns;
create policy "admins read campaigns" on public.campaigns for select using (public.is_admin());

drop policy if exists "own campaign stats" on public.campaign_stats;
create policy "own campaign stats" on public.campaign_stats for select
  using (exists (select 1 from campaigns c where c.id = campaign_id
                  and (c.owner_id = auth.uid() or public.is_admin())));

-- правила: только агенты (и команда), только своё активное объявление,
-- не больше 3 идущих кампаний одновременно, остановленную нельзя запустить снова
create or replace function public.check_campaign()
returns trigger language plpgsql security definer set search_path = public, extensions as $$
declare
  v_role text;
  v_live int;
begin
  select role into v_role from profiles where id = new.owner_id;
  if v_role not in ('agent', 'admin') then raise exception 'AGENTS_ONLY'; end if;
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

drop trigger if exists check_campaign on public.campaigns;
create trigger check_campaign
  before insert or update on public.campaigns
  for each row execute function public.check_campaign();

-- показ или клик (вызывает приложение; считается только у идущей кампании)
create or replace function public.log_campaign_event(cid uuid, kind text)
returns void language plpgsql security definer set search_path = public, extensions as $$
begin
  if kind not in ('view', 'click') then return; end if;
  if not exists (select 1 from campaigns where id = cid and status = 'active'
                   and current_date between starts_on and ends_on) then
    return;
  end if;
  insert into campaign_stats (campaign_id, day, views, clicks)
  values (cid, current_date, (kind = 'view')::int, (kind = 'click')::int)
  on conflict (campaign_id, day) do update
     set views  = campaign_stats.views  + excluded.views,
         clicks = campaign_stats.clicks + excluded.clicks;
end $$;

grant execute on function public.log_campaign_event(uuid, text) to anon, authenticated;

-- публичная картинка кампании
insert into storage.buckets (id, name, public) values ('campaign-images', 'campaign-images', true)
  on conflict do nothing;
drop policy if exists "public read campaign images" on storage.objects;
create policy "public read campaign images" on storage.objects for select
  using (bucket_id = 'campaign-images');
drop policy if exists "users upload campaign images" on storage.objects;
create policy "users upload campaign images" on storage.objects for insert to authenticated
  with check (bucket_id = 'campaign-images' and (storage.foldername(name))[1] = auth.uid()::text);
drop policy if exists "users delete campaign images" on storage.objects;
create policy "users delete campaign images" on storage.objects for delete to authenticated
  using (bucket_id = 'campaign-images' and (storage.foldername(name))[1] = auth.uid()::text);



-- #####################################################################
-- ##### 009_ads_security.sql
-- #####################################################################

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



-- #####################################################################
-- ##### 010_security_fixes.sql
-- #####################################################################

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
) language sql stable security definer set search_path = public, extensions as $$
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
returns jsonb language sql stable security definer set search_path = public, extensions as $$
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
returns text language plpgsql security definer set search_path = public, extensions as $$
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
language plpgsql stable security definer set search_path = public, extensions, auth as $$
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
returns trigger language plpgsql set search_path = public, extensions as $$
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
returns void language plpgsql security definer set search_path = public, extensions as $$
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
returns uuid language plpgsql security definer set search_path = public, extensions as $$
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
returns boolean language plpgsql security definer set search_path = public, extensions as $$
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
returns void language plpgsql security definer set search_path = public, extensions as $$
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
returns void language plpgsql security definer set search_path = public, extensions as $$
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
returns boolean language sql stable security definer set search_path = public, extensions as $$
  select exists (select 1 from profiles
                  where id <> p_uid and phone_verified_at is not null
                    and public._norm_phone(phone) = public._norm_phone(p_phone));
$$;
revoke execute on function public._phone_taken(text, uuid) from public, anon, authenticated;

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
returns void language plpgsql security definer set search_path = public, extensions as $$
begin
  if not public.is_admin() then raise exception 'NOT_ADMIN'; end if;
  insert into app_settings (key, value) values ('otp_test_mode', case when p_on then 'true' else 'false' end)
  on conflict (key) do update set value = excluded.value;
  perform public._audit('otp_test_mode', 'settings', 'otp_test_mode', case when p_on then 'on' else 'off' end);
end $$;

create or replace function public.admin_stats()
returns jsonb language plpgsql stable security definer set search_path = public, extensions as $$
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



-- #####################################################################
-- ##### 011_docs_licence.sql
-- #####################################################################

-- =====================================================================
--  Zumi — 011: удаление документов после проверки, лицензия ZIEA
--  1. Фото документов, селфи и фото с проверки на месте удаляются из
--     хранилища verification-docs сразу после решения модератора.
--     Без решения — через 30 дней (срок подтвердит юрист).
--     В базе остаётся только результат: статус, дата, кто проверил, причина.
--  2. Агент без сверенной лицензии ZIEA: пометка на объявлениях,
--     продвижение — только с проверенной лицензией, правило «публиковать
--     только после проверки» включается одной кнопкой (app_settings).
--  Запускать после 010. Можно запускать повторно.
-- =====================================================================

-- =====================================================================
-- 1. ДОКУМЕНТЫ
-- =====================================================================
alter table public.verification_requests
  add column if not exists reviewed_by     uuid references public.profiles(id) on delete set null,
  add column if not exists docs_deleted_at timestamptz;
alter table public.verification_requests drop constraint if exists verification_requests_status_check;
alter table public.verification_requests add constraint verification_requests_status_check
  check (status in ('pending', 'approved', 'rejected', 'expired'));

-- кто может запускать уборку: команда Zumi или сервер (Edge Function с service-ключом)
create or replace function public._is_admin_or_service()
returns boolean language sql stable as $$
  select public.is_admin()
      or coalesce(nullif(current_setting('request.jwt.claims', true), '')::json ->> 'role', '') = 'service_role';
$$;

-- решение модератора: + кто проверил. Пути к файлам остаются, пока файлы не удалены (см. ниже)
create or replace function public.admin_review_verification(rid uuid, approve boolean, p_note text default null)
returns void language plpgsql security definer set search_path = public, extensions as $$
declare r record;
begin
  if not public.is_admin() then raise exception 'NOT_ADMIN'; end if;
  select * into r from verification_requests where id = rid;
  if r is null then raise exception 'REQUEST_NOT_FOUND'; end if;

  update verification_requests
     set status = case when approve then 'approved' else 'rejected' end,
         reviewer_note = p_note, reviewed_at = now(), reviewed_by = auth.uid()
   where id = rid;

  if approve then
    if r.kind = 'identity' then
      update profiles set id_verified_at = now(), is_verified = true where id = r.user_id;
    elsif r.kind = 'ownership' then
      update properties set ownership_verified_at = now() where id = r.property_id;
    else
      update properties set property_verified_at = now(), property_verify_method = 'visit' where id = r.property_id;
    end if;
  end if;
  perform public._audit(case when approve then 'approve' else 'reject' end, r.kind, rid::text, p_note);
end $$;

-- какие файлы удалить:
--   • файлы заявок, по которым уже есть решение;
--   • любые файлы старше 30 дней;
--   • «потерянные» файлы старше часа, которые не относятся ни к одной ожидающей заявке
create or replace function public.docs_purge_list()
returns text[] language plpgsql stable security definer set search_path = public, extensions, storage as $$
begin
  if not public._is_admin_or_service() then raise exception 'NOT_ADMIN'; end if;
  return array(
    select o.name from storage.objects o
     where o.bucket_id = 'verification-docs'
       and (   o.created_at < now() - interval '30 days'
            or exists (select 1 from public.verification_requests v
                        where v.status <> 'pending' and o.name = any(v.doc_paths))
            or (o.created_at < now() - interval '1 hour'
                and not exists (select 1 from public.verification_requests v
                                 where v.status = 'pending' and o.name = any(v.doc_paths))))
     order by o.created_at
     limit 500);
end $$;

-- файлы удалены → убираем ссылки на них; заявки без решения 30 дней — «истекли»
create or replace function public.docs_purge_done(names text[])
returns void language plpgsql security definer set search_path = public, extensions as $$
begin
  if not public._is_admin_or_service() then raise exception 'NOT_ADMIN'; end if;
  update verification_requests
     set doc_paths = array(select x from unnest(doc_paths) x where not x = any(names)),
         docs_deleted_at = now()
   where doc_paths && names;
  update verification_requests
     set status = 'expired', reviewed_at = now(),
         reviewer_note = coalesce(reviewer_note, 'No decision within 30 days — documents deleted. Please send again.')
   where status = 'pending' and created_at < now() - interval '30 days';
end $$;

-- ежедневная уборка без файлов: метки показов рекламы (2 дня), истёкшие заявки
create or replace function public.cleanup_daily()
returns void language plpgsql security definer set search_path = public, extensions as $$
begin
  if not public._is_admin_or_service() and current_user not in ('postgres', 'supabase_admin') then
    raise exception 'NOT_ADMIN';
  end if;
  delete from event_seen where day < current_date - 1;          -- IP и метки устройств — не дольше 2 дней
  delete from verification_codes where created_at < now() - interval '30 days';
  update verification_requests
     set status = 'expired', reviewed_at = now(),
         reviewer_note = coalesce(reviewer_note, 'No decision within 30 days — documents deleted. Please send again.')
   where status = 'pending' and created_at < now() - interval '30 days';
end $$;

-- команда может удалять файлы проверок
drop policy if exists "admins delete docs" on storage.objects;
create policy "admins delete docs" on storage.objects for delete to authenticated
  using (bucket_id = 'verification-docs' and public.is_admin());

-- проверка на месте решается сразу — приложение удаляет фото само, здесь только ссылки
-- (если приложение не успело — файлы уберёт docs_purge_list)

-- если в проекте включён pg_cron — ежедневная уборка в 03:15
do $$
begin
  if exists (select 1 from pg_extension where extname = 'pg_cron') then
    perform cron.unschedule(jobid) from cron.job where jobname = 'zumi-cleanup-daily';
    perform cron.schedule('zumi-cleanup-daily', '15 3 * * *', 'select public.cleanup_daily()');
  end if;
end $$;

-- =====================================================================
-- 2. ЛИЦЕНЗИЯ ZIEA
-- =====================================================================
insert into public.app_settings values ('require_licence_to_publish', 'false') on conflict do nothing;

-- при регистрации агент может сразу указать номер ZIEA
create or replace function public.handle_new_user()
returns trigger language plpgsql security definer set search_path = public, extensions as $$
declare v_agent boolean := new.raw_user_meta_data->>'role' = 'agent';
begin
  insert into public.profiles (id, full_name, phone, role, terms_accepted_at, agent_licence_no)
  values (
    new.id,
    new.raw_user_meta_data->>'full_name',
    new.raw_user_meta_data->>'phone',
    case when v_agent then 'agent' else 'owner' end,
    case when (new.raw_user_meta_data->>'terms_accepted') = 'true' then now() end,
    case when v_agent then nullif(left(trim(coalesce(new.raw_user_meta_data->>'licence_no', '')), 40), '') end
  );
  return new;
end $$;

-- лента: + «лицензия агента сверена» (демо-объявления считаем сверенными)
create or replace view public.property_feed as
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
           '{}'::text[]) as thumb_urls,
         (p.is_demo or pr.role is distinct from 'agent' or pr.licence_verified_at is not null) as owner_licence_verified
    from properties p
    left join areas a     on a.id  = p.area_id
    left join profiles pr on pr.id = p.owner_id
   where p.status = 'active' or p.owner_id = auth.uid() or public.is_admin();

grant select on public.property_feed to anon, authenticated;

-- правило «агент публикует только после проверки лицензии» (выключено, включается кнопкой)
create or replace function public.require_agent_licence()
returns trigger language plpgsql security definer set search_path = public, extensions as $$
declare v_on boolean := coalesce((select value from app_settings where key = 'require_licence_to_publish'), 'false') = 'true';
begin
  if not v_on or new.is_demo or new.owner_id is null then return new; end if;
  if new.status not in ('active', 'pending') then return new; end if;
  if tg_op = 'UPDATE' and old.status in ('active', 'pending') then return new; end if;   -- уже опубликовано
  if exists (select 1 from profiles where id = new.owner_id and role = 'agent' and licence_verified_at is null) then
    raise exception 'LICENCE_REQUIRED';
  end if;
  return new;
end $$;
drop trigger if exists require_agent_licence on public.properties;
create trigger require_agent_licence before insert or update of status on public.properties
  for each row execute function public.require_agent_licence();

create or replace function public.admin_set_setting(p_key text, p_value text)
returns void language plpgsql security definer set search_path = public, extensions as $$
begin
  if not public.is_admin() then raise exception 'NOT_ADMIN'; end if;
  if p_key not in ('otp_test_mode', 'require_licence_to_publish') then raise exception 'BAD_SETTING'; end if;
  if p_value not in ('true', 'false') then raise exception 'BAD_SETTING'; end if;
  insert into app_settings (key, value) values (p_key, p_value)
  on conflict (key) do update set value = excluded.value;
  perform public._audit('setting', 'settings', p_key, p_value);
end $$;

-- продвижение — только агентам с проверенной лицензией
create or replace function public.check_campaign()
returns trigger language plpgsql security definer set search_path = public, extensions as $$
declare
  v_role text;
  v_licence timestamptz;
  v_live int;
begin
  select role, licence_verified_at into v_role, v_licence from profiles where id = new.owner_id;
  if v_role not in ('agent', 'admin') then raise exception 'AGENTS_ONLY'; end if;
  if v_role = 'agent' and v_licence is null and new.status = 'active' then
    raise exception 'LICENCE_NOT_VERIFIED';
  end if;
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

-- уже идущие кампании агентов без лицензии видны дальше только после проверки лицензии
drop policy if exists "live campaigns readable" on public.campaigns;
create policy "live campaigns readable" on public.campaigns for select
  using (status = 'active' and review_status = 'approved' and current_date between starts_on and ends_on
         and exists (select 1 from profiles o where o.id = owner_id
                      and (o.role <> 'agent' or o.licence_verified_at is not null)));

-- счётчики кабинета: + правило лицензий
create or replace function public.admin_stats()
returns jsonb language plpgsql stable security definer set search_path = public, extensions as $$
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
    'require_licence', coalesce((select value from app_settings where key = 'require_licence_to_publish'), 'false') = 'true'
  );
end $$;



-- #####################################################################
-- ##### 012_marketing.sql
-- #####################################################################

-- =====================================================================
--  Zumi — 012: согласие на новости и предложения Zumi
--  Отдельная галочка при регистрации (по умолчанию выключена): новости по WhatsApp или почте.
--  Для каждого канала хранится дата согласия; пусто — согласия нет.
--  В Settings каналы включаются и выключаются по отдельности.
--  Запускать после 011. Можно запускать повторно.
-- =====================================================================
alter table public.profiles
  add column if not exists marketing_email_at    timestamptz,
  add column if not exists marketing_whatsapp_at timestamptz;

-- при регистрации: согласие только если галочка отмечена
create or replace function public.handle_new_user()
returns trigger language plpgsql security definer set search_path = public, extensions as $$
declare v_agent boolean := new.raw_user_meta_data->>'role' = 'agent';
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
  return new;
end $$;

-- включить / выключить в настройках
-- p_channel: 'email' | 'whatsapp'
create or replace function public.set_marketing(p_channel text, p_on boolean)
returns void language plpgsql security definer set search_path = public, extensions as $$
begin
  if auth.uid() is null then raise exception 'AUTH'; end if;
  if p_channel = 'email' then
    update profiles set marketing_email_at = case when p_on then now() end where id = auth.uid();
  elsif p_channel = 'whatsapp' then
    update profiles set marketing_whatsapp_at = case when p_on then now() end where id = auth.uid();
  else
    raise exception 'BAD_CHANNEL';
  end if;
end $$;
revoke execute on function public.set_marketing(text, boolean) from public, anon;
grant execute on function public.set_marketing(text, boolean) to authenticated;

-- своё согласие человек видит в настройках
create or replace function public.my_verification()
returns jsonb language sql stable security definer set search_path = public, extensions as $$
  select jsonb_build_object(
    'id_status', (select status from verification_requests
                   where user_id = auth.uid() and kind = 'identity' order by created_at desc limit 1),
    'id_note',   (select reviewer_note from verification_requests
                   where user_id = auth.uid() and kind = 'identity' order by created_at desc limit 1),
    'licence_note', (select licence_note from profiles where id = auth.uid()),
    'phone', (select phone from profiles where id = auth.uid()),
    'whatsapp', (select whatsapp from profiles where id = auth.uid()),
    'phone_channel', (select phone_verify_channel from profiles where id = auth.uid()),
    'email_verified', (select email_verified_at is not null from profiles where id = auth.uid()),
    'marketing_email', (select marketing_email_at is not null from profiles where id = auth.uid()),
    'marketing_whatsapp', (select marketing_whatsapp_at is not null from profiles where id = auth.uid())
  );
$$;

-- список для рассылки (только команда): почта — тем, кто согласился на почту,
-- WhatsApp — тем, кто согласился на WhatsApp (только подтверждённый номер)
create or replace function public.admin_marketing_list()
returns table (user_id uuid, full_name text, role text, email text, whatsapp text,
               email_since timestamptz, whatsapp_since timestamptz)
language plpgsql stable security definer set search_path = public, extensions, auth as $$
begin
  if not public.is_admin() then raise exception 'NOT_ADMIN'; end if;
  return query
    select pr.id, pr.full_name, pr.role,
           case when pr.marketing_email_at is not null then u.email::text end,
           case when pr.marketing_whatsapp_at is not null and pr.phone_verified_at is not null then pr.phone end,
           pr.marketing_email_at, pr.marketing_whatsapp_at
      from profiles pr join auth.users u on u.id = pr.id
     where (pr.marketing_email_at is not null or pr.marketing_whatsapp_at is not null) and pr.banned_at is null
     order by greatest(pr.marketing_email_at, pr.marketing_whatsapp_at) desc;
end $$;



-- #####################################################################
-- ##### 013_team_help_stats.sql
-- #####################################################################

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
returns boolean language sql stable security definer set search_path = public, extensions as $$
  select exists (select 1 from profiles where id = auth.uid() and role = 'admin'
                  and coalesce(team_level, 'owner') = 'owner');
$$;

-- список команды и выдача ролей — только владелец
create or replace function public.admin_team()
returns table (user_id uuid, full_name text, email text, level text, since timestamptz)
language plpgsql stable security definer set search_path = public, extensions, auth as $$
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
returns void language plpgsql security definer set search_path = public, extensions, auth as $$
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
returns void language plpgsql security definer set search_path = public, extensions as $$
begin
  if not public.is_owner() then raise exception 'OWNER_ONLY'; end if;
  insert into app_settings (key, value) values ('otp_test_mode', case when p_on then 'true' else 'false' end)
  on conflict (key) do update set value = excluded.value;
  perform public._audit('otp_test_mode', 'settings', 'otp_test_mode', case when p_on then 'on' else 'off' end);
end $$;

create or replace function public.admin_set_setting(p_key text, p_value text)
returns void language plpgsql security definer set search_path = public, extensions as $$
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
returns uuid language plpgsql security definer set search_path = public, extensions as $$
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
language plpgsql stable security definer set search_path = public, extensions, auth as $$
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
returns void language plpgsql security definer set search_path = public, extensions as $$
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
language plpgsql stable security definer set search_path = public, extensions as $$
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
returns void language plpgsql security definer set search_path = public, extensions as $$
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
returns void language plpgsql security definer set search_path = public, extensions as $$
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
returns void language plpgsql security definer set search_path = public, extensions as $$
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
returns jsonb language plpgsql stable security definer set search_path = public, extensions as $$
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
returns jsonb language plpgsql stable security definer set search_path = public, extensions as $$
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
- Add good photos: daylight, every room, the outside and the street. 5 or more photos give people a clear picture.
- Check the preview and publish.

## Tips
- Write the real price, so people know right away if the home fits their budget.
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
   'The Verified badge shows that Zumi checked who you are.

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



-- #####################################################################
-- ##### 014_owner_dev.sql
-- #####################################################################

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



-- #####################################################################
-- ##### 015_listing_advice.sql
-- #####################################################################

-- =====================================================================
--  Zumi — 015: помощь продавцу
--  1. Честный счётчик просмотров: один человек — один просмотр объявления в день,
--     свои просмотры автора не считаются. Просмотры по дням.
--  2. Средняя цена по району (для подсказки в мастере) — только если похожих
--     объявлений не меньше 5, чтобы нельзя было вычислить чужое.
--  3. Советы после публикации: правила на сервере по статистике объявления.
--  Запускать после 014. Можно запускать повторно.
-- =====================================================================

-- =====================================================================
-- 1. ПРОСМОТРЫ ПО ДНЯМ
-- =====================================================================
create table if not exists public.listing_views_daily (
  property_id uuid not null references public.properties(id) on delete cascade,
  day         date not null,
  views       int  not null default 0,   -- разные люди за день
  primary key (property_id, day)
);
alter table public.listing_views_daily enable row level security;
drop policy if exists "owner reads own views" on public.listing_views_daily;
create policy "owner reads own views" on public.listing_views_daily for select
  using (exists (select 1 from properties p where p.id = property_id
                  and (p.owner_id = auth.uid() or public.is_admin())));

-- просмотр объявления: один раз в день с человека (вошедший — по аккаунту, гость — по метке устройства)
create or replace function public.log_listing_view(pid uuid, device text default null)
returns void language plpgsql security definer set search_path = public, extensions as $$
declare v_owner uuid;
begin
  select owner_id into v_owner from properties where id = pid and status = 'active';
  if not found then return; end if;
  if v_owner is not null and v_owner = auth.uid() then return; end if;   -- автор смотрит своё — не считаем
  if not public._first_event(pid, 'lv', device) then return; end if;
  insert into listing_views_daily (property_id, day, views)
  values (pid, (now() at time zone 'Africa/Lusaka')::date, 1)
  on conflict (property_id, day) do update set views = listing_views_daily.views + 1;
  update properties set views_count = views_count + 1 where id = pid;
end $$;
grant execute on function public.log_listing_view(uuid, text) to anon, authenticated;

-- старый вызов (без метки устройства) — тоже через честный счётчик
create or replace function public.increment_views(pid uuid)
returns void language sql security definer set search_path = public, extensions as $$
  select public.log_listing_view(pid, null);
$$;

-- =====================================================================
-- 2. ЦЕНЫ ПОХОЖИХ ОБЪЯВЛЕНИЙ В РАЙОНЕ
-- =====================================================================
create or replace function public.area_price_stats(p_area int, p_deal text, p_type text, p_beds int default null,
                                                   p_period text default null, p_currency text default 'ZMW',
                                                   p_exclude uuid default null)
returns jsonb language sql stable security definer set search_path = public, extensions as $$
  with s as (
    select p.price from properties p
     where p.status = 'active' and p.area_id = p_area and p.deal_type::text = p_deal
       and p.property_type::text = p_type and p.currency = p_currency
       and (p_deal <> 'rent' or coalesce(p.rent_period, 'month') = coalesce(p_period, 'month'))
       and (p_beds is null or p.bedrooms between p_beds - 1 and p_beds + 1)
       and (p_exclude is null or p.id <> p_exclude)
       and p.price > 0
  )
  select case when count(*) < 5 then jsonb_build_object('n', count(*))
              else jsonb_build_object(
                'n', count(*),
                'p25', percentile_cont(0.25) within group (order by price),
                'median', percentile_cont(0.5) within group (order by price),
                'p75', percentile_cont(0.75) within group (order by price)) end
    from s;
$$;
grant execute on function public.area_price_stats(int, text, text, int, text, text, uuid) to anon, authenticated;

-- =====================================================================
-- 3. СОВЕТЫ ПОСЛЕ ПУБЛИКАЦИИ
--    Возвращает по каждому своему объявлению: просмотры, контакты и сохранения
--    за 7 дней, просмотры и контакты по дням (14 дней) и до 3 советов (коды —
--    текст пишет приложение).
-- =====================================================================
create or replace function public.listing_advice(pid uuid)
returns jsonb language plpgsql stable security definer set search_path = public, extensions as $$
declare
  p record;
  v_live_days int;
  v_views7 int;
  v_contacts7 int;
  v_saves7 int;
  v_photos int;
  v_stats jsonb;
  v_tips jsonb := '[]'::jsonb;
begin
  select * into p from properties where id = pid;
  if not found or (p.owner_id is distinct from auth.uid() and not public.is_admin()) then
    raise exception 'NOT_FOUND';
  end if;

  v_live_days := greatest(0, (now()::date - coalesce(p.approved_at, p.created_at)::date));
  v_views7 := coalesce((select sum(views) from listing_views_daily
                         where property_id = pid and day > current_date - 7), 0);
  v_contacts7 := (select count(*) from phone_reveals where property_id = pid and created_at > now() - interval '7 days')
               + (select count(*) from conversations where property_id = pid and created_at > now() - interval '7 days');
  v_saves7 := (select count(*) from favorites where property_id = pid and created_at > now() - interval '7 days');
  v_photos := (select count(*) from property_images where property_id = pid);
  v_stats := public.area_price_stats(p.area_id, p.deal_type::text, p.property_type::text, p.bedrooms,
                                     p.rent_period, p.currency, pid);

  if p.status = 'active' then
    -- по порядку важности
    if coalesce(p.confirmed_at, p.created_at) < now() - interval '50 days' then
      v_tips := v_tips || jsonb_build_object('code', 'confirm',
                  'days_left', greatest(0, 60 - (now()::date - coalesce(p.confirmed_at, p.created_at)::date)));
    end if;
    if v_live_days >= 7 and v_views7 >= 30 and v_contacts7 = 0 then
      v_tips := v_tips || jsonb_build_object('code', 'no_contacts', 'views', v_views7);
    end if;
    if v_saves7 >= 5 and v_contacts7 = 0 then
      v_tips := v_tips || jsonb_build_object('code', 'saved_no_contact', 'saves', v_saves7);
    end if;
    if (v_stats ? 'p75') and p.price > (v_stats->>'p75')::numeric * 1.3 then
      v_tips := v_tips || jsonb_build_object('code', 'price_high', 'p25', round((v_stats->>'p25')::numeric),
                  'p75', round((v_stats->>'p75')::numeric), 'n', v_stats->'n');
    end if;
    if (v_stats ? 'p25') and p.price < (v_stats->>'p25')::numeric * 0.5 then
      v_tips := v_tips || jsonb_build_object('code', 'price_low', 'p25', round((v_stats->>'p25')::numeric),
                  'p75', round((v_stats->>'p75')::numeric), 'n', v_stats->'n');
    end if;
    if v_photos < 5 then
      v_tips := v_tips || jsonb_build_object('code', 'photos', 'photos', v_photos);
    end if;
    if length(coalesce(p.description, '')) < 150 then
      v_tips := v_tips || jsonb_build_object('code', 'description');
    end if;
    if v_live_days >= 7 and v_views7 < 10 then
      v_tips := v_tips || jsonb_build_object('code', 'few_views', 'views', v_views7);
    end if;
    if p.property_verified_at is null and v_live_days >= 3 then
      v_tips := v_tips || jsonb_build_object('code', 'verify_onsite');
    end if;
    if jsonb_array_length(v_tips) = 0 and v_contacts7 >= 3 then
      v_tips := jsonb_build_array(jsonb_build_object('code', 'doing_well', 'contacts', v_contacts7));
    end if;
  end if;

  return jsonb_build_object(
    'id', pid,
    'views7', v_views7,
    'contacts7', v_contacts7,
    'saves7', v_saves7,
    'days', coalesce((select jsonb_agg(jsonb_build_object(
                'day', d::date,
                'views', coalesce((select views from listing_views_daily where property_id = pid and day = d::date), 0),
                'contacts', (select count(*) from phone_reveals r where r.property_id = pid
                               and (r.created_at at time zone 'Africa/Lusaka')::date = d::date)
                          + (select count(*) from conversations c where c.property_id = pid
                               and (c.created_at at time zone 'Africa/Lusaka')::date = d::date)
              ) order by d)
              from generate_series(current_date - 13, current_date, interval '1 day') d), '[]'::jsonb),
    'tips', (select coalesce(jsonb_agg(t), '[]'::jsonb) from (
               select t from jsonb_array_elements(v_tips) t limit 3) x)
  );
end $$;
grant execute on function public.listing_advice(uuid) to authenticated;

-- все свои объявления разом (для «Мои объявления»)
create or replace function public.my_listing_advice()
returns jsonb language sql stable security definer set search_path = public, extensions as $$
  select coalesce(jsonb_agg(public.listing_advice(p.id)), '[]'::jsonb)
    from properties p
   where p.owner_id = auth.uid() and p.status in ('active', 'pending') and not p.is_demo;
$$;
grant execute on function public.my_listing_advice() to authenticated;

-- =====================================================================
-- 4. СТАТЬЯ ПОМОЩИ ПРО СТАТИСТИКУ ОБЪЯВЛЕНИЯ
-- =====================================================================
insert into public.help_articles (id, category, title, body, sort, web_only) values
  ('427fc45e-d221-50fd-b46e-089950b6edd5', 'listings', 'Views, contacts and tips for my listing',
   'In Profile → My listings, under each active listing you see the numbers for the last 7 days:
- Views — each person is counted once a day. Your own views are not counted.
- Contacts — people who opened your phone number or started a chat.
- Saved — people who tapped the heart.

Tap "Details" to see views and contacts by day for the last 14 days, and tips for this listing.

## Where the tips come from
Zumi looks at your listing''s numbers and at similar listings in the same area. For example:
- many views but no contacts — check the price and add details people ask about;
- the price is far from similar homes in the area;
- fewer than 5 photos or a very short description;
- the listing needs a "still available" confirmation soon.

Tips are suggestions — you decide what to change.',
   40, false)
on conflict (id) do nothing;


-- =====================================================================
--  Zumi — 016: непрочитанные сообщения
--  Для каждой переписки помним, когда человек последний раз её открывал.
--  Непрочитанные = сообщения от собеседника, пришедшие после этого момента.
--  Число показывается на значке «Chats» (до 10, дальше «10+») и в списке чатов.
--  Запускать после 015. Можно запускать повторно.
-- =====================================================================

create table if not exists public.chat_reads (
  conversation_id uuid not null references public.conversations(id) on delete cascade,
  user_id         uuid not null references public.profiles(id) on delete cascade,
  read_at         timestamptz not null default now(),
  primary key (conversation_id, user_id)
);
alter table public.chat_reads enable row level security;
drop policy if exists "own chat reads" on public.chat_reads;
create policy "own chat reads" on public.chat_reads for select using (user_id = auth.uid());

-- быстрый подсчёт: сообщения собеседника после времени прочтения
create index if not exists messages_conv_sender_idx on public.messages (conversation_id, created_at, sender_id);

-- открыл переписку → всё в ней прочитано
create or replace function public.mark_chat_read(cid uuid)
returns void language plpgsql security definer set search_path = public, extensions as $$
begin
  if auth.uid() is null then raise exception 'NOT_SIGNED_IN'; end if;
  if not exists (select 1 from conversations where id = cid and auth.uid() in (buyer_id, seller_id)) then
    return;
  end if;
  insert into chat_reads (conversation_id, user_id, read_at) values (cid, auth.uid(), now())
  on conflict (conversation_id, user_id) do update set read_at = now();
end $$;
grant execute on function public.mark_chat_read(uuid) to authenticated;

-- всего непрочитанных у меня (для значка). Считаем до 11 — больше значку не нужно.
create or replace function public.my_unread_count()
returns int language sql stable security definer set search_path = public, extensions as $$
  select count(*)::int from (
    select 1
      from conversations c
      join messages m on m.conversation_id = c.id
      left join chat_reads r on r.conversation_id = c.id and r.user_id = auth.uid()
     where auth.uid() in (c.buyer_id, c.seller_id)
       and m.sender_id <> auth.uid()
       and m.created_at > coalesce(r.read_at, '-infinity'::timestamptz)
     limit 11
  ) x;
$$;
grant execute on function public.my_unread_count() to authenticated;

-- список переписок + число непрочитанных в каждой (новый столбец — в конце)
create or replace view public.conversation_list
with (security_invoker = true) as
  select c.*,
         p.title as property_title,
         (select url from property_images i where i.property_id = p.id order by sort_order limit 1) as property_cover,
         case when c.buyer_id = auth.uid() then s.full_name else b.full_name end as other_name,
         (select count(*)::int from messages m
           where m.conversation_id = c.id and m.sender_id <> auth.uid()
             and m.created_at > coalesce((select r.read_at from chat_reads r
                                           where r.conversation_id = c.id and r.user_id = auth.uid()),
                                          '-infinity'::timestamptz)) as unread
    from conversations c
    left join properties p on p.id = c.property_id
    left join profiles  b on b.id = c.buyer_id
    left join profiles  s on s.id = c.seller_id;


-- =====================================================================
--  Zumi — 017: значок «Chats» считает переписки, а не сообщения
--  Число на значке = сколько переписок с новыми сообщениями (до 10, дальше «10+»).
--  В списке чатов у каждой переписки по-прежнему видно, сколько в ней новых сообщений.
--  Запускать после 016. Можно запускать повторно.
-- =====================================================================
create or replace function public.my_unread_count()
returns int language sql stable security definer set search_path = public, extensions as $$
  select count(*)::int from (
    select 1
      from conversations c
      left join chat_reads r on r.conversation_id = c.id and r.user_id = auth.uid()
     where auth.uid() in (c.buyer_id, c.seller_id)
       and exists (select 1 from messages m
                    where m.conversation_id = c.id
                      and m.sender_id <> auth.uid()
                      and m.created_at > coalesce(r.read_at, '-infinity'::timestamptz))
     limit 11
  ) x;
$$;
grant execute on function public.my_unread_count() to authenticated;


-- =====================================================================
--  Zumi — 018: проверка только по телефону и лицензии, телефон обязателен
--  для публикации, точка на карте и что рядом с жильём.
--  1. Проверку документов (NRC/паспорт + селфи), документы о собственности и
--     проверку на месте (фото + геолокация) выключаем. Новые заявки принять нельзя,
--     незавершённые закрываются, фото удаляются обычной уборкой.
--  2. «Проверенный» = подтверждён телефон (+ у агентов — лицензия ZIEA).
--  3. Опубликовать объявление можно только с подтверждённым телефоном.
--  4. У объявления: что рядом (магазины, школа, больница, главная дорога).
--  Запускать после 017. Можно запускать повторно.
-- =====================================================================

-- ---------------------------------------------------------------------
-- 1. Документы больше не принимаем
-- ---------------------------------------------------------------------
drop policy if exists "own requests create" on public.verification_requests;   -- нет политики = вставка запрещена
drop policy if exists "upload own verification docs" on storage.objects;

create or replace function public.submit_property_check(
  pid uuid, dev_lat double precision, dev_lng double precision, photo_paths text[]
)
returns jsonb language plpgsql security definer set search_path = public, extensions as $$
begin
  raise exception 'FEATURE_OFF';
end $$;

-- незавершённые заявки закрываем; фото удалит уборка (docs_purge_list / cleanup_daily)
update public.verification_requests
   set status = 'expired', reviewed_at = now(),
       reviewer_note = coalesce(reviewer_note, 'Document checks are no longer used. Nothing to do.')
 where status = 'pending' and kind in ('identity', 'ownership', 'property');

-- ---------------------------------------------------------------------
-- 2. Проверенный человек: имя + телефон (+ лицензия ZIEA у агентов)
-- ---------------------------------------------------------------------
create or replace function public.person_verified(uid uuid)
returns boolean language sql stable security definer set search_path = public, extensions as $$
  select pr.full_name is not null and length(trim(pr.full_name)) > 1
     and pr.phone_verified_at is not null
     and (pr.role <> 'agent' or pr.licence_verified_at is not null)
    from profiles pr where pr.id = uid;
$$;

-- ---------------------------------------------------------------------
-- 3. Публикация — только с подтверждённым телефоном
-- ---------------------------------------------------------------------
create or replace function public.require_phone_to_publish()
returns trigger language plpgsql security definer set search_path = public, extensions as $$
begin
  if new.is_demo or new.owner_id is null then return new; end if;
  if auth.uid() is null then return new; end if;   -- SQL Editor / сервис (не пользователь приложения)
  if new.status not in ('active', 'pending') then return new; end if;
  if tg_op = 'UPDATE' and old.status in ('active', 'pending') then return new; end if;   -- уже опубликовано
  if not exists (select 1 from profiles where id = new.owner_id and phone_verified_at is not null) then
    raise exception 'PHONE_REQUIRED';
  end if;
  return new;
end $$;
drop trigger if exists require_phone_to_publish on public.properties;
create trigger require_phone_to_publish before insert or update of status on public.properties
  for each row execute function public.require_phone_to_publish();

-- ---------------------------------------------------------------------
-- 4. Что рядом: {"shop":"lt1","school":"1_3","hospital":"3_5","main_road":"gt5"}
--    lt1 — до 1 км, 1_3 — 1–3 км, 3_5 — 3–5 км, gt5 — больше 5 км
-- ---------------------------------------------------------------------
alter table public.properties add column if not exists nearby jsonb not null default '{}'::jsonb;

create or replace function public._nearby_ok(j jsonb)
returns boolean language sql immutable as $$
  select jsonb_typeof(j) = 'object'
     and not exists (
       select 1 from jsonb_each_text(j) e
        where e.key not in ('shop', 'school', 'hospital', 'main_road')
           or e.value not in ('lt1', '1_3', '3_5', 'gt5'));
$$;
alter table public.properties drop constraint if exists properties_nearby_ok;
alter table public.properties add constraint properties_nearby_ok check (public._nearby_ok(nearby));
alter table public.properties drop constraint if exists properties_address_len;
alter table public.properties add constraint properties_address_len check (address is null or length(address) <= 120);

-- лента: + что рядом и «лицензированный агент»
create or replace view public.property_feed as
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
           '{}'::text[]) as thumb_urls,
         (p.is_demo or pr.role is distinct from 'agent' or pr.licence_verified_at is not null) as owner_licence_verified,
         p.nearby,
         (pr.role = 'agent' and pr.licence_verified_at is not null) as owner_licensed
    from properties p
    left join areas a     on a.id  = p.area_id
    left join profiles pr on pr.id = p.owner_id
   where p.status = 'active' or p.owner_id = auth.uid() or public.is_admin();

grant select on public.property_feed to anon, authenticated;

-- ---------------------------------------------------------------------
-- 5. Статьи помощи (только если команда их ещё не меняла)
-- ---------------------------------------------------------------------
update public.help_articles set
  title = 'Number checked and Licensed agent badges',
  body = 'Zumi shows two simple badges:
- Number checked — the owner or agent confirmed their phone number with a code.
- Licensed agent — the Zumi team checked the agent''s registration with the Zambia Institute of Estate Agents (ZIEA).

## How to get them
- Profile → Get verified → confirm your phone with a WhatsApp or SMS code. You do it once.
- Agents: add your ZIEA registration number. We check it with ZIEA — you don''t upload any documents.

You need a confirmed phone number to publish a listing.

Badges show what Zumi checked at that time. They are not a guarantee — always view the property and check the documents yourself.'
 where id = 'f131b212-3739-54b4-8711-d0657f8640a7' and updated_by is null;

update public.help_articles set
  body = replace(replace(body,
    'The person asks for a deposit or "booking fee" before you see the property.',
    'The person asks for a "viewing fee" or "booking fee". On Zumi nobody may charge for a viewing — not before, during or after it.'),
    'Prefer listings with the Verified badge and photos taken on site.',
    'Prefer listings with the Number checked or Licensed agent badge.')
 where id = '92e9e1e2-0b00-5793-ac95-3fc27a6d1090' and updated_by is null;


-- =====================================================================
--  Zumi — 019: «Ещё сдаётся?» и раздел «Скрытые объявления»
--  1. Через 30 дней после последнего подтверждения Zumi спрашивает автора
--     «Ещё доступно?». Нет ответа 7 дней (всего 37) — объявление пропадает из поиска.
--  2. Кто и почему скрыл объявление: сам автор, команда Zumi или «не подтверждено».
--     Скрытое командой автор может вернуть только через повторную проверку.
--  Запускать после 018. Можно запускать повторно.
-- =====================================================================

alter table public.properties
  add column if not exists hidden_by     text check (hidden_by in ('owner', 'team', 'expired')),
  add column if not exists hidden_reason text,
  add column if not exists hidden_at     timestamptz;
grant select (hidden_by, hidden_reason, hidden_at) on public.properties to anon, authenticated;

-- уже скрытые командой (не одобрены / по жалобам) — помечаем
update public.properties set hidden_by = 'team', hidden_reason = moderation_note, hidden_at = coalesce(updated_at, now())
 where status = 'archived' and hidden_by is null and moderation_note is not null;
update public.properties set hidden_by = 'owner', hidden_at = coalesce(updated_at, now())
 where status in ('archived', 'sold', 'rented') and hidden_by is null;

-- кто скрыл — ставит сервер, подделать нельзя
create or replace function public.track_hidden()
returns trigger language plpgsql security definer set search_path = public, extensions as $$
declare v_team boolean := auth.uid() is null or (public.is_admin() and auth.uid() is distinct from new.owner_id);
begin
  if new.status is not distinct from old.status then
    -- автор не может сам поменять отметки
    if not v_team then
      new.hidden_by := old.hidden_by; new.hidden_reason := old.hidden_reason; new.hidden_at := old.hidden_at;
    end if;
    return new;
  end if;

  if new.status in ('archived', 'sold', 'rented') then
    new.hidden_at := now();
    if v_team then
      new.hidden_by := coalesce(nullif(new.hidden_by, 'owner'), 'team');
      new.hidden_reason := coalesce(nullif(trim(new.moderation_note), ''), nullif(trim(new.hidden_reason), ''),
                                    'Hidden by the Zumi team');
    else
      new.hidden_by := 'owner';
      new.hidden_reason := null;
    end if;
  elsif new.status in ('active', 'pending') then
    -- скрытое командой автор возвращает только через проверку модератором
    if old.hidden_by = 'team' and not v_team then
      new.status := 'pending';
      new.approved_at := null;
    end if;
    new.hidden_by := null; new.hidden_reason := null; new.hidden_at := null;
    new.confirmed_at := now();   -- показал снова = подтвердил, что доступно
  end if;
  return new;
end $$;
drop trigger if exists track_hidden on public.properties;
create trigger track_hidden before update on public.properties
  for each row execute function public.track_hidden();

-- «Да, ещё доступно» / «Нет» одним нажатием
create or replace function public.answer_still_available(pid uuid, p_available boolean)
returns void language plpgsql security definer set search_path = public, extensions as $$
declare p record;
begin
  select * into p from properties where id = pid and owner_id = auth.uid();
  if not found then raise exception 'NOT_YOUR_LISTING'; end if;
  if p_available then
    update properties set confirmed_at = now() where id = pid and status = 'active';
  else
    update properties set status = case when p.deal_type = 'sale' then 'sold' else 'rented' end
     where id = pid and status = 'active';
  end if;
end $$;
grant execute on function public.answer_still_available(uuid, boolean) to authenticated;

-- сколько моих объявлений ждут ответа «ещё доступно?» (значок в профиле)
create or replace function public.my_listings_to_confirm()
returns int language sql stable security definer set search_path = public, extensions as $$
  select count(*)::int from properties
   where owner_id = auth.uid() and status = 'active' and not is_demo
     and coalesce(confirmed_at, approved_at, created_at) < now() - interval '30 days';
$$;
grant execute on function public.my_listings_to_confirm() to authenticated;

-- лента: в поиске — только подтверждённые за 37 дней; + кто и почему скрыл
create or replace view public.property_feed as
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
         (p.is_demo or coalesce(p.confirmed_at, p.created_at) > now() - interval '37 days') as is_fresh,
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
         p.hidden_by, p.hidden_reason, p.hidden_at
    from properties p
    left join areas a     on a.id  = p.area_id
    left join profiles pr on pr.id = p.owner_id
   where p.status = 'active' or p.owner_id = auth.uid() or public.is_admin();

grant select on public.property_feed to anon, authenticated;

-- статья помощи (если команда её ещё не меняла) и символ, которого нет в шрифте
update public.help_articles set body = 'A listing is hidden from search when:
- It was not confirmed as "still available". After 30 days Zumi asks you "Is it still available?" on the listing and in Profile. If there is no answer within 7 days, the listing is hidden. Tap "Yes, still available" to show it again.
- You hid it yourself, or marked it as sold or rented.
- The Zumi team hid it — for example after reports or if it was not approved. The reason is shown on the listing.

All hidden listings are in Profile → My listings → Hidden. Nothing is deleted: you can show a listing again in one tap. A listing hidden by the Zumi team goes back for a quick review first.'
 where id = 'ce7fd462-5a6c-59d9-be2a-337af0146f09' and updated_by is null;
update public.help_articles set body = replace(body, '⋯', '…') where body like '%⋯%';


-- =====================================================================
--  Zumi — 020: помощь, отзывы о приложении, выключатель продвижения
--  1. Новые статьи помощи (оплата, не публикуется объявление, сайт не открывается…).
--  2. Отзывы о приложении: человек оценивает Zumi (1–5) и пишет, что не работает.
--     Видит только владелец Zumi — в кабинете разработчика.
--  3. Продвижение агентов выключено, пока владелец не включит его в кабинете.
--  Запускать после 019. Можно запускать повторно.
-- =====================================================================

-- ---------------------------------------------------------------------
-- 1. Помощь
-- ---------------------------------------------------------------------
alter table public.help_articles drop constraint if exists help_articles_category_check;
alter table public.help_articles add constraint help_articles_category_check check (category in
  ('account', 'listings', 'contact', 'verification', 'promotion', 'payments', 'safety', 'technical'));

insert into public.help_articles (id, category, title, body, sort, web_only) values
  ('e705fbca-c1e3-5593-aec7-2ae5fa371d05', 'payments', 'Payments: my payment did not go through', 'Right now Zumi is free: posting listings, chats and calls cost nothing. Zumi never asks you to pay by mobile money to a private number.

## If a payment on Zumi fails (when paid features open)
- Check that you have enough money on your mobile money account, including the operator fee.
- Make sure you typed the PIN on your phone within 2 minutes — the request expires after that.
- Check that your phone has signal. Weak network is the most common reason.
- Don''t pay twice. If money left your account but nothing changed in Zumi, wait 15 minutes — operators sometimes confirm late.
- Still nothing? Open Help & support → "Payment" and send the transaction ID from the SMS. We will check it and return the money or turn on what you paid for.

## Someone asks you to pay "Zumi"
Zumi staff never ask for money in chat, by phone or WhatsApp. Agents may not charge a viewing fee. If someone does, don''t pay and report them.', 10, true),
  ('fb83561c-31fb-5032-b97a-6a70818079b5', 'payments', 'Refunds and money taken by mistake', 'If money was taken by mistake or a paid feature did not work, write to Help & support → "Payment" with:
- the phone number you paid from;
- the date and amount;
- the transaction ID from the operator SMS.

We answer within 1 working day. If the payment really failed on our side, we return the money to the same mobile money account.

Zumi cannot return money you paid directly to an agent or owner — Zumi is not part of deals between users. In that case contact the person, and if you think it is fraud, report the listing and go to the police.', 20, true),
  ('575a4dfc-2025-58ad-ad03-f9da9f7f955d', 'listings', 'I can''t publish my listing', 'Check these things one by one:
- Phone number: you need to confirm your phone with a code once. Zumi asks for it when you tap Publish.
- Pin on the map: put the pin where the property is. Without it you can''t publish.
- Price and neighbourhood: both are required.
- Listing limit: free accounts have a limit of active listings. Hide or delete an old listing, or mark it as rented or sold.
- Team accounts (Zumi staff) can''t post listings — use a personal account.
- Your account is blocked: you will see a message. Write to Help & support.

Your first listings are checked by the Zumi team — usually about 15 minutes. You will see "Under review" in My listings.', 15, false),
  ('4505a935-defa-5738-ad1b-e0adfb76823d', 'listings', 'How to hide or show my listing', 'You don''t have to delete a listing when it is not available for a while.
- Profile → My listings → tap … on the listing → "Hide from search". People won''t see it, nothing is deleted.
- To show it again: My listings → Hidden → tap … → "Show in search again".
- Rented or sold? Choose "Mark as rented" / "Mark as sold". The listing moves to Hidden too.

Every 30 days Zumi asks "Is it still available?" — answer in one tap. If you don''t answer within 7 days, the listing is hidden until you confirm.', 25, false),
  ('e006954a-f026-5b32-8601-362ddb8a456e', 'listings', 'Map pin, address and what is nearby', 'When you post a listing:
- Pin on the map (required): zoom in and put the pin where the property is, as close as you can. People use it to plan a visit.
- Address (optional): street, plot number or a landmark. It is shown on the listing — leave it empty if you prefer to share it in chat.
- What''s nearby (optional): shops, school, hospital or clinic, main road — choose the distance. People see it on the listing and decide faster.

You can change all of this later: My listings → … → Edit.', 35, false),
  ('ad2ff5a7-e5ff-57ed-a447-10272eaca2c1', 'technical', 'The site does not open or shows an old version', '- Check your internet: open any other website.
- Refresh the page: on a computer press Ctrl+Shift+R (Windows) or Cmd+Shift+R in Chrome / Cmd+Option+R in Safari (Mac). On a phone close the tab and open zumi again.
- If Zumi is added to your home screen: close the app completely (swipe it away) and open it again.
- The first visit on a slow network can take up to a minute — you will see "Zumi is still loading". The next visits are much faster.
- Still not working? Try another browser (Chrome works best) and write to Help & support with your phone model.', 20, false),
  ('11f8fbeb-739a-5f9e-813e-ae9308c7766c', 'technical', 'I am not getting emails from Zumi', 'Zumi sends emails to confirm your account and to reset your password.
- Check the Spam, Junk and Promotions folders. Mark the email as "Not spam" so the next ones arrive in your inbox.
- Wait 2–3 minutes — sometimes emails come late.
- Check that the email address is correct: Profile → Settings.
- Tap "Resend" no more than once a minute — too many requests are blocked for a while.

Still nothing after 10 minutes? Write to Help & support.', 30, false),
  ('61ba9a12-4b69-527d-a705-bf24aa6de808', 'contact', 'The WhatsApp button does not open', '- WhatsApp must be installed on your phone. On a computer, WhatsApp Web or the WhatsApp app opens.
- Zumi shows a number only after you confirm your own phone — it protects owners and agents from spam.
- Some owners choose "Chat only" — then there is no WhatsApp button. Use Message instead.
- When WhatsApp opens, a ready message with the listing name, price and area is already typed. You can change it before sending.', 30, false),
  ('fa939f25-45f1-516b-a16c-42bdc0c33492', 'contact', 'New messages and the number on Chats', 'The number on the Chats icon shows how many conversations have new messages. Inside Chats, each conversation shows how many messages are new. Open the conversation — the number disappears.

The number on the Profile icon means your listings need an answer: "Is it still available?".', 40, false),
  ('10397b75-c9d2-5833-8786-5b63e16e9dd8', 'account', 'Where my data is stored', 'Your account data, listings, photos and messages are stored on secure Supabase servers in the European Union (Ireland), which means outside Zambia. You agree to this when you create an account.
- Data is encrypted on the way and on the servers.
- Your phone number is never public. People see it only after they confirm their own number, or not at all if you choose "Chat only".
- We never sell your data.
- You can delete your account any time: Settings → Delete my account. Ask for a copy of your data in Help & support.

Full details: Settings → Privacy Policy.', 40, false),
  ('c1693f27-4d95-539e-9e8e-be6bad8c9d33', 'technical', 'How to send feedback about the app', 'We want Zumi to be simple and fast for you. After a few minutes of use, Zumi may ask "How is Zumi working for you?" — choose a rating and tell us what is not working. It takes 20 seconds.

You can also send feedback any time: Profile → Settings → "Send feedback about the app". The Zumi team reads every message.', 50, false)
on conflict (id) do nothing;

-- ---------------------------------------------------------------------
-- 2. Отзывы о приложении
-- ---------------------------------------------------------------------
create table if not exists public.app_feedback (
  id          uuid primary key default gen_random_uuid(),
  user_id     uuid references public.profiles(id) on delete set null,
  device_hash text,                                   -- зашифрованная метка устройства (гость)
  rating      int  not null check (rating between 1 and 5),
  issues      text[] not null default '{}',
  comment     text check (comment is null or length(comment) <= 1000),
  platform    text,
  app_version text,
  created_at  timestamptz not null default now()
);
create index if not exists app_feedback_created_idx on public.app_feedback (created_at desc);
alter table public.app_feedback enable row level security;   -- читать напрямую нельзя никому, только через функцию владельца

create or replace function public.send_app_feedback(p_rating int, p_issues text[], p_comment text,
                                                    p_platform text, p_version text, p_device text default null)
returns void language plpgsql security definer set search_path = public, extensions as $$
declare
  v_hash text := case when p_device is null or p_device = '' then null else md5('fb' || p_device) end;
  v_issues text[];
begin
  if p_rating is null or p_rating < 1 or p_rating > 5 then raise exception 'BAD_RATING'; end if;
  select coalesce(array_agg(i), '{}') into v_issues from unnest(coalesce(p_issues, '{}')) i
   where i in ('slow', 'crash', 'photos', 'login', 'search', 'chat', 'post', 'confusing', 'other');
  -- не чаще раза в день с человека / устройства (защита от потока)
  if exists (select 1 from app_feedback
              where created_at > now() - interval '1 day'
                and ((auth.uid() is not null and user_id = auth.uid()) or (v_hash is not null and device_hash = v_hash))) then
    raise exception 'TOO_MANY_REQUESTS';
  end if;
  if (select count(*) from app_feedback where created_at > now() - interval '1 hour') > 500 then
    raise exception 'TOO_MANY_REQUESTS';
  end if;
  insert into app_feedback (user_id, device_hash, rating, issues, comment, platform, app_version)
  values (auth.uid(), v_hash, p_rating, v_issues, nullif(left(trim(coalesce(p_comment, '')), 1000), ''),
          left(coalesce(p_platform, ''), 20), left(coalesce(p_version, ''), 20));
end $$;
grant execute on function public.send_app_feedback(int, text[], text, text, text, text) to anon, authenticated;

-- для кабинета разработчика: сводка и последние отзывы
create or replace function public.owner_app_feedback(p_days int default 30)
returns jsonb language plpgsql stable security definer set search_path = public, extensions as $$
declare v_from timestamptz := now() - make_interval(days => greatest(1, least(coalesce(p_days, 30), 365)));
begin
  if not public.is_owner() then raise exception 'OWNER_ONLY'; end if;
  return jsonb_build_object(
    'count',   (select count(*) from app_feedback where created_at >= v_from),
    'average', (select round(avg(rating)::numeric, 2) from app_feedback where created_at >= v_from),
    'by_rating', (select coalesce(jsonb_object_agg(rating, n), '{}'::jsonb) from
                   (select rating, count(*) n from app_feedback where created_at >= v_from group by rating) x),
    'issues', (select coalesce(jsonb_object_agg(i, n), '{}'::jsonb) from
                (select i, count(*) n from app_feedback, unnest(issues) i where created_at >= v_from group by i) x),
    'items', (select coalesce(jsonb_agg(jsonb_build_object(
                'rating', f.rating, 'issues', f.issues, 'comment', f.comment, 'platform', f.platform,
                'version', f.app_version, 'at', f.created_at,
                'who', case when f.user_id is null then 'Guest' else coalesce(pr.full_name, 'User') end)
                order by f.created_at desc), '[]'::jsonb)
              from (select * from app_feedback where created_at >= v_from order by created_at desc limit 200) f
              left join profiles pr on pr.id = f.user_id)
  );
end $$;
grant execute on function public.owner_app_feedback(int) to authenticated;

-- уборка: отзывы храним 1 год
create or replace function public.cleanup_feedback()
returns void language sql security definer set search_path = public, extensions as $$
  delete from app_feedback where created_at < now() - interval '1 year';
$$;

-- ---------------------------------------------------------------------
-- 3. Выключатель продвижения (по умолчанию выключено)
-- ---------------------------------------------------------------------
insert into public.app_settings values ('promotion_enabled', 'false') on conflict do nothing;

create or replace function public.promotion_on()
returns boolean language sql stable security definer set search_path = public, extensions as $$
  select coalesce((select value from app_settings where key = 'promotion_enabled'), 'false') = 'true';
$$;

-- что включено — приложение спрашивает при запуске
create or replace function public.app_flags()
returns jsonb language sql stable security definer set search_path = public, extensions as $$
  select jsonb_build_object('promotion', public.promotion_on());
$$;
grant execute on function public.app_flags() to anon, authenticated;

-- включить / выключить может только владелец
create or replace function public.admin_set_setting(p_key text, p_value text)
returns void language plpgsql security definer set search_path = public, extensions as $$
begin
  if not public.is_admin() then raise exception 'NOT_ADMIN'; end if;
  if p_key not in ('otp_test_mode', 'require_licence_to_publish', 'promotion_enabled') then raise exception 'BAD_SETTING'; end if;
  if p_key = 'promotion_enabled' and not public.is_owner() then raise exception 'OWNER_ONLY'; end if;
  if p_value not in ('true', 'false') then raise exception 'BAD_SETTING'; end if;
  insert into app_settings (key, value) values (p_key, p_value)
  on conflict (key) do update set value = excluded.value;
  perform public._audit('setting', 'settings', p_key, p_value);
end $$;

-- пока выключено: кампанию нельзя запустить…
create or replace function public.promotion_switch()
returns trigger language plpgsql security definer set search_path = public, extensions as $$
begin
  if new.status = 'active' and not public.promotion_on()
     and (tg_op = 'INSERT' or old.status is distinct from 'active') then
    raise exception 'PROMOTION_OFF';
  end if;
  return new;
end $$;
drop trigger if exists promotion_switch on public.campaigns;
create trigger promotion_switch before insert or update of status on public.campaigns
  for each row execute function public.promotion_switch();

-- …и уже запущенные никому не показываются (кроме автора и команды)
drop policy if exists "promotion switch" on public.campaigns;
create policy "promotion switch" on public.campaigns as restrictive for select
  using (public.promotion_on() or owner_id = auth.uid() or public.is_admin());

-- статус для кабинета
create or replace function public.admin_promotion_status()
returns jsonb language plpgsql stable security definer set search_path = public, extensions as $$
begin
  if not public.is_admin() then raise exception 'NOT_ADMIN'; end if;
  return jsonb_build_object('enabled', public.promotion_on(),
    'live_campaigns', (select count(*) from campaigns where status = 'active' and ends_on >= current_date));
end $$;
grant execute on function public.admin_promotion_status() to authenticated;


-- =====================================================================
--  Zumi — 021: обновление старых статей помощи под новые правила
--  («Number checked», телефон для публикации, «ещё доступно?» через 30 дней,
--  лицензия ZIEA без продвижения). Меняются только статьи, которые команда не правила сама.
--  Запускать после 020. Можно запускать повторно.
-- =====================================================================
update public.help_articles set body = 'You sign in to Zumi with your email and password.

## Confirming your phone
You need a confirmed phone to publish a listing and to see phone numbers in listings. Your listings then show "Number checked". You do it only once:
- Open Profile → Get verified (or Settings → Phone & verification).
- Choose WhatsApp or SMS and enter your number with the country code, e.g. +260 97 123 4567.
- Type the 6-digit code you receive. It works for 10 minutes.

## Good to know
- One phone number can be confirmed on only one Zumi account.
- If you change your number in the profile, you need to confirm the new one.
- Forgot your password? On the sign-in screen tap "Forgot password?" — we send a code to your email. Type the whole code from the email (it can be 6–8 digits).'
 where id = 'e2bf5b54-9919-58d0-9461-2de87c71309d' and updated_by is null;
update public.help_articles set body = 'Estate agents in Zambia are registered with the Zambia Institute of Estate Agents (ZIEA). Zumi checks your registration number with the register — you don''t upload any documents.

- Add the number when you sign up as an agent (it is optional), or later in Profile → Get verified.
- Until it is checked, your listings and agent page show "ZIEA licence not verified".
- After the check your listings show the "Licensed agent" badge — people trust them more.

If your number was not approved, the reason is shown in Get verified. Check the number and send it again.'
 where id = 'a44d1cea-2bb5-5fdc-81f2-6aea36e74198' and updated_by is null;
update public.help_articles set body = 'Tap "Post" on the home screen (or "Post a listing" on the website) and follow the steps:
- Choose rent or sale and the type of property.
- Add a clear title, the price and the main details (bedrooms, bathrooms, size).
- Add good photos: daylight, every room, the outside and the street. 5 or more photos give people a clear picture.
- Put the pin on the map where the property is (required). The address and "what''s nearby" are optional.
- Check the preview and publish. The first time, Zumi asks you to confirm your phone with a code.

## Tips
- Write the real price, so people know right away if the home fits their budget.
- Do not put phone numbers or links inside photos or the description — use the contact settings instead.
- Every 30 days Zumi asks "Is it still available?" — answer in one tap. Without an answer for 7 days the listing is hidden from search (not deleted).'
 where id = 'e2232f2d-41f2-569a-a8f0-f3ebc63e88b5' and updated_by is null;


-- =====================================================================
--  Zumi — 022: автоматическое удаление старых данных (как обещано в Privacy Policy)
--  • записи «кто открыл номер» — старше 1 года;
--  • отзывы о приложении — старше 1 года;
--  • аккаунты, заблокированные за мошенничество, — через 2 года после блокировки
--    (если команда не отметила, что данные нужны полиции/суду: legal_hold);
--  • плюс ежедневная уборка из 014 (метки статистики, коды, старые заявки).
--  Запускается каждый день в 03:15 по расписанию (pg_cron). Перед запуском файла
--  включите pg_cron: Database → Extensions → pg_cron → Enable.
--  Запускать после 021. Можно запускать повторно.
-- =====================================================================

-- команда может «заморозить» удаление, пока идёт расследование
alter table public.profiles add column if not exists legal_hold boolean not null default false;

create or replace function public.cleanup_retention()
returns jsonb language plpgsql security definer set search_path = public, extensions as $$
declare v_reveals int; v_feedback int; v_banned int;
begin
  if not public._is_admin_or_service() and current_user not in ('postgres', 'supabase_admin') then
    raise exception 'NOT_ADMIN';
  end if;
  delete from phone_reveals where created_at < now() - interval '1 year';
  get diagnostics v_reveals = row_count;
  delete from app_feedback where created_at < now() - interval '1 year';
  get diagnostics v_feedback = row_count;
  -- заблокированные 2+ года назад: удаляем аккаунт целиком (профиль, объявления, фото-записи, чаты — каскадом)
  with gone as (
    delete from auth.users u
     using profiles p
     where p.id = u.id and p.banned_at is not null and p.banned_at < now() - interval '2 years' and not p.legal_hold
    returning u.id
  ) select count(*) into v_banned from gone;
  return jsonb_build_object('phone_reveals', v_reveals, 'app_feedback', v_feedback, 'banned_accounts', v_banned);
end $$;
revoke execute on function public.cleanup_retention() from public, anon, authenticated;

-- расписание: каждый день 03:15 — обычная уборка и сроки хранения
do $$
begin
  if exists (select 1 from pg_extension where extname = 'pg_cron') then
    perform cron.unschedule(jobid) from cron.job where jobname in ('zumi-cleanup-daily', 'zumi-retention');
    perform cron.schedule('zumi-cleanup-daily', '15 3 * * *', 'select public.cleanup_daily()');
    perform cron.schedule('zumi-retention', '20 3 * * *', 'select public.cleanup_retention()');
    raise notice 'Scheduled: zumi-cleanup-daily and zumi-retention';
  else
    raise notice 'pg_cron is not enabled: enable it in Database → Extensions, then run this file again';
  end if;
end $$;


-- =====================================================================
--  Zumi — 023: лимит объявлений для агентов
--  Агент с проверенной лицензией ZIEA — 10 бесплатных объявлений, без проверки — 5.
--  Собственники — 2 (без изменений). Купленные места (extra_listing_slots) добавляются сверху.
--  Если лицензию сняли — уже опубликованные объявления остаются, новые сверх 5 не добавить.
--  Запускать после 022. Можно запускать повторно.
-- =====================================================================
alter table public.role_limits add column if not exists free_listings_licensed int;
update public.role_limits set free_listings = 5, free_listings_licensed = 10 where role = 'agent';
update public.role_limits set free_listings = 2, free_listings_licensed = null where role = 'owner';

create or replace function public.listing_quota(uid uuid)
returns table (used int, allowed int) language sql stable security definer
set search_path = public, extensions as $$
  select
    (select count(*)::int from properties
      where owner_id = uid and status in ('active', 'draft', 'pending') and not is_demo),
    (select coalesce(
              case when p.role = 'agent' and p.licence_verified_at is not null
                   then coalesce(rl.free_listings_licensed, rl.free_listings)
                   else rl.free_listings end,
              999999) + p.extra_listing_slots
       from profiles p left join role_limits rl on rl.role = p.role
      where p.id = uid);
$$;

-- статья помощи про лицензию: + про лимит (если команда её не меняла)
update public.help_articles set body = body || '

## More listings with a licence
Agents can publish 5 listings for free. With a checked ZIEA licence — 10.'
 where id = 'a44d1cea-2bb5-5fdc-81f2-6aea36e74198' and updated_by is null
   and body not like '%More listings with a licence%';


-- =====================================================================
--  Zumi — 024: выключатель рекламных баннеров (по умолчанию выключено)
--  Пока Zumi полностью бесплатный, в приложении нет ни баннеров, ни шаблона «Your ad here».
--  Владелец включает их в кабинете → Ads. Баннеры можно готовить заранее — они ждут.
--  Запускать после 023. Можно запускать повторно.
-- =====================================================================
insert into public.app_settings values ('ads_enabled', 'false') on conflict do nothing;

create or replace function public.ads_on()
returns boolean language sql stable security definer set search_path = public, extensions as $$
  select coalesce((select value from app_settings where key = 'ads_enabled'), 'false') = 'true';
$$;

create or replace function public.app_flags()
returns jsonb language sql stable security definer set search_path = public, extensions as $$
  select jsonb_build_object('promotion', public.promotion_on(), 'ads', public.ads_on());
$$;
grant execute on function public.app_flags() to anon, authenticated;

-- пока выключено — баннеры никому, кроме команды, не отдаются
drop policy if exists "ads switch" on public.ads;
create policy "ads switch" on public.ads as restrictive for select
  using (public.ads_on() or public.is_admin());

-- менять могут: тестовый режим кодов и правило лицензий — команда; продвижение и баннеры — только владелец
create or replace function public.admin_set_setting(p_key text, p_value text)
returns void language plpgsql security definer set search_path = public, extensions as $$
begin
  if not public.is_admin() then raise exception 'NOT_ADMIN'; end if;
  if p_key not in ('otp_test_mode', 'require_licence_to_publish', 'promotion_enabled', 'ads_enabled') then
    raise exception 'BAD_SETTING';
  end if;
  if p_key in ('promotion_enabled', 'ads_enabled') and not public.is_owner() then raise exception 'OWNER_ONLY'; end if;
  if p_value not in ('true', 'false') then raise exception 'BAD_SETTING'; end if;
  insert into app_settings (key, value) values (p_key, p_value)
  on conflict (key) do update set value = excluded.value;
  perform public._audit('setting', 'settings', p_key, p_value);
end $$;

create or replace function public.admin_promotion_status()
returns jsonb language plpgsql stable security definer set search_path = public, extensions as $$
begin
  if not public.is_admin() then raise exception 'NOT_ADMIN'; end if;
  return jsonb_build_object(
    'enabled', public.promotion_on(),
    'live_campaigns', (select count(*) from campaigns where status = 'active' and ends_on >= current_date),
    'ads_enabled', public.ads_on(),
    'live_ads', (select count(*) from ads where status = 'active' and current_date between starts_on and ends_on));
end $$;
grant execute on function public.admin_promotion_status() to authenticated;

-- =====================================================================
--  Zumi — 026: вход через Google (и позже Facebook)
--  При входе через Google человек не видит нашу форму регистрации: не выбирает
--  «агент / владелец» и не ставит галочку согласия. Поэтому после первого входа
--  приложение показывает экран «Finish setting up», и он вызывает complete_signup().
--  Пока согласие не дано (terms_accepted_at пуст), такой аккаунт не может
--  публиковать объявления.
--  Запускать после 025. Можно запускать повторно.
-- =====================================================================

-- аккаунт, созданный через Google/Facebook, ещё не завершил регистрацию?
create or replace function public._needs_onboarding(p_uid uuid)
returns boolean language sql stable security definer set search_path = public, extensions as $$
  select exists (select 1 from profiles where id = p_uid and terms_accepted_at is null)
     and exists (select 1 from auth.identities i where i.user_id = p_uid and i.provider in ('google', 'facebook'))
     and not exists (select 1 from auth.identities i where i.user_id = p_uid and i.provider = 'email');
$$;
revoke execute on function public._needs_onboarding(uuid) from public, anon;

-- что знает о себе пользователь: + флаг «закончить регистрацию»
create or replace function public.my_verification()
returns jsonb language sql stable security definer set search_path = public, extensions as $$
  select jsonb_build_object(
    'id_status', (select status from verification_requests
                   where user_id = auth.uid() and kind = 'identity' order by created_at desc limit 1),
    'id_note',   (select reviewer_note from verification_requests
                   where user_id = auth.uid() and kind = 'identity' order by created_at desc limit 1),
    'licence_note', (select licence_note from profiles where id = auth.uid()),
    'phone', (select phone from profiles where id = auth.uid()),
    'whatsapp', (select whatsapp from profiles where id = auth.uid()),
    'phone_channel', (select phone_verify_channel from profiles where id = auth.uid()),
    'email_verified', (select email_verified_at is not null from profiles where id = auth.uid()),
    'marketing_email', (select marketing_email_at is not null from profiles where id = auth.uid()),
    'marketing_whatsapp', (select marketing_whatsapp_at is not null from profiles where id = auth.uid()),
    'needs_onboarding', public._needs_onboarding(auth.uid())
  );
$$;

-- экран «Finish setting up»: роль, имя, телефон, лицензия, согласие — один раз
create or replace function public.complete_signup(
  p_role text, p_full_name text, p_phone text, p_licence text default null,
  p_terms boolean default false, p_marketing boolean default false)
returns void language plpgsql security definer set search_path = public, extensions as $$
declare uid uuid := auth.uid();
begin
  if uid is null then raise exception 'AUTH'; end if;
  if not public._needs_onboarding(uid) then raise exception 'ALREADY_DONE'; end if;
  if p_terms is not true then raise exception 'TERMS_REQUIRED'; end if;
  if p_role not in ('owner', 'agent') then raise exception 'BAD_ROLE'; end if;
  if length(trim(coalesce(p_full_name, ''))) < 2 then raise exception 'BAD_NAME'; end if;
  if length(public._norm_phone(coalesce(p_phone, ''))) < 9 then raise exception 'BAD_PHONE'; end if;
  update profiles set
    role = p_role,
    full_name = left(trim(p_full_name), 80),
    phone = left(trim(p_phone), 30),
    agent_licence_no = case when p_role = 'agent' then nullif(left(trim(coalesce(p_licence, '')), 40), '') end,
    terms_accepted_at = now(),
    marketing_email_at = case when p_marketing then now() end,
    marketing_whatsapp_at = case when p_marketing then now() end
  where id = uid;
end $$;
revoke execute on function public.complete_signup(text, text, text, text, boolean, boolean) from public, anon;
grant execute on function public.complete_signup(text, text, text, text, boolean, boolean) to authenticated;

-- без согласия с условиями объявление не опубликовать (защита на сервере)
create or replace function public.require_terms_to_post()
returns trigger language plpgsql security definer set search_path = public, extensions as $$
begin
  if auth.uid() is not null and new.owner_id = auth.uid() and public._needs_onboarding(auth.uid()) then
    raise exception 'FINISH_SIGNUP';
  end if;
  return new;
end $$;
drop trigger if exists require_terms_to_post on public.properties;
create trigger require_terms_to_post before insert on public.properties
  for each row execute function public.require_terms_to_post();

-- =====================================================================
--  Zumi — 027: подтверждение номера через WhatsApp (человек пишет нам сам)
--  1. В приложении: «Confirm with WhatsApp» → сервер выдаёт одноразовый код (15 минут).
--  2. Открывается WhatsApp с готовым сообщением «Zumi code 123456» на номер Zumi.
--  3. Сообщение приходит в функцию whatsapp-webhook → confirm_whatsapp_code():
--     номер, С КОТОРОГО написали, становится подтверждённым номером аккаунта.
--  Входящие сообщения WhatsApp бесплатны — платить за коды не нужно.
--  Номер Zumi для подтверждения: настройка whatsapp_verify_number (пусто — выключено).
--  Запускать после 026. Можно запускать повторно.
-- =====================================================================

create table if not exists public.wa_verify_codes (
  code       text primary key,
  user_id    uuid not null references public.profiles(id) on delete cascade,
  created_at timestamptz not null default now(),
  expires_at timestamptz not null,
  used_at    timestamptz
);
alter table public.wa_verify_codes enable row level security;  -- без политик: только через функции
create index if not exists wa_verify_codes_user_idx on public.wa_verify_codes (user_id, created_at);

-- номер Zumi, на который люди пишут (цифры с кодом страны, например 15551637510)
insert into public.app_settings (key, value) values ('whatsapp_verify_number', '')
on conflict (key) do nothing;

create or replace function public._wa_verify_number()
returns text language sql stable security definer set search_path = public, extensions as $$
  select nullif(regexp_replace(coalesce((select value from app_settings where key = 'whatsapp_verify_number'), ''),
                               '[^0-9]', '', 'g'), '');
$$;

-- что включено: + номер WhatsApp для подтверждения (публичный бизнес-номер)
create or replace function public.app_flags()
returns jsonb language sql stable security definer set search_path = public, extensions as $$
  select jsonb_build_object('promotion', public.promotion_on(), 'ads', public.ads_on(),
                            'wa_verify', public._wa_verify_number());
$$;
grant execute on function public.app_flags() to anon, authenticated;

-- шаг 1: выдать код (старые неиспользованные коды человека сгорают)
create or replace function public.start_whatsapp_verification()
returns jsonb language plpgsql security definer set search_path = public, extensions as $$
declare
  uid uuid := auth.uid();
  v_num text := public._wa_verify_number();
  v_code text;
begin
  if uid is null then raise exception 'AUTH'; end if;
  if v_num is null then raise exception 'FEATURE_OFF'; end if;
  if exists (select 1 from profiles where id = uid and banned_at is not null) then raise exception 'ACCOUNT_BLOCKED'; end if;
  if (select count(*) from wa_verify_codes where user_id = uid and created_at > now() - interval '1 hour') >= 10 then
    raise exception 'TOO_MANY_CODES';
  end if;
  delete from wa_verify_codes where (user_id = uid and used_at is null) or expires_at < now() - interval '1 day';
  loop
    v_code := lpad((floor(random() * 1000000))::int::text, 6, '0');
    exit when not exists (select 1 from wa_verify_codes where code = v_code);
  end loop;
  insert into wa_verify_codes (code, user_id, expires_at) values (v_code, uid, now() + interval '15 minutes');
  return jsonb_build_object('code', v_code, 'number', v_num);
end $$;
revoke execute on function public.start_whatsapp_verification() from public, anon;
grant execute on function public.start_whatsapp_verification() to authenticated;

-- шаг 2: пришло сообщение в WhatsApp (вызывает только функция whatsapp-webhook с ключом сервиса)
create or replace function public.confirm_whatsapp_code(p_text text, p_from text)
returns text language plpgsql security definer set search_path = public, extensions as $$
declare
  v_code text := substring(coalesce(p_text, '') from '(\d{6})');
  v_phone text := '+' || regexp_replace(coalesce(p_from, ''), '[^0-9]', '', 'g');
  c record;
begin
  if v_code is null or length(v_phone) < 10 then return 'unknown'; end if;
  select * into c from wa_verify_codes where code = v_code;
  if c is null or c.used_at is not null or c.expires_at < now() then return 'expired'; end if;
  if public._phone_taken(v_phone, c.user_id) then return 'taken'; end if;
  update wa_verify_codes set used_at = now() where code = v_code;
  update profiles set phone = v_phone, phone_verified_at = now(), phone_verify_channel = 'whatsapp'
   where id = c.user_id;
  return 'ok';
end $$;
revoke execute on function public.confirm_whatsapp_code(text, text) from public, anon, authenticated;
grant execute on function public.confirm_whatsapp_code(text, text) to service_role;

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

-- =====================================================================
--  Zumi — 029: мелкая защита после проверки 05.11
--  • служебные функции уборки нельзя вызвать из приложения (только расписание pg_cron / команда)
--  Запускать после 028. Можно запускать повторно.
-- =====================================================================
revoke execute on function public.cleanup_feedback() from public, anon, authenticated;
revoke execute on function public.cleanup_orders() from public, anon, authenticated;
revoke execute on function public._wa_verify_number() from public, anon, authenticated;
grant execute on function public._wa_verify_number() to service_role;

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
-- =====================================================================
--  Zumi — 032: бесплатный лимит агента с лицензией ZIEA — 20 (было 25). Без лицензии — 15, собственник — 2.
--  Уже размещённые объявления не трогаем: лимит действует только на новые и на возврат скрытых.
--  Запускать после 031. Можно запускать повторно.
-- =====================================================================
update public.role_limits set free_listings = 15, free_listings_licensed = 20 where role = 'agent';

-- проверка: 15 и 20
select role, free_listings, free_listings_licensed from public.role_limits where role in ('agent', 'owner') order by role;
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
-- =====================================================================
--  Zumi — 035: смена типа аккаунта
--  • Собственник → агент: сам, в Settings (агенту больше лимит, но его объявления помечаются
--    «агент», а без проверенной лицензии ZIEA — «licence not verified»).
--  • Агент → собственник и любые другие случаи — только команда Zumi (кабинет → New accounts),
--    чтобы агенты не прятались под видом собственников.
--  Объявления человека меняют пометку «Agent / Owner» вместе с аккаунтом.
--  Запускать после 034. Можно запускать повторно.
-- =====================================================================

create or replace function public.become_agent(p_licence text default null)
returns void language plpgsql security definer set search_path = public, extensions as $$
declare uid uuid := auth.uid(); v_role text;
begin
  if uid is null then raise exception 'AUTH'; end if;
  select role into v_role from profiles where id = uid;
  if v_role = 'agent' then return; end if;
  if v_role <> 'owner' then raise exception 'ASK_SUPPORT'; end if;
  update profiles set
    role = 'agent',
    agent_licence_no = coalesce(nullif(left(trim(coalesce(p_licence, '')), 40), ''), agent_licence_no)
  where id = uid;
  update properties set listed_by = 'agent' where owner_id = uid and not is_demo;
  perform public._audit('account_type', 'profile', uid::text, 'owner → agent (self)');
end $$;
revoke execute on function public.become_agent(text) from public, anon;
grant execute on function public.become_agent(text) to authenticated;

create or replace function public.admin_set_account_type(p_email text, p_type text)
returns text language plpgsql security definer set search_path = public, extensions, auth as $$
declare v_id uuid; v_role text;
begin
  if not public.is_admin() then raise exception 'FORBIDDEN'; end if;
  if p_type not in ('owner', 'agent') then raise exception 'BAD_TYPE'; end if;
  select u.id into v_id from auth.users u where lower(u.email) = lower(trim(p_email));
  if v_id is null then raise exception 'USER_NOT_FOUND'; end if;
  select role into v_role from profiles where id = v_id;
  if v_role = 'admin' then raise exception 'TEAM_ACCOUNT'; end if;
  if p_type = 'owner' and exists (select 1 from profiles where id = v_id and agency_id is not null) then
    raise exception 'IN_AGENCY'; -- сначала выйти из агентства (или закрыть его)
  end if;
  update profiles set role = p_type where id = v_id;
  update properties set listed_by = p_type where owner_id = v_id and not is_demo;
  perform public._audit('account_type', 'profile', v_id::text, coalesce(v_role, '?') || ' → ' || p_type);
  return coalesce(v_role, '?') || ' → ' || p_type;
end $$;
revoke execute on function public.admin_set_account_type(text, text) from public, anon;
grant execute on function public.admin_set_account_type(text, text) to authenticated;

-- проверка: обе функции на месте
select
  exists (select 1 from pg_proc where proname = 'become_agent') as self_ok,
  exists (select 1 from pg_proc where proname = 'admin_set_account_type') as team_ok;
-- =====================================================================
--  Zumi — 036: лимиты и «Ещё актуально?» для агентов
--  • Бесплатные лимиты: собственник 3; агент без лицензии 10, с лицензией 15; агентство — 25 на всех.
--  • «Ещё актуально?»: агентам — каждые 7 дней, без ответа объявление уходит в паузу (из поиска) через 10 дней;
--    собственникам — через 30 / пауза через 37; комнаты — 14 / 21.
--  • Письмо «Ещё актуально?» — одно на человека (со списком), не чаще раза в 6 дней.
--  Уже размещённые объявления не удаляются. Запускать после 035. Можно запускать повторно.
-- =====================================================================

update public.role_limits set free_listings = 3 where role = 'owner';
update public.role_limits set free_listings = 10, free_listings_licensed = 15 where role = 'agent';
update public.role_limits set free_listings = 25, free_listings_licensed = 25 where role = 'agency';

-- через сколько спрашивать и когда ставить на паузу
create or replace function public._ask_interval(p_type text, p_listed_by text)
returns interval language sql immutable as $$
  select case when p_type = 'room' then interval '14 days'
              when p_listed_by = 'agent' then interval '7 days'
              else interval '30 days' end;
$$;
create or replace function public._hide_interval(p_type text, p_listed_by text)
returns interval language sql immutable as $$
  select case when p_type = 'room' then interval '21 days'
              when p_listed_by = 'agent' then interval '10 days'
              else interval '37 days' end;
$$;

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
            now() - public._hide_interval(p.property_type, p.listed_by)) as is_fresh,
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

create or replace function public.my_listings_to_confirm()
returns int language sql stable security definer set search_path = public, extensions as $$
  select count(*)::int from properties
   where owner_id = auth.uid() and status = 'active' and not is_demo
     and coalesce(confirmed_at, approved_at, created_at) < now() - public._ask_interval(property_type, listed_by);
$$;

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
    -- одно письмо на человека за раз, даже если объявлений много (агентам — раз в неделю)
    select x.owner_id, 'confirm'::text, x.owner_id, 4,
           jsonb_build_object('count', x.n, 'title', x.title, 'listing_id', x.listing_id, 'hide_in', x.hide_in)
      from (
        select p.owner_id, count(*)::int as n,
               (array_agg(p.title order by coalesce(p.confirmed_at, p.approved_at, p.created_at)))[1] as title,
               (array_agg(p.id order by coalesce(p.confirmed_at, p.approved_at, p.created_at)))[1] as listing_id,
               greatest(1, min(extract(day from public._hide_interval(p.property_type, p.listed_by))::int
                 - extract(day from now() - coalesce(p.confirmed_at, p.approved_at, p.created_at))::int)) as hide_in
          from properties p
         where p.owner_id is not null and not p.is_demo and p.status = 'active'
           and coalesce(p.confirmed_at, p.approved_at, p.created_at) < now() - public._ask_interval(p.property_type, p.listed_by)
         group by p.owner_id
      ) x
     where not exists (select 1 from email_log l
                        where l.user_id = x.owner_id and l.kind = 'confirm' and l.sent_at > now() - interval '6 days')
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

-- проверка
select role, free_listings, free_listings_licensed from public.role_limits order by role;


-- =====================================================================
--  Zumi — 037: защита от «спящих» мошенников и от уже сданных объявлений
--  1. Новый аккаунт: ВСЕ объявления проверяет команда первые 14 дней
--     (раньше — только первые 2, дальше публиковалось сразу).
--     После 14 дней и 2 одобренных объявлений — публикуется сразу, как раньше.
--  2. Жалоба «Property is not available» от 2 разных людей → автор сразу получает
--     вопрос «Still available?» (в приложении и письмом). Не ответил — объявление
--     само уходит в паузу через несколько дней (агент 3 дня, собственник/комната 7).
--     Объявление НЕ скрывается сразу — чтобы конкуренты не могли «гасить» чужие объявления жалобами.
--  3. Новое поле «сколько месяцев платить вперёд» + фильтр. «Свет и вода» — без изменений в базе.
--  Запускать после 036. Можно запускать повторно.
-- =====================================================================

-- 1. проверка новых аккаунтов
create or replace function public.moderate_new_listing()
returns trigger language plpgsql security definer set search_path = public, extensions as $$
begin
  if new.is_demo or new.owner_id is null then
    new.approved_at := coalesce(new.approved_at, now());
    return new;
  end if;
  if (select count(*) from properties where owner_id = new.owner_id and approved_at is not null) >= 2
     and coalesce((select created_at from profiles where id = new.owner_id), now()) < now() - interval '14 days' then
    new.approved_at := now();
  else
    new.status := 'pending';
    new.approved_at := null;
  end if;
  new.moderation_note := null;
  return new;
end $$;

-- 2. жалобы
create or replace function public.on_listing_report()
returns trigger language plpgsql security definer set search_path = public, extensions as $$
declare
  p properties%rowtype;
  v_since timestamptz;
begin
  update properties set reports_count = reports_count + 1 where id = new.property_id;

  -- мошенничество: 3 жалобы от людей с подтверждённым телефоном → скрыть до проверки
  if (select count(*) from listing_reports r join profiles pr on pr.id = r.reporter_id
       where r.property_id = new.property_id and r.reason in ('scam', 'asked_prepayment')
         and pr.phone_verified_at is not null) >= 3 then
    update properties set status = 'archived', property_verified_at = null where id = new.property_id;
  end if;

  -- «уже сдан»: 2 разных человека после последнего подтверждения → спросить автора прямо сейчас
  if new.reason = 'not_available' then
    select * into p from properties where id = new.property_id;
    v_since := coalesce(p.confirmed_at, p.approved_at, p.created_at);
    if p.status = 'active'
       and (select count(distinct r.reporter_id) from listing_reports r
             where r.property_id = p.id and r.reason = 'not_available' and r.created_at > v_since) >= 2 then
      update properties
         set confirmed_at = least(v_since, now() - public._ask_interval(p.property_type, p.listed_by))
       where id = p.id;
    end if;
  end if;
  return new;
end $$;


-- 3. аренда: сколько месяцев платить вперёд (по желанию автора) — для фильтра «Rent paid upfront»
alter table public.properties add column if not exists advance_months smallint;
alter table public.properties drop constraint if exists properties_advance_ok;
alter table public.properties add constraint properties_advance_ok
  check (advance_months is null or (advance_months between 1 and 24 and deal_type = 'rent'));

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
            now() - public._hide_interval(p.property_type, p.listed_by)) as is_fresh,
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
         p.units_total, p.units_available,
         p.advance_months
    from properties p
    left join areas a     on a.id  = p.area_id
    left join profiles pr on pr.id = p.owner_id
   where (p.status = 'active' and (p.property_type <> 'room' or public.rooms_on()))
      or p.owner_id = auth.uid() or public.is_admin();
grant select on public.property_feed to anon, authenticated;

