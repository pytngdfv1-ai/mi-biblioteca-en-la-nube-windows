import 'dart:convert';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../data/agent_index.dart';
import '../data/album_json.dart';
import '../data/fetch_bytes.dart';
import '../data/koofr_settings.dart';
import '../data/vinyl_store.dart';
import '../models/vinyl.dart';
import '../widgets/cover_art.dart';
import '../widgets/sprite_object.dart';

/// Ajustes → Objetos 3D: los álbumes que el agente 3D ya procesó; toca uno para verlo.
class AgentObjectsScreen extends StatefulWidget {
  const AgentObjectsScreen({super.key, required this.store});
  final VinylStore store;

  @override
  State<AgentObjectsScreen> createState() => _AgentObjectsScreenState();
}

class _AgentObjectsScreenState extends State<AgentObjectsScreen> {
  bool _loading = true;
  final List<(Vinyl, String)> _items = [];
  String _q = '';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final j = await AgentFiles.readJson('objetos.json', dir: '_agente3d');
    final byDir = <String, String>{
      for (final e in (j ?? const {}).entries)
        if (e.value is Map && ((e.value as Map)['estado'] == 'hecho' || (e.value as Map)['estado'] == 'salta' || (e.value as Map)['estado'] == 'espera'))
          AlbumJson.norm(e.key.split('/').where((x) => x.isNotEmpty)): '${(e.value as Map)['estado']}',
    };
    for (final v in widget.store.items) {
      if (v.isDivider) continue;
      final d = AlbumJson.of(v)?.dir;
      final st = d == null ? null : byDir[AlbumJson.norm(d)];
      if (st != null) _items.add((v, st));
    }
    _items.sort((a, b) => '${a.$1.artist} ${a.$1.title}'.toLowerCase().compareTo('${b.$1.artist} ${b.$1.title}'.toLowerCase()));
    if (mounted) setState(() => _loading = false);
  }

  @override
  Widget build(BuildContext context) {
    final q = _q.toLowerCase();
    final list = [for (final e in _items) if (q.isEmpty || '${e.$1.artist} ${e.$1.title}'.toLowerCase().contains(q)) e];
    return Scaffold(
      appBar: AppBar(title: const Text('Objetos 3D')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _items.isEmpty
              ? const Padding(
                  padding: EdgeInsets.all(24),
                  child: Center(
                      child: Text('El agente 3D aún no generó objetos (o no están sincronizados).\nSe crean solos 4 veces al día.',
                          textAlign: TextAlign.center)),
                )
              : Column(children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
                    child: TextField(
                      decoration: const InputDecoration(prefixIcon: Icon(Icons.search), hintText: 'Buscar', isDense: true, border: OutlineInputBorder()),
                      onChanged: (t) => setState(() => _q = t),
                    ),
                  ),
                  Expanded(
                    child: ListView.builder(
                      itemCount: list.length,
                      itemBuilder: (_, i) {
                        final (v, st) = list[i];
                        return ListTile(
                          leading: SizedBox(width: 48, height: 48, child: CoverArt(vinyl: v, radius: 4)),
                          title: Text(v.title, maxLines: 1, overflow: TextOverflow.ellipsis),
                          subtitle: Text(st == 'espera' ? '${v.artist} · solo cassette (falta contraportada)' : v.artist),
                          onTap: () => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => AgentObjectViewer(vinyl: v))),
                        );
                      },
                    ),
                  ),
                ]),
    );
  }
}

/// Visor de los objetos del álbum (LP, 7", cassette): cerrado ↔ abierto con un toque.
class AgentObjectViewer extends StatefulWidget {
  const AgentObjectViewer({super.key, required this.vinyl});
  final Vinyl vinyl;

  @override
  State<AgentObjectViewer> createState() => _AgentObjectViewerState();
}

class _AgentObjectViewerState extends State<AgentObjectViewer> {
  Map<String, dynamic>? _man;
  bool _loadingMan = true;
  String? _obj;
  bool _open = false;
  ui.Image? _img;
  bool _loadingImg = false;
  final Map<String, ui.Image> _cache = {};

  Vinyl get v => widget.vinyl;
  late final AlbumJson? _aj = AlbumJson.of(v);

  static const _names = {'lp': 'LP 12"', '7': 'Vinilo 7"', 'cassette': 'Cassette'};

  @override
  void initState() {
    super.initState();
    _loadMan();
  }

  Future<void> _loadMan() async {
    try {
      final aj = _aj;
      if (aj != null) {
        final raw = utf8.decode(await fetchBytes(KoofrSettings.tag(aj.client.urlOf([...aj.dir, 'objeto3d.json']), aj.account.id)));
        _man = jsonDecode(raw) as Map<String, dynamic>;
        final keys = ((_man!['objetos'] as Map?) ?? const {}).keys.cast<String>().toList();
        _obj = keys.contains(v.isTape ? 'cassette' : 'lp') ? (v.isTape ? 'cassette' : 'lp') : (keys.isEmpty ? null : keys.first);
      }
    } catch (_) {}
    if (mounted) setState(() => _loadingMan = false);
    await _loadImg();
  }

  Future<void> _loadImg() async {
    final aj = _aj;
    final obj = _obj;
    if (aj == null || obj == null || _man == null) return;
    final file = (((_man!['objetos'] as Map)[obj] as Map)[_open ? 'abierto' : 'cerrado']) as String?;
    if (file == null) return;
    final key = '$obj/$file';
    if (_cache[key] != null) {
      setState(() => _img = _cache[key]);
      return;
    }
    setState(() => _loadingImg = true);
    try {
      final bytes = await fetchBytes(KoofrSettings.tag(aj.client.urlOf([...aj.dir, file]), aj.account.id));
      final im = await decodeImageFromList(bytes);
      _cache[key] = im;
      if (mounted && '${_obj}/${(((_man!['objetos'] as Map)[_obj] as Map)[_open ? 'abierto' : 'cerrado'])}' == key) setState(() => _img = im);
    } catch (_) {
      if (mounted) setState(() => _img = null);
    }
    if (mounted) setState(() => _loadingImg = false);
  }

  String get _verbo => _obj == 'cassette' ? (_open ? 'Cerrar estuche' : 'Abrir estuche y sacar cassette') : (_open ? 'Guardar el disco' : 'Sacar el disco');

  @override
  Widget build(BuildContext context) {
    final objs = ((_man?['objetos'] as Map?) ?? const {}).keys.cast<String>().toList();
    return Scaffold(
      appBar: AppBar(title: Text(v.title, maxLines: 1, overflow: TextOverflow.ellipsis)),
      body: _loadingMan
          ? const Center(child: CircularProgressIndicator())
          : _man == null || objs.isEmpty
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(mainAxisSize: MainAxisSize.min, children: [
                      SizedBox(width: 200, height: 200, child: CoverArt(vinyl: v, radius: 8)),
                      const SizedBox(height: 16),
                      const Text('El agente aún no generó los objetos de este álbum.', textAlign: TextAlign.center),
                    ]),
                  ),
                )
              : Column(children: [
                  Expanded(
                    child: Center(
                      child: _img == null
                          ? const CircularProgressIndicator()
                          : SpriteObject(
                              image: _img!,
                              frames: (_man!['cuadros'] as num?)?.toInt() ?? 16,
                              cols: (_man!['columnas'] as num?)?.toInt() ?? 4,
                              onTap: () {
                                setState(() => _open = !_open);
                                _loadImg();
                              },
                            ),
                    ),
                  ),
                  if (_loadingImg) const LinearProgressIndicator(minHeight: 2),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                    child: SegmentedButton<String>(
                      segments: [for (final o in objs) ButtonSegment(value: o, label: Text(_names[o] ?? o))],
                      selected: {if (_obj != null) _obj!},
                      onSelectionChanged: (s) {
                        setState(() {
                          _obj = s.first;
                          _open = false;
                          _img = null;
                        });
                        _loadImg();
                      },
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 10, 16, 6),
                    child: FilledButton.icon(
                      icon: Icon(_open ? Icons.inventory_2_outlined : Icons.unarchive_outlined),
                      label: Text(_verbo),
                      onPressed: () {
                        setState(() => _open = !_open);
                        _loadImg();
                      },
                    ),
                  ),
                  if (_man!['trasera_generada'] == true)
                    const Padding(
                      padding: EdgeInsets.only(bottom: 12),
                      child: Text('Contraportada generada con la lista de temas', style: TextStyle(color: Colors.white54, fontSize: 12)),
                    ),
                  const SizedBox(height: 8),
                ]),
    );
  }
}
