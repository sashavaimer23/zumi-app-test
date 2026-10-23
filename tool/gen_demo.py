import json, uuid, random
random.seed(7)
# (id, name, lng, lat, tagline, image)
areas = [
 (1,'Kabulonga',28.335,-15.425,'Leafy streets & top schools',None),
 (2,'Woodlands',28.320,-15.435,'Central, calm and green',None),
 (3,'Roma',28.310,-15.370,'Vibrant community & city access','asset:n2.jpg'),
 (4,'Ibex Hill',28.370,-15.440,'Modern homes & green spaces','asset:n1.jpg'),
 (5,'Rhodes Park',28.305,-15.405,'Walk to everything',None),
 (6,'Olympia',28.310,-15.385,'Close to UNZA & malls',None),
 (7,'Northmead',28.300,-15.400,'Shops, cafes and nightlife',None),
 (8,'Longacres',28.312,-15.412,'Business district living',None),
 (9,'Chelston',28.370,-15.370,'Affordable family homes',None),
 (10,'Avondale',28.355,-15.375,'Quiet residential area',None),
 (11,'Meanwood',28.330,-15.355,'Peaceful living and family-friendly','asset:n3.jpg'),
 (12,'Chalala',28.330,-15.470,'Growing suburb, great value',None),
 (13,"Leopards Hill",28.390,-15.460,'Big plots and views',None),
 (14,'New Kasama',28.400,-15.430,'New developments',None),
 (15,'Makeni',28.250,-15.460,'Space to build',None),
]
A={a[0]:a for a in areas}
# title, deal, type, price, period, bed, bath, sqm, plot, area, address, images, amen, promoted, by, reno, kids, pets, lease, desc
L = [
 ('Cosy family house','rent','house',45000,'month',3,2,70.8,None,4,'The 3rd street',['p1.jpg','p6.jpg'],['parking','garden','ac'],True,'agent','designer',True,False,'year','Bright 3-bedroom family house in a quiet gated street of Ibex Hill. Fitted kitchen, borehole, solar backup and a private garden.'),
 ('Cosy apartment','rent','apartment',40000,'month',2,1,65.8,None,4,'The 2nd street',['p2.jpg','p7.jpg'],['parking','furnished','ac','internet'],True,'agent','designer',True,True,'year','Modern 2-bedroom apartment with open-plan living area, fibre internet and secure parking.'),
 ('Commercial for rent','rent','commercial',38000,'month',None,1,65.8,None,11,'The Meanwood road',['p3.jpg'],['parking'],False,'agent','cosmetic',None,None,'year','Warehouse / showroom space on the main road with loading area and parking.'),
 ('Modern 3 bedroom house in Ibex Hill','rent','house',45000,'month',3,2,68,None,4,'Bishops road',['p6.jpg','p1.jpg'],['parking','garden'],False,'owner','designer',True,True,'year','Newly built 3-bedroom house with en-suite master bedroom and covered veranda.'),
 ('Contemporary townhouse','sale','house',2850000,None,4,3,210,None,3,'Kasama road',['p4.jpg','n2.jpg'],['parking','garden','garage','ac'],True,'agent','designer',None,None,None,'Double-storey townhouse with balcony, double garage and landscaped garden.'),
 ('Family home with big garden','sale','house',4200000,None,5,4,320,1800,1,'Ngwee road',['p5.jpg','p4.jpg'],['parking','garden','pool','garage'],False,'agent','designer',None,None,None,'Spacious 5-bedroom home on a large plot, swimming pool and staff quarters.'),
 ('Furnished apartment, daily','rent','apartment',1500,'day',1,1,48,None,5,'Lagos road',['p7.jpg'],['furnished','ac','internet','tv','fridge','washing_machine'],False,'owner','designer',True,False,'months','Fully furnished 1-bedroom apartment for short stays. Wi-Fi and Netflix included.'),
 ('3 bedroom house near Arcades','rent','house',18000,'month',3,2,120,None,2,'Kabelenga road',['n1.jpg','p1.jpg'],['parking','garden'],False,'owner','cosmetic',True,True,'year','Comfortable family house close to Arcades and schools.'),
 ('Residential plot, 2000 m²','sale','land',650000,None,None,None,None,2000,13,'Leopards Hill road',['p5.jpg'],[],False,'agent',None,None,None,None,'Title-deeded residential plot with water and electricity nearby.'),
 ('2 bedroom flat','rent','apartment',9500,'month',2,1,70,None,12,'Chalala main road',['p6.jpg'],['parking'],False,'owner','none',True,True,'year','Affordable 2-bedroom flat in a secure complex.'),
 ('4 bedroom house','sale','house',1950000,None,4,3,190,900,11,'Mutumbi road',['n3.jpg','p4.jpg'],['parking','garden','garage'],False,'agent','cosmetic',None,None,None,'Solid 4-bedroom house with borehole and solar geyser.'),
 ('Roma Park apartment','rent','apartment',22000,'month',3,2,110,None,3,'Roma Park',['n2.jpg','p2.jpg'],['parking','ac','internet','dishwasher'],False,'agent','designer',True,False,'year','3-bedroom apartment in Roma Park, gym and 24/7 security.'),
 ('Office space','rent','commercial',30000,'month',None,2,140,None,6,'Great East road',['p3.jpg'],['parking','internet','ac'],False,'agent','cosmetic',None,None,'year','Open-plan office with meeting room, close to UNZA.'),
 ('Plot in Makeni','sale','land',250000,None,None,None,None,1200,15,'Makeni',['n1.jpg'],[],False,'owner',None,None,None,None,'Residential plot in a fast-growing area.'),
 ('Starter house in New Kasama','rent','house',12000,'month',3,1,95,None,14,'New Kasama',['p1.jpg'],['parking'],False,'owner','cosmetic',True,True,'year','Neat 3-bedroom house, newly painted.'),
 ('Chelston bungalow','sale','house',900000,None,2,1,85,600,9,'Chelston',['p4.jpg'],['garden'],False,'owner','none',None,None,None,'2-bedroom bungalow, ideal first home or rental investment.'),
 ('Luxury villa with pool','rent','house',75000,'month',5,5,400,2500,1,'Kabulonga road',['p5.jpg','p7.jpg'],['parking','garden','pool','garage','furnished','ac','internet'],True,'agent','designer',True,True,'year','Executive 5-bedroom villa with pool, fully furnished.'),
 ('Northmead 1 bedroom','rent','apartment',7000,'month',1,1,45,None,7,'Northmead',['p2.jpg'],['internet'],False,'owner','cosmetic',False,False,'months','Compact 1-bedroom flat near shops and cafes.'),
]
HL={'Cosy family house':'Gated street | Borehole | Solar backup','Cosy apartment':'Fibre internet | Secure parking','Luxury villa with pool':'Pool | Fully furnished | Big garden','Contemporary townhouse':'Double garage | Balcony','Family home with big garden':'Pool | Staff quarters | Big plot'}
props=[]
for i,l in enumerate(L):
    (t,deal,ptype,price,period,bed,bath,sqm,plot,aid,addr,imgs,amen,promo,by,reno,kids,pets,lease,desc)=l
    a=A[aid]
    lng=round(a[2]+random.uniform(-0.008,0.008),6); lat=round(a[3]+random.uniform(-0.008,0.008),6)
    props.append(dict(id=str(uuid.UUID(int=0xD000+i)), title=t, description=desc, deal_type=deal, property_type=ptype,
      price=price, currency='ZMW', rent_period=period, bedrooms=bed, bathrooms=bath, area_sqm=sqm, plot_sqm=plot,
      amenities=amen, area_id=aid, area_name=a[1], city='Lusaka', address=addr, lat=lat, lng=lng, status='active',
      is_promoted=promo, image_urls=['asset:'+x for x in imgs], listed_by=by,
      contact_name=('Zumi Realty' if by=='agent' else 'Private owner'), contact_phone='+260 97 000 00%02d'%i,
      renovation=reno, kids_allowed=kids, pets_allowed=pets, lease_term=lease, views_count=random.randint(20,400),
      created_at='2026-10-%02dT10:00:00Z'%(20-i), is_demo=True,
      property_verified=False, property_verify_method=None, property_verified_at=None,
      ownership_verified=False,
      confirmed_at='2026-10-%02dT08:00:00Z'%(21-(i%5)),
      highlights=HL.get(t),
      owner_phone_verified=True, owner_identity_verified=(by=='agent'),
      agency_name=('Zumi Realty' if by=='agent' else None)))

# ---- Dart
def dv(v):
    if v is None: return 'null'
    if isinstance(v,bool): return 'true' if v else 'false'
    if isinstance(v,(int,float)): return repr(v)
    if isinstance(v,list): return '['+', '.join(dv(x) for x in v)+']'
    return "'"+str(v).replace("\\","\\\\").replace("'","\\'").replace('$','\\$')+"'"
out=["// GENERATED from tool/gen_demo.py — demo data shared with supabase/003_demo_seed.sql",
"// ignore_for_file: prefer_single_quotes","",
"const List<Map<String, dynamic>> demoAreas = ["]
for a in areas:
    out.append("  {'id': %d, 'city': 'Lusaka', 'name': %s, 'lat': %s, 'lng': %s, 'tagline': %s, 'image_url': %s},"%(a[0],dv(a[1]),a[3],a[2],dv(a[4]),dv(a[5])))
out.append("];\n\nconst List<Map<String, dynamic>> demoProperties = [")
for p in props:
    out.append("  {"+", ".join("'%s': %s"%(k,dv(v)) for k,v in p.items())+"},")
out.append("];\n")
open('/home/claude/zumi/lib/data/demo_data.dart','w').write("\n".join(out))

# ---- SQL
def sv(v):
    if v is None: return 'null'
    if isinstance(v,bool): return 'true' if v else 'false'
    if isinstance(v,(int,float)): return repr(v)
    if isinstance(v,list): return "array["+",".join(sv(x) for x in v)+"]::text[]" if v else "'{}'::text[]"
    return "'"+str(v).replace("'","''")+"'"
s=["-- =====================================================================",
"--  Zumi — 003: демо-объявления (is_demo = true). Запускать после 002.",
"--  Удалить все демо одной командой:  delete from public.properties where is_demo;",
"--  Фото демо лежат в приложении (asset:...). Реальные фото — в Storage.",
"-- =====================================================================",""]
for a in areas:
    s.append("update public.areas set tagline = %s, image_url = %s where city = 'Lusaka' and name = %s;"%(sv(a[4]),sv(a[5]),sv(a[1])))
s.append("")
cols=['id','title','description','deal_type','property_type','price','currency','rent_period','bedrooms','bathrooms','area_sqm','plot_sqm','amenities','area_id','address','location','status','promoted_until','listed_by','contact_name','contact_phone','renovation','kids_allowed','pets_allowed','lease_term','views_count','created_at','is_demo']
s.append("insert into public.properties ("+", ".join(cols)+") values")
rows=[]
for p in props:
    vals=[]
    for c in cols:
        if c=='area_id': vals.append("(select id from public.areas where city='Lusaka' and name=%s)"%sv(p['area_name']))
        elif c=='location': vals.append("st_point(%s,%s)::geography"%(p['lng'],p['lat']))
        elif c=='promoted_until': vals.append("now() + interval '30 days'" if p['is_promoted'] else 'null')
        else: vals.append(sv(p[c]))
    rows.append("  ("+", ".join(vals)+")")
s.append(",\n".join(rows)+"\non conflict (id) do nothing;\n")
s.append("insert into public.property_images (property_id, url, sort_order) values")
ir=[]
for p in props:
    for j,u in enumerate(p['image_urls']): ir.append("  ('%s', '%s', %d)"%(p['id'],u,j))
s.append(",\n".join(ir)+";\n")
open('/home/claude/zumi/supabase/003_demo_seed.sql','w').write("\n".join(s))
print(len(props),'props')
