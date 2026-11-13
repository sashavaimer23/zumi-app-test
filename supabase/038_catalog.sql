-- =====================================================================
--  Zumi — 038: каталог агента (портфолио) с красивой ссылкой zumihome.com/<имя>
--  • У агента появляется короткий адрес (slug), например zumihome.com/john-banda.
--    Создаётся сам при первом открытии «My catalogue», агент может поменять.
--  • «О себе», районы работы, показывать ли WhatsApp в каталоге (по умолчанию — да).
--  • Счётчик просмотров каталога (по дням).
--  • Страница каталога — лёгкая (Cloudflare), открывается и на плохом интернете.
--  Запускать после 037. Можно запускать повторно.
-- =====================================================================

alter table public.profiles
  add column if not exists slug text,
  add column if not exists catalog_areas text,
  add column if not exists catalog_public_contact boolean not null default true;

alter table public.profiles drop constraint if exists profiles_slug_ok;
alter table public.profiles add constraint profiles_slug_ok
  check (slug is null or slug ~ '^[a-z0-9][a-z0-9-]{1,38}[a-z0-9]$');
alter table public.profiles drop constraint if exists profiles_catalog_areas_ok;
alter table public.profiles add constraint profiles_catalog_areas_ok
  check (catalog_areas is null or length(catalog_areas) <= 120);
create unique index if not exists profiles_slug_key on public.profiles (slug) where slug is not null;

-- просмотры каталога по дням (только сервер)
create table if not exists public.catalog_views (
  profile_id uuid not null references public.profiles(id) on delete cascade,
  day        date not null default current_date,
  n          int  not null default 0,
  primary key (profile_id, day)
);
alter table public.catalog_views enable row level security;

-- адреса, которые заняты сайтом
create or replace function public._slug_reserved(s text)
returns boolean language sql immutable as $$
  select s = any (array['agents','agent','agency','agencies','l','rent','buy','terms','privacy','delete-account',
    'sitemap','admin','api','assets','icons','canvaskit','help','support','login','signup','sign-up','register',
    'zumi','about','blog','app','settings','search','map','post','www','mail','hello','team','owner','owners',
    'catalog','catalogue','listing','listings','home','index','robots','favicon','manifest','join','invite',
    'pricing','plans','contact','news','jobs','careers','legal','security','status','test','staging'])
    or s ~ '^(rent|buy)-';
$$;

-- адрес из имени: «John Banda» → john-banda (если занят — john-banda-2 …)
create or replace function public._make_slug(p_name text)
returns text language plpgsql volatile security definer set search_path = public, extensions as $$
declare
  base text := trim(both '-' from regexp_replace(lower(coalesce(p_name, '')), '[^a-z0-9]+', '-', 'g'));
  s text;
  i int := 1;
begin
  base := left(base, 32);
  base := trim(both '-' from base);
  if length(base) < 3 then base := 'agent-' || base; end if;
  base := trim(both '-' from base);
  s := base;
  while public._slug_reserved(s) or exists (select 1 from profiles where slug = s) loop
    i := i + 1;
    s := base || '-' || i;
    if i > 50 then s := base || '-' || substr(md5(random()::text), 1, 4); end if;
  end loop;
  return s;
end $$;
revoke execute on function public._make_slug(text) from public, anon, authenticated;

-- мой каталог (для «My catalogue» в профиле)
create or replace function public.my_catalog()
returns jsonb language plpgsql security definer set search_path = public, extensions as $$
declare
  uid uuid := auth.uid();
  pr profiles%rowtype;
begin
  if uid is null then raise exception 'AUTH'; end if;
  select * into pr from profiles where id = uid;
  if pr.slug is null then
    update profiles set slug = public._make_slug(coalesce(nullif(trim(pr.full_name), ''), pr.agency_name, 'agent'))
     where id = uid returning * into pr;
  end if;
  return jsonb_build_object(
    'slug', pr.slug,
    'bio', pr.bio,
    'areas', pr.catalog_areas,
    'public_contact', pr.catalog_public_contact,
    'views_7d', coalesce((select sum(n) from catalog_views where profile_id = uid and day > current_date - 7), 0),
    'views_total', coalesce((select sum(n) from catalog_views where profile_id = uid), 0));
end $$;
revoke execute on function public.my_catalog() from public, anon;
grant execute on function public.my_catalog() to authenticated;

create or replace function public.set_my_catalog(p_slug text, p_bio text, p_areas text, p_public_contact boolean)
returns text language plpgsql security definer set search_path = public, extensions as $$
declare
  uid uuid := auth.uid();
  s text := lower(trim(coalesce(p_slug, '')));
begin
  if uid is null then raise exception 'AUTH'; end if;
  if s !~ '^[a-z0-9][a-z0-9-]{1,38}[a-z0-9]$' or s ~ '--' then raise exception 'BAD_SLUG'; end if;
  if public._slug_reserved(s) then raise exception 'SLUG_RESERVED'; end if;
  if exists (select 1 from profiles where slug = s and id <> uid) then raise exception 'SLUG_TAKEN'; end if;
  update profiles
     set slug = s,
         bio = nullif(left(trim(coalesce(p_bio, '')), 600), ''),
         catalog_areas = nullif(left(trim(coalesce(p_areas, '')), 120), ''),
         catalog_public_contact = coalesce(p_public_contact, true)
   where id = uid;
  return s;
end $$;
revoke execute on function public.set_my_catalog(text, text, text, boolean) from public, anon;
grant execute on function public.set_my_catalog(text, text, text, boolean) to authenticated;

-- страница каталога (видят все, без входа)
-- WhatsApp/телефон — только у агентов, с подтверждённым номером и если агент не выключил показ.
create or replace function public.catalog_page(p_slug text)
returns jsonb language sql stable security definer set search_path = public, extensions as $$
  select jsonb_build_object(
    'id', pr.id,
    'slug', pr.slug,
    'role', pr.role,
    'name', coalesce(nullif(trim(pr.full_name), ''), 'Agent'),
    'agency_name', nullif(trim(pr.agency_name), ''),
    'agency_id', pr.agency_id,
    'avatar_url', pr.avatar_url,
    'bio', pr.bio,
    'areas', pr.catalog_areas,
    'licensed', pr.role = 'agent' and pr.licence_verified_at is not null,
    'phone_checked', pr.phone_verified_at is not null,
    'since', to_char(pr.created_at, 'YYYY'),
    'contact', case when pr.role = 'agent' and pr.catalog_public_contact and pr.phone_verified_at is not null
                    then nullif(regexp_replace(coalesce(nullif(pr.whatsapp, ''), pr.phone, ''), '[^0-9]', '', 'g'), '')
               end)
    from profiles pr
   where pr.slug = lower(trim(p_slug)) and pr.banned_at is null;
$$;
grant execute on function public.catalog_page(text) to anon, authenticated;

-- +1 просмотр (зовёт страница каталога, только для людей, не для ботов)
create or replace function public.catalog_seen(p_slug text)
returns void language sql security definer set search_path = public, extensions as $$
  insert into catalog_views (profile_id, day, n)
  select id, current_date, 1 from profiles where slug = lower(trim(p_slug))
  on conflict (profile_id, day) do update set n = catalog_views.n + 1;
$$;
grant execute on function public.catalog_seen(text) to anon, authenticated;

-- проверка
select
  exists (select 1 from information_schema.columns where table_name = 'profiles' and column_name = 'slug') as slug_ok,
  (select count(*) from pg_proc where proname in ('my_catalog', 'set_my_catalog', 'catalog_page', 'catalog_seen')) = 4 as functions_ok;
