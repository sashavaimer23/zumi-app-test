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
returns boolean language sql stable security definer set search_path = public as $$
  select exists (select 1 from profiles where id = auth.uid() and role = 'admin');
$$;

alter table public.profiles
  add column if not exists banned_at  timestamptz,
  add column if not exists ban_reason text;

grant select (banned_at) on public.profiles to authenticated;

-- заблокированный пользователь не может публиковать объявления
create or replace function public.block_banned_posting()
returns trigger language plpgsql security definer set search_path = public as $$
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
returns void language sql security definer set search_path = public as $$
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
returns trigger language plpgsql security definer set search_path = public as $$
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
returns void language plpgsql security definer set search_path = public as $$
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
set search_path = public as $$
  select round(avg(rating)::numeric, 1), count(*)::int
    from reviews where target_id = uid and status = 'published';
$$;

-- ---------------------------------------------------------------------
-- 6. Решения команды (все — только для admin, всё пишется в журнал)
-- ---------------------------------------------------------------------
create or replace function public.admin_stats()
returns jsonb language plpgsql stable security definer set search_path = public as $$
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
returns void language plpgsql security definer set search_path = public as $$
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
returns void language plpgsql security definer set search_path = public as $$
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
returns void language plpgsql security definer set search_path = public as $$
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
returns void language plpgsql security definer set search_path = public as $$
begin
  if not public.is_admin() then raise exception 'NOT_ADMIN'; end if;
  update properties set status = 'active' where id = pid;
  perform public._audit('restore', 'listing', pid::text, null);
end $$;

create or replace function public.admin_unban(uid uuid)
returns void language plpgsql security definer set search_path = public as $$
begin
  if not public.is_admin() then raise exception 'NOT_ADMIN'; end if;
  update profiles set banned_at = null, ban_reason = null where id = uid;
  perform public._audit('unban', 'user', uid::text, null);
end $$;

-- обращения
create or replace function public.admin_set_ticket_status(tid uuid, new_status text)
returns void language plpgsql security definer set search_path = public as $$
begin
  if not public.is_admin() then raise exception 'NOT_ADMIN'; end if;
  update support_tickets set status = new_status where id = tid;
  perform public._audit(new_status, 'ticket', tid::text, null);
end $$;

-- отзывы: скрыть / вернуть / ответить от имени Zumi
create or replace function public.admin_moderate_review(rid uuid, p_action text, p_reply text default null)
returns void language plpgsql security definer set search_path = public as $$
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
