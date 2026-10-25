-- =====================================================================
--  Zumi — 015: помощь продавцу
--  1. Честный счётчик просмотров: один человек — один просмотр объявления в день,
--     свои просмотры автора не считаются. Просмотры по дням.
--  2. Средняя цена по району (для подсказки в мастере) — только если похожих
--     объявлений не меньше 5, чтобы нельзя было вычислить чужое.
--  3. Советы после публикации: правила на сервере по статистике объявления.
--  Запускать после 014. Можно запускать повторно.
-- =====================================================================

-- =====================================================================
-- 1. ПРОСМОТРЫ ПО ДНЯМ
-- =====================================================================
create table if not exists public.listing_views_daily (
  property_id uuid not null references public.properties(id) on delete cascade,
  day         date not null,
  views       int  not null default 0,   -- разные люди за день
  primary key (property_id, day)
);
alter table public.listing_views_daily enable row level security;
drop policy if exists "owner reads own views" on public.listing_views_daily;
create policy "owner reads own views" on public.listing_views_daily for select
  using (exists (select 1 from properties p where p.id = property_id
                  and (p.owner_id = auth.uid() or public.is_admin())));

-- просмотр объявления: один раз в день с человека (вошедший — по аккаунту, гость — по метке устройства)
create or replace function public.log_listing_view(pid uuid, device text default null)
returns void language plpgsql security definer set search_path = public as $$
declare v_owner uuid;
begin
  select owner_id into v_owner from properties where id = pid and status = 'active';
  if not found then return; end if;
  if v_owner is not null and v_owner = auth.uid() then return; end if;   -- автор смотрит своё — не считаем
  if not public._first_event(pid, 'lv', device) then return; end if;
  insert into listing_views_daily (property_id, day, views)
  values (pid, (now() at time zone 'Africa/Lusaka')::date, 1)
  on conflict (property_id, day) do update set views = listing_views_daily.views + 1;
  update properties set views_count = views_count + 1 where id = pid;
end $$;
grant execute on function public.log_listing_view(uuid, text) to anon, authenticated;

-- старый вызов (без метки устройства) — тоже через честный счётчик
create or replace function public.increment_views(pid uuid)
returns void language sql security definer set search_path = public as $$
  select public.log_listing_view(pid, null);
$$;

-- =====================================================================
-- 2. ЦЕНЫ ПОХОЖИХ ОБЪЯВЛЕНИЙ В РАЙОНЕ
-- =====================================================================
create or replace function public.area_price_stats(p_area int, p_deal text, p_type text, p_beds int default null,
                                                   p_period text default null, p_currency text default 'ZMW',
                                                   p_exclude uuid default null)
returns jsonb language sql stable security definer set search_path = public as $$
  with s as (
    select p.price from properties p
     where p.status = 'active' and p.area_id = p_area and p.deal_type::text = p_deal
       and p.property_type::text = p_type and p.currency = p_currency
       and (p_deal <> 'rent' or coalesce(p.rent_period, 'month') = coalesce(p_period, 'month'))
       and (p_beds is null or p.bedrooms between p_beds - 1 and p_beds + 1)
       and (p_exclude is null or p.id <> p_exclude)
       and p.price > 0
  )
  select case when count(*) < 5 then jsonb_build_object('n', count(*))
              else jsonb_build_object(
                'n', count(*),
                'p25', percentile_cont(0.25) within group (order by price),
                'median', percentile_cont(0.5) within group (order by price),
                'p75', percentile_cont(0.75) within group (order by price)) end
    from s;
$$;
grant execute on function public.area_price_stats(int, text, text, int, text, text, uuid) to anon, authenticated;

-- =====================================================================
-- 3. СОВЕТЫ ПОСЛЕ ПУБЛИКАЦИИ
--    Возвращает по каждому своему объявлению: просмотры, контакты и сохранения
--    за 7 дней, просмотры и контакты по дням (14 дней) и до 3 советов (коды —
--    текст пишет приложение).
-- =====================================================================
create or replace function public.listing_advice(pid uuid)
returns jsonb language plpgsql stable security definer set search_path = public as $$
declare
  p record;
  v_live_days int;
  v_views7 int;
  v_contacts7 int;
  v_saves7 int;
  v_photos int;
  v_stats jsonb;
  v_tips jsonb := '[]'::jsonb;
begin
  select * into p from properties where id = pid;
  if not found or (p.owner_id is distinct from auth.uid() and not public.is_admin()) then
    raise exception 'NOT_FOUND';
  end if;

  v_live_days := greatest(0, (now()::date - coalesce(p.approved_at, p.created_at)::date));
  v_views7 := coalesce((select sum(views) from listing_views_daily
                         where property_id = pid and day > current_date - 7), 0);
  v_contacts7 := (select count(*) from phone_reveals where property_id = pid and created_at > now() - interval '7 days')
               + (select count(*) from conversations where property_id = pid and created_at > now() - interval '7 days');
  v_saves7 := (select count(*) from favorites where property_id = pid and created_at > now() - interval '7 days');
  v_photos := (select count(*) from property_images where property_id = pid);
  v_stats := public.area_price_stats(p.area_id, p.deal_type::text, p.property_type::text, p.bedrooms,
                                     p.rent_period, p.currency, pid);

  if p.status = 'active' then
    -- по порядку важности
    if coalesce(p.confirmed_at, p.created_at) < now() - interval '50 days' then
      v_tips := v_tips || jsonb_build_object('code', 'confirm',
                  'days_left', greatest(0, 60 - (now()::date - coalesce(p.confirmed_at, p.created_at)::date)));
    end if;
    if v_live_days >= 7 and v_views7 >= 30 and v_contacts7 = 0 then
      v_tips := v_tips || jsonb_build_object('code', 'no_contacts', 'views', v_views7);
    end if;
    if v_saves7 >= 5 and v_contacts7 = 0 then
      v_tips := v_tips || jsonb_build_object('code', 'saved_no_contact', 'saves', v_saves7);
    end if;
    if (v_stats ? 'p75') and p.price > (v_stats->>'p75')::numeric * 1.3 then
      v_tips := v_tips || jsonb_build_object('code', 'price_high', 'p25', round((v_stats->>'p25')::numeric),
                  'p75', round((v_stats->>'p75')::numeric), 'n', v_stats->'n');
    end if;
    if (v_stats ? 'p25') and p.price < (v_stats->>'p25')::numeric * 0.5 then
      v_tips := v_tips || jsonb_build_object('code', 'price_low', 'p25', round((v_stats->>'p25')::numeric),
                  'p75', round((v_stats->>'p75')::numeric), 'n', v_stats->'n');
    end if;
    if v_photos < 5 then
      v_tips := v_tips || jsonb_build_object('code', 'photos', 'photos', v_photos);
    end if;
    if length(coalesce(p.description, '')) < 150 then
      v_tips := v_tips || jsonb_build_object('code', 'description');
    end if;
    if v_live_days >= 7 and v_views7 < 10 then
      v_tips := v_tips || jsonb_build_object('code', 'few_views', 'views', v_views7);
    end if;
    if p.property_verified_at is null and v_live_days >= 3 then
      v_tips := v_tips || jsonb_build_object('code', 'verify_onsite');
    end if;
    if jsonb_array_length(v_tips) = 0 and v_contacts7 >= 3 then
      v_tips := jsonb_build_array(jsonb_build_object('code', 'doing_well', 'contacts', v_contacts7));
    end if;
  end if;

  return jsonb_build_object(
    'id', pid,
    'views7', v_views7,
    'contacts7', v_contacts7,
    'saves7', v_saves7,
    'days', coalesce((select jsonb_agg(jsonb_build_object(
                'day', d::date,
                'views', coalesce((select views from listing_views_daily where property_id = pid and day = d::date), 0),
                'contacts', (select count(*) from phone_reveals r where r.property_id = pid
                               and (r.created_at at time zone 'Africa/Lusaka')::date = d::date)
                          + (select count(*) from conversations c where c.property_id = pid
                               and (c.created_at at time zone 'Africa/Lusaka')::date = d::date)
              ) order by d)
              from generate_series(current_date - 13, current_date, interval '1 day') d), '[]'::jsonb),
    'tips', (select coalesce(jsonb_agg(t), '[]'::jsonb) from (
               select t from jsonb_array_elements(v_tips) t limit 3) x)
  );
end $$;
grant execute on function public.listing_advice(uuid) to authenticated;

-- все свои объявления разом (для «Мои объявления»)
create or replace function public.my_listing_advice()
returns jsonb language sql stable security definer set search_path = public as $$
  select coalesce(jsonb_agg(public.listing_advice(p.id)), '[]'::jsonb)
    from properties p
   where p.owner_id = auth.uid() and p.status in ('active', 'pending') and not p.is_demo;
$$;
grant execute on function public.my_listing_advice() to authenticated;

-- =====================================================================
-- 4. СТАТЬЯ ПОМОЩИ ПРО СТАТИСТИКУ ОБЪЯВЛЕНИЯ
-- =====================================================================
insert into public.help_articles (id, category, title, body, sort, web_only) values
  ('427fc45e-d221-50fd-b46e-089950b6edd5', 'listings', 'Views, contacts and tips for my listing',
   'In Profile → My listings, under each active listing you see the numbers for the last 7 days:
- Views — each person is counted once a day. Your own views are not counted.
- Contacts — people who opened your phone number or started a chat.
- Saved — people who tapped the heart.

Tap "Details" to see views and contacts by day for the last 14 days, and tips for this listing.

## Where the tips come from
Zumi looks at your listing''s numbers and at similar listings in the same area. For example:
- many views but no contacts — check the price and add details people ask about;
- the price is far from similar homes in the area;
- fewer than 5 photos or a very short description;
- the listing needs a "still available" confirmation soon.

Tips are suggestions — you decide what to change.',
   40, false)
on conflict (id) do nothing;
