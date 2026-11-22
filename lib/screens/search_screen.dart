import 'package:flutter/material.dart';

import '../data/agent_index.dart';
import '../data/vinyl_store.dart';
import '../models/vinyl.dart';
import '../theme.dart';
import '../widgets/cover_art.dart';
import '../data/cajon.dart';
import 'crate_screen.dart';
import 'library_actions.dart';

/// Buscador general: discos por artista o título, y temas por nombre.
class SearchScreen extends StatefulWidget {
  const SearchScreen({super.key, required this.store});
  final VinylStore store;

  @override
  State<SearchScreen> createState() => _SearchScreenState();
}

class _Hit {
  const _Hit(this.v, this.track);
  final Vinyl v;

  /// Índice del tema encontrado (null = el resultado es el disco).
  final int? track;
}

class _Lyr {
  const _Lyr(this.v, this.tema, this.frag);
  final Vinyl v;
  final String tema;
  final String frag;
}

class _SearchScreenState extends State<SearchScreen> {
  final _c = TextEditingController();
  String _q = '';

  /// Índice del agente (sello, país, géneros, letras) por artista|título.
  Map<String, Map<String, dynamic>> _extra = {};

  @override
  void initState() {
    super.initState();
    _loadExtra();
  }

  Future<void> _loadExtra() async {
    try {
      final j = await AgentFiles.readJson('buscar.json');
      final m = <String, Map<String, dynamic>>{};
      for (final e in (j?['albums'] as List? ?? const [])) {
        if (e is Map) m[AgentIndex.key('${e['artista']}', '${e['titulo']}')] = e.cast<String, dynamic>();
      }
      if (mounted && m.isNotEmpty) setState(() => _extra = m);
    } catch (_) {}
  }

  static String _n(String s) {
    const from = 'áàäâãéèëêíìïîóòöôõúùüûñç';
    const to = 'aaaaaeeeeiiiiooooouuuunc';
    var t = s.toLowerCase();
    for (var i = 0; i < from.length; i++) {
      t = t.replaceAll(from[i], to[i]);
    }
    return t.replaceAll(RegExp(r'\s+'), ' ').trim();
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  (List<_Hit>, List<_Hit>, List<_Lyr>) _search() {
    final words = _n(_q).split(' ').where((w) => w.isNotEmpty).toList();
    if (words.isEmpty) return (const [], const [], const []);
    bool all(String hay) => words.every(hay.contains);
    final discs = <_Hit>[];
    final tracks = <_Hit>[];
    final lyrics = <_Lyr>[];
    final seen = <String>{};
    for (final v in widget.store.items) {
      if (v.isDivider || !seen.add(v.id)) continue;
      final x = _extra[AgentIndex.key(v.artist, v.title)];
      final meta = x == null ? '' : ' ${x['sello'] ?? ''} ${x['pais'] ?? ''} ${(x['generos'] as List? ?? const []).join(' ')}';
      if (all(_n('${v.artist} ${v.title} ${v.genre ?? ''} ${v.year > 0 ? v.year : ''}$meta'))) {
        discs.add(_Hit(v, null));
      }
      if (x != null && lyrics.length < 40) {
        for (final l in (x['letras'] as List? ?? const [])) {
          if (l is! Map) continue;
          final raw = '${l['texto']}';
          final t = _n(raw);
          if (!all(t)) continue;
          final at = t.indexOf(words.first);
          final from = (at - 30).clamp(0, t.length);
          final to = (at + 70).clamp(0, t.length);
          lyrics.add(_Lyr(v, '${l['tema']}', '…${t.substring(from, to)}…'));
          break;
        }
      }
      for (var i = 0; i < v.tracks.length && tracks.length < 80; i++) {
        if (!v.hasAudio) break;
        if (all(_n('${v.tracks[i]} ${v.artist}'))) tracks.add(_Hit(v, i));
      }
    }
    discs.sort((a, b) => a.v.artist.toLowerCase().compareTo(b.v.artist.toLowerCase()));
    return (discs.take(60).toList(), tracks, lyrics);
  }

  /// Abre la biblioteca (anillo) que contiene el disco, posicionada en él; no reproduce.
  void _showInLibrary(Vinyl v) {
    final c = Cajon.all.where((c) => c.matches(v)).firstOrNull;
    if (c == null) {
      openStage(context, widget.store, v);
      return;
    }
    Navigator.of(context).push(MaterialPageRoute<void>(
      builder: (_) => CrateScreen(store: widget.store, cajon: c, title: c.name, focusId: v.id),
    ));
  }

  @override
  Widget build(BuildContext context) {
    final (discs, tracks, lyrics) = _search();
    return Scaffold(
      backgroundColor: AppColors.ink,
      appBar: AppBar(
        backgroundColor: AppColors.ink,
        title: TextField(
          controller: _c,
          autofocus: true,
          textInputAction: TextInputAction.search,
          decoration: InputDecoration(
            hintText: 'Buscar artista, disco, tema, sello, letra…',
            border: InputBorder.none,
            suffixIcon: _q.isEmpty
                ? null
                : IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: () => setState(() {
                      _c.clear();
                      _q = '';
                    }),
                  ),
          ),
          onChanged: (t) => setState(() => _q = t),
        ),
      ),
      body: _q.trim().isEmpty
          ? const Center(
              child: Padding(
                padding: EdgeInsets.all(32),
                child: Text('Escribe para buscar en toda tu biblioteca.',
                    textAlign: TextAlign.center, style: TextStyle(color: Colors.white60)),
              ),
            )
          : (discs.isEmpty && tracks.isEmpty && lyrics.isEmpty)
              ? const Center(child: Text('Sin resultados', style: TextStyle(color: Colors.white60)))
              : ListView(
                  children: [
                    if (discs.isNotEmpty) _head('Discos (${discs.length})'),
                    for (final h in discs)
                      ListTile(
                        leading: SizedBox(width: 48, height: 48, child: CoverArt(vinyl: h.v)),
                        title: Text(h.v.title, maxLines: 1, overflow: TextOverflow.ellipsis),
                        subtitle: Text('${h.v.artist}${h.v.year > 0 ? ' · ${h.v.year}' : ''}',
                            maxLines: 1, overflow: TextOverflow.ellipsis),
                        onTap: () => _showInLibrary(h.v),
                      ),
                    if (tracks.isNotEmpty) _head('Temas (${tracks.length})'),
                    for (final h in tracks)
                      ListTile(
                        leading: SizedBox(width: 48, height: 48, child: CoverArt(vinyl: h.v)),
                        title: Text(h.v.tracks[h.track!], maxLines: 1, overflow: TextOverflow.ellipsis),
                        subtitle: Text('${h.v.artist} · ${h.v.title}', maxLines: 1, overflow: TextOverflow.ellipsis),
                        trailing: const Icon(Icons.library_music_outlined),
                        onTap: () => _showInLibrary(h.v),
                      ),
                    if (lyrics.isNotEmpty) _head('Letras (${lyrics.length})'),
                    for (final l in lyrics)
                      ListTile(
                        leading: SizedBox(width: 48, height: 48, child: CoverArt(vinyl: l.v)),
                        title: Text('${l.tema} · ${l.v.artist}', maxLines: 1, overflow: TextOverflow.ellipsis),
                        subtitle: Text(l.frag, maxLines: 2, overflow: TextOverflow.ellipsis),
                        trailing: const Icon(Icons.lyrics_outlined),
                        onTap: () => _showInLibrary(l.v),
                      ),
                  ],
                ),
    );
  }

  Widget _head(String t) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 4),
        child: Text(t.toUpperCase(),
            style: const TextStyle(color: AppColors.gold, fontSize: 12, letterSpacing: 1, fontWeight: FontWeight.w600)),
      );
}
