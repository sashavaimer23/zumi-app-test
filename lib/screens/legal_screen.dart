import 'package:flutter/material.dart';

import '../theme.dart';

/// Условия использования и Политика конфиденциальности.
///
/// ВАЖНО: это черновики. Перед запуском их должен проверить юрист в Замбии.
/// Когда тексты будут проверены — поставьте kLegalDraft = false (плашка «Draft» исчезнет).
const kLegalDraft = true;
const kLegalUpdated = '29 October 2026';

enum LegalDoc { terms, privacy }

void openLegal(BuildContext context, LegalDoc doc) {
  Navigator.push(context, MaterialPageRoute(builder: (_) => LegalScreen(doc: doc)));
}

class LegalScreen extends StatelessWidget {
  const LegalScreen({super.key, required this.doc});
  final LegalDoc doc;

  @override
  Widget build(BuildContext context) {
    final (title, sections) = doc == LegalDoc.terms ? ('Terms of Service', _terms) : ('Privacy Policy', _privacy);
    return Scaffold(
      appBar: AppBar(title: Text(title)),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 760),
          child: ListView(
            padding: const EdgeInsets.fromLTRB(22, 8, 22, 48),
            children: [
              Text('Last updated: $kLegalUpdated', style: const TextStyle(color: Zc.grey, fontSize: 13)),
              if (kLegalDraft)
                Container(
                  margin: const EdgeInsets.only(top: 12),
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(color: Zc.orangeSoft, borderRadius: BorderRadius.circular(12)),
                  child: const Text('Draft — this text will be reviewed by a lawyer before Zumi launches.',
                      style: TextStyle(fontSize: 13)),
                ),
              for (final (h, body) in sections) ...[
                Padding(
                  padding: const EdgeInsets.only(top: 24, bottom: 8),
                  child: Text(h, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600, color: Zc.green)),
                ),
                Text(body, style: const TextStyle(fontSize: 15, height: 1.5)),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

const _terms = <(String, String)>[
  (
    '1. About Zumi',
    'Zumi is an online platform where property owners and estate agents in Zambia publish listings for sale '
        'and rent, and where people looking for a home can find them and get in touch. Zumi is not an estate '
        'agent, broker, landlord, seller or legal adviser, and is not a party to any deal between users. Zumi does '
        'not own, inspect, value or manage any property and does not hold or handle money between users. Any '
        'viewing, agreement, payment or lease is arranged directly between you and the other person, at your own '
        'decision and risk.'
  ),
  (
    '2. Your account',
    'You must be at least 18 years old to create an account. Give your real name and keep your contact '
        'details up to date. One account is for one person or agency. Keep your password private — you are '
        'responsible for what happens in your account. You can delete your account at any time in Settings.'
  ),
  (
    '3. Listings',
    '• List only property that exists and that you have the right to offer — as the owner, or with the '
        'owner\'s permission.\n'
        '• Estate agents must be registered with the Zambia Institute of Estate Agents (ZIEA), as required by '
        'the Estate Agents Act No. 21 of 2000.\n'
        '• Price, photos, location and details must be true and current. Use your own photos.\n'
        '• Do not post the same property twice. Mark a property as sold or rented when it is no longer available.\n'
        '• Free listings: owners — 2 active listings, agents — 5. More listings and promotion may be paid.\n'
        '• To publish a listing you must confirm your phone number with a code (once).\n'
        '• Put the pin on the map where the property really is. The address and "what\'s nearby" are optional, '
        'but must be true if you add them.\n'
        '• A listing that has not been confirmed as available for 60 days is hidden from search until you confirm it.'
  ),
  (
    '4. Safety rules',
    'It is not allowed to:\n'
        '• ask for a "viewing fee", "booking fee", "registration fee" or any other payment for showing a property — '
        'at any time: before, during or after a viewing;\n'
        '• ask for a deposit or rent before the person has seen the property and a written agreement is signed;\n'
        '• publish fake listings or pretend to be someone else;\n'
        '• refuse people because of tribe, religion, gender, disability or nationality;\n'
        '• send spam, insults or threats, or share other people\'s personal data;\n'
        '• use Zumi for anything illegal.\n'
        'Never pay before you have seen the property in person, checked who the owner is and signed a written '
        'agreement. If anyone asks you for a viewing fee, do not pay and report the listing in Zumi.\n'
        'Viewings: meet in daylight, tell someone where you are going, go with a friend if you can, and do not '
        'carry large amounts of cash. You go to viewings and meet other users at your own risk.'
  ),
  (
    '5. Badges',
    '"Number checked" means the person confirmed their phone number with a code. "Licensed agent" means the '
        'Zumi team checked the agent\'s registration number with the Zambia Institute of Estate Agents (ZIEA) at '
        'the time of the check. Zumi does not check identity documents, ownership documents or the property itself. '
        'Badges do not guarantee the person, the property, the price or the outcome of a deal. Always view the '
        'property and check the documents yourself.'
  ),
  (
    '6. Reviews and reports',
    'Reviews must describe your own real experience. Do not post insults, fake reviews or personal data. '
        'You can report a listing or a review — the Zumi team checks reports and may hide content.'
  ),
  (
    '7. Paid features',
    'Some features (promotion to the top, extra listings) may be paid. The price is always shown before you '
        'pay. Payments are processed by payment providers such as mobile money operators.'
  ),
  (
    '8. Moderation',
    'Zumi may edit, hide or remove listings, reviews and messages that break these rules, and may block '
        'accounts used for fraud or abuse. If you think we made a mistake, write to us in Help & support.'
  ),
  (
    '9. Liability',
    'Zumi provides the platform "as is" and "as available". We work to keep it safe and working, but we do not '
        'promise that it will always be available, error-free, or that listings are accurate, legal or still on '
        'offer.\n'
        'To the fullest extent allowed by the law of Zambia, Zumi, its owners and team are not responsible for:\n'
        '• any money you lose — including deposits, rent, fees or payments made to other users;\n'
        '• fraud, false information, scams or other wrongdoing by owners, agents, buyers, tenants or anyone else '
        'you met through Zumi;\n'
        '• injury, theft, damage to property or any other harm that happens during or after a viewing or a meeting;\n'
        '• the condition, ownership, title, legal status or price of any property;\n'
        '• deals, contracts and disputes between users;\n'
        '• lost profits, lost data or indirect damage of any kind.\n'
        'Badges (for example a checked phone number or a checked licence) only show what the Zumi team checked at '
        'that time — they are not a guarantee of the person or the property.\n'
        'If Zumi is found liable for anything despite this, our total liability is limited to the amount you paid '
        'Zumi in the 12 months before the claim. Nothing in these terms limits liability that cannot be limited '
        'under the law of Zambia.'
  ),
  (
    '10. Your responsibility',
    'You are responsible for what you publish and do on Zumi. If your listing, message or actions break these '
        'terms or the law and someone makes a claim against Zumi because of it, you agree to cover Zumi\'s '
        'reasonable losses and costs from that claim.'
  ),
  (
    '11. Changes and law',
    'We may update these terms. If the changes are important, we will tell you in the app. '
        'These terms are governed by the laws of the Republic of Zambia. Questions: Profile → Help & support.'
  ),
];

const _privacy = <(String, String)>[
  (
    'Who we are',
    'Zumi is a property platform for Zambia. This policy explains what personal data we collect, why, and '
        'what rights you have under the Data Protection Act No. 3 of 2021.'
  ),
  (
    'What we collect',
    '• Account: name, email, phone number, account type (owner or agent), the date you accepted the '
        'Terms and this Privacy Policy, and — only if you tick the box — the date you agreed to receive Zumi news '
        'and offers by WhatsApp and/or email (you can turn each off any time in Settings).\n'
        '• Profile: photo, agency name, "about you" and business WhatsApp number (agents), ZIEA licence number '
        '(agents), and how people may contact you (phone or chat only).\n'
        '• Listings: photos, description, price, the pin on the map, the address and "what\'s nearby" (if you '
        'add them), contact number you add.\n'
        '• Messages you send in Zumi chats and to support.\n'
        '• Phone-number views: when you open a phone or WhatsApp number, we record who opened whose number and '
        'when. This protects agents and owners from spam and lets us find bots.\n'
        '• Confirmation codes: the phone number or email we sent a code to, when, and how many attempts were '
        'made (the code itself is stored only in protected, scrambled form).\n'
        '• Safety records: reports about listings or reviews, blocked accounts and the reason, and a log of '
        'actions taken by Zumi moderators.\n'
        '• Checks: whether your phone number is confirmed and, for agents, the ZIEA registration number and the '
        'result of our check. Zumi does not collect ID documents, selfies or ownership documents.\n'
        '• View statistics for ads, promotions and listings: your IP address and a random device code, used only '
        'to count each person once a day. They are deleted after 2 days. Authors see only the numbers, never who '
        'viewed their listing.\n'
        '• Usage statistics: anonymous counts only — how many visits per hour, day and month, how many people '
        'come back, whether Zumi is opened on the website, Android or iPhone and which app version, and how often '
        'search filters and neighbourhoods are used. To count each person once, we keep a scrambled code of your '
        'account or device for up to 35 days. No names are stored with these numbers.\n'
        '• Error reports: when the app breaks, the text of the error (numbers and emails are removed), the platform '
        'and the app version.\n'
        '• Help articles: whether an article was helpful and your optional comment.\n'
        '• Technical data: device type, app version and error logs, to keep the app working.\n'
        '• On your device only: your saved (favourite) listings, recently viewed listings and the random '
        'device code. You can remove them by clearing the app or browser data.'
  ),
  (
    'Why we use it',
    'To run your account and show your listings; to let people contact you; to prevent scams and keep users '
        'safe; to show the "Number checked" and "Licensed agent" badges; to answer support requests; to improve the app. '
        'We do not sell your personal data.'
  ),
  (
    'Who can see what',
    '• Public: your listings (without the phone number), your name and photo, and — for agents — the agent '
        'page with agency name, "about you", licence status and reviews.\n'
        '• Phone numbers in listings and agents\' WhatsApp numbers are not public. They are shown only to '
        'signed-in users who have confirmed their own phone, one at a time when they tap "Show number" or '
        '"WhatsApp", and only up to a daily limit. Each such view is recorded.\n'
        '• Agents and owners can choose "Chat only" — then their number is not shown at all and people '
        'contact them through Zumi chat.\n'
        '• Private: your email, your personal phone number and your confirmation codes.'
  ),
  (
    'Storage and security',
    '• Where your data is stored: Zumi uses the cloud provider Supabase. Your account data, listings, photos and '
        'messages are stored on Supabase servers in the European Union (Ireland), which means outside Zambia.\n'
        '• Other services we use: Google — to send emails from Zumi (codes and messages about your account); '
        'GitHub Pages — to deliver the Zumi website; a map provider — to show maps (it sees your IP address when '
        'map images load). They receive only what they need for that job.\n'
        '• Your consent: when you create an account, you give your explicit consent to this transfer and storage of '
        'your data outside Zambia. Without it we cannot create an account, because Zumi has no servers in Zambia yet.\n'
        '• How it is protected: data in the European Union is protected by the EU General Data Protection Regulation, '
        'which gives a level of protection at least equal to the Data Protection Act No. 3 of 2021 of Zambia. On top of '
        'that, data is encrypted when it travels between your device and our servers and when it is stored; access '
        'is limited by strict rules to what each person needs; phone numbers are hidden from other users; '
        'only the Zumi team can open the team panel and every moderator action is logged.\n'
        '• If something goes wrong: if a data breach affects your data, we will inform the Data Protection '
        'Commissioner and you as required by law.\n'
        '• If the rules for keeping data in Zambia change, or the Commissioner requires it, we will move or copy the '
        'data as required.'
  ),
  (
    'How long we keep it',
    'We keep data only as long as we need it for the reason it was collected.\n'
        'Account data of active users (including checked phone numbers and licence numbers) — in protected form '
        'for as long as the account is open, to keep Zumi safe. '
        'IP addresses and device codes for ad statistics — 2 days. Phone-number view records — up to 1 year. '
        'Accounts blocked for fraud, scams or abuse: the data needed to prevent the same person from coming back '
        'and to help the police or other authorities (name, email, phone number, the reason and the evidence) is '
        'kept for up to 2 years after the block, or longer only while a police investigation or court case needs it.\n'
        'When you delete your account, your profile, listings, photos and chats are deleted within 30 days, except '
        'what the law requires us to keep or what is needed for a fraud case described above. Records of payments '
        'may be kept without your name where the law requires it.'
  ),
  (
    'Your rights',
    'Under the Data Protection Act No. 3 of 2021 you can: see and correct your data in Settings; ask for a copy '
        'of your data or ask questions through Help & support; object to or ask us to limit some uses of your data; '
        'withdraw consent for news and offers (Settings); and delete your account at any time '
        '(Settings → Delete my account). Withdrawing consent to storage outside Zambia means closing the account. '
        'You can also complain to the Data Protection Commissioner of Zambia.'
  ),
  (
    'Children',
    'Zumi is for people aged 18 and over. We do not knowingly collect data about children.'
  ),
  (
    'Contact',
    'Questions about privacy: Profile → Help & support → "My account".'
  ),
];
