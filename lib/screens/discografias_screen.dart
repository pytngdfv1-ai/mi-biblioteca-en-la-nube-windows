import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../data/agent_index.dart';
import '../data/vinyl_store.dart';

/// Discografías: lista desplegable por artista con todos sus álbumes y sus temas.
/// Los datos los deja el agente 3D en _agente3d/discografias.json; lo que tienes se calcula
/// aquí, tema por tema, contra tu biblioteca (álbumes y temas sueltos):
/// ✓ verde = álbum completo · punto amarillo con ✓ = parcial · ✗ = nada.
/// Los temas que te faltan se pueden marcar y exportar como lista («Artista – Tema») para
/// pegarla en un importador a Spotify, o buscarlos uno a uno en Spotify.
class DiscografiasScreen extends StatefulWidget {
  const DiscografiasScreen({super.key, required this.store});

  final VinylStore store;

  @override
  State<DiscografiasScreen> createState() => _DiscografiasScreenState();
}

/// Qué temas y álbumes de la biblioteca coinciden con la discografía (sin tildes ni mayúsculas).
class _Own {
  _Own(VinylStore store) {
    for (final v in store.items) {
      if (v.isDivider) continue;
      final a = AgentIndex.fold(v.artist);
      final t = _tracks.putIfAbsent(a, () => <String>{});
      for (final tr in v.tracks) {
        final k = _key(tr);
        if (k.isNotEmpty) t.add(k);
      }
      if (!v.single && !v.cassette) {
        (_albums.putIfAbsent(a, () => <String>{})).add(AgentIndex.fold(v.title));
      }
    }
  }

  final Map<String, Set<String>> _tracks = {};
  final Map<String, Set<String>> _albums = {};

  /// Quita el número de pista y extensión del nombre ("01 - Tema.mp3" → "tema").
  static String _key(String s) {
    var t = s.replaceAll(RegExp(r'\.(mp3|flac|m4a|wav|ogg|opus|aac|wma)$', caseSensitive: false), '');
    t = t.replaceFirst(RegExp(r'^\s*\d{1,3}\s*[-._)]*\s*'), '');
    return AgentIndex.fold(t);
  }

  Iterable<String> _artistKeys(String artist) {
    final k = AgentIndex.fold(artist);
    return {..._tracks.keys, ..._albums.keys}.where((x) => x.isNotEmpty && k.isNotEmpty && (x == k || (k.length >= 4 && x.length >= 4 && (x.contains(k) || k.contains(x)))));
  }

  bool hasTrack(String artist, String tema) {
    final k = _key(tema);
    if (k.isEmpty) return false;
    for (final a in _artistKeys(artist)) {
      final set = _tracks[a];
      if (set != null && set.contains(k)) return true;
    }
    return false;
  }

  bool hasAlbum(String artist, String titulo) {
    final k = AgentIndex.fold(titulo);
    if (k.isEmpty) return false;
    for (final a in _artistKeys(artist)) {
      if (_albums[a]?.contains(k) ?? false) return true;
    }
    return false;
  }

  /// (temas que tienes, temas totales, estado: 0 nada · 1 parcial · 2 completo).
  (int, int, int) status(String artist, Map<String, dynamic> al) {
    final temas = ((al['temas'] as List?) ?? const []).map((e) => '$e').toList();
    final albumEnBiblioteca = hasAlbum(artist, '${al['titulo']}');
    if (temas.isEmpty) return (albumEnBiblioteca ? 1 : 0, 1, albumEnBiblioteca ? 2 : 0);
    var n = 0;
    for (final t in temas) {
      if (albumEnBiblioteca || hasTrack(artist, t)) n++;
    }
    return (n, temas.length, n == 0 ? 0 : (n == temas.length ? 2 : 1));
  }
}

class _DiscografiasScreenState extends State<DiscografiasScreen> {
  late final _Own _own = _Own(widget.store);
  final Set<String> _sel = <String>{};

  static const _importador = 'https://www.tunemymusic.com/es/transfer';

  bool _tiene(String artista, Map<String, dynamic> al, String t) => _own.hasTrack(artista, t) || _own.hasAlbum(artista, '${al['titulo']}');

  void _toggle(String key, bool on) => setState(() => on ? _sel.add(key) : _sel.remove(key));

  void _toggleMany(List<String> keys, bool on) => setState(() => on ? _sel.addAll(keys) : _sel.removeAll(keys));

  /// Todos los temas que faltan de los artistas visibles.
  void _marcarTodoLoQueFalta(List<Map<String, dynamic>> shown) {
    final keys = <String>[];
    for (final a in shown) {
      final artista = '${a['artista']}';
      for (final al in ((a['albumes'] as List?) ?? const []).whereType<Map>()) {
        final m = al.cast<String, dynamic>();
        for (final t in ((m['temas'] as List?) ?? const [])) {
          if (!_tiene(artista, m, '$t')) keys.add('$artista – $t');
        }
      }
    }
    setState(() => _sel.addAll(keys));
    _aviso(keys.isEmpty ? 'No te falta ningún tema aquí' : '${keys.length} temas marcados');
  }

  void _aviso(String t) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(t)));
  }

  String get _texto => _sel.join('\n');

  Future<void> _copiar() async {
    await Clipboard.setData(ClipboardData(text: _texto));
    _aviso('Lista copiada (${_sel.length} temas). Pégala en el importador.');
  }

  Future<void> _guardar() async {
    try {
      Directory dir = Directory('${Platform.environment['USERPROFILE'] ?? ''}\\Downloads');
      if (!dir.existsSync()) dir = (await getDownloadsDirectory()) ?? await getApplicationDocumentsDirectory();
      var f = File('${dir.path}/Temas_que_me_faltan.txt');
      var n = 2;
      while (f.existsSync()) {
        f = File('${dir.path}/Temas_que_me_faltan_$n.txt');
        n++;
      }
      await f.writeAsString(_texto);
      _aviso('Guardado: ${f.path}');
    } catch (e) {
      _aviso('No se pudo guardar: $e');
    }
  }

  Future<void> _abrir(String url) async {
    var ok = false;
    try {
      ok = await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
    } catch (_) {}
    if (!ok) {
      await Clipboard.setData(ClipboardData(text: url));
      _aviso('Enlace copiado: pégalo en el navegador');
    }
  }

  bool _loading = true;
  List<Map<String, dynamic>> _artists = [];
  String _q = '';
  bool _soloFaltan = false;
  String _actualizado = '';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final j = await AgentFiles.readJson('discografias.json', dir: '_agente3d');
    final list = ((j?['artistas'] as List?) ?? const []).whereType<Map>().map((e) => e.cast<String, dynamic>()).toList();
    list.sort((a, b) => AgentIndex.fold('${a['artista']}').compareTo(AgentIndex.fold('${b['artista']}')));
    if (!mounted) return;
    setState(() {
      _artists = list;
      _actualizado = '${j?['actualizado'] ?? ''}';
      _loading = false;
    });
  }

  // ---- Buscador inteligente: sin tildes ni símbolos, por palabras, tolera errores de tipeo ----
  static int _dist(String a, String b) {
    if (a == b) return 0;
    final p = List<int>.generate(b.length + 1, (i) => i);
    for (var i = 1; i <= a.length; i++) {
      var prev = p[0];
      p[0] = i;
      for (var j = 1; j <= b.length; j++) {
        final tmp = p[j];
        p[j] = [p[j] + 1, p[j - 1] + 1, prev + (a[i - 1] == b[j - 1] ? 0 : 1)].reduce((x, y) => x < y ? x : y);
        prev = tmp;
      }
    }
    return p[b.length];
  }

  static String _f(String s) => AgentIndex.fold(s);

  static List<String> _words(String s) {
    const from = 'áàäâãéèëêíìïîóòöôõúùüûñç';
    const to = 'aaaaaeeeeiiiiooooouuuunc';
    var t = s.toLowerCase();
    for (var i = 0; i < from.length; i++) {
      t = t.replaceAll(from[i], to[i]);
    }
    return t.split(RegExp(r'[^a-z0-9]+')).where((w) => w.isNotEmpty).toList();
  }

  /// ¿Coincide la palabra de búsqueda con alguna palabra del texto? (prefijo, contenida o a 1–2 letras de distancia)
  static bool _hit(String w, List<String> words, String folded) {
    if (folded.contains(w)) return true;
    if (w.length < 4) return false;
    final tol = w.length >= 7 ? 2 : 1;
    for (final x in words) {
      if ((x.length - w.length).abs() <= tol && _dist(w, x) <= tol) return true;
      if (x.length > w.length && _dist(w, x.substring(0, w.length)) <= (w.length >= 6 ? 1 : 0)) return true;
    }
    return false;
  }

  static bool _match(List<String> qs, String text) {
    final words = _words(text);
    final folded = _f(text);
    return qs.every((w) => _hit(w, words, folded));
  }

  /// Devuelve el artista filtrado (null si no coincide). Si la búsqueda acierta en un álbum o tema, solo deja esos.
  Map<String, dynamic>? _filtrar(Map<String, dynamic> a) {
    final albums = ((a['albumes'] as List?) ?? const []).whereType<Map>().map((e) => e.cast<String, dynamic>()).toList();
    final nombreArtista = '${a['artista']}';
    var base = _soloFaltan ? albums.where((x) => _own.status(nombreArtista, x).$3 != 2).toList() : albums;
    if (_soloFaltan && base.isEmpty) return null;
    final qs = _words(_q);
    if (qs.isEmpty) return {...a, 'albumes': base};
    final nombre = '${a['artista']}';
    if (_match(qs, nombre)) return {...a, 'albumes': base};
    final hit = <Map<String, dynamic>>[];
    for (final al in base) {
      final temas = ((al['temas'] as List?) ?? const []).map((e) => '$e').toList();
      final t = '${al['titulo']} ${al['año'] ?? ''} $nombre';
      if (_match(qs, t) || temas.any((x) => _match(qs, '$x $nombre'))) hit.add(al);
    }
    return hit.isEmpty ? null : {...a, 'albumes': hit};
  }

  @override
  Widget build(BuildContext context) {
    final shown = <Map<String, dynamic>>[];
    for (final a in _artists) {
      final f = _filtrar(a);
      if (f != null) shown.add(f);
    }
    final searching = _q.trim().isNotEmpty;
    var falta = 0;
    for (final a in _artists) {
      for (final al in ((a['albumes'] as List?) ?? const []).whereType<Map>()) {
        final st = _own.status('${a['artista']}', al.cast<String, dynamic>());
        falta += st.$2 - st.$1;
      }
    }
    return Scaffold(
      appBar: AppBar(
        title: const Text('Discografías'),
        actions: [
          PopupMenuButton<String>(
            tooltip: 'Lista para Spotify',
            icon: const Icon(Icons.playlist_add),
            onSelected: (v) {
              if (v == 'todo') _marcarTodoLoQueFalta(shown);
              if (v == 'quitar') setState(_sel.clear);
            },
            itemBuilder: (_) => const [
              PopupMenuItem(value: 'todo', child: Text('Marcar todo lo que me falta (lo que se ve)')),
              PopupMenuItem(value: 'quitar', child: Text('Quitar todas las marcas')),
            ],
          ),
        ],
      ),
      bottomNavigationBar: _sel.isEmpty
          ? null
          : Material(
              color: const Color(0xFF17171C),
              child: SafeArea(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  child: Row(children: [
                    Expanded(child: Text('${_sel.length} temas marcados', style: const TextStyle(fontSize: 13))),
                    TextButton(onPressed: _copiar, child: const Text('Copiar')),
                    TextButton(onPressed: _guardar, child: const Text('.txt')),
                    TextButton(onPressed: () => _abrir(_importador), child: const Text('Importar')),
                    IconButton(tooltip: 'Quitar marcas', icon: const Icon(Icons.close), onPressed: () => setState(_sel.clear)),
                  ]),
                ),
              ),
            ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _artists.isEmpty
              ? const Center(
                  child: Padding(
                    padding: EdgeInsets.all(24),
                    child: Text('Aún no hay discografías. El agente las va generando poco a poco en cada corrida.', textAlign: TextAlign.center),
                  ),
                )
              : Column(children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
                    child: TextField(
                      decoration: const InputDecoration(
                        prefixIcon: Icon(Icons.search),
                        hintText: 'Artista, álbum, tema o año',
                        isDense: true,
                        border: OutlineInputBorder(),
                      ),
                      onChanged: (t) => setState(() => _q = t),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    child: Row(children: [
                      FilterChip(label: const Text('Solo lo que me falta'), selected: _soloFaltan, onSelected: (v) => setState(() => _soloFaltan = v)),
                      const Spacer(),
                      Text('${_artists.length} artistas · faltan $falta', style: const TextStyle(fontSize: 12, color: Colors.white60)),
                    ]),
                  ),
                  Expanded(
                    child: shown.isEmpty
                        ? const Center(child: Text('Sin resultados'))
                        : ListView.builder(
                            itemCount: shown.length,
                            itemBuilder: (_, i) => _ArtistTile(a: shown[i], open: searching, own: _own, sel: _sel, onToggle: _toggle, onToggleMany: _toggleMany, onSearch: (q) => _abrir('https://open.spotify.com/search/${Uri.encodeComponent(q)}')),
                          ),
                  ),
                  if (_actualizado.isNotEmpty)
                    Padding(padding: const EdgeInsets.all(4), child: Text('Actualizado $_actualizado', style: const TextStyle(fontSize: 10, color: Colors.white38))),
                ]),
    );
  }
}

class _ArtistTile extends StatelessWidget {
  const _ArtistTile({
    required this.a,
    required this.open,
    required this.own,
    required this.sel,
    required this.onToggle,
    required this.onToggleMany,
    required this.onSearch,
  });
  final Map<String, dynamic> a;
  final bool open;
  final _Own own;
  final Set<String> sel;
  final void Function(String key, bool on) onToggle;
  final void Function(List<String> keys, bool on) onToggleMany;
  final void Function(String query) onSearch;

  static const _verde = Color(0xFF7BD88F);
  static const _amarillo = Color(0xFFFFD54F);

  List<String> _faltan(String artista, Map<String, dynamic> al) => [
        for (final t in ((al['temas'] as List?) ?? const []))
          if (!(own.hasTrack(artista, '$t') || own.hasAlbum(artista, '${al['titulo']}'))) '$t',
      ];

  Widget _tema(String artista, Map<String, dynamic> al, int i, String t) {
    final tiene = own.hasTrack(artista, t) || own.hasAlbum(artista, '${al['titulo']}');
    final key = '$artista – $t';
    return ListTile(
      dense: true,
      contentPadding: const EdgeInsets.only(left: 64, right: 8),
      title: Text('${i + 1}. $t', style: TextStyle(fontSize: 13, color: tiene ? null : Colors.white54)),
      trailing: tiene
          ? const Padding(padding: EdgeInsets.only(right: 8), child: Icon(Icons.check, color: _verde, size: 18))
          : SizedBox(
              width: 96,
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                IconButton(
                  tooltip: 'Buscar en Spotify',
                  visualDensity: VisualDensity.compact,
                  icon: const Icon(Icons.search, size: 20),
                  onPressed: () => onSearch('$artista $t'),
                ),
                Checkbox(value: sel.contains(key), visualDensity: VisualDensity.compact, onChanged: (v) => onToggle(key, v ?? false)),
              ]),
            ),
      onTap: tiene ? null : () => onToggle(key, !sel.contains(key)),
    );
  }

  Widget _icono(int estado) {
    if (estado == 2) return const Icon(Icons.check_circle, color: _verde, size: 20);
    if (estado == 1) {
      return const SizedBox(
        width: 28,
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(Icons.circle, color: _amarillo, size: 9),
          SizedBox(width: 2),
          Icon(Icons.check, color: _amarillo, size: 16),
        ]),
      );
    }
    return const Icon(Icons.cancel_outlined, color: Color(0xFFFF8A80), size: 20);
  }

  @override
  Widget build(BuildContext context) {
    final albums = ((a['albumes'] as List?) ?? const []).whereType<Map>().map((e) => e.cast<String, dynamic>()).toList();
    final artista = '${a['artista']}';
    var tienes = 0, total = 0, completos = 0;
    for (final al in albums) {
      final st = own.status(artista, al);
      tienes += st.$1;
      total += st.$2;
      if (st.$3 == 2) completos++;
    }
    final parcial = a['parcial'] == true;
    return ExpansionTile(
      key: PageStorageKey('${a['artista']}$open'),
      initiallyExpanded: open,
      title: Text('${a['artista']}', maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w700)),
      subtitle: Text('Tienes $tienes de $total temas · $completos de ${albums.length} álbumes completos${parcial ? ' (en proceso)' : ''}', style: const TextStyle(fontSize: 12)),
      children: [
        for (final al in albums)
          ExpansionTile(
            tilePadding: const EdgeInsets.only(left: 24, right: 16),
            leading: _icono(own.status(artista, al).$3),
            title: Text('${al['titulo']}', maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 14)),
            subtitle: Text('${al['año'] ?? ''}${al['tipo'] == 'ep' ? ' · EP' : al['tipo'] == 'single' ? ' · single' : ''}${own.status(artista, al).$3 == 1 ? ' · tienes ${own.status(artista, al).$1} de ${own.status(artista, al).$2} temas' : ''}', style: const TextStyle(fontSize: 11)),
            children: [
              if (_faltan(artista, al).isNotEmpty)
                Builder(builder: (_) {
                  final keys = [for (final t in _faltan(artista, al)) '$artista – $t'];
                  final todos = keys.every(sel.contains);
                  return ListTile(
                    dense: true,
                    contentPadding: const EdgeInsets.only(left: 64, right: 16),
                    leading: null,
                    title: Text(todos ? 'Quitar marcas de este álbum' : 'Marcar lo que falta de este álbum (${keys.length})', style: const TextStyle(fontSize: 12, color: _amarillo)),
                    onTap: () => onToggleMany(keys, !todos),
                  );
                }),
              for (final (i, t) in ((al['temas'] as List?) ?? const []).indexed)
                _tema(artista, al, i, '$t'),
              if (((al['temas'] as List?) ?? const []).isEmpty)
                const ListTile(dense: true, contentPadding: EdgeInsets.only(left: 64), title: Text('Temas pendientes de cargar', style: TextStyle(fontSize: 12, color: Colors.white38))),
            ],
          ),
      ],
    );
  }
}
