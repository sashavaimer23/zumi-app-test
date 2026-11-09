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
grant usage on schema zt to anon, authenticated, service_role;
grant execute on all functions in schema zt to anon, authenticated, service_role;

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
select set_config('request.jwt.claim.sub', '', false);
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

-- ---------- лимиты объявлений ----------
insert into auth.users(id, email, raw_user_meta_data) values
 ('a0000000-0000-0000-0000-000000000011', 'agent2@x.zm', '{"full_name":"Agent Two","role":"agent"}');
select zt.ok('owner: 2 free listings', (select allowed from listing_quota('a0000000-0000-0000-0000-000000000001')) = 2);
select zt.ok('agent without a checked licence: 15', (select allowed from listing_quota('a0000000-0000-0000-0000-000000000011')) = 15);
select zt.ok('agent with a checked licence: 20', (select allowed from listing_quota('a0000000-0000-0000-0000-000000000002')) = 20);
update profiles set extra_listing_slots = 3 where id = 'a0000000-0000-0000-0000-000000000002';
select zt.ok('bought slots are added on top', (select allowed from listing_quota('a0000000-0000-0000-0000-000000000002')) = 23);

-- ---------- рекламные баннеры: выключатель ----------
insert into ads(id, advertiser, title, placement, image_url, target_type, target, starts_on, ends_on, status)
values ('d0000000-0000-0000-0000-000000000001', 'Shop', 'Test ad', 'home_hero', 'https://x/a.jpg', 'link', 'x.zm',
        current_date, current_date + 5, 'active');
select set_config('request.jwt.claim.sub', '', false);   -- гость: без входа
set role anon;
select zt.ok('banners are off by default', (app_flags()->>'ads')::boolean = false and (select count(*) from ads) = 0);
reset role;
set role authenticated;
select set_config('request.jwt.claim.sub', 'a0000000-0000-0000-0000-000000000005', false);
select zt.err('moderator cannot switch banners', 'OWNER_ONLY', $$select admin_set_setting('ads_enabled','true')$$);
select set_config('request.jwt.claim.sub', 'a0000000-0000-0000-0000-000000000004', false);
select zt.ok('owner still sees prepared banners', (select count(*) from ads) = 1);
select admin_set_setting('ads_enabled', 'true');
reset role;
select set_config('request.jwt.claim.sub', '', false);
set role anon;
select zt.ok('banners shown after the owner switch', (app_flags()->>'ads')::boolean and (select count(*) from ads) = 1);
reset role;

-- ---------- вход через Google: завершить регистрацию ----------
insert into auth.users(id, email, raw_user_meta_data) values
 ('a0000000-0000-0000-0000-000000000021', 'g@gmail.com', '{"full_name":"Gina"}');
insert into auth.identities(user_id, provider) values ('a0000000-0000-0000-0000-000000000021', 'google');
update profiles set phone_verified_at = now() where id = 'a0000000-0000-0000-0000-000000000021';
set role authenticated;
select set_config('request.jwt.claim.sub', 'a0000000-0000-0000-0000-000000000021', false);
select zt.ok('google account must finish sign-up', (my_verification()->>'needs_onboarding')::boolean);
select zt.err('google account cannot post before consent', 'FINISH_SIGNUP', $$
  insert into properties(owner_id,title,deal_type,property_type,price,location,status,area_id)
  values (auth.uid(),'House','rent','house',5000,'SRID=4326;POINT(28.3 -15.4)','active',(select min(id) from areas))$$);
select zt.err('consent is required', 'TERMS_REQUIRED', $$select complete_signup('agent','Gina','+260971234567',null,false,false)$$);
select complete_signup('agent', 'Gina Z', '+260971234567', 'ZIEA-1', true, false);
select zt.ok('sign-up finished', not (my_verification()->>'needs_onboarding')::boolean);
select zt.err('finish sign-up only once', 'ALREADY_DONE', $$select complete_signup('owner','X','+260971234567',null,true,false)$$);
select set_config('request.jwt.claim.sub', 'a0000000-0000-0000-0000-000000000002', false);
select zt.ok('email accounts never see the extra step', not (my_verification()->>'needs_onboarding')::boolean);
reset role;
select zt.ok('google account saved as agent with consent',
  (select role = 'agent' and terms_accepted_at is not null from profiles where id = 'a0000000-0000-0000-0000-000000000021'));

-- ---------- подтверждение номера через WhatsApp ----------
select set_config('request.jwt.claim.sub', '', false);
select zt.ok('WhatsApp check is off until a number is set', app_flags()->>'wa_verify' is null);
update app_settings set value = '+1 555 163 7510' where key = 'whatsapp_verify_number';
select zt.ok('number shown to the app', app_flags()->>'wa_verify' = '15551637510');
insert into auth.users(id, email, raw_user_meta_data) values
 ('a0000000-0000-0000-0000-000000000031', 'wa@x.zm', '{"full_name":"Wa User","terms_accepted":"true"}');
set role authenticated;
select set_config('request.jwt.claim.sub', 'a0000000-0000-0000-0000-000000000031', false);
create temp table wa_t as select start_whatsapp_verification()->>'code' as code;
grant select on wa_t to service_role;
select zt.ok('code has 6 digits', (select code ~ '^[0-9]{6}$' from wa_t));
select zt.err('app cannot confirm codes itself', 'permission denied',
  $$select confirm_whatsapp_code('Zumi code 000000', '260971110000')$$);
reset role;
set role service_role;
select zt.ok('wrong code is rejected', confirm_whatsapp_code('Zumi code 999999x', '260971110000') in ('expired','unknown'));
select zt.ok('message from WhatsApp confirms the number',
  confirm_whatsapp_code('Zumi code ' || (select code from wa_t), '260971110000') = 'ok');
select zt.ok('a code works only once', confirm_whatsapp_code('Zumi code ' || (select code from wa_t), '260971110000') = 'expired');
reset role;
select zt.ok('sender number is saved as confirmed',
  (select phone = '+260971110000' and phone_verified_at is not null and phone_verify_channel = 'whatsapp'
     from profiles where id = 'a0000000-0000-0000-0000-000000000031'));
update wa_verify_codes set used_at = null, expires_at = now() + interval '5 minutes', user_id = 'a0000000-0000-0000-0000-000000000011'
 where code = (select code from wa_t);
set role service_role;
select zt.ok('one number — one account', confirm_whatsapp_code('Zumi code ' || (select code from wa_t), '+260 97 111 0000') = 'taken');
reset role;
drop table wa_t;

-- ---------- платные функции ----------
insert into properties(id,owner_id,title,deal_type,property_type,price,location,status,area_id)
values ('b0000000-0000-0000-0000-000000000099','a0000000-0000-0000-0000-000000000002','Agent house','rent','house',9000,
        'SRID=4326;POINT(28.3 -15.4)','active',(select min(id) from areas));
update properties set status = 'active' where id = 'b0000000-0000-0000-0000-000000000099';
select set_config('request.jwt.claim.sub', '', false);
select zt.ok('paid features are off by default', not (app_flags()->>'billing')::boolean);
set role authenticated;
select set_config('request.jwt.claim.sub', 'a0000000-0000-0000-0000-000000000002', false);
select zt.err('nothing can be bought while OFF', 'BILLING_OFF', $$select create_order('boost_7d','b0000000-0000-0000-0000-000000000099')$$);
select zt.ok('price list is public', (select count(*) from price_list where active) >= 10);
select zt.err('app cannot give itself a plan', 'permission denied', $$select mark_order_paid('Z-X','manual','x')$$);
update profiles set plan = 'agency', plan_until = now() + interval '1 year', boost_credits = 99 where id = auth.uid();
reset role;
select zt.ok('plan fields cannot be changed from the app',
  (select plan is null and boost_credits = 0 from profiles where id = 'a0000000-0000-0000-0000-000000000002'));
-- владелец включает
set role authenticated;
select set_config('request.jwt.claim.sub', 'a0000000-0000-0000-0000-000000000005', false);
select zt.err('only the owner switches paid features', 'OWNER_ONLY', $$select admin_set_setting('billing_enabled','true')$$);
select set_config('request.jwt.claim.sub', 'a0000000-0000-0000-0000-000000000004', false);
select admin_set_setting('billing_enabled', 'true');
select admin_set_setting('manual_payment_info', 'Airtel Money 097 000 0000 (Zumi). Reference: your order code.');
select zt.ok('switch ON also shows promotion', (app_flags()->>'billing')::boolean and (app_flags()->>'promotion')::boolean);
-- агент покупает буст, ждёт ручного подтверждения
select set_config('request.jwt.claim.sub', 'a0000000-0000-0000-0000-000000000002', false);
create temp table bo as select create_order('boost_7d', 'b0000000-0000-0000-0000-000000000099', '0971234567') as r;
grant select on bo to service_role;
select zt.ok('order waits for payment with payment info',
  (select r->>'status' = 'pending' and r->>'mode' = 'manual' and r->>'payment_info' like 'Airtel%' and r->>'ref' like 'Z-%' from bo));
select zt.err('cannot boost someone else''s listing', 'NOT_YOUR_LISTING',
  $$select create_order('boost_7d', 'b0000000-0000-0000-0000-000000000001')$$);
select zt.ok('not boosted before payment',
  (select promoted_until is null from properties where id = 'b0000000-0000-0000-0000-000000000099'));
-- владелец подтверждает перевод
select set_config('request.jwt.claim.sub', 'a0000000-0000-0000-0000-000000000004', false);
select admin_mark_order((select (r->>'id')::uuid from bo), 'paid', 'Airtel ref 123');
select zt.ok('paid order switches the boost on',
  (select promoted_until > now() + interval '6 days' from properties where id = 'b0000000-0000-0000-0000-000000000099'));
select zt.ok('order marked done', (select status = 'paid' and fulfilled_at is not null from orders where id = (select (r->>'id')::uuid from bo)));
select zt.ok('owner sees revenue', (admin_billing_status()->>'revenue_30d')::numeric = 60);
-- тариф Pro через «провайдера» (автоматическая оплата)
select set_config('request.jwt.claim.sub', 'a0000000-0000-0000-0000-000000000002', false);
create temp table po as select create_order('plan_pro_m', null, '+260971234567') as r;
grant select on po to service_role;
reset role;
set role service_role;
select zt.ok('provider confirms payment', mark_order_paid((select r->>'ref' from po), 'airtel_money', 'AT-1') = 'ok');
select zt.ok('second confirmation is ignored', mark_order_paid((select r->>'ref' from po), 'airtel_money', 'AT-1') = 'already');
reset role;
select zt.ok('Pro gives 50 listings and 2 boosts',
  (select allowed from listing_quota('a0000000-0000-0000-0000-000000000002')) >= 50
  and (select boost_credits = 2 and plan = 'pro' from profiles where id = 'a0000000-0000-0000-0000-000000000002'));
set role authenticated;
select set_config('request.jwt.claim.sub', 'a0000000-0000-0000-0000-000000000002', false);
select use_boost_credit('b0000000-0000-0000-0000-000000000099');
select zt.err('free campaigns are off while paid features are on', 'USE_BOOST', $$
  insert into campaigns(owner_id, property_id, advertiser, placement, starts_on, ends_on)
  values (auth.uid(), 'b0000000-0000-0000-0000-000000000099', 'Agent', 'home_featured', current_date, current_date + 3)$$);
create temp table fo as select create_order('featured_7d', 'b0000000-0000-0000-0000-000000000099') as r;
select set_config('request.jwt.claim.sub', 'a0000000-0000-0000-0000-000000000004', false);
select admin_mark_order((select (r->>'id')::uuid from fo), 'paid', null);
select zt.ok('paid Featured starts a home campaign',
  (select fulfilled_at is not null from orders where id = (select (r->>'id')::uuid from fo))
  and exists (select 1 from campaigns where property_id = 'b0000000-0000-0000-0000-000000000099' and placement = 'home_featured'));
drop table fo;
select set_config('request.jwt.claim.sub', 'a0000000-0000-0000-0000-000000000002', false);
select zt.ok('boost credit used', (my_billing()->>'boost_credits')::int = 1 and my_billing()->>'plan' = 'pro');
-- собственник: Featured только агентам; доп. место — можно
select set_config('request.jwt.claim.sub', 'a0000000-0000-0000-0000-000000000001', false);
select zt.err('featured is for agents', 'AGENTS_ONLY', $$select create_order('featured_7d','b0000000-0000-0000-0000-000000000001')$$);
create temp table so as select create_order('slot_1') as r;
select set_config('request.jwt.claim.sub', 'a0000000-0000-0000-0000-000000000004', false);
select admin_mark_order((select (r->>'id')::uuid from so), 'paid', null);
reset role;
select zt.ok('extra listing slot added for 30 days',
  (select allowed from listing_quota('a0000000-0000-0000-0000-000000000001')) = 3);
-- тариф арендодателя: только собственникам
set role authenticated;
select set_config('request.jwt.claim.sub', 'a0000000-0000-0000-0000-000000000002', false);
select zt.err('agents cannot buy the landlord plan', 'OWNERS_ONLY', $$select create_order('plan_landlord_m')$$);
select set_config('request.jwt.claim.sub', 'a0000000-0000-0000-0000-000000000001', false);
select zt.err('owners cannot buy agent plans', 'AGENTS_ONLY', $$select create_order('plan_pro_3m')$$);
create temp table lo as select create_order('plan_landlord_3m') as r;
select zt.ok('landlord 3 months costs K200', (select (r->>'amount')::numeric = 200 from lo));
select set_config('request.jwt.claim.sub', 'a0000000-0000-0000-0000-000000000004', false);
select admin_mark_order((select (r->>'id')::uuid from lo), 'paid', null);
reset role;
select zt.ok('landlord plan: 10 listings (+1 bought slot) for 3 months',
  (select allowed from listing_quota('a0000000-0000-0000-0000-000000000001')) = 11
  and (select plan = 'landlord' and plan_until > now() + interval '90 days' and boost_credits = 3
         from profiles where id = 'a0000000-0000-0000-0000-000000000001'));
drop table lo;
set role authenticated;
select set_config('request.jwt.claim.sub', 'a0000000-0000-0000-0000-000000000004', false);
select admin_set_setting('billing_enabled', 'false');
reset role;
drop table bo; drop table po; drop table so;

-- ---------- служебные функции закрыты ----------
select set_config('request.jwt.claim.sub', '', false);
set role anon;
select zt.err('guests cannot run cleanups', 'permission denied', $$select cleanup_feedback()$$);
select zt.err('guests cannot cancel orders in bulk', 'permission denied', $$select cleanup_orders()$$);
reset role;

-- ---------- Rooms & budget ----------
select set_config('request.jwt.claim.sub', '', false);
select zt.ok('rooms section is off by default', not (app_flags()->>'rooms')::boolean);
set role authenticated;
select set_config('request.jwt.claim.sub', 'a0000000-0000-0000-0000-000000000001', false);
select zt.err('people cannot post rooms while the section is off', 'ROOMS_OFF', $$
  insert into properties(owner_id,title,deal_type,property_type,price,location,status,area_id,room_info)
  values (auth.uid(),'Room','rent','room',900,'SRID=4326;POINT(28.31234 -15.41234)','active',(select min(id) from areas),
          '{"kind":"room","bathroom":"shared"}')$$);
reset role;
select set_config('request.jwt.claim.sub', '', false);   -- как в SQL Editor
insert into properties(id,owner_id,title,deal_type,property_type,price,location,status,area_id,room_info)
values ('b0000000-0000-0000-0000-0000000000f1','a0000000-0000-0000-0000-000000000002','Room in Kalingalinga','sale','room',900,
        'SRID=4326;POINT(28.31234 -15.41234)','active',(select min(id) from areas),
        '{"kind":"boys_quarters","bathroom":"own","kitchen":"shared","water":"borehole","power":"own_prepaid","wall":true}');
update properties set status = 'active' where id = 'b0000000-0000-0000-0000-0000000000f1';
select zt.ok('rooms are always for rent', (select deal_type from properties where id = 'b0000000-0000-0000-0000-0000000000f1') = 'rent');
select set_config('request.jwt.claim.sub', '', false);
set role anon;
select zt.ok('guests do not see rooms while off', not exists (select 1 from property_feed where property_type = 'room'));
reset role;
set role authenticated;
select set_config('request.jwt.claim.sub', 'a0000000-0000-0000-0000-000000000005', false);
select zt.ok('team sees rooms while off', exists (select 1 from property_feed where property_type = 'room'));
select set_config('request.jwt.claim.sub', 'a0000000-0000-0000-0000-000000000004', false);
select admin_set_setting('rooms_enabled', 'true');
select set_config('request.jwt.claim.sub', 'a0000000-0000-0000-0000-000000000001', false);
select zt.err('room details are checked', 'properties_room_info_ok', $$
  insert into properties(owner_id,title,deal_type,property_type,price,location,status,area_id,room_info)
  values (auth.uid(),'Room','rent','room',900,'SRID=4326;POINT(28.31234 -15.41234)','active',(select min(id) from areas),
          '{"kind":"palace"}')$$);
reset role;
select set_config('request.jwt.claim.sub', '', false);
set role anon;
select zt.ok('demo rooms are there for the preview', (select count(*) from property_feed where property_type = 'room' and is_demo) >= 4);
select zt.ok('compounds are added as areas', (select count(*) from areas where kind = 'compound') >= 8);
select zt.ok('guests see rooms when on, with approximate place',
  (select abs(lat * 100 - round(lat * 100)) < 1e-6 and abs(lng * 100 - round(lng * 100)) < 1e-6
     from property_feed where id = 'b0000000-0000-0000-0000-0000000000f1'));
select zt.ok('room details are shown', (select room_info->>'water' = 'borehole' from property_feed where id = 'b0000000-0000-0000-0000-0000000000f1'));
reset role;
set role authenticated;
select set_config('request.jwt.claim.sub', 'a0000000-0000-0000-0000-000000000002', false);
select zt.ok('owner sees the exact place',
  (select round(lat::numeric, 5) = -15.41234 from property_feed where id = 'b0000000-0000-0000-0000-0000000000f1'));
select set_config('request.jwt.claim.sub', 'a0000000-0000-0000-0000-000000000004', false);
select admin_set_setting('rooms_enabled', 'false');
reset role;
select zt.ok('rooms are not counted in area prices',
  (select listings_count from area_stats where id = (select min(id) from areas))
  = (select count(*) from properties p where p.area_id = (select min(id) from areas) and p.status = 'active'
       and p.property_type <> 'room' and (p.is_demo or coalesce(p.confirmed_at, p.created_at) > now() - interval '60 days')));
delete from properties where id = 'b0000000-0000-0000-0000-0000000000f1';

-- ---------- письма-уведомления ----------
update auth.users set email_confirmed_at = now() where email like '%@x.zm';
select set_config('request.jwt.claim.sub', '', false);
insert into conversations(id, property_id, buyer_id, seller_id, last_message_at)
values ('c0000000-0000-0000-0000-0000000000e1', null, 'a0000000-0000-0000-0000-000000000003',
        'a0000000-0000-0000-0000-000000000001', now());
insert into messages(conversation_id, sender_id, body, created_at) values
 ('c0000000-0000-0000-0000-0000000000e1', 'a0000000-0000-0000-0000-000000000003', 'Hi, is it still free?', now() - interval '3 minutes');
set role anon;
select zt.err('guests cannot read the email queue', 'permission denied', $$select email_due(10)$$);
reset role;
set role authenticated;
select set_config('request.jwt.claim.sub', 'a0000000-0000-0000-0000-000000000001', false);
select zt.err('people cannot read the email queue', 'permission denied', $$select email_due(10)$$);
select zt.err('people cannot mark emails', 'permission denied',
  $$select email_mark(auth.uid(), 'chat', gen_random_uuid(), true)$$);
select zt.ok('email alerts are on by default', my_email_alerts());
reset role;
select set_config('request.jwt.claim.sub', '', false);
set role service_role;
select zt.ok('fresh message waits 10 minutes before an email',
  not exists (select 1 from jsonb_array_elements(email_due(50)) e where e->>'kind' = 'chat'));
reset role;
update messages set created_at = now() - interval '15 minutes' where conversation_id = 'c0000000-0000-0000-0000-0000000000e1';
set role service_role;
select zt.ok('unread message older than 10 minutes → email to the seller',
  exists (select 1 from jsonb_array_elements(email_due(50)) e
           where e->>'kind' = 'chat' and e->>'email' = 'owner@x.zm' and e->'data'->>'from' = 'Buyer'
             and (e->'data'->>'count')::int = 1 and length(e->>'token') = 32));
select zt.ok('the writer does not get an email about own message',
  not exists (select 1 from jsonb_array_elements(email_due(50)) e where e->>'kind' = 'chat' and e->>'email' = 'buyer@x.zm'));
select email_mark('a0000000-0000-0000-0000-000000000001', 'chat', 'c0000000-0000-0000-0000-0000000000e1', true);
select zt.ok('only one email per unread chat',
  not exists (select 1 from jsonb_array_elements(email_due(50)) e where e->>'kind' = 'chat'));
select zt.ok('unsubscribe link needs the right token',
  not email_unsubscribe('a0000000-0000-0000-0000-000000000001', 'wrong'));
reset role;
-- прочитал, потом новое сообщение → снова письмо
insert into chat_reads(conversation_id, user_id, read_at)
values ('c0000000-0000-0000-0000-0000000000e1', 'a0000000-0000-0000-0000-000000000001', now() - interval '14 minutes');
insert into messages(conversation_id, sender_id, body, created_at) values
 ('c0000000-0000-0000-0000-0000000000e1', 'a0000000-0000-0000-0000-000000000003', 'Can I view on Saturday?', now() - interval '12 minutes');
update email_log set sent_at = now() - interval '20 minutes' where kind = 'chat';
set role service_role;
select zt.ok('after reading, a new message gets a new email',
  exists (select 1 from jsonb_array_elements(email_due(50)) e
           where e->>'kind' = 'chat' and e->'data'->>'snippet' = 'Can I view on Saturday?'));
reset role;
set role authenticated;
select set_config('request.jwt.claim.sub', 'a0000000-0000-0000-0000-000000000001', false);
select set_marketing('alerts', false);
select zt.ok('people can turn email alerts off', not my_email_alerts());
reset role;
select set_config('request.jwt.claim.sub', '', false);
set role service_role;
select zt.ok('no emails after turning off',
  not exists (select 1 from jsonb_array_elements(email_due(50)) e where e->>'email' = 'owner@x.zm'));
reset role;
update profiles set email_alerts_off_at = null where id = 'a0000000-0000-0000-0000-000000000001';
set role service_role;
select zt.ok('unsubscribe link works',
  email_unsubscribe('a0000000-0000-0000-0000-000000000001', _email_token('a0000000-0000-0000-0000-000000000001')));
reset role;
select zt.ok('unsubscribed → alerts off',
  (select email_alerts_off_at is not null from profiles where id = 'a0000000-0000-0000-0000-000000000001'));
update profiles set email_alerts_off_at = null where id = 'a0000000-0000-0000-0000-000000000001';
-- «Still available?»
insert into properties(id,owner_id,title,deal_type,property_type,price,location,status,area_id,created_at)
values ('b0000000-0000-0000-0000-0000000000e2','a0000000-0000-0000-0000-000000000002','Old house','rent','house',5000,
        'SRID=4326;POINT(28.31 -15.41)','active',(select min(id) from areas), now() - interval '40 days');
update properties set status = 'active' where id = 'b0000000-0000-0000-0000-0000000000e2';
update properties set confirmed_at = now() - interval '32 days', approved_at = now() - interval '40 days'
 where id = 'b0000000-0000-0000-0000-0000000000e2';
set role service_role;
select zt.ok('owner is asked by email to confirm an old listing',
  exists (select 1 from jsonb_array_elements(email_due(50)) e
           where e->>'kind' = 'confirm' and e->>'email' = 'agent@x.zm' and (e->'data'->>'hide_in')::int = 5));
reset role;
delete from properties where id = 'b0000000-0000-0000-0000-0000000000e2';
delete from conversations where id = 'c0000000-0000-0000-0000-0000000000e1';
set role authenticated;
select set_config('request.jwt.claim.sub', 'a0000000-0000-0000-0000-000000000004', false);
select zt.ok('owner sees email status', admin_email_status() ? 'sent_24h');
select set_config('request.jwt.claim.sub', 'a0000000-0000-0000-0000-000000000001', false);
select zt.ok('others do not see email status', admin_email_status() is null);
reset role;

-- ---------- бизнес-модель: дом на несколько квартир, жалоба «это агент», подозрительные, напоминание ----------
select set_config('request.jwt.claim.sub', '', false);
insert into properties(id,owner_id,title,deal_type,property_type,price,location,status,area_id,units_total,units_available)
values ('b0000000-0000-0000-0000-0000000000e3','a0000000-0000-0000-0000-000000000001','Block of flats','rent','apartment',4000,
        'SRID=4326;POINT(28.32 -15.42)','active',(select min(id) from areas),6,2);
update properties set status = 'active' where id = 'b0000000-0000-0000-0000-0000000000e3';
set role anon;
select zt.ok('feed shows free units of a building',
  (select units_total = 6 and units_available = 2 from property_feed where id = 'b0000000-0000-0000-0000-0000000000e3'));
reset role;
select zt.err('free units cannot exceed the total', 'properties_units_ok',
  $$update properties set units_available = 7 where id = 'b0000000-0000-0000-0000-0000000000e3'$$);
select zt.err('a building needs at least 2 units', 'properties_units_ok',
  $$update properties set units_total = 1, units_available = 1 where id = 'b0000000-0000-0000-0000-0000000000e3'$$);
set role authenticated;
select set_config('request.jwt.claim.sub', 'a0000000-0000-0000-0000-000000000003', false);
insert into listing_reports(property_id, reporter_id, reason)
values ('b0000000-0000-0000-0000-0000000000e3', auth.uid(), 'agent_as_owner');
select zt.ok('people can report "this is an agent"', true);
select zt.ok('only the team sees suspect owners', not exists (select 1 from admin_suspect_owners()));
select set_config('request.jwt.claim.sub', 'a0000000-0000-0000-0000-000000000004', false);
select zt.ok('team sees the reported "owner"',
  exists (select 1 from admin_suspect_owners() where user_id = 'a0000000-0000-0000-0000-000000000001' and agent_reports = 1));
reset role;
delete from properties where id = 'b0000000-0000-0000-0000-0000000000e3';
update profiles set plan_until = now() + interval '3 days' where id = 'a0000000-0000-0000-0000-000000000001';
set role service_role;
select zt.ok('reminder 5 days before the plan ends',
  exists (select 1 from jsonb_array_elements(email_due(50)) e
           where e->>'kind' = 'plan_ending' and e->>'email' = 'owner@x.zm' and e->'data'->>'plan' = 'landlord'
             and (e->'data'->>'days')::int = 3));
select email_mark('a0000000-0000-0000-0000-000000000001', 'plan_ending', 'a0000000-0000-0000-0000-000000000001', true);
select zt.ok('only one reminder',
  not exists (select 1 from jsonb_array_elements(email_due(50)) e where e->>'kind' = 'plan_ending'));
reset role;

-- ---------- агентства ----------
select set_config('request.jwt.claim.sub', '', false);
insert into auth.users(id, email, raw_user_meta_data) values
 ('a0000000-0000-0000-0000-0000000000a6', 'agency@x.zm',
  '{"full_name":"Boss Agent","role":"agency","agency_name":"Copper Homes","firm_licence_no":"ZIEA-F-9","terms_accepted":true}'),
 ('a0000000-0000-0000-0000-0000000000a7', 'staff@x.zm', '{"full_name":"Staff","role":"agent","terms_accepted":true}');
select zt.ok('signing up as Agency creates the agency',
  (select p.role = 'agent' and a.name = 'Copper Homes' and a.firm_licence_no = 'ZIEA-F-9' and p.agency_name = 'Copper Homes'
     from profiles p join agencies a on a.id = p.agency_id where p.id = 'a0000000-0000-0000-0000-0000000000a6'));
set role authenticated;
select set_config('request.jwt.claim.sub', 'a0000000-0000-0000-0000-0000000000a7', false);
select zt.err('nobody can put themselves into an agency', 'USE_INVITE',
  $$update profiles set agency_id = (select id from agencies limit 1) where id = auth.uid()$$);
select zt.err('only agency owners make invites', 'NOT_AGENCY_OWNER', $$select agency_invite()$$);
select set_config('request.jwt.claim.sub', 'a0000000-0000-0000-0000-0000000000a6', false);
create temp table inv as select agency_invite() as code;
grant select on inv to authenticated;
select zt.ok('agency has 30 shared free listings', (select allowed from listing_quota(auth.uid())) = 30);
select set_config('request.jwt.claim.sub', 'a0000000-0000-0000-0000-000000000001', false);
select zt.err('owners cannot join an agency', 'AGENTS_ONLY', $$select join_agency((select code from inv))$$);
select set_config('request.jwt.claim.sub', 'a0000000-0000-0000-0000-0000000000a7', false);
select zt.ok('invite shows the agency name before joining',
  (select agency_invite_info((select code from inv))->>'name') = 'Copper Homes');
select join_agency((select code from inv));
select zt.ok('agent joined by invite', (select agency_name = 'Copper Homes' from profiles where id = auth.uid()));
select zt.err('an invite works once', 'ALREADY_IN_AGENCY', $$select join_agency((select code from inv))$$);
reset role;
select set_config('request.jwt.claim.sub', '', false);
insert into properties(owner_id,title,deal_type,property_type,price,location,status,area_id) values
 ('a0000000-0000-0000-0000-0000000000a7','Staff house','rent','house',5000,'SRID=4326;POINT(28.31 -15.41)','active',(select min(id) from areas)),
 ('a0000000-0000-0000-0000-0000000000a6','Boss house','rent','house',6000,'SRID=4326;POINT(28.32 -15.41)','active',(select min(id) from areas));
update properties set status = 'active' where owner_id in ('a0000000-0000-0000-0000-0000000000a6', 'a0000000-0000-0000-0000-0000000000a7');
select zt.ok('the limit is shared: both agents see 2 of 30 used',
  (select used = 2 and allowed = 30 from listing_quota('a0000000-0000-0000-0000-0000000000a7'))
  and (select used = 2 from listing_quota('a0000000-0000-0000-0000-0000000000a6')));
update app_settings set value = 'true' where key = 'billing_enabled';
set role authenticated;
select set_config('request.jwt.claim.sub', 'a0000000-0000-0000-0000-0000000000a7', false);
select zt.err('staff cannot buy their own plan', 'ASK_AGENCY_OWNER', $$select create_order('plan_pro_m')$$);
reset role;
update app_settings set value = 'false' where key = 'billing_enabled';
set role authenticated;
select set_config('request.jwt.claim.sub', 'a0000000-0000-0000-0000-000000000004', false);
select admin_verify_agency((select agency_id from profiles where id = 'a0000000-0000-0000-0000-0000000000a6'), true);
select zt.ok('verified firm: 50 shared listings', (select allowed from listing_quota('a0000000-0000-0000-0000-0000000000a7')) = 50);
select zt.ok('team sees agencies to check', exists (select 1 from admin_agencies() where name = 'Copper Homes' and members = 2));
select set_config('request.jwt.claim.sub', '', false);
reset role;
set role anon;
select zt.ok('agency page is public: 2 agents, 2 listings, firm number hidden',
  (select (j->>'active_listings')::int = 2 and jsonb_array_length(j->'members') = 2 and j->>'firm_licence_no' is null
            and (j->>'verified')::boolean
     from (select agency_page(agency_id) as j from profiles where id = 'a0000000-0000-0000-0000-0000000000a6') x));
reset role;
set role authenticated;
select set_config('request.jwt.claim.sub', 'a0000000-0000-0000-0000-0000000000a6', false);
select update_agency('Copper Homes Ltd', 'ZIEA-F-10', null, 'Lusaka homes since 2015');
select zt.ok('renamed agency: staff show the new name; new firm number needs a new check',
  (select agency_name = 'Copper Homes Ltd' from profiles where id = 'a0000000-0000-0000-0000-0000000000a7')
  and (select allowed from listing_quota(auth.uid())) = 30);
select zt.err('agency owner cannot leave', 'OWNER_CANNOT_LEAVE', $$select leave_agency()$$);
select agency_remove_member('a0000000-0000-0000-0000-0000000000a7');
select zt.ok('removed agent: own limit again, no agency name',
  (select agency_id is null and agency_name is null from profiles where id = 'a0000000-0000-0000-0000-0000000000a7')
  and (select used = 1 and allowed = 15 from listing_quota('a0000000-0000-0000-0000-0000000000a7')));
reset role;
drop table inv;
delete from properties where owner_id in ('a0000000-0000-0000-0000-0000000000a6', 'a0000000-0000-0000-0000-0000000000a7');

-- ---------- смена типа аккаунта ----------
select set_config('request.jwt.claim.sub', '', false);
insert into auth.users(id, email, raw_user_meta_data) values
 ('a0000000-0000-0000-0000-0000000000b1', 'switch@x.zm', '{"full_name":"Switcher","role":"owner","terms_accepted":true}');
insert into properties(owner_id,title,deal_type,property_type,price,location,status,area_id) values
 ('a0000000-0000-0000-0000-0000000000b1','My flat','rent','apartment',3000,'SRID=4326;POINT(28.31 -15.41)','active',(select min(id) from areas));
set role authenticated;
select set_config('request.jwt.claim.sub', 'a0000000-0000-0000-0000-0000000000b1', false);
select become_agent('ZIEA-777');
select zt.ok('owner becomes an agent by themselves; listings now say Agent',
  (select role = 'agent' and agent_licence_no = 'ZIEA-777' from profiles where id = auth.uid())
  and not exists (select 1 from properties where owner_id = auth.uid() and listed_by <> 'agent'));
select zt.err('people cannot change their type back', 'FORBIDDEN', $$select admin_set_account_type('switch@x.zm', 'owner')$$);
select set_config('request.jwt.claim.sub', 'a0000000-0000-0000-0000-000000000004', false);
select zt.ok('team can switch an agent back to owner', admin_set_account_type('switch@x.zm', 'owner') = 'agent → owner');
select zt.ok('listings follow the account type',
  not exists (select 1 from properties where owner_id = 'a0000000-0000-0000-0000-0000000000b1' and listed_by <> 'owner'));
select zt.err('team accounts are not switched here', 'TEAM_ACCOUNT', $$select admin_set_account_type('boss@x.zm', 'agent')$$);
reset role;
delete from properties where owner_id = 'a0000000-0000-0000-0000-0000000000b1';

select zt.ok('ALL CHECKS PASSED', true);
