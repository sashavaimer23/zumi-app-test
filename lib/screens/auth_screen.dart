import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/models.dart';
import '../state/app_state.dart';
import '../theme.dart';
import '../widgets/common.dart';
import 'forgot_password_screen.dart';
import 'legal_screen.dart';
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
  String _role = 'owner';
  bool _consent = false;
  final _form = GlobalKey<FormState>();
  final _email = TextEditingController();
  final _password = TextEditingController();
  final _name = TextEditingController();
  final _phone = TextEditingController();
  final _licence = TextEditingController(); // номер ZIEA (агенты)

  @override
  void dispose() {
    for (final c in [_email, _password, _name, _phone, _licence]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_form.currentState!.validate()) return;
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
          licenceNo: _role == 'agent' ? _licence.text.trim() : null,
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
      if (e.code == 'CONFIRM_EMAIL') setState(() => _signUp = false);
      showSnack(context, e.message);
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
                    'Tip: an email with "agent" signs in as an agent.',
                    style: TextStyle(fontSize: 13),
                  ),
                ),
              ],
              const SizedBox(height: 26),
              if (_signUp) ...[
                _label('I am'),
                Row(children: [
                  Expanded(child: _roleCard('owner', 'Owner', 'I list my own property', ZI.house)),
                  const SizedBox(width: 12),
                  Expanded(child: _roleCard('agent', 'Agent', 'I list for clients', ZI.badge)),
                ]),
                const SizedBox(height: 18),
                _label('Full name'),
                TextFormField(
                  controller: _name,
                  textCapitalization: TextCapitalization.words,
                  decoration: const InputDecoration(hintText: 'Your name'),
                  validator: (v) => (v ?? '').trim().length < 2 ? 'Enter your name' : null,
                ),
                const SizedBox(height: 18),
                _label('Phone'),
                TextFormField(
                  controller: _phone,
                  keyboardType: TextInputType.phone,
                  decoration: const InputDecoration(hintText: '+260 …'),
                  validator: (v) => (v ?? '').replaceAll(RegExp(r'\D'), '').length < 9 ? 'Enter a valid phone' : null,
                ),
                const SizedBox(height: 18),
                if (_role == 'agent') ...[
                  _label('ZIEA registration number'),
                  TextFormField(
                    controller: _licence,
                    textCapitalization: TextCapitalization.characters,
                    decoration: const InputDecoration(hintText: 'From your ZIEA certificate (you can add it later)'),
                    validator: (v) => (v ?? '').trim().length > 40 ? 'Too long' : null,
                  ),
                  const SizedBox(height: 6),
                  const Text(
                    'The Zumi team checks it with the Zambia Institute of Estate Agents. Until then your listings show '
                    '"ZIEA licence not verified" and promotion is not available.',
                    style: TextStyle(fontSize: 12, color: Zc.grey, height: 1.35),
                  ),
                  const SizedBox(height: 18),
                ],
              ],
              _label('Email'),
              TextFormField(
                controller: _email,
                keyboardType: TextInputType.emailAddress,
                autocorrect: false,
                decoration: const InputDecoration(hintText: 'you@example.com'),
                validator: (v) => RegExp(r'^\S+@\S+\.\S+$').hasMatch((v ?? '').trim()) ? null : 'Enter a valid email',
              ),
              const SizedBox(height: 18),
              _label('Password'),
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
                Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Checkbox(
                    value: _consent,
                    activeColor: Zc.orange,
                    onChanged: (v) => setState(() => _consent = v ?? false),
                  ),
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.only(top: 12),
                      child: Wrap(crossAxisAlignment: WrapCrossAlignment.center, children: [
                        const Text('I agree to the ', style: TextStyle(fontSize: 13, color: Zc.text)),
                        _link('Terms of Service', () => openLegal(context, LegalDoc.terms)),
                        const Text(' and ', style: TextStyle(fontSize: 13, color: Zc.text)),
                        _link('Privacy Policy', () => openLegal(context, LegalDoc.privacy)),
                        const Text(', and to Zumi processing my data to run my account.',
                            style: TextStyle(fontSize: 13, color: Zc.text)),
                      ]),
                    ),
                  ),
                ]),
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
            ],
          ),
        ),
      ),
    );
  }

  Widget _link(String text, VoidCallback onTap) => GestureDetector(
        onTap: onTap,
        child: Text(text,
            style: const TextStyle(fontSize: 13, color: Zc.green, decoration: TextDecoration.underline)),
      );

  Widget _label(String t) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Text(t, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w600, color: Zc.text)),
      );

  Widget _roleCard(String role, String title, String sub, IconData icon) {
    final on = _role == role;
    return GestureDetector(
      onTap: () => setState(() => _role = role),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: on ? Zc.orangeSoft : Colors.white,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: on ? Zc.orange : Zc.green, width: on ? 1.6 : 0.8),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Icon(icon, color: Zc.green),
            const Spacer(),
            RadioDot(selected: on, size: 20),
          ]),
          const SizedBox(height: 10),
          Text(title, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w600, color: Zc.green)),
          Text(sub, style: const TextStyle(fontSize: 12, color: Zc.grey)),
        ]),
      ),
    );
  }
}
