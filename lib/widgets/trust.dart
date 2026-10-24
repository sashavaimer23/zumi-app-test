import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';

import '../models/models.dart';
import '../screens/auth_screen.dart';
import '../state/app_state.dart';
import '../theme.dart';
import 'common.dart';
import 'zicons.dart';

// ======================================================================
// Verification (всё добровольно). Плашка «Verified» = проверенный автор.
// Три строки на странице объявления:
//
//  Identity Verified  — телефон подтверждён SMS-кодом + документ (NRC/паспорт)
//  Property Verified  — объект существует: 3 фото на месте + геолокация
//                       рядом с точкой объявления (или визит команды Zumi)
//  Ownership Verified — документы о собственности / полномочия агента
//
// На объявлении с Property Verified показывается плашка «Verified».
// ======================================================================

const _tealTint = Color(0x140F5D4E);
const _okGreen = Color(0xFF2E9E5B);

/// Описание уровней — используется на странице объявления и в экране проверки
class VerificationLevel {
  final IconData icon;
  final String title;
  final String description;
  const VerificationLevel(this.icon, this.title, this.description);

  static const identity = VerificationLevel(
    ZI.checkCircle,
    'Identity Verified',
    'The owner or agent confirmed their phone by SMS and their NRC / passport. Agents are also checked with ZIEA.',
  );
  static const property = VerificationLevel(
    ZI.houseCheck,
    'Location Verified',
    'Photos were taken at the property and the location matches the listing.',
  );
  static const ownership = VerificationLevel(
    ZI.shield,
    'Ownership Verified',
    'Ownership documents or the agent\'s authority to represent the owner were checked.',
  );
}

/// Плашка «✓ Verified» поверх фото
class VerifiedBadge extends StatelessWidget {
  const VerifiedBadge({super.key, this.compact = false});
  final bool compact;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.symmetric(horizontal: compact ? 9 : 12, vertical: compact ? 4 : 7),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: const [BoxShadow(color: Zc.shadow, blurRadius: 8, offset: Offset(0, 2))],
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(ZI.verified, size: compact ? 14 : 18, color: _okGreen),
        SizedBox(width: compact ? 4 : 6),
        Text('Verified',
            style: TextStyle(fontSize: compact ? 12 : 14, color: Zc.text, fontWeight: FontWeight.w500)),
      ]),
    );
  }
}

/// «ZIEA licence not verified» — агент, чья лицензия ещё не сверена с реестром
class LicenceWarning extends StatelessWidget {
  const LicenceWarning({super.key, this.compact = false});
  final bool compact;

  @override
  Widget build(BuildContext context) => Tooltip(
        message: 'The Zumi team has not yet checked this agent\'s licence with the ZIEA register',
        child: Container(
          padding: EdgeInsets.symmetric(horizontal: compact ? 8 : 10, vertical: compact ? 3 : 6),
          decoration: BoxDecoration(color: const Color(0xFFFFF1D6), borderRadius: BorderRadius.circular(20)),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Icon(ZI.warning, size: compact ? 13 : 16, color: const Color(0xFF9A6200)),
            const SizedBox(width: 5),
            Text('ZIEA licence not verified',
                style: TextStyle(
                    fontSize: compact ? 11 : 13, color: const Color(0xFF9A6200), fontWeight: FontWeight.w600)),
          ]),
        ),
      );
}

/// Галочка рядом с именем, если личность автора подтверждена
class VerifiedMark extends StatelessWidget {
  const VerifiedMark({super.key, this.size = 16});
  final double size;

  @override
  Widget build(BuildContext context) => Tooltip(
        message: 'Identity Verified',
        child: Icon(ZI.verified, size: size, color: _okGreen),
      );
}

/// Строка «✦ Property verified on 16th of October» / «Availability confirmed 2 days ago»
class TrustLine extends StatelessWidget {
  const TrustLine({super.key, required this.p});
  final Property p;

  static String? textFor(Property p) {
    // Пока у Zumi нет выездной команды, показываем только автоматическую проверку на месте
    if (p.propertyVerified && p.propertyVerifiedAt != null && p.propertyVerifyMethod == 'geo_photos') {
      return 'Photos taken on site and location checked on ${formatDayMonth(p.propertyVerifiedAt!)}';
    }
    if (p.confirmedAt != null) return 'Availability confirmed ${daysAgo(p.confirmedAt!)}';
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final text = textFor(p);
    if (text == null) return const SizedBox.shrink();
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(color: _tealTint, borderRadius: BorderRadius.circular(10)),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(p.propertyVerified ? ZI.sparkle : ZI.clock, size: 16, color: Zc.green),
        const SizedBox(width: 8),
        Flexible(child: Text(text, style: const TextStyle(fontSize: 14, color: Zc.green))),
      ]),
    );
  }
}

/// Строка уровня проверки (как в макете: иконка, заголовок, описание)
class VerificationRow extends StatelessWidget {
  const VerificationRow({super.key, required this.level, required this.done, this.trailing, this.showDivider = true});
  final VerificationLevel level;
  final bool done;
  final Widget? trailing;
  final bool showDivider;

  @override
  Widget build(BuildContext context) {
    final color = done ? _okGreen : Zc.lightGrey;
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 16),
      decoration: BoxDecoration(
        border: showDivider ? const Border(bottom: BorderSide(color: Zc.chip)) : null,
      ),
      child: Row(children: [
        SizedBox(width: 40, child: Icon(level.icon, color: color, size: 26)),
        const SizedBox(width: 14),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Flexible(
                child: Text(level.title,
                    style: TextStyle(
                        fontSize: 17, fontWeight: FontWeight.w600, color: done ? Zc.text : Zc.grey)),
              ),
              if (!done) ...[
                const SizedBox(width: 8),
                const Text('Not yet', style: TextStyle(fontSize: 12, color: Zc.grey)),
              ],
            ]),
            const SizedBox(height: 4),
            Text(level.description, style: const TextStyle(fontSize: 14, color: Zc.grey, height: 1.35)),
          ]),
        ),
        if (trailing != null) ...[const SizedBox(width: 12), trailing!],
      ]),
    );
  }
}

/// Блок проверок на странице объявления
class TrustPanel extends StatelessWidget {
  const TrustPanel({super.key, required this.p});
  final Property p;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 4),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Zc.chip),
      ),
      child: Column(children: [
        VerificationRow(level: VerificationLevel.identity, done: p.ownerIdentityVerified),
        VerificationRow(level: VerificationLevel.property, done: p.propertyVerified),
        VerificationRow(level: VerificationLevel.ownership, done: p.ownershipVerified, showDivider: false),
      ]),
    );
  }
}

/// Советы безопасности + кнопка «Пожаловаться»
class SafetyTips extends StatelessWidget {
  const SafetyTips({super.key, required this.p});
  final Property p;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Zc.lightGrey),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Text('Stay safe on Zumi', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600)),
        const SizedBox(height: 8),
        for (final t in const [
          'Never pay a deposit or fees before you have seen the property in person.',
          'Ask to see the title deed or the owner\'s authorization letter.',
          'Pay only to the account named in the lease agreement — not to a "friend" or "relative".',
          'Be careful if the price is much lower than similar homes nearby.',
        ])
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 3),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Padding(
                  padding: EdgeInsets.only(top: 6), child: CircleAvatar(radius: 2.5, backgroundColor: Zc.orange)),
              const SizedBox(width: 10),
              Expanded(child: Text(t, style: const TextStyle(fontSize: 14, height: 1.4))),
            ]),
          ),
        const SizedBox(height: 8),
        TextButton.icon(
          style: TextButton.styleFrom(foregroundColor: Zc.orange, padding: EdgeInsets.zero),
          onPressed: () => showReportSheet(context, p),
          icon: const Icon(ZI.flag, size: 18),
          label: const Text('Report this listing'),
        ),
      ]),
    );
  }
}

// ----------------------------------------------------------------------
// Жалоба
// ----------------------------------------------------------------------
Future<void> showReportSheet(BuildContext context, Property p) async {
  final app = context.read<AppState>();
  if (!app.signedIn) {
    final ok = await Navigator.push<bool>(
      context,
      MaterialPageRoute(builder: (_) => const AuthScreen(reason: 'Sign in to report a listing.')),
    );
    if (ok != true || !context.mounted) return;
  }
  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Zc.bg,
    shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
    builder: (_) => _ReportSheet(p: p),
  );
}

class _ReportSheet extends StatefulWidget {
  const _ReportSheet({required this.p});
  final Property p;

  @override
  State<_ReportSheet> createState() => _ReportSheetState();
}

class _ReportSheetState extends State<_ReportSheet> {
  String? _reason;
  final _details = TextEditingController();
  bool _sending = false;

  @override
  void dispose() {
    _details.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    if (_reason == null) return;
    setState(() => _sending = true);
    try {
      await context.read<AppState>().repo.reportListing(widget.p.id, _reason!, _details.text.trim());
      if (!mounted) return;
      Navigator.pop(context);
      showSnack(context, 'Thank you! Our team will check this listing.');
    } catch (e) {
      if (mounted) showSnack(context, '$e');
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: SafeArea(
        child: ListView(
          shrinkWrap: true,
          padding: const EdgeInsets.fromLTRB(22, 20, 22, 20),
          children: [
            const Text('Report listing',
                style: TextStyle(fontSize: 22, fontWeight: FontWeight.w600, color: Zc.green)),
            const SizedBox(height: 6),
            const Text('Your report is anonymous for the author.', style: TextStyle(color: Zc.grey)),
            const SizedBox(height: 12),
            for (final e in reportReasons.entries)
              InkWell(
                onTap: () => setState(() => _reason = e.key),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 10),
                  child: Row(children: [
                    RadioDot(selected: _reason == e.key, size: 20),
                    const SizedBox(width: 12),
                    Expanded(child: Text(e.value, style: const TextStyle(fontSize: 15))),
                  ]),
                ),
              ),
            const SizedBox(height: 8),
            TextField(
              controller: _details,
              minLines: 2,
              maxLines: 4,
              decoration: const InputDecoration(hintText: 'Tell us more (optional)'),
            ),
            const SizedBox(height: 20),
            PrimaryButton(
              label: 'Send report',
              width: double.infinity,
              loading: _sending,
              onPressed: _reason == null ? null : _send,
            ),
          ],
        ),
      ),
    );
  }
}

// ----------------------------------------------------------------------
// Загрузка документов: kind = 'identity' (NRC/паспорт) или 'ownership'
// ----------------------------------------------------------------------
Future<bool?> showDocumentsSheet(
  BuildContext context, {
  required String kind,
  Property? property,
  required bool isAgent,
}) {
  return showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Zc.bg,
    shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
    builder: (_) => FractionallySizedBox(
      heightFactor: 0.9,
      child: _DocumentsSheet(kind: kind, property: property, isAgent: isAgent),
    ),
  );
}

class _DocumentsSheet extends StatefulWidget {
  const _DocumentsSheet({required this.kind, this.property, required this.isAgent});
  final String kind;
  final Property? property;
  final bool isAgent;

  @override
  State<_DocumentsSheet> createState() => _DocumentsSheetState();
}

class _DocumentsSheetState extends State<_DocumentsSheet> {
  final List<PickedPhoto> _docs = [];
  final _note = TextEditingController();
  bool _sending = false;

  bool get _ownership => widget.kind == 'ownership';

  List<String> get _needed => _ownership
      ? [
          'Title deed, or a lease agreement in your name',
          if (widget.isAgent) 'A signed letter from the owner allowing you to list the property',
          'Your NRC or passport — the name must match the documents',
        ]
      : [
          'NRC or passport (front side)',
          'A selfie holding your NRC / passport',
          if (widget.isAgent) 'Agency registration (PACRA certificate)',
        ];

  @override
  void dispose() {
    _note.dispose();
    super.dispose();
  }

  Future<void> _pick() async {
    try {
      final files = await ImagePicker().pickMultiImage(imageQuality: 80, maxWidth: 2000, maxHeight: 2000);
      var skipped = 0;
      for (final f in files.take(8 - _docs.length)) {
        final bytes = await f.readAsBytes();
        if (bytes.lengthInBytes > kMaxDocBytes) {
          skipped++; // документы — до 10 MB
          continue;
        }
        _docs.add(PickedPhoto(f.name, bytes));
      }
      if (skipped > 0 && mounted) showSnack(context, 'Files larger than 10 MB were skipped');
      if (mounted) setState(() {});
    } catch (e) {
      if (mounted) showSnack(context, 'Could not open the gallery: $e');
    }
  }

  Future<void> _send() async {
    if (_docs.isEmpty) {
      showSnack(context, 'Please add the documents first');
      return;
    }
    setState(() => _sending = true);
    try {
      await context.read<AppState>().repo.requestVerification(
            kind: widget.kind,
            propertyId: widget.property?.id,
            docs: _docs,
            note: _note.text.trim(),
          );
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) showSnack(context, '$e');
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final level = _ownership ? VerificationLevel.ownership : VerificationLevel.identity;
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: ListView(
        padding: const EdgeInsets.fromLTRB(22, 22, 22, 30),
        children: [
          Row(children: [
            Icon(level.icon, color: _okGreen, size: 30),
            const Spacer(),
            IconButton(onPressed: () => Navigator.pop(context), icon: const Icon(ZI.close, color: Zc.green)),
          ]),
          const SizedBox(height: 10),
          Text(level.title, style: zHeadline(context, size: 28)),
          const SizedBox(height: 8),
          Text(level.description, style: const TextStyle(color: Zc.grey, fontSize: 15, height: 1.4)),
          const SizedBox(height: 20),
          const Text('What we need', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600)),
          const SizedBox(height: 8),
          for (final n in _needed)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                const Icon(ZI.fileText, size: 18, color: Zc.green),
                const SizedBox(width: 10),
                Expanded(child: Text(n, style: const TextStyle(fontSize: 14, height: 1.4))),
              ]),
            ),
          const SizedBox(height: 18),
          OutlinedButton.icon(
            style: OutlinedButton.styleFrom(
              foregroundColor: Zc.green,
              side: const BorderSide(color: Zc.green),
              padding: const EdgeInsets.symmetric(vertical: 14),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
            ),
            onPressed: _pick,
            icon: const Icon(ZI.camera),
            label: Text(_docs.isEmpty ? 'Add photos of documents' : 'Add more (${_docs.length}/8)'),
          ),
          if (_docs.isNotEmpty) ...[
            const SizedBox(height: 12),
            PhotoThumbs(photos: _docs, onRemove: (i) => setState(() => _docs.removeAt(i))),
          ],
          const SizedBox(height: 14),
          TextField(
            controller: _note,
            minLines: 2,
            maxLines: 4,
            decoration: const InputDecoration(hintText: 'Comment for the Zumi team (optional)'),
          ),
          const SizedBox(height: 10),
          const Row(children: [
            Icon(ZI.shield, size: 16, color: Zc.grey),
            SizedBox(width: 6),
            Expanded(
              child: Text('Documents are stored privately and seen only by the Zumi verification team.',
                  style: TextStyle(fontSize: 12, color: Zc.grey)),
            ),
          ]),
          const SizedBox(height: 22),
          PrimaryButton(label: 'Send for review', width: double.infinity, loading: _sending, onPressed: _send),
        ],
      ),
    );
  }
}

/// Миниатюры выбранных фото с крестиком
class PhotoThumbs extends StatelessWidget {
  const PhotoThumbs({super.key, required this.photos, required this.onRemove, this.size = 80});
  final List<PickedPhoto> photos;
  final ValueChanged<int> onRemove;
  final double size;

  @override
  Widget build(BuildContext context) {
    return Wrap(spacing: 8, runSpacing: 8, children: [
      for (var i = 0; i < photos.length; i++)
        Stack(children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(10),
            child: Image.memory(photos[i].bytes, width: size, height: size, fit: BoxFit.cover),
          ),
          Positioned(
            right: 2,
            top: 2,
            child: GestureDetector(
              onTap: () => onRemove(i),
              child: const CircleAvatar(
                radius: 11,
                backgroundColor: Zc.scrim,
                child: Icon(ZI.close, size: 13, color: Colors.white),
              ),
            ),
          ),
        ]),
    ]);
  }
}
