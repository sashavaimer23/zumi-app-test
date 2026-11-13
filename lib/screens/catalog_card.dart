import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../config.dart';
import '../models/models.dart';
import '../state/app_state.dart';
import '../theme.dart';
import '../widgets/common.dart';
import '../widgets/share.dart';
import '../widgets/zicons.dart';

/// «My catalogue» в профиле агента: красивая ссылка zumihome.com/<имя>, «Поделиться» сверху,
/// просмотры, «Посмотреть» и «Настроить». Сама страница каталога — лёгкая (Cloudflare).
class CatalogCard extends StatefulWidget {
  const CatalogCard({super.key, required this.user, required this.listings, this.rating});
  final AppUser user;
  final List<Property> listings;
  final Rating? rating;

  @override
  State<CatalogCard> createState() => _CatalogCardState();
}

class _CatalogCardState extends State<CatalogCard> {
  CatalogInfo? _c;
  bool _failed = false;

  String get _site => AppConfig.siteUrl ?? 'https://zumihome.com';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final c = await context.read<AppState>().repo.myCatalog();
      if (mounted) setState(() => _c = c);
    } catch (_) {
      if (mounted) setState(() => _failed = true); // база ещё без 038 — ссылка по-старому
    }
  }

  String get _link => _c?.link(_site) ?? '$_site/agent/${widget.user.id}';
  String get _shortLink => _c?.shortLink ?? 'zumihome.com/agent/…';

  void _share() {
    final u = widget.user;
    final n = widget.listings.where((p) => p.status == 'active').length;
    final who = (u.fullName ?? '').trim().isEmpty ? 'My' : '${u.fullName!.trim()}${(u.agencyName ?? '').isEmpty ? '' : ' · ${u.agencyName}'} —';
    showShareSheet(context, text: '$who property catalogue on Zumi ($n ${n == 1 ? 'property' : 'properties'})', link: _link);
  }

  Future<void> _edit() async {
    final c = _c;
    if (c == null) return;
    final saved = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Zc.bg,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (_) => _CatalogEditor(info: c),
    );
    if (saved == true) _load();
  }

  @override
  Widget build(BuildContext context) {
    final active = widget.listings.where((p) => p.status == 'active').length;
    final r = widget.rating;
    final c = _c;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(18), border: Border.all(color: Zc.chip)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        const Row(children: [
          Icon(ZI.storefront, color: Zc.green),
          SizedBox(width: 8),
          Text('My catalogue', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600, color: Zc.green)),
        ]),
        const SizedBox(height: 4),
        const Text('All your properties on one page — send this link to clients instead of listings one by one.',
            style: TextStyle(fontSize: 13, color: Zc.grey, height: 1.35)),
        const SizedBox(height: 12),
        // ссылка — нажми, чтобы скопировать
        InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: c == null && !_failed
              ? null
              : () async {
                  await Clipboard.setData(ClipboardData(text: _link));
                  if (context.mounted) showSnack(context, 'Link copied');
                },
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(color: Zc.chip, borderRadius: BorderRadius.circular(12)),
            child: Row(children: [
              const Icon(ZI.link, size: 18, color: Zc.green),
              const SizedBox(width: 8),
              Expanded(
                child: Text(c == null && !_failed ? 'Loading…' : _shortLink,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: Zc.green)),
              ),
              const Icon(ZI.copy, size: 18, color: Zc.grey),
            ]),
          ),
        ),
        const SizedBox(height: 12),
        FilledButton.icon(
          style: FilledButton.styleFrom(
            backgroundColor: Zc.orange,
            minimumSize: const Size.fromHeight(50),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(25)),
          ),
          onPressed: c == null && !_failed ? null : _share,
          icon: const Icon(ZI.share, size: 19),
          label: const Text('Share catalogue', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
        ),
        const SizedBox(height: 14),
        Row(children: [
          _Stat(value: '$active', label: active == 1 ? 'property' : 'properties'),
          _Stat(value: c == null ? '—' : '${c.views7d}', label: 'views this week'),
          _Stat(
            value: r == null || r.count == 0 ? '—' : r.average.toStringAsFixed(1),
            label: r == null || r.count == 0 ? 'no reviews yet' : '${r.count} ${r.count == 1 ? 'review' : 'reviews'}',
          ),
        ]),
        const SizedBox(height: 12),
        Row(children: [
          Expanded(
            child: OutlinedButton.icon(
              style: OutlinedButton.styleFrom(
                foregroundColor: Zc.green,
                side: const BorderSide(color: Zc.green),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              ),
              onPressed: c == null && !_failed
                  ? null
                  : () => launchUrl(Uri.parse(_link), mode: LaunchMode.externalApplication),
              icon: const Icon(ZI.eye, size: 18),
              label: const Text('Preview'),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: OutlinedButton.icon(
              style: OutlinedButton.styleFrom(
                foregroundColor: Zc.green,
                side: const BorderSide(color: Zc.green),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              ),
              onPressed: c == null ? null : _edit,
              icon: const Icon(ZI.edit, size: 18),
              label: const Text('Edit'),
            ),
          ),
        ]),
        if (c != null && (c.bio ?? '').isEmpty) ...[
          const SizedBox(height: 10),
          const Text('Tip: add a few words about you and the areas you cover — clients trust a catalogue with a face and a story.',
              style: TextStyle(fontSize: 12.5, color: Zc.grey, height: 1.35)),
        ],
      ]),
    );
  }
}

class _Stat extends StatelessWidget {
  const _Stat({required this.value, required this.label});
  final String value;
  final String label;

  @override
  Widget build(BuildContext context) => Expanded(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(value, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w600, color: Zc.text)),
          Text(label, style: const TextStyle(fontSize: 12, color: Zc.grey)),
        ]),
      );
}

/// Настройка каталога: адрес ссылки, «о себе», районы, показывать ли WhatsApp
class _CatalogEditor extends StatefulWidget {
  const _CatalogEditor({required this.info});
  final CatalogInfo info;

  @override
  State<_CatalogEditor> createState() => _CatalogEditorState();
}

class _CatalogEditorState extends State<_CatalogEditor> {
  late final _slug = TextEditingController(text: widget.info.slug);
  late final _bio = TextEditingController(text: widget.info.bio ?? '');
  late final _areas = TextEditingController(text: widget.info.areas ?? '');
  late bool _contact = widget.info.publicContact;
  bool _saving = false;
  String? _error;

  @override
  void dispose() {
    _slug.dispose();
    _bio.dispose();
    _areas.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await context.read<AppState>().repo.setMyCatalog(
            slug: _slug.text,
            bio: _bio.text,
            areas: _areas.text,
            publicContact: _contact,
          );
      if (!mounted) return;
      Navigator.pop(context, true);
      showSnack(context, 'Catalogue saved');
    } catch (e) {
      if (mounted) setState(() => _error = '$e'.replaceFirst('Exception: ', ''));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(20, 18, 20, 20 + MediaQuery.viewInsetsOf(context).bottom),
      child: SingleChildScrollView(
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
          const Text('Edit catalogue', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w600, color: Zc.green)),
          const SizedBox(height: 16),
          const Text('Link address', style: TextStyle(fontWeight: FontWeight.w600)),
          const SizedBox(height: 6),
          TextField(
            controller: _slug,
            autocorrect: false,
            inputFormatters: [
              FilteringTextInputFormatter.allow(RegExp(r'[a-zA-Z0-9-]')),
              LengthLimitingTextInputFormatter(40),
            ],
            decoration: const InputDecoration(prefixText: 'zumihome.com/', hintText: 'john-banda'),
          ),
          const SizedBox(height: 4),
          const Text('Short and easy to say on the phone: your name or your agency.',
              style: TextStyle(fontSize: 12, color: Zc.grey)),
          const SizedBox(height: 16),
          const Text('About you (optional)', style: TextStyle(fontWeight: FontWeight.w600)),
          const SizedBox(height: 6),
          TextField(
            controller: _bio,
            maxLines: 4,
            maxLength: 600,
            decoration: const InputDecoration(
                hintText: 'e.g. Helping families find homes in Lusaka for 8 years. Viewings 7 days a week.'),
          ),
          const SizedBox(height: 8),
          const Text('Areas you work in (optional)', style: TextStyle(fontWeight: FontWeight.w600)),
          const SizedBox(height: 6),
          TextField(
            controller: _areas,
            maxLength: 120,
            decoration: const InputDecoration(hintText: 'e.g. Ibex Hill, Woodlands, Kabulonga'),
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            value: _contact,
            activeThumbColor: Zc.green,
            onChanged: (v) => setState(() => _contact = v),
            title: const Text('WhatsApp and Call buttons in the catalogue'),
            subtitle: const Text(
                'Clients can message you straight from the link, without signing up. Only your checked number is shown.',
                style: TextStyle(fontSize: 12.5)),
          ),
          if (_error != null) ...[
            const SizedBox(height: 8),
            Text(_error!, style: const TextStyle(color: Colors.red, fontSize: 13.5)),
          ],
          const SizedBox(height: 14),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Zc.green,
              minimumSize: const Size.fromHeight(50),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(25)),
            ),
            onPressed: _saving ? null : _save,
            child: Text(_saving ? 'Saving…' : 'Save'),
          ),
        ]),
      ),
    );
  }
}
