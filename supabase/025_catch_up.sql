-- =====================================================================
--  Zumi — 025: догоняющий файл (021 + 022 + 023 + 024 одним запуском)
--  Проверка 30.10 показала, что на сервере не применены 021, 022 и 024.
--  Перед запуском: Database → Extensions → pg_cron → Enable.
--  Можно запускать повторно. В конце покажет таблицу «что включено».
-- =====================================================================

-- ===================== 021_help_update.sql =====================
-- =====================================================================
--  Zumi — 021: обновление старых статей помощи под новые правила
--  («Number checked», телефон для публикации, «ещё доступно?» через 30 дней,
--  лицензия ZIEA без продвижения). Меняются только статьи, которые команда не правила сама.
--  Запускать после 020. Можно запускать повторно.
-- =====================================================================
update public.help_articles set body = 'You sign in to Zumi with your email and password.

## Confirming your phone
You need a confirmed phone to publish a listing and to see phone numbers in listings. Your listings then show "Number checked". You do it only once:
- Open Profile → Get verified (or Settings → Phone & verification).
- Choose WhatsApp or SMS and enter your number with the country code, e.g. +260 97 123 4567.
- Type the 6-digit code you receive. It works for 10 minutes.

## Good to know
- One phone number can be confirmed on only one Zumi account.
- If you change your number in the profile, you need to confirm the new one.
- Forgot your password? On the sign-in screen tap "Forgot password?" — we send a code to your email. Type the whole code from the email (it can be 6–8 digits).'
 where id = 'e2bf5b54-9919-58d0-9461-2de87c71309d' and updated_by is null;
update public.help_articles set body = 'Estate agents in Zambia are registered with the Zambia Institute of Estate Agents (ZIEA). Zumi checks your registration number with the register — you don''t upload any documents.

- Add the number when you sign up as an agent (it is optional), or later in Profile → Get verified.
- Until it is checked, your listings and agent page show "ZIEA licence not verified".
- After the check your listings show the "Licensed agent" badge — people trust them more.

If your number was not approved, the reason is shown in Get verified. Check the number and send it again.'
 where id = 'a44d1cea-2bb5-5fdc-81f2-6aea36e74198' and updated_by is null;
update public.help_articles set body = 'Tap "Post" on the home screen (or "Post a listing" on the website) and follow the steps:
- Choose rent or sale and the type of property.
- Add a clear title, the price and the main details (bedrooms, bathrooms, size).
- Add good photos: daylight, every room, the outside and the street. 5 or more photos give people a clear picture.
- Put the pin on the map where the property is (required). The address and "what''s nearby" are optional.
- Check the preview and publish. The first time, Zumi asks you to confirm your phone with a code.

## Tips
- Write the real price, so people know right away if the home fits their budget.
- Do not put phone numbers or links inside photos or the description — use the contact settings instead.
- Every 30 days Zumi asks "Is it still available?" — answer in one tap. Without an answer for 7 days the listing is hidden from search (not deleted).'
 where id = 'e2232f2d-41f2-569a-a8f0-f3ebc63e88b5' and updated_by is null;

-- ===================== 022_retention.sql =====================
-- =====================================================================
--  Zumi — 022: автоматическое удаление старых данных (как обещано в Privacy Policy)
--  • записи «кто открыл номер» — старше 1 года;
--  • отзывы о приложении — старше 1 года;
--  • аккаунты, заблокированные за мошенничество, — через 2 года после блокировки
--    (если команда не отметила, что данные нужны полиции/суду: legal_hold);
--  • плюс ежедневная уборка из 014 (метки статистики, коды, старые заявки).
--  Запускается каждый день в 03:15 по расписанию (pg_cron). Перед запуском файла
--  включите pg_cron: Database → Extensions → pg_cron → Enable.
--  Запускать после 021. Можно запускать повторно.
-- =====================================================================

-- команда может «заморозить» удаление, пока идёт расследование
alter table public.profiles add column if not exists legal_hold boolean not null default false;

create or replace function public.cleanup_retention()
returns jsonb language plpgsql security definer set search_path = public, extensions as $$
declare v_reveals int; v_feedback int; v_banned int;
begin
  if not public._is_admin_or_service() and current_user not in ('postgres', 'supabase_admin') then
    raise exception 'NOT_ADMIN';
  end if;
  delete from phone_reveals where created_at < now() - interval '1 year';
  get diagnostics v_reveals = row_count;
  delete from app_feedback where created_at < now() - interval '1 year';
  get diagnostics v_feedback = row_count;
  -- заблокированные 2+ года назад: удаляем аккаунт целиком (профиль, объявления, фото-записи, чаты — каскадом)
  with gone as (
    delete from auth.users u
     using profiles p
     where p.id = u.id and p.banned_at is not null and p.banned_at < now() - interval '2 years' and not p.legal_hold
    returning u.id
  ) select count(*) into v_banned from gone;
  return jsonb_build_object('phone_reveals', v_reveals, 'app_feedback', v_feedback, 'banned_accounts', v_banned);
end $$;
revoke execute on function public.cleanup_retention() from public, anon, authenticated;

-- расписание: каждый день 03:15 — обычная уборка и сроки хранения
do $$
begin
  if exists (select 1 from pg_extension where extname = 'pg_cron') then
    perform cron.unschedule(jobid) from cron.job where jobname in ('zumi-cleanup-daily', 'zumi-retention');
    perform cron.schedule('zumi-cleanup-daily', '15 3 * * *', 'select public.cleanup_daily()');
    perform cron.schedule('zumi-retention', '20 3 * * *', 'select public.cleanup_retention()');
    raise notice 'Scheduled: zumi-cleanup-daily and zumi-retention';
  else
    raise notice 'pg_cron is not enabled: enable it in Database → Extensions, then run this file again';
  end if;
end $$;

-- ===================== 023_agent_limits.sql =====================
-- =====================================================================
--  Zumi — 023: лимит объявлений для агентов
--  Агент с проверенной лицензией ZIEA — 10 бесплатных объявлений, без проверки — 5.
--  Собственники — 2 (без изменений). Купленные места (extra_listing_slots) добавляются сверху.
--  Если лицензию сняли — уже опубликованные объявления остаются, новые сверх 5 не добавить.
--  Запускать после 022. Можно запускать повторно.
-- =====================================================================
alter table public.role_limits add column if not exists free_listings_licensed int;
update public.role_limits set free_listings = 5, free_listings_licensed = 10 where role = 'agent';
update public.role_limits set free_listings = 2, free_listings_licensed = null where role = 'owner';

create or replace function public.listing_quota(uid uuid)
returns table (used int, allowed int) language sql stable security definer
set search_path = public, extensions as $$
  select
    (select count(*)::int from properties
      where owner_id = uid and status in ('active', 'draft', 'pending') and not is_demo),
    (select coalesce(
              case when p.role = 'agent' and p.licence_verified_at is not null
                   then coalesce(rl.free_listings_licensed, rl.free_listings)
                   else rl.free_listings end,
              999999) + p.extra_listing_slots
       from profiles p left join role_limits rl on rl.role = p.role
      where p.id = uid);
$$;

-- статья помощи про лицензию: + про лимит (если команда её не меняла)
update public.help_articles set body = body || '

## More listings with a licence
Agents can publish 5 listings for free. With a checked ZIEA licence — 10.'
 where id = 'a44d1cea-2bb5-5fdc-81f2-6aea36e74198' and updated_by is null
   and body not like '%More listings with a licence%';

-- ===================== 024_ads_switch.sql =====================
-- =====================================================================
--  Zumi — 024: выключатель рекламных баннеров (по умолчанию выключено)
--  Пока Zumi полностью бесплатный, в приложении нет ни баннеров, ни шаблона «Your ad here».
--  Владелец включает их в кабинете → Ads. Баннеры можно готовить заранее — они ждут.
--  Запускать после 023. Можно запускать повторно.
-- =====================================================================
insert into public.app_settings values ('ads_enabled', 'false') on conflict do nothing;

create or replace function public.ads_on()
returns boolean language sql stable security definer set search_path = public, extensions as $$
  select coalesce((select value from app_settings where key = 'ads_enabled'), 'false') = 'true';
$$;

create or replace function public.app_flags()
returns jsonb language sql stable security definer set search_path = public, extensions as $$
  select jsonb_build_object('promotion', public.promotion_on(), 'ads', public.ads_on());
$$;
grant execute on function public.app_flags() to anon, authenticated;

-- пока выключено — баннеры никому, кроме команды, не отдаются
drop policy if exists "ads switch" on public.ads;
create policy "ads switch" on public.ads as restrictive for select
  using (public.ads_on() or public.is_admin());

-- менять могут: тестовый режим кодов и правило лицензий — команда; продвижение и баннеры — только владелец
create or replace function public.admin_set_setting(p_key text, p_value text)
returns void language plpgsql security definer set search_path = public, extensions as $$
begin
  if not public.is_admin() then raise exception 'NOT_ADMIN'; end if;
  if p_key not in ('otp_test_mode', 'require_licence_to_publish', 'promotion_enabled', 'ads_enabled') then
    raise exception 'BAD_SETTING';
  end if;
  if p_key in ('promotion_enabled', 'ads_enabled') and not public.is_owner() then raise exception 'OWNER_ONLY'; end if;
  if p_value not in ('true', 'false') then raise exception 'BAD_SETTING'; end if;
  insert into app_settings (key, value) values (p_key, p_value)
  on conflict (key) do update set value = excluded.value;
  perform public._audit('setting', 'settings', p_key, p_value);
end $$;

create or replace function public.admin_promotion_status()
returns jsonb language plpgsql stable security definer set search_path = public, extensions as $$
begin
  if not public.is_admin() then raise exception 'NOT_ADMIN'; end if;
  return jsonb_build_object(
    'enabled', public.promotion_on(),
    'live_campaigns', (select count(*) from campaigns where status = 'active' and ends_on >= current_date),
    'ads_enabled', public.ads_on(),
    'live_ads', (select count(*) from ads where status = 'active' and current_date between starts_on and ends_on));
end $$;
grant execute on function public.admin_promotion_status() to authenticated;

-- ===================== проверка =====================
select
  (select count(*) from pg_proc where proname = 'cleanup_retention') = 1          as "022 retention",
  (select count(*) from pg_extension where extname = 'pg_cron') = 1               as "pg_cron on",
  (select count(*) from information_schema.columns
     where table_name = 'role_limits' and column_name = 'free_listings_licensed') = 1 as "023 limits",
  (select public.app_flags() ? 'ads')                                             as "024 ads switch",
  (select body like '%don''t upload any documents%' from public.help_articles
     where id = 'a44d1cea-2bb5-5fdc-81f2-6aea36e74198')                           as "021 help";
