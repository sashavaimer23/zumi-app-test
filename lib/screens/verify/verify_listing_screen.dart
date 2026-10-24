import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';

import '../../models/models.dart';
import '../../state/app_state.dart';
import '../../theme.dart';
import '../../widgets/common.dart';
import '../../widgets/trust.dart';
import '../../widgets/zicons.dart';
import 'get_verified_screen.dart';

/// «Сделайте недвижимость проверенной» — три добровольных шага.
class VerifyListingScreen extends StatefulWidget {
  const VerifyListingScreen({super.key, required this.property});
  final Property property;

  @override
  State<VerifyListingScreen> createState() => _VerifyListingScreenState();
}

class _VerifyListingScreenState extends State<VerifyListingScreen> {
  Property get p => widget.property;

  // Property Verified
  final List<PickedPhoto> _photos = [];
  bool _checking = false;
  bool _propertyDone = false;
  String? _checkMessage;

  // статусы заявок с документами
  late Future<List<String?>> _statuses;

  @override
  void initState() {
    super.initState();
    _propertyDone = p.propertyVerified;
    _loadStatuses();
  }

  void _loadStatuses() {
    final repo = context.read<AppState>().repo;
    _statuses = Future.wait([
      repo.verificationStatus(kind: 'identity'),
      repo.verificationStatus(kind: 'ownership', propertyId: p.id),
    ]);
  }

  // ---------------- фото на месте ----------------
  Future<void> _takePhoto() async {
    try {
      final f = await ImagePicker().pickImage(
        source: ImageSource.camera,
        imageQuality: 75,
        maxWidth: 1600,
        maxHeight: 1600,
      );
      if (f == null) return;
      final bytes = await f.readAsBytes();
      if (bytes.lengthInBytes > kMaxDocBytes) {
        if (mounted) showSnack(context, 'This photo is larger than 10 MB. Please take it again.');
        return;
      }
      _photos.add(PickedPhoto(f.name, bytes));
      if (mounted) setState(() {});
    } catch (e) {
      if (mounted) showSnack(context, 'Could not open the camera: $e');
    }
  }

  // ---------------- геолокация + проверка ----------------
  Future<Position?> _location() async {
    if (!await Geolocator.isLocationServiceEnabled()) {
      if (mounted) showSnack(context, 'Please turn on location services');
      return null;
    }
    var perm = await Geolocator.checkPermission();
    if (perm == LocationPermission.denied) perm = await Geolocator.requestPermission();
    if (perm == LocationPermission.denied || perm == LocationPermission.deniedForever) {
      if (mounted) showSnack(context, 'Zumi needs your location to confirm you are at the property');
      return null;
    }
    return Geolocator.getCurrentPosition(
      locationSettings: const LocationSettings(accuracy: LocationAccuracy.high),
    );
  }

  Future<void> _checkProperty() async {
    if (_photos.length < 3) {
      showSnack(context, 'Take at least 3 photos at the property first');
      return;
    }
    setState(() {
      _checking = true;
      _checkMessage = null;
    });
    final app = context.read<AppState>();
    try {
      final pos = await _location();
      if (pos == null) return;
      final r = await app.repo.submitPropertyCheck(p.id, _photos, pos.latitude, pos.longitude);
      if (!mounted) return;
      setState(() {
        _propertyDone = r.verified;
        _checkMessage = r.verified
            ? 'Done! Your listing now shows the Verified badge.'
            : 'You seem to be ${_km(r.distanceM)} away from the pin on the map. '
                'Please do the check at the property, or fix the pin in your listing.';
      });
      if (r.verified) app.dataChanged();
    } catch (e) {
      if (mounted) showSnack(context, '$e');
    } finally {
      if (mounted) setState(() => _checking = false);
    }
  }

  String _km(int m) => m >= 1000 ? '${(m / 1000).toStringAsFixed(1)} km' : '$m m';

  // ---------------- UI ----------------
  @override
  Widget build(BuildContext context) {
    final user = context.watch<AppState>().user;
    final isAgent = user?.isAgent ?? false;

    return Scaffold(
      appBar: AppBar(title: const Text('Verification')),
      body: FutureBuilder<List<String?>>(
        future: _statuses,
        builder: (context, snap) {
          final ownStatus = snap.data?[1];
          return ListView(
            padding: const EdgeInsets.fromLTRB(22, 8, 22, 40),
            children: [
              Text('Verification', style: zHeadline(context, size: 30)),
              const SizedBox(height: 8),
              const Text(
                'The Verified badge comes from checking you as a person. Confirming the location and '
                'ownership is optional, but gives buyers and tenants even more confidence.',
                style: TextStyle(color: Zc.grey, fontSize: 15, height: 1.4),
              ),
              const SizedBox(height: 18),
              _ListingMini(p: p),
              const SizedBox(height: 10),

              // ---- Плашка Verified — от проверки личности автора
              _Step(
                level: VerificationLevel.identity,
                done: user?.identityVerified ?? false,
                children: [
                  _SubRow(
                    icon: ZI.verified,
                    title: 'Verified badge',
                    status: (user?.identityVerified ?? false)
                        ? 'Shown on all your listings'
                        : 'Confirm phone and ID once — about 3 minutes',
                    done: user?.identityVerified ?? false,
                    action: (user?.identityVerified ?? false)
                        ? null
                        : () => Navigator.push(
                            context, MaterialPageRoute(builder: (_) => const GetVerifiedScreen())),
                    actionLabel: 'Get verified',
                  ),
                ],
              ),
              const Padding(
                padding: EdgeInsets.only(top: 22, bottom: 2),
                child: Text('Extra trust — optional',
                    style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600, color: Zc.green)),
              ),

              // ---- 2. Property
              _Step(
                level: VerificationLevel.property,
                done: _propertyDone,
                children: _propertyDone
                    ? [
                        if (_checkMessage != null)
                          Text(_checkMessage!, style: const TextStyle(color: Zc.green, fontSize: 14)),
                      ]
                    : [
                        const Text(
                          'Go to the property, take 3 photos with your camera, then tap “Check my location”. '
                          'Your phone must be within 300 m of the pin on the map.',
                          style: TextStyle(fontSize: 14, height: 1.4),
                        ),
                        const SizedBox(height: 12),
                        if (_photos.isNotEmpty) ...[
                          PhotoThumbs(
                            photos: _photos,
                            size: 70,
                            onRemove: (i) => setState(() => _photos.removeAt(i)),
                          ),
                          const SizedBox(height: 12),
                        ],
                        Wrap(spacing: 10, runSpacing: 10, children: [
                          _SmallBtn(
                            icon: ZI.camera,
                            label: _photos.isEmpty ? 'Take photos' : 'Take another (${_photos.length}/3)',
                            onTap: _takePhoto,
                            filled: _photos.length < 3,
                          ),
                          _SmallBtn(
                            icon: ZI.location,
                            label: _checking ? 'Checking…' : 'Check my location',
                            onTap: _checking ? null : _checkProperty,
                            filled: _photos.length >= 3,
                          ),
                        ]),
                        if (_checkMessage != null) ...[
                          const SizedBox(height: 10),
                          Text(_checkMessage!, style: const TextStyle(color: Zc.orange, fontSize: 14, height: 1.4)),
                        ],
                      ],
              ),

              // ---- 3. Ownership
              _Step(
                level: VerificationLevel.ownership,
                done: p.ownershipVerified || ownStatus == 'approved',
                children: [
                  _SubRow(
                    icon: ZI.fileText,
                    title: isAgent ? 'Owner\'s authorization' : 'Title deed or lease',
                    status: _statusText(p.ownershipVerified ? 'approved' : ownStatus),
                    done: p.ownershipVerified || ownStatus == 'approved',
                    action: p.ownershipVerified || ownStatus == 'approved' || ownStatus == 'pending'
                        ? null
                        : () async {
                            final sent = await showDocumentsSheet(
                              context,
                              kind: 'ownership',
                              property: p,
                              isAgent: isAgent,
                            );
                            if (sent == true && mounted) setState(_loadStatuses);
                          },
                    actionLabel: 'Upload',
                  ),
                ],
              ),
              const SizedBox(height: 26),
              PrimaryButton(label: 'Done', width: double.infinity, onPressed: () => Navigator.pop(context)),
            ],
          );
        },
      ),
    );
  }

  String _statusText(String? s) => switch (s) {
        'approved' => 'Verified',
        'pending' => 'Under review — 1–2 working days',
        'rejected' => 'Not approved — please upload again',
        _ => 'Not verified',
      };
}

class _Step extends StatelessWidget {
  const _Step({required this.level, required this.done, required this.children});
  final VerificationLevel level;
  final bool done;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(top: 14),
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: done ? const Color(0x552E9E5B) : Zc.chip),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        VerificationRow(level: level, done: done, showDivider: children.isNotEmpty),
        if (children.isNotEmpty) const SizedBox(height: 12),
        ...children,
      ]),
    );
  }
}

class _SubRow extends StatelessWidget {
  const _SubRow({
    required this.icon,
    required this.title,
    required this.status,
    required this.done,
    required this.action,
    required this.actionLabel,
  });
  final IconData icon;
  final String title;
  final String status;
  final bool done;
  final VoidCallback? action;
  final String actionLabel;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(children: [
        Icon(icon, color: Zc.green, size: 22),
        const SizedBox(width: 12),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(title, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w500)),
            Text(status, style: TextStyle(fontSize: 13, color: done ? const Color(0xFF2E9E5B) : Zc.grey)),
          ]),
        ),
        if (action != null) _SmallBtn(label: actionLabel, onTap: action, filled: true),
        if (done) const Icon(ZI.verified, color: Color(0xFF2E9E5B), size: 22),
      ]),
    );
  }
}

class _SmallBtn extends StatelessWidget {
  const _SmallBtn({this.icon, required this.label, required this.onTap, this.filled = false});
  final IconData? icon;
  final String label;
  final VoidCallback? onTap;
  final bool filled;

  @override
  Widget build(BuildContext context) {
    final fg = filled ? Colors.white : Zc.green;
    return Material(
      color: filled ? Zc.orange : const Color(0xFFE9EFEE),
      borderRadius: BorderRadius.circular(18),
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            if (icon != null) ...[Icon(icon, size: 18, color: fg), const SizedBox(width: 6)],
            Text(label, style: TextStyle(color: fg, fontSize: 14)),
          ]),
        ),
      ),
    );
  }
}

class _ListingMini extends StatelessWidget {
  const _ListingMini({required this.p});
  final Property p;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(color: Zc.chip, borderRadius: BorderRadius.circular(14)),
      child: Row(children: [
        SizedBox(width: 64, height: 64, child: PropImage(p.cover, radius: 10)),
        const SizedBox(width: 12),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(p.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w600)),
            Text(p.locationLine, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Zc.grey, fontSize: 13)),
          ]),
        ),
      ]),
    );
  }
}
