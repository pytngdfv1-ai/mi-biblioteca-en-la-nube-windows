import 'dart:convert';

import 'fetch_bytes.dart';
import 'koofr_settings.dart';

/// Archivos que el agente deja en la nube (_agente/…): índice, versión, etc.
class AgentFiles {
  /// Lee un JSON de la carpeta _agente de la primera cuenta que lo tenga (null si no existe).
  static Future<Map<String, dynamic>?> readJson(String name, {String dir = '_agente'}) async {
    for (final a in KoofrAccounts.list) {
      final f = a.folder.trim();
      for (final folder in {f, f.replaceAll('ú', 'u'), f.replaceAll('u', 'ú'), 'Musica', 'Música'}) {
        try {
          final base = Uri.parse(a.baseUrl);
          final u = base.replace(pathSegments: [
            ...base.pathSegments.where((s) => s.isNotEmpty),
            ...folder.split('/').where((s) => s.isNotEmpty),
            dir,
            name,
          ]);
          final raw = utf8.decode(await fetchBytes(KoofrSettings.tag(u.toString(), a.id)));
          final j = jsonDecode(raw);
          if (j is Map<String, dynamic>) return j;
        } catch (_) {}
      }
    }
    return null;
  }
}

/// Índice del agente (indice.json): años y faltantes de cada álbum ya calculados.
class AgentIndex {
  static Map<String, int>? _years;
  static List<Map<String, dynamic>>? _entries;

  static String fold(String s) {
    const from = 'áàäâãéèëêíìïîóòöôõúùüûñç';
    const to = 'aaaaaeeeeiiiiooooouuuunc';
    var t = s.toLowerCase();
    for (var i = 0; i < from.length; i++) {
      t = t.replaceAll(from[i], to[i]);
    }
    return t.replaceAll(RegExp(r'[^a-z0-9]'), '');
  }

  static String key(String artist, String title) => '${fold(artist)}|${fold(title)}';

  /// Todos los álbumes del índice (vacío si el agente aún no lo generó).
  static Future<List<Map<String, dynamic>>> entries({bool refresh = false}) async {
    if (_entries != null && !refresh) return _entries!;
    final j = await AgentFiles.readJson('indice.json');
    final list = <Map<String, dynamic>>[
      for (final e in (j?['albums'] as List? ?? const [])) if (e is Map) e.cast<String, dynamic>(),
    ];
    if (j != null) _entries = list;
    return list;
  }

  /// Mapa artista|título → año.
  static Future<Map<String, int>> years() async {
    if (_years != null) return _years!;
    final out = <String, int>{};
    for (final e in await entries()) {
      final y = (e['año'] as num?)?.toInt() ?? 0;
      if (y > 0) out[key('${e['artista']}', '${e['titulo']}')] = y;
    }
    if (out.isNotEmpty) _years = out;
    return out;
  }
}
