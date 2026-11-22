import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:path_provider/path_provider.dart';

import '../models/vinyl.dart';
import 'fetch_bytes.dart';

Uint8List? _thumb(Uint8List b) {
  final im = img.decodeImage(b);
  if (im == null) return null;
  final r = img.copyResize(im, width: 260);
  return Uint8List.fromList(img.encodeJpg(r, quality: 80));
}

/// PDF a color de la línea de tiempo: años (de más antiguo a más reciente) con sus portadas.
class TimelinePdf {
  static Future<Uint8List> build(
    Map<int, List<Vinyl>> byYear,
    List<int> years, {
    void Function(int done, int total)? onProgress,
  }) async {
    final doc = pw.Document();
    final total = years.fold<int>(0, (a, y) => a + byYear[y]!.length);
    var done = 0;
    final blocks = <pw.Widget>[];
    int? decade;
    for (final y in years) {
      final d = y <= 0 ? -1 : y ~/ 10 * 10;
      if (d != decade) {
        decade = d;
        final hue = d < 0 ? 0.0 : ((d ~/ 10) * 47 % 360).toDouble();
        blocks.add(pw.Container(
          margin: const pw.EdgeInsets.only(top: 14, bottom: 4),
          padding: const pw.EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          color: _hsl(hue, .55, .35),
          width: double.infinity,
          child: pw.Text(d < 0 ? 'Sin año' : (d >= 2000 ? 'Década de $d' : 'Años ${(d % 100).toString().padLeft(2, '0')}'),
              style: pw.TextStyle(color: PdfColors.white, fontSize: 14, fontWeight: pw.FontWeight.bold)),
        ));
      }
      final cells = <pw.Widget>[];
      for (final v in byYear[y]!) {
        Uint8List? t;
        final u = v.coverUrl;
        if (u != null) {
          try {
            t = await compute(_thumb, await fetchBytes(u));
          } catch (_) {}
        }
        final box = t != null
            ? pw.Image(pw.MemoryImage(t), width: 82, height: 82, fit: pw.BoxFit.cover)
            : pw.Container(
                width: 82,
                height: 82,
                color: _hsl(v.hue.toDouble(), .5, .3),
                padding: const pw.EdgeInsets.all(4),
                child: pw.Text(v.title, style: const pw.TextStyle(color: PdfColors.white, fontSize: 8), maxLines: 4),
              );
        cells.add(pw.Container(
          width: 90,
          margin: const pw.EdgeInsets.only(right: 4, bottom: 6),
          child: pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
            box,
            pw.SizedBox(height: 2),
            pw.Text(v.title, maxLines: 1, style: pw.TextStyle(fontSize: 6.5, fontWeight: pw.FontWeight.bold)),
            pw.Text(v.artist, maxLines: 1, style: const pw.TextStyle(fontSize: 6, color: PdfColors.grey700)),
          ]),
        ));
        onProgress?.call(++done, total);
      }
      blocks.add(pw.Wrap(children: [
        pw.Container(
          width: 40,
          padding: const pw.EdgeInsets.only(top: 3),
          child: pw.Text(y > 0 ? '$y' : '', style: pw.TextStyle(fontSize: 12, fontWeight: pw.FontWeight.bold, color: PdfColors.amber800)),
        ),
        ...cells,
      ]));
    }
    doc.addPage(pw.MultiPage(
      pageFormat: PdfPageFormat.a4,
      margin: const pw.EdgeInsets.all(28),
      header: (c) => c.pageNumber == 1
          ? pw.Text('Mi Biblioteca – Línea de tiempo', style: pw.TextStyle(fontSize: 20, fontWeight: pw.FontWeight.bold))
          : pw.SizedBox(),
      footer: (c) => pw.Align(alignment: pw.Alignment.centerRight, child: pw.Text('${c.pageNumber}/${c.pagesCount}', style: const pw.TextStyle(fontSize: 8))),
      build: (_) => blocks,
    ));
    return doc.save();
  }

  static PdfColor _hsl(double h, double s, double l) {
    final c = (1 - (2 * l - 1).abs()) * s;
    final x = c * (1 - ((h / 60) % 2 - 1).abs());
    final m = l - c / 2;
    final (r, g, b) = switch ((h ~/ 60) % 6) {
      0 => (c, x, 0.0),
      1 => (x, c, 0.0),
      2 => (0.0, c, x),
      3 => (0.0, x, c),
      4 => (x, 0.0, c),
      _ => (c, 0.0, x),
    };
    return PdfColor(r + m, g + m, b + m);
  }

  /// Guarda en Descargas (o en la carpeta de la app si no se puede). Devuelve la ruta.
  static Future<String> save(Uint8List bytes) async {
    var name = 'Linea_de_tiempo.pdf';
    Directory dir = Directory('${Platform.environment['USERPROFILE'] ?? ''}\\Downloads');
    if (!dir.existsSync()) dir = (await getDownloadsDirectory()) ?? await getApplicationDocumentsDirectory();
    var f = File('${dir.path}/$name');
    var n = 2;
    while (f.existsSync()) {
      f = File('${dir.path}/Linea_de_tiempo_$n.pdf');
      n++;
    }
    try {
      await f.writeAsBytes(bytes);
    } catch (_) {
      final alt = await getApplicationDocumentsDirectory();
      f = File('${alt.path}/$name');
      await f.writeAsBytes(bytes);
    }
    return f.path;
  }
}
