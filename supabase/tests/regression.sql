-- =====================================================================
--  Проверки базы Zumi. Запускаются при каждой сборке (GitHub) после all_in_one.sql.
--  Любая проверка не прошла → сборка останавливается, сайт не обновляется.
--  zt.ok(название, условие)                    — условие должно быть истинным
--  zt.err(название, 'ОЖИДАЕМАЯ_ОШИБКА', 'sql') — команда должна завершиться этой ошибкой
-- =====================================================================
\set ON_ERROR_STOP 1
create schema if not exists zt;
create or replace function zt.ok(label text, cond boolean) returns void language plpgsql as $$
begin
  if cond is not true then raise exception 'FAILED: %', label; end if;
  raise notice 'ok  %', label;
end $$;
create or replace function zt.err(label text, expected text, q text) returns void language plpgsql as $$
begin
  begin
    execute q;
  exception when others then
    if sqlerrm not like '%' || expected || '%' then
      raise exception 'FAILED: % — expected %, got: %', label, expected, sqlerrm;
    end if;
    raise notice 'ok  % (refused: %)', label, expected;
    return;
  end;
  raise exception 'FAILED: % — expected error %, but it succeeded', label, expected;
end $$;
grant usage on schema zt to anon, authenticated;
grant execute on all functions in schema zt to anon, authenticated;

-- ---------- люди ----------
insert into auth.users(id, email, raw_user_meta_data) values
 ('a0000000-0000-0000-0000-000000000001', 'owner@x.zm',  '{"full_name":"Owner","role":"owner","terms_accepted":true}'),
 ('a0000000-0000-0000-0000-000000000002', 'agent@x.zm',  '{"full_name":"Agent","role":"agent","terms_accepted":true}'),
 ('a0000000-0000-0000-0000-000000000003', 'buyer@x.zm',  '{"full_name":"Buyer","role":"owner","terms_accepted":true}'),
 ('a0000000-0000-0000-0000-000000000004', 'boss@x.zm',   '{"full_name":"Boss"}'),
 ('a0000000-0000-0000-0000-000000000005', 'mod@x.zm',    '{"full_name":"Mod"}');
update profiles set role = 'admin', team_level = 'owner'     where id = 'a0000000-0000-0000-0000-000000000004';
update profiles set role = 'admin', team_level = 'moderator' where id = 'a0000000-0000-0000-0000-000000000005';
update profiles set licence_verified_at = now(), agent_licence_no = 'ZIEA-1' where id = 'a0000000-0000-0000-0000-000000000002';

select zt.ok('every public table has RLS',
  not exists (select 1 from pg_class c join pg_namespace n on n.oid = c.relnamespace
               where n.nspname = 'public' and c.relkind = 'r' and not c.relrowsecurity));

-- ---------- гость ----------
set role anon;
select zt.err('guest cannot read profiles (phones)', 'permission denied', 'select phone from profiles');
select zt.err('guest cannot read listing phones', 'permission denied', 'select contact_phone from properties');
select zt.ok('guest sees no messages', (select count(*) from messages) = 0);
select zt.ok('guest sees no app feedback', (select count(*) from app_feedback) = 0);
select zt.ok('guest sees no settings', (select count(*) from app_settings) = 0);
select zt.ok('promotion is off by default', (app_flags()->>'promotion')::boolean = false);
select zt.err('guest cannot change settings', 'NOT_ADMIN', $$select admin_set_setting('promotion_enabled','true')$$);
reset role;

-- ---------- публикация: нужен телефон, точка, правильное «что рядом» ----------
set role authenticated;
select set_config('request.jwt.claim.sub', 'a0000000-0000-0000-0000-000000000001', false);
select zt.err('publishing without a confirmed phone is refused', 'PHONE_REQUIRED', $$
  insert into properties(owner_id,title,deal_type,property_type,price,location,status,area_id)
  values (auth.uid(),'House','rent','house',5000,'SRID=4326;POINT(28.3 -15.4)','active',(select min(id) from areas))$$);
reset role;
update profiles set phone_verified_at = now() where id in ('a0000000-0000-0000-0000-000000000001', 'a0000000-0000-0000-0000-000000000002');
set role authenticated;
select set_config('request.jwt.claim.sub', 'a0000000-0000-0000-0000-000000000001', false);
select zt.err('unknown "what is nearby" values are refused', 'properties_nearby_ok', $$
  insert into properties(owner_id,title,deal_type,property_type,price,location,status,area_id,nearby)
  values (auth.uid(),'House','rent','house',5000,'SRID=4326;POINT(28.3 -15.4)','active',(select min(id) from areas),'{"pool":"lt1"}')$$);
insert into properties(id,owner_id,title,deal_type,property_type,price,location,status,area_id,nearby,address)
values ('b0000000-0000-0000-0000-000000000001', auth.uid(),'House','rent','house',5000,'SRID=4326;POINT(28.3 -15.4)',
        'active',(select min(id) from areas),'{"shop":"lt1","main_road":"1_3"}','Plot 12');
select zt.ok('first listing goes to review', (select status from properties where id = 'b0000000-0000-0000-0000-000000000001') = 'pending');
select zt.err('documents are no longer accepted', 'row-level security', $$
  insert into verification_requests(user_id,kind,status,consent_at) values (auth.uid(),'identity','pending',now())$$);
reset role;

-- ---------- модерация, скрытие, «ещё доступно?» ----------
set role authenticated;
select set_config('request.jwt.claim.sub', 'a0000000-0000-0000-0000-000000000005', false);
select admin_review_listing('b0000000-0000-0000-0000-000000000001', true);
select set_config('request.jwt.claim.sub', 'a0000000-0000-0000-0000-000000000003', false);
select zt.ok('approved listing is public with nearby', (select nearby->>'shop' from property_feed where id = 'b0000000-0000-0000-0000-000000000001') = 'lt1');
select set_config('request.jwt.claim.sub', 'a0000000-0000-0000-0000-000000000001', false);
update properties set status = 'archived' where id = 'b0000000-0000-0000-0000-000000000001';
select zt.ok('owner hide is marked "owner"', (select hidden_by from properties where id = 'b0000000-0000-0000-0000-000000000001') = 'owner');
update properties set hidden_by = 'team' where id = 'b0000000-0000-0000-0000-000000000001';
select zt.ok('owner cannot forge "hidden by team"', (select hidden_by from properties where id = 'b0000000-0000-0000-0000-000000000001') = 'owner');
update properties set status = 'active' where id = 'b0000000-0000-0000-0000-000000000001';
select zt.ok('owner shows it again', (select status from properties where id = 'b0000000-0000-0000-0000-000000000001') = 'active');
select set_config('request.jwt.claim.sub', 'a0000000-0000-0000-0000-000000000005', false);
select admin_review_listing('b0000000-0000-0000-0000-000000000001', false, 'Fake photos');
select set_config('request.jwt.claim.sub', 'a0000000-0000-0000-0000-000000000001', false);
select zt.ok('team hide keeps the reason', (select hidden_by || ':' || hidden_reason from properties where id = 'b0000000-0000-0000-0000-000000000001') = 'team:Fake photos');
update properties set status = 'active' where id = 'b0000000-0000-0000-0000-000000000001';
select zt.ok('listing hidden by team goes back to review', (select status from properties where id = 'b0000000-0000-0000-0000-000000000001') = 'pending');
reset role;
update properties set status = 'active', approved_at = now() - interval '40 days' where id = 'b0000000-0000-0000-0000-000000000001';
update properties set confirmed_at = now() - interval '40 days' where id = 'b0000000-0000-0000-0000-000000000001';
set role authenticated;
select set_config('request.jwt.claim.sub', 'a0000000-0000-0000-0000-000000000001', false);
select zt.ok('listing not confirmed for 40 days asks the owner', my_listings_to_confirm() = 1);
select zt.ok('and is hidden from search', (select not is_fresh from property_feed where id = 'b0000000-0000-0000-0000-000000000001'));
select answer_still_available('b0000000-0000-0000-0000-000000000001', true);
select zt.ok('"yes, still available" brings it back', my_listings_to_confirm() = 0
  and (select is_fresh from property_feed where id = 'b0000000-0000-0000-0000-000000000001'));
reset role;

-- ---------- чаты: непрочитанные считаются переписками ----------
insert into conversations(id, property_id, buyer_id, seller_id)
values ('c0000000-0000-0000-0000-000000000001', 'b0000000-0000-0000-0000-000000000001',
        'a0000000-0000-0000-0000-000000000003', 'a0000000-0000-0000-0000-000000000001');
insert into messages(conversation_id, sender_id, body)
select 'c0000000-0000-0000-0000-000000000001', 'a0000000-0000-0000-0000-000000000003', 'hi ' || g from generate_series(1, 5) g;
set role authenticated;
select set_config('request.jwt.claim.sub', 'a0000000-0000-0000-0000-000000000001', false);
select zt.ok('5 messages in 1 chat = badge 1', my_unread_count() = 1);
select zt.ok('chat list shows 5 new', (select unread from conversation_list where id = 'c0000000-0000-0000-0000-000000000001') = 5);
select mark_chat_read('c0000000-0000-0000-0000-000000000001');
select zt.ok('opening the chat clears the badge', my_unread_count() = 0);
select set_config('request.jwt.claim.sub', 'a0000000-0000-0000-0000-000000000002', false);
select zt.ok('other people cannot read the chat', (select count(*) from messages) = 0);
reset role;

-- ---------- продвижение: выключатель ----------
set role authenticated;
select set_config('request.jwt.claim.sub', 'a0000000-0000-0000-0000-000000000002', false);
reset role;
insert into properties(id,owner_id,title,deal_type,property_type,price,location,status,area_id,approved_at)
values ('b0000000-0000-0000-0000-000000000002','a0000000-0000-0000-0000-000000000002','Flat','rent','apartment',8000,
        'SRID=4326;POINT(28.3 -15.4)','active',(select min(id) from areas),now());
update properties set status = 'active' where id = 'b0000000-0000-0000-0000-000000000002';
set role authenticated;
select set_config('request.jwt.claim.sub', 'a0000000-0000-0000-0000-000000000002', false);
select zt.err('campaign cannot start while promotion is off', 'PROMOTION_OFF', $$
  insert into campaigns(owner_id,property_id,advertiser,placement,starts_on,ends_on,status)
  values (auth.uid(),'b0000000-0000-0000-0000-000000000002','Agent','search_top',current_date,current_date+3,'active')$$);
select set_config('request.jwt.claim.sub', 'a0000000-0000-0000-0000-000000000005', false);
select zt.err('moderator cannot switch promotion', 'OWNER_ONLY', $$select admin_set_setting('promotion_enabled','true')$$);
select set_config('request.jwt.claim.sub', 'a0000000-0000-0000-0000-000000000004', false);
select admin_set_setting('promotion_enabled', 'true');
select set_config('request.jwt.claim.sub', 'a0000000-0000-0000-0000-000000000002', false);
insert into campaigns(owner_id,property_id,advertiser,placement,starts_on,ends_on,status)
values (auth.uid(),'b0000000-0000-0000-0000-000000000002','Agent','search_top',current_date,current_date+3,'active');
select zt.ok('campaign starts when promotion is on', (select count(*) from campaigns) = 1);
select set_config('request.jwt.claim.sub', 'a0000000-0000-0000-0000-000000000004', false);
select admin_set_setting('promotion_enabled', 'false');
select set_config('request.jwt.claim.sub', 'a0000000-0000-0000-0000-000000000003', false);
select zt.ok('when off nobody else sees campaigns', (select count(*) from campaigns) = 0);
reset role;

-- ---------- отзывы о приложении ----------
set role anon;
select send_app_feedback(2, array['slow','not-a-code'], 'Slow on 3G', 'web', '1.0', 'device-1');
select zt.err('one feedback per device per day', 'TOO_MANY_REQUESTS',
  $$select send_app_feedback(5, null, null, 'web', '1.0', 'device-1')$$);
reset role;
select zt.ok('unknown issue codes are dropped', (select issues = array['slow'] from app_feedback limit 1));
set role authenticated;
select set_config('request.jwt.claim.sub', 'a0000000-0000-0000-0000-000000000005', false);
select zt.err('only the owner reads feedback', 'OWNER_ONLY', $$select owner_app_feedback(30)$$);
select set_config('request.jwt.claim.sub', 'a0000000-0000-0000-0000-000000000004', false);
select zt.ok('owner sees the feedback', (owner_app_feedback(30)->>'count')::int = 1);
reset role;

-- ---------- сроки хранения ----------
insert into auth.users(id, email) values ('a0000000-0000-0000-0000-000000000009', 'banned@x.zm');
update profiles set banned_at = now() - interval '3 years' where id = 'a0000000-0000-0000-0000-000000000009';
insert into phone_reveals(user_id, created_at) values ('a0000000-0000-0000-0000-000000000003', now() - interval '2 years');
select cleanup_retention();
select zt.ok('accounts banned 2+ years ago are deleted', not exists (select 1 from auth.users where id = 'a0000000-0000-0000-0000-000000000009'));
select zt.ok('phone views older than 1 year are deleted', not exists (select 1 from phone_reveals where created_at < now() - interval '1 year'));
set role authenticated;
select zt.err('app users cannot run the cleanup', 'permission denied', 'select cleanup_retention()');
reset role;

select zt.ok('ALL CHECKS PASSED', true);
