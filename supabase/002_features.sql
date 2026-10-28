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
