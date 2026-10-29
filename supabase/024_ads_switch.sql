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
