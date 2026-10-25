import 'package:flutter/material.dart';

import '../theme.dart';

/// Условия использования и Политика конфиденциальности.
///
/// ВАЖНО: это черновики. Перед запуском их должен проверить юрист в Замбии.
/// Когда тексты будут проверены — поставьте kLegalDraft = false (плашка «Draft» исчезнет).
const kLegalDraft = true;
const kLegalUpdated = '25 October 2026';

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
        'agent and is not a party to any deal between users. Any agreement, payment or lease is made directly '
        'between you and the other person.'
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
        '• A listing that has not been confirmed as available for 60 days is hidden from search until you confirm it.'
  ),
  (
    '4. Safety rules',
    'It is not allowed to:\n'
        '• ask for any deposit, "viewing fee" or "booking fee" before the person has seen the property;\n'
        '• publish fake listings or pretend to be someone else;\n'
        '• refuse people because of tribe, religion, gender, disability or nationality;\n'
        '• send spam, insults or threats, or share other people\'s personal data;\n'
        '• use Zumi for anything illegal.\n'
        'Never pay before you have seen the property in person and checked who the owner is.'
  ),
  (
    '5. Verified badge',
    'The Verified badge means that the Zumi team checked the person\'s phone number and identity document '
        '(and, for agents, ZIEA registration) at the time of the check. It does not guarantee the property, '
        'the price or the outcome of a deal. Always view the property and check documents yourself.'
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
    'Zumi provides the platform "as is". We do our best to keep it safe and working, but we are not '
        'responsible for the content users publish or for deals between users, to the extent allowed by law.'
  ),
  (
    '10. Changes and law',
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
        '• Listings: photos, description, price, location on the map, contact number you add.\n'
        '• Messages you send in Zumi chats and to support.\n'
        '• Phone-number views: when you open a phone or WhatsApp number, we record who opened whose number and '
        'when. This protects agents and owners from spam and lets us find bots.\n'
        '• Confirmation codes: the phone number or email we sent a code to, when, and how many attempts were '
        'made (the code itself is stored only in protected, scrambled form).\n'
        '• Safety records: reports about listings or reviews, blocked accounts and the reason, and a log of '
        'actions taken by Zumi moderators.\n'
        '• Verification (only if you choose to get verified): photo of your NRC or passport and a selfie; '
        'for the on-site check — photos and your location at that moment.\n'
        '• Ad and promotion statistics: your IP address and a random device code, used only to count each '
        'person once a day for views and clicks. They are deleted after 2 days.\n'
        '• Usage statistics: anonymous counts only — how many visits per hour and per day, and how often search '
        'filters and neighbourhoods are used. No names are stored with these numbers.\n'
        '• Help articles: whether an article was helpful and your optional comment.\n'
        '• Technical data: device type, app version and error logs, to keep the app working.\n'
        '• On your device only: your saved (favourite) listings, recently viewed listings and the random '
        'device code. You can remove them by clearing the app or browser data.'
  ),
  (
    'Why we use it',
    'To run your account and show your listings; to let people contact you; to prevent scams and keep users '
        'safe; to check identity for the Verified badge; to answer support requests; to improve the app. '
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
        '• Private: your email, your personal phone number and your confirmation codes.\n'
        '• Verification documents are stored privately and seen only by the Zumi verification team.'
  ),
  (
    'Storage and security',
    'Data is stored with our cloud provider (Supabase) and may be processed on servers outside Zambia with '
        'the safeguards required by the Data Protection Act. Access is protected and limited to what each person needs.'
  ),
  (
    'How long we keep it',
    'Account data — until you delete the account. Verification photos (documents, selfie, on-site photos) — '
        'deleted as soon as the team approves or rejects the check, and in any case within 30 days if no decision '
        'is made; we keep only the result (status, date, who checked it and the reason if rejected). '
        'IP addresses and device codes for ad statistics — 2 days. Phone-number view records and safety records — '
        'as long as needed to protect users. '
        'When you delete your account, your profile, listings, photos and chats are deleted. Records of payments '
        'may be kept without your name where the law requires it.'
  ),
  (
    'Your rights',
    'You can see and correct your data in Settings, download a copy or ask questions through Help & support, '
        'withdraw consent for verification, and delete your account at any time (Settings → Delete my account). '
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
