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
