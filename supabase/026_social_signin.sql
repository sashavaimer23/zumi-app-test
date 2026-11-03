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
