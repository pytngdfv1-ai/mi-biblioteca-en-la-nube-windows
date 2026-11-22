import 'vinyl.dart';

/// Imágenes que el agente deja en la carpeta del álbum: foto del sello (vinilo/CD), del cassette
/// y miniatura de la portada. Se reconocen por nombre, no hace falta guardarlas en el modelo.
extension VinylExtras on Vinyl {
  String? _byName(RegExp r) {
    for (final u in booklet) {
      final segs = Uri.parse(u).pathSegments;
      if (segs.isEmpty) continue;
      var n = segs.last;
      try {
        n = Uri.decodeComponent(n);
      } catch (_) {}
      if (r.hasMatch(n)) return u;
    }
    return null;
  }

  /// Foto real del sello central del disco.
  String? get labelUrl => _byName(RegExp(r'^sello\.', caseSensitive: false));

  /// Foto real del cassette de esta edición.
  String? get shellUrl => _byName(RegExp(r'^cassette\.', caseSensitive: false));

  /// Miniatura de 300 px de la portada (para listas).
  String? get thumbUrl {
    for (final u in booklet) {
      if (Uri.decodeFull(Uri.parse(u).removeFragment().path).contains('/Libreto liviano - miniatura/')) return u;
    }
    return null;
  }
}

/// ¿Es una imagen de apoyo del agente (no una página del libreto)?
bool isAgentImage(String url) {
  final segs = Uri.parse(url).pathSegments;
  if (segs.isEmpty) return false;
  var n = segs.last;
  try {
    n = Uri.decodeComponent(n);
  } catch (_) {}
  return RegExp(r'^(sello|cassette)\.', caseSensitive: false).hasMatch(n);
}
