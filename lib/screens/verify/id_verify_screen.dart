import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';

import '../../models/models.dart';
import '../../state/app_state.dart';
import '../../theme.dart';
import '../../widgets/common.dart';
import '../../widgets/zicons.dart';

/// Проверка личности: тип документа → фото документа → селфи → согласие.
/// Возвращает true, если отправлено.
class IdVerifyScreen extends StatefulWidget {
  const IdVerifyScreen({super.key});

  @override
  State<IdVerifyScreen> createState() => _IdVerifyScreenState();
}

class _IdVerifyScreenState extends State<IdVerifyScreen> {
  String _docType = 'nrc';
  PickedPhoto? _doc;
  PickedPhoto? _selfie;
  bool _consent = false;
  bool _sending = false;

  Future<PickedPhoto?> _capture({required bool selfie, ImageSource source = ImageSource.camera}) async {
    try {
      final f = await ImagePicker().pickImage(
        source: source,
        preferredCameraDevice: selfie ? CameraDevice.front : CameraDevice.rear,
        imageQuality: 80,
        maxWidth: 1800,
        maxHeight: 1800,
      );
      if (f == null) return null;
      return PickedPhoto(f.name, await f.readAsBytes());
    } catch (e) {
      if (mounted) showSnack(context, 'Could not open the camera: $e');
      return null;
    }
  }

  Future<void> _send() async {
    if (_doc == null || _selfie == null) {
      showSnack(context, 'Please add both photos');
      return;
    }
    if (!_consent) {
      showSnack(context, 'Please confirm your consent below');
      return;
    }
    setState(() => _sending = true);
    try {
      await context.read<AppState>().repo.submitIdentity(docType: _docType, document: _doc!, selfie: _selfie!);
      if (!mounted) return;
      showSnack(
        context,
        context.read<AppState>().repo.isDemo
            ? 'Demo mode: approved instantly'
            : 'Sent! We check within 1–2 working days.',
      );
      Navigator.pop(context, true);
    } catch (e) {
      if (mounted) showSnack(context, '$e');
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final docName = _docType == 'nrc' ? 'NRC' : 'passport';
    return Scaffold(
      appBar: AppBar(title: const Text('ID check')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(22, 4, 22, 40),
        children: [
          Text('Confirm your identity', style: zHeadline(context, size: 28)),
          const SizedBox(height: 6),
          const Text('Two photos and you are done.', style: TextStyle(color: Zc.grey, fontSize: 15)),
          const SizedBox(height: 20),

          // 1. тип документа
          const _Label('1. Choose your document'),
          Wrap(spacing: 10, children: [
            ZChip(label: 'NRC', selected: _docType == 'nrc', onTap: () => setState(() => _docType = 'nrc')),
            ZChip(
              label: 'Passport',
              selected: _docType == 'passport',
              onTap: () => setState(() => _docType = 'passport'),
            ),
          ]),
          const SizedBox(height: 22),

          // 2. фото документа
          _Label('2. Photo of your $docName'),
          _PhotoBox(
            photo: _doc,
            icon: ZI.idCard,
            hint: _docType == 'nrc'
                ? 'Front side of your NRC. All text and the photo must be readable.'
                : 'The page with your photo. All text must be readable.',
            onCamera: () async {
              final p = await _capture(selfie: false);
              if (p != null) setState(() => _doc = p);
            },
            onGallery: () async {
              final p = await _capture(selfie: false, source: ImageSource.gallery);
              if (p != null) setState(() => _doc = p);
            },
          ),
          const SizedBox(height: 22),

          // 3. селфи
          const _Label('3. A selfie'),
          _PhotoBox(
            photo: _selfie,
            icon: ZI.user,
            hint: 'Your face clearly visible, no sunglasses or hat. We compare it with the photo on your ID.',
            onCamera: () async {
              final p = await _capture(selfie: true);
              if (p != null) setState(() => _selfie = p);
            },
          ),
          const SizedBox(height: 22),

          // 4. согласие (Data Protection Act, 2021)
          InkWell(
            onTap: () => setState(() => _consent = !_consent),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Checkbox(
                value: _consent,
                activeColor: Zc.green,
                onChanged: (v) => setState(() => _consent = v ?? false),
              ),
              const Expanded(
                child: Padding(
                  padding: EdgeInsets.only(top: 12),
                  child: Text(
                    'I agree that Zumi processes these photos only to verify my identity. They are stored '
                    'privately, never shown to other users, and deleted after the check (Data Protection Act, 2021).',
                    style: TextStyle(fontSize: 13, height: 1.4),
                  ),
                ),
              ),
            ]),
          ),
          const SizedBox(height: 20),
          PrimaryButton(label: 'Send for check', width: double.infinity, loading: _sending, onPressed: _send),
        ],
      ),
    );
  }
}

class _Label extends StatelessWidget {
  const _Label(this.text);
  final String text;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: Text(text, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w600)),
      );
}

class _PhotoBox extends StatelessWidget {
  const _PhotoBox({required this.photo, required this.icon, required this.hint, required this.onCamera, this.onGallery});
  final PickedPhoto? photo;
  final IconData icon;
  final String hint;
  final VoidCallback onCamera;
  final VoidCallback? onGallery;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: photo != null ? const Color(0x552E9E5B) : Zc.lightGrey),
      ),
      child: Row(children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(10),
          child: SizedBox(
            width: 84,
            height: 84,
            child: photo != null
                ? Image.memory(photo!.bytes, fit: BoxFit.cover)
                : ColoredBox(color: Zc.chip, child: Icon(icon, color: Zc.green, size: 34)),
          ),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(hint, style: const TextStyle(fontSize: 13, color: Zc.grey, height: 1.35)),
            const SizedBox(height: 8),
            Wrap(spacing: 8, runSpacing: 6, children: [
              TextButton.icon(
                style: TextButton.styleFrom(
                  backgroundColor: photo == null ? Zc.orange : Zc.chip,
                  foregroundColor: photo == null ? Colors.white : Zc.green,
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                ),
                onPressed: onCamera,
                icon: const Icon(ZI.camera, size: 18),
                label: Text(photo == null ? 'Take photo' : 'Retake'),
              ),
              if (onGallery != null)
                TextButton(
                  onPressed: onGallery,
                  child: const Text('Upload', style: TextStyle(color: Zc.green)),
                ),
            ]),
          ]),
        ),
      ]),
    );
  }
}
