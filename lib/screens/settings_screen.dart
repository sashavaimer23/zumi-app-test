import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';

import '../models/models.dart';
import '../state/app_state.dart';
import '../theme.dart';
import '../widgets/common.dart';
import '../widgets/trust.dart';
import '../widgets/zicons.dart';
import 'legal_screen.dart';
import 'support/support_screen.dart';
import 'help/help_screen.dart';
import 'verify/get_verified_screen.dart';
import 'verify/phone_verify_screen.dart';

/// Настройки профиля. У агента больше полей: агентство, «о себе», рабочий WhatsApp, лицензия ZIEA.
class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final _name = TextEditingController();
  final _agency = TextEditingController();
  final _bio = TextEditingController();
  final _whatsapp = TextEditingController();
  bool _saving = false;
  bool _uploading = false;
  bool _dirty = false;

  @override
  void initState() {
    super.initState();
    final u = context.read<AppState>().user;
    _name.text = u?.fullName ?? '';
    _agency.text = u?.agencyName ?? '';
    _bio.text = u?.bio ?? '';
    _whatsapp.text = u?.whatsapp ?? '';
    for (final c in [_name, _agency, _bio, _whatsapp]) {
      c.addListener(() {
        if (!_dirty) setState(() => _dirty = true);
      });
    }
  }

  @override
  void dispose() {
    for (final c in [_name, _agency, _bio, _whatsapp]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _pickAvatar() async {
    final repo = context.read<AppState>().repo;
    try {
      final f = await ImagePicker().pickImage(source: ImageSource.gallery, maxWidth: 1200, imageQuality: 85);
      if (f == null) return;
      setState(() => _uploading = true);
      final bytes = await f.readAsBytes();
      if (bytes.lengthInBytes > 15 * 1024 * 1024) {
        if (mounted) showSnack(context, 'This photo is too large. Please choose one under 15 MB.');
        return;
      }
      // фото уменьшается до 400×400 перед загрузкой (на сервере лимит 5 MB)
      await repo.uploadAvatar(PickedPhoto(f.name, bytes));
      if (mounted) showSnack(context, 'Photo updated');
    } catch (e) {
      if (mounted) showSnack(context, '$e');
    } finally {
      if (mounted) setState(() => _uploading = false);
    }
  }

  Future<void> _save(AppUser u) async {
    if (_name.text.trim().length < 2) {
      showSnack(context, 'Please enter your name');
      return;
    }
    final wa = _whatsapp.text.trim();
    if (u.isAgent && wa.isNotEmpty && wa.replaceAll(RegExp(r'\D'), '').length < 9) {
      showSnack(context, 'Enter a valid WhatsApp number, e.g. +260 97 123 4567');
      return;
    }
    setState(() => _saving = true);
    final app = context.read<AppState>();
    try {
      await app.repo.updateProfile(
        fullName: _name.text,
        agencyName: u.isAgent ? _agency.text : null,
        bio: u.isAgent ? _bio.text : null,
        whatsapp: u.isAgent ? wa : null,
      );
      app.dataChanged();
      if (mounted) {
        setState(() => _dirty = false);
        showSnack(context, 'Saved');
      }
    } catch (e) {
      if (mounted) showSnack(context, '$e');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _changePassword() async {
    final repo = context.read<AppState>().repo;
    final pass = await showDialog<String>(context: context, builder: (_) => const _NewPasswordDialog());
    if (pass == null) return;
    try {
      await repo.changePassword(pass);
      if (mounted) showSnack(context, 'Password changed');
    } catch (e) {
      if (mounted) showSnack(context, '$e');
    }
  }

  Future<void> _deleteAccount() async {
    final app = context.read<AppState>();
    final ok = await showDialog<bool>(context: context, builder: (_) => const _DeleteDialog());
    if (ok != true) return;
    final messenger = ScaffoldMessenger.of(context);
    final nav = Navigator.of(context);
    try {
      await app.repo.deleteAccount();
      nav.popUntil((r) => r.isFirst);
      messenger.showSnackBar(const SnackBar(content: Text('Your account and all your data were deleted')));
    } catch (e) {
      if (mounted) showSnack(context, '$e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final u = app.user;
    if (u == null) {
      return Scaffold(appBar: AppBar(), body: const Center(child: Text('Please sign in first')));
    }

    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 640),
          child: ListView(
            padding: const EdgeInsets.fromLTRB(22, 8, 22, 40),
            children: [
              // ---------- фото ----------
              Center(
                child: GestureDetector(
                  onTap: _uploading ? null : _pickAvatar,
                  child: Stack(clipBehavior: Clip.none, children: [
                    ZAvatar(url: u.avatarUrl, name: u.fullName ?? u.email, size: 104),
                    if (_uploading)
                      const Positioned.fill(
                        child: DecoratedBox(
                          decoration: BoxDecoration(color: Zc.scrim, shape: BoxShape.circle),
                          child: Center(child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2.5)),
                        ),
                      ),
                    Positioned(
                      right: 0,
                      bottom: 0,
                      child: Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: Zc.orange,
                          shape: BoxShape.circle,
                          border: Border.all(color: Zc.bg, width: 3),
                        ),
                        child: const Icon(ZI.camera, size: 18, color: Colors.white),
                      ),
                    ),
                  ]),
                ),
              ),
              const SizedBox(height: 8),
              Center(
                child: TextButton(
                  onPressed: _uploading ? null : _pickAvatar,
                  child: Text(u.avatarUrl == null ? 'Add a photo' : 'Change photo',
                      style: const TextStyle(color: Zc.orange)),
                ),
              ),
              Text(
                u.isAgent
                    ? 'A clear photo of you or your agency logo — clients trust agents they can see.'
                    : 'Optional. A real photo helps buyers and tenants trust you.',
                textAlign: TextAlign.center,
                style: const TextStyle(color: Zc.grey, fontSize: 13),
              ),

              // ---------- профиль ----------
              const _Section('Profile'),
              _label('Full name'),
              TextField(
                controller: _name,
                textCapitalization: TextCapitalization.words,
                decoration: const InputDecoration(hintText: 'As on your NRC or passport'),
              ),
              if (u.isAgent) ...[
                _label('Agency name'),
                TextField(
                  controller: _agency,
                  textCapitalization: TextCapitalization.words,
                  decoration: const InputDecoration(hintText: 'e.g. Lusaka Homes Ltd (or leave empty)'),
                ),
                _label('About you'),
                TextField(
                  controller: _bio,
                  minLines: 3,
                  maxLines: 6,
                  maxLength: 600,
                  textCapitalization: TextCapitalization.sentences,
                  decoration: const InputDecoration(
                    hintText: 'Areas you work in, years of experience, languages, viewing days…',
                  ),
                ),
                _label('Business WhatsApp'),
                TextField(
                  controller: _whatsapp,
                  keyboardType: TextInputType.phone,
                  decoration: const InputDecoration(hintText: '+260 …'),
                ),
                const Padding(
                  padding: EdgeInsets.only(top: 6),
                  child: Text('Shown on your agent page so clients can reach you.',
                      style: TextStyle(color: Zc.grey, fontSize: 12)),
                ),
              ],
              const SizedBox(height: 18),
              PrimaryButton(
                label: 'Save changes',
                loading: _saving,
                width: double.infinity,
                onPressed: _dirty ? () => _save(u) : null,
              ),

              // ---------- как с вами связываются ----------
              const _Section('How people contact you'),
              for (final (mode, title, sub) in const [
                ('phone', 'Show my number', 'People with a confirmed phone can tap "Show number" (max 15 numbers a day each).'),
                ('chat', 'Chat only', 'Your number is never shown. People write to you in Zumi chat.'),
              ])
                RadioListTile<String>(
                  contentPadding: EdgeInsets.zero,
                  value: mode,
                  groupValue: u.contactMode,
                  activeColor: Zc.orange,
                  title: Text(title, style: const TextStyle(fontSize: 15)),
                  subtitle: Text(sub, style: const TextStyle(fontSize: 12, color: Zc.grey)),
                  onChanged: (v) async {
                    if (v == null) return;
                    try {
                      await app.repo.updateProfile(contactMode: v);
                      app.dataChanged();
                      if (context.mounted) showSnack(context, v == 'chat' ? 'Chat only — your number is hidden' : 'Your number can be shown');
                    } catch (e) {
                      if (context.mounted) showSnack(context, '$e');
                    }
                  },
                ),

              // ---------- рассылка ----------
              const _Section('News and offers'),
              for (final (channel, on, title) in [
                ('email', u.marketingEmail, 'By email'),
                ('whatsapp', u.marketingWhatsapp, 'By WhatsApp'),
              ])
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  activeColor: Zc.orange,
                  value: on,
                  title: Text(title, style: const TextStyle(fontSize: 15)),
                  subtitle: Text(
                    channel == 'email'
                        ? 'New features, tips and special offers — a few emails a month at most.'
                        : (u.phoneVerified
                            ? 'Sent to your confirmed number ${u.phone ?? ''}.'
                            : 'We send to your phone after you confirm it.'),
                    style: const TextStyle(fontSize: 12, color: Zc.grey),
                  ),
                  onChanged: (v) async {
                    try {
                      await app.repo.setMarketing(channel, v);
                      if (context.mounted) showSnack(context, v ? 'Subscribed ${title.toLowerCase()}' : 'Unsubscribed ${title.toLowerCase()}');
                    } catch (e) {
                      if (context.mounted) showSnack(context, '$e');
                    }
                  },
                ),

              // ---------- проверка ----------
              const _Section('Phone & verification'),
              _Row(
                icon: ZI.mobile,
                title: (u.phone ?? '').isEmpty ? 'No phone number' : u.phone!,
                subtitle: u.phoneVerified
                    ? 'Confirmed by ${u.phoneChannel == 'whatsapp' ? 'WhatsApp' : 'SMS'}'
                    : 'Not confirmed yet',
                trailing: u.phoneVerified ? 'Change' : 'Verify',
                onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const PhoneVerifyScreen())),
              ),
              _Row(
                icon: ZI.shield,
                title: u.identityVerified ? 'You are Verified' : 'Get the Verified badge',
                subtitle: u.identityVerified
                    ? 'The badge is shown on all your listings.'
                    : 'Phone + NRC / passport${u.isAgent ? ' + ZIEA licence' : ''} — about 3 minutes',
                trailingWidget: u.identityVerified ? const VerifiedMark(size: 20) : null,
                onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const GetVerifiedScreen())),
              ),
              if (u.isAgent)
                _Row(
                  icon: ZI.badge,
                  title: (u.licenceNo ?? '').isEmpty ? 'ZIEA licence' : 'ZIEA licence ${u.licenceNo}',
                  subtitle: u.licenceVerified
                      ? 'Checked by the Zumi team'
                      : ((u.licenceNo ?? '').isEmpty ? 'Not added yet' : 'With the Zumi team — about 15 minutes'),
                  onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const GetVerifiedScreen())),
                ),

              // ---------- аккаунт ----------
              const _Section('Account'),
              _Row(icon: ZI.envelope, title: u.email ?? 'No email', subtitle: 'Email for signing in'),
              _Row(
                icon: u.isAgent ? ZI.badge : ZI.house,
                title: u.isAdmin ? 'Zumi team' : (u.isAgent ? 'Agent account' : 'Owner account'),
                subtitle: 'To change the account type, write to support',
              ),
              _Row(icon: ZI.lock, title: 'Change password', onTap: _changePassword),

              // ---------- помощь и документы ----------
              const _Section('Help & legal'),
              _Row(
                icon: ZI.chat,
                title: 'Help & support',
                onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const HelpScreen())),
              ),
              _Row(
                icon: ZI.fileText,
                title: 'Terms of Service',
                onTap: () => openLegal(context, LegalDoc.terms),
              ),
              _Row(
                icon: ZI.shieldFill,
                title: 'Privacy Policy',
                onTap: () => openLegal(context, LegalDoc.privacy),
              ),

              const SizedBox(height: 26),
              OutlinedButton.icon(
                style: OutlinedButton.styleFrom(
                  foregroundColor: Zc.green,
                  side: const BorderSide(color: Zc.green),
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                ),
                onPressed: () async {
                  await app.repo.signOut();
                  if (context.mounted) Navigator.of(context).popUntil((r) => r.isFirst);
                },
                icon: const Icon(ZI.signOut),
                label: const Text('Sign out'),
              ),
              const SizedBox(height: 10),
              TextButton.icon(
                onPressed: _deleteAccount,
                icon: const Icon(ZI.trash, color: Color(0xFFC0392B)),
                label: const Text('Delete my account', style: TextStyle(color: Color(0xFFC0392B))),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _label(String t) => Padding(
        padding: const EdgeInsets.only(bottom: 8, top: 16),
        child: Text(t, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: Zc.text)),
      );
}

class _Section extends StatelessWidget {
  const _Section(this.title);
  final String title;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(top: 30, bottom: 6),
        child: Text(title, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w600, color: Zc.green)),
      );
}

class _Row extends StatelessWidget {
  const _Row({required this.icon, required this.title, this.subtitle, this.trailing, this.trailingWidget, this.onTap});
  final IconData icon;
  final String title;
  final String? subtitle;
  final String? trailing;
  final Widget? trailingWidget;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: Icon(icon, color: Zc.green),
      title: Text(title, style: const TextStyle(fontSize: 15)),
      subtitle: subtitle == null ? null : Text(subtitle!, style: const TextStyle(fontSize: 13, color: Zc.grey)),
      trailing: trailingWidget ??
          (trailing != null
              ? Text(trailing!, style: const TextStyle(color: Zc.orange))
              : (onTap != null ? const Icon(ZI.caretRight, size: 18, color: Zc.grey) : null)),
      onTap: onTap,
    );
  }
}

class _NewPasswordDialog extends StatefulWidget {
  const _NewPasswordDialog();

  @override
  State<_NewPasswordDialog> createState() => _NewPasswordDialogState();
}

class _NewPasswordDialogState extends State<_NewPasswordDialog> {
  final _a = TextEditingController();
  final _b = TextEditingController();
  String? _error;

  @override
  void dispose() {
    _a.dispose();
    _b.dispose();
    super.dispose();
  }

  void _ok() {
    if (_a.text.length < 6) {
      setState(() => _error = 'At least 6 characters');
    } else if (_a.text != _b.text) {
      setState(() => _error = 'Passwords do not match');
    } else {
      Navigator.pop(context, _a.text);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('New password'),
      content: Column(mainAxisSize: MainAxisSize.min, children: [
        TextField(controller: _a, obscureText: true, decoration: const InputDecoration(hintText: 'New password')),
        const SizedBox(height: 10),
        TextField(
          controller: _b,
          obscureText: true,
          decoration: InputDecoration(hintText: 'Repeat the password', errorText: _error),
          onSubmitted: (_) => _ok(),
        ),
      ]),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
        TextButton(onPressed: _ok, child: const Text('Save')),
      ],
    );
  }
}

class _DeleteDialog extends StatefulWidget {
  const _DeleteDialog();

  @override
  State<_DeleteDialog> createState() => _DeleteDialogState();
}

class _DeleteDialogState extends State<_DeleteDialog> {
  final _c = TextEditingController();

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final ok = _c.text.trim().toUpperCase() == 'DELETE';
    return AlertDialog(
      title: const Text('Delete your account?'),
      content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Text(
          'Your profile, listings, photos, chats and documents will be deleted for good. '
          'This cannot be undone.\n\nType DELETE to confirm.',
          style: TextStyle(height: 1.4),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _c,
          autofocus: true,
          textCapitalization: TextCapitalization.characters,
          decoration: const InputDecoration(hintText: 'DELETE'),
          onChanged: (_) => setState(() {}),
        ),
      ]),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
        TextButton(
          onPressed: ok ? () => Navigator.pop(context, true) : null,
          child: Text('Delete', style: TextStyle(color: ok ? const Color(0xFFC0392B) : Zc.grey)),
        ),
      ],
    );
  }
}
