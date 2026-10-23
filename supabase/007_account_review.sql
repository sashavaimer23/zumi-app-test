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
returns void language plpgsql security definer set search_path = public as $$
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
returns jsonb language sql stable security definer set search_path = public as $$
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
) language plpgsql stable security definer set search_path = public, auth as $$
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
returns void language plpgsql security definer set search_path = public as $$
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
returns jsonb language plpgsql stable security definer set search_path = public as $$
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
