-- =====================================================================
--  Zumi — 017: значок «Chats» считает переписки, а не сообщения
--  Число на значке = сколько переписок с новыми сообщениями (до 10, дальше «10+»).
--  В списке чатов у каждой переписки по-прежнему видно, сколько в ней новых сообщений.
--  Запускать после 016. Можно запускать повторно.
-- =====================================================================
create or replace function public.my_unread_count()
returns int language sql stable security definer set search_path = public, extensions as $$
  select count(*)::int from (
    select 1
      from conversations c
      left join chat_reads r on r.conversation_id = c.id and r.user_id = auth.uid()
     where auth.uid() in (c.buyer_id, c.seller_id)
       and exists (select 1 from messages m
                    where m.conversation_id = c.id
                      and m.sender_id <> auth.uid()
                      and m.created_at > coalesce(r.read_at, '-infinity'::timestamptz))
     limit 11
  ) x;
$$;
grant execute on function public.my_unread_count() to authenticated;
