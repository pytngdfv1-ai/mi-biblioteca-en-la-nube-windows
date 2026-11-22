import 'package:flutter/material.dart';

import '../data/album_json.dart';
import '../data/lyrics.dart';
import '../models/vinyl.dart';
import '../widgets/cover_art.dart';

/// Ficha completa del álbum o tema: metadatos editables (se guardan en album.json de la carpeta),
/// lo que falta, la lista de temas y sus letras. [focus] lleva directo al campo que falta.
class InfoScreen extends StatefulWidget {
  const InfoScreen({super.key, required this.vinyl, this.focus});
  final Vinyl vinyl;
  final String? focus;

  @override
  State<InfoScreen> createState() => _InfoScreenState();
}

class _InfoScreenState extends State<InfoScreen> {
  static const _fields = <(String, String)>[
    ('titulo', 'Título'),
    ('artista', 'Artista'),
    ('año', 'Año'),
    ('sello', 'Sello'),
    ('generos', 'Géneros (separados por coma)'),
    ('pais', 'País'),
  ];

  final _ctl = <String, TextEditingController>{};
  final _nodes = <String, FocusNode>{};
  final _keys = <String, GlobalKey>{};
  late final AlbumJson? _aj = AlbumJson.of(widget.vinyl);
  Map<String, dynamic> _j = {};
  bool _loading = true;
  bool _dirty = false;
  bool _saving = false;

  Vinyl get v => widget.vinyl;

  @override
  void initState() {
    super.initState();
    for (final f in _fields) {
      _ctl[f.$1] = TextEditingController()..addListener(() => _dirty = true);
      _nodes[f.$1] = FocusNode();
      _keys[f.$1] = GlobalKey();
    }
    _keys['letras'] = GlobalKey();
    _keys['portada'] = GlobalKey();
    _load();
  }

  @override
  void dispose() {
    for (final c in _ctl.values) {
      c.dispose();
    }
    for (final n in _nodes.values) {
      n.dispose();
    }
    super.dispose();
  }

  String _asText(dynamic x) => x is List ? x.join(', ') : (x == null || x == 0 ? '' : '$x');

  Future<void> _load() async {
    final j = await _aj?.read() ?? <String, dynamic>{};
    _j = j;
    _ctl['titulo']!.text = _asText(j['titulo']).isEmpty ? v.title : _asText(j['titulo']);
    _ctl['artista']!.text = _asText(j['artista']).isEmpty ? v.artist : _asText(j['artista']);
    _ctl['año']!.text = _asText(j['año']).isEmpty ? (v.year > 0 ? '${v.year}' : '') : _asText(j['año']);
    for (final k in ['sello', 'generos', 'pais']) {
      _ctl[k]!.text = _asText(j[k]);
    }
    if (k0(j['generos']).isEmpty && (v.genre ?? '').isNotEmpty) _ctl['generos']!.text = v.genre!;
    _dirty = false;
    if (mounted) setState(() => _loading = false);
    WidgetsBinding.instance.addPostFrameCallback((_) => _goFocus());
  }

  String k0(dynamic x) => _asText(x);

  void _goFocus() {
    final f = widget.focus;
    if (f == null || !mounted) return;
    final key = _keys[f];
    final ctx = key?.currentContext;
    if (ctx != null) Scrollable.ensureVisible(ctx, duration: const Duration(milliseconds: 300), alignment: .1);
    _nodes[f]?.requestFocus();
  }

  Future<void> _save() async {
    if (_aj == null) return;
    setState(() => _saving = true);
    final ch = <String, dynamic>{
      'titulo': _ctl['titulo']!.text.trim(),
      'artista': _ctl['artista']!.text.trim(),
      'sello': _ctl['sello']!.text.trim(),
      'pais': _ctl['pais']!.text.trim(),
      'generos': [
        for (final g in _ctl['generos']!.text.split(',')) if (g.trim().isNotEmpty) g.trim()
      ],
    };
    final y = int.tryParse(_ctl['año']!.text.trim());
    if (y != null) ch['año'] = y;
    ch.removeWhere((k, val) => val == '' || (val is List && val.isEmpty));
    String msg;
    try {
      final ok = await _aj!.save(ch);
      msg = ok ? 'Guardado en la nube' : 'No se pudo guardar';
      if (ok) _dirty = false;
    } catch (_) {
      msg = 'No se pudo guardar (¿sin conexión?)';
    }
    if (mounted) {
      setState(() => _saving = false);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
    }
  }

  List<String> get _falta {
    final out = <String>[];
    for (final k in ['año', 'sello', 'generos']) {
      if (_ctl[k]!.text.trim().isEmpty) out.add(k);
    }
    if (v.coverUrl == null) out.add('portada');
    final l = (_j['archivos'] as Map?)?['letras'] as Map?;
    if (l != null && ((l['sincronizadas'] ?? 0) as num) + ((l['texto'] ?? 0) as num) == 0) out.add('letras');
    return out;
  }

  void _lyric(String title) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF161816),
      builder: (_) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: .7,
        maxChildSize: .95,
        builder: (_, sc) => FutureBuilder<Lyrics?>(
          future: LyricsService.get(v.artist, title, album: v.single ? null : v.title),
          builder: (_, s) {
            final l = s.data;
            return ListView(controller: sc, padding: const EdgeInsets.all(20), children: [
              Text(title, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
              const SizedBox(height: 12),
              if (s.connectionState != ConnectionState.done)
                const Center(child: CircularProgressIndicator())
              else if (l == null || l.isEmpty)
                const Text('Sin letra disponible para este tema.')
              else
                Text(l.plain.isNotEmpty ? l.plain : l.synced.map((e) => e.text).join('\n'), style: const TextStyle(height: 1.5, fontSize: 15)),
            ]);
          },
        ),
      ),
    );
  }

  Widget _field(String k, String label) => Padding(
        key: _keys[k],
        padding: const EdgeInsets.only(bottom: 10),
        child: TextField(
          controller: _ctl[k],
          focusNode: _nodes[k],
          enabled: _aj != null,
          keyboardType: k == 'año' ? TextInputType.number : TextInputType.text,
          decoration: InputDecoration(
            labelText: label,
            isDense: true,
            border: const OutlineInputBorder(),
            suffixIcon: _ctl[k]!.text.trim().isEmpty ? const Icon(Icons.error_outline, color: Colors.redAccent, size: 18) : null,
          ),
          onChanged: (_) => setState(() {}),
        ),
      );

  @override
  Widget build(BuildContext context) {
    final temas = (_j['temas'] as List?)?.cast<Map>() ?? const <Map>[];
    final falta = _falta;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Información'),
        actions: [
          if (_aj != null)
            TextButton.icon(
              onPressed: (_dirty && !_saving) ? _save : null,
              icon: _saving ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.save_outlined),
              label: const Text('Guardar'),
            ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(padding: const EdgeInsets.all(16), children: [
              Center(key: _keys['portada'], child: SizedBox(width: 180, height: 180, child: CoverArt(vinyl: v, radius: 8))),
              const SizedBox(height: 14),
              if (_aj == null)
                const Padding(
                  padding: EdgeInsets.only(bottom: 12),
                  child: Text('Este disco no está en una nube: solo se puede ver. Súbelo a la nube para editar su ficha.',
                      style: TextStyle(color: Colors.white60, fontSize: 12)),
                ),
              if (falta.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: Wrap(spacing: 6, runSpacing: 4, children: [
                    for (final f in falta)
                      ActionChip(
                        avatar: const Icon(Icons.close, color: Colors.redAccent, size: 16),
                        label: Text('Falta: $f'),
                        onPressed: () {
                          final ctx = _keys[f]?.currentContext;
                          if (ctx != null) Scrollable.ensureVisible(ctx, duration: const Duration(milliseconds: 300), alignment: .1);
                          _nodes[f]?.requestFocus();
                        },
                      ),
                  ]),
                ),
              for (final f in _fields) _field(f.$1, f.$2),
              Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Wrap(spacing: 8, children: [
                  Chip(label: Text(v.single ? 'Tema suelto' : '${v.tracks.length} temas')),
                  if (v.lang != null) Chip(label: Text(v.lang == 'en' ? 'Inglés' : 'Español')),
                  for (final f in ((_j['formatos_audio'] as List?) ?? const [])) Chip(label: Text('$f'.toUpperCase())),
                ]),
              ),
              const Divider(height: 28),
              Text('TEMAS Y LETRAS', key: _keys['letras'], style: const TextStyle(color: Colors.white60, fontSize: 12)),
              const SizedBox(height: 6),
              for (var i = 0; i < v.tracks.length; i++)
                ListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  leading: Text('${i + 1}'),
                  title: Text(v.tracks[i]),
                  subtitle: i < temas.length && temas[i]['duracion_ms'] != null
                      ? Text(_dur((temas[i]['duracion_ms'] as num).toInt()))
                      : null,
                  trailing: IconButton(
                    tooltip: 'Ver letra',
                    icon: const Icon(Icons.lyrics_outlined),
                    onPressed: () => _lyric(v.tracks[i]),
                  ),
                ),
            ]),
    );
  }

  String _dur(int ms) {
    final s = ms ~/ 1000;
    return '${s ~/ 60}:${(s % 60).toString().padLeft(2, '0')}';
  }
}
