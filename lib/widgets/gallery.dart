import 'package:flutter/material.dart';

import '../theme.dart';
import 'common.dart';
import 'zicons.dart';

/// Галерея объявления для компьютера: большое фото слева + 3 фото справа (как у крупных порталов).
/// По клику открывается полноэкранный просмотр.
class DesktopGallery extends StatelessWidget {
  const DesktopGallery({super.key, required this.images, this.badges = const [], this.height = 520});
  final List<String?> images;
  final List<Widget> badges;
  final double height;

  void _open(BuildContext context, int i) => openGalleryViewer(context, images, i);

  @override
  Widget build(BuildContext context) {
    final side = images.length > 1 ? images.sublist(1).take(3).toList() : <String?>[];
    final more = images.length - 1 - side.length;

    Widget tile(String? url, int index, {Widget? overlay}) => GestureDetector(
          onTap: () => _open(context, index),
          child: MouseRegion(
            cursor: SystemMouseCursors.zoomIn,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(14),
              child: Stack(fit: StackFit.expand, children: [
                PropImage(url),
                if (overlay != null) overlay,
              ]),
            ),
          ),
        );

    return SizedBox(
      height: height,
      child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Expanded(
          flex: side.isEmpty ? 1 : 71,
          child: tile(
            images.first,
            0,
            overlay: Positioned(top: 16, left: 16, child: Row(mainAxisSize: MainAxisSize.min, children: badges)),
          ),
        ),
        if (side.isNotEmpty) ...[
          const SizedBox(width: 10),
          Expanded(
            flex: 29,
            child: Column(children: [
              for (var i = 0; i < 3; i++) ...[
                if (i > 0) const SizedBox(height: 10),
                Expanded(
                  child: i < side.length
                      ? tile(
                          side[i],
                          i + 1,
                          overlay: i == side.length - 1
                              ? Positioned(
                                  right: 12,
                                  bottom: 12,
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                                    decoration: BoxDecoration(
                                      color: const Color(0x99000000),
                                      borderRadius: BorderRadius.circular(18),
                                    ),
                                    child: Row(mainAxisSize: MainAxisSize.min, children: [
                                      const Icon(ZI.camera, color: Colors.white, size: 16),
                                      const SizedBox(width: 6),
                                      Text(more > 0 ? '+$more · ${images.length}' : '${images.length}',
                                          style: const TextStyle(color: Colors.white, fontSize: 13)),
                                    ]),
                                  ),
                                )
                              : null,
                        )
                      : ClipRRect(
                          borderRadius: BorderRadius.circular(14),
                          child: const ColoredBox(color: Zc.chip),
                        ),
                ),
              ],
            ]),
          ),
        ],
      ]),
    );
  }
}

/// Полноэкранный просмотр фото: листание, увеличение, стрелки
void openGalleryViewer(BuildContext context, List<String?> images, int initial) {
  Navigator.of(context).push(PageRouteBuilder(
    opaque: false,
    barrierColor: Colors.black,
    pageBuilder: (_, __, ___) => _GalleryViewer(images: images, initial: initial),
    transitionsBuilder: (_, a, __, child) => FadeTransition(opacity: a, child: child),
  ));
}

class _GalleryViewer extends StatefulWidget {
  const _GalleryViewer({required this.images, required this.initial});
  final List<String?> images;
  final int initial;

  @override
  State<_GalleryViewer> createState() => _GalleryViewerState();
}

class _GalleryViewerState extends State<_GalleryViewer> {
  late final _ctrl = PageController(initialPage: widget.initial);
  late int _i = widget.initial;

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  void _go(int d) {
    final n = (_i + d).clamp(0, widget.images.length - 1);
    _ctrl.animateToPage(n, duration: const Duration(milliseconds: 250), curve: Curves.easeOut);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(children: [
        PageView.builder(
          controller: _ctrl,
          itemCount: widget.images.length,
          onPageChanged: (i) => setState(() => _i = i),
          itemBuilder: (_, i) => InteractiveViewer(
            minScale: 1,
            maxScale: 4,
            child: Center(child: PropImage(widget.images[i], fit: BoxFit.contain)),
          ),
        ),
        SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Row(children: [
              Text('${_i + 1} / ${widget.images.length}', style: const TextStyle(color: Colors.white, fontSize: 15)),
              const Spacer(),
              IconButton(
                onPressed: () => Navigator.pop(context),
                icon: const Icon(ZI.close, color: Colors.white, size: 28),
              ),
            ]),
          ),
        ),
        if (_i > 0)
          Align(
            alignment: Alignment.centerLeft,
            child: _Arrow(icon: ZI.back, onTap: () => _go(-1)),
          ),
        if (_i < widget.images.length - 1)
          Align(
            alignment: Alignment.centerRight,
            child: _Arrow(icon: ZI.forward, onTap: () => _go(1)),
          ),
      ]),
    );
  }
}

class _Arrow extends StatelessWidget {
  const _Arrow({required this.icon, required this.onTap});
  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.all(16),
        child: Material(
          color: const Color(0x33FFFFFF),
          shape: const CircleBorder(),
          child: InkWell(
            customBorder: const CircleBorder(),
            onTap: onTap,
            child: Padding(padding: const EdgeInsets.all(12), child: Icon(icon, color: Colors.white, size: 26)),
          ),
        ),
      );
}
