import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import '../data/cover_lookup.dart';
import '../data/studio_save.dart';
import '../data/vinyl_store.dart';
import '../models/vinyl.dart';
import '../widgets/cover_art.dart';

/// Ajustes → Portadas sugeridas: discos y temas cuya portada no está en su carpeta.
/// La sugerencia viene de la carátula incrustrada en los temas o de internet; al aceptar,
/// se guarda como "Portada.jpg" en la carpeta del disco (local o nube).
class CoverSuggestScreen extends StatefulWidget {
  const CoverSuggestScreen({super.key, required this.store});
  final VinylStore store;

  @override
  State<CoverSuggestScreen> createState() => _CoverSuggestScreenState();
}

class _CoverSuggestScreenState extends State<CoverSuggestScreen> {
  final _skipped = <String>{};
  final _found = <String, String?>{}; // id -> url sugerida (null = no hay)
  final _searching = <String>{};
  final _saving = <String>{};
  final _err = <String, String>{}; // id -> motivo del último error
  Set<String> _done = {}; // ya guardadas en su carpeta (persistente)
  String _status = '';
  bool _all = false;

  /// La portada es una copia del equipo o de internet (no un archivo de la carpeta).
  bool _inCache(String? u) => u != null && u.startsWith('file:') && u.contains('/covers/');

  List<Vinyl> get _list => [
        for (final v in widget.store.items)
          if (v.owned && v.trackUrls.isNotEmpty && !_skipped.contains(v.id) && !_done.contains(v.id) && (v.coverUrl == null || _inCache(v.coverUrl))) v,
      ];

  @override
  void initState() {
    super.initState();
    SharedPreferences.getInstance().then((p) {
      _done = (p.getStringList('cover_saved_ids') ?? const []).toSet();
      if (mounted) setState(() {});
    }).catchError((_) {});
  }

  Future<void> _markDone(String id) async {
    _done.add(id);
    try {
      final p = await SharedPreferences.getInstance();
      await p.setStringList('cover_saved_ids', _done.toList());
    } catch (_) {}
  }

  String? _sug(Vinyl v) => v.coverUrl ?? _found[v.id];

  Future<void> _search(Vinyl v) async {
    if (_searching.contains(v.id) || _found.containsKey(v.id)) return;
    _searching.add(v.id);
    String? url;
    try {
      final hit = await CoverLookup.find(
        artist: v.artist,
        albums: [if (!v.single) v.title],
        tracks: v.tracks,
        trackFirst: v.single,
      );
      url = hit?.url;
    } catch (_) {}
    _searching.remove(v.id);
    _found[v.id] = url;
    if (mounted) setState(() {});
  }

  Future<Uint8List?> _bytes(String url) async {
    if (url.startsWith('file:')) return File(Uri.parse(url).toFilePath()).readAsBytes();
    final res = await http
        .get(Uri.parse(url), headers: const {'User-Agent': 'VinylSolutions/1.0 (personal music library app)'})
        .timeout(const Duration(seconds: 30));
    return res.statusCode == 200 && res.bodyBytes.length > 500 ? res.bodyBytes : null;
  }

  Future<bool> _save(Vinyl v) async {
    final url = _sug(v);
    if (url == null) {
      _err[v.id] = 'Sin portada para guardar';
      return false;
    }
    _saving.add(v.id);
    _err.remove(v.id);
    if (mounted) setState(() {});
    try {
      for (var n = 0; n < 3; n++) {
        try {
          final b = await _bytes(url);
          if (b == null) throw Exception('No se pudo leer la imagen');
          await StudioSave.image(widget.store, v, b, label: 'Portada', type: 'front', asCover: true);
          await _markDone(v.id);
          return true;
        } catch (e) {
          _err[v.id] = '$e'.replaceFirst('Exception: ', '').replaceFirst('KoofrException: ', '');
          if (n < 2) await Future<void>.delayed(Duration(seconds: 2 * (n + 1)));
        }
      }
      return false;
    } finally {
      _saving.remove(v.id);
      if (mounted) setState(() {});
    }
  }

  Future<void> _saveAll() async {
    final todo = [for (final v in _list) if (_inCache(v.coverUrl)) v];
    setState(() {
      _all = true;
      _status = '';
    });
    var ok = 0, fail = 0;
    for (var i = 0; i < todo.length; i++) {
      if (!mounted) return;
      setState(() => _status = 'Guardando ${i + 1}/${todo.length}…');
      (await _save(todo[i])) ? ok++ : fail++;
      await Future<void>.delayed(const Duration(milliseconds: 500));
    }
    if (mounted) {
      setState(() {
        _all = false;
        _status = 'Guardadas $ok${fail > 0 ? ' · $fail con error' : ''}.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: widget.store,
      builder: (context, _) {
        final list = _list;
        final ready = list.where((v) => _inCache(v.coverUrl)).length;
        return Scaffold(
          appBar: AppBar(title: const Text('Portadas sugeridas')),
          body: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(14, 6, 14, 6),
                child: Row(children: [
                  Expanded(child: Text(_status.isEmpty ? '${list.length} sin portada en su carpeta' : _status, style: const TextStyle(color: Colors.white70))),
                  FilledButton(onPressed: _all || ready == 0 ? null : _saveAll, child: Text('Guardar $ready')),
                ]),
              ),
              if (_all) const LinearProgressIndicator(minHeight: 2),
              Expanded(
                child: list.isEmpty
                    ? const Center(child: Text('Todo tiene su portada en la carpeta.', style: TextStyle(color: Colors.white60)))
                    : ListView.builder(
                        itemCount: list.length,
                        itemBuilder: (_, i) {
                          final v = list[i];
                          final u = _sug(v);
                          if (v.coverUrl == null && !_found.containsKey(v.id)) _search(v);
                          final busy = _saving.contains(v.id);
                          return ListTile(
                            leading: SizedBox(
                              width: 52,
                              height: 52,
                              child: u == null
                                  ? Center(
                                      child: _found.containsKey(v.id)
                                          ? const Icon(Icons.image_not_supported_outlined, color: Colors.white38)
                                          : const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)))
                                  : buildCoverImage(u, cacheWidth: 150, fallback: const ColoredBox(color: Color(0xFF222226))),
                            ),
                            title: Text(v.single && v.tracks.isNotEmpty ? v.tracks.first : v.title, maxLines: 1, overflow: TextOverflow.ellipsis),
                            subtitle: _err[v.id] != null
                                ? Text('${v.artist} · ${_err[v.id]}', maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Color(0xFFE0453A), fontSize: 12))
                                : Text(v.artist, maxLines: 1, overflow: TextOverflow.ellipsis),
                            trailing: busy
                                ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2))
                                : Row(mainAxisSize: MainAxisSize.min, children: [
                                    IconButton(
                                      tooltip: _err[v.id] != null ? 'Reintentar' : 'Guardar en la carpeta',
                                      icon: Icon(_err[v.id] != null ? Icons.refresh : Icons.check_circle_outline),
                                      onPressed: u == null || _all
                                          ? null
                                          : () => _save(v),
                                    ),
                                    IconButton(
                                      tooltip: 'Omitir',
                                      icon: const Icon(Icons.close),
                                      onPressed: () => setState(() => _skipped.add(v.id)),
                                    ),
                                  ]),
                          );
                        },
                      ),
              ),
            ],
          ),
        );
      },
    );
  }
}
