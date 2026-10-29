-- =====================================================================
--  Zumi — 021: обновление старых статей помощи под новые правила
--  («Number checked», телефон для публикации, «ещё доступно?» через 30 дней,
--  лицензия ZIEA без продвижения). Меняются только статьи, которые команда не правила сама.
--  Запускать после 020. Можно запускать повторно.
-- =====================================================================
update public.help_articles set body = 'You sign in to Zumi with your email and password.

## Confirming your phone
You need a confirmed phone to publish a listing and to see phone numbers in listings. Your listings then show "Number checked". You do it only once:
- Open Profile → Get verified (or Settings → Phone & verification).
- Choose WhatsApp or SMS and enter your number with the country code, e.g. +260 97 123 4567.
- Type the 6-digit code you receive. It works for 10 minutes.

## Good to know
- One phone number can be confirmed on only one Zumi account.
- If you change your number in the profile, you need to confirm the new one.
- Forgot your password? On the sign-in screen tap "Forgot password?" — we send a code to your email. Type the whole code from the email (it can be 6–8 digits).'
 where id = 'e2bf5b54-9919-58d0-9461-2de87c71309d' and updated_by is null;
update public.help_articles set body = 'Estate agents in Zambia are registered with the Zambia Institute of Estate Agents (ZIEA). Zumi checks your registration number with the register — you don''t upload any documents.

- Add the number when you sign up as an agent (it is optional), or later in Profile → Get verified.
- Until it is checked, your listings and agent page show "ZIEA licence not verified".
- After the check your listings show the "Licensed agent" badge — people trust them more.

If your number was not approved, the reason is shown in Get verified. Check the number and send it again.'
 where id = 'a44d1cea-2bb5-5fdc-81f2-6aea36e74198' and updated_by is null;
update public.help_articles set body = 'Tap "Post" on the home screen (or "Post a listing" on the website) and follow the steps:
- Choose rent or sale and the type of property.
- Add a clear title, the price and the main details (bedrooms, bathrooms, size).
- Add good photos: daylight, every room, the outside and the street. 5 or more photos give people a clear picture.
- Put the pin on the map where the property is (required). The address and "what''s nearby" are optional.
- Check the preview and publish. The first time, Zumi asks you to confirm your phone with a code.

## Tips
- Write the real price, so people know right away if the home fits their budget.
- Do not put phone numbers or links inside photos or the description — use the contact settings instead.
- Every 30 days Zumi asks "Is it still available?" — answer in one tap. Without an answer for 7 days the listing is hidden from search (not deleted).'
 where id = 'e2232f2d-41f2-569a-a8f0-f3ebc63e88b5' and updated_by is null;
