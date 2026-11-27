part of 'admin_screen.dart';

/// Admin → Risk: подозрительные объявления по убыванию риска (миграция 042).
/// Автоматически сервер делает только обратимое (на проверку, предупреждение в чате).
/// Бан — только владелец Zumi, кнопкой здесь.
class _RiskAdmin extends StatefulWidget {
  const _RiskAdmin({required this.owner});
  final bool owner;

  @override
  State<_RiskAdmin> createState() => _RiskAdminState();
}

class _RiskAdminState extends State<_RiskAdmin> {
  late Future<List<RiskItem>> _f = context.read<AppState>().repo.adminRiskList();

  void _reload() => setState(() => _f = context.read<AppState>().repo.adminRiskList());

  Future<void> _act(RiskItem it, String action) async {
    final repo = context.read<AppState>().repo;
    if (action == 'ban' || action == 'hide') {
      final ok = await showDialog<bool>(
        context: context,
        builder: (_) => AlertDialog(
          title: Text(action == 'ban' ? 'Block ${it.ownerName}?' : 'Hide this listing?'),
          content: Text(action == 'ban'
              ? 'The account is blocked and all its listings are hidden. You can unblock it later in Reports.'
              : 'The listing disappears from Zumi. The owner sees it as hidden.'),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
            FilledButton(onPressed: () => Navigator.pop(context, true), child: Text(action == 'ban' ? 'Block' : 'Hide')),
          ],
        ),
      );
      if (ok != true) return;
    }
    try {
      await repo.adminRiskAction(it.propertyId, action);
      if (!mounted) return;
      showSnack(context, switch (action) {
        'safe' => 'Marked as safe — back in search',
        'review' => 'Sent to review',
        'hide' => 'Listing hidden',
        _ => 'Account blocked',
      });
      _reload();
    } catch (e) {
      if (mounted) showSnack(context, '$e');
    }
  }

  Future<void> _recalc() async {
    try {
      final n = await context.read<AppState>().repo.adminRiskRecalc();
      if (!mounted) return;
      showSnack(context, 'Checked $n listings');
      _reload();
    } catch (e) {
      if (mounted) showSnack(context, '$e');
    }
  }

  Color _color(int s) => s >= 70
      ? const Color(0xFFB3261E)
      : s >= 40
          ? const Color(0xFFC77700)
          : s > 0
              ? const Color(0xFF6E7A74)
              : Zc.green;

  @override
  Widget build(BuildContext context) {
    return _Page(
      title: 'Risk',
      subtitle: 'Listings that look suspicious, highest risk first. Repeats by the same agency or by verified agents '
          'with a similar price are normal — they are grouped, not punished.',
      trailing: Row(mainAxisSize: MainAxisSize.min, children: [
        IconButton(tooltip: 'Check all again', onPressed: _recalc, icon: const Icon(ZI.sort)),
        if (widget.owner)
          IconButton(
            tooltip: 'Weights, limits and chat words',
            onPressed: () => showModalBottomSheet<void>(
              context: context,
              isScrollControlled: true,
              backgroundColor: Zc.bg,
              builder: (_) => const _RiskSettingsSheet(),
            ),
            icon: const Icon(ZI.settings),
          ),
      ]),
      child: FutureBuilder<List<RiskItem>>(
        future: _f,
        builder: (context, snap) {
          if (snap.hasError) {
            return Padding(
              padding: const EdgeInsets.all(16),
              child: Text('Run migration 042_trust_safety.sql in Supabase to turn this on.\n\n${snap.error}',
                  style: const TextStyle(color: Zc.grey)),
            );
          }
          if (!snap.hasData) {
            return const Padding(
                padding: EdgeInsets.all(30), child: Center(child: CircularProgressIndicator(color: Zc.orange)));
          }
          final list = snap.data!;
          if (list.isEmpty) return _emptyDone('Nothing suspicious right now.');
          return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            for (final it in list)
              Container(
                margin: const EdgeInsets.only(bottom: 12),
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: it.score >= 40 ? _color(it.score) : Zc.chip),
                ),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Container(
                      width: 46,
                      padding: const EdgeInsets.symmetric(vertical: 6),
                      decoration: BoxDecoration(color: _color(it.score), borderRadius: BorderRadius.circular(10)),
                      child: Text('${it.score}',
                          textAlign: TextAlign.center,
                          style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 16)),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text(it.title, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15)),
                        Text(
                          [
                            money(it.price, it.currency) + (it.rentPeriod == 'month' ? ' /mo' : ''),
                            if (it.areaName != null) it.areaName!,
                            it.agencyName ?? it.ownerName,
                            it.status,
                            if (it.groupSize > 1) 'same home ×${it.groupSize}',
                            if (it.ownerBanned) 'BLOCKED',
                          ].join(' · '),
                          style: const TextStyle(fontSize: 12.5, color: Zc.grey),
                        ),
                      ]),
                    ),
                  ]),
                  const SizedBox(height: 10),
                  for (final r in it.reasons)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 4),
                      child: Text('• ${r.text}  (+${r.points})', style: const TextStyle(fontSize: 13.5, height: 1.35)),
                    ),
                  if (it.accountScore > 0)
                    Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Text(
                        'Account risk ${it.accountScore}: ${it.accountReasons.map((r) => r.text).join('; ')}',
                        style: const TextStyle(fontSize: 12.5, color: Zc.grey),
                      ),
                    ),
                  if (it.clearedScore != null)
                    const Padding(
                      padding: EdgeInsets.only(top: 4),
                      child: Text('The team already marked this as safe.',
                          style: TextStyle(fontSize: 12.5, color: Zc.green)),
                    ),
                  const SizedBox(height: 8),
                  Wrap(spacing: 8, runSpacing: 8, children: [
                    OutlinedButton(
                      onPressed: () async {
                        final nav = Navigator.of(context);
                        final p = await context.read<AppState>().repo.getProperty(it.propertyId);
                        if (p != null) nav.push(MaterialPageRoute(builder: (_) => PropertyScreen(property: p)));
                      },
                      child: const Text('Open'),
                    ),
                    FilledButton(
                      style: FilledButton.styleFrom(backgroundColor: Zc.green),
                      onPressed: () => _act(it, 'safe'),
                      child: const Text('Looks fine'),
                    ),
                    if (it.status == 'active')
                      OutlinedButton(onPressed: () => _act(it, 'review'), child: const Text('Send to review')),
                    OutlinedButton(onPressed: () => _act(it, 'hide'), child: const Text('Hide')),
                    if (widget.owner && !it.ownerBanned && it.ownerId != null)
                      OutlinedButton(
                        style: OutlinedButton.styleFrom(foregroundColor: const Color(0xFFB3261E)),
                        onPressed: () => _act(it, 'ban'),
                        child: const Text('Block account'),
                      ),
                  ]),
                ]),
              ),
          ]);
        },
      ),
    );
  }
}

/// Веса, пороги и стоп-слова чата (меняет только владелец Zumi)
class _RiskSettingsSheet extends StatefulWidget {
  const _RiskSettingsSheet();

  @override
  State<_RiskSettingsSheet> createState() => _RiskSettingsSheetState();
}

class _RiskSettingsSheetState extends State<_RiskSettingsSheet> {
  static const _labels = <String, String>{
    'review_at': 'Send to review from risk',
    'warn_at': 'Warn people in chat from risk',
    'w_photo_dup': 'Points: same photos as a verified listing',
    'w_text_dup': 'Points: copied text',
    'w_low_price': 'Points: price far below the area',
    'w_chat_payment': 'Points: asks for money in chat',
    'w_chat_link': 'Points: links in chat',
    'w_new_burst': 'Points: new account, too much activity',
    'w_report': 'Points: each report',
    'w_report_scam': 'Points: each scam / prepayment report',
    'price_drop': 'Price lower than typical by (0.4 = 40%)',
    'min_comparables': 'Need at least N similar listings to compare price',
    'group_price_diff': 'Same home: price may differ by (0.15 = 15%)',
    'photo_distance': 'Photos count as the same up to (0–64, lower = stricter)',
    'text_similarity': 'Text counts as copied from (0–1)',
    'new_days': 'Account counts as new for N days',
    'burst_listings': 'New account: more than N listings a day',
    'burst_chats': 'New account: messaged more than N people a day',
    'trusted_days': 'Trusted after N days without confirmed reports',
  };
  final _ctrls = <String, TextEditingController>{};
  final _words = TextEditingController();
  bool _loading = true;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    context.read<AppState>().repo.adminRiskSettings().then((s) {
      if (!mounted) return;
      setState(() {
        for (final e in s.config.entries) {
          _ctrls[e.key] = TextEditingController(text: '${e.value}');
        }
        _words.text = s.stopWords;
        _loading = false;
      });
    }).catchError((e) {
      if (mounted) {
        showSnack(context, '$e');
        Navigator.pop(context);
      }
    });
  }

  @override
  void dispose() {
    for (final c in _ctrls.values) {
      c.dispose();
    }
    _words.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final cfg = <String, num>{};
    for (final e in _ctrls.entries) {
      final v = num.tryParse(e.value.text.trim());
      if (v == null || v < 0) {
        showSnack(context, 'Check "${_labels[e.key] ?? e.key}"');
        return;
      }
      cfg[e.key] = v;
    }
    setState(() => _saving = true);
    try {
      await context.read<AppState>().repo.adminSetRiskSettings(cfg, _words.text.trim());
      if (!mounted) return;
      Navigator.pop(context);
      showSnack(context, 'Saved. Tap "Check all again" to apply to existing listings.');
    } catch (e) {
      if (mounted) showSnack(context, '$e');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final keys = [..._labels.keys.where(_ctrls.containsKey), ..._ctrls.keys.where((k) => !_labels.containsKey(k))];
    return Padding(
      padding: EdgeInsets.fromLTRB(20, 18, 20, 20 + MediaQuery.viewInsetsOf(context).bottom),
      child: _loading
          ? const SizedBox(height: 200, child: Center(child: CircularProgressIndicator(color: Zc.orange)))
          : SingleChildScrollView(
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
                const Text('Risk settings', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w600, color: Zc.green)),
                const SizedBox(height: 14),
                const Text('Chat stop words (comma separated)', style: TextStyle(fontWeight: FontWeight.w600)),
                const SizedBox(height: 6),
                TextField(controller: _words, maxLines: 4, maxLength: 3000),
                const SizedBox(height: 8),
                for (final k in keys)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: Row(children: [
                      Expanded(child: Text(_labels[k] ?? k, style: const TextStyle(fontSize: 13.5))),
                      const SizedBox(width: 10),
                      SizedBox(
                        width: 80,
                        child: TextField(
                          controller: _ctrls[k],
                          keyboardType: const TextInputType.numberWithOptions(decimal: true),
                          textAlign: TextAlign.center,
                        ),
                      ),
                    ]),
                  ),
                const SizedBox(height: 10),
                FilledButton(
                  style: FilledButton.styleFrom(backgroundColor: Zc.green, minimumSize: const Size.fromHeight(48)),
                  onPressed: _saving ? null : _save,
                  child: Text(_saving ? 'Saving…' : 'Save'),
                ),
              ]),
            ),
    );
  }
}
