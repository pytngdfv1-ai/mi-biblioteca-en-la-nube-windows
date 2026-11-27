import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../data/cloud_upload.dart';
import '../data/koofr_client.dart';
import '../data/koofr_settings.dart';
import '../data/library_settings.dart';
import '../data/local_scanner.dart';
import '../data/local_sync.dart';
import '../data/vinyl_store.dart';
import 'upload_settings_screen.dart';

/// Agrega a la biblioteca una carpeta de música del equipo.
class LocalScreen extends StatefulWidget {
  const LocalScreen({super.key, required this.store});

  final VinylStore store;

  @override
  State<LocalScreen> createState() => _LocalScreenState();
}

class _LocalScreenState extends State<LocalScreen> {
  bool _busy = false;
  String _status = '';

  LocalSyncConfig _cfg = LocalSyncConfig();
  List<String>? _folders;
  bool _syncBusy = false;
  double _syncP = 0;
  String _syncMsg = '';

  @override
  void initState() {
    super.initState();
    _loadCfg();
  }

  Future<void> _loadCfg() async {
    final c = await LocalSyncConfig.load();
    if (!mounted) return;
    setState(() => _cfg = c);
    _loadFolders();
  }

  Future<void> _loadFolders() async {
    final a = _cfg.account;
    if (a == null || a.split != 'yes') {
      if (mounted) setState(() => _folders = const []);
      return;
    }
    try {
      final f = await KoofrClient(a).topFolders();
      if (mounted) setState(() => _folders = f);
    } catch (_) {
      if (mounted) setState(() => _folders = const []);
    }
  }

  Future<void> _preview() async {
    if (!_cfg.ready) return;
    setState(() {
      _syncBusy = true;
      _syncP = 0;
      _syncMsg = 'Revisando la carpeta…';
    });
    try {
      final items = await LocalSync.plan(_cfg, onProgress: (n) {
        if (mounted) setState(() => _syncMsg = 'Leyendo $n…');
      });
      if (!mounted) return;
      setState(() => _syncMsg = items.isEmpty
          ? 'No hay nada nuevo para subir.'
          : 'Subiría ${items.length}:\n${[
              for (final it in items.take(12)) '• ${it.v.artist} – ${it.v.title} → ${CloudUpload.targetDir(it.v, _cfg.dest, flatSingles: true).join('/')}',
            ].join('\n')}${items.length > 12 ? '\n… y ${items.length - 12} más' : ''}');
    } catch (e) {
      if (mounted) setState(() => _syncMsg = 'No se pudo revisar: $e');
    } finally {
      if (mounted) setState(() => _syncBusy = false);
    }
  }

  Future<void> _subir() async {
    if (!_cfg.ready) return;
    setState(() {
      _syncBusy = true;
      _syncP = 0;
      _syncMsg = 'Revisando la carpeta…';
    });
    try {
      final r = await LocalSync.runAll(_cfg, store: widget.store, onProgress: (m, p) {
        if (mounted) {
          setState(() {
            _syncMsg = m;
            _syncP = p;
          });
        }
      });
      if (mounted) setState(() => _syncMsg = r.text);
    } catch (e) {
      if (mounted) setState(() => _syncMsg = 'No se pudo subir: $e');
    } finally {
      if (mounted) setState(() => _syncBusy = false);
    }
  }

  Widget _syncCard() {
    final a = _cfg.account;
    final accounts = KoofrAccounts.list;
    final folders = _folders;
    return Card(
      margin: const EdgeInsets.only(top: 20),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('Subir lo nuevo a la nube', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
          const SizedBox(height: 4),
          Text(
            (_cfg.path ?? '').isEmpty
                ? 'Primero elige la carpeta del equipo con "Elegir carpeta".'
                : 'Carpeta: ${_cfg.path}\nSube lo que aún no está en la nube como Artista/Disco/Tema '
                    '(quita "Artista - " del nombre del archivo). No pisa nada y verifica cada copia.',
            style: const TextStyle(fontSize: 12, color: Colors.white70),
          ),
          if (accounts.isEmpty)
            const Padding(padding: EdgeInsets.only(top: 8), child: Text('Primero conecta una nube.', style: TextStyle(color: Colors.white54))),
          if (accounts.length > 1 && (_cfg.path ?? '').isNotEmpty)
            DropdownButton<String>(
              isExpanded: true,
              value: a?.id,
              hint: const Text('Nube de destino'),
              items: [for (final x in accounts) DropdownMenuItem(value: x.id, child: Text(x.name))],
              onChanged: _syncBusy
                  ? null
                  : (v) {
                      setState(() {
                        _cfg.accountId = v;
                        _cfg.dest = null;
                      });
                      _cfg.save();
                      _loadFolders();
                    },
            ),
          if (a != null && a.split == 'yes' && (_cfg.path ?? '').isNotEmpty)
            DropdownButton<String>(
              isExpanded: true,
              value: folders != null && folders.contains(_cfg.dest) ? _cfg.dest : null,
              hint: Text(folders == null ? 'Leyendo carpetas…' : 'Carpeta de la nube (ej.: Inglés)'),
              items: [for (final f in folders ?? const <String>[]) DropdownMenuItem(value: f, child: Text(f))],
              onChanged: _syncBusy
                  ? null
                  : (v) {
                      setState(() => _cfg.dest = v);
                      _cfg.save();
                    },
            ),
          if (a != null && (_cfg.path ?? '').isNotEmpty) ...[
            SwitchListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              title: const Text('Revisar al abrir la app'),
              subtitle: const Text('Sube lo nuevo en silencio al abrir'),
              value: _cfg.auto,
              onChanged: _syncBusy ? null : (v) {
                setState(() => _cfg.auto = v);
                _cfg.save();
              },
            ),
            SwitchListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              title: const Text('Borrar del equipo tras subir'),
              subtitle: const Text('Solo si la copia en la nube quedó verificada'),
              value: _cfg.deleteLocal,
              onChanged: _syncBusy ? null : (v) {
                setState(() => _cfg.deleteLocal = v);
                _cfg.save();
              },
            ),
            Row(children: [
              OutlinedButton(onPressed: _syncBusy || !_cfg.ready ? null : _preview, child: const Text('Ver qué subiría')),
              const SizedBox(width: 10),
              FilledButton(onPressed: _syncBusy || !_cfg.ready ? null : _subir, child: const Text('Subir lo nuevo')),
            ]),
            TextButton(
              onPressed: () => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => UploadSettingsScreen(store: widget.store))),
              child: const Text('Pausa y cola de subida'),
            ),
          ],
          if (_syncBusy) Padding(padding: const EdgeInsets.only(top: 8), child: LinearProgressIndicator(value: _syncP == 0 ? null : _syncP)),
          if (_syncMsg.isNotEmpty) Padding(padding: const EdgeInsets.only(top: 8), child: Text(_syncMsg, style: const TextStyle(fontSize: 12))),
        ]),
      ),
    );
  }

  Future<void> _pick() async {
    setState(() {
      _busy = true;
      _status = 'Eligiendo carpeta…';
    });
    try {
      final path = await FilePicker.platform.getDirectoryPath();
      if (path == null) {
        setState(() => _status = '');
        return;
      }
      _cfg.path = path;
      await _cfg.save();
      setState(() => _status = 'Leyendo carpeta…');
      final scanner = LocalScanner();
      final reuse = {
        for (final v in widget.store.items)
          if ((v.source ?? '').startsWith('local')) v.id: v,
      };
      final result = await scanner.scan(
        path,
        reuse: reuse,
        onProgress: (n) {
          if (mounted) setState(() => _status = 'Leyendo $n…');
        },
      );
      await widget.store.addAlbums(result.albums);
      if (!mounted) return;
      setState(() => _status = result.albums.isEmpty
          ? 'No encontré álbumes completos. ${scanner.diagnostic}\n'
              '${result.summary(LibrarySettings.minTracks)}'
          : result.summary(LibrarySettings.minTracks));
    } on LocalException catch (e) {
      if (mounted) setState(() => _status = e.message);
    } catch (e) {
      if (mounted) setState(() => _status = 'No se pudo leer la carpeta: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Carpeta local')),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          const Text(
            'Elige una carpeta de tu equipo con tu música.\n'
            'Cada carpeta con audio es un álbum y su carpeta padre es el artista. '
            'Agrega cover.jpg en el álbum para la carátula.',
            style: TextStyle(color: Colors.white70),
          ),
          const SizedBox(height: 20),
          FilledButton.icon(
            icon: _busy
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.folder_open),
            label: const Text('Elegir carpeta'),
            onPressed: _busy ? null : _pick,
          ),
          const SizedBox(height: 12),
          Text(_status),
          _syncCard(),
        ],
      ),
    );
  }
}
