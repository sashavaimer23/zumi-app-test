-- =====================================================================
--  Zumi — 003: демо-объявления (is_demo = true). Запускать после 002.
--  Удалить все демо одной командой:  delete from public.properties where is_demo;
--  Фото демо лежат в приложении (asset:...). Реальные фото — в Storage.
-- =====================================================================

update public.areas set tagline = 'Leafy streets & top schools', image_url = 'asset:area_kabulonga.jpg' where city = 'Lusaka' and name = 'Kabulonga';
update public.areas set tagline = 'Central, calm and green', image_url = 'asset:area_woodlands.jpg' where city = 'Lusaka' and name = 'Woodlands';
update public.areas set tagline = 'Vibrant community & city access', image_url = 'asset:area_roma.jpg' where city = 'Lusaka' and name = 'Roma';
update public.areas set tagline = 'Modern homes & green spaces', image_url = 'asset:area_ibex_hill.jpg' where city = 'Lusaka' and name = 'Ibex Hill';
update public.areas set tagline = 'Walk to everything', image_url = 'asset:area_rhodes_park.jpg' where city = 'Lusaka' and name = 'Rhodes Park';
update public.areas set tagline = 'Close to UNZA & malls', image_url = 'asset:area_olympia.jpg' where city = 'Lusaka' and name = 'Olympia';
update public.areas set tagline = 'Shops, cafes and nightlife', image_url = 'asset:area_northmead.jpg' where city = 'Lusaka' and name = 'Northmead';
update public.areas set tagline = 'Business district living', image_url = 'asset:area_longacres.jpg' where city = 'Lusaka' and name = 'Longacres';
update public.areas set tagline = 'Affordable family homes', image_url = 'asset:area_chelston.jpg' where city = 'Lusaka' and name = 'Chelston';
update public.areas set tagline = 'Quiet residential area', image_url = 'asset:area_avondale.jpg' where city = 'Lusaka' and name = 'Avondale';
update public.areas set tagline = 'Peaceful living and family-friendly', image_url = 'asset:area_meanwood.jpg' where city = 'Lusaka' and name = 'Meanwood';
update public.areas set tagline = 'Growing suburb, great value', image_url = 'asset:area_chalala.jpg' where city = 'Lusaka' and name = 'Chalala';
update public.areas set tagline = 'Big plots and views', image_url = 'asset:area_leopards_hill.jpg' where city = 'Lusaka' and name = 'Leopards Hill';
update public.areas set tagline = 'New developments', image_url = 'asset:area_new_kasama.jpg' where city = 'Lusaka' and name = 'New Kasama';
update public.areas set tagline = 'Space to build', image_url = 'asset:area_makeni.jpg' where city = 'Lusaka' and name = 'Makeni';

insert into public.properties (id, title, description, deal_type, property_type, price, currency, rent_period, bedrooms, bathrooms, area_sqm, plot_sqm, amenities, area_id, address, location, status, promoted_until, listed_by, contact_name, contact_phone, renovation, kids_allowed, pets_allowed, lease_term, views_count, created_at, is_demo) values
  ('00000000-0000-0000-0000-00000000d000', 'Cosy family house', 'Bright 3-bedroom family house in a quiet gated street of Ibex Hill. Fitted kitchen, borehole, solar backup and a private garden.', 'rent', 'house', 45000, 'ZMW', 'month', 3, 2, 70.8, null, array['parking','garden','ac']::text[], (select id from public.areas where city='Lusaka' and name='Ibex Hill'), 'The 3rd street', st_point(28.367181,-15.445586)::geography, 'active', now() + interval '30 days', 'agent', 'Zumi Realty', '+260 97 000 0000', 'designer', true, false, 'year', 353, '2026-10-20T10:00:00Z', true),
  ('00000000-0000-0000-0000-00000000d001', 'Cosy apartment', 'Modern 2-bedroom apartment with open-plan living area, fibre internet and secure parking.', 'rent', 'apartment', 40000, 'ZMW', 'month', 2, 1, 65.8, null, array['parking','furnished','ac','internet']::text[], (select id from public.areas where city='Lusaka' and name='Ibex Hill'), 'The 2nd street', st_point(28.362773,-15.43486)::geography, 'active', now() + interval '30 days', 'agent', 'Zumi Realty', '+260 97 000 0001', 'designer', true, true, 'year', 68, '2026-10-19T10:00:00Z', true),
  ('00000000-0000-0000-0000-00000000d002', 'Commercial for rent', 'Warehouse / showroom space on the main road with loading area and parking.', 'rent', 'commercial', 38000, 'ZMW', 'month', null, 1, 65.8, null, array['parking']::text[], (select id from public.areas where city='Lusaka' and name='Meanwood'), 'The Meanwood road', st_point(28.327851,-15.362072)::geography, 'active', null, 'agent', 'Zumi Realty', '+260 97 000 0002', 'cosmetic', null, null, 'year', 279, '2026-10-18T10:00:00Z', true),
  ('00000000-0000-0000-0000-00000000d003', 'Modern 3 bedroom house in Ibex Hill', 'Newly built 3-bedroom house with en-suite master bedroom and covered veranda.', 'rent', 'house', 45000, 'ZMW', 'month', 3, 2, 68, null, array['parking','garden']::text[], (select id from public.areas where city='Lusaka' and name='Ibex Hill'), 'Bishops road', st_point(28.365435,-15.446625)::geography, 'active', null, 'owner', 'Private owner', '+260 97 000 0003', 'designer', true, true, 'year', 234, '2026-10-17T10:00:00Z', true),
  ('00000000-0000-0000-0000-00000000d004', 'Contemporary townhouse', 'Double-storey townhouse with balcony, double garage and landscaped garden.', 'sale', 'house', 2850000, 'ZMW', null, 4, 3, 210, null, array['parking','garden','garage','ac']::text[], (select id from public.areas where city='Lusaka' and name='Roma'), 'Kasama road', st_point(28.303118,-15.376549)::geography, 'active', now() + interval '30 days', 'agent', 'Zumi Realty', '+260 97 000 0004', 'designer', null, null, null, 237, '2026-10-16T10:00:00Z', true),
  ('00000000-0000-0000-0000-00000000d005', 'Family home with big garden', 'Spacious 5-bedroom home on a large plot, swimming pool and staff quarters.', 'sale', 'house', 4200000, 'ZMW', null, 5, 4, 320, 1800, array['parking','garden','pool','garage']::text[], (select id from public.areas where city='Lusaka' and name='Kabulonga'), 'Ngwee road', st_point(28.327946,-15.423953)::geography, 'active', null, 'agent', 'Zumi Realty', '+260 97 000 0005', 'designer', null, null, null, 134, '2026-10-15T10:00:00Z', true),
  ('00000000-0000-0000-0000-00000000d006', 'Furnished apartment, daily', 'Fully furnished 1-bedroom apartment for short stays. Wi-Fi and Netflix included.', 'rent', 'apartment', 1500, 'ZMW', 'day', 1, 1, 48, null, array['furnished','ac','internet','tv','fridge','washing_machine']::text[], (select id from public.areas where city='Lusaka' and name='Rhodes Park'), 'Lagos road', st_point(28.30709,-15.403672)::geography, 'active', null, 'owner', 'Private owner', '+260 97 000 0006', 'designer', true, false, 'months', 51, '2026-10-14T10:00:00Z', true),
  ('00000000-0000-0000-0000-00000000d007', '3 bedroom house near Arcades', 'Comfortable family house close to Arcades and schools.', 'rent', 'house', 18000, 'ZMW', 'month', 3, 2, 120, null, array['parking','garden']::text[], (select id from public.areas where city='Lusaka' and name='Woodlands'), 'Kabelenga road', st_point(28.321234,-15.436653)::geography, 'active', null, 'owner', 'Private owner', '+260 97 000 0007', 'cosmetic', true, true, 'year', 133, '2026-10-13T10:00:00Z', true),
  ('00000000-0000-0000-0000-00000000d008', 'Residential plot, 2000 m²', 'Title-deeded residential plot with water and electricity nearby.', 'sale', 'land', 650000, 'ZMW', null, null, null, null, 2000, '{}'::text[], (select id from public.areas where city='Lusaka' and name='Leopards Hill'), 'Leopards Hill road', st_point(28.382745,-15.454265)::geography, 'active', null, 'agent', 'Zumi Realty', '+260 97 000 0008', null, null, null, null, 168, '2026-10-12T10:00:00Z', true),
  ('00000000-0000-0000-0000-00000000d009', '2 bedroom flat', 'Affordable 2-bedroom flat in a secure complex.', 'rent', 'apartment', 9500, 'ZMW', 'month', 2, 1, 70, null, array['parking']::text[], (select id from public.areas where city='Lusaka' and name='Chalala'), 'Chalala main road', st_point(28.328706,-15.469349)::geography, 'active', null, 'owner', 'Private owner', '+260 97 000 0009', 'none', true, true, 'year', 312, '2026-10-11T10:00:00Z', true),
  ('00000000-0000-0000-0000-00000000d00a', '4 bedroom house', 'Solid 4-bedroom house with borehole and solar geyser.', 'sale', 'house', 1950000, 'ZMW', null, 4, 3, 190, 900, array['parking','garden','garage']::text[], (select id from public.areas where city='Lusaka' and name='Meanwood'), 'Mutumbi road', st_point(28.326936,-15.349942)::geography, 'active', null, 'agent', 'Zumi Realty', '+260 97 000 0010', 'cosmetic', null, null, null, 112, '2026-10-10T10:00:00Z', true),
  ('00000000-0000-0000-0000-00000000d00b', 'Roma Park apartment', '3-bedroom apartment in Roma Park, gym and 24/7 security.', 'rent', 'apartment', 22000, 'ZMW', 'month', 3, 2, 110, null, array['parking','ac','internet','dishwasher']::text[], (select id from public.areas where city='Lusaka' and name='Roma'), 'Roma Park', st_point(28.303649,-15.368861)::geography, 'active', null, 'agent', 'Zumi Realty', '+260 97 000 0011', 'designer', true, false, 'year', 116, '2026-10-09T10:00:00Z', true),
  ('00000000-0000-0000-0000-00000000d00c', 'Office space', 'Open-plan office with meeting room, close to UNZA.', 'rent', 'commercial', 30000, 'ZMW', 'month', null, 2, 140, null, array['parking','internet','ac']::text[], (select id from public.areas where city='Lusaka' and name='Olympia'), 'Great East road', st_point(28.307958,-15.384236)::geography, 'active', null, 'agent', 'Zumi Realty', '+260 97 000 0012', 'cosmetic', null, null, 'year', 52, '2026-10-08T10:00:00Z', true),
  ('00000000-0000-0000-0000-00000000d00d', 'Plot in Makeni', 'Residential plot in a fast-growing area.', 'sale', 'land', 250000, 'ZMW', null, null, null, null, 1200, '{}'::text[], (select id from public.areas where city='Lusaka' and name='Makeni'), 'Makeni', st_point(28.25103,-15.458096)::geography, 'active', null, 'owner', 'Private owner', '+260 97 000 0013', null, null, null, null, 274, '2026-10-07T10:00:00Z', true),
  ('00000000-0000-0000-0000-00000000d00e', 'Starter house in New Kasama', 'Neat 3-bedroom house, newly painted.', 'rent', 'house', 12000, 'ZMW', 'month', 3, 1, 95, null, array['parking']::text[], (select id from public.areas where city='Lusaka' and name='New Kasama'), 'New Kasama', st_point(28.402886,-15.431159)::geography, 'active', null, 'owner', 'Private owner', '+260 97 000 0014', 'cosmetic', true, true, 'year', 180, '2026-10-06T10:00:00Z', true),
  ('00000000-0000-0000-0000-00000000d00f', 'Chelston bungalow', '2-bedroom bungalow, ideal first home or rental investment.', 'sale', 'house', 900000, 'ZMW', null, 2, 1, 85, 600, array['garden']::text[], (select id from public.areas where city='Lusaka' and name='Chelston'), 'Chelston', st_point(28.36945,-15.363225)::geography, 'active', null, 'owner', 'Private owner', '+260 97 000 0015', 'none', null, null, null, 205, '2026-10-05T10:00:00Z', true),
  ('00000000-0000-0000-0000-00000000d010', 'Luxury villa with pool', 'Executive 5-bedroom villa with pool, fully furnished.', 'rent', 'house', 75000, 'ZMW', 'month', 5, 5, 400, 2500, array['parking','garden','pool','garage','furnished','ac','internet']::text[], (select id from public.areas where city='Lusaka' and name='Kabulonga'), 'Kabulonga road', st_point(28.331796,-15.42029)::geography, 'active', now() + interval '30 days', 'agent', 'Zumi Realty', '+260 97 000 0016', 'designer', true, true, 'year', 377, '2026-10-04T10:00:00Z', true),
  ('00000000-0000-0000-0000-00000000d011', 'Northmead 1 bedroom', 'Compact 1-bedroom flat near shops and cafes.', 'rent', 'apartment', 7000, 'ZMW', 'month', 1, 1, 45, null, array['internet']::text[], (select id from public.areas where city='Lusaka' and name='Northmead'), 'Northmead', st_point(28.304477,-15.40669)::geography, 'active', null, 'owner', 'Private owner', '+260 97 000 0017', 'cosmetic', false, false, 'months', 173, '2026-10-03T10:00:00Z', true)
on conflict (id) do nothing;

insert into public.property_images (property_id, url, sort_order) values
  ('00000000-0000-0000-0000-00000000d000', 'asset:p1.jpg', 0),
  ('00000000-0000-0000-0000-00000000d000', 'asset:p6.jpg', 1),
  ('00000000-0000-0000-0000-00000000d001', 'asset:p2.jpg', 0),
  ('00000000-0000-0000-0000-00000000d001', 'asset:p7.jpg', 1),
  ('00000000-0000-0000-0000-00000000d002', 'asset:p3.jpg', 0),
  ('00000000-0000-0000-0000-00000000d003', 'asset:p6.jpg', 0),
  ('00000000-0000-0000-0000-00000000d003', 'asset:p1.jpg', 1),
  ('00000000-0000-0000-0000-00000000d004', 'asset:p4.jpg', 0),
  ('00000000-0000-0000-0000-00000000d004', 'asset:n2.jpg', 1),
  ('00000000-0000-0000-0000-00000000d005', 'asset:p5.jpg', 0),
  ('00000000-0000-0000-0000-00000000d005', 'asset:p4.jpg', 1),
  ('00000000-0000-0000-0000-00000000d006', 'asset:p7.jpg', 0),
  ('00000000-0000-0000-0000-00000000d007', 'asset:n1.jpg', 0),
  ('00000000-0000-0000-0000-00000000d007', 'asset:p1.jpg', 1),
  ('00000000-0000-0000-0000-00000000d008', 'asset:p5.jpg', 0),
  ('00000000-0000-0000-0000-00000000d009', 'asset:p6.jpg', 0),
  ('00000000-0000-0000-0000-00000000d00a', 'asset:n3.jpg', 0),
  ('00000000-0000-0000-0000-00000000d00a', 'asset:p4.jpg', 1),
  ('00000000-0000-0000-0000-00000000d00b', 'asset:n2.jpg', 0),
  ('00000000-0000-0000-0000-00000000d00b', 'asset:p2.jpg', 1),
  ('00000000-0000-0000-0000-00000000d00c', 'asset:p3.jpg', 0),
  ('00000000-0000-0000-0000-00000000d00d', 'asset:n1.jpg', 0),
  ('00000000-0000-0000-0000-00000000d00e', 'asset:p1.jpg', 0),
  ('00000000-0000-0000-0000-00000000d00f', 'asset:p4.jpg', 0),
  ('00000000-0000-0000-0000-00000000d010', 'asset:p5.jpg', 0),
  ('00000000-0000-0000-0000-00000000d010', 'asset:p7.jpg', 1),
  ('00000000-0000-0000-0000-00000000d011', 'asset:p2.jpg', 0);
