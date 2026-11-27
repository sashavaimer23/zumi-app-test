-- =====================================================================
--  Zumi — 042: защита от мошенников (trust & safety)
--  Главное правило: повтор объявления САМ ПО СЕБЕ не нарушение. Агенты одного агентства
--  и разные лицензированные агенты часто выкладывают один и тот же дом — это нормально.
--  Повтор подозрителен только вместе с другими тревожными признаками.
--
--  • Сигналы риска (бесплатно, в базе): одинаковые фото (хеш считает функция photo-hash на сервере),
--    похожий текст (pg_trgm), цена на 40%+ ниже медианы, слова про предоплату и ссылки в чате,
--    всплеск активности нового аккаунта, жалобы. Веса и пороги — app_settings 'risk_config',
--    стоп-слова — app_settings 'chat_stop_words' (меняются из админки → Risk).
--  • Повторы: одно агентство или проверенные аккаунты с похожей ценой → группа, 0 баллов.
--    В поиске одна карточка на группу, в объявлении — «Also offered by».
--  • Автопубликация: телефон подтверждён И (лицензированный агент ИЛИ аккаунт старше 30 дней
--    без подтверждённых жалоб). Остальное — на проверку команде (как раньше для новых).
--  • Автоматически только обратимое: риск 40+ → на модерацию (номер скрыт) + письмо команде;
--    риск 70+ → ещё предупреждение в чатах по объявлению. Бан и удаление — только вручную.
--  • Всё пишется в журнал (_audit).
--  Запускать после 041. Можно запускать повторно.
-- =====================================================================

create extension if not exists pg_trgm with schema extensions;

-- ---------- настройки ----------
insert into public.app_settings (key, value) values
  ('risk_config', '{"w_photo_dup":35,"w_text_dup":20,"w_low_price":30,"w_chat_payment":25,"w_chat_link":10,'
                  '"w_new_burst":20,"w_report":15,"w_report_scam":30,"review_at":40,"warn_at":70,'
                  '"photo_distance":6,"text_similarity":0.6,"price_drop":0.4,"min_comparables":5,'
                  '"group_price_diff":0.15,"new_days":7,"burst_listings":3,"burst_chats":20,"trusted_days":30}'),
  ('chat_stop_words', 'deposit first, pay first, pay before, pay upfront, viewing fee, booking fee, reservation fee, '
                      'advance payment, send money, send the money, airtel money, mtn money, momo, mobile money, '
                      'zamtel kwacha, western union, moneygram, transfer the money, pay to secure, before viewing')
on conflict (key) do nothing;

create or replace function public._risk_cfg()
returns jsonb language sql stable security definer set search_path = public, extensions as $$
  select '{"w_photo_dup":35,"w_text_dup":20,"w_low_price":30,"w_chat_payment":25,"w_chat_link":10,
           "w_new_burst":20,"w_report":15,"w_report_scam":30,"review_at":40,"warn_at":70,"photo_distance":6,
           "text_similarity":0.6,"price_drop":0.4,"min_comparables":5,"group_price_diff":0.15,"new_days":7,
           "burst_listings":3,"burst_chats":20,"trusted_days":30}'::jsonb
         || coalesce((select value::jsonb from app_settings where key = 'risk_config'), '{}'::jsonb);
$$;
create or replace function public._rc(k text)
returns numeric language sql stable security definer set search_path = public, extensions as $$
  select (public._risk_cfg()->>k)::numeric;
$$;

-- ---------- данные ----------
alter table public.property_images
  add column if not exists phash bit(64),          -- «отпечаток» фото (dHash), считает функция photo-hash
  add column if not exists sha256 text,
  add column if not exists hashed_at timestamptz,
  add column if not exists hash_error text;
create index if not exists property_images_unhashed_idx on public.property_images (id) where hashed_at is null;

alter table public.properties
  add column if not exists dup_group uuid,          -- группа одинаковых объявлений (один дом)
  add column if not exists dup_lead boolean;        -- карточка группы, которую показываем в поиске
create index if not exists properties_dup_group_idx on public.properties (dup_group) where dup_group is not null;
create index if not exists properties_text_trgm_idx on public.properties
  using gin ((coalesce(title, '') || ' ' || coalesce(description, '')) extensions.gin_trgm_ops);

alter table public.conversations add column if not exists risk_warned_at timestamptz;

create table if not exists public.listing_risk (
  property_id   uuid primary key references public.properties(id) on delete cascade,
  score         int not null default 0,
  reasons       jsonb not null default '[]',      -- [{code, points, text}]
  updated_at    timestamptz not null default now(),
  cleared_score int,                              -- команда отметила «всё в порядке» при этом риске
  cleared_by    uuid references public.profiles(id) on delete set null,
  cleared_at    timestamptz
);
create index if not exists listing_risk_score_idx on public.listing_risk (score desc);
alter table public.listing_risk enable row level security;
drop policy if exists "team reads listing risk" on public.listing_risk;
create policy "team reads listing risk" on public.listing_risk for select using (public.is_admin());

create table if not exists public.account_risk (
  user_id     uuid primary key references public.profiles(id) on delete cascade,
  score       int not null default 0,
  reasons     jsonb not null default '[]',
  updated_at  timestamptz not null default now()
);
alter table public.account_risk enable row level security;
drop policy if exists "team reads account risk" on public.account_risk;
create policy "team reads account risk" on public.account_risk for select using (public.is_admin());

create table if not exists public.chat_flags (
  id              bigserial primary key,
  message_id      uuid references public.messages(id) on delete cascade,
  conversation_id uuid references public.conversations(id) on delete cascade,
  property_id     uuid references public.properties(id) on delete cascade,
  sender_id       uuid references public.profiles(id) on delete cascade,
  kind            text not null check (kind in ('payment', 'link')),
  words           text,
  created_at      timestamptz not null default now()
);
create index if not exists chat_flags_prop_idx on public.chat_flags (property_id, sender_id);
create index if not exists chat_flags_sender_idx on public.chat_flags (sender_id, created_at);
alter table public.chat_flags enable row level security;
drop policy if exists "team reads chat flags" on public.chat_flags;
create policy "team reads chat flags" on public.chat_flags for select using (public.is_admin());

-- письма команде о подозрительных объявлениях
create table if not exists public.risk_alerts (
  id           bigserial primary key,
  property_id  uuid references public.properties(id) on delete cascade,
  score        int not null,
  action       text not null,                      -- review | warn
  created_at   timestamptz not null default now()
);
alter table public.risk_alerts enable row level security;
drop policy if exists "team reads risk alerts" on public.risk_alerts;
create policy "team reads risk alerts" on public.risk_alerts for select using (public.is_admin());

-- журнал от имени системы (без входа) — тот же admin_audit, admin_id = null
create or replace function public._audit_sys(p_action text, p_type text, p_target text, p_note text)
returns void language sql security definer set search_path = public, extensions as $$
  insert into admin_audit (admin_id, action, target_type, target_id, note)
  values (auth.uid(), p_action, p_type, p_target, left(p_note, 500));
$$;
revoke execute on function public._audit_sys(text, text, text, text) from public, anon, authenticated;

-- ---------- кому доверяем ----------
-- проверенный: номер подтверждён и (лицензированный агент ИЛИ аккаунт старше N дней без подтверждённых жалоб)
create or replace function public._trusted(uid uuid)
returns boolean language sql stable security definer set search_path = public, extensions as $$
  select coalesce((
    select pr.banned_at is null and pr.phone_verified_at is not null
       and ((pr.role = 'agent' and pr.licence_verified_at is not null)
            or (pr.created_at < now() - make_interval(days => public._rc('trusted_days')::int)
                and not exists (select 1 from listing_reports r join properties x on x.id = r.property_id
                                 where x.owner_id = pr.id and r.status = 'action_taken')))
      from profiles pr where pr.id = uid), false);
$$;

-- ---------- 3. автопубликация ----------
create or replace function public.moderate_new_listing()
returns trigger language plpgsql security definer set search_path = public, extensions as $$
begin
  if new.is_demo or new.owner_id is null then
    new.approved_at := coalesce(new.approved_at, now());
    return new;
  end if;
  -- сразу в поиск — только проверенным (риск объявления пересчитается после вставки и фото)
  if public._trusted(new.owner_id) then
    new.approved_at := now();
  else
    new.status := 'pending';
    new.approved_at := null;
  end if;
  new.moderation_note := null;
  return new;
end $$;

-- ---------- группы повторов ----------
create or replace function public._regroup(g uuid)
returns void language plpgsql security definer set search_path = public, extensions as $$
declare v_lead uuid;
begin
  if g is null then return; end if;
  select p.id into v_lead from properties p
   where p.dup_group = g and p.status = 'active'
   order by public._trusted(p.owner_id) desc,
            exists (select 1 from profiles o where o.id = p.owner_id and o.licence_verified_at is not null) desc,
            coalesce(p.confirmed_at, p.approved_at, p.created_at) desc
   limit 1;
  update properties set dup_lead = (id = v_lead) where dup_group = g and dup_lead is distinct from (id = v_lead);
end $$;

-- ---------- пересчёт риска аккаунта ----------
create or replace function public.account_risk_recalc(uid uuid)
returns int language plpgsql security definer set search_path = public, extensions as $$
declare
  pr profiles%rowtype;
  r jsonb := '[]';
  s int := 0;
  n int;
begin
  select * into pr from profiles where id = uid;
  if not found then return 0; end if;
  if pr.created_at > now() - make_interval(days => public._rc('new_days')::int) then
    select count(*) into n from properties where owner_id = uid and not is_demo and created_at > now() - interval '24 hours';
    if n > public._rc('burst_listings') then
      s := s + public._rc('w_new_burst')::int;
      r := r || jsonb_build_object('code', 'burst_listings', 'points', public._rc('w_new_burst'),
             'text', format('New account posted %s listings in 24 hours', n));
    end if;
    select count(distinct case when c.buyer_id = uid then c.seller_id else c.buyer_id end) into n
      from messages m join conversations c on c.id = m.conversation_id
     where m.sender_id = uid and m.created_at > now() - interval '24 hours';
    if n > public._rc('burst_chats') then
      s := s + public._rc('w_new_burst')::int;
      r := r || jsonb_build_object('code', 'burst_chats', 'points', public._rc('w_new_burst'),
             'text', format('New account messaged %s people in 24 hours', n));
    end if;
  end if;
  if exists (select 1 from chat_flags where sender_id = uid and kind = 'payment' and created_at > now() - interval '30 days') then
    s := s + public._rc('w_chat_payment')::int;
    r := r || jsonb_build_object('code', 'chat_payment', 'points', public._rc('w_chat_payment'),
           'text', 'Asked for money in chat (deposit, viewing fee or mobile money)');
  end if;
  select count(*) into n from listing_reports rr join properties x on x.id = rr.property_id
   where x.owner_id = uid and rr.status = 'action_taken';
  if n > 0 then
    s := s + least(n, 3) * public._rc('w_report')::int;
    r := r || jsonb_build_object('code', 'confirmed_reports', 'points', least(n, 3) * public._rc('w_report'),
           'text', format('%s confirmed report(s) on their listings', n));
  end if;
  insert into account_risk (user_id, score, reasons, updated_at) values (uid, s, r, now())
  on conflict (user_id) do update set score = excluded.score, reasons = excluded.reasons, updated_at = now();
  return s;
end $$;
revoke execute on function public.account_risk_recalc(uuid) from public, anon, authenticated;

-- ---------- пересчёт риска объявления ----------
create or replace function public.risk_recalc(pid uuid)
returns int language plpgsql security definer set search_path = public, extensions as $$
declare
  l properties%rowtype;
  a profiles%rowtype;
  m record;
  r jsonb := '[]';
  s int := 0;
  v_acc int;
  v_med numeric;
  v_cnt int;
  v_n int;
  v_trusted_a boolean;
  v_group uuid;
  v_old_group uuid;
  v_photo boolean;
  v_text boolean;
  v_dup_pts boolean := false;
  v_prev listing_risk%rowtype;
  v_review int := public._rc('review_at')::int;
  v_warn int := public._rc('warn_at')::int;
  v_txt text;
begin
  perform set_config('zumi.risk', 'on', true);
  select * into l from properties where id = pid;
  if not found or l.is_demo or l.owner_id is null then return 0; end if;
  select * into a from profiles where id = l.owner_id;
  v_trusted_a := public._trusted(l.owner_id);
  v_old_group := l.dup_group;
  v_txt := coalesce(l.title, '') || ' ' || coalesce(l.description, '');

  -- повторы: одинаковые фото или похожий текст у объявлений ДРУГИХ авторов
  for m in
    select x.*, o.agency_id as o_agency, o.full_name as o_name, o.agency_name as o_agency_name,
           public._trusted(x.owner_id) as o_trusted,
           exists (select 1 from property_images i join property_images j on j.property_id = x.id
                    where i.property_id = l.id and i.phash is not null and j.phash is not null
                      and bit_count(i.phash # j.phash) <= public._rc('photo_distance')) as photo_match,
           (length(coalesce(l.description, '')) >= 40
            and extensions.similarity(v_txt, coalesce(x.title, '') || ' ' || coalesce(x.description, ''))
                >= public._rc('text_similarity')) as text_match
      from properties x
      left join profiles o on o.id = x.owner_id
     where x.id <> l.id and not x.is_demo and x.owner_id is not null and x.owner_id <> l.owner_id
       and x.status in ('active', 'pending') and x.deal_type = l.deal_type
       and (exists (select 1 from property_images i join property_images j on j.property_id = x.id
                     where i.property_id = l.id and i.phash is not null and j.phash is not null
                       and bit_count(i.phash # j.phash) <= public._rc('photo_distance'))
            or (length(coalesce(l.description, '')) >= 40
                and (coalesce(x.title, '') || ' ' || coalesce(x.description, '')) operator(extensions.%) v_txt))
  loop
    v_photo := m.photo_match;
    v_text := m.text_match;
    continue when not v_photo and not v_text;
    if (a.agency_id is not null and a.agency_id = m.o_agency)
       or (v_trusted_a and m.o_trusted
           and abs(l.price - m.price) <= public._rc('group_price_diff') * greatest(m.price, 1)) then
      -- нормальный повтор: один дом у агентства / у проверенных агентов → группа, 0 баллов
      v_group := coalesce(v_group, m.dup_group, l.dup_group, least(l.id, m.id));
      update properties set dup_group = v_group where id in (l.id, m.id) and dup_group is distinct from v_group;
    elsif not v_trusted_a and m.o_trusted and m.created_at < l.created_at
          and (l.price < m.price * 0.95 or l.area_id is distinct from m.area_id) and not v_dup_pts then
      v_dup_pts := true;
      if v_photo then
        s := s + public._rc('w_photo_dup')::int;
        r := r || jsonb_build_object('code', 'photo_dup', 'points', public._rc('w_photo_dup'), 'other', m.id,
               'text', format('Photos match a listing by verified %s %s posted earlier%s',
                              case when m.o_agency_name is not null then 'agent' else 'account' end,
                              coalesce(m.o_agency_name, m.o_name, ''),
                              case when l.price < m.price * 0.95 then format(' — here the price is %s%% lower',
                                     round(100 - l.price * 100 / greatest(m.price, 1)))
                                   else ' — but in a different area' end));
      end if;
      if v_text then
        s := s + public._rc('w_text_dup')::int;
        r := r || jsonb_build_object('code', 'text_dup', 'points', public._rc('w_text_dup'), 'other', m.id,
               'text', format('Text copies a listing by verified %s posted earlier', coalesce(m.o_agency_name, m.o_name, 'account')));
      end if;
    end if;
  end loop;
  -- больше не похоже ни на что — выходим из группы
  if v_group is null and v_old_group is not null
     and not exists (select 1 from properties where dup_group = v_old_group and id <> l.id) then
    update properties set dup_group = null, dup_lead = null where id = l.id;
  end if;

  -- цена сильно ниже медианы похожих
  select percentile_cont(0.5) within group (order by x.price), count(*) into v_med, v_cnt
    from properties x
   where x.id <> l.id and not x.is_demo and x.status = 'active' and x.area_id = l.area_id
     and x.deal_type = l.deal_type and x.property_type = l.property_type
     and coalesce(x.bedrooms, -1) = coalesce(l.bedrooms, -1)
     and coalesce(x.rent_period, '') = coalesce(l.rent_period, '') and coalesce(x.currency, 'ZMW') = coalesce(l.currency, 'ZMW');
  if v_cnt >= public._rc('min_comparables') and l.price < v_med * (1 - public._rc('price_drop')) then
    s := s + public._rc('w_low_price')::int;
    r := r || jsonb_build_object('code', 'low_price', 'points', public._rc('w_low_price'),
           'text', format('Price is %s%% below similar listings in this area (typical: %s)',
                          round(100 - l.price * 100 / greatest(v_med, 1)), round(v_med)));
  end if;

  -- чат по этому объявлению: автор просит деньги / кидает ссылки
  if exists (select 1 from chat_flags where property_id = l.id and sender_id = l.owner_id and kind = 'payment') then
    s := s + public._rc('w_chat_payment')::int;
    r := r || jsonb_build_object('code', 'chat_payment', 'points', public._rc('w_chat_payment'),
           'text', 'In chat the lister asked for a deposit, viewing fee or mobile money');
  end if;
  if exists (select 1 from chat_flags where property_id = l.id and sender_id = l.owner_id and kind = 'link') then
    s := s + public._rc('w_chat_link')::int;
    r := r || jsonb_build_object('code', 'chat_link', 'points', public._rc('w_chat_link'),
           'text', 'In chat the lister sent links to other websites');
  end if;

  -- жалобы (разные люди; подтверждённые и новые)
  select count(*) into v_n from listing_reports where property_id = l.id and status <> 'reviewed'
     and reason in ('scam', 'asked_prepayment');
  if v_n > 0 then
    s := s + least(v_n, 2) * public._rc('w_report_scam')::int;
    r := r || jsonb_build_object('code', 'reports_scam', 'points', least(v_n, 2) * public._rc('w_report_scam'),
           'text', format('%s report(s): scam or asked for prepayment', v_n));
  end if;
  select count(*) into v_n from listing_reports where property_id = l.id and status <> 'reviewed'
     and reason not in ('scam', 'asked_prepayment', 'not_available');
  if v_n > 0 then
    s := s + least(v_n, 3) * public._rc('w_report')::int;
    r := r || jsonb_build_object('code', 'reports', 'points', least(v_n, 3) * public._rc('w_report'),
           'text', format('%s other report(s)', v_n));
  end if;

  -- аккаунт: всплеск активности нового аккаунта (баллы идут и объявлению)
  v_acc := public.account_risk_recalc(l.owner_id);
  select coalesce(sum((e->>'points')::int), 0) into v_n
    from account_risk ar, jsonb_array_elements(ar.reasons) e
   where ar.user_id = l.owner_id and e->>'code' in ('burst_listings', 'burst_chats');
  if v_n > 0 then
    s := s + v_n;
    r := r || jsonb_build_object('code', 'account_burst', 'points', v_n,
           'text', 'Brand-new account with unusually high activity');
  end if;

  select * into v_prev from listing_risk where property_id = l.id;
  insert into listing_risk (property_id, score, reasons, updated_at) values (l.id, s, r, now())
  on conflict (property_id) do update set score = excluded.score, reasons = excluded.reasons, updated_at = now();

  if v_group is not null then perform public._regroup(v_group); end if;
  if v_old_group is not null and v_old_group is distinct from v_group then perform public._regroup(v_old_group); end if;

  -- 4. автоматически — только обратимое. Команда отметила «в порядке» — не трогаем, пока риск не вырос
  if s >= v_review and (v_prev.cleared_score is null or s > v_prev.cleared_score) then
    if l.status = 'active' then
      update properties set status = 'pending', approved_at = null,
             moderation_note = 'Automatic safety check — the Zumi team will review it shortly.'
       where id = l.id;
      insert into risk_alerts (property_id, score, action) values (l.id, s, 'review');
      perform public._audit_sys('risk_review', 'listing', l.id::text, format('risk %s', s));
    end if;
    if s >= v_warn then
      update conversations set risk_warned_at = now() where property_id = l.id and risk_warned_at is null;
      if found then
        insert into risk_alerts (property_id, score, action) values (l.id, s, 'warn');
        perform public._audit_sys('risk_warn_chats', 'listing', l.id::text, format('risk %s', s));
      end if;
    end if;
  end if;
  return s;
end $$;
revoke execute on function public.risk_recalc(uuid) from public, anon, authenticated;

-- ---------- триггеры пересчёта ----------
create or replace function public._risk_on_property()
returns trigger language plpgsql security definer set search_path = public, extensions as $$
begin
  if coalesce(current_setting('zumi.risk', true), '') = 'on' then return new; end if;
  if new.is_demo or new.owner_id is null then return new; end if;
  if tg_op = 'UPDATE' and new.price is not distinct from old.price and new.title is not distinct from old.title
     and new.description is not distinct from old.description and new.area_id is not distinct from old.area_id
     and new.deal_type is not distinct from old.deal_type and new.bedrooms is not distinct from old.bedrooms
     and new.status is not distinct from old.status then
    return new;
  end if;
  perform public.risk_recalc(new.id);
  perform set_config('zumi.risk', '', true);
  return new;
end $$;
drop trigger if exists zz_risk_on_property on public.properties;
create trigger zz_risk_on_property after insert or update on public.properties
  for each row execute function public._risk_on_property();

create or replace function public._risk_on_image()
returns trigger language plpgsql security definer set search_path = public, extensions as $$
begin
  if coalesce(current_setting('zumi.risk', true), '') = 'on' then return new; end if;
  if new.phash is not null and (tg_op = 'INSERT' or old.phash is distinct from new.phash) then
    perform public.risk_recalc(new.property_id);
    perform set_config('zumi.risk', '', true);
  end if;
  return new;
end $$;
drop trigger if exists zz_risk_on_image on public.property_images;
create trigger zz_risk_on_image after insert or update of phash on public.property_images
  for each row execute function public._risk_on_image();

create or replace function public._risk_on_report()
returns trigger language plpgsql security definer set search_path = public, extensions as $$
begin
  if coalesce(current_setting('zumi.risk', true), '') = 'on' then return new; end if;
  perform public.risk_recalc(new.property_id);
  perform set_config('zumi.risk', '', true);
  return new;
end $$;
drop trigger if exists zz_risk_on_report on public.listing_reports;
create trigger zz_risk_on_report after insert or update of status on public.listing_reports
  for each row execute function public._risk_on_report();

-- чат: стоп-слова и внешние ссылки
create or replace function public._chat_scan(p_body text)
returns jsonb language sql stable security definer set search_path = public, extensions as $$
  select jsonb_build_object(
    'payment', (select string_agg(w, ', ') from (
        select trim(x) as w from unnest(string_to_array(coalesce((select value from app_settings where key = 'chat_stop_words'), ''), ',')) x
      ) t where length(w) >= 3 and lower(p_body) like '%' || lower(w) || '%'),
    'link', p_body ~* '(https?://|www\.)' and p_body !~* '^[^h]*https?://(www\.)?zumihome\.com');
$$;

create or replace function public._risk_on_message()
returns trigger language plpgsql security definer set search_path = public, extensions as $$
declare
  c conversations%rowtype;
  v jsonb := public._chat_scan(new.body);
  v_new boolean := false;
begin
  select * into c from conversations where id = new.conversation_id;
  if v->>'payment' is not null then
    insert into chat_flags (message_id, conversation_id, property_id, sender_id, kind, words)
    values (new.id, new.conversation_id, c.property_id, new.sender_id, 'payment', v->>'payment');
    v_new := true;
  end if;
  if (v->>'link')::boolean then
    insert into chat_flags (message_id, conversation_id, property_id, sender_id, kind, words)
    values (new.id, new.conversation_id, c.property_id, new.sender_id, 'link', null);
    v_new := true;
  end if;
  if coalesce(current_setting('zumi.risk', true), '') = 'on' then return new; end if;
  if v_new and c.property_id is not null then
    perform public.risk_recalc(c.property_id);
    perform set_config('zumi.risk', '', true);
  elsif v_new then
    perform public.account_risk_recalc(new.sender_id);
  end if;
  return new;
end $$;
drop trigger if exists zz_risk_on_message on public.messages;
create trigger zz_risk_on_message after insert on public.messages
  for each row execute function public._risk_on_message();

-- номер скрыт, пока объявление на проверке по риску (на всякий случай — и для активных с высоким риском)
create or replace function public._risk_blocks_phone(pid uuid)
returns boolean language sql stable security definer set search_path = public, extensions as $$
  select exists (select 1 from listing_risk r where r.property_id = pid
                  and r.score >= public._rc('review_at') and (r.cleared_score is null or r.score > r.cleared_score));
$$;

create or replace function public.reveal_phone(pid uuid)
returns text language plpgsql security definer set search_path = public, extensions as $$
declare
  uid uuid := auth.uid();
  p record;
  me record;
begin
  if uid is null then raise exception 'AUTH'; end if;
  select pr.banned_at, pr.phone_verified_at into me from profiles pr where pr.id = uid;
  if me.banned_at is not null then raise exception 'ACCOUNT_BLOCKED'; end if;

  select pp.owner_id, pp.contact_phone, pp.status, pp.is_demo, coalesce(o.contact_mode, 'phone') as mode
    into p from properties pp left join profiles o on o.id = pp.owner_id where pp.id = pid;
  if p is null then raise exception 'NOT_FOUND'; end if;
  if p.owner_id = uid then return p.contact_phone; end if;           -- своё объявление
  if p.status <> 'active' then raise exception 'NOT_FOUND'; end if;
  if public._risk_blocks_phone(pid) then raise exception 'UNDER_REVIEW'; end if;
  if me.phone_verified_at is null then raise exception 'PHONE_NOT_VERIFIED'; end if;
  if p.mode = 'chat' then raise exception 'CHAT_ONLY'; end if;
  if coalesce(p.contact_phone, '') = '' then raise exception 'NO_PHONE'; end if;

  if not exists (select 1 from phone_reveals where user_id = uid and property_id = pid
                   and created_at > now() - interval '1 day') then
    if (select count(*) from phone_reveals where user_id = uid and created_at > now() - interval '1 day') >= 15 then
      raise exception 'REVEAL_LIMIT';
    end if;
    insert into phone_reveals (user_id, property_id) values (uid, pid);
    perform public._campaign_bump(pid, 'call');
  end if;
  return p.contact_phone;
end $$;

-- ---------- лента: одна карточка на группу ----------
create or replace view public.property_feed as
  select p.id, p.owner_id, p.title, p.description, p.deal_type, p.property_type, p.price, p.currency,
         p.rent_period, p.bedrooms, p.bathrooms, p.area_sqm, p.plot_sqm, p.furnished, p.amenities,
         p.area_id, p.address,
         -- комната: точное место видят только автор и команда, остальным — примерно (~1 км)
         (case when p.property_type = 'room' and not coalesce(p.owner_id = auth.uid(), false) and not public.is_admin()
              then st_snaptogrid(p.location::geometry, 0.01)::geography(point, 4326)
              else p.location end)::geography(point, 4326) as location,
         p.status, p.promoted_until, p.views_count, p.is_demo,
         p.created_at, p.updated_at, p.listed_by, p.contact_name, p.renovation, p.kids_allowed,
         p.pets_allowed, p.lease_term, p.property_verified_at, p.property_verify_method,
         p.ownership_verified_at, p.confirmed_at, p.highlights, p.reports_count,
         p.approved_at, p.moderation_note,
         st_y(case when p.property_type = 'room' and not coalesce(p.owner_id = auth.uid(), false) and not public.is_admin()
                   then st_snaptogrid(p.location::geometry, 0.01) else p.location::geometry end) as lat,
         st_x(case when p.property_type = 'room' and not coalesce(p.owner_id = auth.uid(), false) and not public.is_admin()
                   then st_snaptogrid(p.location::geometry, 0.01) else p.location::geometry end) as lng,
         a.name  as area_name,
         a.city  as city,
         coalesce(p.promoted_until > now(), false)  as is_promoted,
         (p.property_verified_at is not null)       as property_verified,
         (p.ownership_verified_at is not null)      as ownership_verified,
         (pr.phone_verified_at is not null)         as owner_phone_verified,
         coalesce(public.person_verified(p.owner_id), p.is_demo and p.listed_by = 'agent') as owner_identity_verified,
         pr.full_name   as owner_name,
         pr.agency_name as agency_name,
         pr.avatar_url  as owner_avatar_url,
         pr.role        as owner_role,
         coalesce(pr.contact_mode, 'phone') as contact_mode,
         (coalesce(p.contact_phone, '') <> '') as has_phone,
         (p.is_demo or coalesce(p.confirmed_at, p.created_at) >
            now() - public._hide_interval(p.property_type, p.listed_by)) as is_fresh,
         coalesce(
           (select array_agg(i.url order by i.sort_order)
              from property_images i where i.property_id = p.id),
           '{}'::text[]) as image_urls,
         coalesce(
           (select array_agg(coalesce(i.thumb_url, i.url) order by i.sort_order)
              from property_images i where i.property_id = p.id),
           '{}'::text[]) as thumb_urls,
         (p.is_demo or pr.role is distinct from 'agent' or pr.licence_verified_at is not null) as owner_licence_verified,
         p.nearby,
         (pr.role = 'agent' and pr.licence_verified_at is not null) as owner_licensed,
         p.hidden_by, p.hidden_reason, p.hidden_at,
         p.room_info,
         p.units_total, p.units_available,
         p.advance_months,
         p.dup_group, coalesce(p.dup_lead, true) as dup_lead
    from properties p
    left join areas a     on a.id  = p.area_id
    left join profiles pr on pr.id = p.owner_id
   where (p.status = 'active' and (p.property_type <> 'room' or public.rooms_on()))
      or p.owner_id = auth.uid() or public.is_admin();
grant select on public.property_feed to anon, authenticated;


-- «Also offered by» — другие агенты с этим же домом
create or replace function public.also_offered(p_id uuid)
returns table (id uuid, owner_name text, agency_name text, licensed boolean, price numeric, currency text,
               rent_period text, slug text)
language sql stable security definer set search_path = public, extensions as $$
  select x.id, coalesce(nullif(trim(o.full_name), ''), 'Agent'), nullif(trim(o.agency_name), ''),
         (o.role = 'agent' and o.licence_verified_at is not null), x.price, coalesce(x.currency, 'ZMW'),
         x.rent_period, o.slug
    from properties p
    join properties x on x.dup_group = p.dup_group and x.id <> p.id and x.status = 'active'
    left join profiles o on o.id = x.owner_id
   where p.id = p_id and p.dup_group is not null
   order by x.price
   limit 10;
$$;
grant execute on function public.also_offered(uuid) to anon, authenticated;

-- есть ли предупреждение по переписке (риск 70+)
create or replace function public.conversation_warning(p_conv uuid)
returns boolean language sql stable security definer set search_path = public, extensions as $$
  select coalesce((select c.risk_warned_at is not null from conversations c
                    where c.id = p_conv and auth.uid() in (c.buyer_id, c.seller_id)), false);
$$;
grant execute on function public.conversation_warning(uuid) to authenticated;

-- стоп-слова — в приложение (баннер в чате)
create or replace function public.app_flags()
returns jsonb language sql stable security definer set search_path = public, extensions as $$
  select jsonb_build_object('promotion', public.promotion_on(), 'ads', public.ads_on(),
                            'wa_verify', public._wa_verify_number(), 'billing', public.billing_on(),
                            'rooms', public.rooms_on(),
                            'chat_stop_words', (select value from app_settings where key = 'chat_stop_words'));
$$;
grant execute on function public.app_flags() to anon, authenticated;

-- ---------- 6. админка: раздел Risk ----------
create or replace function public.admin_risk_list(p_limit int default 100)
returns jsonb language sql stable security definer set search_path = public, extensions as $$
  select case when not public.is_admin() then '[]'::jsonb else coalesce(jsonb_agg(t order by t.score desc), '[]'::jsonb) end
    from (
      select r.property_id, r.score, r.reasons, r.updated_at, r.cleared_score,
             p.title, p.status, p.price, p.currency, p.rent_period, p.deal_type, a.name as area_name,
             p.owner_id, coalesce(o.full_name, '—') as owner_name, o.agency_name, o.role as owner_role,
             o.banned_at is not null as owner_banned,
             coalesce(ar.score, 0) as account_score, coalesce(ar.reasons, '[]'::jsonb) as account_reasons,
             (select count(*) from properties g where g.dup_group = p.dup_group and p.dup_group is not null) as group_size
        from listing_risk r
        join properties p on p.id = r.property_id
        left join areas a on a.id = p.area_id
        left join profiles o on o.id = p.owner_id
        left join account_risk ar on ar.user_id = p.owner_id
       where r.score > 0 or p.dup_group is not null
       order by r.score desc
       limit greatest(1, least(p_limit, 500))
    ) t;
$$;
grant execute on function public.admin_risk_list(int) to authenticated;

-- действия команды: safe (всё в порядке), review (на проверку), hide (скрыть), ban (только владелец Zumi)
create or replace function public.admin_risk_action(p_property uuid, p_action text, p_note text default null)
returns void language plpgsql security definer set search_path = public, extensions as $$
declare v_owner uuid; v_score int;
begin
  if not public.is_admin() then raise exception 'NOT_ADMIN'; end if;
  select owner_id into v_owner from properties where id = p_property;
  if not found then raise exception 'NOT_FOUND'; end if;
  select score into v_score from listing_risk where property_id = p_property;
  perform set_config('zumi.risk', 'on', true);
  if p_action = 'safe' then
    update listing_risk set cleared_score = coalesce(v_score, 0), cleared_by = auth.uid(), cleared_at = now()
     where property_id = p_property;
    update properties set status = 'active', approved_at = coalesce(approved_at, now()), moderation_note = null
     where id = p_property and status = 'pending';
    update conversations set risk_warned_at = null where property_id = p_property;
  elsif p_action = 'review' then
    update properties set status = 'pending', approved_at = null,
           moderation_note = 'The Zumi team is checking this listing.' where id = p_property;
  elsif p_action = 'hide' then
    update properties set status = 'archived',
           moderation_note = coalesce(p_note, 'Hidden by the Zumi team after a safety check.') where id = p_property;
  elsif p_action = 'ban' then
    if not public.is_owner() then raise exception 'OWNER_ONLY'; end if;
    if v_owner is null then raise exception 'NOT_FOUND'; end if;
    update profiles set banned_at = now(), ban_reason = coalesce(p_note, 'Fraud risk') where id = v_owner;
    update properties set status = 'archived' where owner_id = v_owner and status in ('active', 'pending');
  else
    raise exception 'UNKNOWN_ACTION';
  end if;
  perform public._audit('risk_' || p_action, 'listing', p_property::text, p_note);
end $$;
grant execute on function public.admin_risk_action(uuid, text, text) to authenticated;

-- настройки риска и стоп-слова (меняет только владелец Zumi)
create or replace function public.admin_risk_settings()
returns jsonb language sql stable security definer set search_path = public, extensions as $$
  select case when public.is_admin() then jsonb_build_object(
    'config', public._risk_cfg(),
    'stop_words', (select value from app_settings where key = 'chat_stop_words')) end;
$$;
grant execute on function public.admin_risk_settings() to authenticated;

create or replace function public.admin_set_risk_settings(p_config jsonb, p_stop_words text)
returns void language plpgsql security definer set search_path = public, extensions as $$
declare k text;
begin
  if not public.is_owner() then raise exception 'OWNER_ONLY'; end if;
  if p_config is not null then
    if jsonb_typeof(p_config) <> 'object' then raise exception 'BAD_SETTING'; end if;
    for k in select jsonb_object_keys(p_config) loop
      if not (public._risk_cfg() ? k) or jsonb_typeof(p_config->k) <> 'number' or (p_config->>k)::numeric < 0 then
        raise exception 'BAD_SETTING';
      end if;
    end loop;
    insert into app_settings (key, value) values ('risk_config', (public._risk_cfg() || p_config)::text)
    on conflict (key) do update set value = excluded.value;
  end if;
  if p_stop_words is not null then
    if length(p_stop_words) > 3000 then raise exception 'TOO_LONG'; end if;
    insert into app_settings (key, value) values ('chat_stop_words', p_stop_words)
    on conflict (key) do update set value = excluded.value;
  end if;
  perform public._audit('setting', 'settings', 'risk', left(coalesce(p_config::text, '') || ' | words', 100));
end $$;
grant execute on function public.admin_set_risk_settings(jsonb, text) to authenticated;

-- пересчитать всё (кнопка в админке и будильник раз в 30 минут — медианы цен и «всплески» меняются со временем)
create or replace function public.risk_recalc_recent()
returns int language plpgsql security definer set search_path = public, extensions as $$
declare v int := 0; x uuid;
begin
  if auth.uid() is not null and not public.is_admin() then raise exception 'NOT_ADMIN'; end if;
  for x in select id from properties where not is_demo and owner_id is not null and status in ('active', 'pending')
              and coalesce(updated_at, created_at) > now() - interval '60 days' loop
    perform public.risk_recalc(x);
    v := v + 1;
  end loop;
  perform set_config('zumi.risk', '', true);
  return v;
end $$;
revoke execute on function public.risk_recalc_recent() from public, anon;
grant execute on function public.risk_recalc_recent() to authenticated;

-- ---------- письма команде + дневной потолок уведомлений (письма регистрации важнее) ----------
create or replace function public.email_due(p_limit int default 40)
returns jsonb language plpgsql security definer set search_path = public, extensions as $$
declare
  v jsonb;
  -- дневной потолок для уведомлений: на бесплатном Resend 100 писем в сутки на всё,
  -- письма регистрации и сброса пароля важнее (их шлёт Supabase через тот же Resend)
  v_cap int := coalesce((select value::int from app_settings where key = 'email_daily_cap'), 60);
  v_left int;
begin
  insert into app_settings (key, value) values ('email_last_run', now()::text)
  on conflict (key) do update set value = excluded.value;
  delete from email_log where sent_at < now() - interval '90 days';
  v_left := v_cap - (select count(*) from email_log where ok and sent_at > now() - interval '24 hours');
  if v_left <= 0 then return '[]'::jsonb; end if;

  with people as (
    select p.id, u.email,
           coalesce(nullif(trim(p.full_name), ''), 'there') as name
      from profiles p
      join auth.users u on u.id = p.id
     where p.email_alerts_off_at is null
       and p.banned_at is null
       and u.email is not null
       and u.email_confirmed_at is not null
  ),
  -- 1. непрочитанные сообщения (старше 10 минут, за последние 2 дня)
  chat as (
    select v.uid as user_id, 'chat'::text as kind, c.id as ref_id, 1 as prio,
           jsonb_build_object(
             'from', coalesce(nullif(trim(case when s.role = 'agent' and coalesce(s.agency_name, '') <> ''
                                              then s.agency_name else s.full_name end), ''), 'Someone'),
             'title', coalesce(pr.title, 'your listing'),
             'count', (select count(*) from messages m
                        where m.conversation_id = c.id and m.sender_id = v.other
                          and m.created_at > coalesce(cr.read_at, '-infinity')),
             'snippet', (select left(m.body, 160) from messages m
                          where m.conversation_id = c.id and m.sender_id = v.other
                          order by m.created_at desc limit 1)) as data
      from conversations c
      cross join lateral (values (c.buyer_id, c.seller_id), (c.seller_id, c.buyer_id)) v(uid, other)
      left join chat_reads cr on cr.conversation_id = c.id and cr.user_id = v.uid
      left join profiles s on s.id = v.other
      left join properties pr on pr.id = c.property_id
     where c.last_message_at > now() - interval '2 days'
       and exists (select 1 from messages m
                    where m.conversation_id = c.id and m.sender_id = v.other
                      and m.created_at > coalesce(cr.read_at, '-infinity')
                      and m.created_at > now() - interval '2 days'
                      and m.created_at < now() - interval '10 minutes')
       and not exists (select 1 from email_log l
                        where l.user_id = v.uid and l.kind = 'chat' and l.ref_id = c.id
                          and l.sent_at > coalesce(cr.read_at, '-infinity'))
  ),
  -- 2. ответ поддержки
  support as (
    select t.user_id, 'support'::text, t.id, 2,
           jsonb_build_object('subject', t.subject, 'snippet', left(sm.body, 160))
      from support_tickets t
      cross join lateral (select body, created_at from support_messages
                           where ticket_id = t.id and is_staff order by created_at desc limit 1) sm
     where sm.created_at > now() - interval '2 days'
       and sm.created_at < now() - interval '3 minutes'
       and not exists (select 1 from email_log l
                        where l.user_id = t.user_id and l.kind = 'support' and l.ref_id = t.id
                          and l.sent_at > sm.created_at)
  ),
  -- 3. модерация: одобрено (только то, что ждало модератора) / не одобрено
  approved as (
    select p.owner_id, 'approved'::text, p.id, 3,
           jsonb_build_object('title', p.title, 'listing_id', p.id)
      from properties p
     where p.owner_id is not null and not p.is_demo and p.status = 'active'
       and p.approved_at > now() - interval '2 days'
       and p.approved_at > p.created_at + interval '5 minutes'
       and not exists (select 1 from email_log l
                        where l.user_id = p.owner_id and l.kind = 'approved' and l.ref_id = p.id)
  ),
  not_approved as (
    select p.owner_id, 'not_approved'::text, p.id, 3,
           jsonb_build_object('title', p.title, 'note', p.moderation_note)
      from properties p
     where p.owner_id is not null and not p.is_demo and p.status = 'archived'
       and p.moderation_note is not null
       and coalesce(p.updated_at, p.created_at) > now() - interval '2 days'
       and not exists (select 1 from email_log l
                        where l.user_id = p.owner_id and l.kind = 'not_approved' and l.ref_id = p.id
                          and l.sent_at > coalesce(p.updated_at, p.created_at) - interval '1 minute')
  ),
  -- 4. «Still available?» — пора подтвердить (как в my_listings_to_confirm)
  confirm as (
    -- одно письмо на человека за раз, даже если объявлений много (агентам — раз в неделю)
    select x.owner_id, 'confirm'::text, x.owner_id, 4,
           jsonb_build_object('count', x.n, 'title', x.title, 'listing_id', x.listing_id, 'hide_in', x.hide_in)
      from (
        select p.owner_id, count(*)::int as n,
               (array_agg(p.title order by coalesce(p.confirmed_at, p.approved_at, p.created_at)))[1] as title,
               (array_agg(p.id order by coalesce(p.confirmed_at, p.approved_at, p.created_at)))[1] as listing_id,
               greatest(1, min(extract(day from public._hide_interval(p.property_type, p.listed_by))::int
                 - extract(day from now() - coalesce(p.confirmed_at, p.approved_at, p.created_at))::int)) as hide_in
          from properties p
         where p.owner_id is not null and not p.is_demo and p.status = 'active'
           and coalesce(p.confirmed_at, p.approved_at, p.created_at) < now() - public._ask_interval(p.property_type, p.listed_by)
         group by p.owner_id
      ) x
     where not exists (select 1 from email_log l
                        where l.user_id = x.owner_id and l.kind = 'confirm' and l.sent_at > now() - interval '6 days')
  ),
  -- 5. тариф заканчивается через 5 дней или меньше — одно напоминание на срок
  plan_end as (
    select p.id, 'plan_ending'::text, p.id, 5,
           jsonb_build_object('plan', p.plan, 'until', to_char(p.plan_until, 'DD Mon YYYY'),
                              'days', greatest(1, ceil(extract(epoch from p.plan_until - now()) / 86400)::int))
      from profiles p
     where p.plan is not null and p.plan_until > now() and p.plan_until < now() + interval '5 days'
       and not exists (select 1 from email_log l
                        where l.user_id = p.id and l.kind = 'plan_ending' and l.ref_id = p.id
                          and l.sent_at > p.plan_until - interval '6 days')
  ),
  -- 0. команде: подозрительное объявление ушло на проверку (одно письмо на объявление за сутки)
  risk as (
    select t.id as user_id, 'risk_alert'::text as kind, ra.property_id as ref_id, 0 as prio,
           jsonb_build_object('title', p.title, 'listing_id', p.id, 'score', ra.score, 'action', ra.action,
                              'reason', (select e->>'text' from listing_risk lr, jsonb_array_elements(lr.reasons) e
                                          where lr.property_id = p.id order by (e->>'points')::int desc limit 1)) as data
      from (select distinct on (property_id) * from risk_alerts
             where created_at > now() - interval '2 days' order by property_id, score desc) ra
      join properties p on p.id = ra.property_id
      join profiles t on t.role = 'admin' and coalesce(t.team_level, 'owner') = 'owner'
     where not exists (select 1 from email_log l
                        where l.user_id = t.id and l.kind = 'risk_alert' and l.ref_id = ra.property_id
                          and l.sent_at > now() - interval '1 day')
  ),
  allx as (
    select * from risk union all select * from chat union all select * from support union all select * from approved
    union all select * from not_approved union all select * from confirm union all select * from plan_end
  )
  select coalesce(jsonb_agg(x order by x.prio), '[]'::jsonb) into v from (
    select a.user_id, a.kind, a.ref_id, a.prio, a.data, pe.email, pe.name,
           public._email_token(a.user_id) as token
      from allx a join people pe on pe.id = a.user_id
     order by a.prio
     limit greatest(1, least(p_limit, 200, v_left))
  ) x;
  return v;
end $$;
revoke execute on function public.email_due(int) from public, anon, authenticated;
grant execute on function public.email_due(int) to service_role;

insert into public.app_settings (key, value) values ('email_daily_cap', '60') on conflict (key) do nothing;

-- ---------- будильники ----------
do $$
begin
  if exists (select 1 from pg_extension where extname = 'pg_cron') then
    perform cron.unschedule(jobid) from cron.job where jobname in ('zumi-risk', 'zumi-photo-hash');
    -- риск: медианы цен и «всплески» меняются со временем
    perform cron.schedule('zumi-risk', '*/30 * * * *', $c$ select public.risk_recalc_recent() $c$);
    -- отпечатки новых фото (функция photo-hash; пока её нет — просто ничего не происходит)
    if exists (select 1 from pg_extension where extname = 'pg_net') then
      perform cron.schedule('zumi-photo-hash', '*/5 * * * *', $c$
        select net.http_post(
          url := (select value from public.app_settings where key = 'functions_url') || '/photo-hash',
          headers := jsonb_build_object('Content-Type', 'application/json',
                       'x-cron-secret', (select value from public.app_settings where key = 'email_cron_secret')),
          body := '{}'::jsonb)
      $c$);
    end if;
  end if;
end $$;

-- для функции photo-hash: какие фото ещё без отпечатка (только сервер)
create or replace function public.photos_to_hash(p_limit int default 30)
returns table (id uuid, url text) language sql stable security definer set search_path = public, extensions as $$
  select i.id, i.url from property_images i
    join properties p on p.id = i.property_id
   where i.hashed_at is null and not p.is_demo and i.url like 'http%'
   order by i.id limit greatest(1, least(p_limit, 100));
$$;
revoke execute on function public.photos_to_hash(int) from public, anon, authenticated;
grant execute on function public.photos_to_hash(int) to service_role;

create or replace function public.photo_hashed(p_id uuid, p_phash text, p_sha256 text, p_error text default null)
returns void language sql security definer set search_path = public, extensions as $$
  update property_images
     set phash = case when p_phash ~ '^[01]{64}$' then p_phash::bit(64) end,
         sha256 = p_sha256, hashed_at = now(), hash_error = left(p_error, 200)
   where id = p_id;
$$;
revoke execute on function public.photo_hashed(uuid, text, text, text) from public, anon, authenticated;
grant execute on function public.photo_hashed(uuid, text, text, text) to service_role;

-- старые объявления — сразу посчитать риск один раз
select public.risk_recalc_recent();

-- проверка
select
  exists (select 1 from information_schema.columns where table_name = 'property_images' and column_name = 'phash') as photos_ok,
  exists (select 1 from information_schema.columns where table_name = 'property_feed' and column_name = 'dup_lead') as feed_ok,
  (select count(*) from pg_proc where proname in ('risk_recalc', 'admin_risk_list', 'admin_risk_action', 'also_offered')) = 4 as risk_ok;
