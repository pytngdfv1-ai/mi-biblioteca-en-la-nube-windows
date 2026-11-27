import 'dart:async';

import 'package:flutter/material.dart';

import '../data/upload_queue.dart';

/// Cola de subida: lo que se está subiendo, lo pendiente, lo ya subido y los errores (con reintento).
class UploadQueueScreen extends StatefulWidget {
  const UploadQueueScreen({super.key});

  @override
  State<UploadQueueScreen> createState() => _UploadQueueScreenState();
}

class _UploadQueueScreenState extends State<UploadQueueScreen> {
  List<QueueItem> _items = [];
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _load();
    // La tarea en segundo plano también escribe en la cola: se refresca sola.
    _timer = Timer.periodic(const Duration(seconds: 3), (_) => _load());
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _load() async {
    final q = await UploadQueue.load();
    if (mounted) setState(() => _items = q);
  }

  static String _size(int b) {
    if (b >= 1 << 30) return '${(b / (1 << 30)).toStringAsFixed(1)} GB';
    if (b >= 1 << 20) return '${(b / (1 << 20)).toStringAsFixed(1)} MB';
    return '${(b / 1024).toStringAsFixed(0)} KB';
  }

  static String _when(int ms) {
    final d = DateTime.fromMillisecondsSinceEpoch(ms);
    String two(int n) => n.toString().padLeft(2, '0');
    return '${two(d.day)}/${two(d.month)} ${two(d.hour)}:${two(d.minute)}';
  }

  List<Widget> _section(String title, List<QueueItem> list, {bool errors = false, bool done = false}) {
    if (list.isEmpty) return const [];
    return [
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
        child: Text('$title (${list.length})', style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13, color: Colors.white70)),
      ),
      for (final e in list.take(done ? 50 : 500))
        ListTile(
          dense: true,
          leading: Icon(
            errors
                ? Icons.error_outline
                : done
                    ? Icons.check_circle
                    : e.state == 'uploading'
                        ? Icons.cloud_upload
                        : Icons.schedule,
            color: errors
                ? Colors.redAccent
                : done
                    ? const Color(0xFF7BD88F)
                    : null,
            size: 20,
          ),
          title: Text('${e.artist} – ${e.title}', maxLines: 1, overflow: TextOverflow.ellipsis),
          subtitle: Text(
            errors
                ? '${e.error ?? 'Error'}\nIntento ${e.tries}; próximo: ${_when(e.next)}'
                : done
                    ? '${_size(e.bytes)} · ${_when(e.at)}'
                    : '${e.single ? 'Tema suelto' : 'Disco'} · ${_size(e.bytes)}',
            style: const TextStyle(fontSize: 12),
          ),
          isThreeLine: errors,
          trailing: errors
              ? TextButton(
                  onPressed: () async {
                    await UploadQueue.retryErrors(sig: e.sig);
                    _load();
                  },
                  child: const Text('Reintentar'),
                )
              : null,
        ),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final uploading = _items.where((e) => e.state == 'uploading').toList();
    final pending = _items.where((e) => e.state == 'pending').toList();
    final errors = _items.where((e) => e.state == 'error').toList();
    final done = _items.where((e) => e.state == 'done').toList()..sort((a, b) => b.at.compareTo(a.at));
    return Scaffold(
      appBar: AppBar(
        title: const Text('Cola de subida'),
        actions: [
          if (errors.isNotEmpty)
            TextButton(
              onPressed: () async {
                await UploadQueue.retryErrors();
                _load();
              },
              child: const Text('Reintentar errores'),
            ),
          if (done.isNotEmpty)
            IconButton(
              tooltip: 'Limpiar subidos',
              icon: const Icon(Icons.cleaning_services_outlined),
              onPressed: () async {
                await UploadQueue.clearDone();
                _load();
              },
            ),
        ],
      ),
      body: _items.isEmpty
          ? const Center(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: Text(
                  'La cola está vacía.\nEn Ajustes → Subida desde el equipo, toca «Subir todo ahora».',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.white70),
                ),
              ),
            )
          : ListView(children: [
              ..._section('Subiendo', uploading),
              ..._section('Pendientes', pending),
              ..._section('Errores', errors, errors: true),
              ..._section('Subidos', done, done: true),
              const SizedBox(height: 24),
            ]),
    );
  }
}
