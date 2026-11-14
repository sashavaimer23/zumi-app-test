-- =====================================================================
--  Zumi — ещё 8 демо-объявлений тестовому агенту Mwila Banda (всего станет 14)
--  Запускать ПОСЛЕ test_agent.sql (можно и после переноса на zumi.team.zm+agent@gmail.com). Можно повторно.
--  Удаляются вместе с агентом (строка «УДАЛИТЬ» в test_agent.sql).
-- =====================================================================

delete from public.properties where id in (
  '7e570000-0000-4000-8000-0000000000b1','7e570000-0000-4000-8000-0000000000b2','7e570000-0000-4000-8000-0000000000b3',
  '7e570000-0000-4000-8000-0000000000b4','7e570000-0000-4000-8000-0000000000b5','7e570000-0000-4000-8000-0000000000b6',
  '7e570000-0000-4000-8000-0000000000b7','7e570000-0000-4000-8000-0000000000b8');

insert into public.properties (id, owner_id, title, description, deal_type, property_type, price, currency, rent_period,
  bedrooms, bathrooms, area_sqm, amenities, area_id, address, location, listed_by, contact_name, contact_phone,
  kids_allowed, pets_allowed, advance_months, status)
select v.id::uuid,
       coalesce((select id from auth.users where lower(email) = 'zumi.team.zm+agent@gmail.com'), '7e570000-0000-4000-8000-000000000001'),
       v.title, v.descr, v.deal, v.ptype, v.price, 'ZMW',
       case when v.deal = 'rent' then 'month' end,
       v.beds, v.baths, v.sqm, v.amen, a.id, v.addr,
       ('SRID=4326;POINT(' || v.lng || ' ' || v.lat || ')')::geography, 'agent', 'Mwila Banda', '+260 970 000 101',
       true, v.pets, v.adv, 'active'
  from (values
    ('7e570000-0000-4000-8000-0000000000b1', 'Townhouse in a gated estate, Leopards Hill',
     '3-bedroom townhouse in a quiet gated estate with 24h guards. Solar geyser, borehole and a small private garden.',
     'rent', 'house', 15000, 3, 2, 160, array['solar','borehole','parking','garden'], 'Leopards Hill', 'Leopards Hill Rd', -15.458, 28.392, true, 3),
    ('7e570000-0000-4000-8000-0000000000b2', 'Studio flat near UNZA, Chelston',
     'Compact studio for one person. Own prepaid meter, water 24/7, shared parking. 5 minutes to the Great East Road.',
     'rent', 'apartment', 3500, 1, 1, 32, array['prepaid_meter','water_24h','parking'], 'Chelston', 'Chelston Green', -15.371, 28.368, false, 1),
    ('7e570000-0000-4000-8000-0000000000b3', 'Executive 5-bedroom house in Leopards Hill',
     'Large family home on 1 acre: 5 en-suite bedrooms, cinema room, pool and a big entertainment area. Full solar system with batteries and a borehole.',
     'sale', 'house', 6500000, 5, 5, 520, array['solar','inverter','borehole','water_tank','pool','garage','garden','ac'], 'Leopards Hill', 'Leopards Hill', -15.462, 28.395, true, null),
    ('7e570000-0000-4000-8000-0000000000b4', 'Office space on Addis Ababa Drive, Rhodes Park',
     'Ground-floor office, 120 m², open plan with 2 private rooms, kitchenette and 4 parking bays. Generator backup.',
     'rent', 'commercial', 25000, null, 2, 120, array['generator','parking','internet','ac'], 'Rhodes Park', 'Addis Ababa Dr', -15.404, 28.306, null, 3),
    ('7e570000-0000-4000-8000-0000000000b5', '2-bedroom flat with balcony in Longacres',
     'Second-floor flat with a sunny balcony, close to embassies and shops. Inverter backup, water tank, secure parking.',
     'rent', 'apartment', 11000, 2, 2, 105, array['inverter','water_tank','parking'], 'Longacres', 'Longacres', -15.413, 28.313, false, 2),
    ('7e570000-0000-4000-8000-0000000000b6', 'Starter house in Makeni',
     'Neat 2-bedroom house with a big yard — great first home. Borehole and council water. Title deeds ready.',
     'sale', 'house', 850000, 2, 1, 90, array['borehole','council_water','parking'], 'Makeni', 'Makeni Villa', -15.462, 28.252, true, null),
    ('7e570000-0000-4000-8000-0000000000b7', 'Garden flat in Avondale',
     'Ground-floor 2-bedroom flat with its own small garden. Own ZESCO prepaid meter, solar lights, quiet street.',
     'rent', 'apartment', 7500, 2, 1, 80, array['prepaid_meter','solar','garden','parking'], 'Avondale', 'Avondale', -15.376, 28.356, true, 2),
    ('7e570000-0000-4000-8000-0000000000b8', 'Corner plot in Meanwood Ibex',
     'Residential corner plot, 1,200 m², in a fast-growing area. Water and power on the road, title ready.',
     'sale', 'land', 420000, null, null, 1200, array['council_water'], 'Meanwood', 'Meanwood Ibex', -15.356, 28.331, null, null)
  ) v(id, title, descr, deal, ptype, price, beds, baths, sqm, amen, area, addr, lat, lng, pets, adv)
  left join public.areas a on a.name = v.area and a.city = 'Lusaka';

update public.properties set status = 'active', approved_at = now(), confirmed_at = now(), moderation_note = null
 where id::text like '7e570000-0000-4000-8000-0000000000b%';

insert into public.property_images (property_id, url, sort_order) values
  ('7e570000-0000-4000-8000-0000000000b1', 'asset:p6.jpg', 0), ('7e570000-0000-4000-8000-0000000000b1', 'asset:area_leopards_hill.jpg', 1),
  ('7e570000-0000-4000-8000-0000000000b2', 'asset:p7.jpg', 0), ('7e570000-0000-4000-8000-0000000000b2', 'asset:area_chelston.jpg', 1),
  ('7e570000-0000-4000-8000-0000000000b3', 'asset:hero.jpg', 0), ('7e570000-0000-4000-8000-0000000000b3', 'asset:p3.jpg', 1),
  ('7e570000-0000-4000-8000-0000000000b3', 'asset:p1.jpg', 2),
  ('7e570000-0000-4000-8000-0000000000b4', 'asset:area_rhodes_park.jpg', 0), ('7e570000-0000-4000-8000-0000000000b4', 'asset:n1.jpg', 1),
  ('7e570000-0000-4000-8000-0000000000b5', 'asset:area_longacres.jpg', 0), ('7e570000-0000-4000-8000-0000000000b5', 'asset:p2.jpg', 1),
  ('7e570000-0000-4000-8000-0000000000b6', 'asset:area_makeni.jpg', 0), ('7e570000-0000-4000-8000-0000000000b6', 'asset:p4.jpg', 1),
  ('7e570000-0000-4000-8000-0000000000b7', 'asset:area_avondale.jpg', 0), ('7e570000-0000-4000-8000-0000000000b7', 'asset:n2.jpg', 1),
  ('7e570000-0000-4000-8000-0000000000b8', 'asset:area_meanwood.jpg', 0);

-- проверка: должно быть 14
select count(*) as listings_visible from public.property_feed
 where owner_id = coalesce((select id from auth.users where lower(email) = 'zumi.team.zm+agent@gmail.com'), '7e570000-0000-4000-8000-000000000001')
   and status = 'active' and is_fresh;
