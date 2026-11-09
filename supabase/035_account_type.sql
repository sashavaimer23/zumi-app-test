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
