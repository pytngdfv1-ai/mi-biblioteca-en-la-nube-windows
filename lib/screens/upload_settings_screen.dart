import 'package:flutter/material.dart';

import '../data/local_sync.dart';
import '../data/upload_queue.dart';
import '../data/vinyl_store.dart';
import 'upload_queue_screen.dart';

/// Ajustes de la subida desde el equipo: revisar al abrir, pausa, subir todo ahora y cola.
/// (La subida automática en segundo plano y el ahorro de energía son solo de Android.)
class UploadSettingsScreen extends StatefulWidget {
  const UploadSettingsScreen({super.key, required this.store});
  final VinylStore store;

  @override
  State<UploadSettingsScreen> createState() => _UploadSettingsScreenState();
}

class _UploadSettingsScreenState extends State<UploadSettingsScreen> {
  LocalSyncConfig _cfg = LocalSyncConfig();
  bool _loaded = false;
  bool _busy = false;
  double _p = 0;
  String _msg = '';
  int _pending = 0;
  int _errors = 0;

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    final c = await LocalSyncConfig.load();
    final q = await UploadQueue.load();
    if (!mounted) return;
    setState(() {
      _cfg = c;
      _pending = q.where((e) => e.state == 'pending' || e.state == 'uploading').length;
      _errors = q.where((e) => e.state == 'error').length;
      _loaded = true;
    });
  }

  Future<void> _uploadAll() async {
    if (!_cfg.ready) {
      setState(() => _msg = 'Primero elige la carpeta y la nube en Carpeta local.');
      return;
    }
    setState(() {
      _busy = true;
      _p = 0;
      _msg = 'Revisando la carpeta…';
    });
    try {
      final r = await LocalSync.runAll(_cfg, store: widget.store, retryAll: true, onProgress: (m, p) {
        if (mounted) {
          setState(() {
            _msg = m;
            _p = p;
          });
        }
      });
      if (mounted) setState(() => _msg = r.text);
    } catch (e) {
      if (mounted) setState(() => _msg = 'No se pudo subir: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
      _init();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Subida desde el equipo')),
      body: !_loaded
          ? const Center(child: CircularProgressIndicator())
          : ListView(padding: const EdgeInsets.all(16), children: [
              Text(
                _cfg.ready
                    ? 'Carpeta: ${_cfg.path}\nNube: ${_cfg.account?.name}${(_cfg.dest ?? '').isEmpty ? '' : ' / ${_cfg.dest}'}'
                    : 'Falta elegir la carpeta y la nube en Carpeta local (tarjeta «Subir lo nuevo a la nube»).',
                style: const TextStyle(fontSize: 12, color: Colors.white70),
              ),
              const SizedBox(height: 8),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Revisar al abrir la app'),
                subtitle: const Text('Sube lo nuevo en silencio al abrir'),
                value: _cfg.auto,
                onChanged: (v) async {
                  setState(() => _cfg.auto = v);
                  await _cfg.save();
                },
              ),
              const Divider(),
              Row(children: [
                Expanded(
                  child: FilledButton.icon(
                    icon: const Icon(Icons.cloud_upload),
                    label: const Text('Subir todo ahora'),
                    onPressed: _busy || _cfg.paused ? null : _uploadAll,
                  ),
                ),
                const SizedBox(width: 10),
                OutlinedButton.icon(
                  icon: Icon(_cfg.paused ? Icons.play_arrow : Icons.pause),
                  label: Text(_cfg.paused ? 'Reanudar' : 'Pausar subida'),
                  onPressed: () async {
                    setState(() => _cfg.paused = !_cfg.paused);
                    await _cfg.save();
                  },
                ),
              ]),
              if (_cfg.paused)
                const Padding(
                  padding: EdgeInsets.only(top: 8),
                  child: Text('Subida en pausa: no se sube nada. Lo ya subido no se pierde.', style: TextStyle(fontSize: 12, color: Colors.amber)),
                ),
              if (_busy) Padding(padding: const EdgeInsets.only(top: 10), child: LinearProgressIndicator(value: _p == 0 ? null : _p)),
              if (_msg.isNotEmpty) Padding(padding: const EdgeInsets.only(top: 8), child: Text(_msg, style: const TextStyle(fontSize: 12))),
              const Divider(height: 28),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.list_alt),
                title: const Text('Cola de subida'),
                subtitle: Text('$_pending pendientes · $_errors con error'),
                trailing: const Icon(Icons.chevron_right),
                onTap: () async {
                  await Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const UploadQueueScreen()));
                  _init();
                },
              ),
            ]),
    );
  }
}
