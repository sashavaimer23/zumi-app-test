import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../features.dart';
import '../../models/models.dart';
import '../../state/app_state.dart';
import '../../theme.dart';
import '../../widgets/common.dart';
import '../../widgets/zicons.dart';

/// Подтверждение кодом: WhatsApp, SMS или email (человек выбирает сам).
/// Значок «телефон подтверждён» даётся только за код через WhatsApp или SMS.
/// Возвращает true через Navigator.pop, если телефон подтверждён.
class PhoneVerifyScreen extends StatefulWidget {
  const PhoneVerifyScreen({super.key, this.afterSignup = false});

  /// Показан сразу после регистрации — тогда есть кнопка «Skip for now»
  final bool afterSignup;

  @override
  State<PhoneVerifyScreen> createState() => _PhoneVerifyScreenState();
}

class _PhoneVerifyScreenState extends State<PhoneVerifyScreen> {
  late final _phone = TextEditingController(text: _initialPhone());
  final _code = TextEditingController();
  late final _email = TextEditingController(text: context.read<AppState>().user?.email ?? '');
  String _channel = 'whatsapp'; // whatsapp | sms | email
  bool _codeSent = false;
  bool _testMode = false;
  bool _loading = false;
  String _sentTo = '';

  // ---- подтверждение через WhatsApp: человек сам пишет нам код ----
  bool get _waMode => Features.waVerifyNumber != null && !context.read<AppState>().repo.isDemo;
  String? _waCode;
  String? _waNumber;
  Timer? _waPoll;
  DateTime? _waUntil;
  bool _checking = false;

  String _initialPhone() {
    final p = context.read<AppState>().user?.phone ?? '';
    return p.isEmpty ? '+260 ' : p;
  }

  @override
  void dispose() {
    _waPoll?.cancel();
    _phone.dispose();
    _code.dispose();
    _email.dispose();
    super.dispose();
  }

  /// +260 97 123 4567 → +260971234567; 0971234567 → +260971234567
  String? _normalize(String raw) {
    var d = raw.replaceAll(RegExp(r'[^0-9+]'), '');
    if (d.startsWith('0')) d = '+260${d.substring(1)}';
    if (!d.startsWith('+')) d = '+$d';
    return RegExp(r'^\+\d{10,15}$').hasMatch(d) ? d : null;
  }

  Future<void> _send() async {
    final String? dest;
    if (_channel == 'email') {
      final e = _email.text.trim();
      dest = RegExp(r'^\S+@\S+\.\S+$').hasMatch(e) ? e : null;
      if (dest == null) {
        showSnack(context, 'Enter a valid email');
        return;
      }
    } else {
      dest = _normalize(_phone.text);
      if (dest == null) {
        showSnack(context, 'Enter a valid phone number, e.g. +260 97 123 4567');
        return;
      }
    }
    setState(() => _loading = true);
    try {
      final test = await context.read<AppState>().repo.sendCode(_channel, dest);
      if (!mounted) return;
      setState(() {
        _codeSent = true;
        _sentTo = dest!;
        _testMode = test;
      });
    } catch (e) {
      if (mounted) showSnack(context, '$e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _verify() async {
    if (_code.text.trim().length < 6) {
      showSnack(context, 'Enter the 6-digit code');
      return;
    }
    setState(() => _loading = true);
    try {
      await context.read<AppState>().repo.verifyCode(_channel, _sentTo, _code.text.trim());
      if (!mounted) return;
      if (_channel == 'email') {
        showSnack(context, 'Email confirmed. To get "Phone confirmed", use WhatsApp or SMS.');
        Navigator.pop(context, false);
      } else {
        showSnack(context, 'Phone number confirmed');
        Navigator.pop(context, true);
      }
    } catch (e) {
      if (mounted) showSnack(context, '$e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Uri _waLink() => Uri.parse(
      'https://wa.me/$_waNumber?text=${Uri.encodeComponent('Zumi code $_waCode — please confirm my number')}');

  Future<void> _startWhatsApp() async {
    setState(() => _loading = true);
    try {
      final r = await context.read<AppState>().repo.startWhatsAppVerification();
      if (!mounted) return;
      setState(() {
        _waCode = r.code;
        _waNumber = r.number;
        _waUntil = DateTime.now().add(const Duration(minutes: 15));
      });
      await _openWhatsApp();
      _waPoll?.cancel();
      _waPoll = Timer.periodic(const Duration(seconds: 3), (_) => _checkConfirmed());
    } on AppException catch (e) {
      if (mounted) showSnack(context, e.message);
    } catch (e) {
      if (mounted) showSnack(context, '$e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _openWhatsApp() async {
    final ok = await launchUrl(_waLink(), mode: LaunchMode.externalApplication);
    if (!ok && mounted) showSnack(context, 'Could not open WhatsApp. Send the code shown below to the Zumi number.');
  }

  /// Пришло ли сообщение: перечитываем профиль (номер подтверждает сервер, когда WhatsApp перешлёт сообщение)
  Future<void> _checkConfirmed({bool manual = false}) async {
    if (_checking) return;
    final until = _waUntil;
    if (until != null && DateTime.now().isAfter(until)) {
      _waPoll?.cancel();
      if (mounted) setState(() => _waCode = null);
      if (mounted) showSnack(context, 'The code expired. Tap "Confirm with WhatsApp" again.');
      return;
    }
    _checking = true;
    if (manual) setState(() {});
    final state = context.read<AppState>();
    try {
      await state.repo.refreshUser();
    } catch (_) {/* попробуем ещё раз */}
    _checking = false;
    if (!mounted) return;
    if (state.user?.phoneVerified ?? false) {
      _waPoll?.cancel();
      showSnack(context, 'Phone number confirmed');
      Navigator.pop(context, true);
    } else if (manual) {
      setState(() {});
      showSnack(context, 'Not received yet. Make sure you pressed Send in WhatsApp — it can take a few seconds.');
    }
  }

  String _prettyNumber(String digits) => '+$digits';

  Widget _whatsAppView() {
    final code = _waCode;
    Widget step(String n, String text) => Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Container(
              width: 26, height: 26,
              alignment: Alignment.center,
              decoration: const BoxDecoration(color: Zc.greenTint, shape: BoxShape.circle),
              child: Text(n, style: const TextStyle(color: Zc.green, fontWeight: FontWeight.w700, fontSize: 13)),
            ),
            const SizedBox(width: 12),
            Expanded(child: Padding(
              padding: const EdgeInsets.only(top: 3),
              child: Text(text, style: const TextStyle(fontSize: 15, color: Zc.text, height: 1.35)),
            )),
          ]),
        );
    final waButton = SizedBox(
      width: double.infinity,
      height: 54,
      child: FilledButton.icon(
        onPressed: _loading ? null : (code == null ? _startWhatsApp : _openWhatsApp),
        style: FilledButton.styleFrom(
          backgroundColor: const Color(0xFF25D366),
          foregroundColor: Colors.white,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        ),
        icon: _loading
            ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2.4, color: Colors.white))
            : const Icon(ZI.whatsapp, size: 22),
        label: Text(code == null ? 'Confirm with WhatsApp' : 'Open WhatsApp again',
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
      ),
    );
    return Scaffold(
      appBar: AppBar(
        automaticallyImplyLeading: !widget.afterSignup,
        actions: [
          if (widget.afterSignup)
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Skip for now', style: TextStyle(color: Zc.grey)),
            ),
        ],
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(26, 10, 26, 40),
          children: [
            const Icon(ZI.mobile, size: 48, color: Zc.orange),
            const SizedBox(height: 18),
            Text(code == null ? 'Verify your phone' : 'Press Send in WhatsApp', style: zHeadline(context, size: 34)),
            const SizedBox(height: 10),
            Text(
              code == null
                  ? 'You do this only once. You need it to publish a listing and to see phone numbers in listings — '
                      'and your listings show "Number checked".'
                  : 'WhatsApp opened with a ready message to Zumi. Send it, then come back here — '
                      'your number is confirmed by itself.',
              style: const TextStyle(color: Zc.grey, fontSize: 15, height: 1.4),
            ),
            const SizedBox(height: 22),
            Container(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
              decoration: BoxDecoration(color: Zc.white, borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: Zc.lightGrey)),
              child: Column(children: [
                step('1', 'Tap the green button — WhatsApp opens with a message to Zumi.'),
                step('2', 'Press Send. Use the WhatsApp number you want on Zumi — that number gets confirmed.'),
                step('3', 'Come back here. It takes a few seconds.'),
              ]),
            ),
            const SizedBox(height: 24),
            waButton,
            if (code != null) ...[
              const SizedBox(height: 18),
              const Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)),
                SizedBox(width: 10),
                Text('Waiting for your message…', style: TextStyle(color: Zc.grey)),
              ]),
              const SizedBox(height: 8),
              Center(
                child: TextButton(
                  onPressed: _checking ? null : () => _checkConfirmed(manual: true),
                  child: const Text("I've sent it — check now", style: TextStyle(color: Zc.green, fontSize: 15)),
                ),
              ),
              const SizedBox(height: 6),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(color: Zc.orangeSoft, borderRadius: BorderRadius.circular(12)),
                child: Text(
                  'WhatsApp did not open? Send the code $code to ${_prettyNumber(_waNumber!)} on WhatsApp. '
                  'The code works for 15 minutes.',
                  style: const TextStyle(fontSize: 13, height: 1.35),
                ),
              ),
            ],
            const SizedBox(height: 20),
            const Text(
              'No WhatsApp on your phone? Write to us in Profile → Help & support and we will help you confirm it.',
              style: TextStyle(fontSize: 12, color: Zc.grey, height: 1.35),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_waMode) return _whatsAppView();
    final via = switch (_channel) { 'whatsapp' => 'WhatsApp', 'sms' => 'SMS', _ => 'email' };
    return Scaffold(
      appBar: AppBar(
        automaticallyImplyLeading: !widget.afterSignup,
        actions: [
          if (widget.afterSignup)
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Skip for now', style: TextStyle(color: Zc.grey)),
            ),
        ],
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(26, 10, 26, 40),
          children: [
            const Icon(ZI.mobile, size: 48, color: Zc.orange),
            const SizedBox(height: 18),
            Text(_codeSent ? 'Enter the code' : 'Verify your phone', style: zHeadline(context, size: 34)),
            const SizedBox(height: 10),
            Text(
              _codeSent
                  ? 'We sent a 6-digit code by $via to $_sentTo'
                  : 'You confirm your phone only once. You need it to publish a listing and to see phone numbers '
                      'in listings — and your listings show "Number checked".',
              style: const TextStyle(color: Zc.grey, fontSize: 15, height: 1.4),
            ),
            if (_codeSent && _testMode) ...[
              const SizedBox(height: 14),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(color: Zc.orangeSoft, borderRadius: BorderRadius.circular(12)),
                child: const Text('Test mode: messages are not sent yet. Use the code 123456.',
                    style: TextStyle(fontSize: 13)),
              ),
            ],
            const SizedBox(height: 24),
            if (!_codeSent) ...[
              const Text('Where should we send the code?', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600)),
              const SizedBox(height: 10),
              Wrap(spacing: 10, runSpacing: 10, children: [
                for (final (k, l) in const [('whatsapp', 'WhatsApp'), ('sms', 'SMS'), ('email', 'Email')])
                  ZChip(label: l, selected: _channel == k, onTap: () => setState(() => _channel = k)),
              ]),
              const SizedBox(height: 18),
              if (_channel == 'email') ...[
                const Text('Email', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600)),
                const SizedBox(height: 8),
                TextField(
                  controller: _email,
                  keyboardType: TextInputType.emailAddress,
                  decoration: const InputDecoration(hintText: 'you@example.com'),
                  onSubmitted: (_) => _send(),
                ),
                const SizedBox(height: 8),
                const Text('An email code confirms your email only. The "Phone confirmed" badge needs WhatsApp or SMS.',
                    style: TextStyle(fontSize: 12, color: Zc.grey)),
              ] else ...[
                const Text('Phone number', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600)),
                const SizedBox(height: 8),
                TextField(
                  controller: _phone,
                  keyboardType: TextInputType.phone,
                  decoration: const InputDecoration(hintText: '+260 97 123 4567'),
                  onSubmitted: (_) => _send(),
                ),
              ],
              const SizedBox(height: 30),
              PrimaryButton(label: 'Send code', width: double.infinity, loading: _loading, onPressed: _send),
            ] else ...[
              TextField(
                controller: _code,
                keyboardType: TextInputType.number,
                autofocus: true,
                maxLength: 6,
                textAlign: TextAlign.center,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                style: const TextStyle(fontSize: 28, letterSpacing: 12),
                decoration: const InputDecoration(hintText: '······', counterText: ''),
                onSubmitted: (_) => _verify(),
              ),
              const SizedBox(height: 30),
              PrimaryButton(label: 'Verify', width: double.infinity, loading: _loading, onPressed: _verify),
              const SizedBox(height: 12),
              Center(
                child: TextButton(
                  onPressed: _loading ? null : () => setState(() => _codeSent = false),
                  child: const Text('Change number, method or resend code', style: TextStyle(color: Zc.green)),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
