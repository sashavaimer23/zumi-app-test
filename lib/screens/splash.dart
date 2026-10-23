import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../theme.dart';
import '../widgets/common.dart';

/// Заставка при запуске приложения:
/// 1) просто зелёный фон; 2) снизу «вырастает» светлый лист логотипа;
/// 3) сверху на него опускается оранжевая крыша и пружинит;
/// 4) расходится мягкая волна, по одной выпрыгивают буквы Z U M I;
/// 5) появляется слоган; 6) заставка растворяется и открывается главная.
/// Пока идёт заставка, главная уже загружается под ней.
class SplashGate extends StatefulWidget {
  const SplashGate({super.key, required this.child});
  final Widget child;

  @override
  State<SplashGate> createState() => _SplashGateState();
}

class _SplashGateState extends State<SplashGate> with SingleTickerProviderStateMixin {
  late final AnimationController _c =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 3300));
  bool _done = false;

  @override
  void initState() {
    super.initState();
    _c.addStatusListener((s) {
      if (s == AnimationStatus.completed && mounted) setState(() => _done = true);
    });
    _c.forward();
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Stack(children: [
      widget.child,
      if (!_done)
        Positioned.fill(
          child: AnnotatedRegion<SystemUiOverlayStyle>(
            value: SystemUiOverlayStyle.light,
            child: AnimatedBuilder(animation: _c, builder: (context, _) => _SplashView(t: _c.value)),
          ),
        ),
    ]);
  }
}

/// Отрезок анимации [a..b] → 0..1 с нужной кривой
double _iv(double t, double a, double b, [Curve curve = Curves.linear]) =>
    curve.transform(((t - a) / (b - a)).clamp(0.0, 1.0));

class _SplashView extends StatelessWidget {
  const _SplashView({required this.t});
  final double t;

  static const _tagline1 = 'EVERY KEY HAS A STORY.';
  static const _tagline2 = 'START YOURS.';

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    final logoW = (size.shortestSide * 0.27).clamp(84.0, 130.0);

    final leaf = _iv(t, 0.10, 0.32, const ElasticOutCurve(0.55));
    final roof = _iv(t, 0.24, 0.46, const ElasticOutCurve(0.5));
    final bump = _iv(t, 0.36, 0.48); // логотип «приседает», когда крыша встаёт на место
    final ring = _iv(t, 0.40, 0.66, Curves.easeOut);
    final exit = _iv(t, 0.88, 1.0, Curves.easeInCubic);

    final squash = math.sin(bump * math.pi) * 0.07;

    return Opacity(
      opacity: 1 - exit,
      // Material — чтобы у текста был правильный стиль (заставка лежит над навигатором)
      child: Material(
        color: Zc.splash,
        child: Stack(children: [
          // логотип + ZUMI по центру
          Center(
            child: Transform.scale(
              scale: 1 + exit * 0.18,
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                SizedBox(
                  width: logoW * 2.2,
                  height: logoW * 2.2 * 0.8,
                  child: Stack(alignment: Alignment.center, children: [
                    // мягкая волна от логотипа
                    if (ring > 0 && ring < 1)
                      Container(
                        width: logoW * (1.0 + ring * 1.1),
                        height: logoW * (1.0 + ring * 1.1),
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: Zc.cream.withAlpha((90 * (1 - ring)).round()),
                            width: 2 + 6 * (1 - ring),
                          ),
                        ),
                      ),
                    Transform(
                      alignment: Alignment.bottomCenter,
                      transform: Matrix4.diagonal3Values(1 + squash, 1 - squash, 1),
                      child: SizedBox(
                        width: logoW,
                        height: logoW * 0.8,
                        child: CustomPaint(painter: _LogoBuildPainter(leaf: leaf, roof: roof)),
                      ),
                    ),
                  ]),
                ),
                const SizedBox(height: 6),
                _Letters(t: t),
              ]),
            ),
          ),
          // слоган внизу
          Positioned(
            left: 24,
            right: 24,
            bottom: MediaQuery.paddingOf(context).bottom + size.height * 0.08,
            child: Column(children: [
              _TaglineLine(text: _tagline1, p: _iv(t, 0.60, 0.76, Curves.easeOutCubic)),
              const SizedBox(height: 6),
              _TaglineLine(text: _tagline2, p: _iv(t, 0.68, 0.84, Curves.easeOutCubic)),
            ]),
          ),
        ]),
      ),
    );
  }
}

/// Буквы Z U M I по одной: подпрыгивают снизу
class _Letters extends StatelessWidget {
  const _Letters({required this.t});
  final double t;

  @override
  Widget build(BuildContext context) {
    const letters = ['Z', 'U', 'M', 'I'];
    final style = zBrand(const TextStyle(
      fontSize: 38,
      fontWeight: FontWeight.w600,
      color: Zc.cream,
      height: 1,
    ));
    return Row(mainAxisSize: MainAxisSize.min, children: [
      for (var i = 0; i < letters.length; i++)
        Builder(builder: (_) {
          final start = 0.44 + i * 0.045;
          final p = _iv(t, start, start + 0.16, Curves.easeOutBack);
          final fade = _iv(t, start, start + 0.08);
          return Padding(
            padding: const EdgeInsets.symmetric(horizontal: 9),
            child: Opacity(
              opacity: fade,
              child: Transform.translate(
                offset: Offset(0, (1 - p) * 26),
                child: Transform.rotate(angle: (1 - p) * (i.isEven ? -0.25 : 0.25), child: Text(letters[i], style: style)),
              ),
            ),
          );
        }),
    ]);
  }
}

class _TaglineLine extends StatelessWidget {
  const _TaglineLine({required this.text, required this.p});
  final String text;
  final double p;

  @override
  Widget build(BuildContext context) {
    return Opacity(
      opacity: p,
      child: Transform.translate(
        offset: Offset(0, (1 - p) * 12),
        child: Text(
          text,
          textAlign: TextAlign.center,
          style: zBrand(TextStyle(
            fontSize: 15,
            color: Zc.cream,
            fontWeight: FontWeight.w400,
            // буквы чуть «съезжаются», пока строка появляется
            letterSpacing: 2.2 + (1 - p) * 3,
          )),
        ),
      ),
    );
  }
}

/// Логотип по частям: лист растёт снизу, крыша опускается на него сверху
class _LogoBuildPainter extends CustomPainter {
  _LogoBuildPainter({required this.leaf, required this.roof});
  final double leaf; // 0..1 (с отскоком чуть больше 1)
  final double roof;

  @override
  void paint(Canvas canvas, Size s) {
    final (left, right) = zumiLogoPaths(s);

    if (leaf > 0) {
      canvas.save();
      // растёт от нижнего края
      final pivot = Offset(s.width * 0.185, s.height);
      canvas.translate(pivot.dx, pivot.dy + (1 - leaf.clamp(0.0, 1.0)) * s.height * 0.35);
      canvas.scale(1, leaf.clamp(0.0, 1.3));
      canvas.translate(-pivot.dx, -pivot.dy);
      canvas.drawPath(left, Paint()..color = Zc.cream);
      canvas.restore();
    }

    if (roof > 0) {
      canvas.save();
      // крыша «на петле» у верхушки листа: поворачивается и опускается на место
      final hinge = Offset(s.width * 0.40, s.height * 0.10);
      canvas.translate(hinge.dx, hinge.dy - (1 - roof) * s.height * 0.5);
      canvas.rotate((1 - roof) * -0.95);
      canvas.translate(-hinge.dx, -hinge.dy);
      final a = (roof * 3).clamp(0.0, 1.0);
      canvas.drawPath(right, Paint()..color = Zc.orange.withAlpha((255 * a).round()));
      canvas.restore();
    }
  }

  @override
  bool shouldRepaint(_LogoBuildPainter old) => old.leaf != leaf || old.roof != roof;
}
