import 'dart:math' as math;

import 'package:flutter/material.dart';

const kDiscStyles = ['Clásico', 'Mármol', 'Humo', 'Galaxia', 'Metálico', 'Translúcido', 'Salpicado'];

/// Colores para vinilo y cassette.
const kDiscColors = <Color>[
  Color(0xFFC62828), Color(0xFFEF6C00), Color(0xFFFBC02D), Color(0xFF2E7D32),
  Color(0xFF00838F), Color(0xFF1565C0), Color(0xFF6A1B9A), Color(0xFFD81B60),
  Color(0xFFECEFF1), Color(0xFF455A64),
];

/// Pinta la textura del vinilo (antes de los surcos), recortada al disco.
void paintDiscTexture(Canvas canvas, Offset c, double r, int style, Color color) {
  if (style <= 0) return;
  final rect = Rect.fromCircle(center: c, radius: r);
  final rnd = math.Random(style * 131 + (color.value % 9973));
  canvas.save();
  canvas.clipPath(Path()..addOval(rect));
  Offset pt() => Offset(c.dx + (rnd.nextDouble() - .5) * r * 2, c.dy + (rnd.nextDouble() - .5) * r * 2);
  final blur = MaskFilter.blur(BlurStyle.normal, r * .04);
  switch (style) {
    case 1: // mármol
      canvas.drawRect(rect, Paint()..color = Color.lerp(color, Colors.black, .35)!);
      for (var i = 0; i < 8; i++) {
        final a = rnd.nextDouble() * math.pi * 2;
        final p = Path()..moveTo(c.dx + math.cos(a) * r * 1.1, c.dy + math.sin(a) * r * 1.1);
        for (var k = 0; k < 4; k++) {
          final q = pt();
          final e = pt();
          p.quadraticBezierTo(q.dx, q.dy, e.dx, e.dy);
        }
        canvas.drawPath(
          p,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = r * (.05 + rnd.nextDouble() * .12)
            ..color = (i.isEven ? Colors.white : color).withOpacity(.3 + rnd.nextDouble() * .3)
            ..maskFilter = blur,
        );
      }
    case 2: // humo
      canvas.drawRect(rect, Paint()..color = Color.lerp(color, Colors.black, .7)!);
      for (var i = 0; i < 9; i++) {
        canvas.drawCircle(
          pt(),
          r * (.25 + rnd.nextDouble() * .35),
          Paint()
            ..color = Color.lerp(color, Colors.white, .55)!.withOpacity(.14 + rnd.nextDouble() * .16)
            ..maskFilter = MaskFilter.blur(BlurStyle.normal, r * .18),
        );
      }
    case 3: // galaxia
      canvas.drawRect(rect, Paint()..color = const Color(0xFF0A0820));
      canvas.drawRect(
        rect,
        Paint()
          ..shader = SweepGradient(colors: [
            color.withOpacity(.0), color.withOpacity(.65), const Color(0xFFE040FB).withOpacity(.5),
            const Color(0xFF29B6F6).withOpacity(.5), color.withOpacity(.0),
          ]).createShader(rect)
          ..maskFilter = MaskFilter.blur(BlurStyle.normal, r * .15),
      );
      for (var i = 0; i < 70; i++) {
        canvas.drawCircle(pt(), r * (.004 + rnd.nextDouble() * .008), Paint()..color = Colors.white.withOpacity(.4 + rnd.nextDouble() * .6));
      }
    case 4: // metálico
      canvas.drawRect(
        rect,
        Paint()
          ..shader = SweepGradient(colors: [
            Color.lerp(color, Colors.white, .1)!, Color.lerp(color, Colors.black, .55)!,
            Color.lerp(color, Colors.white, .65)!, Color.lerp(color, Colors.black, .5)!,
            Color.lerp(color, Colors.white, .1)!,
          ], stops: const [0, .28, .5, .78, 1]).createShader(rect),
      );
    case 5: // translúcido
      canvas.drawRect(rect, Paint()..color = color.withOpacity(.55));
      canvas.drawRect(
        rect,
        Paint()
          ..shader = RadialGradient(
            center: const Alignment(-.4, -.5),
            colors: [Colors.white.withOpacity(.35), Colors.transparent],
          ).createShader(rect),
      );
    case 6: // salpicado
      canvas.drawRect(rect, Paint()..color = Color.lerp(color, Colors.black, .45)!);
      final cols = [color, Colors.white, Color.lerp(color, Colors.yellow, .5)!];
      for (var i = 0; i < 60; i++) {
        canvas.drawCircle(pt(), r * (.01 + rnd.nextDouble() * .07), Paint()..color = cols[i % 3].withOpacity(.55 + rnd.nextDouble() * .4));
      }
  }
  canvas.restore();
}
