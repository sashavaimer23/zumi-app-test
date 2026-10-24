import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';

import '../../data/images.dart';
import '../../models/models.dart';
import '../../state/app_state.dart';
import '../../theme.dart';
import '../../widgets/common.dart';
import '../../widgets/promo_card.dart';
import '../../widgets/share.dart';
import '../../widgets/zicons.dart';
import '../verify/get_verified_screen.dart';
import 'crop_dialog.dart';

const _ok = Color(0xFF2E9E5B);
const _bad = Color(0xFFD64545);

String _fmtInt(int n) {
  final s = n.toString();
  final b = StringBuffer();
  for (var i = 0; i < s.length; i++) {
    if (i > 0 && (s.length - i) % 3 == 0) b.write(',');
    b.write(s[i]);
  }
  return b.toString();
}

String _fmtSize(int bytes) =>
    bytes >= 1024 * 1024 ? '${(bytes / 1024 / 1024).toStringAsFixed(1)} MB' : '${(bytes / 1024).round()} KB';

(String, Color) _phaseChip(Campaign c) => switch (c.phase) {
      'live' => ('Live', _ok),
      'review' => ('Under review', Zc.orange),
      'rejected' => ('Not approved', _bad),
      'scheduled' => ('Starts ${formatShortDate(c.startsOn)}', Zc.orange),
      'paused' => ('Paused', Zc.grey),
      'finished' => ('Finished', Zc.green),
      _ => ('Stopped', _bad),
    };

Widget _chip(String text, Color color) => Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(color: color.withAlpha(28), borderRadius: BorderRadius.circular(12)),
      child: Text(text, style: TextStyle(fontSize: 12, color: color, fontWeight: FontWeight.w600)),
    );

/// Узкая колонка по центру на компьютере
double _side(BuildContext context) {
  final w = MediaQuery.sizeOf(context).width;
  return w > 820 ? (w - 760) / 2 : 20;
}

// ======================================================================
// Вкладка «Promotion» в кабинете агента: список кампаний
// ======================================================================
class PromotionScreen extends StatefulWidget {
  const PromotionScreen({super.key});

  @override
  State<PromotionScreen> createState() => _PromotionScreenState();
}

class _PromotionScreenState extends State<PromotionScreen> {
  late Future<List<dynamic>> _future = _load();

  Future<List<dynamic>> _load() async {
    final repo = context.read<AppState>().repo;
    final campaigns = await repo.myCampaigns();
    final listings = await repo.myListings();
    final stats = await Future.wait(campaigns.map((c) => repo.campaignStats(c.id)));
    return [campaigns, {for (final p in listings) p.id: p}, stats];
  }

  void _reload() => setState(() => _future = _load());

  Future<void> _new() async {
    final created = await Navigator.push<bool>(context, MaterialPageRoute(builder: (_) => const CampaignWizard()));
    if (created == true) _reload();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Promotion')),
      body: FutureBuilder<List<dynamic>>(
        future: _future,
        builder: (context, snap) {
          if (snap.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator(color: Zc.orange));
          }
          if (snap.hasError) {
            return EmptyState(icon: ZI.warning, title: 'Could not load', subtitle: '${snap.error}');
          }
          final user = context.watch<AppState>().user;
          final campaigns = snap.data![0] as List<Campaign>;
          final props = snap.data![1] as Map<String, Property>;
          final stats = snap.data![2] as List<CampaignStats>;
          final views = stats.fold<int>(0, (a, s) => a + s.views);
          final clicks = stats.fold<int>(0, (a, s) => a + s.clicks);

          return RefreshIndicator(
            color: Zc.orange,
            onRefresh: () async => _reload(),
            child: ListView(
              padding: EdgeInsets.fromLTRB(_side(context), 8, _side(context), 40),
              children: [
                Text('Promote your listings', style: zHeadline(context, size: 28)),
                const SizedBox(height: 6),
                const Text(
                  'Your listing is shown above the others — first in search or in "Featured" on the home page. '
                  'Choose the dates: it starts and ends by itself.',
                  style: TextStyle(color: Zc.grey, height: 1.4),
                ),
                const SizedBox(height: 18),
                if (user != null && user.isAgent && !user.licenceVerified)
                  Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(color: const Color(0xFFFFF1D6), borderRadius: BorderRadius.circular(14)),
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      const Row(children: [
                        Icon(ZI.lock, color: Color(0xFF9A6200), size: 18),
                        SizedBox(width: 8),
                        Expanded(
                          child: Text('Promotion opens after your ZIEA licence is checked',
                              style: TextStyle(fontWeight: FontWeight.w600)),
                        ),
                      ]),
                      const SizedBox(height: 6),
                      Text(
                        (user.licenceNo ?? '').isEmpty
                            ? 'Add your ZIEA registration number — the Zumi team checks it with the register.'
                            : 'Your number ${user.licenceNo} is waiting for the Zumi team to check it.',
                        style: const TextStyle(fontSize: 13, height: 1.4),
                      ),
                      if ((user.licenceNo ?? '').isEmpty) ...[
                        const SizedBox(height: 10),
                        PrimaryButton(
                          label: 'Add licence number',
                          width: double.infinity,
                          onPressed: () => Navigator.push(
                            context,
                            MaterialPageRoute(builder: (_) => const GetVerifiedScreen()),
                          ),
                        ),
                      ],
                    ]),
                  )
                else
                  PrimaryButton(label: '+  New campaign', width: double.infinity, onPressed: _new),
                if (campaigns.isNotEmpty) ...[
                  const SizedBox(height: 22),
                  Row(children: [
                    _BigNumber(value: _fmtInt(views), label: 'views'),
                    _BigNumber(value: _fmtInt(clicks), label: 'clicks'),
                    _BigNumber(value: formatCtr(views == 0 ? 0 : clicks * 100 / views), label: 'click rate'),
                  ]),
                  const SizedBox(height: 18),
                  for (var i = 0; i < campaigns.length; i++)
                    _CampaignTile(
                      c: campaigns[i],
                      p: props[campaigns[i].propertyId],
                      s: stats[i],
                      onTap: () async {
                        await Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => CampaignDetailScreen(campaign: campaigns[i], property: props[campaigns[i].propertyId]),
                          ),
                        );
                        _reload();
                      },
                    ),
                ] else
                  const Padding(
                    padding: EdgeInsets.only(top: 40),
                    child: EmptyState(
                      icon: ZI.bolt,
                      title: 'No campaigns yet',
                      subtitle: 'Tap "New campaign" to put one of your listings at the top.',
                    ),
                  ),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _BigNumber extends StatelessWidget {
  const _BigNumber({required this.value, required this.label});
  final String value;
  final String label;

  @override
  Widget build(BuildContext context) => Expanded(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(value, style: const TextStyle(fontSize: 26, fontWeight: FontWeight.w700, color: Zc.text)),
          Text(label, style: const TextStyle(fontSize: 13, color: Zc.grey)),
        ]),
      );
}

class _CampaignTile extends StatelessWidget {
  const _CampaignTile({required this.c, required this.p, required this.s, required this.onTap});
  final Campaign c;
  final Property? p;
  final CampaignStats s;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final (label, color) = _phaseChip(c);
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Zc.chip),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(children: [
            SizedBox(width: 96, height: 64, child: PropImage(c.imageUrl ?? p?.coverThumb, radius: 10)),
            const SizedBox(width: 12),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(p?.title ?? 'Listing', maxLines: 1, overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontWeight: FontWeight.w600)),
                Text('${c.advertiser} · ${c.placementLabel}',
                    maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12, color: Zc.grey)),
                const SizedBox(height: 6),
                Wrap(spacing: 8, runSpacing: 4, crossAxisAlignment: WrapCrossAlignment.center, children: [
                  _chip(label, color),
                  Text('${_fmtInt(s.views)} views · ${_fmtInt(s.clicks)} clicks · ${_fmtInt(s.calls)} calls · '
                      '${_fmtInt(s.messages)} messages',
                      style: const TextStyle(fontSize: 12, color: Zc.text)),
                ]),
              ]),
            ),
            const Icon(ZI.caretRight, color: Zc.grey, size: 18),
          ]),
        ),
      ),
    );
  }
}

// ======================================================================
// Мастер «New campaign»: 1) объявление и рекламодатель  2) место и картинка
// 3) предпросмотр  4) даты и запуск
// ======================================================================
class CampaignWizard extends StatefulWidget {
  const CampaignWizard({super.key});

  @override
  State<CampaignWizard> createState() => _CampaignWizardState();
}

class _CampaignWizardState extends State<CampaignWizard> {
  final _d = CampaignDraft();
  final _advertiser = TextEditingController();
  final _contact = TextEditingController();
  int _step = 1;
  late final Future<List<Property>> _listings =
      context.read<AppState>().repo.myListings().then((l) => l.where((p) => p.status == 'active').toList());

  // картинка
  String? _imageError;
  String? _imageInfo;
  bool _processing = false;
  bool _launching = false;
  bool _wideView = false;

  @override
  void initState() {
    super.initState();
    final u = context.read<AppState>().user;
    _advertiser.text = u?.agencyName ?? u?.fullName ?? '';
  }

  @override
  void dispose() {
    _advertiser.dispose();
    _contact.dispose();
    super.dispose();
  }

  // ------------------------- шаг 1 -------------------------
  String? _validateStep1() {
    if (_d.property == null) return 'Choose the listing to promote';
    if (_advertiser.text.trim().length < 2) return 'Write the advertiser name';
    final c = _contact.text.trim();
    if (c.isEmpty) return null; // ссылка не обязательна
    if (RegExp(r'^[+\d\s()./-]+$').hasMatch(c)) {
      return 'Phone numbers are not shown on promoted cards — people call you with "Show number". Leave this empty or add a website.';
    }
    if (!c.contains('.') || c.contains(' ')) return 'Enter a website link, e.g. https://lusakahomes.co.zm';
    return null;
  }

  // ------------------------- шаг 2: картинка -------------------------
  Future<void> _pickImage() async {
    try {
      final f = await ImagePicker().pickImage(source: ImageSource.gallery);
      if (f == null) return;
      setState(() {
        _processing = true;
        _imageError = null;
        _imageInfo = null;
      });
      final bytes = await f.readAsBytes();
      final name = f.name.toLowerCase();

      // 1) формат и вес файла
      if (!(name.endsWith('.jpg') || name.endsWith('.jpeg') || name.endsWith('.png') || name.endsWith('.webp') ||
          name.endsWith('.heic') || !name.contains('.'))) {
        _fail('This file type is not supported. Use a JPG, PNG or WebP photo.');
        return;
      }
      if (bytes.lengthInBytes > kBannerMaxBytes) {
        _fail('The file is too large (${_fmtSize(bytes.lengthInBytes)}). The maximum is 15 MB.');
        return;
      }
      // 2) размер в пикселях
      final decoded = await decodeImageFromList(bytes);
      final w = decoded.width, h = decoded.height;
      decoded.dispose();
      if (w < kBannerMinW || h < kBannerMinH) {
        _fail('The image is too small: $w×$h px. Use at least $kBannerMinW×$kBannerMinH px so it looks sharp '
            'on big screens.');
        return;
      }
      // 3) пропорции: 3:2. Если другие — предлагаем выбрать часть кадра
      final ratio = w / h;
      var crop = (0.0, 0.0, 1.0, 1.0);
      if ((ratio - kPromoRatio).abs() > 0.02) {
        if (!mounted) return;
        final picked = await showBannerCrop(
          context,
          bytes: bytes,
          width: w,
          height: h,
          message: 'Your image is $w×$h px, but promotion images are 3:2 (for example 1500×1000). '
              'Choose which part to show.',
        );
        if (picked == null) {
          setState(() => _processing = false);
          return;
        }
        crop = picked;
      }
      // 4) обрезаем и сжимаем
      final out = await cropBanner(bytes, crop.$1, crop.$2, crop.$3, crop.$4);
      if (out == null) {
        _fail('Could not read this image. Try another photo (JPG or PNG).');
        return;
      }
      if (!mounted) return;
      setState(() {
        _d.image = out;
        _processing = false;
        _imageInfo = 'Ready: 3:2, ${_fmtSize(out.lengthInBytes)} (was ${_fmtSize(bytes.lengthInBytes)})';
      });
    } catch (_) {
      _fail('Could not read this image. Try another photo (JPG or PNG).');
    }
  }

  void _fail(String msg) {
    if (!mounted) return;
    setState(() {
      _processing = false;
      _imageError = msg;
    });
  }

  // ------------------------- шаг 4: запуск -------------------------
  Future<void> _pickDates() async {
    final today = DateTime.now();
    final r = await showDateRangePicker(
      context: context,
      firstDate: DateTime(today.year, today.month, today.day),
      lastDate: today.add(const Duration(days: 365)),
      initialDateRange: _d.startsOn == null ? null : DateTimeRange(start: _d.startsOn!, end: _d.endsOn!),
      helpText: 'Campaign dates',
    );
    if (r != null) {
      setState(() {
        _d.startsOn = r.start;
        _d.endsOn = r.end;
      });
    }
  }

  void _quick(int days) {
    final t = DateTime.now();
    final start = DateTime(t.year, t.month, t.day);
    setState(() {
      _d.startsOn = start;
      _d.endsOn = start.add(Duration(days: days - 1));
    });
  }

  Future<void> _launch() async {
    if (_d.startsOn == null) {
      showSnack(context, 'Choose the start and end dates');
      return;
    }
    setState(() => _launching = true);
    final nav = Navigator.of(context);
    final messenger = ScaffoldMessenger.of(context);
    try {
      final c = await context.read<AppState>().repo.createCampaign(_d);
      context.read<AppState>().dataChanged();
      nav.pop(true);
      messenger.showSnackBar(SnackBar(
        content: Text(c.phase == 'review'
            ? 'Sent for a quick check: the Zumi team looks at your picture and texts, usually within a day.'
            : c.isLive
                ? 'Campaign is live! It ends by itself after ${formatShortDate(c.endsOn)}.'
                : 'Campaign scheduled: it starts by itself on ${formatShortDate(c.startsOn)}.'),
      ));
    } catch (e) {
      if (mounted) showSnack(context, '$e');
    } finally {
      if (mounted) setState(() => _launching = false);
    }
  }

  void _next() {
    if (_step == 1) {
      final err = _validateStep1();
      if (err != null) {
        showSnack(context, err);
        return;
      }
      _d.advertiser = _advertiser.text.trim();
      _d.contact = _contact.text.trim();
    }
    if (_step == 2 && _processing) return;
    setState(() => _step++);
  }

  Campaign get _previewCampaign => Campaign(
        id: 'preview',
        ownerId: '',
        propertyId: _d.property?.id ?? '',
        advertiser: _d.advertiser.isEmpty ? _advertiser.text.trim() : _d.advertiser,
        contact: _d.contact.isEmpty ? _contact.text.trim() : _d.contact,
        placement: _d.placement,
        startsOn: DateTime.now(),
        endsOn: DateTime.now(),
        createdAt: DateTime.now(),
      );

  @override
  Widget build(BuildContext context) {
    const titles = ['Listing & advertiser', 'Placement & image', 'Preview', 'Dates'];
    return Scaffold(
      appBar: AppBar(
        title: Text('New campaign · ${titles[_step - 1]}'),
        leading: IconButton(
          icon: const Icon(ZI.back),
          onPressed: () => _step == 1 ? Navigator.pop(context) : setState(() => _step--),
        ),
      ),
      body: Column(children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(0, 6, 0, 0),
          child: StepProgress(step: _step, total: 4),
        ),
        Expanded(
          child: ListView(
            padding: EdgeInsets.fromLTRB(_side(context), 20, _side(context), 30),
            children: switch (_step) {
              1 => _step1(),
              2 => _step2(),
              3 => _step3(),
              _ => _step4(),
            },
          ),
        ),
        SafeArea(
          top: false,
          child: Padding(
            padding: EdgeInsets.fromLTRB(_side(context), 8, _side(context), 14),
            child: PrimaryButton(
              width: double.infinity,
              loading: _launching || (_step == 2 && _processing),
              label: _step == 4 ? 'Launch campaign' : 'Continue',
              onPressed: _step == 4 ? _launch : _next,
            ),
          ),
        ),
      ]),
    );
  }

  Widget _h(String t, [String? sub]) => Padding(
        padding: const EdgeInsets.only(top: 6, bottom: 10),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(t, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600, color: Zc.green)),
          if (sub != null) ...[
            const SizedBox(height: 2),
            Text(sub, style: const TextStyle(fontSize: 13, color: Zc.grey)),
          ],
        ]),
      );

  List<Widget> _step1() => [
        _h('Which listing?', 'Only your active listings can be promoted.'),
        FutureBuilder<List<Property>>(
          future: _listings,
          builder: (context, snap) {
            if (!snap.hasData) {
              return const Padding(
                padding: EdgeInsets.all(20),
                child: Center(child: CircularProgressIndicator(color: Zc.orange)),
              );
            }
            final list = snap.data!;
            if (list.isEmpty) {
              return const Text('You have no active listings yet. Post a listing first.',
                  style: TextStyle(color: Zc.grey));
            }
            return Column(children: [
              for (final p in list)
                GestureDetector(
                  onTap: () => setState(() => _d.property = p),
                  child: Container(
                    margin: const EdgeInsets.only(bottom: 10),
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: _d.property?.id == p.id ? Zc.orangeSoft : Colors.white,
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: _d.property?.id == p.id ? Zc.orange : Zc.chip, width: 1.4),
                    ),
                    child: Row(children: [
                      SizedBox(width: 72, height: 54, child: PropImage(p.coverThumb, radius: 8)),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Text(p.title, maxLines: 1, overflow: TextOverflow.ellipsis,
                              style: const TextStyle(fontWeight: FontWeight.w600)),
                          Text(p.priceLabel, style: const TextStyle(color: Zc.orange, fontSize: 13)),
                        ]),
                      ),
                      RadioDot(selected: _d.property?.id == p.id, size: 20),
                    ]),
                  ),
                ),
            ]);
          },
        ),
        const SizedBox(height: 14),
        _h('Advertiser', 'Who the campaign is for — your agency or your client. Shown as "Promoted by …".'),
        TextField(
          controller: _advertiser,
          maxLength: 80,
          textCapitalization: TextCapitalization.words,
          decoration: const InputDecoration(hintText: 'e.g. Lusaka Homes Ltd', counterText: ''),
        ),
        const SizedBox(height: 14),
        _h('Website (optional)',
            'Adds a "Visit website" button. People call you with "Show number" on the listing — '
            'your number stays protected. A link or your own picture is checked by the Zumi team first.'),
        TextField(
          controller: _contact,
          keyboardType: TextInputType.url,
          decoration: const InputDecoration(hintText: 'https://…'),
        ),
      ];

  List<Widget> _step2() => [
        _h('Where to show it'),
        for (final e in campaignPlacements.entries)
          GestureDetector(
            onTap: () => setState(() => _d.placement = e.key),
            child: Container(
              margin: const EdgeInsets.only(bottom: 10),
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: _d.placement == e.key ? Zc.orangeSoft : Colors.white,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: _d.placement == e.key ? Zc.orange : Zc.chip, width: 1.4),
              ),
              child: Row(children: [
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(e.value.$1, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
                    const SizedBox(height: 2),
                    Text(e.value.$2, style: const TextStyle(fontSize: 13, color: Zc.grey)),
                  ]),
                ),
                RadioDot(selected: _d.placement == e.key, size: 20),
              ]),
            ),
          ),
        const SizedBox(height: 14),
        _h('Image', 'JPG, PNG or WebP · at least 1200×800 px · 3:2. We crop and compress it for you.'),
        GestureDetector(
          onTap: _processing ? null : _pickImage,
          child: AspectRatio(
            aspectRatio: kPromoRatio,
            child: Container(
              decoration: BoxDecoration(
                color: Zc.field,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: _imageError != null ? _bad : Zc.green, width: 0.8),
              ),
              clipBehavior: Clip.antiAlias,
              child: _processing
                  ? const Center(child: CircularProgressIndicator(color: Zc.orange))
                  : (_d.image != null
                      ? Image.memory(_d.image!, fit: BoxFit.cover)
                      : const Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                          Icon(ZI.photos, size: 40, color: Zc.grey),
                          SizedBox(height: 8),
                          Text('Tap to upload an image', style: TextStyle(fontSize: 16, color: Zc.grey)),
                        ])),
            ),
          ),
        ),
        const SizedBox(height: 8),
        if (_imageError != null)
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(color: _bad.withAlpha(20), borderRadius: BorderRadius.circular(12)),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Icon(ZI.warning, color: _bad, size: 20),
              const SizedBox(width: 8),
              Expanded(child: Text(_imageError!, style: const TextStyle(fontSize: 13, height: 1.35))),
            ]),
          ),
        if (_imageInfo != null)
          Row(children: [
            const Icon(ZI.checkCircle, color: _ok, size: 18),
            const SizedBox(width: 6),
            Expanded(child: Text(_imageInfo!, style: const TextStyle(fontSize: 13, color: _ok))),
            TextButton(onPressed: _pickImage, child: const Text('Change', style: TextStyle(color: Zc.orange))),
            TextButton(
              onPressed: () => setState(() {
                _d.image = null;
                _imageInfo = null;
              }),
              child: const Text('Remove', style: TextStyle(color: Zc.grey)),
            ),
          ]),
        if (_d.image == null && _imageError == null)
          const Text("No image? We'll use the listing's main photo.", style: TextStyle(fontSize: 13, color: Zc.grey)),
      ];

  List<Widget> _step3() {
    final p = _d.property!;
    final phone = Center(
      child: Container(
        width: 380,
        padding: const EdgeInsets.fromLTRB(14, 18, 14, 4),
        decoration: BoxDecoration(
          color: Zc.bg,
          borderRadius: BorderRadius.circular(34),
          border: Border.all(color: const Color(0xFF2B2B2B), width: 8),
        ),
        child: PromotedCard(campaign: _previewCampaign, property: p, imageBytes: _d.image, preview: true),
      ),
    );
    final web = Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Zc.bg,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Zc.lightGrey, width: 1.5),
      ),
      child: FittedBox(
        fit: BoxFit.scaleDown,
        alignment: Alignment.topLeft,
        child: SizedBox(
          width: 1000,
          child: PromotedCard(campaign: _previewCampaign, property: p, imageBytes: _d.image, wide: true, preview: true),
        ),
      ),
    );
    return [
      _h('Preview', 'This is how people will see your listing.'),
      Center(
        child: SegmentedButton<bool>(
          segments: const [
            ButtonSegment(value: false, label: Text('Phone'), icon: Icon(ZI.mobile)),
            ButtonSegment(value: true, label: Text('Website'), icon: Icon(ZI.globe)),
          ],
          selected: {_wideView},
          onSelectionChanged: (v) => setState(() => _wideView = v.first),
        ),
      ),
      const SizedBox(height: 16),
      _wideView ? web : phone,
      const SizedBox(height: 12),
      Text('Shown in: ${campaignPlacements[_d.placement]!.$1}',
          textAlign: TextAlign.center, style: const TextStyle(color: Zc.grey, fontSize: 13)),
    ];
  }

  List<Widget> _step4() {
    final s = _d.startsOn, e = _d.endsOn;
    final days = s == null ? 0 : e!.difference(s).inDays + 1;
    return [
      _h('When to show it', 'It appears by itself on the first day and disappears after the last day.'),
      Wrap(spacing: 10, runSpacing: 10, children: [
        for (final d in const [7, 14, 30])
          ZChip(label: '$d days from today', selected: s != null && days == d && _isToday(s), onTap: () => _quick(d)),
      ]),
      const SizedBox(height: 14),
      OutlinedButton.icon(
        style: OutlinedButton.styleFrom(
          foregroundColor: Zc.green,
          side: const BorderSide(color: Zc.green),
          padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 16),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        ),
        onPressed: _pickDates,
        icon: const Icon(ZI.calendar),
        label: Text(s == null ? 'Choose dates' : '${formatShortDate(s)} — ${formatShortDate(e!)}  ($days days)'),
      ),
      if (s != null) ...[
        const SizedBox(height: 18),
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(color: Zc.chip, borderRadius: BorderRadius.circular(14)),
          child: Text(
            '${_isToday(s) ? 'Starts today' : 'Starts on ${formatShortDate(s)}'} and ends after ${formatShortDate(e!)}. '
            'You can pause or stop it at any time.',
            style: const TextStyle(height: 1.4),
          ),
        ),
      ],
      const SizedBox(height: 14),
      const Text('Up to 3 campaigns can run at the same time. Paid promotion will be added with Mobile Money.',
          style: TextStyle(fontSize: 12, color: Zc.grey)),
    ];
  }

  bool _isToday(DateTime d) {
    final t = DateTime.now();
    return d.year == t.year && d.month == t.month && d.day == t.day;
  }
}

// ======================================================================
// Кампания: статистика, пауза/стоп, отчёт рекламодателю
// ======================================================================
class CampaignDetailScreen extends StatefulWidget {
  const CampaignDetailScreen({super.key, required this.campaign, required this.property});
  final Campaign campaign;
  final Property? property;

  @override
  State<CampaignDetailScreen> createState() => _CampaignDetailScreenState();
}

class _CampaignDetailScreenState extends State<CampaignDetailScreen> {
  late Campaign _c = widget.campaign;
  late Future<CampaignStats> _stats = context.read<AppState>().repo.campaignStats(_c.id);
  bool _busy = false;

  Future<void> _setStatus(String status) async {
    if (status == 'stopped') {
      final ok = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Stop this campaign?'),
          content: const Text('The listing will no longer be promoted. A stopped campaign cannot be started again '
              '— you can create a new one.'),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
            TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Stop', style: TextStyle(color: _bad))),
          ],
        ),
      );
      if (ok != true) return;
    }
    setState(() => _busy = true);
    try {
      await context.read<AppState>().repo.setCampaignStatus(_c.id, status);
      if (!mounted) return;
      setState(() => _c = _c.copyWith(status: status));
      context.read<AppState>().dataChanged();
      showSnack(context, switch (status) {
        'paused' => 'Paused — the listing is not promoted until you resume',
        'active' => 'Resumed',
        _ => 'Campaign stopped',
      });
    } catch (e) {
      if (mounted) showSnack(context, '$e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  String _report(CampaignStats s) {
    final p = widget.property;
    final b = StringBuffer()
      ..writeln('Zumi — promotion report')
      ..writeln('Advertiser: ${_c.advertiser}')
      ..writeln('Listing: ${p?.title ?? '-'}${p == null ? '' : ' (${p.priceLabel})'}')
      ..writeln('Placement: ${_c.placementLabel}')
      ..writeln('Dates: ${formatShortDate(_c.startsOn)} – ${formatShortDate(_c.endsOn)} (${_c.days} days)')
      ..writeln('Status: ${_phaseChip(_c).$1}')
      ..writeln()
      ..writeln('Views: ${_fmtInt(s.views)}')
      ..writeln('Clicks: ${_fmtInt(s.clicks)}')
      ..writeln('Click rate: ${formatCtr(s.ctr)}')
      ..writeln('Calls: ${_fmtInt(s.calls)}')
      ..writeln('Messages: ${_fmtInt(s.messages)}');
    if (s.days.isNotEmpty) {
      b
        ..writeln()
        ..writeln('By day:');
      for (final d in s.days) {
        final ctr = d.views == 0 ? 0.0 : d.clicks * 100 / d.views;
        b.writeln('${formatShortDate(d.day)}: ${_fmtInt(d.views)} views, ${_fmtInt(d.clicks)} clicks, '
            '${formatCtr(ctr)}, ${d.calls} calls, ${d.messages} messages');
      }
    }
    return b.toString().trimRight();
  }

  @override
  Widget build(BuildContext context) {
    final p = widget.property;
    final (label, color) = _phaseChip(_c);
    final canChange = _c.phase != 'finished' && _c.phase != 'stopped';
    return Scaffold(
      appBar: AppBar(title: const Text('Campaign')),
      body: FutureBuilder<CampaignStats>(
        future: _stats,
        builder: (context, snap) {
          final s = snap.data ?? const CampaignStats([]);
          return RefreshIndicator(
            color: Zc.orange,
            onRefresh: () async {
              setState(() => _stats = context.read<AppState>().repo.campaignStats(_c.id));
              await _stats;
            },
            child: ListView(
              padding: EdgeInsets.fromLTRB(_side(context), 8, _side(context), 40),
              children: [
                Row(children: [
                  Expanded(child: Text(_c.advertiser, style: zHeadline(context, size: 26))),
                  _chip(label, color),
                ]),
                const SizedBox(height: 6),
                Text('${_c.placementLabel} · ${formatShortDate(_c.startsOn)} – ${formatShortDate(_c.endsOn)}',
                    style: const TextStyle(color: Zc.grey)),
                if (_c.phase == 'review' || _c.phase == 'rejected')
                  Container(
                    margin: const EdgeInsets.only(top: 12),
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(color: Zc.orangeSoft, borderRadius: BorderRadius.circular(12)),
                    child: Text(
                      _c.phase == 'review'
                          ? 'The Zumi team checks campaigns with your own picture, name or link before they are shown. '
                              'This usually takes less than a day.'
                          : 'The Zumi team did not approve this campaign'
                              '${(_c.reviewNote ?? '').isEmpty ? '.' : ': ${_c.reviewNote}'} '
                              'Stop it and create a new one with changes.',
                      style: const TextStyle(fontSize: 13, height: 1.4),
                    ),
                  ),
                const SizedBox(height: 18),

                // ---- цифры
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16)),
                  child: Column(children: [
                    Row(children: [
                      _BigNumber(value: _fmtInt(s.views), label: 'views'),
                      _BigNumber(value: _fmtInt(s.clicks), label: 'clicks'),
                      _BigNumber(value: formatCtr(s.ctr), label: 'click rate'),
                    ]),
                    const SizedBox(height: 14),
                    Row(children: [
                      _BigNumber(value: _fmtInt(s.calls), label: 'calls'),
                      _BigNumber(value: _fmtInt(s.messages), label: 'messages'),
                      const Expanded(child: SizedBox()),
                    ]),
                  ]),
                ),
                const SizedBox(height: 8),
                const Text(
                    'Views — people who saw the card. Clicks — opened the listing or tapped Call / Website. '
                    'Calls — opened the phone number. Messages — started a chat.',
                    style: TextStyle(fontSize: 12, color: Zc.grey)),
                if (s.days.isNotEmpty) ...[
                  const SizedBox(height: 16),
                  _DayBars(days: s.days),
                  const SizedBox(height: 10),
                  for (final d in s.days.reversed)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 5),
                      child: Row(children: [
                        Expanded(child: Text(formatShortDate(d.day))),
                        SizedBox(width: 90, child: Text('${_fmtInt(d.views)} views', textAlign: TextAlign.right)),
                        SizedBox(width: 80, child: Text('${_fmtInt(d.clicks)} clicks', textAlign: TextAlign.right)),
                        SizedBox(
                          width: 60,
                          child: Text(formatCtr(d.views == 0 ? 0 : d.clicks * 100 / d.views),
                              textAlign: TextAlign.right, style: const TextStyle(color: Zc.grey)),
                        ),
                      ]),
                    ),
                ],
                const SizedBox(height: 18),

                // ---- отчёт
                Row(children: [
                  Expanded(
                    child: FilledButton.icon(
                      style: FilledButton.styleFrom(
                        backgroundColor: Zc.orange,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                      ),
                      onPressed: () => showShareSheet(context, text: _report(s)),
                      icon: const Icon(ZI.share, size: 18),
                      label: const Text('Send report'),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: OutlinedButton.icon(
                      style: OutlinedButton.styleFrom(
                        foregroundColor: Zc.green,
                        side: const BorderSide(color: Zc.green),
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                      ),
                      onPressed: () async {
                        await Clipboard.setData(ClipboardData(text: _report(s)));
                        if (context.mounted) showSnack(context, 'Report copied');
                      },
                      icon: const Icon(ZI.copy, size: 18),
                      label: const Text('Copy report'),
                    ),
                  ),
                ]),

                // ---- управление
                if (canChange) ...[
                  const SizedBox(height: 24),
                  Row(children: [
                    if (_c.status == 'active')
                      Expanded(
                        child: OutlinedButton(
                          onPressed: _busy ? null : () => _setStatus('paused'),
                          child: const Text('Pause'),
                        ),
                      )
                    else
                      Expanded(
                        child: OutlinedButton(
                          onPressed: _busy ? null : () => _setStatus('active'),
                          child: const Text('Resume'),
                        ),
                      ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: OutlinedButton(
                        style: OutlinedButton.styleFrom(foregroundColor: _bad, side: const BorderSide(color: _bad)),
                        onPressed: _busy ? null : () => _setStatus('stopped'),
                        child: const Text('Stop'),
                      ),
                    ),
                  ]),
                ],

                // ---- как выглядит
                if (p != null) ...[
                  const SizedBox(height: 28),
                  const Text('How it looks', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600, color: Zc.green)),
                  const SizedBox(height: 12),
                  Center(
                    child: SizedBox(width: 380, child: PromotedCard(campaign: _c, property: p, preview: true)),
                  ),
                ],
              ],
            ),
          );
        },
      ),
    );
  }
}

/// Простой столбиковый график показов по дням
class _DayBars extends StatelessWidget {
  const _DayBars({required this.days});
  final List<CampaignDay> days;

  @override
  Widget build(BuildContext context) {
    final shown = days.length > 30 ? days.sublist(days.length - 30) : days;
    final peak = shown.fold<int>(1, (a, d) => d.views > a ? d.views : a);
    return SizedBox(
      height: 90,
      child: Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
        for (final d in shown)
          Expanded(
            child: Tooltip(
              message: '${formatShortDate(d.day)}: ${d.views} views, ${d.clicks} clicks',
              child: Container(
                margin: const EdgeInsets.symmetric(horizontal: 2),
                height: 6 + 84 * d.views / peak,
                decoration: BoxDecoration(color: Zc.orange, borderRadius: BorderRadius.circular(4)),
              ),
            ),
          ),
      ]),
    );
  }
}
