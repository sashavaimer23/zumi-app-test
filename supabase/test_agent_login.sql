-- =====================================================================
--  Zumi — вход под тестовым агентом Mwila Banda
--  Почта агента меняется на zumi.team.zm+agent@gmail.com — письма придут
--  в обычный ящик Gmail Zumi (Gmail понимает «+agent»).
--  После запуска: zumihome.com → Sign in → «Forgot password?» →
--  zumi.team.zm+agent@gmail.com → письмо в Gmail Zumi → придумать пароль.
--  Пароль придумываешь сама, никому его не отправляешь.
-- =====================================================================

update auth.users set
  email = 'zumi.team.zm+agent@gmail.com',
  email_confirmed_at = coalesce(email_confirmed_at, now()),
  -- Supabase не любит пустые (NULL) служебные поля у созданных вручную аккаунтов
  confirmation_token = coalesce(confirmation_token, ''),
  recovery_token = coalesce(recovery_token, ''),
  email_change = coalesce(email_change, ''),
  email_change_token_new = coalesce(email_change_token_new, ''),
  email_change_token_current = coalesce(email_change_token_current, ''),
  reauthentication_token = coalesce(reauthentication_token, ''),
  phone_change = coalesce(phone_change, ''),
  phone_change_token = coalesce(phone_change_token, ''),
  updated_at = now()
where id = '7e570000-0000-4000-8000-000000000001';

-- способ входа «почта + пароль»
delete from auth.identities where user_id = '7e570000-0000-4000-8000-000000000001';
insert into auth.identities (provider_id, user_id, identity_data, provider, last_sign_in_at, created_at, updated_at)
values ('7e570000-0000-4000-8000-000000000001', '7e570000-0000-4000-8000-000000000001',
        jsonb_build_object('sub', '7e570000-0000-4000-8000-000000000001', 'email', 'zumi.team.zm+agent@gmail.com',
                           'email_verified', true),
        'email', now(), now(), now());

-- проверка
select email, email_confirmed_at is not null as confirmed,
       (select count(*) from auth.identities where user_id = u.id) as identities
  from auth.users u where id = '7e570000-0000-4000-8000-000000000001';
