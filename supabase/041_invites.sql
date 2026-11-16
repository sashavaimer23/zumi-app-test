-- =====================================================================
--  Zumi — 041: «Пригласить друга» + каталоги агентов в карте сайта
--  • У агента и собственника есть личная ссылка-приглашение (короткий код).
--  • Кто зарегистрировался по ней — запоминаем, кто пригласил. В кабинете: «Вы пригласили N».
--  • Бонуса пока нет (добавим позже, если решим) — только счётчик.
--  • catalog_slugs() — адреса каталогов агентов для Google (sitemap).
--  Запускать после 040. Можно запускать повторно.
-- =====================================================================

alter table public.profiles
  add column if not exists invite_code text,
  add column if not exists invited_by uuid references public.profiles(id) on delete set null,
  add column if not exists invited_at timestamptz;
create unique index if not exists profiles_invite_code_key on public.profiles (invite_code) where invite_code is not null;
create index if not exists profiles_invited_by_idx on public.profiles (invited_by) where invited_by is not null;

-- моя ссылка-приглашение и сколько людей пришло
create or replace function public.my_invite()
returns jsonb language plpgsql security definer set search_path = public, extensions as $$
declare uid uuid := auth.uid(); v text;
begin
  if uid is null then raise exception 'AUTH'; end if;
  select invite_code into v from profiles where id = uid;
  while v is null loop
    v := upper(substr(md5(random()::text || clock_timestamp()::text), 1, 6));
    if exists (select 1 from profiles where invite_code = v) then v := null; continue; end if;
    update profiles set invite_code = v where id = uid;
  end loop;
  return jsonb_build_object(
    'code', v,
    'invited', (select count(*) from profiles where invited_by = uid),
    'posted', (select count(distinct p.id) from profiles p join properties x on x.owner_id = p.id and not x.is_demo
                where p.invited_by = uid));
end $$;
revoke execute on function public.my_invite() from public, anon;
grant execute on function public.my_invite() to authenticated;

-- новый человек: «меня пригласил …» (только в первые 3 дня после регистрации, один раз, не сам себя)
create or replace function public.claim_invite(p_code text)
returns boolean language plpgsql security definer set search_path = public, extensions as $$
declare uid uuid := auth.uid(); v_from uuid;
begin
  if uid is null then raise exception 'AUTH'; end if;
  select id into v_from from profiles where invite_code = upper(trim(coalesce(p_code, '')));
  if v_from is null or v_from = uid then return false; end if;
  update profiles set invited_by = v_from, invited_at = now()
   where id = uid and invited_by is null and created_at > now() - interval '3 days';
  return found;
end $$;
revoke execute on function public.claim_invite(text) from public, anon;
grant execute on function public.claim_invite(text) to authenticated;

-- каталоги агентов с объявлениями — для sitemap
create or replace function public.catalog_slugs()
returns table (slug text) language sql stable security definer set search_path = public, extensions as $$
  select pr.slug from profiles pr
   where pr.slug is not null and pr.banned_at is null
     and exists (select 1 from properties x where x.owner_id = pr.id and x.status = 'active' and not x.is_demo)
   limit 5000;
$$;
grant execute on function public.catalog_slugs() to anon, authenticated;

-- для команды: кто кого пригласил больше всех
create or replace function public.admin_top_inviters()
returns table (id uuid, name text, role text, invited bigint, posted bigint)
language sql stable security definer set search_path = public, extensions as $$
  select p.id, coalesce(p.full_name, '—'), p.role,
         count(i.id), count(distinct x.owner_id)
    from profiles p
    join profiles i on i.invited_by = p.id
    left join properties x on x.owner_id = i.id and not x.is_demo
   where public.is_admin()
   group by p.id
   order by count(i.id) desc
   limit 50;
$$;
grant execute on function public.admin_top_inviters() to authenticated;

-- проверка
select (select count(*) from pg_proc where proname in ('my_invite', 'claim_invite', 'catalog_slugs')) = 3 as invites_ok;
