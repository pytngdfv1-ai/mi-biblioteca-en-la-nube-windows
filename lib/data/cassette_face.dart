import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../models/vinyl.dart';

/// Cara de un cassette dibujado de verdad: carcasa, etiqueta de papel pegada, ventana con
/// carretes y cinta, base con ranuras y tornillos. [side] = 'A' o 'B'.
class CassetteFace {
  static Future<ui.Image> build(Vinyl v, {String side = 'A', int w = 900, ui.Image? cover}) async {
    final h = (w * .63).round();
    final rec = ui.PictureRecorder();
    final c = Canvas(rec);
    final W = w.toDouble(), H = h.toDouble();

    // Carcasa
    final shell = RRect.fromRectAndRadius(Rect.fromLTWH(0, 0, W, H), Radius.circular(H * .05));
    c.drawRRect(
        shell,
        Paint()
          ..shader = const LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [Color(0xFF3A3A40), Color(0xFF1C1C20)])
              .createShader(Rect.fromLTWH(0, 0, W, H)));
    c.drawRRect(shell, Paint()..style = PaintingStyle.stroke..strokeWidth = H * .012..color = const Color(0xFF55555C));

    // Franja de color con la portada (como en el reproductor) y papel escrito a mano arriba.
    final strip = Rect.fromLTWH(W * .07, H * .07, W * .86, H * .55);
    final sr = RRect.fromRectAndRadius(strip, Radius.circular(H * .02));
    c.save();
    c.clipRRect(sr);
    c.drawRect(strip, Paint()..color = HSLColor.fromAHSL(1, v.hue % 360, .35, .12).toColor());
    if (cover != null) {
      final s0 = math.max(strip.width / cover.width, strip.height / cover.height);
      final dw = cover.width * s0, dh = cover.height * s0;
      c.drawImageRect(cover, Rect.fromLTWH(0, 0, cover.width.toDouble(), cover.height.toDouble()),
          Rect.fromCenter(center: strip.center, width: dw, height: dh), Paint()..filterQuality = FilterQuality.medium);
      c.drawRect(strip, Paint()..color = const Color(0x77000000));
    }
    // Papel con renglones y margen rojo
    final paper = Path()
      ..moveTo(strip.left, strip.top + H * .02)
      ..lineTo(strip.right, strip.top + H * .02)
      ..lineTo(strip.right - W * .02, strip.top + strip.height * .30)
      ..lineTo(strip.left + W * .0, strip.top + strip.height * .30)
      ..close();
    c.drawPath(paper, Paint()..color = const Color(0xFFF3EEDD));
    final ruled = Paint()..color = const Color(0x553B63C4)..strokeWidth = H * .004;
    c.drawLine(Offset(strip.left, strip.top + strip.height * .22), Offset(strip.right, strip.top + strip.height * .22), ruled);
    c.drawLine(Offset(strip.left + W * .05, strip.top + H * .02), Offset(strip.left + W * .05, strip.top + strip.height * .30),
        Paint()..color = const Color(0x66D04040)..strokeWidth = H * .004);
    final title = v.single && v.tracks.isNotEmpty ? v.tracks.first : v.title;
    _text(c, '$title – ${v.artist}', Offset(strip.left + W * .07, strip.top + H * .022), strip.width - W * .1, H * .085,
        w: FontWeight.w700, color: const Color(0xFF1F3C88), family: 'cursive');
    // Lado y datos
    c.drawRRect(RRect.fromRectAndRadius(Rect.fromLTWH(strip.left + W * .015, strip.bottom - H * .1, W * .05, H * .085), const Radius.circular(2)),
        Paint()..color = const Color(0xFF1B1B1B));
    _text(c, side, Offset(strip.left + W * .027, strip.bottom - H * .1), W * .04, H * .075, w: FontWeight.w900, color: const Color(0xFFF2F2F2));
    _text(c, 'NORMAL · ${v.tracks.length} T', Offset(strip.right - W * .3, strip.bottom - H * .09), W * .28, H * .05,
        w: FontWeight.w800, color: const Color(0x99DDDDDD));
    c.restore();

    // Ventana con carretes y cinta
    final win = RRect.fromRectAndRadius(Rect.fromLTWH(W * .22, H * .30, W * .56, H * .27), Radius.circular(H * .045));
    c.drawRRect(win, Paint()..color = const Color(0xFF0B0B0D));
    c.drawRRect(win, Paint()..style = PaintingStyle.stroke..strokeWidth = H * .01..color = const Color(0xFF6A6A72));
    final cy = H * .435;
    final lx = W * .36, rx = W * .64;
    final tape = Paint()..color = const Color(0xFF3B2A20);
    c.drawCircle(Offset(lx, cy), H * .1, tape);
    c.drawCircle(Offset(rx, cy), H * .075, tape);
    c.drawLine(Offset(lx, cy + H * .1), Offset(rx, cy + H * .075), Paint()..color = const Color(0xFF3B2A20)..strokeWidth = H * .012);
    for (final x in [lx, rx]) {
      c.drawCircle(Offset(x, cy), H * .052, Paint()..color = const Color(0xFFE9E9EC));
      c.drawCircle(Offset(x, cy), H * .034, Paint()..color = const Color(0xFF0B0B0D));
      for (var i = 0; i < 6; i++) {
        final a = i * math.pi / 3;
        c.drawLine(Offset(x + math.cos(a) * H * .034, cy + math.sin(a) * H * .034),
            Offset(x + math.cos(a) * H * .05, cy + math.sin(a) * H * .05), Paint()..color = const Color(0xFFE9E9EC)..strokeWidth = H * .012);
      }
    }

    // Base trapezoidal con ranuras
    final base = Path()
      ..moveTo(W * .2, H * .68)
      ..lineTo(W * .8, H * .68)
      ..lineTo(W * .9, H * .97)
      ..lineTo(W * .1, H * .97)
      ..close();
    c.drawPath(base, Paint()..color = const Color(0xFF2A2A30));
    c.drawPath(base, Paint()..style = PaintingStyle.stroke..strokeWidth = H * .008..color = const Color(0xFF55555C));
    for (final x in [.3, .7]) {
      c.drawCircle(Offset(W * x, H * .83), H * .035, Paint()..color = const Color(0xFF0B0B0D));
    }
    for (final x in [.42, .58]) {
      c.drawRRect(RRect.fromRectAndRadius(Rect.fromCenter(center: Offset(W * x, H * .9), width: W * .035, height: H * .05), Radius.circular(2)),
          Paint()..color = const Color(0xFF0B0B0D));
    }
    // Tornillos
    for (final p in [const Offset(.035, .06), const Offset(.965, .06), const Offset(.035, .94), const Offset(.965, .94)]) {
      c.drawCircle(Offset(W * p.dx, H * p.dy), H * .022, Paint()..color = const Color(0xFF8C9094));
      c.drawLine(Offset(W * p.dx - H * .014, H * p.dy), Offset(W * p.dx + H * .014, H * p.dy), Paint()..color = const Color(0xFF2A2A31)..strokeWidth = H * .006);
    }
    // Reflejo suave del plástico
    c.drawRRect(
        shell,
        Paint()
          ..shader = const LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [Color(0x22FFFFFF), Color(0x00FFFFFF), Color(0x11FFFFFF)], stops: [0, .5, 1])
              .createShader(Rect.fromLTWH(0, 0, W, H)));
    return rec.endRecording().toImage(w, h);
  }

  static void _text(Canvas c, String s, Offset at, double maxW, double size,
      {FontWeight w = FontWeight.w500, Color color = const Color(0xFF000000), String? family}) {
    final tp = TextPainter(
      text: TextSpan(text: s, style: TextStyle(fontSize: size, fontWeight: w, color: color, fontFamily: family)),
      textDirection: TextDirection.ltr,
      maxLines: 1,
      ellipsis: '…',
    )..layout(maxWidth: maxW);
    tp.paint(c, at);
  }
}
