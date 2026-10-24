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
returns void language plpgsql security definer set search_path = public as $$
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
returns text[] language plpgsql stable security definer set search_path = public, storage as $$
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
returns void language plpgsql security definer set search_path = public as $$
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
returns void language plpgsql security definer set search_path = public as $$
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
returns trigger language plpgsql security definer set search_path = public as $$
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
returns trigger language plpgsql security definer set search_path = public as $$
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
returns void language plpgsql security definer set search_path = public as $$
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
returns trigger language plpgsql security definer set search_path = public as $$
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
returns jsonb language plpgsql stable security definer set search_path = public as $$
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
