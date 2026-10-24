import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../config.dart';
import '../models/models.dart';
import '../state/app_state.dart';
import '../theme.dart';
import '../widgets/common.dart';
import '../widgets/contact.dart';
import '../widgets/results.dart';
import '../widgets/reviews.dart';
import '../widgets/share.dart';
import '../widgets/trust.dart';
import '../widgets/wide_card.dart';
import '../widgets/zicons.dart';

/// Публичная страница человека.
///  • Агент — как витрина агентства: фото, агентство, проверки, рейтинг, «о себе»,
///    каталог объявлений и отзывы клиентов.
///  • Собственник — коротко: фото, имя, проверка и его объявления.
class PublicProfileScreen extends StatefulWidget {
  const PublicProfileScreen({super.key, required this.userId});

  /// id пользователя (или 'demo:Имя' для демо-объявлений)
  final String userId;

  @override
  State<PublicProfileScreen> createState() => _PublicProfileScreenState();
}

class _PublicProfileScreenState extends State<PublicProfileScreen> {
  late Future<List<dynamic>> _future;

  @override
  void initState() {
    super.initState();
    _load();
  }

  void _load() {
    final repo = context.read<AppState>().repo;
    _future = Future.wait<dynamic>([
      repo.publicProfile(widget.userId),
      repo.listingsBy(widget.userId),
      repo.ratingOf(widget.userId),
    ]);
  }

  void _share(PublicProfile pr) {
    final site = AppConfig.siteUrl;
    final who = pr.isAgent ? (pr.agencyName ?? pr.displayName) : pr.displayName;
    showShareSheet(
      context,
      text: '$who on Zumi — ${pr.activeListings} ${pr.activeListings == 1 ? 'listing' : 'listings'} in Zambia',
      link: site == null || widget.userId.startsWith('demo:') ? null : '$site/?agent=${widget.userId}',
    );
  }

  @override
  Widget build(BuildContext context) {
    final desk = isDesktop(context);
    final side = desk ? desktopSide(context) : 20.0;

    return Scaffold(
      body: FutureBuilder<List<dynamic>>(
        future: _future,
        builder: (context, snap) {
          if (snap.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator(color: Zc.orange));
          }
          final pr = snap.hasError ? null : snap.data![0] as PublicProfile?;
          if (pr == null) {
            return SafeArea(
              child: Column(children: [
                Align(alignment: Alignment.centerLeft, child: BackButton(color: Zc.green)),
                const Expanded(
                  child: EmptyState(
                    icon: ZI.userCircle,
                    title: 'Profile not available',
                    subtitle: 'This account may have been removed.',
                  ),
                ),
              ]),
            );
          }
          final listings = snap.data![1] as List<Property>;
          final rating = snap.data![2] as Rating;

          return SafeArea(
            bottom: false,
            child: CustomScrollView(slivers: [
              // ---------- шапка ----------
              SliverToBoxAdapter(
                child: Padding(
                  padding: EdgeInsets.fromLTRB(desk ? side - 12 : 8, 8, desk ? side - 12 : 8, 0),
                  child: Row(children: [
                    const BackButton(color: Zc.green),
                    const Spacer(),
                    IconButton(
                      tooltip: 'Share',
                      onPressed: () => _share(pr),
                      icon: const Icon(ZI.share, color: Zc.green),
                    ),
                  ]),
                ),
              ),
              SliverPadding(
                padding: EdgeInsets.fromLTRB(side, 6, side, 0),
                sliver: SliverToBoxAdapter(child: _Header(pr: pr, rating: rating)),
              ),
              if (pr.isAgent && (pr.bio ?? '').isNotEmpty)
                SliverPadding(
                  padding: EdgeInsets.fromLTRB(side, 22, side, 0),
                  sliver: SliverToBoxAdapter(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      const _H('About'),
                      Text(pr.bio!, style: const TextStyle(fontSize: 15, height: 1.45)),
                    ]),
                  ),
                ),
              if (pr.isAgent && pr.hasWhatsapp && pr.contactMode != 'chat')
                SliverPadding(
                  padding: EdgeInsets.fromLTRB(side, 18, side, 0),
                  sliver: SliverToBoxAdapter(
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: OutlinedButton.icon(
                        style: OutlinedButton.styleFrom(
                          foregroundColor: Zc.green,
                          side: const BorderSide(color: Zc.green),
                          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                        ),
                        onPressed: () => Contact.agentWhatsapp(context, pr),
                        icon: const Icon(ZI.whatsapp),
                        label: const Text('WhatsApp the agent'),
                      ),
                    ),
                  ),
                ),

              // ---------- объявления ----------
              SliverPadding(
                padding: EdgeInsets.fromLTRB(side, 28, side, 14),
                sliver: SliverToBoxAdapter(
                  child: _H(pr.isAgent ? 'Listings (${listings.length})' : 'Listings by ${pr.displayName}'),
                ),
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

              // ---------- отзывы (агенты) ----------
              if (pr.isAgent)
                SliverPadding(
                  padding: EdgeInsets.fromLTRB(side, 12, side, 0),
                  sliver: SliverToBoxAdapter(
                    child: ReviewsSection(targetId: widget.userId, name: pr.agencyName ?? pr.displayName),
                  ),
                ),
              const SliverToBoxAdapter(child: SizedBox(height: 60)),
            ]),
          );
        },
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.pr, required this.rating});
  final PublicProfile pr;
  final Rating rating;

  @override
  Widget build(BuildContext context) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
        ZAvatar(url: pr.avatarUrl, name: pr.displayName, size: 84),
        const SizedBox(width: 16),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Flexible(child: Text(pr.displayName, style: zHeadline(context, size: 26))),
              if (pr.verified) ...[const SizedBox(width: 8), const VerifiedMark(size: 20)],
            ]),
            const SizedBox(height: 4),
            Text(
              pr.isAgent
                  ? ((pr.agencyName ?? '').isNotEmpty ? 'Real estate agent · ${pr.agencyName}' : 'Real estate agent')
                  : 'Property owner',
              style: const TextStyle(color: Zc.grey, fontSize: 15),
            ),
            if (pr.isAgent && rating.count > 0) ...[
              const SizedBox(height: 6),
              Row(children: [
                Stars(value: rating.average, size: 16),
                const SizedBox(width: 6),
                Text('${rating.average.toStringAsFixed(1)} · ${rating.count} ${rating.count == 1 ? 'review' : 'reviews'}',
                    style: const TextStyle(fontSize: 13, color: Zc.text)),
              ]),
            ],
          ]),
        ),
      ]),
      const SizedBox(height: 16),
      Wrap(spacing: 8, runSpacing: 8, children: [
        if (pr.verified) const VerifiedBadge(compact: true),
        if (pr.isAgent && pr.licenceVerified) const _Chip(icon: ZI.badge, text: 'ZIEA licence checked'),
        if (pr.isAgent && !pr.licenceVerified) const LicenceWarning(),
        if (pr.phoneVerified) const _Chip(icon: ZI.mobile, text: 'Phone confirmed'),
        if (pr.memberSince != null) _Chip(icon: ZI.calendar, text: 'On Zumi since ${formatMonthYear(pr.memberSince!)}'),
        _Chip(icon: ZI.house, text: '${pr.activeListings} active ${pr.activeListings == 1 ? 'listing' : 'listings'}'),
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
        decoration: BoxDecoration(color: Zc.chip, borderRadius: BorderRadius.circular(20)),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(icon, size: 15, color: Zc.green),
          const SizedBox(width: 6),
          Text(text, style: const TextStyle(fontSize: 12, color: Zc.green, fontWeight: FontWeight.w500)),
        ]),
      );
}

class _H extends StatelessWidget {
  const _H(this.text);
  final String text;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: Text(text, style: const TextStyle(fontSize: 21, fontWeight: FontWeight.w600, color: Zc.green)),
      );
}
