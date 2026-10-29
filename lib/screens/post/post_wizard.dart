import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:latlong2/latlong.dart';
import 'package:provider/provider.dart';

import '../../data/images.dart';
import '../../models/models.dart';
import '../../state/app_state.dart';
import '../../theme.dart';
import '../../widgets/success_hero.dart';
import '../../widgets/common.dart';
import '../../widgets/onboarding.dart';
import '../auth_screen.dart';
import '../filters_sheet.dart';
import '../shell.dart';
import 'location_picker.dart';
import 'seller_help.dart';
import '../../widgets/trust.dart';
import '../verify/get_verified_screen.dart';
import '../verify/phone_verify_screen.dart';
import '../../widgets/zicons.dart';

/// Подача объявления в 5 шагов (макеты «постинг 1–5»).
/// Лимиты: агент 5 бесплатных объявлений, собственник 2 (настраивается в таблице role_limits).
class PostWizard extends StatefulWidget {
  const PostWizard({super.key, this.editing});

  /// Если задано — правка этого объявления (открывается отдельным экраном)
  final Property? editing;

  @override
  State<PostWizard> createState() => _PostWizardState();
}

class _PostWizardState extends State<PostWizard> {
  late final ListingDraft _d =
      widget.editing == null ? ListingDraft() : ListingDraft.fromProperty(widget.editing!);
  bool get _editing => widget.editing != null;
  int _step = 1;
  bool _publishing = false;
  Property? _created; // опубликованное объявление — для предложения проверки
  Future<Quota>? _quota;
  String? _quotaUser;

  final _title = TextEditingController();
  final _size = TextEditingController();
  final _desc = TextEditingController();
  final _price = TextEditingController();
  final _phone = TextEditingController();
  final _address = TextEditingController();

  // ---- помощь продавцу ----
  /// Мягкая проверка фото: коды предупреждений для каждого нового фото
  final Map<PickedPhoto, List<String>> _photoWarn = Map.identity();
  String _priceKey = '';
  Future<PriceStats>? _priceFuture;

  /// Шкала заполненности — обновляется при наборе текста
  Widget _completeness() => AnimatedBuilder(
        animation: Listenable.merge([_title, _desc, _size, _price, _phone]),
        builder: (context, _) {
          final (score, missing) = listingScore(
            d: _d,
            title: _title.text,
            description: _desc.text,
            size: _size.text,
            price: _price.text,
            phone: _phone.text,
          );
          return CompletenessCard(score: score, missing: missing);
        },
      );

  /// Подпись фото: «Photo 3 is dark …»
  List<String> get _photoWarnings {
    final out = <String>[];
    final seen = <int>{};
    for (var i = 0; i < _d.photos.length; i++) {
      final ph = _d.photos[i];
      if (ph.isExisting) continue;
      final b = ph.bytes;
      final sig = Object.hash(b.length, Object.hashAll(b.take(2048)), Object.hashAll(b.skip(b.length > 2048 ? b.length - 2048 : 0)));
      final codes = [...?_photoWarn[ph], if (!seen.add(sig)) 'duplicate'];
      for (final c in codes) {
        out.add('Photo ${i + 1} ${photoWarningText(c)}');
      }
    }
    return out;
  }

  Future<void> _checkPhotos(List<PickedPhoto> fresh) async {
    for (final ph in fresh) {
      final w = await photoWarnings(ph.bytes);
      if (!mounted) return;
      if (w.isNotEmpty) setState(() => _photoWarn[ph] = w);
    }
  }

  /// Цены похожих объявлений — запрос только когда поменялись район, тип, спальни или валюта
  Future<PriceStats>? _priceStats() {
    final a = _d.area;
    if (a == null) return null;
    final key = '${a.id}|${_d.dealType}|${_d.propertyType}|${_d.bedrooms}|${_d.rentPeriod}|${_d.currency}';
    if (key != _priceKey) {
      _priceKey = key;
      _priceFuture = context.read<AppState>().repo.areaPriceStats(
            areaId: a.id,
            deal: _d.dealType,
            type: _d.propertyType,
            bedrooms: _d.bedrooms,
            rentPeriod: _d.rentPeriod,
            currency: _d.currency,
            excludeId: widget.editing?.id,
          );
    }
    return _priceFuture;
  }

  @override
  void initState() {
    super.initState();
    final e = widget.editing;
    if (e != null) {
      _title.text = e.title;
      _size.text = _d.areaSqm == null ? '' : _fmtNum(_d.areaSqm!);
      _desc.text = e.description ?? '';
      _price.text = e.price.round().toString();
      _phone.text = e.contactPhone ?? '';
      _address.text = e.address ?? '';
      // номер не приходит с объявлением — свой берём отдельно
      if (_phone.text.isEmpty) {
        context.read<AppState>().repo.myListingPhone(e.id).then((n) {
          if (n != null && mounted && _phone.text.isEmpty) setState(() => _phone.text = n);
        });
      }
      // район из справочника
      context.read<AppState>().areas().then((areas) {
        for (final a in areas) {
          if (a.id == e.areaId && mounted) setState(() => _d.area = a);
        }
      });
    }
  }

  static String _fmtNum(double v) => v == v.roundToDouble() ? v.toInt().toString() : v.toString();

  @override
  void dispose() {
    for (final c in [_title, _size, _desc, _price, _phone, _address]) {
      c.dispose();
    }
    super.dispose();
  }

  bool get _dirty => _step > 1 || _title.text.isNotEmpty || _d.photos.isNotEmpty;

  Future<void> _close() async {
    if (_editing) {
      final ok = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Discard changes?'),
          content: const Text('Your changes will not be saved.'),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Keep editing')),
            TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Discard')),
          ],
        ),
      );
      if (ok == true && mounted) Navigator.pop(context, false);
      return;
    }
    if (_step == 5 || !_dirty) {
      Shell.of(context)?.resetPost();
      return;
    }
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Discard this listing?'),
        content: const Text('Everything you entered will be lost.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Keep editing')),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Discard')),
        ],
      ),
    );
    if (ok == true && mounted) Shell.of(context)?.resetPost();
  }

  void _back() => setState(() => _step--);

  // ------------------------------------------------------------------
  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    if (!app.signedIn) {
      return const AuthScreen(embedded: true, reason: 'Sign in to list your property on Zumi.');
    }
    // аккаунт команды Zumi не публикует объявления (это проверяет и сервер)
    if (app.user!.isAdmin) {
      return const Scaffold(
        body: SafeArea(
          child: EmptyState(
            icon: ZI.shield,
            title: 'Team accounts do not post listings',
            subtitle: 'To list your own property, sign in with your personal Zumi account. '
                'Team accounts are only for checks, support and the team panel.',
          ),
        ),
      );
    }
    if (_quotaUser != app.user!.id) {
      _quotaUser = app.user!.id;
      // при правке лимит не проверяем — объявление уже есть
      _quota = _editing ? Future<Quota>.value(const Quota(0, 999)) : app.repo.myQuota();
      if (!_editing) _phone.text = app.user!.phone ?? '';
    }

    return Scaffold(
      body: SafeArea(
        child: FutureBuilder<Quota>(
          future: _quota,
          builder: (context, snap) {
            if (snap.connectionState != ConnectionState.done) {
              return const Center(child: CircularProgressIndicator(color: Zc.orange));
            }
            final q = snap.data;
            if (!_editing && q != null && q.reached && _step < 5) {
              return _LimitReached(quota: q, isAgent: app.user!.isAgent);
            }

            return Column(children: [
              // крестик и прогресс
              Padding(
                padding: const EdgeInsets.fromLTRB(8, 8, 8, 0),
                child: Row(children: [
                  IconButton(
                    icon: const Icon(ZI.close, size: 34, color: Zc.green),
                    onPressed: _close,
                  ),
                  const Spacer(),
                  if (_step > 1 && _step < 5)
                    TextButton.icon(
                      onPressed: _back,
                      icon: const Icon(ZI.back, color: Zc.green, size: 18),
                      label: const Text('Back', style: TextStyle(color: Zc.green)),
                    ),
                ]),
              ),
              const SizedBox(height: 10),
              StepProgress(step: _step),
              Expanded(
                child: AnimatedSwitcher(
                  duration: const Duration(milliseconds: 220),
                  child: KeyedSubtree(key: ValueKey(_step), child: _body(q)),
                ),
              ),
            ]);
          },
        ),
      ),
    );
  }

  Widget _body(Quota? q) => switch (_step) {
        1 => _step1(q),
        2 => _step2(),
        3 => _step3(),
        4 => _step4(),
        _ => _step5(),
      };

  Widget _page({required String title, required String subtitle, required List<Widget> children, Widget? button}) {
    // на компьютере форма узкой колонкой по центру, а не на весь экран
    final w = MediaQuery.sizeOf(context).width;
    final side = w > 760 ? (w - 640) / 2 : 26.0;
    return ListView(
      padding: EdgeInsets.fromLTRB(side, 30, side, 30),
      children: [
        Text(title, style: zHeadline(context, size: w > 760 ? 36 : 42)),
        const SizedBox(height: 8),
        Text(subtitle, style: const TextStyle(fontSize: 16, color: Zc.grey)),
        const SizedBox(height: 28),
        ...children,
        if (button != null) ...[const SizedBox(height: 40), Center(child: button)],
      ],
    );
  }

  Widget _label(String t) => Padding(
        padding: const EdgeInsets.only(bottom: 8, top: 18),
        child: Text(t, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600, color: Zc.text)),
      );

  // ------------------------------ ШАГ 1 ------------------------------
  Widget _step1(Quota? q) {
    return _page(
      title: _editing ? 'Edit your listing' : 'List your property',
      subtitle: _editing ? 'Change anything you need — the listing stays online.' : 'Tell us what you are listing to get started',
      children: [
        if (!_editing)
          const HintCard(
            id: 'hint_post',
            icon: ZI.camera,
            title: 'Your first listing — 3 minutes',
            text: 'Have 5+ daylight photos ready: every room, the outside and the street. '
                'Your first 2 listings are checked by the Zumi team, usually within a day.',
            margin: EdgeInsets.only(bottom: 16),
          ),
        if (q != null && !_editing)
          Container(
            margin: const EdgeInsets.only(bottom: 20),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(color: Zc.chip, borderRadius: BorderRadius.circular(12)),
            child: Row(children: [
              const Icon(ZI.info, size: 18, color: Zc.green),
              const SizedBox(width: 8),
              Expanded(
                child: Text('${q.left} of ${q.allowed} free listings left',
                    style: const TextStyle(fontSize: 13, color: Zc.green)),
              ),
            ]),
          ),
        Row(children: [
          Expanded(
            child: _DealCard(
              image: 'deal_rent.jpg',
              title: 'For rent',
              subtitle: 'Find the right tenants quickly.',
              selected: _d.dealType == DealType.rent,
              onTap: () => setState(() => _d.dealType = DealType.rent),
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: _DealCard(
              image: 'deal_sale.jpg',
              title: 'For sale',
              subtitle: 'Reach serious buyers.',
              selected: _d.dealType == DealType.sale,
              onTap: () => setState(() => _d.dealType = DealType.sale),
            ),
          ),
        ]),
        const SizedBox(height: 44),
        Text('Property type', style: zHeadline(context, size: 36)),
        const SizedBox(height: 8),
        const Text('What kind of property are you listing?', style: TextStyle(fontSize: 16, color: Zc.grey)),
        const SizedBox(height: 22),
        GridView.count(
          crossAxisCount: 2,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          mainAxisSpacing: 16,
          crossAxisSpacing: 16,
          childAspectRatio: 2.6,
          children: [
            for (final (t, icon) in [
              (PropertyType.house, ZI.house),
              (PropertyType.apartment, ZI.apartment),
              (PropertyType.commercial, ZI.commercial),
              (PropertyType.land, ZI.land),
            ])
              _TypeTile(
                icon: icon,
                label: t.label,
                selected: _d.propertyType == t,
                onTap: () => setState(() => _d.propertyType = t),
              ),
          ],
        ),
      ],
      button: PrimaryButton(label: 'Continue', onPressed: () => setState(() => _step = 2)),
    );
  }

  // ------------------------------ ШАГ 2 ------------------------------
  Widget _step2() {
    final isLand = _d.propertyType == PropertyType.land;
    return _page(
      title: 'Property details',
      subtitle: 'Help people know more about your property.',
      children: [
        _completeness(),
        _label('Title'),
        TextField(
          controller: _title,
          textCapitalization: TextCapitalization.sentences,
          maxLength: 80,
          decoration: const InputDecoration(
            hintText: 'e.g. 3-bedroom house with borehole in Kabulonga',
            counterText: '',
          ),
        ),
        if (!isLand) ...[
          _label('Bedrooms'),
          _NumberDropdown(value: _d.bedrooms, max: 10, onChanged: (v) => setState(() => _d.bedrooms = v)),
          _label('Bathrooms'),
          _NumberDropdown(value: _d.bathrooms, max: 8, onChanged: (v) => setState(() => _d.bathrooms = v)),
        ],
        _label(isLand ? 'Plot size (m²)' : 'Property size (m²)'),
        TextField(
          controller: _size,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]'))],
          decoration: const InputDecoration(hintText: '0'),
        ),
        _label('Description'),
        TextField(
          controller: _desc,
          minLines: 4,
          maxLines: 8,
          textCapitalization: TextCapitalization.sentences,
          decoration: const InputDecoration(
            hintText: 'What makes it a good home? Rooms, condition, water, power, security, what is nearby…',
          ),
        ),
        DescriptionHints(controller: _desc),
        if (!isLand) ...[
          const SizedBox(height: 36),
          Text('Amenities', style: zHeadline(context, size: 36)),
          const SizedBox(height: 8),
          const Text('Select what your property offers.', style: TextStyle(fontSize: 16, color: Zc.grey)),
          const SizedBox(height: 20),
          GridView.count(
            crossAxisCount: 2,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            mainAxisSpacing: 12,
            crossAxisSpacing: 14,
            childAspectRatio: 3.4,
            children: [
              for (final e in amenityLabels.entries)
                _PillToggle(
                  label: e.value,
                  selected: _d.amenities.contains(e.key),
                  onTap: () => setState(
                      () => _d.amenities.contains(e.key) ? _d.amenities.remove(e.key) : _d.amenities.add(e.key)),
                ),
            ],
          ),
        ],
      ],
      button: PrimaryButton(
        label: 'Continue',
        onPressed: () {
          if (_title.text.trim().length < 5) {
            showSnack(context, 'Please write a title (at least 5 characters)');
            return;
          }
          _d.title = _title.text.trim();
          _d.description = _desc.text.trim();
          _d.areaSqm = double.tryParse(_size.text.replaceAll(',', '.'));
          if (_d.areaSqm == 0) _d.areaSqm = null;
          setState(() => _step = 3);
        },
      ),
    );
  }

  // ------------------------------ ШАГ 3 ------------------------------
  Future<void> _pickPhotos() async {
    try {
      final files = await ImagePicker().pickMultiImage(imageQuality: 80, maxWidth: 1600, maxHeight: 1600);
      final room = 10 - _d.photos.length;
      var skipped = 0;
      final fresh = <PickedPhoto>[];
      for (final f in files.take(room)) {
        var bytes = await f.readAsBytes();
        // фото до 5 MB: большое пробуем сжать, если не вышло — пропускаем
        if (bytes.lengthInBytes > kMaxImageBytes) {
          final smaller = await makeThumb(bytes, width: 1600, quality: 78);
          if (smaller == null || smaller.lengthInBytes > kMaxImageBytes) {
            skipped++;
            continue;
          }
          bytes = smaller;
        }
        final ph = PickedPhoto(f.name, bytes);
        _d.photos.add(ph);
        fresh.add(ph);
      }
      _checkPhotos(fresh);
      if (skipped > 0 && mounted) {
        showSnack(context, '$skipped ${skipped == 1 ? 'photo was' : 'photos were'} skipped: photos must be under 5 MB');
      } else if (files.length > room && mounted) {
        showSnack(context, 'Maximum 10 photos');
      }
      if (mounted) setState(() {});
    } catch (e) {
      if (mounted) showSnack(context, 'Could not open the gallery: $e');
    }
  }

  Widget _step3() {
    return _page(
      title: 'Add Photos',
      subtitle: 'Showcase your property with clear, high-quality photos of every room, the outside and the street.',
      children: [
        _completeness(),
        const PhotoTipsCard(),
        GestureDetector(
          onTap: _pickPhotos,
          child: Container(
            height: _d.photos.isEmpty ? 300 : 150,
            decoration: BoxDecoration(
              color: Zc.field,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: Zc.green, width: 0.8),
            ),
            child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
              const Icon(ZI.photos, size: 44, color: Zc.grey),
              const SizedBox(height: 10),
              const Text('Add Photos', style: TextStyle(fontSize: 26, fontWeight: FontWeight.w700, color: Zc.grey)),
              if (_d.photos.isEmpty) ...[
                const SizedBox(height: 20),
                const Text('Tap to upload photos from your gallery', style: TextStyle(fontSize: 15)),
                const SizedBox(height: 10),
              ],
              const Text('JPG or PNG, up to 5 MB each · up to 10 photos', style: TextStyle(fontSize: 13, color: Zc.grey)),
            ]),
          ),
        ),
        if (_d.photos.isNotEmpty) ...[
          const SizedBox(height: 18),
          Text('${_d.photos.length} / 10 · the first photo is the cover',
              style: const TextStyle(color: Zc.grey, fontSize: 13)),
          const SizedBox(height: 10),
          ReorderableWrap(
            photos: _d.photos,
            onRemove: (i) => setState(() => _d.photos.removeAt(i)),
            onMakeCover: (i) => setState(() => _d.photos.insert(0, _d.photos.removeAt(i))),
          ),
          // мягкая проверка: только подсказки, публиковать можно
          if (_photoWarnings.isNotEmpty)
            Container(
              margin: const EdgeInsets.only(top: 14),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(color: Zc.orangeSoft, borderRadius: BorderRadius.circular(12)),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                const Text('Photo check — you can still publish', style: TextStyle(fontWeight: FontWeight.w600)),
                const SizedBox(height: 4),
                for (final w in _photoWarnings)
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Text('• $w', style: const TextStyle(fontSize: 13)),
                  ),
              ]),
            ),
        ],
      ],
      button: PrimaryButton(
        label: 'Continue',
        onPressed: () {
          if (_d.photos.isEmpty) {
            showSnack(context, 'Add at least one photo');
            return;
          }
          setState(() => _step = 4);
        },
      ),
    );
  }

  // ------------------------------ ШАГ 4 ------------------------------
  Widget _step4() {
    final previewPrice = double.tryParse(_price.text.replaceAll(',', '')) ?? 0;
    return _page(
      title: 'Price & Location',
      subtitle: 'Set a price and location so the right people can find your property.',
      children: [
        _completeness(),
        _label('Price'),
        Row(children: [
          Expanded(
            child: TextField(
              controller: _price,
              keyboardType: TextInputType.number,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              decoration: const InputDecoration(
                hintText: '0',
                border: OutlineInputBorder(borderRadius: BorderRadius.horizontal(left: Radius.circular(10))),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.horizontal(left: Radius.circular(10)),
                  borderSide: BorderSide(color: Zc.green, width: 0.8),
                ),
              ),
              onChanged: (_) => setState(() {}),
            ),
          ),
          Container(
            height: 56,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            decoration: const BoxDecoration(
              color: Zc.field,
              borderRadius: BorderRadius.horizontal(right: Radius.circular(10)),
              border: Border(
                top: BorderSide(color: Zc.green, width: 0.8),
                right: BorderSide(color: Zc.green, width: 0.8),
                bottom: BorderSide(color: Zc.green, width: 0.8),
              ),
            ),
            child: DropdownButtonHideUnderline(
              child: DropdownButton<String>(
                value: _d.currency,
                icon: const Icon(ZI.caretDown, color: Zc.green),
                items: const [
                  DropdownMenuItem(value: 'ZMW', child: Text('ZMW')),
                  DropdownMenuItem(value: 'USD', child: Text('USD')),
                ],
                onChanged: (v) => setState(() => _d.currency = v ?? 'ZMW'),
              ),
            ),
          ),
        ]),
        if (_d.dealType == DealType.rent) ...[
          const SizedBox(height: 12),
          Wrap(spacing: 10, children: [
            ZChip(label: 'Per month', selected: _d.rentPeriod == 'month', onTap: () => setState(() => _d.rentPeriod = 'month')),
            ZChip(label: 'Per day', selected: _d.rentPeriod == 'day', onTap: () => setState(() => _d.rentPeriod = 'day')),
          ]),
        ],
        // цены похожих объявлений в районе
        if (_d.area == null)
          const Padding(
            padding: EdgeInsets.only(top: 8),
            child: Text('Choose the neighbourhood below to see prices of similar homes.',
                style: TextStyle(fontSize: 12, color: Zc.grey)),
          )
        else
          FutureBuilder<PriceStats>(
            future: _priceStats(),
            builder: (context, snap) => snap.hasData
                ? PriceHint(
                    stats: snap.data!,
                    price: previewPrice,
                    currency: _d.currency,
                    areaName: _d.area!.name,
                    perLabel: _d.dealType == DealType.rent ? (_d.rentPeriod == 'day' ? ' per day' : ' per month') : '',
                  )
                : const SizedBox(height: 8),
          ),
        _label('Neighbourhood'),
        InkWell(
          onTap: () async {
            final areas = await context.read<AppState>().areas();
            if (!mounted) return;
            final a = await pickArea(context, areas);
            if (a != null) {
              setState(() {
                _d.area = a;
                _d.lat = null;
                _d.lng = null;
                _d.pinned = false;
              });
            }
          },
          child: InputDecorator(
            decoration: const InputDecoration(suffixIcon: Icon(ZI.caretDown, color: Zc.green)),
            child: Text(_d.area?.name ?? 'Select the area',
                style: TextStyle(fontSize: 15, color: _d.area == null ? Zc.grey : Zc.text)),
          ),
        ),
        _label('Location on the map *'),
        _PinCard(
          draft: _d,
          onPick: _d.area == null
              ? () => showSnack(context, 'Choose the neighbourhood first')
              : () async {
                  final start = LatLng(_d.lat ?? _d.area!.lat, _d.lng ?? _d.area!.lng);
                  final res = await Navigator.push<LatLng>(
                    context,
                    MaterialPageRoute(builder: (_) => LocationPickerScreen(start: start)),
                  );
                  if (res != null) {
                    setState(() {
                      _d.lat = res.latitude;
                      _d.lng = res.longitude;
                      _d.pinned = true;
                    });
                  }
                },
        ),
        _label('Address (optional)'),
        TextField(
          controller: _address,
          maxLength: 120,
          textCapitalization: TextCapitalization.sentences,
          decoration: const InputDecoration(hintText: 'e.g. Plot 12, Leopards Hill Road', counterText: ''),
          onChanged: (v) => _d.address = v,
        ),
        const Padding(
          padding: EdgeInsets.only(top: 6),
          child: Text('Shown on the listing. Leave it empty if you prefer to share the address in chat.',
              style: TextStyle(fontSize: 12, color: Zc.grey)),
        ),
        _label("What's nearby (optional)"),
        const Text('Helps people decide faster. Choose the distance for what you know.',
            style: TextStyle(fontSize: 13, color: Zc.grey)),
        const SizedBox(height: 10),
        _NearbyPicker(value: _d.nearby, onChanged: (m) => setState(() => _d.nearby = m)),
        _label('Contact number'),
        TextField(
          controller: _phone,
          keyboardType: TextInputType.phone,
          decoration: const InputDecoration(hintText: 'Your number'),
        ),
        const SizedBox(height: 36),
        const Text('Listing preview', style: TextStyle(fontSize: 26, fontWeight: FontWeight.w500, color: Zc.text)),
        const SizedBox(height: 14),
        _Preview(draft: _d, price: previewPrice),
      ],
      button: PrimaryButton(label: _editing ? 'Save changes' : 'Publish', loading: _publishing, onPressed: _publish),
    );
  }

  /// «Подтвердите номер, чтобы опубликовать» → экран кода. true — номер подтверждён.
  Future<bool> _askPhone() async {
    final go = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Confirm your phone number'),
        content: const Text(
          'To publish a listing, confirm your phone number with a code. You do it only once — '
          'after that your listings show "Number checked".',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Not now')),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Confirm')),
        ],
      ),
    );
    if (go != true || !mounted) return false;
    final ok = await Navigator.push<bool>(context, MaterialPageRoute(builder: (_) => const PhoneVerifyScreen()));
    if (!mounted) return false;
    await context.read<AppState>().repo.refreshUser();
    return ok == true || (mounted && (context.read<AppState>().user?.phoneVerified ?? false));
  }

  Future<void> _publish() async {
    final price = double.tryParse(_price.text.replaceAll(',', ''));
    if (price == null || price <= 0) {
      showSnack(context, 'Please enter the price');
      return;
    }
    if (_d.area == null) {
      showSnack(context, 'Please select the neighbourhood');
      return;
    }
    if (!_d.pinned || _d.lat == null) {
      showSnack(context, 'Please put the pin on the map where the property is');
      return;
    }
    // публиковать можно только с подтверждённым телефоном (подтверждается один раз)
    if (!_editing && !(context.read<AppState>().user?.phoneVerified ?? false)) {
      final ok = await _askPhone();
      if (!ok || !mounted) return;
    }
    if (_phone.text.replaceAll(RegExp(r'\D'), '').length < 9) {
      showSnack(context, 'Please enter a valid contact number');
      return;
    }
    _d.price = price;
    _d.contactPhone = _phone.text.trim();

    setState(() => _publishing = true);
    final app = context.read<AppState>();
    if (_editing) {
      final nav = Navigator.of(context);
      final messenger = ScaffoldMessenger.of(context);
      try {
        await app.repo.updateListing(widget.editing!.id, _d);
        app.dataChanged();
        nav.pop(true);
        messenger.showSnackBar(const SnackBar(content: Text('Changes saved')));
      } catch (e) {
        if (mounted) showSnack(context, '$e');
      } finally {
        if (mounted) setState(() => _publishing = false);
      }
      return;
    }
    try {
      _created = await app.repo.createListing(_d);
      app.dataChanged();
      // первое объявление — потом покажем короткий тур «где ваши объявления и сообщения»
      if (!app.hintSeen('posted_first')) {
        app.markHint('posted_first');
        app.requestTour();
      }
      if (mounted) setState(() => _step = 5);
    } on AppException catch (e) {
      if (!mounted) return;
      if (e.code == 'LISTING_LIMIT_REACHED') {
        setState(() => _quota = app.repo.myQuota());
      } else if (e.code == 'PHONE_REQUIRED') {
        if (await _askPhone() && mounted) _publish();
      } else {
        showSnack(context, e.message);
      }
    } catch (e) {
      if (mounted) showSnack(context, '$e');
    } finally {
      if (mounted) setState(() => _publishing = false);
    }
  }

  // ------------------------------ ШАГ 5 ------------------------------
  Widget _step5() {
    final w = MediaQuery.sizeOf(context).width;
    final side = w > 760 ? (w - 640) / 2 : 26.0;
    return ListView(
      padding: EdgeInsets.fromLTRB(side, 30, side, 30),
      children: [
        const ListingLiveHero(),
        const SizedBox(height: 24),
        Text(_created?.isPending ?? false ? 'Almost live!' : 'Your listing is live!',
            textAlign: TextAlign.center, style: zHeadline(context, size: 40)),
        const SizedBox(height: 16),
        Text(
          _created?.isPending ?? false
              ? 'Your first listings get a quick check by the Zumi team — usually about 15 minutes. '
                  'It appears in search right after.'
              : 'People can now find your property\non Zumi.',
          textAlign: TextAlign.center,
          style: const TextStyle(fontSize: 18, color: Zc.grey, height: 1.35),
        ),
        const SizedBox(height: 28),
        // агенту без проверенной лицензии — предложить добавить номер ZIEA (необязательно)
        if (_created != null &&
            (context.watch<AppState>().user?.isAgent ?? false) &&
            !(context.watch<AppState>().user?.licenceVerified ?? false))
          Container(
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: Zc.chip),
            ),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Row(children: [
                VerifiedBadge(compact: true, label: 'Licensed agent'),
                Spacer(),
                Text('Optional', style: TextStyle(color: Zc.grey, fontSize: 13)),
              ]),
              const SizedBox(height: 12),
              const Text('Get the Licensed agent badge?',
                  style: TextStyle(fontSize: 19, fontWeight: FontWeight.w600, color: Zc.green)),
              const SizedBox(height: 6),
              const Text(
                'Add your ZIEA registration number — the Zumi team checks it with ZIEA. Your listings then show '
                '"Licensed agent" and people trust them more. No documents to upload.',
                style: TextStyle(fontSize: 14, color: Zc.grey, height: 1.4),
              ),
              const SizedBox(height: 14),
              Row(children: [
                Expanded(
                  child: PrimaryButton(
                    label: 'Add licence number',
                    width: double.infinity,
                    onPressed: () async {
                      await Navigator.push(
                          context, MaterialPageRoute(builder: (_) => const GetVerifiedScreen()));
                      if (mounted) Shell.of(this.context)?.resetPost(goTo: 4);
                    },
                  ),
                ),
                const SizedBox(width: 10),
                TextButton(
                  onPressed: () => Shell.of(this.context)?.resetPost(goTo: 4),
                  child: const Text('Maybe later', style: TextStyle(color: Zc.grey)),
                ),
              ]),
            ]),
          )
        else
          Center(
            child: PrimaryButton(
              label: 'Continue',
              onPressed: () => Shell.of(context)?.resetPost(goTo: 4), // в профиль → «Мои объявления»
            ),
          ),
      ],
    );
  }
}

// ======================================================================
// Вспомогательные виджеты мастера
// ======================================================================

/// Точка на карте: обязательна — иначе человек не поймёт, где именно жильё
class _PinCard extends StatelessWidget {
  const _PinCard({required this.draft, required this.onPick});
  final ListingDraft draft;
  final VoidCallback onPick;

  @override
  Widget build(BuildContext context) {
    final pinned = draft.pinned && draft.lat != null;
    return InkWell(
      borderRadius: BorderRadius.circular(14),
      onTap: onPick,
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: pinned ? Zc.greenTint : Zc.orangeSoft,
          borderRadius: BorderRadius.circular(14),
        ),
        child: Row(children: [
          Icon(pinned ? ZI.checkCircle : ZI.pin, color: pinned ? Zc.green : Zc.orange, size: 26),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(pinned ? 'Location pinned' : 'Put the pin where the property is',
                  style: TextStyle(fontWeight: FontWeight.w600, color: pinned ? Zc.green : Zc.text)),
              const SizedBox(height: 2),
              Text(
                pinned
                    ? 'Tap to move the pin'
                    : 'Zoom in and place it as close as you can — people use it to plan a visit.',
                style: const TextStyle(fontSize: 13, color: Zc.grey),
              ),
            ]),
          ),
          Icon(ZI.caretRight, color: pinned ? Zc.green : Zc.orange),
        ]),
      ),
    );
  }
}

/// Что рядом: магазины, школа, больница, главная дорога — расстояние по выбору
class _NearbyPicker extends StatelessWidget {
  const _NearbyPicker({required this.value, required this.onChanged});
  final Map<String, String> value;
  final ValueChanged<Map<String, String>> onChanged;

  @override
  Widget build(BuildContext context) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      for (final place in kNearbyPlaces.entries)
        Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Icon(nearbyIcon(place.key), size: 18, color: Zc.green),
              const SizedBox(width: 6),
              Text(place.value, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
            ]),
            const SizedBox(height: 6),
            Wrap(spacing: 8, runSpacing: 8, children: [
              for (final d in kNearbyDistances.entries)
                ZChip(
                  label: d.value,
                  selected: value[place.key] == d.key,
                  onTap: () {
                    final m = Map<String, String>.of(value);
                    // повторное нажатие снимает выбор
                    m[place.key] == d.key ? m.remove(place.key) : m[place.key] = d.key;
                    onChanged(m);
                  },
                ),
            ]),
          ]),
        ),
    ]);
  }
}
class _DealCard extends StatelessWidget {
  const _DealCard({
    required this.image,
    required this.title,
    required this.subtitle,
    required this.selected,
    required this.onTap,
  });
  final String image, title, subtitle;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.all(4),
        decoration: BoxDecoration(
          color: Zc.bg,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: selected ? Zc.orange : Zc.lightGrey, width: selected ? 2 : 1.2),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          AspectRatio(
            aspectRatio: MediaQuery.sizeOf(context).width > 760 ? 1.3 : 0.92,
            child: PropImage('asset:$image', radius: 14),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(8, 14, 8, 10),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(title, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w500)),
              const SizedBox(height: 4),
              SizedBox(
                height: 38,
                child: Text(subtitle, style: const TextStyle(fontSize: 14, color: Zc.text)),
              ),
              Align(alignment: Alignment.centerRight, child: RadioDot(selected: selected)),
            ]),
          ),
        ]),
      ),
    );
  }
}

class _TypeTile extends StatelessWidget {
  const _TypeTile({required this.icon, required this.label, required this.selected, required this.onTap});
  final IconData icon;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(horizontal: 16),
        decoration: BoxDecoration(
          color: selected ? Zc.orangeSoft : Zc.bg,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: selected ? Zc.orange : Zc.green, width: selected ? 2 : 1.2),
        ),
        child: Row(children: [
          Icon(icon, color: Zc.green, size: 26),
          const SizedBox(width: 10),
          Expanded(
            child: Text(label,
                overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 17, color: Zc.green)),
          ),
          RadioDot(selected: selected, size: 20),
        ]),
      ),
    );
  }
}

class _PillToggle extends StatelessWidget {
  const _PillToggle({required this.label, required this.selected, required this.onTap});
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(horizontal: 18),
        decoration: BoxDecoration(
          color: selected ? Zc.orangeSoft : Zc.bg,
          borderRadius: BorderRadius.circular(30),
          border: Border.all(color: selected ? Zc.orange : Zc.green, width: 1.2),
        ),
        child: Row(children: [
          Expanded(
            child: Text(label, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 15, color: Zc.green)),
          ),
          RadioDot(selected: selected, size: 20),
        ]),
      ),
    );
  }
}

class _NumberDropdown extends StatelessWidget {
  const _NumberDropdown({required this.value, required this.max, required this.onChanged});
  final int value;
  final int max;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    return DropdownButtonFormField<int>(
      value: value,
      icon: const Icon(ZI.caretDown, color: Zc.green, size: 28),
      items: [for (var i = 0; i <= max; i++) DropdownMenuItem(value: i, child: Text(i == max ? '$i+' : '$i'))],
      onChanged: (v) => onChanged(v ?? value),
    );
  }
}

/// Миниатюры выбранных фото: долгое нажатие — сделать обложкой, крестик — удалить
class ReorderableWrap extends StatelessWidget {
  const ReorderableWrap({super.key, required this.photos, required this.onRemove, required this.onMakeCover});
  final List<PickedPhoto> photos;
  final ValueChanged<int> onRemove;
  final ValueChanged<int> onMakeCover;

  @override
  Widget build(BuildContext context) {
    return Wrap(spacing: 10, runSpacing: 10, children: [
      for (var i = 0; i < photos.length; i++)
        GestureDetector(
          onLongPress: () => onMakeCover(i),
          child: Stack(children: [
            SizedBox(
              width: 100,
              height: 100,
              child: photos[i].isExisting
                  ? PropImage(photos[i].url, radius: 10)
                  : ClipRRect(
                      borderRadius: BorderRadius.circular(10),
                      child: Image.memory(photos[i].bytes, width: 100, height: 100, fit: BoxFit.cover),
                    ),
            ),
            if (i == 0)
              Positioned(
                left: 6,
                bottom: 6,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(color: Zc.orange, borderRadius: BorderRadius.circular(6)),
                  child: const Text('Cover', style: TextStyle(color: Colors.white, fontSize: 10)),
                ),
              ),
            Positioned(
              right: 4,
              top: 4,
              child: GestureDetector(
                onTap: () => onRemove(i),
                child: Container(
                  decoration: const BoxDecoration(color: Zc.scrim, shape: BoxShape.circle),
                  padding: const EdgeInsets.all(3),
                  child: const Icon(ZI.close, color: Colors.white, size: 16),
                ),
              ),
            ),
          ]),
        ),
    ]);
  }
}

/// Превью карточки (как в макете «Listing preview»)
class _Preview extends StatelessWidget {
  const _Preview({required this.draft, required this.price});
  final ListingDraft draft;
  final double price;

  @override
  Widget build(BuildContext context) {
    final d = draft;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Zc.green, width: 0.8),
      ),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(14),
          child: SizedBox(
            width: 130,
            height: 130,
            child: d.photos.isEmpty
                ? const ColoredBox(color: Zc.chip)
                : d.photos.first.isExisting
                    ? PropImage(d.photos.first.url)
                    : Image.memory(d.photos.first.bytes, fit: BoxFit.cover),
          ),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(
              d.title.isEmpty ? 'Your title' : d.title,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 10),
            if (d.propertyType != PropertyType.land)
              Wrap(spacing: 12, runSpacing: 6, children: [
                _mini(ZI.bed, '${d.bedrooms} beds'),
                _mini(ZI.bath, '${d.bathrooms} baths'),
              ]),
            if (d.areaSqm != null) ...[const SizedBox(height: 6), _mini(ZI.size, '${d.areaSqm!.round()} (m²)')],
            const SizedBox(height: 12),
            Text(formatMoney(price, d.currency),
                style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w600, color: Zc.orange)),
            if (d.dealType == DealType.rent)
              Text(d.rentPeriod == 'day' ? 'Per day' : 'Per month', style: const TextStyle(color: Zc.grey)),
          ]),
        ),
      ]),
    );
  }

  Widget _mini(IconData i, String t) => Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(i, size: 18, color: Zc.green),
        const SizedBox(width: 4),
        Text(t, style: const TextStyle(fontSize: 13, color: Zc.grey)),
      ]);
}

/// Лимит бесплатных объявлений исчерпан
class _LimitReached extends StatelessWidget {
  const _LimitReached({required this.quota, required this.isAgent});
  final Quota quota;
  final bool isAgent;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(26, 50, 26, 30),
      children: [
        const Icon(ZI.crown, size: 72, color: Zc.orange),
        const SizedBox(height: 20),
        Text('Free listings used', textAlign: TextAlign.center, style: zHeadline(context, size: 34)),
        const SizedBox(height: 14),
        Text(
          // в приложениях для Android и iPhone о покупке не говорим (правила Apple и Google) — только на сайте
          kIsWeb
              ? '${isAgent ? 'Agents' : 'Owners'} can publish ${quota.allowed} listings for free. '
                  'To add more, buy an extra listing slot.'
              : '${isAgent ? 'Agents' : 'Owners'} can publish ${quota.allowed} listings for free. '
                  'Archive or mark a listing as rented or sold to post a new one.',
          textAlign: TextAlign.center,
          style: const TextStyle(fontSize: 16, color: Zc.grey, height: 1.4),
        ),
        const SizedBox(height: 36),
        if (kIsWeb)
          Center(
            child: PrimaryButton(
              label: 'Buy extra listing',
              width: double.infinity,
              onPressed: () => showSnack(context, 'Payments are coming soon (Mobile Money and cards).'),
            ),
          ),
        const SizedBox(height: 12),
        Center(
          child: TextButton(
            onPressed: () => Shell.of(context)?.resetPost(goTo: 4),
            child: const Text('Manage my listings', style: TextStyle(color: Zc.green, fontSize: 16)),
          ),
        ),
        const SizedBox(height: 8),
        const Text(
          'Tip: archiving a listing that is sold or rented frees up a slot.',
          textAlign: TextAlign.center,
          style: TextStyle(color: Zc.grey, fontSize: 13),
        ),
      ],
    );
  }
}
