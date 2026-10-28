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
