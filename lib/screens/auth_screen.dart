import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../features.dart';
import '../models/models.dart';
import '../state/app_state.dart';
import '../theme.dart';
import '../widgets/common.dart';
import '../widgets/signup_parts.dart';
import 'forgot_password_screen.dart';
import 'help/help_screen.dart';
import 'verify/phone_verify_screen.dart';
import '../widgets/zicons.dart';

/// Вход / регистрация. При регистрации выбирается роль: собственник или агент.
/// Возвращает true через Navigator.pop, если пользователь вошёл.
class AuthScreen extends StatefulWidget {
  const AuthScreen({super.key, this.embedded = false, this.reason});

  /// true — экран встроен во вкладку (без кнопки «назад» и без pop)
  final bool embedded;
  final String? reason;

  @override
  State<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends State<AuthScreen> {
  bool _signUp = false;
  bool _loading = false;
  bool _googleLoading = false;
  bool _facebookLoading = false;
  String _role = 'owner';
  bool _consent = false;
  bool _marketing = false; // новости и предложения — по желанию, по умолчанию выключено
  final _form = GlobalKey<FormState>();
  final _email = TextEditingController();
  final _password = TextEditingController();
  final _name = TextEditingController();
  final _phone = TextEditingController();
  final _licence = TextEditingController(); // номер ZIEA (агенты)
  final _agencyName = TextEditingController(); // регистрация агентства
  final _firmNo = TextEditingController();

  /// Почта, на которую ушло письмо «подтвердите почту» — пока не null, показываем экран «Проверьте почту»
  String? _awaitingEmail;
  int _resendIn = 0; // секунд до повторной отправки
  Timer? _resendTimer;
  bool _resending = false;

  @override
  void dispose() {
    _resendTimer?.cancel();
    for (final c in [_email, _password, _name, _phone, _licence, _agencyName, _firmNo]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_form.currentState!.validate()) {
      // ошибки видны у полей; если человек внизу формы — подскажем, что смотреть выше
      showSnack(context, 'Please check the fields marked in red');
      return;
    }
    if (_signUp && !_consent) {
      showSnack(context, 'Please accept the Terms of Service and Privacy Policy');
      return;
    }
    setState(() => _loading = true);
    final repo = context.read<AppState>().repo;
    final nav = Navigator.of(context); // экран входа может исчезнуть сразу после входа
    try {
      if (_signUp) {
        await repo.signUp(
          email: _email.text.trim(),
          password: _password.text,
          fullName: _name.text.trim(),
          phone: _phone.text.trim(),
          role: _role,
          termsAccepted: _consent,
          licenceNo: _role != 'owner' ? _licence.text.trim() : null,
          marketing: _marketing,
          agencyName: _role == 'agency' ? _agencyName.text.trim() : null,
          firmLicenceNo: _role == 'agency' ? _firmNo.text.trim() : null,
        );
        // после регистрации — предлагаем подтвердить телефон по SMS (можно пропустить)
        if (!widget.embedded) nav.pop(true);
        nav.push(MaterialPageRoute(builder: (_) => const PhoneVerifyScreen(afterSignup: true)));
        return;
      } else {
        await repo.signIn(email: _email.text.trim(), password: _password.text);
      }
      if (!mounted) return;
      if (!widget.embedded) Navigator.pop(context, true);
    } on AppException catch (e) {
      if (!mounted) return;
      if (e.code == 'CONFIRM_EMAIL') {
        // регистрация прошла (или вход до подтверждения) — объясняем, что делать дальше
        _showCheckEmail(_email.text.trim(), justSent: _signUp);
        return;
      }
      showSnack(context, e.message);
    } catch (e) {
      if (mounted) showSnack(context, '$e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  /// Вход через Google: страница уходит на Google и возвращается уже со входом.
  /// Новым людям после этого покажется экран «Finish setting up» (роль и согласие).
  Future<void> _google() async {
    setState(() => _googleLoading = true);
    try {
      await context.read<AppState>().repo.signInWithGoogle();
    } on AppException catch (e) {
      if (mounted) showSnack(context, e.message);
    } catch (e) {
      if (mounted) showSnack(context, '$e');
    } finally {
      if (mounted) setState(() => _googleLoading = false);
    }
  }

  Future<void> _facebook() async {
    setState(() => _facebookLoading = true);
    try {
      await context.read<AppState>().repo.signInWithFacebook();
    } on AppException catch (e) {
      if (mounted) showSnack(context, e.message);
    } catch (e) {
      if (mounted) showSnack(context, '$e');
    } finally {
      if (mounted) setState(() => _facebookLoading = false);
    }
  }

  void _showCheckEmail(String email, {required bool justSent}) {
    setState(() {
      _awaitingEmail = email;
      _signUp = false;
    });
    if (justSent) _startCooldown();
  }

  void _startCooldown() {
    _resendTimer?.cancel();
    setState(() => _resendIn = 60);
    _resendTimer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted) {
        t.cancel();
        return;
      }
      setState(() => _resendIn--);
      if (_resendIn <= 0) t.cancel();
    });
  }

  Future<void> _resend() async {
    final email = _awaitingEmail;
    if (email == null) return;
    setState(() => _resending = true);
    try {
      await context.read<AppState>().repo.resendConfirmation(email);
      if (!mounted) return;
      _startCooldown();
      showSnack(context, 'Sent again. Check your inbox and Spam.');
    } on AppException catch (e) {
      if (mounted) showSnack(context, e.message);
    } catch (e) {
      if (mounted) showSnack(context, '$e');
    } finally {
      if (mounted) setState(() => _resending = false);
    }
  }

  /// Экран «Проверьте почту»: что произошло, что сделать, повторная отправка и вход
  Widget _checkEmailView(String email) {
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
    return Scaffold(
      appBar: widget.embedded ? null : AppBar(),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(26, 32, 26, 120),
          children: [
            Center(
              child: Container(
                width: 84, height: 84,
                decoration: const BoxDecoration(color: Zc.orangeSoft, shape: BoxShape.circle),
                child: const Icon(ZI.envelope, size: 40, color: Zc.orange),
              ),
            ),
            const SizedBox(height: 22),
            Text('Check your email', textAlign: TextAlign.center, style: zHeadline(context, size: 32)),
            const SizedBox(height: 10),
            const Text('We sent a confirmation link to', textAlign: TextAlign.center,
                style: TextStyle(color: Zc.grey, fontSize: 15)),
            const SizedBox(height: 4),
            Text(email, textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: Zc.text)),
            const SizedBox(height: 26),
            Container(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
              decoration: BoxDecoration(color: Zc.white, borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: Zc.lightGrey)),
              child: Column(children: [
                step('1', 'Open your email inbox.'),
                step('2', 'Find the email from Zumi. Not there? Check Spam or Promotions.'),
                step('3', 'Tap the link in the email — your account is then confirmed.'),
                step('4', 'Come back here and sign in.'),
              ]),
            ),
            const SizedBox(height: 26),
            PrimaryButton(
              label: "I've confirmed — Sign in",
              width: double.infinity,
              onPressed: () => setState(() {
                _awaitingEmail = null;
                _email.text = email;
              }),
            ),
            const SizedBox(height: 12),
            Center(
              child: TextButton(
                onPressed: (_resendIn > 0 || _resending) ? null : _resend,
                child: Text(
                  _resending
                      ? 'Sending…'
                      : _resendIn > 0 ? 'Resend the email in $_resendIn s' : "Didn't get it? Resend the email",
                  style: TextStyle(color: _resendIn > 0 ? Zc.grey : Zc.green, fontSize: 15),
                ),
              ),
            ),
            Center(
              child: TextButton(
                onPressed: () => setState(() {
                  _awaitingEmail = null;
                  _signUp = true;
                }),
                child: const Text('Wrong email? Change it', style: TextStyle(color: Zc.grey, fontSize: 14)),
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final awaiting = _awaitingEmail;
    if (awaiting != null) return _checkEmailView(awaiting);
    final demo = context.read<AppState>().repo.isDemo;
    return Scaffold(
      appBar: widget.embedded ? null : AppBar(),
      body: SafeArea(
        child: Form(
          key: _form,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(26, 24, 26, 120),
            children: [
              const Align(alignment: Alignment.centerLeft, child: ZLogo(size: 52)),
              const SizedBox(height: 20),
              Text(_signUp ? 'Create account' : 'Welcome back', style: zHeadline(context, size: 36)),
              const SizedBox(height: 8),
              Text(
                widget.reason ?? (_signUp ? 'List properties and chat with buyers and tenants.' : 'Sign in to post and chat.'),
                style: const TextStyle(color: Zc.grey, fontSize: 15),
              ),
              if (demo) ...[
                const SizedBox(height: 14),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(color: Zc.orangeSoft, borderRadius: BorderRadius.circular(12)),
                  child: const Text(
                    'Demo mode: any email and a 6+ character password will work. Nothing is sent to a server. '
                    'Tip: an email with "agent" signs in as an agent, "admin" — as the Zumi owner, '
                    '"moderator" — as a moderator.',
                    style: TextStyle(fontSize: 13),
                  ),
                ),
              ],
              const SizedBox(height: 26),
              // самый быстрый путь: аккаунт Google (роль и согласие — на следующем экране)
              GoogleButton(loading: _googleLoading, onPressed: _google),
              if (Features.facebookLogin) ...[
                const SizedBox(height: 12),
                FacebookButton(loading: _facebookLoading, onPressed: _facebook),
              ],
              const OrDivider(),
              if (_signUp) ...[
                const Text.rich(
                  TextSpan(children: [
                    TextSpan(text: '* ', style: TextStyle(color: Zc.orange, fontWeight: FontWeight.w700)),
                    TextSpan(text: 'required field'),
                  ]),
                  style: TextStyle(fontSize: 13, color: Zc.grey),
                ),
                const SizedBox(height: 14),
                const FieldLabel('I am', required: true),
                RolePicker(value: _role, onChanged: (r) => setState(() => _role = r)),
                const SizedBox(height: 18),
                const FieldLabel('Full name', required: true),
                TextFormField(
                  controller: _name,
                  textCapitalization: TextCapitalization.words,
                  decoration: const InputDecoration(hintText: 'Your name'),
                  validator: (v) => (v ?? '').trim().length < 2 ? 'Enter your name' : null,
                ),
                const SizedBox(height: 18),
                const FieldLabel('Phone', required: true),
                TextFormField(
                  controller: _phone,
                  keyboardType: TextInputType.phone,
                  decoration: const InputDecoration(hintText: '+260 …'),
                  validator: (v) => (v ?? '').replaceAll(RegExp(r'\D'), '').length < 9 ? 'Enter a valid phone' : null,
                ),
                const SizedBox(height: 18),
                if (_role == 'agency') AgencyFields(name: _agencyName, firmNo: _firmNo),
                if (_role != 'owner') ...[
                  FieldLabel(_role == 'agency' ? 'Your personal ZIEA number' : 'ZIEA registration number', optional: true),
                  TextFormField(
                    controller: _licence,
                    textCapitalization: TextCapitalization.characters,
                    decoration: const InputDecoration(hintText: 'e.g. ZIEA-1234 — or leave empty'),
                    validator: (v) => (v ?? '').trim().length > 40 ? 'Too long' : null,
                  ),
                  const SizedBox(height: 6),
                  const Text(kLicenceHint, style: TextStyle(fontSize: 12, color: Zc.grey, height: 1.35)),
                  const SizedBox(height: 18),
                ],
              ],
              FieldLabel('Email', required: _signUp),
              TextFormField(
                controller: _email,
                keyboardType: TextInputType.emailAddress,
                autocorrect: false,
                decoration: const InputDecoration(hintText: 'you@example.com'),
                validator: (v) => RegExp(r'^\S+@\S+\.\S+$').hasMatch((v ?? '').trim()) ? null : 'Enter a valid email',
              ),
              const SizedBox(height: 18),
              FieldLabel('Password', required: _signUp),
              TextFormField(
                controller: _password,
                obscureText: true,
                decoration: const InputDecoration(hintText: 'At least 6 characters'),
                validator: (v) => (v ?? '').length < 6 ? 'At least 6 characters' : null,
                onFieldSubmitted: (_) => _submit(),
              ),
              if (!_signUp)
                Align(
                  alignment: Alignment.centerRight,
                  child: TextButton(
                    onPressed: () async {
                      final ok = await Navigator.push<bool>(
                        context,
                        MaterialPageRoute(builder: (_) => ForgotPasswordScreen(email: _email.text.trim())),
                      );
                      if (ok == true && mounted && !widget.embedded) Navigator.pop(context, true);
                    },
                    child: const Text('Forgot password?', style: TextStyle(color: Zc.orange)),
                  ),
                ),
              if (_signUp) ...[
                const SizedBox(height: 16),
                // отдельная галочка согласия — дата согласия сохраняется на сервере
                ConsentCheck(value: _consent, onChanged: (v) => setState(() => _consent = v)),
                // где хранятся данные — до согласия, простыми словами
                  MarketingCheck(value: _marketing, onChanged: (v) => setState(() => _marketing = v)),
              ],
              const SizedBox(height: 30),
              Center(
                child: PrimaryButton(
                  label: _signUp ? 'Sign up' : 'Sign in',
                  loading: _loading,
                  onPressed: _submit,
                  width: double.infinity,
                ),
              ),
              const SizedBox(height: 14),
              Center(
                child: TextButton(
                  onPressed: () => setState(() => _signUp = !_signUp),
                  child: Text(
                    _signUp ? 'Already have an account? Sign in' : 'New to Zumi? Create an account',
                    style: const TextStyle(color: Zc.green, fontSize: 15),
                  ),
                ),
              ),
              // помощь доступна и без входа
              Center(
                child: TextButton.icon(
                  onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const HelpScreen())),
                  icon: const Icon(ZI.info, size: 18, color: Zc.grey),
                  label: const Text('Help & questions', style: TextStyle(color: Zc.grey)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
