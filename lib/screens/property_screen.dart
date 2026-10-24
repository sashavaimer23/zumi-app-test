import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:provider/provider.dart';

import '../config.dart';
import '../models/models.dart';
import '../state/app_state.dart';
import '../theme.dart';
import '../widgets/ads.dart';
import '../widgets/common.dart';
import '../widgets/contact.dart';
import '../widgets/gallery.dart';
import '../widgets/reviews.dart';
import '../widgets/share.dart';
import '../widgets/trust.dart';
import '../widgets/wide_card.dart';
import 'auth_screen.dart';
import 'chat_screen.dart';
import 'public_profile_screen.dart';
import '../widgets/zicons.dart';

/// Страница объявления: галерея, цена, характеристики, описание, удобства, карта, контакты.
class PropertyScreen extends StatefulWidget {
  const PropertyScreen({super.key, required this.property});
  final Property property;

  @override
  State<PropertyScreen> createState() => _PropertyScreenState();
}

class _PropertyScreenState extends State<PropertyScreen> {
  int _page = 0;
  bool _chatLoading = false;

  Property get p => widget.property;

  @override
  void initState() {
    super.initState();
    _profileId = p.ownerId ?? (context.read<AppState>().repo.isDemo ? reviewTargetFor(p) : null);
    WidgetsBinding.instance.addPostFrameCallback((_) => context.read<AppState>().markViewed(p.id));
  }

  void _share() => showShareSheet(
        context,
        text: p.shareText(null),
        link: AppConfig.siteUrl == null || p.isDemo ? null : '${AppConfig.siteUrl}/?listing=${p.id}',
      );

  /// Страница автора: у агента — каталог и отзывы, у собственника — коротко
  String? _profileId;

  void _openAuthor() {
    final id = _profileId;
    if (id == null) return;
    Navigator.push(context, MaterialPageRoute(builder: (_) => PublicProfileScreen(userId: id)));
  }

  Future<void> _chat() async {
    final app = context.read<AppState>();
    if (!app.signedIn) {
      final ok = await Navigator.push<bool>(context, MaterialPageRoute(builder: (_) => const AuthScreen()));
      if (ok != true || !mounted) return;
    }
    setState(() => _chatLoading = true);
    try {
      final id = await app.repo.startConversation(p.id);
      app.chatsChanged();
      if (!mounted) return;
      Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => ChatScreen(conversationId: id, title: p.contactName ?? p.title)),
      );
    } catch (e) {
      if (mounted) showSnack(context, '$e');
    } finally {
      if (mounted) setState(() => _chatLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final images = p.images.isEmpty ? <String?>[null] : p.images;
    final top = MediaQuery.paddingOf(context).top;
    final desk = isDesktop(context);
    final side = desk ? desktopSide(context) : 22.0;

    return Scaffold(
      body: CustomScrollView(slivers: [
        // ---------- галерея: компьютер — большое фото + 3 справа ----------
        if (desk)
          SliverPadding(
            padding: EdgeInsets.fromLTRB(side, 18, side, 0),
            sliver: SliverToBoxAdapter(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  TextButton.icon(
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(ZI.back, size: 18, color: Zc.green),
                    label: const Text('Back to search', style: TextStyle(color: Zc.green, fontSize: 15)),
                  ),
                  const Spacer(),
                  _CircleIcon(icon: ZI.share, onTap: _share),
                  const SizedBox(width: 10),
                  FavButton(propertyId: p.id, size: 42),
                ]),
                const SizedBox(height: 10),
                DesktopGallery(
                  images: images,
                  height: (MediaQuery.sizeOf(context).width * 0.36).clamp(380.0, 560.0),
                  badges: [
                    if (p.isVerified) ...[const VerifiedBadge(), const SizedBox(width: 8)],
                    if (p.isPromoted) const PromotedBadge(),
                  ],
                ),
              ]),
            ),
          )
        // ---------- телефон: листаемые фото на всю ширину ----------
        else
        SliverToBoxAdapter(
          child: SizedBox(
            height: MediaQuery.sizeOf(context).width * 0.78 + top,
            child: Stack(fit: StackFit.expand, children: [
              PageView.builder(
                itemCount: images.length,
                onPageChanged: (i) => setState(() => _page = i),
                itemBuilder: (_, i) => GestureDetector(
                  onTap: () => openGalleryViewer(context, images, i),
                  child: PropImage(images[i]),
                ),
              ),
              Positioned(
                top: top + 10,
                left: 12,
                child: _CircleIcon(icon: ZI.back, onTap: () => Navigator.pop(context)),
              ),
              Positioned(
                top: top + 10,
                right: 12,
                child: Row(children: [
                  _CircleIcon(icon: ZI.share, onTap: _share),
                  const SizedBox(width: 10),
                  FavButton(propertyId: p.id, size: 44),
                ]),
              ),
              if (images.length > 1)
                Positioned(
                  bottom: 14,
                  left: 0,
                  right: 0,
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      for (var i = 0; i < images.length; i++)
                        AnimatedContainer(
                          duration: const Duration(milliseconds: 200),
                          margin: const EdgeInsets.symmetric(horizontal: 3),
                          width: i == _page ? 18 : 7,
                          height: 7,
                          decoration: BoxDecoration(
                            color: i == _page ? Zc.orange : Colors.white,
                            borderRadius: BorderRadius.circular(4),
                          ),
                        ),
                    ],
                  ),
                ),
            ]),
          ),
        ),

        // ---------- основное ----------
        SliverPadding(
          padding: EdgeInsets.fromLTRB(side, 22, side, 0),
          sliver: SliverList.list(children: [
            Wrap(spacing: 0, runSpacing: 8, crossAxisAlignment: WrapCrossAlignment.center, children: [
              if (p.isVerified) ...[const VerifiedBadge(compact: true), const SizedBox(width: 8)],
              if (p.isPromoted) ...[const PromotedBadge(), const SizedBox(width: 8)],
              _Tag(p.dealType == DealType.sale ? 'For sale' : 'For rent'),
              const SizedBox(width: 8),
              _Tag(p.listedBy == 'agent' ? 'Agent' : 'Owner'),
              if (p.isDemo) ...[const SizedBox(width: 8), const _Tag('Demo')],
            ]),
            const SizedBox(height: 14),
            Text(p.priceLabel, style: const TextStyle(fontSize: 26, fontWeight: FontWeight.w700, color: Zc.orange)),
            const SizedBox(height: 8),
            Text(p.title, style: zHeadline(context, size: 26)),
            const SizedBox(height: 8),
            Row(children: [
              const Icon(ZI.pin, size: 18, color: Zc.grey),
              const SizedBox(width: 4),
              Expanded(child: Text(p.locationLine, style: const TextStyle(color: Zc.grey, fontSize: 15))),
            ]),
            if (TrustLine.textFor(p) != null) ...[const SizedBox(height: 12), TrustLine(p: p)],
            if (p.unlicensedAgent) ...[const SizedBox(height: 10), const LicenceWarning()],
            const SizedBox(height: 18),
            Wrap(spacing: 22, runSpacing: 10, children: [
              if (p.bedrooms != null) _Spec(ZI.bed, '${p.bedrooms} beds'),
              if (p.bathrooms != null) _Spec(ZI.bath, '${p.bathrooms} baths'),
              if (p.areaSqm != null) _Spec(ZI.size, '${_n(p.areaSqm!)} m²'),
              if (p.plotSqm != null) _Spec(ZI.land, 'Plot ${_n(p.plotSqm!)} m²'),
              _Spec(ZI.eye, '${p.viewsCount} views'),
            ]),
            const SizedBox(height: 22),
            TrustPanel(p: p),
            if ((p.description ?? '').isNotEmpty) ...[
              _h('Description'),
              Text(p.description!, style: const TextStyle(fontSize: 15, height: 1.45)),
            ],
            // реклама: блок под описанием
            const Padding(padding: EdgeInsets.only(top: 22), child: ListingAdBlock()),
            if (p.amenities.isNotEmpty) ...[
              _h('Amenities'),
              Wrap(spacing: 10, runSpacing: 10, children: [
                for (final a in p.amenities)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: Zc.green, width: 0.8),
                    ),
                    child: Text(amenityLabels[a] ?? a, style: const TextStyle(color: Zc.green)),
                  ),
              ]),
            ],
            _h('Details'),
            _row('Property type', p.propertyType.label),
            if (p.dealType == DealType.rent) _row('Rental', p.rentPeriod == 'day' ? 'Daily' : 'Long-term'),
            if (p.leaseTerm != null) _row('Lease term', p.leaseTerm == 'year' ? 'From a year' : 'A few months'),
            if (p.renovation != null) _row('Renovation', renovationLabels[p.renovation] ?? p.renovation!),
            if (p.kidsAllowed != null) _row('Kids allowed', p.kidsAllowed! ? 'Yes' : 'No'),
            if (p.petsAllowed != null) _row('Pets allowed', p.petsAllowed! ? 'Yes' : 'No'),
            _h('Location'),
            ClipRRect(
              borderRadius: BorderRadius.circular(16),
              child: SizedBox(
                height: 200,
                child: FlutterMap(
                  options: MapOptions(
                    initialCenter: LatLng(p.lat, p.lng),
                    initialZoom: 14.5,
                    interactionOptions: const InteractionOptions(flags: InteractiveFlag.pinchZoom | InteractiveFlag.drag),
                  ),
                  children: [
                    TileLayer(urlTemplate: AppConfig.mapTilesUrl, userAgentPackageName: AppConfig.mapUserAgent),
                    MarkerLayer(markers: [
                      Marker(
                        point: LatLng(p.lat, p.lng),
                        width: 44,
                        height: 44,
                        alignment: Alignment.topCenter,
                        child: const Icon(ZI.pinFill, color: Zc.orange, size: 44),
                      ),
                    ]),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 6),
            Text('Approximate location · Map ${AppConfig.mapAttribution}',
                style: const TextStyle(color: Zc.grey, fontSize: 12)),
            _h(p.listedBy == 'agent' ? 'Agent' : 'Owner'),
            InkWell(
              borderRadius: BorderRadius.circular(14),
              onTap: _profileId == null ? null : _openAuthor,
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 6),
                child: Row(children: [
                  ZAvatar(url: p.ownerAvatarUrl, name: p.contactName, size: 52),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Row(children: [
                        Flexible(
                          child: Text(p.contactName ?? 'Seller',
                              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
                        ),
                        if (p.ownerIdentityVerified) ...[const SizedBox(width: 6), const VerifiedMark()],
                      ]),
                      Text(
                        p.listedBy == 'agent'
                            ? ((p.agencyName ?? '').isNotEmpty ? 'Real estate agent · ${p.agencyName}' : 'Real estate agent')
                            : 'Property owner',
                        style: const TextStyle(color: Zc.grey),
                      ),
                      if (_profileId != null)
                        Text(p.listedBy == 'agent' ? 'See all listings and reviews' : 'View profile',
                            style: const TextStyle(color: Zc.orange, fontSize: 13)),
                    ]),
                  ),
                  if (_profileId != null) const Icon(ZI.caretRight, color: Zc.grey, size: 18),
                ]),
              ),
            ),
            if (reviewTargetFor(p) != null) ...[
              const SizedBox(height: 28),
              ReviewsSection(targetId: reviewTargetFor(p)!, name: p.contactName ?? 'the author', propertyId: p.id),
            ],
            const SizedBox(height: 24),
            SafetyTips(p: p),
            const SizedBox(height: 120),
          ]),
        ),
      ]),

      // ---------- кнопки связи ----------
      bottomNavigationBar: SafeArea(
        child: Container(
          padding: EdgeInsets.fromLTRB(desk ? side : 16, 10, desk ? side : 16, 10),
          decoration: const BoxDecoration(
            color: Zc.bg,
            boxShadow: [BoxShadow(color: Zc.shadow, blurRadius: 12, offset: Offset(0, -2))],
          ),
          child: Row(children: [
            // номер показывает сервер по кнопке; «только чат» — кнопок звонка нет
            if (!p.chatOnly && p.hasPhone) ...[
              _ActionBtn(icon: ZI.phone, label: 'Number', onTap: () => Contact.showNumber(context, p)),
              const SizedBox(width: 10),
              _ActionBtn(icon: ZI.whatsapp, label: 'WhatsApp', onTap: () => Contact.whatsapp(context, p)),
              const SizedBox(width: 10),
            ],
            Expanded(
              child: SizedBox(
                height: 52,
                child: FilledButton.icon(
                  style: FilledButton.styleFrom(
                    backgroundColor: Zc.orange,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                  ),
                  onPressed: _chatLoading ? null : _chat,
                  icon: _chatLoading
                      ? const SizedBox(
                          width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                      : const Icon(ZI.chat),
                  label: const Text('Message', style: TextStyle(fontSize: 16)),
                ),
              ),
            ),
          ]),
        ),
      ),
    );
  }

  Widget _h(String t) => Padding(
        padding: const EdgeInsets.only(top: 28, bottom: 12),
        child: Text(t, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w600, color: Zc.green)),
      );

  Widget _row(String k, String v) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 7),
        child: Row(children: [
          Expanded(child: Text(k, style: const TextStyle(color: Zc.grey, fontSize: 15))),
          Text(v, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w500)),
        ]),
      );
}

String _n(double v) => v == v.roundToDouble() ? v.toInt().toString() : v.toStringAsFixed(1);

class _Tag extends StatelessWidget {
  const _Tag(this.text);
  final String text;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(color: Zc.chip, borderRadius: BorderRadius.circular(20)),
        child: Text(text, style: const TextStyle(fontSize: 12, color: Zc.green, fontWeight: FontWeight.w500)),
      );
}

class _Spec extends StatelessWidget {
  const _Spec(this.icon, this.text);
  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) => Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(icon, size: 20, color: Zc.green),
        const SizedBox(width: 6),
        Text(text, style: const TextStyle(fontSize: 15)),
      ]);
}

class _CircleIcon extends StatelessWidget {
  const _CircleIcon({required this.icon, required this.onTap});
  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => GestureDetector(
        onTap: onTap,
        child: Container(
          width: 44,
          height: 44,
          decoration: const BoxDecoration(color: Color(0xCCFFFFFF), shape: BoxShape.circle),
          child: Icon(icon, color: Zc.green),
        ),
      );
}

class _ActionBtn extends StatelessWidget {
  const _ActionBtn({required this.icon, required this.label, required this.onTap});
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => SizedBox(
        height: 52,
        child: OutlinedButton(
          style: OutlinedButton.styleFrom(
            foregroundColor: Zc.green,
            side: const BorderSide(color: Zc.green),
            padding: const EdgeInsets.symmetric(horizontal: 14),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          ),
          onPressed: onTap,
          child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
            Icon(icon, size: 20),
            Text(label, style: const TextStyle(fontSize: 11)),
          ]),
        ),
      );
}
