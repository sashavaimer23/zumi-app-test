part of 'admin_screen.dart';

// ======================================================================
// LISTINGS TO CHECK — первые объявления новых людей
// ======================================================================
class _ListingsQueue extends StatefulWidget {
  const _ListingsQueue({required this.onChanged});
  final VoidCallback onChanged;

  @override
  State<_ListingsQueue> createState() => _ListingsQueueState();
}

class _ListingsQueueState extends State<_ListingsQueue> {
  late Future<List<Property>> _future = context.read<AppState>().repo.adminPendingListings();

  Future<void> _decide(Property p, bool approve) async {
    String? note;
    if (!approve) {
      note = await _askNote(context, 'Reject — tell the author why', [
        'Photos are not of a real property',
        'Price looks like a scam',
        'Duplicate listing',
        'Not enough details',
        'Contact details in photos or text',
      ]);
      if (note == null) return;
    }
    try {
      await context.read<AppState>().repo.adminReviewListing(p.id, approve, note: note);
      if (!mounted) return;
      context.read<AppState>().dataChanged();
      showSnack(context, approve ? 'Published' : 'Rejected');
      setState(() => _future = context.read<AppState>().repo.adminPendingListings());
      widget.onChanged();
    } catch (e) {
      if (mounted) showSnack(context, '$e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return _Page(
      title: 'Listings to check',
      subtitle: 'The first 2 listings of every new person wait here. Check the photos, price and description.',
      child: _Loader<List<Property>>(
        future: _future,
        builder: (list) {
          if (list.isEmpty) return _emptyDone('No listings waiting.');
          return Column(children: [
            for (final p in list)
              _Card(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    SizedBox(width: 120, height: 84, child: PropImage(p.coverThumb, radius: 10)),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text(p.title, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
                        Text(p.priceLabel, style: const TextStyle(color: Zc.orange)),
                        Text('${p.specsLine} · ${p.locationLine}',
                            style: const TextStyle(fontSize: 12, color: Zc.grey)),
                        Text('${p.contactName ?? 'Author'} · ${p.listedBy == 'agent' ? 'Agent' : 'Owner'} · '
                            '${p.images.length} photos · ${timeAgo(p.createdAt)}',
                            style: const TextStyle(fontSize: 12, color: Zc.grey)),
                      ]),
                    ),
                  ]),
                  const SizedBox(height: 12),
                  Wrap(spacing: 10, runSpacing: 8, children: [
                    _actionBtn('Publish', () => _decide(p, true), primary: true),
                    _actionBtn('Open', () => Navigator.push(
                          context,
                          MaterialPageRoute(builder: (_) => PropertyScreen(property: p)),
                        )),
                    _actionBtn('Reject', () => _decide(p, false)),
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
// ТЕСТОВЫЙ РЕЖИМ КОДОВ — красная плашка, пока он включён
// ======================================================================
class _OtpTestBanner extends StatelessWidget {
  const _OtpTestBanner({required this.onChanged});
  final Future<void> Function() onChanged;

  Future<void> _turnOff(BuildContext context) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Turn off test codes?'),
        content: const Text(
          'Do this only after real SMS / WhatsApp sending is connected. '
          'Otherwise nobody will receive a code and new people cannot confirm their phone.',
          style: TextStyle(height: 1.4),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Turn off')),
        ],
      ),
    );
    if (ok != true || !context.mounted) return;
    try {
      await context.read<AppState>().repo.adminSetOtpTestMode(false);
      await onChanged();
      if (context.mounted) showSnack(context, 'Test codes are off');
    } catch (e) {
      if (context.mounted) showSnack(context, '$e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      color: const Color(0xFFD64545),
      padding: const EdgeInsets.fromLTRB(16, 10, 10, 10),
      child: Row(children: [
        const Icon(ZI.warning, color: Colors.white),
        const SizedBox(width: 10),
        const Expanded(
          child: Text(
            'TEST MODE: code 123456 confirms ANY phone. Anyone can "confirm" someone else\'s number — '
            'turn this off before launch.',
            style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600, height: 1.3),
          ),
        ),
        const SizedBox(width: 8),
        TextButton(
          style: TextButton.styleFrom(backgroundColor: Colors.white, foregroundColor: const Color(0xFFD64545)),
          onPressed: () => _turnOff(context),
          child: const Text('Turn off'),
        ),
      ]),
    );
  }
}

// ======================================================================
// PROMOTIONS TO CHECK — своя картинка, название или ссылка агента
// ======================================================================
class _PromosQueue extends StatefulWidget {
  const _PromosQueue({required this.onChanged});
  final VoidCallback onChanged;

  @override
  State<_PromosQueue> createState() => _PromosQueueState();
}

class _PromosQueueState extends State<_PromosQueue> {
  late Future<List<(Campaign, Property?)>> _future = context.read<AppState>().repo.adminPendingCampaigns();

  Future<void> _decide(Campaign c, bool approve) async {
    String? note;
    if (!approve) {
      note = await _askNote(context, 'Not approved — tell the agent why', [
        'The picture is not of this property',
        'Text or contacts inside the picture',
        'Misleading name',
        'Link to an unsafe or unrelated website',
        'Low quality picture',
      ]);
      if (note == null) return;
    }
    try {
      await context.read<AppState>().repo.adminReviewCampaign(c.id, approve, note: note);
      if (!mounted) return;
      showSnack(context, approve ? 'Approved — the promotion is shown now' : 'Not approved');
      setState(() => _future = context.read<AppState>().repo.adminPendingCampaigns());
      widget.onChanged();
    } catch (e) {
      if (mounted) showSnack(context, '$e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return _Page(
      title: 'Promotions to check',
      subtitle: 'Agents\' campaigns with their own picture, name or website link. They go on the home page '
          'and top of search only after you approve.',
      child: _Loader<List<(Campaign, Property?)>>(
        future: _future,
        builder: (list) {
          if (list.isEmpty) return _emptyDone('No promotions waiting.');
          return Column(children: [
            for (final (c, p) in list)
              _Card(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    SizedBox(
                      width: 180,
                      child: AspectRatio(
                        aspectRatio: kPromoRatio,
                        child: PropImage(c.imageUrl ?? p?.coverThumb, radius: 10),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text('Promoted by ${c.advertiser}',
                            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
                        Text(p?.title ?? 'Listing not found', style: const TextStyle(fontSize: 13)),
                        Text('${c.placementLabel} · ${formatShortDate(c.startsOn)} – ${formatShortDate(c.endsOn)}',
                            style: const TextStyle(fontSize: 12, color: Zc.grey)),
                        if (c.imageUrl != null)
                          const Text('Own picture', style: TextStyle(fontSize: 12, color: Zc.orange)),
                        if ((c.contact ?? '').isNotEmpty)
                          SelectableText('Link: ${c.contact}', style: const TextStyle(fontSize: 12, color: Zc.green)),
                      ]),
                    ),
                  ]),
                  const SizedBox(height: 12),
                  Wrap(spacing: 10, runSpacing: 8, children: [
                    _actionBtn('Approve', () => _decide(c, true), primary: true),
                    if (p != null)
                      _actionBtn('Open listing', () => Navigator.push(
                            context,
                            MaterialPageRoute(builder: (_) => PropertyScreen(property: p)),
                          )),
                    _actionBtn('Reject', () => _decide(c, false)),
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
// PHONE VIEWS — кто чаще всех смотрит номера (боты видны сразу)
// ======================================================================
class _PhoneViews extends StatefulWidget {
  const _PhoneViews();

  @override
  State<_PhoneViews> createState() => _PhoneViewsState();
}

class _PhoneViewsState extends State<_PhoneViews> {
  int _days = 7;
  late Future<List<PhoneWatcher>> _future = _load();

  Future<List<PhoneWatcher>> _load() => context.read<AppState>().repo.adminPhoneWatchers(days: _days);

  Future<void> _ban(PhoneWatcher w) async {
    final note = await _askNote(context, 'Block ${w.fullName ?? 'this account'}?',
        ['Bot — collects phone numbers', 'Spam calls to agents', 'Fake account']);
    if (note == null) return;
    try {
      await context.read<AppState>().repo.adminReviewAccount(w.userId, 'ban', note: note);
      if (!mounted) return;
      showSnack(context, 'Account blocked');
      setState(() => _future = _load());
    } catch (e) {
      if (mounted) showSnack(context, '$e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return _Page(
      title: 'Phone views',
      subtitle: 'Who looks at phone numbers the most. Up to 15 numbers a day per person — '
          'someone always at the limit is probably a bot.',
      trailing: SegmentedButton<int>(
        segments: const [
          ButtonSegment(value: 1, label: Text('Today')),
          ButtonSegment(value: 7, label: Text('7 days')),
          ButtonSegment(value: 30, label: Text('30 days')),
        ],
        selected: {_days},
        onSelectionChanged: (s) => setState(() {
          _days = s.first;
          _future = _load();
        }),
      ),
      child: _Loader<List<PhoneWatcher>>(
        future: _future,
        builder: (list) {
          if (list.isEmpty) return _emptyDone('Nobody has looked at numbers yet.');
          return Column(children: [
            for (final w in list)
              _Card(
                highlight: w.reveals >= 15 * (_days == 1 ? 1 : 0.8) && !w.banned,
                child: Row(children: [
                  Container(
                    width: 52,
                    alignment: Alignment.center,
                    child: Text('${w.reveals}',
                        style: TextStyle(
                            fontSize: 24,
                            fontWeight: FontWeight.w700,
                            color: w.reveals >= 15 ? const Color(0xFFD64545) : Zc.green)),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(w.fullName ?? 'No name', style: const TextStyle(fontWeight: FontWeight.w600)),
                      SelectableText([if (w.email != null) w.email!, if (w.phone != null) w.phone!].join(' · '),
                          style: const TextStyle(fontSize: 12, color: Zc.grey)),
                      Text('${w.listings} listings · last ${timeAgo(w.lastAt)}${w.banned ? ' · blocked' : ''}',
                          style: const TextStyle(fontSize: 12, color: Zc.grey)),
                    ]),
                  ),
                  if (!w.banned) _actionBtn('Block', () => _ban(w), danger: true),
                ]),
              ),
          ]);
        },
      ),
    );
  }
}

// ======================================================================
// ADS — рекламные кампании и заявки «Здесь может быть ваша реклама»
// ======================================================================
(String, Color) _adPhase(Ad a) => switch (a.phase) {
      'draft' => ('Draft', Zc.grey),
      'live' => ('Running', const Color(0xFF2E9E5B)),
      'scheduled' => ('Starts ${formatShortDate(a.startsOn)}', Zc.orange),
      'paused' => ('Paused', Zc.grey),
      'finished' => ('Ended', Zc.green),
      _ => ('Stopped', const Color(0xFFD64545)),
    };

class _Ads extends StatefulWidget {
  const _Ads({required this.onChanged});
  final VoidCallback onChanged;

  @override
  State<_Ads> createState() => _AdsState();
}

class _AdsState extends State<_Ads> {
  late Future<List<dynamic>> _future = _load();

  Future<List<dynamic>> _load() async {
    final repo = context.read<AppState>().repo;
    final ads = await repo.adminAds();
    final stats = await Future.wait(ads.map((a) => repo.adStats(a.id)));
    return [ads, stats];
  }

  void _reload() {
    AdCache.clear();
    setState(() => _future = _load());
    widget.onChanged();
  }

  Future<void> _open({Ad? edit}) async {
    final saved = await Navigator.push<bool>(context, MaterialPageRoute(builder: (_) => AdWizard(edit: edit)));
    if (saved == true) _reload();
  }

  Future<void> _status(Ad a, String status) async {
    if (status == 'stopped') {
      final ok = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Stop this campaign?'),
          content: const Text('The banner disappears now. A stopped campaign cannot be started again.'),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
            TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Stop')),
          ],
        ),
      );
      if (ok != true) return;
    }
    try {
      await context.read<AppState>().repo.adminSetAdStatus(a.id, status);
      _reload();
    } catch (e) {
      if (mounted) showSnack(context, '$e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return _Page(
      title: 'Ads',
      subtitle: 'Banners on the home page, between listings and on listing pages. '
          'Each banner is marked "Sponsored".',
      trailing: _actionBtn('+ New campaign', () => _open(), primary: true),
      child: _Loader<List<dynamic>>(
        future: _future,
        builder: (data) {
          final ads = data[0] as List<Ad>;
          final stats = data[1] as List<CampaignStats>;
          return _adList(ads, stats);
        },
      ),
    );
  }

  Widget _adList(List<Ad> ads, List<CampaignStats> stats) {
    if (ads.isEmpty) {
      return _emptyDone('No ad campaigns yet. Until you add one, people see a sample banner.');
    }
    return Column(children: [
      for (var i = 0; i < ads.length; i++)
        Builder(builder: (context) {
          final a = ads[i], s = stats[i];
          final (label, color) = _adPhase(a);
          final canChange = a.phase != 'finished' && a.phase != 'stopped';
          return _Card(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                SizedBox(
                  width: 150,
                  child: AspectRatio(
                    aspectRatio: a.place.ratio,
                    child: PropImage(a.imageUrl, radius: 8),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(a.title, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
                    Text('${a.advertiser} · ${a.place.label}', style: const TextStyle(fontSize: 12, color: Zc.grey)),
                    Text('${formatShortDate(a.startsOn)} – ${formatShortDate(a.endsOn)}',
                        style: const TextStyle(fontSize: 12, color: Zc.grey)),
                    const SizedBox(height: 6),
                    Wrap(spacing: 8, runSpacing: 4, crossAxisAlignment: WrapCrossAlignment.center, children: [
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
                        decoration: BoxDecoration(color: color.withAlpha(28), borderRadius: BorderRadius.circular(10)),
                        child: Text(label, style: TextStyle(fontSize: 12, color: color, fontWeight: FontWeight.w600)),
                      ),
                      Text('${s.views} views · ${s.clicks} clicks · ${formatCtr(s.ctr)}',
                          style: const TextStyle(fontSize: 12)),
                    ]),
                  ]),
                ),
              ]),
              const SizedBox(height: 12),
              Wrap(spacing: 8, runSpacing: 8, children: [
                if (a.status == 'draft') ...[
                  _actionBtn('Launch', () => _status(a, 'active'), primary: true),
                  _actionBtn('Edit', () => _open(edit: a)),
                ],
                if (a.status == 'active' && canChange) _actionBtn('Pause', () => _status(a, 'paused')),
                if (a.status == 'paused' && canChange) _actionBtn('Resume', () => _status(a, 'active'), primary: true),
                if (a.status != 'draft' && canChange) _actionBtn('Stop', () => _status(a, 'stopped'), danger: true),
                _actionBtn('Stats', () => _showStats(a, s)),
              ]),
            ]),
          );
        }),
    ]);
  }

  void _showStats(Ad a, CampaignStats s) {
    final text = StringBuffer()
      ..writeln('Zumi — ad report')
      ..writeln('Advertiser: ${a.advertiser}')
      ..writeln('Campaign: ${a.title}')
      ..writeln('Placement: ${a.place.label}')
      ..writeln('Dates: ${formatShortDate(a.startsOn)} – ${formatShortDate(a.endsOn)}')
      ..writeln()
      ..writeln('Views: ${s.views} · Clicks: ${s.clicks} · Click rate: ${formatCtr(s.ctr)}');
    for (final d in s.days) {
      text.writeln('${formatShortDate(d.day)}: ${d.views} views, ${d.clicks} clicks');
    }
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(a.title),
        content: SingleChildScrollView(child: SelectableText(text.toString().trim())),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.pop(ctx);
              showShareSheet(context, text: text.toString().trim());
            },
            child: const Text('Send report'),
          ),
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Close')),
        ],
      ),
    );
  }
}

// ----------------------------------------------------------------------
// Мастер рекламной кампании
// ----------------------------------------------------------------------
class AdWizard extends StatefulWidget {
  const AdWizard({super.key, this.edit});
  final Ad? edit;

  @override
  State<AdWizard> createState() => _AdWizardState();
}

class _AdWizardState extends State<AdWizard> {
  final _d = AdDraft();
  final _advertiser = TextEditingController();
  final _title = TextEditingController();
  final _target = TextEditingController();
  String? _imageError;
  String? _imageInfo;
  bool _processing = false;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final e = widget.edit;
    if (e != null) {
      _d
        ..id = e.id
        ..targetType = e.targetType
        ..placement = e.placement
        ..imageUrl = e.imageUrl
        ..startsOn = e.startsOn
        ..endsOn = e.endsOn;
      _advertiser.text = e.advertiser;
      _title.text = e.title;
      _target.text = e.target;
    }
  }

  @override
  void dispose() {
    for (final c in [_advertiser, _title, _target]) {
      c.dispose();
    }
    super.dispose();
  }

  AdPlacement get _place => adPlacements[_d.placement]!;

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
      if (bytes.lengthInBytes > kBannerMaxBytes) {
        _fail('The file is too large (${(bytes.lengthInBytes / 1048576).toStringAsFixed(1)} MB). The maximum is 15 MB.');
        return;
      }
      final decoded = await decodeImageFromList(bytes);
      final w = decoded.width, h = decoded.height;
      decoded.dispose();
      final p = _place;
      if (w < p.minW || h < p.minH) {
        _fail('The image is too small: $w×$h px. For "${p.label}" use at least ${p.minW}×${p.minH} px (${p.ratioLabel}).');
        return;
      }
      var crop = (0.0, 0.0, 1.0, 1.0);
      if ((w / h - p.ratio).abs() > p.ratio * 0.02) {
        if (!mounted) return;
        final picked = await showBannerCrop(
          context,
          bytes: bytes,
          width: w,
          height: h,
          ratio: p.ratio,
          message: 'Your image is $w×$h px, but "${p.label}" needs ${p.ratioLabel} (for example ${p.outW}×${p.outH}). '
              'Choose which part to show.',
        );
        if (picked == null) {
          setState(() => _processing = false);
          return;
        }
        crop = picked;
      }
      final out = await cropBanner(bytes, crop.$1, crop.$2, crop.$3, crop.$4, outW: p.outW, outH: p.outH);
      if (out == null) {
        _fail('Could not read this image. Try a JPG or PNG.');
        return;
      }
      if (!mounted) return;
      setState(() {
        _d.image = out;
        _processing = false;
        _imageInfo = 'Ready: ${p.ratioLabel}, ${(out.lengthInBytes / 1024).round()} KB '
            '(was ${(bytes.lengthInBytes / 1024).round()} KB)';
      });
    } catch (_) {
      _fail('Could not read this image. Try a JPG or PNG.');
    }
  }

  void _fail(String msg) {
    if (!mounted) return;
    setState(() {
      _processing = false;
      _imageError = msg;
    });
  }

  Future<void> _pickDates() async {
    final t = DateTime.now();
    final r = await showDateRangePicker(
      context: context,
      firstDate: DateTime(t.year, t.month, t.day),
      lastDate: t.add(const Duration(days: 365)),
      initialDateRange: _d.startsOn == null ? null : DateTimeRange(start: _d.startsOn!, end: _d.endsOn!),
    );
    if (r != null) {
      setState(() {
        _d.startsOn = r.start;
        _d.endsOn = r.end;
      });
    }
  }

  String? _validate({required bool launch}) {
    if (_advertiser.text.trim().length < 2) return 'Write the advertiser';
    if (_title.text.trim().length < 2) return 'Write a title (for your list and the report)';
    final t = _target.text.trim();
    if (t.isEmpty) return 'Where does the banner lead? Add a link, phone or WhatsApp number';
    if (_d.targetType == 'link' && !t.contains('.')) return 'Enter a website link, e.g. https://…';
    if (_d.targetType != 'link' && t.replaceAll(RegExp(r'\D'), '').length < 9) return 'The phone number looks too short';
    if (launch && _d.image == null && _d.imageUrl == null) return 'Upload the banner image';
    if (launch && _d.startsOn == null) return 'Choose the start and end dates';
    return null;
  }

  Future<void> _save({required bool launch}) async {
    final err = _validate(launch: launch);
    if (err != null) {
      showSnack(context, err);
      return;
    }
    _d
      ..advertiser = _advertiser.text.trim()
      ..title = _title.text.trim()
      ..target = _target.text.trim();
    setState(() => _saving = true);
    final nav = Navigator.of(context);
    final messenger = ScaffoldMessenger.of(context);
    try {
      final ad = await context.read<AppState>().repo.adminSaveAd(_d, launch: launch);
      AdCache.clear();
      nav.pop(true);
      messenger.showSnackBar(SnackBar(
        content: Text(!launch
            ? 'Saved as draft'
            : (ad.isLive
                ? 'Running! It ends by itself after ${formatShortDate(ad.endsOn)}.'
                : 'Scheduled: it starts by itself on ${formatShortDate(ad.startsOn)}.')),
      ));
    } catch (e) {
      if (mounted) showSnack(context, '$e');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Ad get _previewAd => Ad(
        id: 'preview',
        advertiser: _advertiser.text,
        title: _title.text.isEmpty ? 'Your banner' : _title.text,
        targetType: _d.targetType,
        target: _target.text,
        placement: _d.placement,
        imageUrl: _d.imageUrl,
        startsOn: DateTime.now(),
        endsOn: DateTime.now(),
        createdAt: DateTime.now(),
      );

  Widget _h(String t, [String? sub]) => Padding(
        padding: const EdgeInsets.only(top: 22, bottom: 10),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(t, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600, color: Zc.green)),
          if (sub != null) Text(sub, style: const TextStyle(fontSize: 13, color: Zc.grey)),
        ]),
      );

  @override
  Widget build(BuildContext context) {
    final w = MediaQuery.sizeOf(context).width;
    final side = w > 820 ? (w - 760) / 2 : 20.0;
    final s = _d.startsOn, e = _d.endsOn;
    return Scaffold(
      appBar: AppBar(title: Text(widget.edit == null ? 'New ad campaign' : 'Edit ad campaign')),
      body: ListView(
        padding: EdgeInsets.fromLTRB(side, 4, side, 40),
        children: [
          _h('Advertiser and title'),
          TextField(controller: _advertiser, decoration: const InputDecoration(hintText: 'Advertiser, e.g. Zambezi Home Loans')),
          const SizedBox(height: 10),
          TextField(controller: _title, maxLength: 80, decoration: const InputDecoration(hintText: 'Title, e.g. Home loans from 12%', counterText: '')),
          _h('Where the banner leads'),
          Wrap(spacing: 8, children: [
            for (final (k, l) in const [('link', 'Website'), ('phone', 'Phone call'), ('whatsapp', 'WhatsApp')])
              ZChip(label: l, selected: _d.targetType == k, onTap: () => setState(() => _d.targetType = k)),
          ]),
          const SizedBox(height: 10),
          TextField(
            controller: _target,
            keyboardType: _d.targetType == 'link' ? TextInputType.url : TextInputType.phone,
            decoration: InputDecoration(hintText: _d.targetType == 'link' ? 'https://…' : '+260 97 …'),
          ),
          _h('Placement'),
          for (final p in adPlacements.values)
            GestureDetector(
              onTap: () => setState(() {
                if (_d.placement != p.key) {
                  _d.placement = p.key;
                  // другая пропорция — картинку нужно загрузить заново
                  _d.image = null;
                  _d.imageUrl = null;
                  _imageInfo = null;
                  _imageError = null;
                }
              }),
              child: Container(
                margin: const EdgeInsets.only(bottom: 8),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: _d.placement == p.key ? Zc.orangeSoft : Colors.white,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: _d.placement == p.key ? Zc.orange : Zc.chip, width: 1.3),
                ),
                child: Row(children: [
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text('${p.label} · ${p.ratioLabel}', style: const TextStyle(fontWeight: FontWeight.w600)),
                      Text('${p.hint} Image at least ${p.minW}×${p.minH} px.',
                          style: const TextStyle(fontSize: 12, color: Zc.grey)),
                    ]),
                  ),
                  RadioDot(selected: _d.placement == p.key, size: 20),
                ]),
              ),
            ),
          _h('Image', 'JPG, PNG or WebP. We check the size, crop to ${_place.ratioLabel} and compress it.'),
          GestureDetector(
            onTap: _processing ? null : _pickImage,
            child: AspectRatio(
              aspectRatio: _place.ratio,
              child: Container(
                decoration: BoxDecoration(
                  color: Zc.field,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: _imageError != null ? const Color(0xFFD64545) : Zc.green, width: 0.8),
                ),
                clipBehavior: Clip.antiAlias,
                child: _processing
                    ? const Center(child: CircularProgressIndicator(color: Zc.orange))
                    : _d.image != null
                        ? Image.memory(_d.image!, fit: BoxFit.cover)
                        : (_d.imageUrl != null
                            ? PropImage(_d.imageUrl)
                            : const Center(
                                child: Text('Tap to upload', style: TextStyle(color: Zc.grey, fontSize: 16)))),
              ),
            ),
          ),
          const SizedBox(height: 6),
          if (_imageError != null)
            Text(_imageError!, style: const TextStyle(color: Color(0xFFD64545), fontSize: 13)),
          if (_imageInfo != null) Text(_imageInfo!, style: const TextStyle(color: Color(0xFF2E9E5B), fontSize: 13)),

          _h('Preview on a phone'),
          Center(
            child: Container(
              width: 360,
              padding: const EdgeInsets.fromLTRB(12, 16, 12, 16),
              decoration: BoxDecoration(
                color: Zc.bg,
                borderRadius: BorderRadius.circular(32),
                border: Border.all(color: const Color(0xFF2B2B2B), width: 8),
              ),
              child: Column(children: [
                if (_d.placement == 'feed_strip') ...[
                  const _FakeCard(),
                  const SizedBox(height: 10),
                ],
                if (_d.placement == 'listing_block') ...[
                  const Align(
                    alignment: Alignment.centerLeft,
                    child: Text('Description', style: TextStyle(fontWeight: FontWeight.w600, color: Zc.green)),
                  ),
                  const SizedBox(height: 4),
                  const _FakeLines(),
                  const SizedBox(height: 10),
                ],
                AdBanner(ad: _previewAd, imageBytes: _d.image, preview: true, radius: 12),
                if (_d.placement != 'listing_block') ...[
                  const SizedBox(height: 10),
                  const _FakeCard(),
                ],
              ]),
            ),
          ),

          _h('Dates', 'Starts by itself on the first day and ends by itself after the last day.'),
          OutlinedButton.icon(
            style: OutlinedButton.styleFrom(
              foregroundColor: Zc.green,
              side: const BorderSide(color: Zc.green),
              padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 16),
            ),
            onPressed: _pickDates,
            icon: const Icon(ZI.calendar),
            label: Text(s == null ? 'Choose dates' : '${formatShortDate(s)} — ${formatShortDate(e!)}'),
          ),
          const SizedBox(height: 26),
          Row(children: [
            Expanded(
              child: OutlinedButton(
                style: OutlinedButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 16)),
                onPressed: _saving ? null : () => _save(launch: false),
                child: const Text('Save draft'),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              flex: 2,
              child: PrimaryButton(label: 'Launch', loading: _saving, width: double.infinity, onPressed: () => _save(launch: true)),
            ),
          ]),
        ],
      ),
    );
  }
}

/// Серые «заглушки» карточки и текста в предпросмотре
class _FakeCard extends StatelessWidget {
  const _FakeCard();

  @override
  Widget build(BuildContext context) => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        AspectRatio(
          aspectRatio: 1.6,
          child: Container(decoration: BoxDecoration(color: Zc.chip, borderRadius: BorderRadius.circular(12))),
        ),
        const SizedBox(height: 6),
        const _FakeLines(),
      ]);
}

class _FakeLines extends StatelessWidget {
  const _FakeLines();

  @override
  Widget build(BuildContext context) => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        for (final w in const [0.6, 0.9, 0.5])
          FractionallySizedBox(
            widthFactor: w,
            child: Container(
              height: 9,
              margin: const EdgeInsets.only(bottom: 5),
              decoration: BoxDecoration(color: Zc.chip, borderRadius: BorderRadius.circular(4)),
            ),
          ),
      ]);
}

// ----------------------------------------------------------------------
// Бесплатное продвижение агенту (пока нет оплаты)
// ----------------------------------------------------------------------
Future<void> _grantPromotion(BuildContext context, AccountItem a) async {
  final repo = context.read<AppState>().repo;
  List<Property> listings;
  try {
    listings = await repo.adminAgentListings(a.id);
  } catch (e) {
    if (context.mounted) showSnack(context, '$e');
    return;
  }
  if (!context.mounted) return;
  if (listings.isEmpty) {
    showSnack(context, '${a.fullName ?? 'This agent'} has no active listings to promote');
    return;
  }
  Property? pick = listings.first;
  var days = 7;
  var placement = 'search_top';
  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setS) => AlertDialog(
        title: Text('Free promotion for ${a.fullName ?? 'agent'}'),
        content: SizedBox(
          width: 420,
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('Listing', style: TextStyle(fontWeight: FontWeight.w600)),
            const SizedBox(height: 6),
            DropdownButton<Property>(
              isExpanded: true,
              value: pick,
              items: [
                for (final p in listings)
                  DropdownMenuItem(value: p, child: Text(p.title, overflow: TextOverflow.ellipsis)),
              ],
              onChanged: (p) => setS(() => pick = p),
            ),
            const SizedBox(height: 12),
            const Text('Days', style: TextStyle(fontWeight: FontWeight.w600)),
            const SizedBox(height: 6),
            Wrap(spacing: 8, children: [
              for (final d in const [3, 7, 14, 30])
                ZChip(label: '$d days', selected: days == d, onTap: () => setS(() => days = d)),
            ]),
            const SizedBox(height: 12),
            const Text('Where', style: TextStyle(fontWeight: FontWeight.w600)),
            const SizedBox(height: 6),
            Wrap(spacing: 8, runSpacing: 8, children: [
              for (final e in campaignPlacements.entries)
                ZChip(label: e.value.$1, selected: placement == e.key, onTap: () => setS(() => placement = e.key)),
            ]),
          ]),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Give promotion')),
        ],
      ),
    ),
  );
  if (ok != true || pick == null) return;
  try {
    await repo.adminGrantPromotion(a.id, pick!.id, days, placement: placement);
    if (context.mounted) showSnack(context, 'Promotion given for $days days — it starts today');
  } catch (e) {
    if (context.mounted) showSnack(context, '$e');
  }
}
