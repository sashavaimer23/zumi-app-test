import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../data/images.dart';
import '../../models/models.dart';
import '../../state/app_state.dart';
import '../../theme.dart';
import '../../widgets/ads.dart';
import '../../widgets/common.dart';
import '../../widgets/promo_card.dart';
import '../../widgets/reviews.dart';
import '../../widgets/share.dart';
import '../../widgets/zicons.dart';
import '../../utils/download.dart';
import '../help/help_screen.dart';
import '../promotion/crop_dialog.dart';
import '../property_screen.dart';
import '../support/ticket_chat_screen.dart';

part 'admin_extra.dart';
part 'admin_owner.dart';

// ======================================================================
// Кабинет команды Zumi. Доступен только role = 'admin' (проверяет сервер).
// Модератор — клиенты и поддержка: обращения, жалобы, проверки, отзывы, блокировки, статьи помощи.
// Владелец — ещё реклама, статистика рекламы, общая статистика, раздел разработчика, роли, журнал.
// ======================================================================

enum _Section {
  inbox, accounts, listings, licences, reports, phones, support, reviews, help, // модератор
  ads, adStats, stats, dev, feedback, team, log, // владелец
}

/// Только для владельца Zumi (сервер тоже проверяет)
const _ownerOnly = {
  _Section.ads, _Section.adStats, _Section.stats, _Section.dev, _Section.feedback, _Section.team, _Section.log,
};

extension on _Section {
  String get label => switch (this) {
        _Section.inbox => 'Inbox',
        _Section.stats => 'Statistics',
        _Section.adStats => 'Ad statistics',
        _Section.dev => 'Developer',
        _Section.feedback => 'Feedback',
        _Section.help => 'Help articles',
        _Section.team => 'Team & roles',
        _Section.accounts => 'New accounts',
        _Section.listings => 'Listings to check',
        _Section.phones => 'Phone views',
        _Section.ads => 'Ads',
        _Section.licences => 'Licences',
        _Section.reports => 'Reports',
        _Section.support => 'Support',
        _Section.reviews => 'Reviews',
        _Section.log => 'Activity log',
      };
  IconData get icon => switch (this) {
        _Section.inbox => ZI.bell,
        _Section.stats => ZI.sort,
        _Section.adStats => ZI.eye,
        _Section.dev => ZI.settings,
        _Section.feedback => ZI.star,
        _Section.help => ZI.info,
        _Section.team => ZI.lock,
        _Section.accounts => ZI.userCircle,
        _Section.listings => ZI.house,
        _Section.phones => ZI.phone,
        _Section.ads => ZI.bolt,
        _Section.licences => ZI.badge,
        _Section.reports => ZI.flag,
        _Section.support => ZI.chat,
        _Section.reviews => ZI.sparkle,
        _Section.log => ZI.clock,
      };
}

class AdminScreen extends StatefulWidget {
  const AdminScreen({super.key});

  @override
  State<AdminScreen> createState() => _AdminScreenState();
}

class _AdminScreenState extends State<AdminScreen> {
  _Section _section = _Section.inbox;
  AdminStats _stats = const AdminStats();

  @override
  void initState() {
    super.initState();
    _refreshStats();
    // фото документов по решённым и старым заявкам удаляем из хранилища (тихо, в фоне)
    context.read<AppState>().repo.adminPurgeDocs();
  }

  Future<void> _refreshStats() async {
    try {
      final s = await context.read<AppState>().repo.adminStats();
      if (mounted) setState(() => _stats = s);
    } catch (e) {
      if (mounted) showSnack(context, '$e');
    }
  }

  void _go(_Section s) => setState(() => _section = s);

  bool get _isOwner => context.read<AppState>().user?.isOwner ?? false;

  int _badge(_Section s) => switch (s) {
        _Section.inbox => _stats.totalFor(owner: _isOwner),
        _Section.stats => 0,
        _Section.adStats => 0,
        _Section.dev => 0,
        _Section.help => _stats.helpUnhelpful,
        _Section.team => 0,
        _Section.accounts => _stats.accounts,
        _Section.listings => _stats.listingsNew,
        _Section.phones => 0,
        _Section.ads => _stats.campaignsNew, // кампании агентов со своей картинкой ждут решения
        _Section.licences => _stats.licences,
        _Section.reports => _stats.reports,
        _Section.support => _stats.tickets,
        _Section.reviews => _stats.reviews,
        _Section.log => 0,
        _Section.feedback => 0,
      };

  Widget _body() => switch (_section) {
        _Section.inbox => _Inbox(stats: _stats, onOpen: _go, onRefresh: _refreshStats, owner: _isOwner),
        _Section.stats => const _Stats(),
        _Section.adStats => const _AdStats(),
        _Section.dev => const _DevStats(),
        _Section.feedback => const _Feedback(),
        _Section.help => const _HelpAdmin(),
        _Section.team => const _Team(),
        _Section.accounts => _Accounts(onChanged: _refreshStats, onOpen: _go),
        _Section.listings => _ListingsQueue(onChanged: _refreshStats),
        _Section.phones => const _PhoneViews(),
        _Section.ads => _AdsHub(onChanged: _refreshStats, pending: _stats.campaignsNew),
        _Section.licences => _Licences(
            onChanged: _refreshStats,
            requireLicence: _stats.requireLicence,
            canChangeRule: context.read<AppState>().user?.isOwner ?? false,
          ),
        _Section.reports => _Reports(onChanged: _refreshStats),
        _Section.support => _Support(onChanged: _refreshStats),
        _Section.reviews => _Reviews(onChanged: _refreshStats),
        _Section.log => const _Log(),
      };

  @override
  Widget build(BuildContext context) {
    final user = context.watch<AppState>().user;
    if (user == null || !user.isAdmin) {
      return Scaffold(
        appBar: AppBar(),
        body: const EmptyState(icon: ZI.shield, title: 'Zumi team only', subtitle: 'This area is for the Zumi team.'),
      );
    }
    final wide = MediaQuery.sizeOf(context).width >= 900;

    final nav = [
      for (final s in _Section.values)
        if (user.isOwner || !_ownerOnly.contains(s))
        _NavItem(
          section: s,
          selected: s == _section,
          badge: _badge(s),
          onTap: () => _go(s),
          compact: !wide,
        ),
    ];

    return Scaffold(
      appBar: AppBar(
        title: Row(children: [
          const ZLogo(size: 28),
          const SizedBox(width: 10),
          Text('Zumi team · ${_section.label}', style: const TextStyle(fontSize: 18)),
        ]),
        actions: [
          IconButton(onPressed: _refreshStats, icon: const Icon(ZI.sort), tooltip: 'Refresh'),
        ],
      ),
      body: Column(children: [
        if (_stats.otpTestMode) _OtpTestBanner(onChanged: _refreshStats, canTurnOff: user.isOwner),
        Expanded(child: wide
          ? Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Container(
                width: 230,
                decoration: const BoxDecoration(border: Border(right: BorderSide(color: Zc.chip))),
                child: ListView(padding: const EdgeInsets.all(12), children: nav),
              ),
              Expanded(child: KeyedSubtree(key: ValueKey(_section), child: _body())),
            ])
          : Column(children: [
              SizedBox(
                height: 52,
                child: ListView(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  children: nav,
                ),
              ),
              const Divider(height: 1, color: Zc.chip),
              Expanded(child: KeyedSubtree(key: ValueKey(_section), child: _body())),
            ])),
      ]),
    );
  }
}

class _NavItem extends StatelessWidget {
  const _NavItem({
    required this.section,
    required this.selected,
    required this.badge,
    required this.onTap,
    required this.compact,
  });
  final _Section section;
  final bool selected;
  final int badge;
  final VoidCallback onTap;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final fg = selected ? Colors.white : Zc.text;
    return Padding(
      padding: EdgeInsets.only(bottom: compact ? 0 : 4, right: compact ? 6 : 0),
      child: Material(
        color: selected ? Zc.green : Colors.transparent,
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: onTap,
          child: Padding(
            padding: EdgeInsets.symmetric(horizontal: 12, vertical: compact ? 6 : 11),
            child: Row(mainAxisSize: compact ? MainAxisSize.min : MainAxisSize.max, children: [
              Icon(section.icon, size: 20, color: fg),
              const SizedBox(width: 10),
              compact
                  ? Text(section.label, style: TextStyle(color: fg))
                  : Expanded(child: Text(section.label, style: TextStyle(color: fg, fontSize: 15))),
              if (badge > 0) ...[
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                  decoration: BoxDecoration(color: Zc.orange, borderRadius: BorderRadius.circular(10)),
                  child: Text('$badge', style: const TextStyle(color: Colors.white, fontSize: 12)),
                ),
              ],
            ]),
          ),
        ),
      ),
    );
  }
}

// ----------------------------------------------------------------------
// Общие мелочи
// ----------------------------------------------------------------------
Future<String?> _askNote(BuildContext context, String title, List<String> presets) {
  final ctrl = TextEditingController();
  return showDialog<String>(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setS) => AlertDialog(
        title: Text(title),
        content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          Wrap(spacing: 6, runSpacing: 6, children: [
            for (final p in presets)
              ActionChip(label: Text(p), onPressed: () => setS(() => ctrl.text = p)),
          ]),
          const SizedBox(height: 10),
          TextField(controller: ctrl, maxLines: 3, decoration: const InputDecoration(hintText: 'Reason / note')),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          TextButton(onPressed: () => Navigator.pop(ctx, ctrl.text.trim()), child: const Text('Confirm')),
        ],
      ),
    ),
  );
}

class _Page extends StatelessWidget {
  const _Page({required this.title, required this.subtitle, required this.child, this.trailing});
  final String title;
  final String subtitle;
  final Widget child;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return ListView(padding: const EdgeInsets.fromLTRB(20, 18, 20, 40), children: [
      Row(children: [
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(title, style: zHeadline(context, size: 26)),
            const SizedBox(height: 4),
            Text(subtitle, style: const TextStyle(color: Zc.grey, fontSize: 14)),
          ]),
        ),
        if (trailing != null) trailing!,
      ]),
      const SizedBox(height: 18),
      child,
    ]);
  }
}

class _Card extends StatelessWidget {
  const _Card({required this.child, this.highlight = false});
  final Widget child;
  final bool highlight;

  @override
  Widget build(BuildContext context) => Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: highlight ? Zc.orange : Zc.chip, width: highlight ? 1.5 : 1),
        ),
        child: child,
      );
}

Widget _actionBtn(String label, VoidCallback onTap, {bool primary = false, bool danger = false}) {
  final bg = primary ? const Color(0xFF2E9E5B) : (danger ? const Color(0xFFD64545) : Zc.chip);
  final fg = primary || danger ? Colors.white : Zc.text;
  return TextButton(
    style: TextButton.styleFrom(
      backgroundColor: bg,
      foregroundColor: fg,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
    ),
    onPressed: onTap,
    child: Text(label),
  );
}

Widget _emptyDone(String text) => Padding(
      padding: const EdgeInsets.symmetric(vertical: 40),
      child: EmptyState(icon: ZI.checkCircle, title: 'All done', subtitle: text),
    );

/// FutureBuilder + повтор загрузки после действий
class _Loader<T> extends StatelessWidget {
  const _Loader({required this.future, required this.builder});
  final Future<T> future;
  final Widget Function(T data) builder;

  @override
  Widget build(BuildContext context) => FutureBuilder<T>(
        future: future,
        builder: (context, snap) {
          if (snap.hasError) return EmptyState(icon: ZI.warning, title: 'Could not load', subtitle: '${snap.error}');
          if (!snap.hasData) {
            return const Padding(
              padding: EdgeInsets.all(40),
              child: Center(child: CircularProgressIndicator(color: Zc.orange)),
            );
          }
          return builder(snap.data as T);
        },
      );
}

// ======================================================================
// INBOX
// ======================================================================
class _Inbox extends StatelessWidget {
  const _Inbox({required this.stats, required this.onOpen, required this.onRefresh, required this.owner});
  final AdminStats stats;
  final bool owner;
  final ValueChanged<_Section> onOpen;
  final Future<void> Function() onRefresh;

  @override
  Widget build(BuildContext context) {
    final tiles = [
      (_Section.reports, stats.reports, 'Scam & problem reports', 'Check first — people may lose money'),
      (_Section.accounts, stats.accounts, 'New accounts', 'Everyone who signed up — take a quick look'),
      (_Section.listings, stats.listingsNew, 'Listings to check', 'First listings of new people'),
      if (owner) (_Section.ads, stats.campaignsNew, 'Agent campaigns to check', 'Own pictures, names and links — in Ads'),
      (_Section.licences, stats.licences, 'Agent licences', 'Check the number with ZIEA'),
      (_Section.support, stats.tickets, 'Support requests', 'Waiting for your reply'),
      (_Section.reviews, stats.reviews, 'Flagged reviews', 'Reported by users'),
      (_Section.help, stats.helpUnhelpful, 'Help articles that did not help', 'Last 7 days — read the comments'),
    ];
    return RefreshIndicator(
      onRefresh: onRefresh,
      child: _Page(
        title: stats.totalFor(owner: owner) == 0 ? 'Nothing waiting' : '${stats.totalFor(owner: owner)} things need you',
        subtitle: '${stats.listings} active listings · ${stats.users} users',
        child: LayoutBuilder(builder: (context, c) {
          final cols = c.maxWidth > 800 ? 3 : (c.maxWidth > 500 ? 2 : 1);
          return GridView.count(
            crossAxisCount: cols,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            mainAxisSpacing: 12,
            crossAxisSpacing: 12,
            childAspectRatio: cols == 1 ? 3.6 : 2.2,
            children: [
              for (final (section, count, title, sub) in tiles)
                Material(
                  color: count > 0 ? Colors.white : const Color(0xFFFAF7F2),
                  borderRadius: BorderRadius.circular(16),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(16),
                    onTap: () => onOpen(section),
                    child: Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: count > 0 && section == _Section.reports ? Zc.orange : Zc.chip),
                      ),
                      child: Row(children: [
                        Text('$count',
                            style: TextStyle(
                                fontSize: 34,
                                fontWeight: FontWeight.w700,
                                color: count > 0 ? Zc.orange : Zc.lightGrey)),
                        const SizedBox(width: 16),
                        Expanded(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(title, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
                              Text(sub, style: const TextStyle(fontSize: 12, color: Zc.grey)),
                            ],
                          ),
                        ),
                        const Icon(ZI.caretRight, color: Zc.grey, size: 18),
                      ]),
                    ),
                  ),
                ),
            ],
          );
        }),
      ),
    );
  }
}

// ======================================================================
// NEW ACCOUNTS — каждый, кто зарегистрировался
// ======================================================================
class _Accounts extends StatefulWidget {
  const _Accounts({required this.onChanged, required this.onOpen});
  final VoidCallback onChanged;
  final ValueChanged<_Section> onOpen;

  @override
  State<_Accounts> createState() => _AccountsState();
}

class _AccountsState extends State<_Accounts> {
  bool _onlyNew = true;
  late Future<List<AccountItem>> _future = _load();

  Future<List<AccountItem>> _load() => context.read<AppState>().repo.adminAccounts(onlyNew: _onlyNew);

  Future<void> _act(AccountItem a, String action) async {
    String? note;
    if (action == 'ban') {
      note = await _askNote(context, 'Block ${a.fullName ?? 'this account'}?', [
        'Fake account',
        'Scam / asked for prepayment',
        'Pretends to be someone else',
        'Spam',
      ]);
      if (note == null) return;
    }
    try {
      await context.read<AppState>().repo.adminReviewAccount(a.id, action, note: note);
      if (!mounted) return;
      showSnack(context, action == 'ban' ? 'Account blocked' : 'Marked as checked');
      setState(() => _future = _load());
      widget.onChanged();
    } catch (e) {
      if (mounted) showSnack(context, '$e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return _Page(
      title: 'New accounts',
      subtitle: 'Everyone who signed up. Check that the name and email look real; '
          'documents and licences are in ID checks and Licences.',
      trailing: SegmentedButton<bool>(
        segments: const [
          ButtonSegment(value: true, label: Text('New')),
          ButtonSegment(value: false, label: Text('All')),
        ],
        selected: {_onlyNew},
        onSelectionChanged: (s) => setState(() {
          _onlyNew = s.first;
          _future = _load();
        }),
      ),
      child: _Loader<List<AccountItem>>(
        future: _future,
        builder: (list) {
          if (list.isEmpty) return _emptyDone('No new accounts.');
          return Column(children: [for (final a in list) _accountCard(a)]);
        },
      ),
    );
  }

  Widget _accountCard(AccountItem a) {
    Widget chip(String text, Color c) => Container(
          padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
          decoration: BoxDecoration(color: c.withAlpha(30), borderRadius: BorderRadius.circular(12)),
          child: Text(text, style: TextStyle(fontSize: 12, color: c, fontWeight: FontWeight.w500)),
        );
    const ok = Color(0xFF2E9E5B);
    const wait = Zc.orange;
    const no = Zc.grey;
    const bad = Color(0xFFD64545);
    final id = switch (a.idStatus) {
      'approved' => chip('ID ✓', ok),
      'pending' => chip('ID waiting', wait),
      'rejected' => chip('ID rejected', bad),
      _ => chip('No ID yet', no),
    };
    return _Card(
      highlight: a.reviewedAt == null,
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          ZAvatar(url: a.avatarUrl, name: a.fullName ?? a.email, size: 44),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(a.fullName ?? 'No name', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
              SelectableText(
                [if (a.email != null) a.email!, if ((a.phone ?? '').isNotEmpty) a.phone!].join(' · '),
                style: const TextStyle(fontSize: 13, color: Zc.grey),
              ),
              Text('${a.isAgent ? 'Agent' : 'Owner'} · signed up ${timeAgo(a.createdAt)} · ${a.listings} listings',
                  style: const TextStyle(fontSize: 12, color: Zc.grey)),
            ]),
          ),
        ]),
        const SizedBox(height: 10),
        Wrap(spacing: 6, runSpacing: 6, children: [
          a.phoneVerified ? chip('Phone ✓', ok) : chip('Phone not confirmed', no),
          id,
          if (a.isAgent)
            a.licenceVerified
                ? chip('ZIEA ✓', ok)
                : (a.licenceNo != null ? chip('ZIEA ${a.licenceNo} waiting', wait) : chip('No ZIEA number', no)),
          if (a.banned) chip('Blocked', bad),
        ]),
        if (!a.banned && a.reviewedAt == null) ...[
          const SizedBox(height: 12),
          Wrap(spacing: 10, runSpacing: 8, children: [
            _actionBtn('Looks OK', () => _act(a, 'ok'), primary: true),
            if (a.isAgent && a.licenceNo != null && !a.licenceVerified)
              _actionBtn('Open licence', () => widget.onOpen(_Section.licences)),
            _actionBtn('Block', () => _act(a, 'ban'), danger: true),
          ]),
        ],
        if (a.isAgent && !a.banned && (context.read<AppState>().user?.isOwner ?? false)) ...[
          const SizedBox(height: 8),
          TextButton.icon(
            onPressed: () => _grantPromotion(context, a),
            icon: const Icon(ZI.bolt, size: 18, color: Zc.orange),
            label: const Text('Give free promotion', style: TextStyle(color: Zc.orange)),
          ),
        ],
      ]),
    );
  }
}

// ======================================================================
// LICENCES (ZIEA)
// ======================================================================
class _Licences extends StatefulWidget {
  const _Licences({required this.onChanged, required this.requireLicence, required this.canChangeRule});
  final VoidCallback onChanged;
  final bool requireLicence;
  final bool canChangeRule; // правило меняет только владелец

  @override
  State<_Licences> createState() => _LicencesState();
}

class _LicencesState extends State<_Licences> {
  late Future<List<LicenceItem>> _future = context.read<AppState>().repo.adminLicenceQueue();
  late bool _require = widget.requireLicence;

  @override
  void didUpdateWidget(covariant _Licences old) {
    super.didUpdateWidget(old);
    if (old.requireLicence != widget.requireLicence) _require = widget.requireLicence;
  }

  Future<void> _setRequire(bool on) async {
    try {
      await context.read<AppState>().repo.adminSetRequireLicence(on);
      if (!mounted) return;
      setState(() => _require = on);
      showSnack(context, on
          ? 'From now on agents publish only after their licence is checked'
          : 'Agents can publish before the check (with the "licence not verified" label)');
      widget.onChanged();
    } catch (e) {
      if (mounted) showSnack(context, '$e');
    }
  }

  Future<void> _decide(LicenceItem l, bool approve) async {
    String? note;
    if (!approve) {
      note = await _askNote(context, 'Reject licence', ['Number not found at ZIEA', 'Name does not match', 'Licence expired']);
      if (note == null) return;
    }
    try {
      await context.read<AppState>().repo.adminReviewLicence(l.userId, approve, note: note);
      if (!mounted) return;
      setState(() => _future = context.read<AppState>().repo.adminLicenceQueue());
      widget.onChanged();
    } catch (e) {
      if (mounted) showSnack(context, '$e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return _Page(
      title: 'Agent licences',
      subtitle: 'Check the number with the Zambia Institute of Estate Agents, then approve.',
      trailing: TextButton.icon(
        onPressed: () => launchUrl(Uri.parse('https://www.ziea.org/'), mode: LaunchMode.externalApplication),
        icon: const Icon(ZI.globe, color: Zc.green),
        label: const Text('Open ZIEA', style: TextStyle(color: Zc.green)),
      ),
      child: _Loader<List<LicenceItem>>(
        future: _future,
        builder: (list) {
          final rule = _Card(
            child: SwitchListTile(
              contentPadding: EdgeInsets.zero,
              activeThumbColor: Zc.orange,
              value: _require,
              onChanged: widget.canChangeRule ? _setRequire : null,
              title: const Text('Publish only after the licence check',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
              subtitle: const Text(
                'Off: agents without a checked licence can publish, their listings show "ZIEA licence not verified". '
                'On: they cannot publish new listings until you approve the licence. '
                'Promotion is always only for agents with a checked licence.',
                style: TextStyle(fontSize: 12, color: Zc.grey, height: 1.35),
              ),
            ),
          );
          if (list.isEmpty) return Column(children: [rule, _emptyDone('No licences waiting.')]);
          return Column(children: [
            rule,
            for (final l in list)
              _Card(
                child: Row(children: [
                  const Icon(ZI.badge, color: Zc.green, size: 28),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(l.userName ?? 'Agent', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
                      SelectableText('ZIEA no. ${l.licenceNo}', style: const TextStyle(fontSize: 14)),
                    ]),
                  ),
                  Wrap(spacing: 8, children: [
                    _actionBtn('Approve', () => _decide(l, true), primary: true),
                    _actionBtn('Reject', () => _decide(l, false)),
                  ]),
                ]),
              ),
          ]);
        },
      ),
    );
  }
}

// ======================================================================
// REPORTS (scam / problems)
// ======================================================================
class _Reports extends StatefulWidget {
  const _Reports({required this.onChanged});
  final VoidCallback onChanged;

  @override
  State<_Reports> createState() => _ReportsState();
}

class _ReportsState extends State<_Reports> {
  bool _onlyNew = true;
  late Future<List<ReportItem>> _future = _load();

  Future<List<ReportItem>> _load() => context.read<AppState>().repo.adminReports(onlyNew: _onlyNew);

  Future<void> _resolve(ReportItem r, String action) async {
    String? note;
    if (action != 'dismiss') {
      note = await _askNote(
        context,
        action == 'ban' ? 'Block the author and hide all their listings?' : 'Hide this listing?',
        ['Asked for money before viewing', 'Fake listing / not their property', 'Wrong information', 'Duplicate'],
      );
      if (note == null) return;
    }
    try {
      await context.read<AppState>().repo.adminResolveReport(r.id, action, note: note);
      if (!mounted) return;
      showSnack(context, switch (action) {
        'hide' => 'Listing hidden',
        'ban' => 'Author blocked',
        _ => 'Marked as OK',
      });
      setState(() => _future = _load());
      widget.onChanged();
    } catch (e) {
      if (mounted) showSnack(context, '$e');
    }
  }

  Future<void> _restore(ReportItem r) async {
    try {
      await context.read<AppState>().repo.adminRestoreListing(r.propertyId);
      if (!mounted) return;
      showSnack(context, 'Listing is visible again');
      setState(() => _future = _load());
    } catch (e) {
      if (mounted) showSnack(context, '$e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return _Page(
      title: 'Reports',
      subtitle: 'Scams and problems reported by users. Prepayment requests are the most common scam.',
      trailing: FilterChip(
        label: const Text('Only new'),
        selected: _onlyNew,
        onSelected: (v) => setState(() {
          _onlyNew = v;
          _future = _load();
        }),
      ),
      child: _Loader<List<ReportItem>>(
        future: _future,
        builder: (list) {
          if (list.isEmpty) return _emptyDone('No reports.');
          return Column(children: [
            for (final r in list)
              _Card(
                highlight: r.status == 'new' && (r.reason == 'scam' || r.reason == 'asked_prepayment'),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    SizedBox(width: 90, height: 70, child: PropImage(r.propertyCover, radius: 10)),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text(r.propertyTitle ?? 'Listing',
                            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
                        Text('By ${r.ownerName ?? 'unknown'} · listing ${r.propertyStatus ?? ''}',
                            style: const TextStyle(fontSize: 12, color: Zc.grey)),
                        const SizedBox(height: 6),
                        Wrap(spacing: 6, runSpacing: 4, children: [
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                            decoration: BoxDecoration(color: Zc.orangeSoft, borderRadius: BorderRadius.circular(8)),
                            child: Text(reportReasons[r.reason] ?? r.reason,
                                style: const TextStyle(fontSize: 12, color: Zc.orange, fontWeight: FontWeight.w600)),
                          ),
                          if (r.totalReports > 1)
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                              decoration: BoxDecoration(color: const Color(0xFFFDE2E2), borderRadius: BorderRadius.circular(8)),
                              child: Text('${r.totalReports} reports',
                                  style: const TextStyle(fontSize: 12, color: Color(0xFFD64545))),
                            ),
                        ]),
                      ]),
                    ),
                    Text(timeAgo(r.createdAt), style: const TextStyle(fontSize: 12, color: Zc.grey)),
                  ]),
                  if ((r.details ?? '').isNotEmpty) ...[
                    const SizedBox(height: 10),
                    Text('“${r.details}”', style: const TextStyle(fontSize: 14, fontStyle: FontStyle.italic)),
                  ],
                  Text('Reported by ${r.reporterName ?? 'user'}', style: const TextStyle(fontSize: 12, color: Zc.grey)),
                  const SizedBox(height: 12),
                  if (r.status == 'new')
                    Wrap(spacing: 10, runSpacing: 8, children: [
                      _actionBtn('All OK', () => _resolve(r, 'dismiss')),
                      _actionBtn('Hide listing', () => _resolve(r, 'hide'), danger: true),
                      _actionBtn('Block author', () => _resolve(r, 'ban'), danger: true),
                    ])
                  else
                    Row(children: [
                      Text(r.status == 'reviewed' ? 'Resolved: all OK' : 'Resolved: action taken',
                          style: const TextStyle(color: Zc.grey)),
                      const Spacer(),
                      if (r.propertyStatus == 'archived')
                        TextButton(onPressed: () => _restore(r), child: const Text('Show listing again')),
                    ]),
                ]),
              ),
          ]);
        },
      ),
    );
  }
}

// ======================================================================
// SUPPORT
// ======================================================================
class _Support extends StatefulWidget {
  const _Support({required this.onChanged});
  final VoidCallback onChanged;

  @override
  State<_Support> createState() => _SupportState();
}

class _SupportState extends State<_Support> {
  String? _status = 'open';
  late Future<List<SupportTicket>> _future = _load();

  Future<List<SupportTicket>> _load() => context.read<AppState>().repo.adminTickets(status: _status);

  @override
  Widget build(BuildContext context) {
    return _Page(
      title: 'Support requests',
      subtitle: 'Reply like in a chat. Quick replies are above the message box.',
      trailing: SegmentedButton<String?>(
        segments: const [
          ButtonSegment(value: 'open', label: Text('Waiting')),
          ButtonSegment(value: 'answered', label: Text('Answered')),
          ButtonSegment(value: null, label: Text('All')),
        ],
        selected: {_status},
        onSelectionChanged: (s) => setState(() {
          _status = s.first;
          _future = _load();
        }),
      ),
      child: _Loader<List<SupportTicket>>(
        future: _future,
        builder: (list) {
          if (list.isEmpty) return _emptyDone('No requests here.');
          return Column(children: [
            for (final t in list)
              _Card(
                highlight: t.status == 'open' && t.category == 'scam',
                child: InkWell(
                  onTap: () async {
                    await Navigator.push(
                      context,
                      MaterialPageRoute(builder: (_) => TicketChatScreen(ticket: t, asStaff: true)),
                    );
                    if (!mounted) return;
                    setState(() => _future = _load());
                    widget.onChanged();
                  },
                  child: Row(children: [
                    CircleAvatar(
                      backgroundColor: t.status == 'open' ? Zc.orangeSoft : Zc.chip,
                      child: Icon(t.category == 'scam' ? ZI.flag : ZI.chat,
                          color: t.status == 'open' ? Zc.orange : Zc.green),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text(t.subject, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
                        Text('${t.userName ?? 'User'} · ${ticketCategories[t.category] ?? t.category}',
                            style: const TextStyle(fontSize: 12, color: Zc.grey)),
                        const SizedBox(height: 4),
                        Text(t.lastMessage ?? '', maxLines: 2, overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontSize: 13)),
                      ]),
                    ),
                    const SizedBox(width: 8),
                    Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                      Text(timeAgo(t.lastMessageAt), style: const TextStyle(fontSize: 12, color: Zc.grey)),
                      const SizedBox(height: 4),
                      Text(t.status, style: TextStyle(fontSize: 12, color: t.status == 'open' ? Zc.orange : Zc.grey)),
                    ]),
                  ]),
                ),
              ),
          ]);
        },
      ),
    );
  }
}

// ======================================================================
// REVIEWS
// ======================================================================
class _Reviews extends StatefulWidget {
  const _Reviews({required this.onChanged});
  final VoidCallback onChanged;

  @override
  State<_Reviews> createState() => _ReviewsState();
}

class _ReviewsState extends State<_Reviews> {
  bool _flaggedOnly = true;
  late Future<List<Review>> _future = _load();

  Future<List<Review>> _load() => context.read<AppState>().repo.adminReviews(flaggedOnly: _flaggedOnly);

  Future<void> _act(Review r, String action) async {
    String? reply;
    if (action == 'reply') {
      reply = await _askNote(context, 'Public reply from Zumi', [
        'Thank you for your feedback! We have contacted the agent.',
        'We are sorry about your experience. Our team is checking this listing.',
        'Thank you! We are glad everything went well.',
      ]);
      if (reply == null) return;
    }
    try {
      await context.read<AppState>().repo.adminModerateReview(r.id, action, reply: reply);
      if (!mounted) return;
      setState(() => _future = _load());
      widget.onChanged();
    } catch (e) {
      if (mounted) showSnack(context, '$e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return _Page(
      title: 'Reviews',
      subtitle: 'Hide insults, fake reviews and personal data. Reply publicly as the Zumi team.',
      trailing: FilterChip(
        label: const Text('Reported only'),
        selected: _flaggedOnly,
        onSelected: (v) => setState(() {
          _flaggedOnly = v;
          _future = _load();
        }),
      ),
      child: _Loader<List<Review>>(
        future: _future,
        builder: (list) {
          if (list.isEmpty) return _emptyDone('No reviews to check.');
          return Column(children: [
            for (final r in list)
              _Card(
                highlight: r.flagsCount > 0 && r.status == 'published',
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Row(children: [
                    Stars(value: r.rating.toDouble(), size: 16),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text('${r.authorName ?? 'User'} · ${timeAgo(r.createdAt)}',
                          style: const TextStyle(fontSize: 12, color: Zc.grey)),
                    ),
                    if (r.flagsCount > 0)
                      Text('${r.flagsCount} reports', style: const TextStyle(fontSize: 12, color: Color(0xFFD64545))),
                    if (r.status == 'hidden')
                      const Padding(
                        padding: EdgeInsets.only(left: 8),
                        child: Text('hidden', style: TextStyle(fontSize: 12, color: Zc.grey)),
                      ),
                  ]),
                  const SizedBox(height: 8),
                  Text(r.body ?? '(no text)', style: const TextStyle(fontSize: 14, height: 1.4)),
                  if (r.zumiReply != null) ...[
                    const SizedBox(height: 6),
                    Text('Zumi: ${r.zumiReply}', style: const TextStyle(fontSize: 13, color: Zc.green)),
                  ],
                  const SizedBox(height: 12),
                  Wrap(spacing: 10, runSpacing: 8, children: [
                    if (r.status == 'published') _actionBtn('Hide', () => _act(r, 'hide'), danger: true),
                    if (r.status == 'hidden' || r.flagsCount > 0)
                      _actionBtn(r.status == 'hidden' ? 'Publish again' : 'Keep (OK)', () => _act(r, 'publish'),
                          primary: true),
                    _actionBtn('Reply as Zumi', () => _act(r, 'reply')),
                  ]),
                ]),
              ),
          ]);
        },
      ),
    );
  }
}

// ======================================================================
// ACTIVITY LOG
// ======================================================================
class _Log extends StatelessWidget {
  const _Log();

  @override
  Widget build(BuildContext context) {
    return _Page(
      title: 'Activity log',
      subtitle: 'Every decision of the team, newest first.',
      child: _Loader<List<AuditEntry>>(
        future: context.read<AppState>().repo.adminAudit(),
        builder: (list) {
          if (list.isEmpty) return _emptyDone('No actions yet.');
          return Column(children: [
            for (final a in list)
              ListTile(
                dense: true,
                leading: Icon(
                  switch (a.action) {
                    'approve' || 'publish' || 'dismiss' || 'restore' || 'unban' => ZI.checkCircle,
                    'reply' || 'answered' => ZI.chat,
                    _ => ZI.flag,
                  },
                  color: Zc.green,
                ),
                title: Text('${a.adminName ?? 'Admin'} · ${a.action} ${a.targetType}'),
                subtitle: Text([a.targetId, if ((a.note ?? '').isNotEmpty) a.note].join(' — '),
                    maxLines: 2, overflow: TextOverflow.ellipsis),
                trailing: Text(timeAgo(a.createdAt), style: const TextStyle(fontSize: 12, color: Zc.grey)),
              ),
          ]);
        },
      ),
    );
  }
}
