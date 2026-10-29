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
