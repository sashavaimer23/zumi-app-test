-- =====================================================================
--  Zumi — 037: защита от «спящих» мошенников и от уже сданных объявлений
--  1. Новый аккаунт: ВСЕ объявления проверяет команда первые 14 дней
--     (раньше — только первые 2, дальше публиковалось сразу).
--     После 14 дней и 2 одобренных объявлений — публикуется сразу, как раньше.
--  2. Жалоба «Property is not available» от 2 разных людей → автор сразу получает
--     вопрос «Still available?» (в приложении и письмом). Не ответил — объявление
--     само уходит в паузу через несколько дней (агент 3 дня, собственник/комната 7).
--     Объявление НЕ скрывается сразу — чтобы конкуренты не могли «гасить» чужие объявления жалобами.
--  Запускать после 036. Можно запускать повторно.
-- =====================================================================

-- 1. проверка новых аккаунтов
create or replace function public.moderate_new_listing()
returns trigger language plpgsql security definer set search_path = public, extensions as $$
begin
  if new.is_demo or new.owner_id is null then
    new.approved_at := coalesce(new.approved_at, now());
    return new;
  end if;
  if (select count(*) from properties where owner_id = new.owner_id and approved_at is not null) >= 2
     and coalesce((select created_at from profiles where id = new.owner_id), now()) < now() - interval '14 days' then
    new.approved_at := now();
  else
    new.status := 'pending';
    new.approved_at := null;
  end if;
  new.moderation_note := null;
  return new;
end $$;

-- 2. жалобы
create or replace function public.on_listing_report()
returns trigger language plpgsql security definer set search_path = public, extensions as $$
declare
  p properties%rowtype;
  v_since timestamptz;
begin
  update properties set reports_count = reports_count + 1 where id = new.property_id;

  -- мошенничество: 3 жалобы от людей с подтверждённым телефоном → скрыть до проверки
  if (select count(*) from listing_reports r join profiles pr on pr.id = r.reporter_id
       where r.property_id = new.property_id and r.reason in ('scam', 'asked_prepayment')
         and pr.phone_verified_at is not null) >= 3 then
    update properties set status = 'archived', property_verified_at = null where id = new.property_id;
  end if;

  -- «уже сдан»: 2 разных человека после последнего подтверждения → спросить автора прямо сейчас
  if new.reason = 'not_available' then
    select * into p from properties where id = new.property_id;
    v_since := coalesce(p.confirmed_at, p.approved_at, p.created_at);
    if p.status = 'active'
       and (select count(distinct r.reporter_id) from listing_reports r
             where r.property_id = p.id and r.reason = 'not_available' and r.created_at > v_since) >= 2 then
      update properties
         set confirmed_at = least(v_since, now() - public._ask_interval(p.property_type, p.listed_by))
       where id = p.id;
    end if;
  end if;
  return new;
end $$;

-- проверка
select
  (select count(*) from pg_proc where proname = 'moderate_new_listing') = 1 as moderation_ok,
  (select prosrc like '%not_available%' from pg_proc where proname = 'on_listing_report') as reports_ok;
