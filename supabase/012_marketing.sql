-- =====================================================================
--  Zumi — 012: согласие на новости и предложения Zumi
--  Отдельная галочка при регистрации (по умолчанию выключена): новости по WhatsApp или почте.
--  Для каждого канала хранится дата согласия; пусто — согласия нет.
--  В Settings каналы включаются и выключаются по отдельности.
--  Запускать после 011. Можно запускать повторно.
-- =====================================================================
alter table public.profiles
  add column if not exists marketing_email_at    timestamptz,
  add column if not exists marketing_whatsapp_at timestamptz;

-- при регистрации: согласие только если галочка отмечена
create or replace function public.handle_new_user()
returns trigger language plpgsql security definer set search_path = public as $$
declare v_agent boolean := new.raw_user_meta_data->>'role' = 'agent';
begin
  insert into public.profiles (id, full_name, phone, role, terms_accepted_at, agent_licence_no,
                               marketing_email_at, marketing_whatsapp_at)
  values (
    new.id,
    new.raw_user_meta_data->>'full_name',
    new.raw_user_meta_data->>'phone',
    case when v_agent then 'agent' else 'owner' end,
    case when (new.raw_user_meta_data->>'terms_accepted') = 'true' then now() end,
    case when v_agent then nullif(left(trim(coalesce(new.raw_user_meta_data->>'licence_no', '')), 40), '') end,
    case when (new.raw_user_meta_data->>'marketing') = 'true' then now() end,
    case when (new.raw_user_meta_data->>'marketing') = 'true' then now() end
  );
  return new;
end $$;

-- включить / выключить в настройках
-- p_channel: 'email' | 'whatsapp'
create or replace function public.set_marketing(p_channel text, p_on boolean)
returns void language plpgsql security definer set search_path = public as $$
begin
  if auth.uid() is null then raise exception 'AUTH'; end if;
  if p_channel = 'email' then
    update profiles set marketing_email_at = case when p_on then now() end where id = auth.uid();
  elsif p_channel = 'whatsapp' then
    update profiles set marketing_whatsapp_at = case when p_on then now() end where id = auth.uid();
  else
    raise exception 'BAD_CHANNEL';
  end if;
end $$;
revoke execute on function public.set_marketing(text, boolean) from public, anon;
grant execute on function public.set_marketing(text, boolean) to authenticated;

-- своё согласие человек видит в настройках
create or replace function public.my_verification()
returns jsonb language sql stable security definer set search_path = public as $$
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
    'marketing_whatsapp', (select marketing_whatsapp_at is not null from profiles where id = auth.uid())
  );
$$;

-- список для рассылки (только команда): почта — тем, кто согласился на почту,
-- WhatsApp — тем, кто согласился на WhatsApp (только подтверждённый номер)
create or replace function public.admin_marketing_list()
returns table (user_id uuid, full_name text, role text, email text, whatsapp text,
               email_since timestamptz, whatsapp_since timestamptz)
language plpgsql stable security definer set search_path = public, auth as $$
begin
  if not public.is_admin() then raise exception 'NOT_ADMIN'; end if;
  return query
    select pr.id, pr.full_name, pr.role,
           case when pr.marketing_email_at is not null then u.email::text end,
           case when pr.marketing_whatsapp_at is not null and pr.phone_verified_at is not null then pr.phone end,
           pr.marketing_email_at, pr.marketing_whatsapp_at
      from profiles pr join auth.users u on u.id = pr.id
     where (pr.marketing_email_at is not null or pr.marketing_whatsapp_at is not null) and pr.banned_at is null
     order by greatest(pr.marketing_email_at, pr.marketing_whatsapp_at) desc;
end $$;
