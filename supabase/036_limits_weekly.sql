-- =====================================================================
--  Zumi — 036: лимиты и «Ещё актуально?» для агентов
--  • Бесплатные лимиты: собственник 3; агент без лицензии 10, с лицензией 15; агентство — 25 на всех.
--  • «Ещё актуально?»: агентам — каждые 7 дней, без ответа объявление уходит в паузу (из поиска) через 10 дней;
--    собственникам — через 30 / пауза через 37; комнаты — 14 / 21.
--  • Письмо «Ещё актуально?» — одно на человека (со списком), не чаще раза в 6 дней.
--  Уже размещённые объявления не удаляются. Запускать после 035. Можно запускать повторно.
-- =====================================================================

update public.role_limits set free_listings = 3 where role = 'owner';
update public.role_limits set free_listings = 10, free_listings_licensed = 15 where role = 'agent';
update public.role_limits set free_listings = 25, free_listings_licensed = 25 where role = 'agency';

-- через сколько спрашивать и когда ставить на паузу
create or replace function public._ask_interval(p_type text, p_listed_by text)
returns interval language sql immutable as $$
  select case when p_type = 'room' then interval '14 days'
              when p_listed_by = 'agent' then interval '7 days'
              else interval '30 days' end;
$$;
create or replace function public._hide_interval(p_type text, p_listed_by text)
returns interval language sql immutable as $$
  select case when p_type = 'room' then interval '21 days'
              when p_listed_by = 'agent' then interval '10 days'
              else interval '37 days' end;
$$;

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
         p.units_total, p.units_available
    from properties p
    left join areas a     on a.id  = p.area_id
    left join profiles pr on pr.id = p.owner_id
   where (p.status = 'active' and (p.property_type <> 'room' or public.rooms_on()))
      or p.owner_id = auth.uid() or public.is_admin();
grant select on public.property_feed to anon, authenticated;

create or replace function public.my_listings_to_confirm()
returns int language sql stable security definer set search_path = public, extensions as $$
  select count(*)::int from properties
   where owner_id = auth.uid() and status = 'active' and not is_demo
     and coalesce(confirmed_at, approved_at, created_at) < now() - public._ask_interval(property_type, listed_by);
$$;

create or replace function public.email_due(p_limit int default 40)
returns jsonb language plpgsql security definer set search_path = public, extensions as $$
declare
  v jsonb;
begin
  insert into app_settings (key, value) values ('email_last_run', now()::text)
  on conflict (key) do update set value = excluded.value;
  delete from email_log where sent_at < now() - interval '90 days';

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
  allx as (
    select * from chat union all select * from support union all select * from approved
    union all select * from not_approved union all select * from confirm union all select * from plan_end
  )
  select coalesce(jsonb_agg(x order by x.prio), '[]'::jsonb) into v from (
    select a.user_id, a.kind, a.ref_id, a.prio, a.data, pe.email, pe.name,
           public._email_token(a.user_id) as token
      from allx a join people pe on pe.id = a.user_id
     order by a.prio
     limit greatest(1, least(p_limit, 200))
  ) x;
  return v;
end $$;
revoke execute on function public.email_due(int) from public, anon, authenticated;
grant execute on function public.email_due(int) to service_role;

-- проверка
select role, free_listings, free_listings_licensed from public.role_limits order by role;
