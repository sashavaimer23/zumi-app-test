-- =====================================================================
--  Zumi — 016: непрочитанные сообщения
--  Для каждой переписки помним, когда человек последний раз её открывал.
--  Непрочитанные = сообщения от собеседника, пришедшие после этого момента.
--  Число показывается на значке «Chats» (до 10, дальше «10+») и в списке чатов.
--  Запускать после 015. Можно запускать повторно.
-- =====================================================================

create table if not exists public.chat_reads (
  conversation_id uuid not null references public.conversations(id) on delete cascade,
  user_id         uuid not null references public.profiles(id) on delete cascade,
  read_at         timestamptz not null default now(),
  primary key (conversation_id, user_id)
);
alter table public.chat_reads enable row level security;
drop policy if exists "own chat reads" on public.chat_reads;
create policy "own chat reads" on public.chat_reads for select using (user_id = auth.uid());

-- быстрый подсчёт: сообщения собеседника после времени прочтения
create index if not exists messages_conv_sender_idx on public.messages (conversation_id, created_at, sender_id);

-- открыл переписку → всё в ней прочитано
create or replace function public.mark_chat_read(cid uuid)
returns void language plpgsql security definer set search_path = public, extensions as $$
begin
  if auth.uid() is null then raise exception 'NOT_SIGNED_IN'; end if;
  if not exists (select 1 from conversations where id = cid and auth.uid() in (buyer_id, seller_id)) then
    return;
  end if;
  insert into chat_reads (conversation_id, user_id, read_at) values (cid, auth.uid(), now())
  on conflict (conversation_id, user_id) do update set read_at = now();
end $$;
grant execute on function public.mark_chat_read(uuid) to authenticated;

-- для значка (заменено в 017: считаются переписки с новыми сообщениями)
create or replace function public.my_unread_count()
returns int language sql stable security definer set search_path = public, extensions as $$
  select count(*)::int from (
    select 1
      from conversations c
      join messages m on m.conversation_id = c.id
      left join chat_reads r on r.conversation_id = c.id and r.user_id = auth.uid()
     where auth.uid() in (c.buyer_id, c.seller_id)
       and m.sender_id <> auth.uid()
       and m.created_at > coalesce(r.read_at, '-infinity'::timestamptz)
     limit 11
  ) x;
$$;
grant execute on function public.my_unread_count() to authenticated;

-- список переписок + число непрочитанных в каждой (новый столбец — в конце)
create or replace view public.conversation_list
with (security_invoker = true) as
  select c.*,
         p.title as property_title,
         (select url from property_images i where i.property_id = p.id order by sort_order limit 1) as property_cover,
         case when c.buyer_id = auth.uid() then s.full_name else b.full_name end as other_name,
         (select count(*)::int from messages m
           where m.conversation_id = c.id and m.sender_id <> auth.uid()
             and m.created_at > coalesce((select r.read_at from chat_reads r
                                           where r.conversation_id = c.id and r.user_id = auth.uid()),
                                          '-infinity'::timestamptz)) as unread
    from conversations c
    left join properties p on p.id = c.property_id
    left join profiles  b on b.id = c.buyer_id
    left join profiles  s on s.id = c.seller_id;
