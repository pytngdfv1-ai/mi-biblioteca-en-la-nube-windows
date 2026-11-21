import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../data/fetch_bytes.dart';

/// Una imagen dentro del collage. x, y = centro (0..1); scale = lado / ancho del lienzo.
class CollageLayer {
  CollageLayer({required this.url, this.x = .5, this.y = .5, this.scale = .5, this.rot = 0, this.shape = 0, this.cu = 0, this.cv = 0, this.cs = 1});

  String url;
  double x, y, scale, rot;

  /// 0 cuadrado, 1 redondeado, 2 círculo.
  int shape;

  /// Recorte de la imagen: esquina (cu, cv) y tamaño cs, como fracción del cuadrado central.
  double cu, cv, cs;

  CollageLayer copy() => CollageLayer(url: url, x: x, y: y, scale: scale, rot: rot, shape: shape, cu: cu, cv: cv, cs: cs);

  Map<String, dynamic> toJson() =>
      {'url': url, 'x': x, 'y': y, 'scale': scale, 'rot': rot, 'shape': shape, 'cu': cu, 'cv': cv, 'cs': cs};

  factory CollageLayer.fromJson(Map<String, dynamic> j) => CollageLayer(
        url: j['url'] as String,
        x: (j['x'] as num).toDouble(),
        y: (j['y'] as num).toDouble(),
        scale: (j['scale'] as num).toDouble(),
        rot: (j['rot'] as num).toDouble(),
        shape: (j['shape'] as num?)?.toInt() ?? 0,
        cu: (j['cu'] as num?)?.toDouble() ?? 0,
        cv: (j['cv'] as num?)?.toDouble() ?? 0,
        cs: (j['cs'] as num?)?.toDouble() ?? 1,
      );
}

/// Imágenes ya decodificadas (se reutilizan al editar y al guardar).
class CollageImages {
  static final Map<String, ui.Image> _c = {};

  static ui.Image? peek(String url) => _c[url];

  static Future<ui.Image?> load(String url) async {
    final have = _c[url];
    if (have != null) return have;
    try {
      final bytes = await fetchBytes(url);
      final codec = await ui.instantiateImageCodec(bytes, targetWidth: 900);
      final f = await codec.getNextFrame();
      return _c[url] = f.image;
    } catch (_) {
      return null;
    }
  }
}

/// Composiciones automáticas a partir de las portadas de los temas.
class CollageLayout {
  static List<CollageLayer> grid(List<String> urls) {
    final n = urls.length;
    if (n == 0) return [];
    final c = n == 1 ? 1 : (n <= 4 ? 2 : (n <= 9 ? 3 : 4));
    return [
      for (var i = 0; i < c * c; i++)
        CollageLayer(url: urls[i % n], x: ((i % c) + .5) / c, y: ((i ~/ c) + .5) / c, scale: 1 / c),
    ];
  }

  /// Retazos: un trozo rasgado de la portada de cada tema, en cuadrícula con leve giro y solapado.
  static List<CollageLayer> cutouts(List<String> perTrack, {int seed = 1}) {
    if (perTrack.isEmpty) return [];
    final r = math.Random(perTrack.length * 11 + seed * 7);
    final n = math.min(perTrack.length, 16);
    final c = n <= 1 ? 1 : (n <= 4 ? 2 : (n <= 9 ? 3 : 4));
    final out = <CollageLayer>[];
    for (var i = 0; i < c * c; i++) {
      final sz = .32 + r.nextDouble() * .28;
      out.add(CollageLayer(
        url: perTrack[i % n],
        x: ((i % c) + .5) / c,
        y: ((i ~/ c) + .5) / c,
        scale: c == 1 ? 1.0 : 1.12 / c,
        rot: c == 1 ? 0 : (r.nextDouble() - .5) * .16,
        shape: c == 1 ? 0 : 3,
        cu: r.nextDouble() * (1 - sz),
        cv: r.nextDouble() * (1 - sz),
        cs: c == 1 ? 1.0 : sz,
      ));
    }
    return out;
  }

  static List<CollageLayer> mosaic(List<String> urls, {int seed = 1}) {
    if (urls.isEmpty) return [];
    final r = math.Random(urls.length * 7 + seed);
    final out = <CollageLayer>[CollageLayer(url: urls.first, scale: 1.0)];
    final rest = urls.length > 1 ? urls.sublist(1) : urls;
    for (var i = 0; i < math.min(rest.length, 8); i++) {
      out.add(CollageLayer(
        url: rest[i],
        x: .22 + r.nextDouble() * .56,
        y: .22 + r.nextDouble() * .56,
        scale: .38 + r.nextDouble() * .17,
        rot: (r.nextDouble() - .5) * .7,
      ));
    }
    return out;
  }
}

class CollagePainter extends CustomPainter {
  CollagePainter(this.layers, this.images, {this.selected = -1, this.guides = true});

  final List<CollageLayer> layers;
  final Map<String, ui.Image> images;
  final int selected;
  final bool guides;

  static Path shapePath(int shape, Rect r) => switch (shape) {
        2 => (Path()..addOval(r)),
        1 => (Path()..addRRect(RRect.fromRectAndRadius(r, Radius.circular(r.width * .14)))),
        _ => (Path()..addRect(r)),
      };

  /// Contorno de papel rasgado: bordes quebrados e irregulares (forma 3).
  static Path tornPath(Rect r, int seed, double rough) {
    final rnd = math.Random(seed);
    final pts = <Offset>[];
    const n = 22;
    void edge(Offset a, Offset b) {
      for (var k = 0; k < n; k++) {
        final t = k / n;
        final big = rnd.nextDouble() < .12 ? 2.2 : 1.0;
        pts.add(Offset(a.dx + (b.dx - a.dx) * t + (rnd.nextDouble() - .5) * 2 * rough * big,
            a.dy + (b.dy - a.dy) * t + (rnd.nextDouble() - .5) * 2 * rough * big));
      }
    }

    edge(r.topLeft, r.topRight);
    edge(r.topRight, r.bottomRight);
    edge(r.bottomRight, r.bottomLeft);
    edge(r.bottomLeft, r.topLeft);
    return Path()..addPolygon(pts, true);
  }

  /// ¿El punto [p] (en píxeles del lienzo) cae sobre la capa?
  static bool hit(CollageLayer l, Offset p, Size size) {
    final dx = p.dx - l.x * size.width;
    final dy = p.dy - l.y * size.height;
    final c = math.cos(-l.rot), s = math.sin(-l.rot);
    final lx = dx * c - dy * s;
    final ly = dx * s + dy * c;
    final h = l.scale * size.width / 2;
    if (l.shape == 2) return lx * lx + ly * ly <= h * h;
    return lx.abs() <= h && ly.abs() <= h;
  }

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(Offset.zero & size, Paint()..color = const Color(0xFF15151B));
    for (var i = 0; i < layers.length; i++) {
      final l = layers[i];
      final side = l.scale * size.width;
      canvas.save();
      canvas.translate(l.x * size.width, l.y * size.height);
      canvas.rotate(l.rot);
      final r = Rect.fromCenter(center: Offset.zero, width: side, height: side);
      final torn = l.shape == 3;
      final seed = i * 7919 + l.url.hashCode;
      // Rasgado: papel claro con fibra (borde) y la imagen un poco más adentro.
      final path = torn ? tornPath(r, seed, side * .022) : shapePath(l.shape, r);
      if (l.scale < .95 || torn) canvas.drawShadow(path, Colors.black, torn ? 5 : 6, true);
      if (torn) canvas.drawPath(path, Paint()..color = const Color(0xFFF3EEDF));
      canvas.save();
      canvas.clipPath(torn ? tornPath(r.deflate(side * .035), seed + 1, side * .018) : path);
      final img = images[l.url];
      if (img != null) {
        final w = img.width.toDouble(), h = img.height.toDouble();
        final s = math.min(w, h);
        canvas.drawImageRect(img, Rect.fromLTWH((w - s) / 2 + l.cu * s, (h - s) / 2 + l.cv * s, l.cs * s, l.cs * s), r,
            Paint()..filterQuality = FilterQuality.medium);
      } else {
        canvas.drawRect(r, Paint()..color = const Color(0xFF2A2A33));
      }
      canvas.restore();
      if (guides && i == selected) {
        canvas.drawPath(
            path,
            Paint()
              ..style = PaintingStyle.stroke
              ..strokeWidth = 2.5
              ..color = const Color(0xFFFFC857));
      }
      canvas.restore();
    }
  }

  @override
  bool shouldRepaint(covariant CollagePainter old) => true;
}

/// Dibuja el collage en una imagen PNG cuadrada.
Future<Uint8List> renderCollage(List<CollageLayer> layers, {int px = 1200}) async {
  final imgs = <String, ui.Image>{};
  for (final u in {for (final l in layers) l.url}) {
    final i = await CollageImages.load(u);
    if (i != null) imgs[u] = i;
  }
  final rec = ui.PictureRecorder();
  final canvas = Canvas(rec);
  CollagePainter(layers, imgs, guides: false).paint(canvas, Size(px.toDouble(), px.toDouble()));
  final im = await rec.endRecording().toImage(px, px);
  final bd = await im.toByteData(format: ui.ImageByteFormat.png);
  return bd!.buffer.asUint8List();
}
