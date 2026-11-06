import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../config.dart';
import '../models/models.dart';
import '../state/app_state.dart';
import '../theme.dart';
import '../widgets/back_to_top.dart';
import '../widgets/common.dart';
import '../widgets/results.dart';
import '../widgets/share.dart';
import '../widgets/trust.dart';
import '../widgets/wide_card.dart';
import '../widgets/zicons.dart';
import 'auth_screen.dart';
import 'public_profile_screen.dart';

void openAgency(BuildContext context, String agencyId) =>
    Navigator.push(context, MaterialPageRoute(builder: (_) => AgencyScreen(agencyId: agencyId)));

/// Страница агентства: название, проверка фирмы, агенты и все их объявления.
/// Владелец агентства отсюда же управляет: приглашения, состав, данные компании.
class AgencyScreen extends StatefulWidget {
  const AgencyScreen({super.key, required this.agencyId});
  final String agencyId;

  @override
  State<AgencyScreen> createState() => _AgencyScreenState();
}

class _AgencyScreenState extends State<AgencyScreen> {
  late Future<(AgencyPage?, List<Property>)> _future = _load();

  Future<(AgencyPage?, List<Property>)> _load() async {
    final repo = context.read<AppState>().repo;
    final a = await repo.agencyPage(widget.agencyId);
    if (a == null) return (null, const <Property>[]);
    return (a, await repo.agencyListings(a));
  }

  void _reload() => setState(() => _future = _load());

  Future<void> _leave(AgencyPage a) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text('Leave ${a.name}?'),
        content: const Text('Your listings stay yours and stay online. You will use your own listing limit again.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          TextButton(onPressed: () => Navigator.pop(context, true), child: const Text('Leave')),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    try {
      await context.read<AppState>().repo.leaveAgency();
      if (!mounted) return;
      showSnack(context, 'You left the agency');
      _reload();
    } catch (e) {
      if (mounted) showSnack(context, '$e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final desk = isDesktop(context);
    final side = desk ? desktopSide(context) : 20.0;
    return Scaffold(
      body: BackToTop(
        bottom: 24,
        child: FutureBuilder<(AgencyPage?, List<Property>)>(
          future: _future,
          builder: (context, snap) {
            if (snap.connectionState != ConnectionState.done) {
              return const Center(child: CircularProgressIndicator(color: Zc.orange));
            }
            final a = snap.hasError ? null : snap.data!.$1;
            if (a == null) {
              return const SafeArea(
                child: Column(children: [
                  Align(alignment: Alignment.centerLeft, child: BackButton(color: Zc.green)),
                  Expanded(
                    child: EmptyState(
                        icon: ZI.users, title: 'Agency not found', subtitle: 'It may have been closed.'),
                  ),
                ]),
              );
            }
            final listings = snap.data!.$2;
            return SafeArea(
              bottom: false,
              child: CustomScrollView(slivers: [
                SliverToBoxAdapter(
                  child: Padding(
                    padding: EdgeInsets.fromLTRB(desk ? side - 12 : 8, 8, desk ? side - 12 : 8, 0),
                    child: Row(children: [
                      const BackButton(color: Zc.green),
                      const Spacer(),
                      IconButton(
                        tooltip: 'Share',
                        onPressed: () => showShareSheet(
                          context,
                          text: '${a.name} on Zumi — ${a.activeListings} listings in Zambia',
                          link: AppConfig.siteUrl == null ? null : '${AppConfig.siteUrl}/?agency=${a.id}',
                        ),
                        icon: const Icon(ZI.share, color: Zc.green),
                      ),
                    ]),
                  ),
                ),
                SliverPadding(
                  padding: EdgeInsets.fromLTRB(side, 6, side, 0),
                  sliver: SliverToBoxAdapter(child: _AgencyHeader(a: a)),
                ),
                if (a.isOwner)
                  SliverPadding(
                    padding: EdgeInsets.fromLTRB(side, 18, side, 0),
                    sliver: SliverToBoxAdapter(
                      child: _OwnerTools(a: a, onChanged: _reload),
                    ),
                  ),
                if ((a.about ?? '').isNotEmpty)
                  SliverPadding(
                    padding: EdgeInsets.fromLTRB(side, 22, side, 0),
                    sliver: SliverToBoxAdapter(
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        const _H('About'),
                        Text(a.about!, style: const TextStyle(fontSize: 15, height: 1.45)),
                      ]),
                    ),
                  ),
                // ---------- агенты ----------
                SliverPadding(
                  padding: EdgeInsets.fromLTRB(side, 24, side, 8),
                  sliver: SliverToBoxAdapter(child: _H('Agents (${a.members.length})')),
                ),
                SliverPadding(
                  padding: EdgeInsets.symmetric(horizontal: side),
                  sliver: SliverList.list(children: [
                    for (final m in a.members)
                      _MemberTile(
                        m: m,
                        canRemove: a.isOwner && !m.isOwner,
                        onRemoved: _reload,
                      ),
                  ]),
                ),
                // ---------- объявления ----------
                SliverPadding(
                  padding: EdgeInsets.fromLTRB(side, 24, side, 14),
                  sliver: SliverToBoxAdapter(child: _H('Listings (${listings.length})')),
                ),
                if (listings.isEmpty)
                  const SliverToBoxAdapter(
                    child: Padding(
                      padding: EdgeInsets.symmetric(vertical: 20),
                      child: Text('No active listings right now.',
                          textAlign: TextAlign.center, style: TextStyle(color: Zc.grey)),
                    ),
                  )
                else
                  SliverPadding(
                    padding: EdgeInsets.symmetric(horizontal: desk ? side : 16),
                    sliver: SliverList.builder(
                      itemCount: listings.length,
                      itemBuilder: (_, i) => desk
                          ? PropertyWideCard(p: listings[i], onTap: () => openProperty(context, listings[i]))
                          : PropertyCard(p: listings[i], onTap: () => openProperty(context, listings[i])),
                    ),
                  ),
                if (a.isMember && !a.isOwner)
                  SliverPadding(
                    padding: EdgeInsets.fromLTRB(side, 20, side, 0),
                    sliver: SliverToBoxAdapter(
                      child: Center(
                        child: TextButton.icon(
                          onPressed: () => _leave(a),
                          icon: const Icon(ZI.signOut, color: Zc.grey, size: 18),
                          label: const Text('Leave this agency', style: TextStyle(color: Zc.grey)),
                        ),
                      ),
                    ),
                  ),
                const SliverToBoxAdapter(child: SizedBox(height: 60)),
              ]),
            );
          },
        ),
      ),
    );
  }
}

class _H extends StatelessWidget {
  const _H(this.text);
  final String text;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Text(text, style: zHeadline(context, size: 20)),
      );
}

class _AgencyHeader extends StatelessWidget {
  const _AgencyHeader({required this.a});
  final AgencyPage a;

  @override
  Widget build(BuildContext context) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [
        ZAvatar(url: a.logoUrl, name: a.name, size: 84),
        const SizedBox(width: 16),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(a.name, style: zHeadline(context, size: 26)),
            const SizedBox(height: 4),
            const Text('Real estate agency', style: TextStyle(color: Zc.grey, fontSize: 15)),
          ]),
        ),
      ]),
      const SizedBox(height: 16),
      Wrap(spacing: 8, runSpacing: 8, children: [
        if (a.verified) const VerifiedBadge(compact: true, label: 'Registered firm (ZIEA)'),
        _Chip(icon: ZI.users, text: '${a.members.length} ${a.members.length == 1 ? 'agent' : 'agents'}'),
        _Chip(icon: ZI.house, text: '${a.activeListings} active ${a.activeListings == 1 ? 'listing' : 'listings'}'),
        if (a.createdAt != null) _Chip(icon: ZI.calendar, text: 'On Zumi since ${formatMonthYear(a.createdAt!)}'),
      ]),
    ]);
  }
}

class _Chip extends StatelessWidget {
  const _Chip({required this.icon, required this.text});
  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(color: Zc.chip, borderRadius: BorderRadius.circular(12)),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(icon, size: 15, color: Zc.green),
          const SizedBox(width: 6),
          Text(text, style: const TextStyle(fontSize: 13, color: Zc.green)),
        ]),
      );
}

class _MemberTile extends StatelessWidget {
  const _MemberTile({required this.m, required this.canRemove, required this.onRemoved});
  final AgencyMember m;
  final bool canRemove;
  final VoidCallback onRemoved;

  Future<void> _remove(BuildContext context) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text('Remove ${m.name} from the agency?'),
        content: const Text('Their listings stay theirs and stay online.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          TextButton(onPressed: () => Navigator.pop(context, true), child: const Text('Remove')),
        ],
      ),
    );
    if (ok != true || !context.mounted) return;
    try {
      await context.read<AppState>().repo.agencyRemoveMember(m.id);
      onRemoved();
    } catch (e) {
      if (context.mounted) showSnack(context, '$e');
    }
  }

  @override
  Widget build(BuildContext context) => Material(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => PublicProfileScreen(userId: m.id))),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            child: Row(children: [
              ZAvatar(url: m.avatarUrl, name: m.name, size: 42),
              const SizedBox(width: 12),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(m.isOwner ? '${m.name} · head of agency' : m.name,
                      style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
                  Text(
                    [
                      if (m.licensed) 'Licensed agent',
                      '${m.listings} ${m.listings == 1 ? 'listing' : 'listings'}',
                    ].join(' · '),
                    style: const TextStyle(fontSize: 13, color: Zc.grey),
                  ),
                ]),
              ),
              if (canRemove)
                IconButton(
                  tooltip: 'Remove from agency',
                  onPressed: () => _remove(context),
                  icon: const Icon(ZI.close, size: 18, color: Zc.grey),
                )
              else
                const Icon(ZI.caretRight, size: 18, color: Zc.grey),
            ]),
          ),
        ),
      ).withBottom(8);
}

extension on Widget {
  Widget withBottom(double b) => Padding(padding: EdgeInsets.only(bottom: b), child: this);
}

/// Владелец агентства: общий лимит, приглашение агентов, данные компании
class _OwnerTools extends StatefulWidget {
  const _OwnerTools({required this.a, required this.onChanged});
  final AgencyPage a;
  final VoidCallback onChanged;

  @override
  State<_OwnerTools> createState() => _OwnerToolsState();
}

class _OwnerToolsState extends State<_OwnerTools> {
  late final Future<Quota> _quota = context.read<AppState>().repo.myQuota();
  bool _inviting = false;

  Future<void> _invite() async {
    setState(() => _inviting = true);
    try {
      final code = await context.read<AppState>().repo.agencyInvite();
      if (!mounted) return;
      final link = agencyInviteLink(code);
      await showModalBottomSheet<void>(
        context: context,
        backgroundColor: Zc.bg,
        builder: (_) => SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(22, 22, 22, 18),
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('Invite an agent', style: zHeadline(context, size: 22)),
              const SizedBox(height: 6),
              const Text(
                  'Send this link to ONE agent. They open it, sign in with an agent account and join your agency. '
                  'The link works once and for 14 days.',
                  style: TextStyle(color: Zc.grey, fontSize: 14, height: 1.4)),
              const SizedBox(height: 14),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12)),
                child: SelectableText(link, style: const TextStyle(fontSize: 14, color: Zc.green)),
              ),
              const SizedBox(height: 14),
              Row(children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () {
                      Clipboard.setData(ClipboardData(text: link));
                      showSnack(context, 'Link copied');
                    },
                    icon: const Icon(ZI.copy, size: 18),
                    label: const Text('Copy'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: FilledButton.icon(
                    style: FilledButton.styleFrom(backgroundColor: Zc.orange),
                    onPressed: () => showShareSheet(context,
                        text: 'Join ${widget.a.name} on Zumi — list your properties with our agency:', link: link),
                    icon: const Icon(ZI.share, size: 18),
                    label: const Text('Send'),
                  ),
                ),
              ]),
            ]),
          ),
        ),
      );
    } catch (e) {
      if (mounted) showSnack(context, '$e');
    } finally {
      if (mounted) setState(() => _inviting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final a = widget.a;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(color: Zc.greenTint, borderRadius: BorderRadius.circular(16)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Text('Your agency', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
        const SizedBox(height: 6),
        FutureBuilder<Quota>(
          future: _quota,
          builder: (_, s) => Text(
            s.hasData
                ? 'Shared listing limit: ${s.data!.used} of ${s.data!.allowed} used by all your agents.'
                : 'Shared listing limit for all your agents.',
            style: const TextStyle(fontSize: 14),
          ),
        ),
        if (!a.verified) ...[
          const SizedBox(height: 6),
          Text(
            (a.firmLicenceNo ?? '').isEmpty
                ? 'Add your ZIEA firm registration number — once we check it, the limit grows from 30 to 50 '
                    'and you get the "Registered firm" badge.'
                : 'We are checking your firm registration (${a.firmLicenceNo}). After that the limit grows to 50.',
            style: const TextStyle(fontSize: 13, color: Zc.orange, fontWeight: FontWeight.w600, height: 1.35),
          ),
        ],
        const SizedBox(height: 14),
        Wrap(spacing: 10, runSpacing: 10, children: [
          FilledButton.icon(
            style: FilledButton.styleFrom(backgroundColor: Zc.orange),
            onPressed: _inviting ? null : _invite,
            icon: const Icon(ZI.link, size: 18),
            label: const Text('Invite an agent'),
          ),
          OutlinedButton.icon(
            onPressed: () async {
              final changed = await showAgencyEditor(context, a: a);
              if (changed == true) widget.onChanged();
            },
            icon: const Icon(ZI.edit, size: 18),
            label: const Text('Edit agency'),
          ),
        ]),
      ]),
    );
  }
}

/// Создать агентство (для агента без агентства) или изменить данные (владелец)
Future<bool?> showAgencyEditor(BuildContext context, {AgencyPage? a}) {
  final name = TextEditingController(text: a?.name ?? '');
  final firm = TextEditingController(text: a?.firmLicenceNo ?? '');
  final phone = TextEditingController(text: a?.phone ?? '');
  final about = TextEditingController(text: a?.about ?? '');
  var saving = false;
  return showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Zc.bg,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setS) => Padding(
        padding: EdgeInsets.fromLTRB(22, 22, 22, MediaQuery.viewInsetsOf(ctx).bottom + 18),
        child: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(a == null ? 'Create an agency' : 'Edit agency', style: zHeadline(ctx, size: 22)),
            if (a == null) ...[
              const SizedBox(height: 6),
              const Text(
                  'You become the head of the agency. Invite your agents with a link — the agency gets one page '
                  'and one shared listing limit (30 free, 50 once we check the firm registration).',
                  style: TextStyle(color: Zc.grey, fontSize: 14, height: 1.4)),
            ],
            const SizedBox(height: 16),
            TextField(controller: name, decoration: const InputDecoration(labelText: 'Agency name *')),
            const SizedBox(height: 12),
            TextField(
              controller: firm,
              textCapitalization: TextCapitalization.characters,
              decoration: const InputDecoration(labelText: 'ZIEA firm registration number'),
            ),
            if (a != null) ...[
              const SizedBox(height: 12),
              TextField(
                  controller: phone,
                  keyboardType: TextInputType.phone,
                  decoration: const InputDecoration(labelText: 'Office phone')),
              const SizedBox(height: 12),
              TextField(
                controller: about,
                minLines: 3,
                maxLines: 6,
                maxLength: 600,
                decoration: const InputDecoration(labelText: 'About the agency'),
              ),
            ],
            const SizedBox(height: 16),
            PrimaryButton(
              label: a == null ? 'Create agency' : 'Save',
              width: double.infinity,
              loading: saving,
              onPressed: () async {
                if (name.text.trim().length < 2) {
                  showSnack(ctx, 'Enter the agency name');
                  return;
                }
                setS(() => saving = true);
                final repo = ctx.read<AppState>().repo;
                try {
                  if (a == null) {
                    await repo.createAgency(name: name.text.trim(), firmLicenceNo: firm.text.trim());
                  } else {
                    await repo.updateAgency(
                        name: name.text.trim(), firmLicenceNo: firm.text.trim(), phone: phone.text.trim(),
                        about: about.text.trim());
                  }
                  if (ctx.mounted) Navigator.pop(ctx, true);
                } catch (e) {
                  if (ctx.mounted) showSnack(ctx, '$e');
                  setS(() => saving = false);
                }
              },
            ),
          ]),
        ),
      ),
    ),
  );
}

/// Ссылка-приглашение ?join=КОД: показать агентство и вступить
Future<void> showJoinAgency(BuildContext context, String code) async {
  final app = context.read<AppState>();
  AgencyInviteInfo? info;
  try {
    info = await app.repo.agencyInviteInfo(code);
  } catch (_) {}
  if (!context.mounted) return;
  if (info == null || !info.valid) {
    showSnack(context, 'This invite link is not valid or was already used. Ask the agency for a new one.');
    return;
  }
  final inv = info;
  await showDialog<void>(
    context: context,
    builder: (ctx) {
      final u = ctx.watch<AppState>().user;
      final canJoin = u != null && (u.isAgent || u.isAdmin) && u.agencyId == null;
      return AlertDialog(
        title: Text('Join ${inv.name}?'),
        content: Text(
          u == null
              ? 'Sign in with your agent account to join this agency on Zumi.'
              : !(u.isAgent || u.isAdmin)
                  ? 'Only agent accounts can join an agency. Your account is an owner account.'
                  : u.agencyId != null
                      ? 'You are already in an agency. Leave it first (open your agency page → Leave).'
                      : 'Your listings will show the agency name, and the agency shares one listing limit. '
                          'You can leave at any time.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Not now')),
          if (u == null)
            TextButton(
              onPressed: () => Navigator.push(ctx, MaterialPageRoute(builder: (_) => const AuthScreen())),
              child: const Text('Sign in'),
            ),
          if (canJoin)
            TextButton(
              onPressed: () async {
                try {
                  final id = await ctx.read<AppState>().repo.joinAgency(code);
                  if (!ctx.mounted) return;
                  Navigator.pop(ctx);
                  showSnack(context, 'Welcome to ${inv.name}!');
                  if (context.mounted) openAgency(context, id);
                } catch (e) {
                  if (ctx.mounted) showSnack(ctx, '$e');
                }
              },
              child: const Text('Join'),
            ),
        ],
      );
    },
  );
}

/// Профиль агента: «Моё агентство» — открыть, создать или вступить по коду
class AgencyProfileCard extends StatelessWidget {
  const AgencyProfileCard({super.key});

  @override
  Widget build(BuildContext context) {
    final u = context.watch<AppState>().user;
    if (u == null || !u.isAgent) return const SizedBox.shrink();
    if (u.agencyId != null) {
      return Padding(
        padding: const EdgeInsets.only(top: 10),
        child: OutlinedButton.icon(
          style: OutlinedButton.styleFrom(
            foregroundColor: Zc.green,
            side: const BorderSide(color: Zc.green),
            minimumSize: const Size.fromHeight(48),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
          ),
          onPressed: () => openAgency(context, u.agencyId!),
          icon: const Icon(ZI.users, size: 18),
          label: Text((u.agencyName ?? '').isEmpty ? 'My agency' : 'My agency · ${u.agencyName}'),
        ),
      );
    }
    return Padding(
      padding: const EdgeInsets.only(top: 10),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Row(children: [
            Icon(ZI.users, color: Zc.green, size: 20),
            SizedBox(width: 8),
            Text('Work in an agency?', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
          ]),
          const SizedBox(height: 4),
          const Text('Create your agency page and invite your agents, or join your agency with its invite link.',
              style: TextStyle(fontSize: 13, color: Zc.grey, height: 1.35)),
          const SizedBox(height: 10),
          Wrap(spacing: 10, runSpacing: 8, children: [
            TextButton(
              onPressed: () async {
                final ok = await showAgencyEditor(context);
                if (ok == true && context.mounted) {
                  final id = context.read<AppState>().user?.agencyId;
                  showSnack(context, 'Agency created — now invite your agents');
                  if (id != null) openAgency(context, id);
                }
              },
              child: const Text('Create an agency'),
            ),
            TextButton(
              onPressed: () async {
                final c = TextEditingController();
                final code = await showDialog<String>(
                  context: context,
                  builder: (ctx) => AlertDialog(
                    title: const Text('Join an agency'),
                    content: TextField(
                      controller: c,
                      textCapitalization: TextCapitalization.characters,
                      decoration: const InputDecoration(
                          hintText: 'Invite code, e.g. 7F3K9Q2B', helperText: 'Or just open the invite link'),
                    ),
                    actions: [
                      TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
                      TextButton(onPressed: () => Navigator.pop(ctx, c.text.trim()), child: const Text('Next')),
                    ],
                  ),
                );
                if ((code ?? '').isNotEmpty && context.mounted) {
                  // из ссылки берём только код
                  final m = RegExp(r'join=([A-Za-z0-9]+)').firstMatch(code!);
                  await showJoinAgency(context, m?.group(1) ?? code);
                }
              },
              child: const Text('Join with a code'),
            ),
          ]),
        ]),
      ),
    );
  }
}
