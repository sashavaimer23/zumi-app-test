import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../../theme.dart';
import '../../widgets/promo_card.dart';

/// Выбор части картинки в рамке 3:2: двигать пальцем, увеличивать щипком или ползунком.
/// Возвращает доли (left, top, width, height) от исходной картинки.
Future<(double, double, double, double)?> showBannerCrop(
  BuildContext context, {
  required Uint8List bytes,
  required int width,
  required int height,
  String? message,
  double ratio = kPromoRatio,
}) {
  return showDialog<(double, double, double, double)>(
    context: context,
    barrierDismissible: false,
    builder: (_) => _CropDialog(bytes: bytes, iw: width, ih: height, message: message, ratio: ratio),
  );
}

class _CropDialog extends StatefulWidget {
  const _CropDialog({required this.bytes, required this.iw, required this.ih, this.message, required this.ratio});
  final double ratio;
  final Uint8List bytes;
  final int iw;
  final int ih;
  final String? message;

  @override
  State<_CropDialog> createState() => _CropDialogState();
}

class _CropDialogState extends State<_CropDialog> {
  final _ctrl = TransformationController();
  double _vw = 0; // размер рамки
  double _base = 1; // масштаб «картинка закрывает рамку»
  bool _centered = false;

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  double get _zoom => _ctrl.value.getMaxScaleOnAxis();

  /// Какая часть картинки сейчас в рамке (доли 0..1)
  (double, double, double, double) _cropFractions() {
    final vh = _vw / widget.ratio;
    final tl = _ctrl.toScene(Offset.zero);
    final br = _ctrl.toScene(Offset(_vw, vh));
    final cw = widget.iw * _base, ch = widget.ih * _base;
    final l = (tl.dx / cw).clamp(0.0, 1.0);
    final t = (tl.dy / ch).clamp(0.0, 1.0);
    final r = (br.dx / cw).clamp(0.0, 1.0);
    final b = (br.dy / ch).clamp(0.0, 1.0);
    return (l, t, r - l, b - t);
  }

  /// Хватит ли пикселей, чтобы баннер был чётким
  bool get _sharpEnough {
    final (_, _, w, _) = _cropFractions();
    return w * widget.iw >= 800; // после увеличения кадр должен остаться достаточно крупным
  }

  @override
  Widget build(BuildContext context) {
    final screenW = MediaQuery.sizeOf(context).width;
    _vw = math.min(560.0, screenW - 80);
    final vh = _vw / widget.ratio;
    _base = math.max(_vw / widget.iw, vh / widget.ih);
    final cw = widget.iw * _base, ch = widget.ih * _base;
    if (!_centered) {
      _centered = true;
      _ctrl.value = Matrix4.identity()..translateByDouble(-(cw - _vw) / 2, -(ch - vh) / 2, 0, 1);
    }

    return AlertDialog(
      title: const Text('Choose the part to show'),
      content: SizedBox(
        width: _vw,
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          if (widget.message != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Text(widget.message!, style: const TextStyle(fontSize: 13, color: Zc.grey, height: 1.35)),
            ),
          ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: SizedBox(
              width: _vw,
              height: vh,
              child: Stack(children: [
                InteractiveViewer(
                  transformationController: _ctrl,
                  constrained: false,
                  minScale: 1,
                  maxScale: 4,
                  boundaryMargin: EdgeInsets.zero,
                  onInteractionEnd: (_) => setState(() {}),
                  child: SizedBox(width: cw, height: ch, child: Image.memory(widget.bytes, fit: BoxFit.fill)),
                ),
                // сетка «третей» — помогает выбрать кадр
                IgnorePointer(child: CustomPaint(size: Size(_vw, vh), painter: _GridPainter())),
              ]),
            ),
          ),
          const SizedBox(height: 8),
          Row(children: [
            const Icon(Icons.zoom_out, size: 18, color: Zc.grey),
            Expanded(
              child: Slider(
                value: _zoom.clamp(1.0, 4.0),
                min: 1,
                max: 4,
                activeColor: Zc.orange,
                onChanged: (z) => setState(() {
                  // увеличиваем относительно центра рамки
                  final center = _ctrl.toScene(Offset(_vw / 2, vh / 2));
                  _ctrl.value = Matrix4.identity()
                    ..translateByDouble(_vw / 2, vh / 2, 0, 1)
                    ..scaleByDouble(z, z, z, 1)
                    ..translateByDouble(-center.dx, -center.dy, 0, 1);
                }),
              ),
            ),
            const Icon(Icons.zoom_in, size: 18, color: Zc.grey),
          ]),
          Text(
            _sharpEnough
                ? 'Drag to move, pinch or use the slider to zoom.'
                : 'Zoomed in too far — the banner may look blurry.',
            style: TextStyle(fontSize: 12, color: _sharpEnough ? Zc.grey : const Color(0xFFD64545)),
          ),
        ]),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
        FilledButton(
          style: FilledButton.styleFrom(backgroundColor: Zc.orange),
          onPressed: () => Navigator.pop(context, _cropFractions()),
          child: const Text('Use this part'),
        ),
      ],
    );
  }
}

class _GridPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size s) {
    final p = Paint()
      ..color = const Color(0x88FFFFFF)
      ..strokeWidth = 1;
    for (final f in [1 / 3, 2 / 3]) {
      canvas.drawLine(Offset(s.width * f, 0), Offset(s.width * f, s.height), p);
      canvas.drawLine(Offset(0, s.height * f), Offset(s.width, s.height * f), p);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
