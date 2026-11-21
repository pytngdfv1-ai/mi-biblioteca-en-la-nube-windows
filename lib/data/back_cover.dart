import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../models/vinyl.dart';
import 'objects3d.dart';

enum BackStyle { blur, solid, gradient }

/// Genera una contraportada: portada difuminada / color / degradado, con los temas y una nota.
class BackCoverGen {
  static Future<Uint8List> render(
    Vinyl v, {
    required bool tape,
    BackStyle style = BackStyle.blur,
    bool tracks = true,
    String note = '',
  }) async {
    final w = tape ? 840.0 : 1200.0, h = tape ? 1330.0 : 1200.0;
    final rec = ui.PictureRecorder();
    final c = Canvas(rec);
    final r = Rect.fromLTWH(0, 0, w, h);
    final hue = HSLColor.fromAHSL(1, v.hue % 360, .45, .22).toColor();
    final cover = await Objects3D.loadImage(v.coverUrl);
    c.drawRect(r, Paint()..color = hue);
    if (style == BackStyle.gradient) {
      c.drawRect(
        r,
        Paint()
          ..shader = LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [HSLColor.fromAHSL(1, v.hue % 360, .5, .34).toColor(), const Color(0xFF0B0B10)],
          ).createShader(r),
      );
    } else if (style == BackStyle.blur && cover != null) {
      c.saveLayer(r, Paint()..imageFilter = ui.ImageFilter.blur(sigmaX: 40, sigmaY: 40, tileMode: TileMode.clamp));
      final s = math.max(w / cover.width, h / cover.height) * 1.2;
      final dw = cover.width * s, dh = cover.height * s;
      c.drawImageRect(cover, Rect.fromLTWH(0, 0, cover.width.toDouble(), cover.height.toDouble()),
          Rect.fromLTWH((w - dw) / 2, (h - dh) / 2, dw, dh), Paint());
      c.restore();
      c.drawRect(r, Paint()..color = const Color(0x99000000));
    }
    final pad = w * .07;
    var y = pad;
    final title = v.single && v.tracks.isNotEmpty ? v.tracks.first : v.title;
    if (cover != null) {
      final sz = w * .24;
      final rr = RRect.fromRectAndRadius(Rect.fromLTWH(pad, y, sz, sz), const Radius.circular(10));
      c.save();
      c.clipRRect(rr);
      final s = math.max(sz / cover.width, sz / cover.height);
      final dw = cover.width * s, dh = cover.height * s;
      c.drawImageRect(cover, Rect.fromLTWH(0, 0, cover.width.toDouble(), cover.height.toDouble()),
          Rect.fromLTWH(pad + (sz - dw) / 2, y + (sz - dh) / 2, dw, dh), Paint()..filterQuality = FilterQuality.medium);
      c.restore();
      _t(c, v.artist.toUpperCase(), Offset(pad * 2 + sz, y), w - sz - pad * 3, w * .05, FontWeight.w800, Colors.white, 2);
      _t(c, title, Offset(pad * 2 + sz, y + w * .13), w - sz - pad * 3, w * .055, FontWeight.w400, const Color(0xCCFFFFFF), 3);
      y += sz + pad;
    } else {
      _t(c, v.artist.toUpperCase(), Offset(pad, y), w - pad * 2, w * .06, FontWeight.w800, Colors.white, 1);
      _t(c, title, Offset(pad, y + w * .085), w - pad * 2, w * .055, FontWeight.w400, const Color(0xCCFFFFFF), 2);
      y += w * .24;
    }
    c.drawLine(Offset(pad, y), Offset(w - pad, y), Paint()..color = const Color(0x55FFFFFF)..strokeWidth = 2);
    y += pad * .6;
    final noteH = note.trim().isEmpty ? 0.0 : w * .16;
    if (tracks) {
      final fs = w * .042;
      final rows = math.max(1, ((h - y - pad - noteH) / (fs * 1.55)).floor());
      final n = math.min(v.tracks.length, rows);
      for (var i = 0; i < n; i++) {
        final more = i == n - 1 && v.tracks.length > n;
        _t(c, more ? '… +${v.tracks.length - n + 1} más' : '${i + 1}. ${v.tracks[i]}', Offset(pad, y + i * fs * 1.55), w - pad * 2,
            fs, FontWeight.w400, const Color(0xDDFFFFFF), 1);
      }
    }
    if (noteH > 0) {
      _t(c, note.trim(), Offset(pad, h - pad - noteH + 8), w - pad * 2, w * .04, FontWeight.w400, const Color(0xBBFFFFFF), 3, italic: true);
    }
    final im = await rec.endRecording().toImage(w.round(), h.round());
    return (await im.toByteData(format: ui.ImageByteFormat.png))!.buffer.asUint8List();
  }

  static void _t(Canvas c, String t, Offset o, double maxW, double size, FontWeight wt, Color col, int lines, {bool italic = false}) {
    final tp = TextPainter(
      text: TextSpan(text: t, style: TextStyle(fontSize: size, fontWeight: wt, color: col, fontStyle: italic ? FontStyle.italic : FontStyle.normal)),
      textDirection: TextDirection.ltr,
      maxLines: lines,
      ellipsis: '…',
    )..layout(maxWidth: maxW);
    tp.paint(c, o);
  }
}
