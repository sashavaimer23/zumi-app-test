import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/models.dart';
import '../state/app_state.dart';
import '../theme.dart';
import '../widgets/common.dart';

/// Забыли пароль: 1) email → письмо с 6-значным кодом; 2) код + новый пароль.
/// Код вместо ссылки — так сброс работает и в приложении, и на сайте без лишних настроек.
class ForgotPasswordScreen extends StatefulWidget {
  const ForgotPasswordScreen({super.key, this.email = ''});
  final String email;

  @override
  State<ForgotPasswordScreen> createState() => _ForgotPasswordScreenState();
}

class _ForgotPasswordScreenState extends State<ForgotPasswordScreen> {
  late final _email = TextEditingController(text: widget.email);
  final _code = TextEditingController();
  final _pass = TextEditingController();
  final _pass2 = TextEditingController();
  bool _sent = false;
  bool _loading = false;

  @override
  void dispose() {
    for (final c in [_email, _code, _pass, _pass2]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _send() async {
    if (!RegExp(r'^\S+@\S+\.\S+$').hasMatch(_email.text.trim())) {
      showSnack(context, 'Enter a valid email');
      return;
    }
    setState(() => _loading = true);
    try {
      await context.read<AppState>().repo.sendPasswordReset(_email.text);
      if (mounted) setState(() => _sent = true);
    } catch (e) {
      if (mounted) showSnack(context, '$e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _reset() async {
    if (_code.text.trim().length < 6) {
      showSnack(context, 'Enter the 6-digit code from the email');
      return;
    }
    if (_pass.text.length < 6) {
      showSnack(context, 'Password must be at least 6 characters');
      return;
    }
    if (_pass.text != _pass2.text) {
      showSnack(context, 'Passwords do not match');
      return;
    }
    setState(() => _loading = true);
    final nav = Navigator.of(context);
    final messenger = ScaffoldMessenger.of(context);
    try {
      await context.read<AppState>().repo.resetPasswordWithCode(
            email: _email.text,
            code: _code.text,
            newPassword: _pass.text,
          );
      nav.pop(true);
      messenger.showSnackBar(const SnackBar(content: Text('Password changed — you are signed in')));
    } on AppException catch (e) {
      if (mounted) showSnack(context, e.message);
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
      appBar: AppBar(),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 520),
            child: ListView(
              padding: const EdgeInsets.fromLTRB(26, 8, 26, 40),
              children: [
                Text('Reset password', style: zHeadline(context, size: 34)),
                const SizedBox(height: 8),
                Text(
                  _sent
                      ? 'We sent a 6-digit code to ${_email.text.trim()}. Enter it below and choose a new password.'
                      : 'Enter the email of your account. We will send you a 6-digit code.',
                  style: const TextStyle(color: Zc.grey, fontSize: 15, height: 1.4),
                ),
                if (demo) ...[
                  const SizedBox(height: 12),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(color: Zc.orangeSoft, borderRadius: BorderRadius.circular(12)),
                    child: const Text('Demo mode: no email is sent. Use the code 123456.', style: TextStyle(fontSize: 13)),
                  ),
                ],
                const SizedBox(height: 22),
                TextField(
                  controller: _email,
                  enabled: !_sent,
                  keyboardType: TextInputType.emailAddress,
                  autocorrect: false,
                  decoration: const InputDecoration(hintText: 'you@example.com'),
                ),
                if (_sent) ...[
                  const SizedBox(height: 14),
                  TextField(
                    controller: _code,
                    keyboardType: TextInputType.number,
                    maxLength: 6,
                    decoration: const InputDecoration(hintText: '6-digit code', counterText: ''),
                  ),
                  const SizedBox(height: 14),
                  TextField(
                    controller: _pass,
                    obscureText: true,
                    decoration: const InputDecoration(hintText: 'New password (at least 6 characters)'),
                  ),
                  const SizedBox(height: 14),
                  TextField(
                    controller: _pass2,
                    obscureText: true,
                    decoration: const InputDecoration(hintText: 'Repeat the new password'),
                    onSubmitted: (_) => _reset(),
                  ),
                ],
                const SizedBox(height: 26),
                PrimaryButton(
                  label: _sent ? 'Save new password' : 'Send code',
                  loading: _loading,
                  width: double.infinity,
                  onPressed: _sent ? _reset : _send,
                ),
                if (_sent)
                  Center(
                    child: TextButton(
                      onPressed: _loading ? null : () => setState(() => _sent = false),
                      child: const Text('Wrong email or no code? Send again', style: TextStyle(color: Zc.green)),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
