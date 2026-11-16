-- =====================================================================
--  Zumi — 040: быстрая регистрация «Ищу жильё»
--  • При регистрации можно выбрать «Looking for a home» — короткая форма: имя, почта, пароль
--    (телефон не нужен). Такой человек может писать, сохранять, смотреть номера.
--  • Как только он выложит своё первое объявление — автоматически становится собственником.
--    Агентом — как и раньше, в Settings («Switch to agent»).
--  Технически это обычный аккаунт собственника с пометкой is_seeker.
--  Запускать после 039. Можно запускать повторно.
-- =====================================================================

alter table public.profiles add column if not exists is_seeker boolean not null default false;
grant select (is_seeker) on public.profiles to authenticated;

-- регистрация: роль 'seeker' → собственник с пометкой «ищу жильё»
create or replace function public.handle_new_user()
returns trigger language plpgsql security definer set search_path = public, extensions as $$
declare
  v_agent boolean := new.raw_user_meta_data->>'role' in ('agent', 'agency');
  v_agency text := nullif(left(trim(coalesce(new.raw_user_meta_data->>'agency_name', '')), 80), '');
  v_id uuid;
begin
  insert into public.profiles (id, full_name, phone, role, terms_accepted_at, agent_licence_no,
                               marketing_email_at, marketing_whatsapp_at, is_seeker)
  values (
    new.id,
    new.raw_user_meta_data->>'full_name',
    nullif(trim(coalesce(new.raw_user_meta_data->>'phone', '')), ''),
    case when v_agent then 'agent' else 'owner' end,
    case when (new.raw_user_meta_data->>'terms_accepted') = 'true' then now() end,
    case when v_agent then nullif(left(trim(coalesce(new.raw_user_meta_data->>'licence_no', '')), 40), '') end,
    case when (new.raw_user_meta_data->>'marketing') = 'true' then now() end,
    case when (new.raw_user_meta_data->>'marketing') = 'true' then now() end,
    coalesce(new.raw_user_meta_data->>'role', '') = 'seeker'
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

-- анкета после входа через Google: «Looking for a home» — без телефона
create or replace function public.complete_signup(
  p_role text, p_full_name text, p_phone text, p_licence text default null,
  p_terms boolean default false, p_marketing boolean default false)
returns void language plpgsql security definer set search_path = public, extensions as $$
declare uid uuid := auth.uid(); v_seeker boolean := p_role = 'seeker';
begin
  if uid is null then raise exception 'AUTH'; end if;
  if not public._needs_onboarding(uid) then raise exception 'ALREADY_DONE'; end if;
  if p_terms is not true then raise exception 'TERMS_REQUIRED'; end if;
  if p_role not in ('owner', 'agent', 'seeker') then raise exception 'BAD_ROLE'; end if;
  if length(trim(coalesce(p_full_name, ''))) < 2 then raise exception 'BAD_NAME'; end if;
  if not v_seeker and length(public._norm_phone(coalesce(p_phone, ''))) < 9 then raise exception 'BAD_PHONE'; end if;
  update profiles set
    role = case when v_seeker then 'owner' else p_role end,
    is_seeker = v_seeker,
    full_name = left(trim(p_full_name), 80),
    phone = coalesce(nullif(left(trim(coalesce(p_phone, '')), 30), ''), phone),
    agent_licence_no = case when p_role = 'agent' then nullif(left(trim(coalesce(p_licence, '')), 40), '') end,
    terms_accepted_at = now(),
    marketing_email_at = case when p_marketing then now() end,
    marketing_whatsapp_at = case when p_marketing then now() end
  where id = uid;
end $$;

-- выбор в анкете после входа через Google (если там выбрали «Looking for a home»)
create or replace function public.set_seeker(p_on boolean)
returns void language plpgsql security definer set search_path = public, extensions as $$
begin
  if auth.uid() is null then raise exception 'AUTH'; end if;
  update profiles set is_seeker = coalesce(p_on, false)
   where id = auth.uid() and role = 'owner'
     and not exists (select 1 from properties where owner_id = auth.uid() and not is_demo);
end $$;
revoke execute on function public.set_seeker(boolean) from public, anon;
grant execute on function public.set_seeker(boolean) to authenticated;

-- первое объявление → уже не «ищу жильё», а собственник (или агент)
create or replace function public.seeker_posted()
returns trigger language plpgsql security definer set search_path = public, extensions as $$
begin
  if new.owner_id is not null then
    update profiles set is_seeker = false where id = new.owner_id and is_seeker;
  end if;
  return new;
end $$;
drop trigger if exists seeker_posted on public.properties;
create trigger seeker_posted after insert on public.properties
  for each row execute function public.seeker_posted();

-- переход в агента — тоже снимает пометку
create or replace function public.seeker_role_change()
returns trigger language plpgsql as $$
begin
  if new.role is distinct from old.role and new.role <> 'owner' then new.is_seeker := false; end if;
  return new;
end $$;
drop trigger if exists seeker_role_change on public.profiles;
create trigger seeker_role_change before update of role on public.profiles
  for each row execute function public.seeker_role_change();

-- проверка
select
  exists (select 1 from information_schema.columns where table_name = 'profiles' and column_name = 'is_seeker') as seeker_ok,
  exists (select 1 from pg_trigger where tgname = 'seeker_posted') as trigger_ok;
