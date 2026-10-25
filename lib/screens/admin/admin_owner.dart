part of 'admin_screen.dart';

// ======================================================================
// STATISTICS — панель владельца (только числа, без имён)
// ======================================================================
class _Stats extends StatefulWidget {
  const _Stats();

  @override
  State<_Stats> createState() => _StatsState();
}

class _StatsState extends State<_Stats> {
  String _period = 'day';
  late Future<Dashboard> _future = _load();

  Future<Dashboard> _load() => context.read<AppState>().repo.ownerDashboard(_period);

  void _set(String p) => setState(() {
        _period = p;
        _future = _load();
      });

  Future<void> _export(Dashboard d) async {
    final name = 'zumi-stats-${d.period}-${isoDay(d.to)}.csv';
    final downloaded = await saveTextFile(name, d.toCsv());
    if (!mounted) return;
    showSnack(context, downloaded ? 'Downloaded $name' : 'Table copied — paste it into Google Sheets or an email');
  }

  @override
  Widget build(BuildContext context) {
    return _Page(
      title: 'Statistics',
      subtitle: 'Anonymous numbers only — no names. Time in Lusaka.',
      trailing: SegmentedButton<String>(
        segments: const [
          ButtonSegment(value: 'day', label: Text('Today')),
          ButtonSegment(value: 'week', label: Text('7 days')),
          ButtonSegment(value: 'month', label: Text('30 days')),
        ],
        selected: {_period},
        onSelectionChanged: (s) => _set(s.first),
      ),
      child: _Loader<Dashboard>(
        future: _future,
        builder: (d) {
          final day = d.period == 'day';
          final tiles = <(String, String, String?, bool)>[
            // (название, значение, пояснение, главный показатель)
            ('Contacts', _fmt(d.contacts), '${_fmt(d.t('phone_views'))} number views · ${_fmt(d.t('new_chats'))} new chats', true),
            ('Visits', _fmt(d.t('visits')), 'App and website openings', false),
            (day ? 'Visitors today' : 'Visitors a day', _fmt(day ? d.t('visitors_today') : d.t('visitors_avg')),
                day ? 'Different people' : 'Average per day', false),
            ('New users', _fmt(d.t('new_users')), '${_fmt(d.t('users_total'))} in total', false),
            ('New listings', _fmt(d.t('new_listings')), '${_fmt(d.t('active_listings'))} active now', false),
            ('Ads', '${_fmt(d.t('ad_views'))} / ${_fmt(d.t('ad_clicks'))}', 'Views / clicks', false),
            ('Promotion', '${_fmt(d.t('promo_views'))} / ${_fmt(d.t('promo_clicks'))}', 'Views / clicks', false),
            ('Reports', _fmt(d.t('reports')), 'Problem and scam reports', false),
            ('Blocked', _fmt(d.t('bans')), 'Accounts blocked', false),
          ];
          return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            LayoutBuilder(builder: (context, c) {
              final cols = c.maxWidth > 900 ? 4 : (c.maxWidth > 560 ? 3 : 2);
              final w = (c.maxWidth - (cols - 1) * 12) / cols;
              return Wrap(spacing: 12, runSpacing: 12, children: [
                for (final (title, value, note, main) in tiles)
                  SizedBox(width: main ? (cols > 2 ? w * 2 + 12 : c.maxWidth) : w, child: _Kpi(title, value, note, main)),
              ]);
            }),
            const SizedBox(height: 22),
            _Card(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(day ? 'Visits by hour' : 'Visits by day', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
                const SizedBox(height: 12),
                _Bars(points: d.series, value: (p) => p.visits, color: Zc.green),
                const SizedBox(height: 18),
                const Text('Contacts (number views + new chats)', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
                const SizedBox(height: 12),
                _Bars(points: d.series, value: (p) => p.contacts, color: Zc.orange),
              ]),
            ),
            LayoutBuilder(builder: (context, c) {
              final areas = _TopList(
                title: 'Popular neighbourhoods',
                subtitle: 'How often people searched them',
                rows: [for (final (name, n) in d.topAreas) (name, n)],
              );
              final filters = _TopList(
                title: 'Popular filters',
                subtitle: 'What people narrow the search by',
                rows: [for (final (dim, value, n) in d.topFilters) ('${_dimLabel(dim)}: $value', n)],
              );
              if (c.maxWidth < 700) return Column(children: [areas, filters]);
              return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Expanded(child: areas),
                const SizedBox(width: 12),
                Expanded(child: filters),
              ]);
            }),
            const SizedBox(height: 8),
            Wrap(spacing: 10, runSpacing: 8, crossAxisAlignment: WrapCrossAlignment.center, children: [
              _actionBtn('Download table (CSV)', () => _export(d), primary: true),
              const Text('Opens in Excel or Google Sheets — for reports to advertisers.',
                  style: TextStyle(fontSize: 12, color: Zc.grey)),
            ]),
          ]);
        },
      ),
    );
  }
}

String _fmt(int n) {
  final s = '$n';
  final b = StringBuffer();
  for (var i = 0; i < s.length; i++) {
    if (i > 0 && (s.length - i) % 3 == 0) b.write(',');
    b.write(s[i]);
  }
  return b.toString();
}

String _dimLabel(String dim) => switch (dim) {
      'deal' => 'Deal',
      'type' => 'Type',
      'beds' => 'Bedrooms',
      'price' => 'Price',
      'verified' => 'Verified only',
      'furnished' => 'Furnished',
      _ => dim,
    };

class _Kpi extends StatelessWidget {
  const _Kpi(this.title, this.value, this.note, this.main);
  final String title;
  final String value;
  final String? note;
  final bool main;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: main ? Zc.orangeSoft : Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: main ? Zc.orange : Zc.chip),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Expanded(child: Text(title, style: const TextStyle(fontSize: 13, color: Zc.grey))),
            if (main)
              const Text('main number', style: TextStyle(fontSize: 11, color: Zc.orange, fontWeight: FontWeight.w600)),
          ]),
          const SizedBox(height: 4),
          Text(value, style: TextStyle(fontSize: main ? 32 : 26, fontWeight: FontWeight.w700, color: Zc.green)),
          if (note != null) Text(note!, style: const TextStyle(fontSize: 12, color: Zc.grey)),
        ]),
      );
}

/// Простой столбчатый график
class _Bars extends StatelessWidget {
  const _Bars({required this.points, required this.value, required this.color});
  final List<DashPoint> points;
  final int Function(DashPoint) value;
  final Color color;

  String _label(String t) => t.length >= 10 ? '${t.substring(8, 10)}.${t.substring(5, 7)}' : t.substring(0, 2);

  @override
  Widget build(BuildContext context) {
    if (points.isEmpty) return const Text('No data yet', style: TextStyle(color: Zc.grey));
    final maxV = points.map(value).fold<int>(0, (a, b) => a > b ? a : b);
    final every = points.length > 16 ? (points.length / 8).ceil() : (points.length > 8 ? 3 : 1);
    return SizedBox(
      height: 150,
      child: Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
        for (var i = 0; i < points.length; i++)
          Expanded(
            child: Tooltip(
              message: '${points[i].t}: ${value(points[i])}',
              child: Column(mainAxisAlignment: MainAxisAlignment.end, children: [
                Container(
                  margin: const EdgeInsets.symmetric(horizontal: 1.5),
                  height: maxV == 0 ? 2 : 2 + 116 * value(points[i]) / maxV,
                  decoration: BoxDecoration(
                    color: color.withAlpha(value(points[i]) == 0 ? 40 : 220),
                    borderRadius: const BorderRadius.vertical(top: Radius.circular(3)),
                  ),
                ),
                const SizedBox(height: 4),
                SizedBox(
                  height: 16,
                  child: i % every == 0
                      ? FittedBox(
                          child: Text(_label(points[i].t), style: const TextStyle(fontSize: 10, color: Zc.grey)))
                      : null,
                ),
              ]),
            ),
          ),
      ]),
    );
  }
}

class _TopList extends StatelessWidget {
  const _TopList({required this.title, required this.subtitle, required this.rows});
  final String title;
  final String subtitle;
  final List<(String, int)> rows;

  @override
  Widget build(BuildContext context) {
    final maxN = rows.isEmpty ? 1 : rows.map((r) => r.$2).reduce((a, b) => a > b ? a : b);
    return _Card(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(title, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
        Text(subtitle, style: const TextStyle(fontSize: 12, color: Zc.grey)),
        const SizedBox(height: 10),
        if (rows.isEmpty) const Text('No searches yet', style: TextStyle(color: Zc.grey)),
        for (final (name, n) in rows)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Row(children: [
              Expanded(flex: 3, child: Text(name, maxLines: 1, overflow: TextOverflow.ellipsis)),
              Expanded(
                flex: 2,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: LinearProgressIndicator(
                    value: n / (maxN == 0 ? 1 : maxN),
                    minHeight: 8,
                    color: Zc.green,
                    backgroundColor: Zc.chip,
                  ),
                ),
              ),
              SizedBox(width: 48, child: Text(_fmt(n), textAlign: TextAlign.right, style: const TextStyle(fontSize: 13))),
            ]),
          ),
      ]),
    );
  }
}

// ======================================================================
// HELP ARTICLES — правка статей без обновления приложения + оценки
// ======================================================================
class _HelpAdmin extends StatefulWidget {
  const _HelpAdmin();

  @override
  State<_HelpAdmin> createState() => _HelpAdminState();
}

class _HelpAdminState extends State<_HelpAdmin> {
  bool _ratings = false;
  late Future<List<HelpArticle>> _articles = context.read<AppState>().repo.adminHelpArticles();
  late Future<List<HelpRating>> _rates = context.read<AppState>().repo.adminHelpRatings();

  void _reload() => setState(() {
        _articles = context.read<AppState>().repo.adminHelpArticles();
        _rates = context.read<AppState>().repo.adminHelpRatings();
      });

  Future<void> _edit([HelpArticle? a]) async {
    final saved = await Navigator.push<bool>(context, MaterialPageRoute(builder: (_) => _ArticleEditor(article: a)));
    if (saved == true) _reload();
  }

  @override
  Widget build(BuildContext context) {
    return _Page(
      title: 'Help articles',
      subtitle: 'Changes appear in the app at once — no app update needed.',
      trailing: Wrap(spacing: 10, runSpacing: 8, children: [
        SegmentedButton<bool>(
          segments: const [
            ButtonSegment(value: false, label: Text('Articles')),
            ButtonSegment(value: true, label: Text('Ratings')),
          ],
          selected: {_ratings},
          onSelectionChanged: (s) => setState(() => _ratings = s.first),
        ),
        if (!_ratings) _actionBtn('+ New article', () => _edit(), primary: true),
      ]),
      child: _ratings ? _ratingList() : _articleList(),
    );
  }

  Widget _articleList() => _Loader<List<HelpArticle>>(
        future: _articles,
        builder: (list) {
          if (list.isEmpty) return _emptyDone('No articles yet.');
          return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            for (final cat in helpCategories.keys)
              if (list.any((a) => a.category == cat)) ...[
                Padding(
                  padding: const EdgeInsets.only(top: 8, bottom: 6),
                  child: Text(helpCategories[cat]!, style: const TextStyle(fontWeight: FontWeight.w600, color: Zc.green)),
                ),
                for (final a in list.where((a) => a.category == cat))
                  _Card(
                    child: InkWell(
                      onTap: () => _edit(a),
                      child: Row(children: [
                        Expanded(
                          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                            Text(a.title, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
                            Text(
                              [
                                if (!a.published) 'Hidden',
                                if (a.webOnly) 'Website only',
                                if (a.updatedAt != null) 'Updated ${timeAgo(a.updatedAt!)}',
                              ].join(' · '),
                              style: const TextStyle(fontSize: 12, color: Zc.grey),
                            ),
                          ]),
                        ),
                        const Icon(ZI.edit, color: Zc.grey, size: 18),
                      ]),
                    ),
                  ),
              ],
          ]);
        },
      );

  Widget _ratingList() => _Loader<List<HelpRating>>(
        future: _rates,
        builder: (list) {
          final rated = list.where((r) => r.total > 0).toList();
          if (rated.isEmpty) return _emptyDone('No ratings yet.');
          return Column(children: [
            for (final r in rated)
              _Card(
                highlight: r.no > r.yes,
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Row(children: [
                    Expanded(child: Text(r.title, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600))),
                    _vote(ZI.check, r.yes, const Color(0xFF2E9E5B)),
                    const SizedBox(width: 10),
                    _vote(ZI.close, r.no, const Color(0xFFD64545)),
                  ]),
                  Text('${(r.helpfulShare * 100).round()}% found it helpful · ${helpCategories[r.category] ?? r.category}',
                      style: const TextStyle(fontSize: 12, color: Zc.grey)),
                  if (r.comments.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    for (final (text, at) in r.comments.take(5))
                      Padding(
                        padding: const EdgeInsets.only(bottom: 6),
                        child: Text('"$text" — ${timeAgo(at)}', style: const TextStyle(fontSize: 13, height: 1.35)),
                      ),
                  ],
                  Align(
                    alignment: Alignment.centerRight,
                    child: TextButton(
                      onPressed: () async {
                        final all = await _articles;
                        final a = all.where((x) => x.id == r.articleId).firstOrNull;
                        if (a != null) _edit(a);
                      },
                      child: const Text('Improve the article', style: TextStyle(color: Zc.orange)),
                    ),
                  ),
                ]),
              ),
          ]);
        },
      );

  Widget _vote(IconData icon, int n, Color c) => Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(icon, size: 16, color: c),
        const SizedBox(width: 3),
        Text('$n', style: TextStyle(color: c, fontWeight: FontWeight.w600)),
      ]);
}

class _ArticleEditor extends StatefulWidget {
  const _ArticleEditor({this.article});
  final HelpArticle? article;

  @override
  State<_ArticleEditor> createState() => _ArticleEditorState();
}

class _ArticleEditorState extends State<_ArticleEditor> {
  late final _title = TextEditingController(text: widget.article?.title ?? '');
  late final _body = TextEditingController(text: widget.article?.body ?? '');
  late final _sort = TextEditingController(text: '${widget.article?.sort ?? 100}');
  late String _category = widget.article?.category ?? 'account';
  late bool _published = widget.article?.published ?? true;
  late bool _webOnly = widget.article?.webOnly ?? false;
  bool _preview = false;
  bool _saving = false;

  bool get _isNew => widget.article == null;

  @override
  void dispose() {
    for (final c in [_title, _body, _sort]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _save() async {
    if (_title.text.trim().length < 3) {
      showSnack(context, 'Write a title');
      return;
    }
    if (_body.text.trim().length < 10) {
      showSnack(context, 'Write the article text');
      return;
    }
    if (_category == 'promotion' && !_webOnly && RegExp(r'pay|price|ZMW|\$', caseSensitive: false).hasMatch(_body.text)) {
      final ok = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('About payment?'),
          content: const Text(
            'Apple and Google do not allow apps to send people to pay on a website. If this article explains '
            'payment on the website, turn on "Website only".',
            style: TextStyle(height: 1.4),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Go back')),
            TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Save anyway')),
          ],
        ),
      );
      if (ok != true) return;
    }
    if (!mounted) return;
    setState(() => _saving = true);
    final a = HelpArticle(
      id: widget.article?.id ?? '',
      category: _category,
      title: _title.text.trim(),
      body: _body.text.trim(),
      sort: int.tryParse(_sort.text.trim()) ?? 100,
      published: _published,
      webOnly: _webOnly,
    );
    try {
      await context.read<AppState>().repo.adminSaveHelpArticle(a, isNew: _isNew);
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) showSnack(context, '$e');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _delete() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete this article?'),
        content: const Text('Its ratings are deleted too. To hide it for a while, turn off "Published" instead.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Delete')),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    try {
      await context.read<AppState>().repo.adminDeleteHelpArticle(widget.article!.id);
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) showSnack(context, '$e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_isNew ? 'New help article' : 'Edit help article'),
        actions: [
          if (!_isNew) IconButton(onPressed: _delete, icon: const Icon(ZI.trash), tooltip: 'Delete'),
          Padding(
            padding: const EdgeInsets.only(right: 12),
            child: FilledButton(
              style: FilledButton.styleFrom(backgroundColor: Zc.orange),
              onPressed: _saving ? null : _save,
              child: Text(_saving ? 'Saving…' : 'Save'),
            ),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 40),
        children: [
          Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 760),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  Expanded(
                    child: DropdownButtonFormField<String>(
                      value: _category,
                      decoration: const InputDecoration(labelText: 'Section'),
                      items: [
                        for (final e in helpCategories.entries) DropdownMenuItem(value: e.key, child: Text(e.value)),
                      ],
                      onChanged: (v) => setState(() => _category = v ?? _category),
                    ),
                  ),
                  const SizedBox(width: 12),
                  SizedBox(
                    width: 110,
                    child: TextField(
                      controller: _sort,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(labelText: 'Order'),
                    ),
                  ),
                ]),
                const SizedBox(height: 12),
                TextField(
                  controller: _title,
                  maxLength: 140,
                  decoration: const InputDecoration(labelText: 'Title — a question people ask'),
                ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  value: _published,
                  activeColor: Zc.orange,
                  onChanged: (v) => setState(() => _published = v),
                  title: const Text('Published'),
                  subtitle: const Text('Off — the article is hidden from users', style: TextStyle(fontSize: 12)),
                ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  value: _webOnly,
                  activeColor: Zc.orange,
                  onChanged: (v) => setState(() => _webOnly = v),
                  title: const Text('Website only'),
                  subtitle: const Text(
                    'Not shown in the iPhone and Android apps. Use it for articles about paying on the website — '
                    'Apple and Google do not allow apps to point to website payments.',
                    style: TextStyle(fontSize: 12),
                  ),
                ),
                const SizedBox(height: 8),
                Row(children: [
                  const Expanded(
                    child: Text('Text: empty line — new paragraph · "## " — subheading · "- " — list item',
                        style: TextStyle(fontSize: 12, color: Zc.grey)),
                  ),
                  TextButton(
                    onPressed: () => setState(() => _preview = !_preview),
                    child: Text(_preview ? 'Edit' : 'Preview', style: const TextStyle(color: Zc.green)),
                  ),
                ]),
                const SizedBox(height: 6),
                _preview
                    ? Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12)),
                        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Text(_title.text, style: zHeadline(context, size: 24)),
                          const SizedBox(height: 10),
                          HelpBody(text: _body.text),
                        ]),
                      )
                    : TextField(
                        controller: _body,
                        minLines: 14,
                        maxLines: null,
                        maxLength: 20000,
                        decoration: const InputDecoration(hintText: 'Article text'),
                      ),
              ]),
            ),
          ),
        ],
      ),
    );
  }
}

// ======================================================================
// TEAM & ROLES — модераторы и владельцы (только владелец)
// ======================================================================
class _Team extends StatefulWidget {
  const _Team();

  @override
  State<_Team> createState() => _TeamState();
}

class _TeamState extends State<_Team> {
  late Future<List<TeamMember>> _future = context.read<AppState>().repo.adminTeam();
  final _email = TextEditingController();
  String _level = 'moderator';

  @override
  void dispose() {
    _email.dispose();
    super.dispose();
  }

  Future<void> _set(String email, String? level) async {
    try {
      await context.read<AppState>().repo.adminSetTeam(email, level);
      if (!mounted) return;
      showSnack(context, level == null ? 'Removed from the team' : 'Role saved: $level');
      _email.clear();
      setState(() => _future = context.read<AppState>().repo.adminTeam());
    } catch (e) {
      if (mounted) showSnack(context, '$e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final me = context.read<AppState>().user;
    return _Page(
      title: 'Team & roles',
      subtitle: 'Moderator: checks, reports, support, help articles. '
          'Owner: everything, plus statistics, ads, money, settings, roles and the activity log.',
      child: _Loader<List<TeamMember>>(
        future: _future,
        builder: (list) => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          for (final m in list)
            _Card(
              child: Row(children: [
                CircleAvatar(
                  backgroundColor: m.level == 'owner' ? Zc.orangeSoft : Zc.chip,
                  child: Icon(m.level == 'owner' ? ZI.crown : ZI.shield, color: Zc.green, size: 20),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(m.fullName ?? m.email ?? 'Member', style: const TextStyle(fontWeight: FontWeight.w600)),
                    Text('${m.email ?? ''} · ${m.level == 'owner' ? 'Owner' : 'Moderator'}',
                        style: const TextStyle(fontSize: 12, color: Zc.grey)),
                  ]),
                ),
                if (m.userId != me?.id && m.email != null)
                  PopupMenuButton<String>(
                    onSelected: (v) => _set(m.email!, v == 'remove' ? null : v),
                    itemBuilder: (_) => [
                      if (m.level != 'moderator') const PopupMenuItem(value: 'moderator', child: Text('Make moderator')),
                      if (m.level != 'owner') const PopupMenuItem(value: 'owner', child: Text('Make owner')),
                      const PopupMenuItem(value: 'remove', child: Text('Remove from team')),
                    ],
                  )
                else
                  const Text('You', style: TextStyle(color: Zc.grey)),
              ]),
            ),
          const SizedBox(height: 14),
          _Card(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Text('Add a team member', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
              const SizedBox(height: 4),
              const Text('The person must already have a Zumi account with this email.',
                  style: TextStyle(fontSize: 12, color: Zc.grey)),
              const SizedBox(height: 10),
              TextField(
                controller: _email,
                keyboardType: TextInputType.emailAddress,
                decoration: const InputDecoration(hintText: 'Email'),
              ),
              const SizedBox(height: 10),
              Wrap(spacing: 10, runSpacing: 8, crossAxisAlignment: WrapCrossAlignment.center, children: [
                SegmentedButton<String>(
                  segments: const [
                    ButtonSegment(value: 'moderator', label: Text('Moderator')),
                    ButtonSegment(value: 'owner', label: Text('Owner')),
                  ],
                  selected: {_level},
                  onSelectionChanged: (s) => setState(() => _level = s.first),
                ),
                _actionBtn('Add', () {
                  if (!_email.text.contains('@')) {
                    showSnack(context, 'Enter the email of their Zumi account');
                    return;
                  }
                  _set(_email.text, _level);
                }, primary: true),
              ]),
            ]),
          ),
        ]),
      ),
    );
  }
}
