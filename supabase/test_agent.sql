-- =====================================================================
--  Zumi — ТЕСТОВЫЙ агент с готовыми объявлениями (для проверки сайта)
--  Агент: Mwila Banda · Lusaka Home Finders, каталог zumihome.com/mwila-banda
--  6 объявлений с фото, видны в поиске, на странице агента и в каталоге.
--  Войти под ним нельзя (пароля нет) — только смотреть.
--  ВАЖНО: перед запуском сайта удалить — блок «УДАЛИТЬ» внизу.
--  Можно запускать повторно (сначала удаляет старую версию).
-- =====================================================================

-- на всякий случай удаляем прошлую версию
delete from auth.users where id = '7e570000-0000-4000-8000-000000000001';

-- 1. аккаунт (профиль создастся сам)
insert into auth.users (id, instance_id, aud, role, email, email_confirmed_at, raw_user_meta_data, raw_app_meta_data, created_at, updated_at)
values ('7e570000-0000-4000-8000-000000000001', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated',
        'test-agent@zumihome.com', now(),
        '{"full_name":"Mwila Banda","role":"agent","terms_accepted":true}'::jsonb,
        '{"provider":"email","providers":["email"]}'::jsonb, now() - interval '20 days', now());

-- 2. профиль агента: агентство, подтверждённый номер, лицензия, каталог
update public.profiles set
  role = 'agent',
  full_name = 'Mwila Banda',
  agency_name = 'Lusaka Home Finders',
  phone = '+260 970 000 101',
  whatsapp = '+260 970 000 101',
  phone_verified_at = now(),
  agent_licence_no = 'ZIEA-TEST-0101',
  licence_verified_at = now(),
  bio = 'Helping families and expats find homes in Lusaka for 8 years. Viewings 7 days a week, I answer on WhatsApp within the hour.',
  slug = 'mwila-banda',
  catalog_areas = 'Ibex Hill, Woodlands, Kabulonga, Roma',
  catalog_public_contact = true,
  created_at = now() - interval '20 days'
where id = '7e570000-0000-4000-8000-000000000001';

-- 3. объявления
insert into public.properties (id, owner_id, title, description, deal_type, property_type, price, currency, rent_period,
  bedrooms, bathrooms, area_sqm, amenities, area_id, address, location, listed_by, contact_name, contact_phone,
  kids_allowed, pets_allowed, advance_months, status)
select v.id::uuid, '7e570000-0000-4000-8000-000000000001', v.title, v.descr, v.deal, v.ptype, v.price, 'ZMW',
       case when v.deal = 'rent' then 'month' end,
       v.beds, v.baths, v.sqm, v.amen, a.id, v.addr,
       ('SRID=4326;POINT(' || v.lng || ' ' || v.lat || ')')::geography, 'agent', 'Mwila Banda', '+260 970 000 101',
       true, v.pets, v.adv, 'active'
  from (values
    ('7e570000-0000-4000-8000-0000000000a1', 'Family house with garden in Ibex Hill',
     'Bright 3-bedroom house on a quiet street. Big garden, staff quarters, wall and electric gate. Solar backup and a borehole, so no problems with load-shedding or water cuts.',
     'rent', 'house', 18000, 3, 2, 210, array['solar','borehole','water_tank','parking','garden'], 'Ibex Hill', 'Off Nyerere Rd', -15.437, 28.343, true, 3),
    ('7e570000-0000-4000-8000-0000000000a2', 'Modern 2-bedroom flat in Woodlands',
     'Newly built flat on the 1st floor. Open kitchen, fitted wardrobes, secure parking. Inverter backup for lights and Wi-Fi.',
     'rent', 'apartment', 9500, 2, 1, 95, array['inverter','prepaid_meter','parking','internet'], 'Woodlands', 'Chindo Rd', -15.430, 28.318, false, 2),
    ('7e570000-0000-4000-8000-0000000000a3', '4-bedroom house with pool in Kabulonga',
     'Spacious family home with a pool, double garage and a big veranda. Generator and borehole. Close to schools and Woodlands mall.',
     'sale', 'house', 3200000, 4, 3, 340, array['generator','borehole','pool','garage','garden','ac'], 'Kabulonga', 'Kabulonga Rd', -15.414, 28.335, true, null),
    ('7e570000-0000-4000-8000-0000000000a4', 'Cosy cottage in Roma',
     'Self-contained 1-bedroom cottage in a shared yard. Own ZESCO prepaid meter and water 24/7. Good for a young professional.',
     'rent', 'house', 5500, 1, 1, 55, array['prepaid_meter','water_24h','parking'], 'Roma', 'Roma Park', -15.385, 28.318, false, 1),
    ('7e570000-0000-4000-8000-0000000000a5', 'Furnished 3-bedroom apartment in Ibex Hill',
     'Fully furnished apartment in a gated complex with a pool and 24h security. Solar for the whole unit. Ready to move in.',
     'rent', 'apartment', 22000, 3, 2, 150, array['solar','water_tank','furnished','pool','parking','ac','fridge','washing_machine'], 'Ibex Hill', 'Ibex Main Rd', -15.441, 28.350, false, 3),
    ('7e570000-0000-4000-8000-0000000000a6', 'Plot for sale in Woodlands Extension',
     'Serviced residential plot, title deeds ready. Water and power on the road. Quiet area near the new mall.',
     'sale', 'land', 650000, null, null, 900, array['council_water'], 'Woodlands', 'Woodlands Ext', -15.445, 28.326, null, null)
  ) v(id, title, descr, deal, ptype, price, beds, baths, sqm, amen, area, addr, lat, lng, pets, adv)
  left join public.areas a on a.name = v.area and a.city = 'Lusaka';

-- новые аккаунты уходят на проверку — тестового агента сразу публикуем
update public.properties set status = 'active', approved_at = now(), confirmed_at = now(), moderation_note = null
 where owner_id = '7e570000-0000-4000-8000-000000000001';

-- 4. фото (из демо-картинок сайта)
insert into public.property_images (property_id, url, sort_order) values
  ('7e570000-0000-4000-8000-0000000000a1', 'asset:p1.jpg', 0), ('7e570000-0000-4000-8000-0000000000a1', 'asset:p6.jpg', 1),
  ('7e570000-0000-4000-8000-0000000000a1', 'asset:area_ibex_hill.jpg', 2),
  ('7e570000-0000-4000-8000-0000000000a2', 'asset:p2.jpg', 0), ('7e570000-0000-4000-8000-0000000000a2', 'asset:p7.jpg', 1),
  ('7e570000-0000-4000-8000-0000000000a3', 'asset:p3.jpg', 0), ('7e570000-0000-4000-8000-0000000000a3', 'asset:p5.jpg', 1),
  ('7e570000-0000-4000-8000-0000000000a3', 'asset:area_kabulonga.jpg', 2),
  ('7e570000-0000-4000-8000-0000000000a4', 'asset:p4.jpg', 0), ('7e570000-0000-4000-8000-0000000000a4', 'asset:area_roma.jpg', 1),
  ('7e570000-0000-4000-8000-0000000000a5', 'asset:p5.jpg', 0), ('7e570000-0000-4000-8000-0000000000a5', 'asset:p2.jpg', 1),
  ('7e570000-0000-4000-8000-0000000000a6', 'asset:area_woodlands.jpg', 0);

-- проверка: 6 объявлений видны, каталог работает
select
  (select count(*) from public.property_feed where owner_id = '7e570000-0000-4000-8000-000000000001' and status = 'active' and is_fresh) as listings_visible,
  (select public.catalog_page('mwila-banda')->>'name') as catalog_name;

-- =====================================================================
--  УДАЛИТЬ тестового агента (перед запуском): выделить строку ниже и Run
--  delete from auth.users where id = '7e570000-0000-4000-8000-000000000001';
-- =====================================================================
