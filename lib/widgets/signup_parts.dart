import 'package:flutter/material.dart';

import '../screens/legal_screen.dart';
import '../theme.dart';
import 'common.dart';
import 'zicons.dart';

/// Общие части регистрации: обычная форма (почта + пароль) и экран «Finish setting up»
/// после входа через Google используют одни и те же поля и одно и то же согласие.

/// Подпись поля: «*» — обязательно, «(optional)» — можно пропустить
class FieldLabel extends StatelessWidget {
  const FieldLabel(this.text, {super.key, this.required = false, this.optional = false});
  final String text;
  final bool required;
  final bool optional;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Text.rich(
          TextSpan(children: [
            TextSpan(text: text),
            if (required) const TextSpan(text: ' *', style: TextStyle(color: Zc.orange, fontWeight: FontWeight.w700)),
            if (optional)
              const TextSpan(
                  text: '  (optional)', style: TextStyle(color: Zc.grey, fontSize: 14, fontWeight: FontWeight.w400)),
          ]),
          style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w600, color: Zc.text),
        ),
      );
}

/// «I am»: собственник или агент
class RolePicker extends StatelessWidget {
  const RolePicker({super.key, required this.value, required this.onChanged});
  final String value;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) => Row(children: [
        Expanded(child: _card('owner', 'Owner', 'I list my own property', ZI.house)),
        const SizedBox(width: 12),
        Expanded(child: _card('agent', 'Agent', 'I list for clients', ZI.badge)),
      ]);

  Widget _card(String role, String title, String sub, IconData icon) {
    final on = value == role;
    return GestureDetector(
      onTap: () => onChanged(role),
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

/// Подсказка под полем лицензии ZIEA
const kLicenceHint = 'Not required to sign up — you can add it later in Profile. Agents with a checked ZIEA licence '
    'get the "Licensed agent" badge and can post up to 10 listings.';

/// Обязательная галочка: условия, политика и хранение данных вне Замбии (дата согласия хранится на сервере)
class ConsentCheck extends StatelessWidget {
  const ConsentCheck({super.key, required this.value, required this.onChanged});
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) => Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Checkbox(value: value, activeColor: Zc.orange, onChanged: (v) => onChanged(v ?? false)),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.only(top: 12),
            // одним абзацем, чтобы строки переносились естественно
            child: Text.rich(
              TextSpan(style: const TextStyle(fontSize: 13, color: Zc.text, height: 1.4), children: [
                const TextSpan(text: 'I agree to the '),
                WidgetSpan(
                  alignment: PlaceholderAlignment.baseline,
                  baseline: TextBaseline.alphabetic,
                  child: _link('Terms of Service', () => openLegal(context, LegalDoc.terms)),
                ),
                const TextSpan(text: ' and '),
                WidgetSpan(
                  alignment: PlaceholderAlignment.baseline,
                  baseline: TextBaseline.alphabetic,
                  child: _link('Privacy Policy', () => openLegal(context, LegalDoc.privacy)),
                ),
                const TextSpan(
                    text: ', and to Zumi processing my data to run my account and storing it on servers '
                        'outside Zambia (European Union).'),
                const TextSpan(text: ' *', style: TextStyle(color: Zc.orange, fontWeight: FontWeight.w700)),
              ]),
            ),
          ),
        ),
      ]);

  Widget _link(String text, VoidCallback onTap) => GestureDetector(
        onTap: onTap,
        child: Text(text, style: const TextStyle(fontSize: 13, color: Zc.green, decoration: TextDecoration.underline)),
      );
}

/// Новости и предложения — по желанию, по умолчанию выключено
class MarketingCheck extends StatelessWidget {
  const MarketingCheck({super.key, required this.value, required this.onChanged});
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) => Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Checkbox(value: value, activeColor: Zc.orange, onChanged: (v) => onChanged(v ?? false)),
        const Expanded(
          child: Padding(
            padding: EdgeInsets.only(top: 12),
            child: Text(
              'Send me Zumi news and offers by WhatsApp or email (optional). '
              'You can turn this off any time in Settings.',
              style: TextStyle(fontSize: 13, color: Zc.text),
            ),
          ),
        ),
      ]);
}

/// Кнопка «Continue with Google» (цветная «G» нарисована, без загрузки картинок)
class GoogleButton extends StatelessWidget {
  const GoogleButton({super.key, required this.onPressed, this.loading = false});
  final VoidCallback? onPressed;
  final bool loading;

  @override
  Widget build(BuildContext context) => SizedBox(
        width: double.infinity,
        height: 52,
        child: OutlinedButton(
          onPressed: loading ? null : onPressed,
          style: OutlinedButton.styleFrom(
            backgroundColor: Colors.white,
            foregroundColor: Zc.text,
            side: const BorderSide(color: Zc.lightGrey, width: 1.2),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          ),
          child: loading
              ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2.4))
              : const Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                  SizedBox(width: 20, height: 20, child: CustomPaint(painter: _GoogleG())),
                  SizedBox(width: 12),
                  Text('Continue with Google', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
                ]),
        ),
      );
}

class _GoogleG extends CustomPainter {
  const _GoogleG();

  @override
  void paint(Canvas canvas, Size size) {
    final s = size.shortestSide;
    final stroke = s * 0.2;
    final r = (s - stroke) / 2;
    final c = Offset(size.width / 2, size.height / 2);
    final rect = Rect.fromCircle(center: c, radius: r);
    Paint p(Color col) => Paint()
      ..color = col
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke;
    const deg = 3.14159265 / 180;
    // красный сверху, жёлтый слева, зелёный снизу, синий справа + перекладина
    canvas.drawArc(rect, -150 * deg, 110 * deg, false, p(const Color(0xFFEA4335)));
    canvas.drawArc(rect, 150 * deg, 60 * deg, false, p(const Color(0xFFFBBC05)));
    canvas.drawArc(rect, 45 * deg, 105 * deg, false, p(const Color(0xFF34A853)));
    canvas.drawArc(rect, 0, 45 * deg, false, p(const Color(0xFF4285F4)));
    canvas.drawLine(c, Offset(c.dx + r + stroke / 2, c.dy),
        Paint()
          ..color = const Color(0xFF4285F4)
          ..strokeWidth = stroke);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

/// Разделитель «or»
class OrDivider extends StatelessWidget {
  const OrDivider({super.key});

  @override
  Widget build(BuildContext context) => const Padding(
        padding: EdgeInsets.symmetric(vertical: 18),
        child: Row(children: [
          Expanded(child: Divider(color: Zc.lightGrey)),
          Padding(padding: EdgeInsets.symmetric(horizontal: 12), child: Text('or', style: TextStyle(color: Zc.grey))),
          Expanded(child: Divider(color: Zc.lightGrey)),
        ]),
      );
}
