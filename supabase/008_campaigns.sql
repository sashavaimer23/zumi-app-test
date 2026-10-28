-- =====================================================================
--  Zumi — 008: кампании продвижения объявлений (кабинет агента)
--  Агент выбирает своё объявление, место показа, картинку и даты.
--  В первый день кампания появляется сама, после последнего дня — исчезает
--  (никаких расписаний: показ просто проверяет сегодняшнюю дату).
--  Показы и клики считаются по дням — для отчёта рекламодателю.
--  Запускать после 007.
-- =====================================================================

create table if not exists public.campaigns (
  id           uuid primary key default gen_random_uuid(),
  owner_id     uuid not null references public.profiles(id) on delete cascade,
  property_id  uuid not null references public.properties(id) on delete cascade,
  advertiser   text not null check (length(trim(advertiser)) between 2 and 80),
  contact      text check (contact is null or length(contact) <= 200),   -- ссылка или телефон
  placement    text not null check (placement in ('search_top', 'home_featured')),
  image_url    text,                                                     -- своя картинка 3:2
  starts_on    date not null,
  ends_on      date not null,
  status       text not null default 'active' check (status in ('active', 'paused', 'stopped')),
  created_at   timestamptz not null default now(),
  check (ends_on >= starts_on)
);

create index if not exists campaigns_live_idx  on public.campaigns (placement, status, starts_on, ends_on);
create index if not exists campaigns_owner_idx on public.campaigns (owner_id, created_at desc);

-- статистика по дням
create table if not exists public.campaign_stats (
  campaign_id uuid not null references public.campaigns(id) on delete cascade,
  day         date not null,
  views       int  not null default 0,
  clicks      int  not null default 0,
  primary key (campaign_id, day)
);

alter table public.campaigns      enable row level security;
alter table public.campaign_stats enable row level security;

-- идущие сегодня кампании видны всем (чтобы показывать их в списках)
drop policy if exists "live campaigns readable" on public.campaigns;
create policy "live campaigns readable" on public.campaigns for select
  using (status = 'active' and current_date between starts_on and ends_on);
drop policy if exists "own campaigns" on public.campaigns;
create policy "own campaigns" on public.campaigns for all
  using (owner_id = auth.uid()) with check (owner_id = auth.uid());
drop policy if exists "admins read campaigns" on public.campaigns;
create policy "admins read campaigns" on public.campaigns for select using (public.is_admin());

drop policy if exists "own campaign stats" on public.campaign_stats;
create policy "own campaign stats" on public.campaign_stats for select
  using (exists (select 1 from campaigns c where c.id = campaign_id
                  and (c.owner_id = auth.uid() or public.is_admin())));

-- правила: только агенты (и команда), только своё активное объявление,
-- не больше 3 идущих кампаний одновременно, остановленную нельзя запустить снова
create or replace function public.check_campaign()
returns trigger language plpgsql security definer set search_path = public, extensions as $$
declare
  v_role text;
  v_live int;
begin
  select role into v_role from profiles where id = new.owner_id;
  if v_role not in ('agent', 'admin') then raise exception 'AGENTS_ONLY'; end if;
  if new.status = 'active' and not exists (select 1 from properties p where p.id = new.property_id
                   and p.owner_id = new.owner_id and p.status = 'active') then
    raise exception 'NOT_YOUR_LISTING';
  end if;
  if tg_op = 'UPDATE' and old.status = 'stopped' and new.status <> 'stopped' then
    raise exception 'CAMPAIGN_STOPPED';
  end if;
  if tg_op = 'INSERT' and new.starts_on < current_date then
    raise exception 'START_IN_PAST';
  end if;
  if new.status = 'active' then
    select count(*) into v_live from campaigns c
     where c.owner_id = new.owner_id and c.status = 'active' and c.ends_on >= current_date
       and c.id <> new.id;
    if v_live >= 3 then raise exception 'CAMPAIGN_LIMIT'; end if;
  end if;
  return new;
end $$;

drop trigger if exists check_campaign on public.campaigns;
create trigger check_campaign
  before insert or update on public.campaigns
  for each row execute function public.check_campaign();

-- показ или клик (вызывает приложение; считается только у идущей кампании)
create or replace function public.log_campaign_event(cid uuid, kind text)
returns void language plpgsql security definer set search_path = public, extensions as $$
begin
  if kind not in ('view', 'click') then return; end if;
  if not exists (select 1 from campaigns where id = cid and status = 'active'
                   and current_date between starts_on and ends_on) then
    return;
  end if;
  insert into campaign_stats (campaign_id, day, views, clicks)
  values (cid, current_date, (kind = 'view')::int, (kind = 'click')::int)
  on conflict (campaign_id, day) do update
     set views  = campaign_stats.views  + excluded.views,
         clicks = campaign_stats.clicks + excluded.clicks;
end $$;

grant execute on function public.log_campaign_event(uuid, text) to anon, authenticated;

-- публичная картинка кампании
insert into storage.buckets (id, name, public) values ('campaign-images', 'campaign-images', true)
  on conflict do nothing;
drop policy if exists "public read campaign images" on storage.objects;
create policy "public read campaign images" on storage.objects for select
  using (bucket_id = 'campaign-images');
drop policy if exists "users upload campaign images" on storage.objects;
create policy "users upload campaign images" on storage.objects for insert to authenticated
  with check (bucket_id = 'campaign-images' and (storage.foldername(name))[1] = auth.uid()::text);
drop policy if exists "users delete campaign images" on storage.objects;
create policy "users delete campaign images" on storage.objects for delete to authenticated
  using (bucket_id = 'campaign-images' and (storage.foldername(name))[1] = auth.uid()::text);
