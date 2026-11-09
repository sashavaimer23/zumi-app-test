import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/models.dart';
import '../state/app_state.dart';
import '../theme.dart';
import '../widgets/common.dart';
import '../widgets/signup_parts.dart';
import 'verify/phone_verify_screen.dart';

/// Пока аккаунт, созданный через Google, не закончил регистрацию — вместо приложения
/// показываем экран «Finish setting up». Обычные аккаунты (почта + пароль) его не видят.
class OnboardingGate extends StatelessWidget {
  const OnboardingGate({super.key, required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final needs = context.select<AppState, bool>((s) => s.user?.needsOnboarding ?? false);
    return needs ? const FinishSignupScreen() : child;
  }
}

/// Последний шаг после входа через Google: роль, имя, телефон, лицензия (агентам), согласие.
class FinishSignupScreen extends StatefulWidget {
  const FinishSignupScreen({super.key});

  @override
  State<FinishSignupScreen> createState() => _FinishSignupScreenState();
}

class _FinishSignupScreenState extends State<FinishSignupScreen> {
  final _form = GlobalKey<FormState>();
  late final TextEditingController _name;
  final _phone = TextEditingController();
  final _licence = TextEditingController();
  final _agencyName = TextEditingController();
  final _firmNo = TextEditingController();
  String _role = 'owner';
  bool _consent = false;
  bool _marketing = false;
  bool _loading = false;

  @override
  void initState() {
    super.initState();
    // имя из Google — человек может поправить
    _name = TextEditingController(text: context.read<AppState>().user?.fullName ?? '');
  }

  @override
  void dispose() {
    for (final c in [_name, _phone, _licence, _agencyName, _firmNo]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_form.currentState!.validate()) {
      showSnack(context, 'Please check the fields marked in red');
      return;
    }
    if (!_consent) {
      showSnack(context, 'Please accept the Terms of Service and Privacy Policy');
      return;
    }
    setState(() => _loading = true);
    final nav = Navigator.of(context);
    try {
      await context.read<AppState>().repo.completeSignup(
            role: _role == 'agency' ? 'agent' : _role,
            fullName: _name.text.trim(),
            phone: _phone.text.trim(),
            licenceNo: _role != 'owner' ? _licence.text.trim() : null,
            termsAccepted: _consent,
            marketing: _marketing,
          );
      if (_role == 'agency' && mounted) {
        await context.read<AppState>().repo.createAgency(name: _agencyName.text.trim(), firmLicenceNo: _firmNo.text.trim());
      }
      // как после обычной регистрации — предлагаем сразу подтвердить телефон (можно пропустить)
      nav.push(MaterialPageRoute(builder: (_) => const PhoneVerifyScreen(afterSignup: true)));
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
    final email = context.select<AppState, String?>((s) => s.user?.email);
    return Scaffold(
      body: SafeArea(
        child: Form(
          key: _form,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(26, 24, 26, 120),
            children: [
              const Align(alignment: Alignment.centerLeft, child: ZLogo(size: 52)),
              const SizedBox(height: 20),
              Text('Finish setting up', style: zHeadline(context, size: 34)),
              const SizedBox(height: 8),
              Text(
                email == null
                    ? 'One last step — tell us who you are.'
                    : 'You signed in as $email. One last step — tell us who you are.',
                style: const TextStyle(color: Zc.grey, fontSize: 15, height: 1.35),
              ),
              const SizedBox(height: 24),
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
              ConsentCheck(value: _consent, onChanged: (v) => setState(() => _consent = v)),
              MarketingCheck(value: _marketing, onChanged: (v) => setState(() => _marketing = v)),
              const SizedBox(height: 30),
              PrimaryButton(label: 'Continue', loading: _loading, onPressed: _submit, width: double.infinity),
              const SizedBox(height: 14),
              // передумал — выходим; аккаунт остаётся без согласия и ничего не может публиковать
              Center(
                child: TextButton(
                  onPressed: _loading ? null : () => context.read<AppState>().repo.signOut(),
                  child: const Text('Not now — sign out', style: TextStyle(color: Zc.grey, fontSize: 15)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
