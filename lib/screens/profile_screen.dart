import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../config.dart';
import '../models/models.dart';
import '../state/app_state.dart';
import '../theme.dart';
import '../widgets/common.dart';
import '../widgets/results.dart';
import '../widgets/share.dart';
import '../widgets/trust.dart';
import 'admin/admin_screen.dart';
import 'post/post_wizard.dart';
import 'promotion/promotion_screen.dart';
import 'public_profile_screen.dart';
import 'settings_screen.dart';
import 'support/support_screen.dart';
import 'verify/get_verified_screen.dart';
import 'verify/verify_listing_screen.dart';
import 'auth_screen.dart';
import 'shell.dart';
import '../widgets/zicons.dart';

/// Профиль: роль, лимит бесплатных объявлений, мои объявления, выход.
class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  String _key = '';
  Future<List<dynamic>>? _future;

  void _reload(AppState app) {
    final u = app.user!;
    _future = Future.wait<dynamic>([
      app.repo.myQuota(),
      app.repo.myListings(),
      if (u.isAgent) app.repo.ratingOf(u.id),
    ]);
  }

  void _openSettings() => Navigator.push(context, MaterialPageRoute(builder: (_) => const SettingsScreen()));

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final user = app.user;
    if (user == null) return const AuthScreen(embedded: true);

    final key = '${user.id}#${app.dataVersion}';
    if (key != _key) {
      _key = key;
      _reload(app);
    }

    return Scaffold(
      body: SafeArea(
        child: RefreshIndicator(
          color: Zc.orange,
          onRefresh: () async {
            setState(() => _reload(app));
            await _future;
          },
          child: ListView(
            padding: const EdgeInsets.fromLTRB(22, 18, 22, Shell.navSpace + 20),
            children: [
              Row(children: [
                Expanded(child: Text('Profile', style: zHeadline(context, size: 40))),
                IconButton(
                  tooltip: 'Settings',
                  onPressed: _openSettings,
                  icon: const Icon(ZI.settings, color: Zc.green, size: 28),
                ),
              ]),
              const SizedBox(height: 18),
              InkWell(
                borderRadius: BorderRadius.circular(16),
                onTap: _openSettings,
                child: Row(children: [
                  Stack(clipBehavior: Clip.none, children: [
                    ZAvatar(url: user.avatarUrl, name: user.fullName ?? user.email, size: 68),
                    Positioned(
                      right: -2,
                      bottom: -2,
                      child: Container(
                        padding: const EdgeInsets.all(5),
                        decoration: BoxDecoration(
                          color: Zc.orange,
                          shape: BoxShape.circle,
                          border: Border.all(color: Zc.bg, width: 2),
                        ),
                        child: const Icon(ZI.camera, size: 13, color: Colors.white),
                      ),
                    ),
                  ]),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Row(children: [
                        Flexible(
                          child: Text(user.fullName ?? 'No name',
                              style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w600)),
                        ),
                        if (user.identityVerified) ...[const SizedBox(width: 6), const VerifiedMark(size: 18)],
                      ]),
                      if (user.isAgent && (user.agencyName ?? '').isNotEmpty)
                        Text(user.agencyName!, style: const TextStyle(color: Zc.text)),
                      if (user.email != null) Text(user.email!, style: const TextStyle(color: Zc.grey)),
                      const SizedBox(height: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
                        decoration: BoxDecoration(color: Zc.orangeSoft, borderRadius: BorderRadius.circular(12)),
                        child: Text(user.isAdmin ? 'Zumi team' : (user.isAgent ? 'Agent' : 'Owner'),
                            style: const TextStyle(color: Zc.orange, fontSize: 12, fontWeight: FontWeight.w600)),
                      ),
                    ]),
                  ),
                ]),
              ),
              const SizedBox(height: 26),
              FutureBuilder<List<dynamic>>(
                future: _future,
                builder: (context, snap) {
                  if (snap.connectionState != ConnectionState.done) {
                    return const Padding(
                      padding: EdgeInsets.all(40),
                      child: Center(child: CircularProgressIndicator(color: Zc.orange)),
                    );
                  }
                  if (snap.hasError) {
                    return EmptyState(icon: ZI.warning, title: 'Could not load', subtitle: '${snap.error}');
                  }
                  final quota = snap.data![0] as Quota;
                  final listings = snap.data![1] as List<Property>;
                  final rating = user.isAgent && snap.data!.length > 2 ? snap.data![2] as Rating : null;
                  final hidden = listings.where((p) => p.status == 'active' && !p.isFresh).length;
                  return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                    // агент: своя страница-витрина с каталогом и отзывами
                    if (user.isAgent) ...[
                      _AgentPageCard(user: user, listings: listings, rating: rating),
                      const SizedBox(height: 14),
                    ],
                    _IdentityCard(isAgent: user.isAgent),
                    const SizedBox(height: 14),
                    _QuotaCard(quota: quota),
                    if (hidden > 0) ...[
                      const SizedBox(height: 14),
                      Container(
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(color: Zc.orangeSoft, borderRadius: BorderRadius.circular(14)),
                        child: Row(children: [
                          const Icon(ZI.hidden, color: Zc.orange),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              hidden == 1
                                  ? '1 listing is hidden from search: it was not confirmed for 60 days. '
                                      'Tap … → Confirm still available.'
                                  : '$hidden listings are hidden from search: they were not confirmed for 60 days. '
                                      'Tap … → Confirm still available.',
                              style: const TextStyle(fontSize: 13, height: 1.35),
                            ),
                          ),
                        ]),
                      ),
                    ],
                    const SizedBox(height: 28),
                    Row(children: [
                      Expanded(
                        child: Text(user.isAgent ? 'My catalog' : 'My listings',
                            style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w600, color: Zc.green)),
                      ),
                      TextButton.icon(
                        onPressed: () => Shell.of(context)?.go(2),
                        icon: const Icon(ZI.plus, color: Zc.orange),
                        label: const Text('New', style: TextStyle(color: Zc.orange)),
                      ),
                    ]),
                    const SizedBox(height: 8),
                    if (listings.isEmpty)
                      const Padding(
                        padding: EdgeInsets.symmetric(vertical: 24),
                        child: Text("You haven't listed anything yet.",
                            textAlign: TextAlign.center, style: TextStyle(color: Zc.grey)),
                      ),
                    for (final p in listings) _MyListingTile(p: p),
                  ]);
                },
              ),
              const SizedBox(height: 24),
              if (user.isAdmin)
                _MenuTile(
                  icon: ZI.shieldFill,
                  title: 'Zumi team panel',
                  subtitle: 'ID checks, reports, support, reviews',
                  highlight: true,
                  onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const AdminScreen())),
                ),
              if (user.isAgent || user.isAdmin)
                _MenuTile(
                  icon: ZI.bolt,
                  title: 'Promotion',
                  subtitle: 'Campaigns that show your listings first · views and clicks',
                  onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const PromotionScreen())),
                ),
              _MenuTile(
                icon: ZI.settings,
                title: 'Settings',
                subtitle: user.isAgent
                    ? 'Photo, agency, about you, WhatsApp, password'
                    : 'Photo, name, phone, password',
                onTap: _openSettings,
              ),
              _MenuTile(
                icon: ZI.chat,
                title: 'Help & support',
                subtitle: 'Questions, problems or a suspicious listing',
                onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const SupportScreen())),
              ),
              const SizedBox(height: 16),
              OutlinedButton.icon(
                style: OutlinedButton.styleFrom(
                  foregroundColor: Zc.green,
                  side: const BorderSide(color: Zc.green),
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                ),
                onPressed: () => app.repo.signOut(),
                icon: const Icon(ZI.signOut),
                label: const Text('Sign out'),
              ),
              const SizedBox(height: 14),
              Text(
                app.repo.isDemo ? 'Demo mode · data is stored on this phone only' : 'Connected to Zumi server',
                textAlign: TextAlign.center,
                style: const TextStyle(color: Zc.grey, fontSize: 12),
              ),
            ],
          ),
        ),
      ),
    );
  }
}


class _QuotaCard extends StatelessWidget {
  const _QuotaCard({required this.quota});
  final Quota quota;

  @override
  Widget build(BuildContext context) {
    final double frac = quota.allowed == 0 ? 1.0 : (quota.used / quota.allowed).clamp(0.0, 1.0).toDouble();
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(color: Zc.green, borderRadius: BorderRadius.circular(18)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Text('Free listings', style: TextStyle(color: Zc.navInactive, fontSize: 14)),
        const SizedBox(height: 4),
        Text('${quota.used} of ${quota.allowed} used',
            style: const TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.w600)),
        const SizedBox(height: 12),
        ClipRRect(
          borderRadius: BorderRadius.circular(6),
          child: LinearProgressIndicator(
            value: frac,
            minHeight: 8,
            backgroundColor: const Color(0x33FFFFFF),
            color: Zc.orange,
          ),
        ),
        const SizedBox(height: 14),
        Row(children: [
          Expanded(
            child: Text(
              quota.reached ? 'Limit reached — buy an extra slot to post more.' : '${quota.left} free left',
              style: const TextStyle(color: Colors.white, fontSize: 13),
            ),
          ),
          TextButton(
            style: TextButton.styleFrom(backgroundColor: Zc.orange, foregroundColor: Colors.white),
            onPressed: () => showSnack(context, 'Payments are coming soon (Mobile Money and cards).'),
            child: const Text('Buy more'),
          ),
        ]),
      ]),
    );
  }
}

class _MyListingTile extends StatelessWidget {
  const _MyListingTile({required this.p});
  final Property p;

  @override
  Widget build(BuildContext context) {
    final app = context.read<AppState>();
    final active = p.status == 'active';
    final stale = active && !p.isFresh;
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Zc.lightGrey),
      ),
      child: InkWell(
        onTap: () => openProperty(context, p),
        child: Row(children: [
          SizedBox(width: 78, height: 78, child: PropImage(p.coverThumb, radius: 10)),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(p.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w600)),
              const SizedBox(height: 2),
              Text(p.priceLabel, style: const TextStyle(color: Zc.orange, fontSize: 13)),
              const SizedBox(height: 4),
              Row(children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(
                    color: stale ? Zc.orangeSoft : (active ? Zc.greenTint : Zc.chip),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(stale ? 'Hidden · confirm' : _statusLabel(p.status),
                      style: TextStyle(fontSize: 11, color: stale ? Zc.orange : Zc.green)),
                ),
                const SizedBox(width: 8),
                Text('${p.viewsCount} views', style: const TextStyle(fontSize: 11, color: Zc.grey)),
                if (p.isPromoted) ...[const SizedBox(width: 8), const Icon(ZI.bolt, size: 14, color: Zc.orange)],
                if (p.isVerified) ...[const SizedBox(width: 8), const VerifiedMark(size: 14)],
              ]),
              if (p.isPending)
                const Padding(
                  padding: EdgeInsets.only(top: 4),
                  child: Text('The Zumi team checks first listings — usually about 15 minutes.',
                      style: TextStyle(fontSize: 11, color: Zc.grey)),
                ),
              if (p.status == 'archived' && (p.moderationNote ?? '').isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text('Not approved: ${p.moderationNote}. Edit the listing and publish again.',
                      style: const TextStyle(fontSize: 11, color: Color(0xFFD64545))),
                ),
            ]),
          ),
          PopupMenuButton<String>(
            icon: const Icon(ZI.more, color: Zc.green),
            onSelected: (v) async {
              try {
                switch (v) {
                  case 'edit':
                    final changed = await Navigator.push<bool>(
                      context,
                      MaterialPageRoute(builder: (_) => PostWizard(editing: p)),
                    );
                    if (changed != true) return;
                  case 'share':
                    showShareSheet(
                      context,
                      text: p.shareText(null),
                      link: AppConfig.siteUrl == null ? null : '${AppConfig.siteUrl}/?listing=${p.id}',
                    );
                    return;
                  case 'promote':
                    if (app.user?.isAgent ?? false) {
                      await Navigator.push(context, MaterialPageRoute(builder: (_) => const PromotionScreen()));
                    } else {
                      showSnack(context, 'Promotion will be available with payments (coming soon).');
                    }
                    return;
                  case 'verify':
                    await Navigator.push(
                      context,
                      MaterialPageRoute(builder: (_) => VerifyListingScreen(property: p)),
                    );
                  case 'confirm':
                    await app.repo.confirmListing(p.id);
                    if (context.mounted) showSnack(context, 'Thanks! People will see that the listing is up to date.');
                  case 'archive':
                    await app.repo.setListingStatus(p.id, p.dealType == DealType.sale ? 'sold' : 'rented');
                  case 'activate':
                    await app.repo.setListingStatus(p.id, 'active');
                  case 'delete':
                    final ok = await showDialog<bool>(
                      context: context,
                      builder: (ctx) => AlertDialog(
                        title: const Text('Delete listing?'),
                        content: const Text('This cannot be undone.'),
                        actions: [
                          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
                          TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Delete')),
                        ],
                      ),
                    );
                    if (ok != true) return;
                    await app.repo.deleteListing(p.id);
                }
                app.dataChanged();
              } catch (e) {
                if (context.mounted) showSnack(context, '$e');
              }
            },
            itemBuilder: (_) => [
              const PopupMenuItem(value: 'edit', child: Text('Edit')),
              if (active) const PopupMenuItem(value: 'share', child: Text('Share')),
              if (active) const PopupMenuItem(value: 'promote', child: Text('Promote to top')),
              if (active) PopupMenuItem(value: 'verify', child: Text(p.isVerified ? 'Verification' : 'Get the Verified badge')),
              if (active) const PopupMenuItem(value: 'confirm', child: Text('Confirm still available')),
              if (active)
                PopupMenuItem(
                  value: 'archive',
                  child: Text(p.dealType == DealType.sale ? 'Mark as sold' : 'Mark as rented'),
                ),
              if (!active && !p.isPending)
                PopupMenuItem(
                  value: 'activate',
                  child: Text((p.moderationNote ?? '').isNotEmpty ? 'Send for review again' : 'Publish again'),
                ),
              const PopupMenuItem(value: 'delete', child: Text('Delete')),
            ],
          ),
        ]),
      ),
    );
  }

  String _statusLabel(String s) => switch (s) {
        'active' => 'Active',
        'sold' => 'Sold',
        'rented' => 'Rented',
        'draft' => 'Draft',
        'pending' => 'Under review',
        _ => 'Archived',
      };
}

/// Агент: своя страница с каталогом и отзывами — посмотреть и поделиться
class _AgentPageCard extends StatelessWidget {
  const _AgentPageCard({required this.user, required this.listings, required this.rating});
  final AppUser user;
  final List<Property> listings;
  final Rating? rating;

  @override
  Widget build(BuildContext context) {
    final active = listings.where((p) => p.status == 'active').length;
    final views = listings.fold<int>(0, (a, p) => a + p.viewsCount);
    final r = rating;
    final site = AppConfig.siteUrl;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Zc.chip),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Row(children: [
          Icon(ZI.storefront, color: Zc.green),
          SizedBox(width: 8),
          Text('My agent page', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600, color: Zc.green)),
        ]),
        const SizedBox(height: 4),
        const Text('Your catalog and client reviews — share it with clients instead of sending listings one by one.',
            style: TextStyle(fontSize: 13, color: Zc.grey, height: 1.35)),
        const SizedBox(height: 14),
        Row(children: [
          _Stat(value: '$active', label: 'active'),
          _Stat(value: '$views', label: 'views'),
          _Stat(
            value: r == null || r.count == 0 ? '—' : r.average.toStringAsFixed(1),
            label: r == null || r.count == 0 ? 'no reviews yet' : '${r.count} ${r.count == 1 ? 'review' : 'reviews'}',
            star: r != null && r.count > 0,
          ),
        ]),
        const SizedBox(height: 14),
        Row(children: [
          Expanded(
            child: OutlinedButton(
              style: OutlinedButton.styleFrom(
                foregroundColor: Zc.green,
                side: const BorderSide(color: Zc.green),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              ),
              onPressed: () => Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => PublicProfileScreen(userId: user.id)),
              ),
              child: const Text('View my page'),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: FilledButton.icon(
              style: FilledButton.styleFrom(
                backgroundColor: Zc.orange,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              ),
              onPressed: () => showShareSheet(
                context,
                text: '${user.agencyName ?? user.fullName ?? 'My'} listings on Zumi',
                link: site == null ? null : '$site/?agent=${user.id}',
              ),
              icon: const Icon(ZI.share, size: 18),
              label: const Text('Share'),
            ),
          ),
        ]),
      ]),
    );
  }
}

class _Stat extends StatelessWidget {
  const _Stat({required this.value, required this.label, this.star = false});
  final String value;
  final String label;
  final bool star;

  @override
  Widget build(BuildContext context) => Expanded(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Text(value, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w600, color: Zc.text)),
            if (star) ...[const SizedBox(width: 2), const Icon(Icons.star_rounded, size: 20, color: Color(0xFFF5A623))],
          ]),
          Text(label, style: const TextStyle(fontSize: 12, color: Zc.grey)),
        ]),
      );
}

/// Карточка «Get verified» с прогрессом — ведёт на чек-лист
class _IdentityCard extends StatelessWidget {
  const _IdentityCard({required this.isAgent});
  final bool isAgent;

  @override
  Widget build(BuildContext context) {
    final u = context.watch<AppState>().user;
    if (u == null) return const SizedBox.shrink();
    final (done, total) = u.verificationProgress;
    final verified = u.identityVerified;

    return Material(
      color: verified ? const Color(0x142E9E5B) : Colors.white,
      borderRadius: BorderRadius.circular(18),
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const GetVerifiedScreen())),
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: verified ? Colors.transparent : Zc.orange.withAlpha(90)),
          ),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              const VerifiedBadge(compact: true),
              const Spacer(),
              Text(verified ? 'Done' : '$done of $total',
                  style: TextStyle(fontWeight: FontWeight.w600, color: verified ? const Color(0xFF2E9E5B) : Zc.orange)),
              const SizedBox(width: 4),
              const Icon(ZI.caretRight, size: 18, color: Zc.grey),
            ]),
            const SizedBox(height: 10),
            Text(
              verified ? 'You are Verified' : 'Get the Verified badge',
              style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w600, color: Zc.green),
            ),
            const SizedBox(height: 2),
            Text(
              verified
                  ? 'The badge is shown on all your listings.'
                  : 'Confirm your phone and ID once — about 3 minutes. Verified ${isAgent ? 'agents' : 'owners'} get more calls.',
              style: const TextStyle(fontSize: 13, color: Zc.grey, height: 1.35),
            ),
            if (!verified) ...[
              const SizedBox(height: 12),
              ClipRRect(
                borderRadius: BorderRadius.circular(6),
                child: LinearProgressIndicator(
                  value: done / total,
                  minHeight: 6,
                  backgroundColor: Zc.chip,
                  color: Zc.orange,
                ),
              ),
            ],
          ]),
        ),
      ),
    );
  }
}

class _MenuTile extends StatelessWidget {
  const _MenuTile({required this.icon, required this.title, required this.subtitle, required this.onTap, this.highlight = false});
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;
  final bool highlight;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Material(
        color: highlight ? Zc.green : Colors.white,
        borderRadius: BorderRadius.circular(16),
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: onTap,
          child: Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(16),
              border: highlight ? null : Border.all(color: Zc.chip),
            ),
            child: Row(children: [
              Icon(icon, color: highlight ? Colors.white : Zc.green, size: 26),
              const SizedBox(width: 14),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(title,
                      style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: highlight ? Colors.white : Zc.text)),
                  Text(subtitle, style: TextStyle(fontSize: 13, color: highlight ? Zc.navInactive : Zc.grey)),
                ]),
              ),
              Icon(ZI.caretRight, color: highlight ? Colors.white : Zc.grey, size: 18),
            ]),
          ),
        ),
      ),
    );
  }
}
