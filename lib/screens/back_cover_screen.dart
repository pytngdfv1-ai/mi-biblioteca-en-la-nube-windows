import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../data/back_cover.dart';
import '../data/fetch_bytes.dart';
import '../data/musicbrainz.dart';
import '../data/studio_save.dart';
import '../data/vinyl_store.dart';
import '../models/vinyl.dart';
import '../widgets/cassette_3d.dart' show backCoverOf;

/// Contraportada del disco: usa la original si existe, la busca en internet o la genera;
/// se puede cambiar por una tuya o modificar el diseño generado, y se guarda en la carpeta del disco.
class BackCoverScreen extends StatefulWidget {
  const BackCoverScreen({super.key, required this.store, required this.vinyl});
  final VinylStore store;
  final Vinyl vinyl;

  @override
  State<BackCoverScreen> createState() => _BackCoverScreenState();
}

class _BackCoverScreenState extends State<BackCoverScreen> {
  Vinyl get v => widget.vinyl;
  Uint8List? _bytes;
  ui.Image? _img;
  String _origin = '';
  bool _busy = false;
  bool _saved = false;
  BackStyle _style = BackStyle.blur;
  bool _tracks = true;
  final _note = TextEditingController();

  @override
  void initState() {
    super.initState();
    _initial();
  }

  @override
  void dispose() {
    _note.dispose();
    super.dispose();
  }

  Future<void> _initial() async {
    final url = backCoverOf(v);
    if (url != null) {
      try {
        await _set(await fetchBytes(url), 'Original (guardada con el disco)', saved: true);
        return;
      } catch (_) {}
    }
    await _generate();
  }

  Future<void> _set(Uint8List b, String origin, {bool saved = false}) async {
    final codec = await ui.instantiateImageCodec(b, targetWidth: 900);
    final f = await codec.getNextFrame();
    if (!mounted) return;
    setState(() {
      _bytes = b;
      _img = f.image;
      _origin = origin;
      _saved = saved;
    });
  }

  Future<void> _run(Future<void> Function() job) async {
    setState(() => _busy = true);
    try {
      await job();
    } catch (_) {
      _msg('No se pudo');
    }
    if (mounted) setState(() => _busy = false);
  }

  void _msg(String s) => ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(s)));

  Future<void> _generate() => _run(() async {
        final b = await BackCoverGen.render(v, tape: v.isTape, style: _style, tracks: _tracks, note: _note.text);
        await _set(b, 'Generada');
      });

  Future<void> _search() => _run(() async {
        final r = await MusicBrainz.release(v.artist, v.title);
        final url = r == null ? null : await MusicBrainz.backCover(r);
        if (url == null) {
          _msg('No hay contraportada en internet para este disco');
          return;
        }
        await _set(await fetchBytes(url), 'Descargada (Cover Art Archive)');
      });

  Future<void> _pick() => _run(() async {
        final r = await FilePicker.platform.pickFiles(type: FileType.image, withData: true);
        final b = r?.files.single.bytes;
        if (b == null) return;
        await _set(b, 'Elegida por ti');
      });

  Future<void> _save() => _run(() async {
        final b = _bytes;
        if (b == null) return;
        await StudioSave.image(widget.store, v, b, label: 'Contraportada', type: 'back');
        if (mounted) setState(() => _saved = true);
        _msg('Contraportada guardada con el disco');
      });

  @override
  Widget build(BuildContext context) {
    final generated = _origin == 'Generada';
    return Scaffold(
      appBar: AppBar(title: const Text('Contraportada')),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: FilledButton.icon(
            onPressed: _busy || _bytes == null || _saved ? null : _save,
            icon: const Icon(Icons.save_alt),
            label: Text(_saved ? 'Guardada' : 'Guardar en la carpeta del disco'),
          ),
        ),
      ),
      body: ListView(padding: const EdgeInsets.all(16), children: [
        Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 380),
            child: _img == null
                ? const SizedBox(height: 200, child: Center(child: CircularProgressIndicator()))
                : RawImage(image: _img, fit: BoxFit.contain),
          ),
        ),
        const SizedBox(height: 8),
        Center(child: Text(_origin, style: const TextStyle(color: Colors.white60))),
        const SizedBox(height: 12),
        Wrap(spacing: 8, runSpacing: 4, children: [
          ActionChip(avatar: const Icon(Icons.cloud_download, size: 18), label: const Text('Buscar en internet'), onPressed: _busy ? null : _search),
          ActionChip(avatar: const Icon(Icons.folder_open, size: 18), label: const Text('Elegir archivo'), onPressed: _busy ? null : _pick),
          ActionChip(avatar: const Icon(Icons.auto_fix_high, size: 18), label: const Text('Generar'), onPressed: _busy ? null : _generate),
        ]),
        if (generated) ...[
          const SizedBox(height: 16),
          Text('Modificar', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          SegmentedButton<BackStyle>(
            segments: const [
              ButtonSegment(value: BackStyle.blur, label: Text('Portada')),
              ButtonSegment(value: BackStyle.solid, label: Text('Color')),
              ButtonSegment(value: BackStyle.gradient, label: Text('Degradado')),
            ],
            selected: {_style},
            onSelectionChanged: (s) {
              setState(() => _style = s.first);
              _generate();
            },
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Mostrar los temas'),
            value: _tracks,
            onChanged: (x) {
              setState(() => _tracks = x);
              _generate();
            },
          ),
          TextField(
            controller: _note,
            maxLines: 2,
            decoration: const InputDecoration(labelText: 'Nota (opcional)', border: OutlineInputBorder()),
            onSubmitted: (_) => _generate(),
          ),
          const SizedBox(height: 8),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(onPressed: _busy ? null : _generate, icon: const Icon(Icons.refresh), label: const Text('Aplicar nota')),
          ),
        ],
      ]),
    );
  }
}
