import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../state/app_state.dart';
import '../../theme.dart';
import '../../widgets/common.dart';
import '../../widgets/zicons.dart';

/// Подтверждение телефона SMS-кодом.
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
  bool _codeSent = false;
  bool _loading = false;
  String _sentTo = '';

  String _initialPhone() {
    final p = context.read<AppState>().user?.phone ?? '';
    return p.isEmpty ? '+260 ' : p;
  }

  @override
  void dispose() {
    _phone.dispose();
    _code.dispose();
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
    final phone = _normalize(_phone.text);
    if (phone == null) {
      showSnack(context, 'Enter a valid phone number, e.g. +260 97 123 4567');
      return;
    }
    setState(() => _loading = true);
    try {
      await context.read<AppState>().repo.sendPhoneCode(phone);
      if (!mounted) return;
      setState(() {
        _codeSent = true;
        _sentTo = phone;
      });
    } catch (e) {
      if (mounted) showSnack(context, '$e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _verify() async {
    if (_code.text.trim().length < 6) {
      showSnack(context, 'Enter the 6-digit code from the SMS');
      return;
    }
    setState(() => _loading = true);
    try {
      await context.read<AppState>().repo.verifyPhoneCode(_sentTo, _code.text.trim());
      if (!mounted) return;
      showSnack(context, 'Phone number verified');
      Navigator.pop(context, true);
    } catch (e) {
      if (mounted) showSnack(context, '$e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final demo = context.read<AppState>().repo.isDemo;
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
                  ? 'We sent a 6-digit code by SMS to $_sentTo'
                  : 'A verified phone is the first step to Identity Verified. People trust verified agents and owners more.',
              style: const TextStyle(color: Zc.grey, fontSize: 15, height: 1.4),
            ),
            if (demo) ...[
              const SizedBox(height: 14),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(color: Zc.orangeSoft, borderRadius: BorderRadius.circular(12)),
                child: const Text('Demo mode: no real SMS is sent. Use the code 123456.',
                    style: TextStyle(fontSize: 13)),
              ),
            ],
            const SizedBox(height: 28),
            if (!_codeSent) ...[
              const Text('Phone number', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600)),
              const SizedBox(height: 8),
              TextField(
                controller: _phone,
                keyboardType: TextInputType.phone,
                autofocus: true,
                decoration: const InputDecoration(hintText: '+260 97 123 4567'),
                onSubmitted: (_) => _send(),
              ),
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
                  child: const Text('Change number or resend code', style: TextStyle(color: Zc.green)),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
