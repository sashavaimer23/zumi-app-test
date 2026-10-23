import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/models.dart';
import '../../state/app_state.dart';
import '../../theme.dart';
import '../../widgets/common.dart';
import '../../widgets/trust.dart';
import '../../widgets/zicons.dart';
import 'id_verify_screen.dart';
import 'phone_verify_screen.dart';

const _ok = Color(0xFF2E9E5B);

/// «Get verified» — понятный чек-лист из 3–4 шагов.
/// Пройдя его, человек получает плашку Verified на всех своих объявлениях.
class GetVerifiedScreen extends StatefulWidget {
  const GetVerifiedScreen({super.key});

  @override
  State<GetVerifiedScreen> createState() => _GetVerifiedScreenState();
}

class _GetVerifiedScreenState extends State<GetVerifiedScreen> {
  late Future<String?> _idStatus;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  void _reload() => _idStatus = context.read<AppState>().repo.verificationStatus(kind: 'identity');

  // ---------------- шаги ----------------
  Future<void> _editName(AppUser u) async {
    final ctrl = TextEditingController(text: u.fullName ?? '');
    final name = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Your full name'),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          textCapitalization: TextCapitalization.words,
          decoration: const InputDecoration(hintText: 'As on your NRC or passport'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          TextButton(onPressed: () => Navigator.pop(ctx, ctrl.text), child: const Text('Save')),
        ],
      ),
    );
    if (name == null || name.trim().length < 2 || !mounted) return;
    try {
      await context.read<AppState>().repo.updateProfile(fullName: name);
    } catch (e) {
      if (mounted) showSnack(context, '$e');
    }
  }

  Future<void> _phone() =>
      Navigator.push(context, MaterialPageRoute(builder: (_) => const PhoneVerifyScreen()));

  Future<void> _id() async {
    final sent = await Navigator.push<bool>(context, MaterialPageRoute(builder: (_) => const IdVerifyScreen()));
    if (sent == true && mounted) setState(_reload);
  }

  Future<void> _licence(AppUser u) async {
    final ctrl = TextEditingController(text: u.licenceNo ?? '');
    final no = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('ZIEA registration number'),
        content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text(
            'Estate agents in Zambia must be registered with the Zambia Institute of Estate Agents (ZIEA). '
            'We check your number with ZIEA — you don\'t need to upload anything.',
            style: TextStyle(fontSize: 14, color: Zc.grey, height: 1.4),
          ),
          const SizedBox(height: 14),
          TextField(
            controller: ctrl,
            autofocus: true,
            textCapitalization: TextCapitalization.characters,
            decoration: const InputDecoration(hintText: 'Registration / licence number'),
          ),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          TextButton(onPressed: () => Navigator.pop(ctx, ctrl.text), child: const Text('Submit')),
        ],
      ),
    );
    if (no == null || no.trim().length < 3 || !mounted) return;
    try {
      await context.read<AppState>().repo.submitAgentLicence(no);
      if (mounted) showSnack(context, 'Thanks! We will check it with ZIEA within 1–2 working days.');
    } catch (e) {
      if (mounted) showSnack(context, '$e');
    }
  }

  // ---------------- UI ----------------
  @override
  Widget build(BuildContext context) {
    final u = context.watch<AppState>().user;
    if (u == null) return const Scaffold(body: SizedBox.shrink());

    return FutureBuilder<String?>(
      future: _idStatus,
      builder: (context, snap) {
        final idStatus = u.idVerified ? 'approved' : snap.data;
        final steps = <_StepData>[
          _StepData(
            icon: ZI.user,
            title: 'Your name',
            subtitle: u.profileComplete ? u.fullName! : 'Add your full name as on your ID',
            done: u.profileComplete,
            action: () => _editName(u),
            actionLabel: 'Add',
          ),
          _StepData(
            icon: ZI.mobile,
            title: 'Phone number',
            subtitle: u.phoneVerified ? 'Confirmed by SMS' : 'We send a 6-digit code by SMS',
            done: u.phoneVerified,
            action: _phone,
            actionLabel: 'Verify',
          ),
          _StepData(
            icon: ZI.idCard,
            title: 'ID check',
            subtitle: switch (idStatus) {
              'approved' => 'NRC / passport confirmed',
              'pending' => 'Under review — 1–2 working days',
              'rejected' => 'Photos were not clear — please try again',
              _ => 'Photo of your NRC or passport + a selfie',
            },
            done: u.idVerified,
            pending: idStatus == 'pending',
            action: _id,
            actionLabel: idStatus == 'rejected' ? 'Retry' : 'Start',
          ),
          if (u.isAgent)
            _StepData(
              icon: ZI.badge,
              title: 'Agent licence (ZIEA)',
              subtitle: u.licenceVerified
                  ? 'Licence ${u.licenceNo} confirmed'
                  : (u.licenceNo != null
                      ? 'Number ${u.licenceNo} — under review'
                      : 'Your ZIEA registration number'),
              done: u.licenceVerified,
              pending: !u.licenceVerified && u.licenceNo != null,
              action: () => _licence(u),
              actionLabel: 'Add',
            ),
        ];
        final done = steps.where((s) => s.done).length;
        final next = steps.where((s) => !s.done && !s.pending).firstOrNullSafe;
        final allDone = done == steps.length;

        return Scaffold(
          appBar: AppBar(title: const Text('Get verified')),
          body: ListView(
            padding: const EdgeInsets.fromLTRB(22, 4, 22, 40),
            children: [
              // ---- шапка с плашкой и прогрессом
              Container(
                padding: const EdgeInsets.all(18),
                decoration: BoxDecoration(
                  color: allDone ? const Color(0x142E9E5B) : Zc.chip,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  const VerifiedBadge(),
                  const SizedBox(height: 14),
                  Text(
                    allDone ? 'You are Verified!' : 'Get the Verified badge',
                    style: zHeadline(context, size: 26),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    allDone
                        ? 'The Verified badge is shown on all your listings.'
                        : 'Buyers and tenants trust verified ${u.isAgent ? 'agents' : 'owners'} more and call them first. '
                            'It takes about 3 minutes and you do it only once — the badge appears on all your listings.',
                    style: const TextStyle(fontSize: 14, color: Zc.grey, height: 1.4),
                  ),
                  const SizedBox(height: 14),
                  Row(children: [
                    Expanded(
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(6),
                        child: LinearProgressIndicator(
                          value: done / steps.length,
                          minHeight: 8,
                          backgroundColor: Colors.white,
                          color: allDone ? _ok : Zc.orange,
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Text('$done of ${steps.length}', style: const TextStyle(fontWeight: FontWeight.w600)),
                  ]),
                ]),
              ),
              const SizedBox(height: 18),

              // ---- шаги
              for (var i = 0; i < steps.length; i++) _StepTile(index: i + 1, s: steps[i]),

              const SizedBox(height: 20),
              if (next != null)
                PrimaryButton(
                  label: 'Continue: ${next.title}',
                  width: double.infinity,
                  onPressed: next.action,
                )
              else if (!allDone)
                const Text(
                  'Everything is sent. We will notify you when the check is complete.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Zc.grey),
                ),
              const SizedBox(height: 22),
              const Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Icon(ZI.shield, size: 18, color: Zc.grey),
                SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Your documents are used only to confirm your identity, are stored privately and are '
                    'deleted after the check. We never show them to other users.',
                    style: TextStyle(fontSize: 12, color: Zc.grey, height: 1.4),
                  ),
                ),
              ]),
            ],
          ),
        );
      },
    );
  }
}

extension _FirstOrNull<T> on Iterable<T> {
  T? get firstOrNullSafe {
    final it = iterator;
    return it.moveNext() ? it.current : null;
  }
}

class _StepData {
  final IconData icon;
  final String title;
  final String subtitle;
  final bool done;
  final bool pending;
  final VoidCallback action;
  final String actionLabel;

  const _StepData({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.done,
    this.pending = false,
    required this.action,
    required this.actionLabel,
  });
}

class _StepTile extends StatelessWidget {
  const _StepTile({required this.index, required this.s});
  final int index;
  final _StepData s;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: s.done ? const Color(0x552E9E5B) : Zc.chip),
      ),
      child: Row(children: [
        Container(
          width: 36,
          height: 36,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: s.done ? _ok : (s.pending ? Zc.orangeSoft : Zc.chip),
          ),
          alignment: Alignment.center,
          child: s.done
              ? const Icon(ZI.checkSimple, color: Colors.white, size: 18)
              : (s.pending
                  ? const Icon(ZI.clock, color: Zc.orange, size: 18)
                  : Text('$index', style: const TextStyle(fontWeight: FontWeight.w600, color: Zc.green))),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Icon(s.icon, size: 16, color: Zc.green),
              const SizedBox(width: 6),
              Flexible(child: Text(s.title, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600))),
            ]),
            const SizedBox(height: 2),
            Text(s.subtitle, style: TextStyle(fontSize: 13, color: s.done ? _ok : Zc.grey, height: 1.3)),
          ]),
        ),
        if (!s.done && !s.pending)
          TextButton(
            style: TextButton.styleFrom(
              backgroundColor: Zc.orange,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 16),
            ),
            onPressed: s.action,
            child: Text(s.actionLabel),
          ),
      ]),
    );
  }
}
