import 'dart:math' as math;
import 'dart:ui' show lerpDouble;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';


/// Анимация «Объявление опубликовано»:
/// 1) появляется дом, 2) сзади снизу пружинисто выезжает круг,
/// 3) из-за дома вылетают конфетти и падают, 4) выскакивает значок с галочкой,
/// которая рисуется, и от него разлетаются «лучики».
/// Играет один раз сам при появлении экрана, потом картинка остаётся статичной.
///
/// Все координаты — в системе исходной иллюстрации 1291×966 (success.jpg).
class ListingLiveHero extends StatefulWidget {
  const ListingLiveHero({super.key, this.maxWidth = 440});
  final double maxWidth;

  @override
  State<ListingLiveHero> createState() => _ListingLiveHeroState();
}

const double _W = 1291, _H = 966;
// дом вшит в код (WebP), поэтому грузится мгновенно и без файлов
// отдельным файлом, а не внутри кода: так основная часть сайта легче на ~200 КБ
const _house = AssetImage('assets/images/success_house.webp');

/// Загрузить картинку заранее (вызывается, когда человек открывает мастер)
void precacheSuccessHero(BuildContext context) => precacheImage(_house, context).catchError((_) {});
const _houseRect = Rect.fromLTWH(9, 384, 1272, 571); // где дом лежит на иллюстрации

const _peach = Color(0xFFFEEACE);
const _badgeGreen = Color(0xFF034A3C);
const _checkWhite = Color(0xFFFDFBF7);
const _badgeC = Offset(646, 245);
const double _badgeR = 133;

// Таймлайн (доли от общей длительности)
const _tHouse = (0.00, 0.20);
const _tCircle = (0.14, 0.46);
const _tConfetti = 0.34; // старт залпа
const _tBadge = (0.56, 0.76);
const _tRing = (0.60, 0.86);
const _tCheck = (0.64, 0.78);
const _tRays = 0.70;
const _durationMs = 3000;

double _iv(double t, (double, double) r, [Curve curve = Curves.linear]) {
  final v = ((t - r.$1) / (r.$2 - r.$1)).clamp(0.0, 1.0);
  return curve.transform(v);
}

// все цвета тут непрозрачные, поэтому просто задаём прозрачность 0..255
Color _a(Color c, double o) => c.withAlpha((255 * o.clamp(0.0, 1.0)).round());

class _ListingLiveHeroState extends State<ListingLiveHero> with SingleTickerProviderStateMixin {
  late final AnimationController _c =
      AnimationController(vsync: this, duration: const Duration(milliseconds: _durationMs));
  final _particles = _Particle.burst(38, 7);
  bool _started = false;
  bool _buzzed = false;

  @override
  void initState() {
    super.initState();
    _c.addListener(() {
      if (!_buzzed && _c.value >= _tBadge.$1) {
        _buzzed = true;
        HapticFeedback.mediumImpact();
      }
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started) return;
    _started = true;
    _start();
  }

  /// Запуск один раз: ждём, пока экран выедет и картинка дома будет готова
  /// (но не дольше секунды), затем играем анимацию.
  Future<void> _start() async {
    final ready = precacheImage(_house, context).catchError((_) {});
    await Future.wait([
      ready.timeout(const Duration(milliseconds: 1000), onTimeout: () {}),
      Future<void>.delayed(const Duration(milliseconds: 280)),
    ]);
    if (mounted) _c.forward(from: 0);
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Center(
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: widget.maxWidth),
        child: AspectRatio(
          aspectRatio: _W / _H,
          child: IgnorePointer(
            child: LayoutBuilder(builder: (context, box) {
              final s = box.maxWidth / _W;
              return AnimatedBuilder(
                animation: _c,
                builder: (context, _) {
                  final t = _c.value;
                  final pop = _iv(t, _tHouse, Curves.easeOutBack);
                  final fade = _iv(t, (_tHouse.$1, _tHouse.$2 * 0.6));
                  return Stack(clipBehavior: Clip.none, children: [
                    // круг, взлетающие конфетти, значок, лучики — позади дома
                    Positioned.fill(child: CustomPaint(painter: _BackPainter(t, s, _particles))),
                    // дом
                    Positioned(
                      left: _houseRect.left * s,
                      top: _houseRect.top * s,
                      width: _houseRect.width * s,
                      height: _houseRect.height * s,
                      child: Opacity(
                        opacity: fade,
                        child: Transform.translate(
                          offset: Offset(0, (1 - pop) * 50 * s),
                          child: Transform.scale(
                            scale: 0.84 + 0.16 * pop,
                            alignment: Alignment.bottomCenter,
                            child: Image(image: _house, fit: BoxFit.fill, gaplessPlayback: true),
                          ),
                        ),
                      ),
                    ),
                    // падающие конфетти — уже перед домом
                    Positioned.fill(
                      child: IgnorePointer(child: CustomPaint(painter: _FrontPainter(t, s, _particles))),
                    ),
                  ]);
                },
              );
            }),
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Конфетти: вылетают вверх из-за крыши (рисуются позади дома), после верхней точки
// падают уже перед домом. Переход незаметен — верхняя точка всегда выше крыши.

class _Particle {
  _Particle({
    required this.x0,
    required this.vx,
    required this.vy,
    required this.delay,
    required this.rot,
    required this.spin,
    required this.flip,
    required this.phase,
    required this.len,
    required this.thick,
    required this.color,
  });

  final double x0, vx, vy, delay, rot, spin, flip, phase, len, thick;
  final Color color;

  static const double y0 = 520; // за крышей
  static const double gUp = 2000; // гравитация на взлёте
  static const double gDown = 900; // падают медленнее — как бумажки

  static const _colors = [
    Color(0xFFFC6D31),
    Color(0xFFFF7A59),
    Color(0xFFF59A3C),
    Color(0xFF0A4A3C),
    Color(0xFF0F5D4E),
    Color(0xFFBEA937),
    Color(0xFFF6C35B),
  ];

  static List<_Particle> burst(int n, int seed) {
    final r = math.Random(seed);
    double rnd(double a, double b) => a + r.nextDouble() * (b - a);
    return List.generate(n, (i) {
      final x0 = rnd(430, 870);
      final dot = r.nextDouble() < 0.22;
      final thick = rnd(16, 24);
      return _Particle(
        x0: x0,
        vx: (x0 - 650) * rnd(1.6, 3.2) + rnd(-260, 260),
        vy: -rnd(1050, 1400),
        delay: rnd(0, 0.16),
        rot: rnd(0, math.pi),
        spin: rnd(-7, 7),
        flip: rnd(5, 11),
        phase: rnd(0, math.pi * 2),
        len: dot ? thick : rnd(38, 70),
        thick: thick,
        color: _colors[r.nextInt(_colors.length)],
      );
    });
  }

  /// Положение в момент tt (сек) после старта залпа; rising — ещё летит вверх
  ({Offset p, double angle, double squash, bool rising, double alpha})? at(double tt, double t) {
    final s = tt - delay;
    if (s <= 0) return null;
    final ta = -vy / gUp; // время до верхней точки
    final double y;
    final double x;
    final rising = s < ta;
    final drift = (1 - math.exp(-1.6 * s)) / 1.6; // воздух тормозит по горизонтали
    if (rising) {
      y = y0 + vy * s + 0.5 * gUp * s * s;
      x = x0 + vx * drift;
    } else {
      final d = s - ta;
      y = y0 - vy * vy / (2 * gUp) + 0.5 * gDown * d * d;
      x = x0 + vx * drift + 22 * math.sin(phase + d * 6) * math.min(1, d * 3);
    }
    final fadeEnd = ((1.0 - t) / 0.14).clamp(0.0, 1.0);
    final fadeLow = ((_H + 20 - y) / 160).clamp(0.0, 1.0);
    final fadeIn = (s / 0.06).clamp(0.0, 1.0);
    return (
      p: Offset(x, y),
      angle: rot + spin * s,
      squash: 0.25 + 0.75 * math.cos(flip * s + phase).abs(),
      rising: rising,
      alpha: fadeEnd * fadeLow * fadeIn,
    );
  }

  void paint(Canvas canvas, Offset p, double angle, double squash, double alpha) {
    if (alpha <= 0.01) return;
    final paint = Paint()..color = _a(color, alpha);
    canvas.save();
    canvas.translate(p.dx, p.dy);
    canvas.rotate(angle);
    if (len <= thick) {
      canvas.drawCircle(Offset.zero, thick / 2 * (0.6 + 0.4 * squash), paint);
    } else {
      final l = len * squash;
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromCenter(center: Offset.zero, width: math.max(l, thick), height: thick),
          Radius.circular(thick / 2),
        ),
        paint,
      );
    }
    canvas.restore();
  }
}

double _confettiSeconds(double t) => (t - _tConfetti) * _durationMs / 1000;

// ---------------------------------------------------------------------------
// «Лучики» вокруг значка — те же чёрточки, что на иллюстрации.
// (центр, длина, угол в градусах, толщина, цвет)
const _rays = <(Offset, double, double, double, Color)>[
  (Offset(276, 88), 72.0, 45.0, 24.0, Color(0xFF0A4A3C)),
  (Offset(931, 50), 50.0, 90.0, 24.0, Color(0xFFFC5C19)),
  (Offset(1054, 85), 86, -45, 24, Color(0xFF0A4A3C)),
  (Offset(155, 197), 87.0, 41.0, 26.0, Color(0xFFFC6D31)),
  (Offset(1129, 226), 83, -44, 26, Color(0xFFFC6526)),
  (Offset(411, 250), 52.0, 49.0, 24.0, Color(0xFFFD8111)),
  (Offset(883, 283), 52, -45, 24, Color(0xFF0A4A3C)),
  (Offset(137, 348), 57, -25, 24, Color(0xFFD1541A)),
  (Offset(799, 380), 42, -60, 13, Color(0xFFBEA937)),
  (Offset(478, 398), 59.0, 48.0, 24.0, Color(0xFFFD7134)),
  (Offset(1080, 420), 30.0, 0.0, 30.0, Color(0xFFFC6A2F)),
  (Offset(1205, 376), 55.0, 35.0, 24.0, Color(0xFF0A4A3C)),
];

class _BackPainter extends CustomPainter {
  _BackPainter(this.t, this.s, this.particles);
  final double t, s;
  final List<_Particle> particles;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    canvas.scale(s);

    // 1) круг: выезжает снизу из-за дома и пружинит
    final ci = _iv(t, _tCircle, const ElasticOutCurve(0.5));
    final cf = _iv(t, (_tCircle.$1, _tCircle.$1 + 0.05));
    if (cf > 0) {
      canvas.save();
      canvas.clipRect(const Rect.fromLTRB(-300, -400, _W + 300, 905)); // не ниже земли
      final r = 359 * (0.5 + 0.5 * ci);
      final cy = 372 + (1 - ci) * 560;
      canvas.drawCircle(Offset(646, cy), r, Paint()..color = _a(_peach, cf));
      canvas.restore();
    }

    // 2) конфетти на взлёте (позади дома)
    final tt = _confettiSeconds(t);
    if (tt > 0) {
      for (final p in particles) {
        final st = p.at(tt, t);
        if (st != null && st.rising) p.paint(canvas, st.p, st.angle, st.squash, st.alpha);
      }
    }

    // 3) волна от значка
    final rp = _iv(t, _tRing, Curves.easeOut);
    if (rp > 0 && rp < 1) {
      canvas.drawCircle(
        _badgeC,
        _badgeR * (1 + 0.7 * rp),
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 14 * (1 - rp)
          ..color = _a(_badgeGreen, (1 - rp) * 0.45),
      );
    }

    // 4) лучики разлетаются от значка на свои места
    for (var i = 0; i < _rays.length; i++) {
      final (c, len, deg, th, color) = _rays[i];
      final start = _tRays + i * 0.012;
      final p = _iv(t, (start, start + 0.13), Curves.easeOutBack);
      if (p <= 0) continue;
      final pos = Offset.lerp(_badgeC, c, p)!;
      final grow = p.clamp(0.0, 1.15);
      final paint = Paint()..color = _a(color, p * 3);
      canvas.save();
      canvas.translate(pos.dx, pos.dy);
      canvas.rotate(deg * math.pi / 180);
      if (len <= th) {
        canvas.drawCircle(Offset.zero, th / 2 * grow, paint);
      } else {
        final l = lerpDouble(th, len, grow)!;
        canvas.drawRRect(
          RRect.fromRectAndRadius(
            Rect.fromCenter(center: Offset.zero, width: l, height: th * math.min(1, grow + 0.3)),
            Radius.circular(th / 2),
          ),
          paint,
        );
      }
      canvas.restore();
    }

    // 5) значок: выскакивает с поворотом, галочка рисуется
    final b = _iv(t, _tBadge, const ElasticOutCurve(0.45));
    if (b > 0) {
      canvas.save();
      canvas.translate(_badgeC.dx, _badgeC.dy);
      canvas.rotate((1 - b) * -0.9);
      canvas.scale(b);
      canvas.drawCircle(Offset.zero, _badgeR, Paint()..color = _badgeGreen);
      final ck = _iv(t, _tCheck, Curves.easeInOutCubic);
      if (ck > 0) {
        final path = Path()
          ..moveTo(-60, 15)
          ..lineTo(-24, 48)
          ..lineTo(58, -34);
        final metric = path.computeMetrics().first;
        canvas.drawPath(
          metric.extractPath(0, metric.length * ck),
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 36
            ..strokeCap = StrokeCap.round
            ..strokeJoin = StrokeJoin.round
            ..color = _checkWhite,
        );
      }
      canvas.restore();
    }

    canvas.restore();
  }

  @override
  bool shouldRepaint(_BackPainter old) => old.t != t || old.s != s;
}

class _FrontPainter extends CustomPainter {
  _FrontPainter(this.t, this.s, this.particles);
  final double t, s;
  final List<_Particle> particles;

  @override
  void paint(Canvas canvas, Size size) {
    final tt = _confettiSeconds(t);
    if (tt <= 0) return;
    canvas.save();
    canvas.scale(s);
    for (final p in particles) {
      final st = p.at(tt, t);
      if (st != null && !st.rising) p.paint(canvas, st.p, st.angle, st.squash, st.alpha);
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(_FrontPainter old) => old.t != t || old.s != s;
}
