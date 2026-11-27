import 'dart:io';

import '../models/vinyl.dart';
import 'koofr_client.dart';
import 'koofr_settings.dart';

/// Resultado de subir un disco local a la nube.
class UploadResult {
  UploadResult(this.uploaded, this.skipped, this.firstKey);
  final int uploaded;

  /// Archivos que ya estaban en la nube (no se pisan).
  final int skipped;

  /// Ruta (relativa a la carpeta raíz de la cuenta) del primer tema: sirve para conservar los datos.
  final String firstKey;
}

/// Sube la carpeta de un álbum (o el tema suelto) del equipo / PC a la nube.
class CloudUpload {
  static bool isLocal(Vinyl v) => v.trackUrls.isNotEmpty && v.trackUrls.first.startsWith('file:');

  static String _name(String path) => path.split(RegExp(r'[\\/]')).where((e) => e.isNotEmpty).last;

  static File _file(String url) => File(Uri.parse(url).toFilePath());

  /// Carpeta de la nube donde quedará: [dest]/Artista/Álbum (o Artista/Álbum sin [dest]).
  ///
  /// Con [flatSingles] un tema suelto va directo a [dest]/Artista (sin carpeta propia):
  /// así lo encuentra el agente de la nube, que le busca el álbum y lo copia a Artista/Álbum.
  static List<String> targetDir(Vinyl v, String? dest, {bool flatSingles = false}) {
    final artist = KoofrClient.cleanName(v.artist.isEmpty ? 'Artista desconocido' : v.artist);
    if (flatSingles && v.single) return [if (dest != null && dest.isNotEmpty) dest, artist];
    final album = v.single
        ? KoofrClient.cleanName(v.title)
        : KoofrClient.cleanName(_name(_file(v.trackUrls.first).parent.path));
    return [if (dest != null && dest.isNotEmpty) dest, artist, album.isEmpty ? 'Sin título' : album];
  }

  static String _mime(String name) {
    final n = name.toLowerCase();
    if (n.endsWith('.flac')) return 'audio/flac';
    if (n.endsWith('.mp3')) return 'audio/mpeg';
    if (n.endsWith('.m4a') || n.endsWith('.aac')) return 'audio/mp4';
    if (n.endsWith('.ogg') || n.endsWith('.opus')) return 'audio/ogg';
    if (n.endsWith('.wav')) return 'audio/wav';
    if (n.endsWith('.jpg') || n.endsWith('.jpeg')) return 'image/jpeg';
    if (n.endsWith('.png')) return 'image/png';
    if (n.endsWith('.pdf')) return 'application/pdf';
    return 'application/octet-stream';
  }

  /// Quita «Artista - » del principio del nombre del archivo (conserva el número de pista).
  static String stripArtist(String name, String artist) {
    if (artist.trim().isEmpty) return name;
    final re = RegExp('^((?:\\d{1,3}\\s*[-._)]*\\s*)?)${RegExp.escape(artist.trim())}\\s*[-–—]\\s*', caseSensitive: false);
    final out = name.replaceFirstMapped(re, (m) => m.group(1) ?? '');
    final dot = out.lastIndexOf('.');
    final base = dot < 0 ? out : out.substring(0, dot);
    return base.trim().isEmpty ? name : out;
  }

  /// Archivos a subir con su ruta relativa dentro de la carpeta del disco.
  static Future<List<(File, List<String>)>> _plan(Vinyl v, {bool clean = false}) async {
    String nm(String n) => clean ? stripArtist(n, v.artist) : n;
    if (v.single) {
      return [
        for (final u in v.trackUrls) (_file(u), [nm(_name(_file(u).path))]),
      ];
    }
    final dir = _file(v.trackUrls.first).parent;
    final out = <(File, List<String>)>[];
    await for (final e in dir.list(recursive: true, followLinks: false)) {
      if (e is! File) continue;
      final rel = e.path.substring(dir.path.length).split(RegExp(r'[\\/]')).where((s) => s.isNotEmpty).toList();
      if (rel.isEmpty || rel.last.startsWith('.')) continue;
      if (clean) rel[rel.length - 1] = nm(rel.last);
      out.add((e, rel));
    }
    out.sort((a, b) => a.$2.join('/').compareTo(b.$2.join('/')));
    return out;
  }

  static Future<UploadResult> run(
    Vinyl v,
    KoofrSettings acct, {
    String? dest,
    bool cleanNames = false,
    bool flatSingles = false,
    void Function(String msg, double progress)? onProgress,
  }) async {
    if (!isLocal(v)) throw const KoofrException('Este disco no está en el equipo');
    final client = KoofrClient(acct);
    final base = targetDir(v, dest, flatSingles: flatSingles);
    final files = await _plan(v, clean: cleanNames);
    if (files.isEmpty) throw const KoofrException('No hay archivos para subir');
    var total = 0;
    for (final f in files) {
      total += await f.$1.length();
    }
    var done = 0, up = 0, skip = 0;
    final made = <String>{};
    await client.ensureDir(base);
    for (final f in files) {
      final sub = f.$2.sublist(0, f.$2.length - 1);
      if (sub.isNotEmpty && made.add(sub.join('/'))) await client.ensureDir([...base, ...sub]);
      onProgress?.call(f.$2.last, total == 0 ? 0 : done / total);
      final ok = await client.putFile([...base, ...sub], f.$2.last, f.$1, type: _mime(f.$2.last));
      ok ? up++ : skip++;
      done += await f.$1.length();
    }
    // Verifica que cada archivo en la nube tenga el mismo tamaño que el local antes de dar todo por bueno.
    onProgress?.call('Verificando…', 1);
    final byDir = <String, List<(File, List<String>)>>{};
    for (final f in files) {
      byDir.putIfAbsent(f.$2.sublist(0, f.$2.length - 1).join('/'), () => []).add(f);
    }
    for (final e in byDir.entries) {
      final sub = e.key.isEmpty ? <String>[] : e.key.split('/');
      final remote = {for (final c in await client.browse([...base, ...sub])) c.name: c.size};
      for (final f in e.value) {
        if (remote[f.$2.last] != await f.$1.length()) {
          throw KoofrException('La copia de "${f.$2.last}" en la nube no coincide con la del equipo. No se borró nada.');
        }
      }
    }
    onProgress?.call('Listo', 1);
    final first = files.firstWhere((f) => f.$1.path == _file(v.trackUrls.first).path, orElse: () => files.first);
    return UploadResult(up, skip, [...base, ...first.$2].join('/'));
  }

  /// Borra la copia del equipo (carpeta del álbum o archivos del tema suelto).
  static Future<void> deleteLocal(Vinyl v) async {
    if (v.single) {
      for (final u in v.trackUrls) {
        final f = _file(u);
        if (await f.exists()) await f.delete();
      }
    } else {
      final d = _file(v.trackUrls.first).parent;
      if (await d.exists()) await d.delete(recursive: true);
    }
  }
}
