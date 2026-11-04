-- =====================================================================
--  Zumi — 027: подтверждение номера через WhatsApp (человек пишет нам сам)
--  1. В приложении: «Confirm with WhatsApp» → сервер выдаёт одноразовый код (15 минут).
--  2. Открывается WhatsApp с готовым сообщением «Zumi code 123456» на номер Zumi.
--  3. Сообщение приходит в функцию whatsapp-webhook → confirm_whatsapp_code():
--     номер, С КОТОРОГО написали, становится подтверждённым номером аккаунта.
--  Входящие сообщения WhatsApp бесплатны — платить за коды не нужно.
--  Номер Zumi для подтверждения: настройка whatsapp_verify_number (пусто — выключено).
--  Запускать после 026. Можно запускать повторно.
-- =====================================================================

create table if not exists public.wa_verify_codes (
  code       text primary key,
  user_id    uuid not null references public.profiles(id) on delete cascade,
  created_at timestamptz not null default now(),
  expires_at timestamptz not null,
  used_at    timestamptz
);
alter table public.wa_verify_codes enable row level security;  -- без политик: только через функции
create index if not exists wa_verify_codes_user_idx on public.wa_verify_codes (user_id, created_at);

-- номер Zumi, на который люди пишут (цифры с кодом страны, например 15551637510)
insert into public.app_settings (key, value) values ('whatsapp_verify_number', '')
on conflict (key) do nothing;

create or replace function public._wa_verify_number()
returns text language sql stable security definer set search_path = public, extensions as $$
  select nullif(regexp_replace(coalesce((select value from app_settings where key = 'whatsapp_verify_number'), ''),
                               '[^0-9]', '', 'g'), '');
$$;

-- что включено: + номер WhatsApp для подтверждения (публичный бизнес-номер)
create or replace function public.app_flags()
returns jsonb language sql stable security definer set search_path = public, extensions as $$
  select jsonb_build_object('promotion', public.promotion_on(), 'ads', public.ads_on(),
                            'wa_verify', public._wa_verify_number());
$$;
grant execute on function public.app_flags() to anon, authenticated;

-- шаг 1: выдать код (старые неиспользованные коды человека сгорают)
create or replace function public.start_whatsapp_verification()
returns jsonb language plpgsql security definer set search_path = public, extensions as $$
declare
  uid uuid := auth.uid();
  v_num text := public._wa_verify_number();
  v_code text;
begin
  if uid is null then raise exception 'AUTH'; end if;
  if v_num is null then raise exception 'FEATURE_OFF'; end if;
  if exists (select 1 from profiles where id = uid and banned_at is not null) then raise exception 'ACCOUNT_BLOCKED'; end if;
  if (select count(*) from wa_verify_codes where user_id = uid and created_at > now() - interval '1 hour') >= 10 then
    raise exception 'TOO_MANY_CODES';
  end if;
  delete from wa_verify_codes where (user_id = uid and used_at is null) or expires_at < now() - interval '1 day';
  loop
    v_code := lpad((floor(random() * 1000000))::int::text, 6, '0');
    exit when not exists (select 1 from wa_verify_codes where code = v_code);
  end loop;
  insert into wa_verify_codes (code, user_id, expires_at) values (v_code, uid, now() + interval '15 minutes');
  return jsonb_build_object('code', v_code, 'number', v_num);
end $$;
revoke execute on function public.start_whatsapp_verification() from public, anon;
grant execute on function public.start_whatsapp_verification() to authenticated;

-- шаг 2: пришло сообщение в WhatsApp (вызывает только функция whatsapp-webhook с ключом сервиса)
create or replace function public.confirm_whatsapp_code(p_text text, p_from text)
returns text language plpgsql security definer set search_path = public, extensions as $$
declare
  v_code text := substring(coalesce(p_text, '') from '(\d{6})');
  v_phone text := '+' || regexp_replace(coalesce(p_from, ''), '[^0-9]', '', 'g');
  c record;
begin
  if v_code is null or length(v_phone) < 10 then return 'unknown'; end if;
  select * into c from wa_verify_codes where code = v_code;
  if c is null or c.used_at is not null or c.expires_at < now() then return 'expired'; end if;
  if public._phone_taken(v_phone, c.user_id) then return 'taken'; end if;
  update wa_verify_codes set used_at = now() where code = v_code;
  update profiles set phone = v_phone, phone_verified_at = now(), phone_verify_channel = 'whatsapp'
   where id = c.user_id;
  return 'ok';
end $$;
revoke execute on function public.confirm_whatsapp_code(text, text) from public, anon, authenticated;
grant execute on function public.confirm_whatsapp_code(text, text) to service_role;
