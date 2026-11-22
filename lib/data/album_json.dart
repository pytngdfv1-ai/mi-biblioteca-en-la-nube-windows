import 'dart:convert';
import 'dart:typed_data';

import '../models/vinyl.dart';
import 'fetch_bytes.dart';
import 'koofr_client.dart';
import 'koofr_settings.dart';
import 'library_order.dart';

/// album.json de la carpeta de un álbum en la nube: lectura y edición a mano.
/// El agente respeta lo que se edita aquí (nunca pisa valores ya escritos).
class AlbumJson {
  AlbumJson(this.account, this.client, this.dir);

  final KoofrSettings account;
  final KoofrClient client;
  final List<String> dir; // carpeta del álbum, relativa a la carpeta raíz

  static KoofrSettings? accountOf(Vinyl v) {
    for (final a in KoofrAccounts.list) {
      if (sourceInAccount(v.source, a.id)) return a;
    }
    return null;
  }

  static AlbumJson? of(Vinyl v) {
    final a = accountOf(v);
    if (a == null || v.trackUrls.isEmpty) return null;
    final c = KoofrClient(a);
    final rel = c.relSegments(v.trackUrls.first);
    if (rel.length < 2) return null;
    return AlbumJson(a, c, rel.sublist(0, rel.length - 1));
  }

  /// Carpeta del álbum normalizada (para casar con la ruta del índice del agente).
  static String norm(Iterable<String> segs) => segs.map((s) => s.toLowerCase()).join('/');

  Future<Map<String, dynamic>> read() async {
    try {
      final raw = utf8.decode(await fetchBytes(KoofrSettings.tag(client.urlOf([...dir, 'album.json']), account.id)));
      final j = jsonDecode(raw);
      return j is Map<String, dynamic> ? j : <String, dynamic>{};
    } catch (_) {
      return <String, dynamic>{};
    }
  }

  /// Guarda los cambios sobre el album.json existente (conserva el resto de claves).
  Future<bool> save(Map<String, dynamic> changes) async {
    final cur = await read();
    cur.addAll(changes);
    final bytes = Uint8List.fromList(utf8.encode(const JsonEncoder.withIndent('  ').convert(cur)));
    return client.putBytes(dir, 'album.json', bytes, type: 'application/json');
  }
}
