-- =====================================================================
--  Zumi — 020: помощь, отзывы о приложении, выключатель продвижения
--  1. Новые статьи помощи (оплата, не публикуется объявление, сайт не открывается…).
--  2. Отзывы о приложении: человек оценивает Zumi (1–5) и пишет, что не работает.
--     Видит только владелец Zumi — в кабинете разработчика.
--  3. Продвижение агентов выключено, пока владелец не включит его в кабинете.
--  Запускать после 019. Можно запускать повторно.
-- =====================================================================

-- ---------------------------------------------------------------------
-- 1. Помощь
-- ---------------------------------------------------------------------
alter table public.help_articles drop constraint if exists help_articles_category_check;
alter table public.help_articles add constraint help_articles_category_check check (category in
  ('account', 'listings', 'contact', 'verification', 'promotion', 'payments', 'safety', 'technical'));

insert into public.help_articles (id, category, title, body, sort, web_only) values
  ('e705fbca-c1e3-5593-aec7-2ae5fa371d05', 'payments', 'Payments: my payment did not go through', 'Right now Zumi is free: posting listings, chats and calls cost nothing. Zumi never asks you to pay by mobile money to a private number.

## If a payment on Zumi fails (when paid features open)
- Check that you have enough money on your mobile money account, including the operator fee.
- Make sure you typed the PIN on your phone within 2 minutes — the request expires after that.
- Check that your phone has signal. Weak network is the most common reason.
- Don''t pay twice. If money left your account but nothing changed in Zumi, wait 15 minutes — operators sometimes confirm late.
- Still nothing? Open Help & support → "Payment" and send the transaction ID from the SMS. We will check it and return the money or turn on what you paid for.

## Someone asks you to pay "Zumi"
Zumi staff never ask for money in chat, by phone or WhatsApp. Agents may not charge a viewing fee. If someone does, don''t pay and report them.', 10, true),
  ('fb83561c-31fb-5032-b97a-6a70818079b5', 'payments', 'Refunds and money taken by mistake', 'If money was taken by mistake or a paid feature did not work, write to Help & support → "Payment" with:
- the phone number you paid from;
- the date and amount;
- the transaction ID from the operator SMS.

We answer within 1 working day. If the payment really failed on our side, we return the money to the same mobile money account.

Zumi cannot return money you paid directly to an agent or owner — Zumi is not part of deals between users. In that case contact the person, and if you think it is fraud, report the listing and go to the police.', 20, true),
  ('575a4dfc-2025-58ad-ad03-f9da9f7f955d', 'listings', 'I can''t publish my listing', 'Check these things one by one:
- Phone number: you need to confirm your phone with a code once. Zumi asks for it when you tap Publish.
- Pin on the map: put the pin where the property is. Without it you can''t publish.
- Price and neighbourhood: both are required.
- Listing limit: free accounts have a limit of active listings. Hide or delete an old listing, or mark it as rented or sold.
- Team accounts (Zumi staff) can''t post listings — use a personal account.
- Your account is blocked: you will see a message. Write to Help & support.

Your first listings are checked by the Zumi team — usually about 15 minutes. You will see "Under review" in My listings.', 15, false),
  ('4505a935-defa-5738-ad1b-e0adfb76823d', 'listings', 'How to hide or show my listing', 'You don''t have to delete a listing when it is not available for a while.
- Profile → My listings → tap … on the listing → "Hide from search". People won''t see it, nothing is deleted.
- To show it again: My listings → Hidden → tap … → "Show in search again".
- Rented or sold? Choose "Mark as rented" / "Mark as sold". The listing moves to Hidden too.

Every 30 days Zumi asks "Is it still available?" — answer in one tap. If you don''t answer within 7 days, the listing is hidden until you confirm.', 25, false),
  ('e006954a-f026-5b32-8601-362ddb8a456e', 'listings', 'Map pin, address and what is nearby', 'When you post a listing:
- Pin on the map (required): zoom in and put the pin where the property is, as close as you can. People use it to plan a visit.
- Address (optional): street, plot number or a landmark. It is shown on the listing — leave it empty if you prefer to share it in chat.
- What''s nearby (optional): shops, school, hospital or clinic, main road — choose the distance. People see it on the listing and decide faster.

You can change all of this later: My listings → … → Edit.', 35, false),
  ('ad2ff5a7-e5ff-57ed-a447-10272eaca2c1', 'technical', 'The site does not open or shows an old version', '- Check your internet: open any other website.
- Refresh the page: on a computer press Ctrl+Shift+R (Windows) or Cmd+Shift+R in Chrome / Cmd+Option+R in Safari (Mac). On a phone close the tab and open zumi again.
- If Zumi is added to your home screen: close the app completely (swipe it away) and open it again.
- The first visit on a slow network can take up to a minute — you will see "Zumi is still loading". The next visits are much faster.
- Still not working? Try another browser (Chrome works best) and write to Help & support with your phone model.', 20, false),
  ('11f8fbeb-739a-5f9e-813e-ae9308c7766c', 'technical', 'I am not getting emails from Zumi', 'Zumi sends emails to confirm your account and to reset your password.
- Check the Spam, Junk and Promotions folders. Mark the email as "Not spam" so the next ones arrive in your inbox.
- Wait 2–3 minutes — sometimes emails come late.
- Check that the email address is correct: Profile → Settings.
- Tap "Resend" no more than once a minute — too many requests are blocked for a while.

Still nothing after 10 minutes? Write to Help & support.', 30, false),
  ('61ba9a12-4b69-527d-a705-bf24aa6de808', 'contact', 'The WhatsApp button does not open', '- WhatsApp must be installed on your phone. On a computer, WhatsApp Web or the WhatsApp app opens.
- Zumi shows a number only after you confirm your own phone — it protects owners and agents from spam.
- Some owners choose "Chat only" — then there is no WhatsApp button. Use Message instead.
- When WhatsApp opens, a ready message with the listing name, price and area is already typed. You can change it before sending.', 30, false),
  ('fa939f25-45f1-516b-a16c-42bdc0c33492', 'contact', 'New messages and the number on Chats', 'The number on the Chats icon shows how many conversations have new messages. Inside Chats, each conversation shows how many messages are new. Open the conversation — the number disappears.

The number on the Profile icon means your listings need an answer: "Is it still available?".', 40, false),
  ('10397b75-c9d2-5833-8786-5b63e16e9dd8', 'account', 'Where my data is stored', 'Your account data, listings, photos and messages are stored on secure Supabase servers in the European Union (Ireland), which means outside Zambia. You agree to this when you create an account.
- Data is encrypted on the way and on the servers.
- Your phone number is never public. People see it only after they confirm their own number, or not at all if you choose "Chat only".
- We never sell your data.
- You can delete your account any time: Settings → Delete my account. Ask for a copy of your data in Help & support.

Full details: Settings → Privacy Policy.', 40, false),
  ('c1693f27-4d95-539e-9e8e-be6bad8c9d33', 'technical', 'How to send feedback about the app', 'We want Zumi to be simple and fast for you. After a few minutes of use, Zumi may ask "How is Zumi working for you?" — choose a rating and tell us what is not working. It takes 20 seconds.

You can also send feedback any time: Profile → Settings → "Send feedback about the app". The Zumi team reads every message.', 50, false)
on conflict (id) do nothing;

-- ---------------------------------------------------------------------
-- 2. Отзывы о приложении
-- ---------------------------------------------------------------------
create table if not exists public.app_feedback (
  id          uuid primary key default gen_random_uuid(),
  user_id     uuid references public.profiles(id) on delete set null,
  device_hash text,                                   -- зашифрованная метка устройства (гость)
  rating      int  not null check (rating between 1 and 5),
  issues      text[] not null default '{}',
  comment     text check (comment is null or length(comment) <= 1000),
  platform    text,
  app_version text,
  created_at  timestamptz not null default now()
);
create index if not exists app_feedback_created_idx on public.app_feedback (created_at desc);
alter table public.app_feedback enable row level security;   -- читать напрямую нельзя никому, только через функцию владельца

create or replace function public.send_app_feedback(p_rating int, p_issues text[], p_comment text,
                                                    p_platform text, p_version text, p_device text default null)
returns void language plpgsql security definer set search_path = public, extensions as $$
declare
  v_hash text := case when p_device is null or p_device = '' then null else md5('fb' || p_device) end;
  v_issues text[];
begin
  if p_rating is null or p_rating < 1 or p_rating > 5 then raise exception 'BAD_RATING'; end if;
  select coalesce(array_agg(i), '{}') into v_issues from unnest(coalesce(p_issues, '{}')) i
   where i in ('slow', 'crash', 'photos', 'login', 'search', 'chat', 'post', 'confusing', 'other');
  -- не чаще раза в день с человека / устройства (защита от потока)
  if exists (select 1 from app_feedback
              where created_at > now() - interval '1 day'
                and ((auth.uid() is not null and user_id = auth.uid()) or (v_hash is not null and device_hash = v_hash))) then
    raise exception 'TOO_MANY_REQUESTS';
  end if;
  if (select count(*) from app_feedback where created_at > now() - interval '1 hour') > 500 then
    raise exception 'TOO_MANY_REQUESTS';
  end if;
  insert into app_feedback (user_id, device_hash, rating, issues, comment, platform, app_version)
  values (auth.uid(), v_hash, p_rating, v_issues, nullif(left(trim(coalesce(p_comment, '')), 1000), ''),
          left(coalesce(p_platform, ''), 20), left(coalesce(p_version, ''), 20));
end $$;
grant execute on function public.send_app_feedback(int, text[], text, text, text, text) to anon, authenticated;

-- для кабинета разработчика: сводка и последние отзывы
create or replace function public.owner_app_feedback(p_days int default 30)
returns jsonb language plpgsql stable security definer set search_path = public, extensions as $$
declare v_from timestamptz := now() - make_interval(days => greatest(1, least(coalesce(p_days, 30), 365)));
begin
  if not public.is_owner() then raise exception 'OWNER_ONLY'; end if;
  return jsonb_build_object(
    'count',   (select count(*) from app_feedback where created_at >= v_from),
    'average', (select round(avg(rating)::numeric, 2) from app_feedback where created_at >= v_from),
    'by_rating', (select coalesce(jsonb_object_agg(rating, n), '{}'::jsonb) from
                   (select rating, count(*) n from app_feedback where created_at >= v_from group by rating) x),
    'issues', (select coalesce(jsonb_object_agg(i, n), '{}'::jsonb) from
                (select i, count(*) n from app_feedback, unnest(issues) i where created_at >= v_from group by i) x),
    'items', (select coalesce(jsonb_agg(jsonb_build_object(
                'rating', f.rating, 'issues', f.issues, 'comment', f.comment, 'platform', f.platform,
                'version', f.app_version, 'at', f.created_at,
                'who', case when f.user_id is null then 'Guest' else coalesce(pr.full_name, 'User') end)
                order by f.created_at desc), '[]'::jsonb)
              from (select * from app_feedback where created_at >= v_from order by created_at desc limit 200) f
              left join profiles pr on pr.id = f.user_id)
  );
end $$;
grant execute on function public.owner_app_feedback(int) to authenticated;

-- уборка: отзывы храним 1 год
create or replace function public.cleanup_feedback()
returns void language sql security definer set search_path = public, extensions as $$
  delete from app_feedback where created_at < now() - interval '1 year';
$$;

-- ---------------------------------------------------------------------
-- 3. Выключатель продвижения (по умолчанию выключено)
-- ---------------------------------------------------------------------
insert into public.app_settings values ('promotion_enabled', 'false') on conflict do nothing;

create or replace function public.promotion_on()
returns boolean language sql stable security definer set search_path = public, extensions as $$
  select coalesce((select value from app_settings where key = 'promotion_enabled'), 'false') = 'true';
$$;

-- что включено — приложение спрашивает при запуске
create or replace function public.app_flags()
returns jsonb language sql stable security definer set search_path = public, extensions as $$
  select jsonb_build_object('promotion', public.promotion_on());
$$;
grant execute on function public.app_flags() to anon, authenticated;

-- включить / выключить может только владелец
create or replace function public.admin_set_setting(p_key text, p_value text)
returns void language plpgsql security definer set search_path = public, extensions as $$
begin
  if not public.is_admin() then raise exception 'NOT_ADMIN'; end if;
  if p_key not in ('otp_test_mode', 'require_licence_to_publish', 'promotion_enabled') then raise exception 'BAD_SETTING'; end if;
  if p_key = 'promotion_enabled' and not public.is_owner() then raise exception 'OWNER_ONLY'; end if;
  if p_value not in ('true', 'false') then raise exception 'BAD_SETTING'; end if;
  insert into app_settings (key, value) values (p_key, p_value)
  on conflict (key) do update set value = excluded.value;
  perform public._audit('setting', 'settings', p_key, p_value);
end $$;

-- пока выключено: кампанию нельзя запустить…
create or replace function public.promotion_switch()
returns trigger language plpgsql security definer set search_path = public, extensions as $$
begin
  if new.status = 'active' and not public.promotion_on()
     and (tg_op = 'INSERT' or old.status is distinct from 'active') then
    raise exception 'PROMOTION_OFF';
  end if;
  return new;
end $$;
drop trigger if exists promotion_switch on public.campaigns;
create trigger promotion_switch before insert or update of status on public.campaigns
  for each row execute function public.promotion_switch();

-- …и уже запущенные никому не показываются (кроме автора и команды)
drop policy if exists "promotion switch" on public.campaigns;
create policy "promotion switch" on public.campaigns as restrictive for select
  using (public.promotion_on() or owner_id = auth.uid() or public.is_admin());

-- статус для кабинета
create or replace function public.admin_promotion_status()
returns jsonb language plpgsql stable security definer set search_path = public, extensions as $$
begin
  if not public.is_admin() then raise exception 'NOT_ADMIN'; end if;
  return jsonb_build_object('enabled', public.promotion_on(),
    'live_campaigns', (select count(*) from campaigns where status = 'active' and ends_on >= current_date));
end $$;
grant execute on function public.admin_promotion_status() to authenticated;
