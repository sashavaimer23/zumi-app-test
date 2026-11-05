import 'package:flutter/material.dart';

import '../theme.dart';
import 'zicons.dart';

/// Круглая кнопка «наверх»: появляется, когда пролистали далеко вниз,
/// по нажатию плавно возвращает в начало. Оборачивает любой экран с прокруткой —
/// слушает вертикальную прокрутку верхнего уровня (горизонтальные ленты не считаются).
class BackToTop extends StatefulWidget {
  const BackToTop({super.key, required this.child, this.bottom = 24, this.right = 16});
  final Widget child;

  /// отступ снизу — чтобы не закрывать меню, кнопку «Map» и кнопки связи
  final double bottom;
  final double right;

  @override
  State<BackToTop> createState() => _BackToTopState();
}

class _BackToTopState extends State<BackToTop> {
  ScrollPosition? _position;
  bool _show = false;

  bool _onScroll(ScrollNotification n) {
    if (n.depth != 0 || n.metrics.axis != Axis.vertical) return false;
    final ctx = n.context;
    if (ctx != null) _position = Scrollable.maybeOf(ctx)?.position ?? _position;
    // показываем после полутора экранов прокрутки
    final show = n.metrics.pixels > n.metrics.viewportDimension * 1.5;
    if (show != _show) setState(() => _show = show);
    return false;
  }

  void _toTop() {
    final p = _position;
    if (p == null || !p.hasPixels) return;
    final far = p.pixels > p.viewportDimension * 6;
    if (far) p.jumpTo(p.viewportDimension * 1.2); // очень далеко — сначала почти наверх, потом плавно
    p.animateTo(0, duration: const Duration(milliseconds: 450), curve: Curves.easeOutCubic);
  }

  @override
  Widget build(BuildContext context) {
    return Stack(children: [
      NotificationListener<ScrollNotification>(onNotification: _onScroll, child: widget.child),
      Positioned(
        right: widget.right,
        bottom: widget.bottom + MediaQuery.paddingOf(context).bottom,
        child: IgnorePointer(
          ignoring: !_show,
          child: AnimatedScale(
            scale: _show ? 1 : 0.6,
            duration: const Duration(milliseconds: 180),
            child: AnimatedOpacity(
              opacity: _show ? 1 : 0,
              duration: const Duration(milliseconds: 180),
              child: Tooltip(
                message: 'Back to top',
                child: Material(
                  color: Colors.white,
                  shape: const CircleBorder(),
                  elevation: 4,
                  shadowColor: Colors.black26,
                  child: InkWell(
                    customBorder: const CircleBorder(),
                    onTap: _toTop,
                    child: const SizedBox(
                      width: 46,
                      height: 46,
                      child: Icon(ZI.arrowUp, color: Zc.green, size: 22),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    ]);
  }
}
