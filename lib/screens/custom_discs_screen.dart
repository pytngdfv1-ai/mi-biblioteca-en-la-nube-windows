import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../data/custom_discs.dart';
import '../data/vinyl_store.dart';
import '../models/vinyl.dart';
import '../widgets/collage.dart';
import '../widgets/cassette_card.dart';
import '../widgets/cover_art.dart';
import '../widgets/disc_texture.dart';
import '../widgets/vinyl_disc.dart';

/// Biblioteca de discos y cassettes personalizados.
class CustomDiscsScreen extends StatelessWidget {
  const CustomDiscsScreen({super.key, required this.store});
  final VinylStore store;

  void _open(BuildContext context, [Vinyl? v]) {
    Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => CustomEditorScreen(store: store, existing: v)));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Discos personalizados')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _open(context),
        icon: const Icon(Icons.add),
        label: const Text('Nuevo'),
      ),
      body: ListenableBuilder(
        listenable: store,
        builder: (context, _) {
          final list = [for (final v in store.items) if (CustomDiscs.isCustom(v)) v];
          if (list.isEmpty) {
            return const Center(
              child: Padding(
                padding: EdgeInsets.all(32),
                child: Text(
                  'Arma un disco o cassette con temas de cualquier disco de tu biblioteca. La portada se crea sola como collage y puedes editarla.',
                  textAlign: TextAlign.center,
                ),
              ),
            );
          }
          return ListView.separated(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 90),
            itemCount: list.length,
            separatorBuilder: (_, __) => const Divider(height: 1),
            itemBuilder: (_, i) {
              final v = list[i];
              return ListTile(
                leading: SizedBox(
                  width: 56,
                  height: 56,
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(6),
                    child: v.coverUrl == null
                        ? const ColoredBox(color: Color(0xFF2A2A33), child: Icon(Icons.album))
                        : buildCoverImage(v.coverUrl!, cacheWidth: 160, fallback: const ColoredBox(color: Color(0xFF2A2A33))),
                  ),
                ),
                title: Text(v.title, maxLines: 1, overflow: TextOverflow.ellipsis),
                subtitle: Text('${v.tracks.length} temas · ${v.cassette ? 'Cassette' : 'Vinilo'}'),
                onTap: () => _open(context, v),
                trailing: IconButton(
                  icon: const Icon(Icons.delete_outline),
                  onPressed: () async {
                    final ok = await showDialog<bool>(
                      context: context,
                      builder: (ctx) => AlertDialog(
                        title: Text('¿Eliminar "${v.title}"?'),
                        content: const Text('Solo se quita de la app; tus archivos no se tocan.'),
                        actions: [
                          TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text('Cancelar')),
                          FilledButton(onPressed: () => Navigator.of(ctx).pop(true), child: const Text('Eliminar')),
                        ],
                      ),
                    );
                    if (ok == true) await CustomDiscs.delete(store, v.id);
                  },
                ),
              );
            },
          );
        },
      ),
    );
  }
}

/// Editor: nombre, tipo, temas y collage de portada (mover, girar, escalar, forma).
class CustomEditorScreen extends StatefulWidget {
  const CustomEditorScreen({super.key, required this.store, this.existing});
  final VinylStore store;
  final Vinyl? existing;

  @override
  State<CustomEditorScreen> createState() => _CustomEditorScreenState();
}

class _CustomEditorScreenState extends State<CustomEditorScreen> {
  final _title = TextEditingController();
  final _artist = TextEditingController(text: 'Mezclas');
  bool _cassette = false;
  final List<PickedTrack> _tracks = [];
  List<CollageLayer> _layers = [];
  final Map<String, ui.Image> _images = {};
  int _sel = -1;
  bool _lock = false;
  bool _saving = false;
  Size _cs = const Size(300, 300);
  Offset _f0 = Offset.zero;
  double _s0 = .5, _r0 = 0, _x0 = .5, _y0 = .5;
  int _seed = 1;
  CustomLook _look = CustomLook();
  final _labelCtl = TextEditingController();

  late final Map<String, PickedTrack> _byUrl = _index();

  Map<String, PickedTrack> _index() {
    final m = <String, PickedTrack>{};
    for (final v in widget.store.items) {
      if (v.isDivider || CustomDiscs.isCustom(v)) continue;
      for (var i = 0; i < v.tracks.length && i < v.trackUrls.length; i++) {
        m[v.trackUrls[i]] = PickedTrack(v.tracks[i], v.trackUrls[i], v.coverUrl, v.artist);
      }
    }
    return m;
  }

  @override
  void initState() {
    super.initState();
    final e = widget.existing;
    if (e != null) {
      _title.text = e.title;
      _artist.text = e.artist;
      _cassette = e.cassette;
      for (var i = 0; i < e.tracks.length && i < e.trackUrls.length; i++) {
        _tracks.add(_byUrl[e.trackUrls[i]] ?? PickedTrack(e.tracks[i], e.trackUrls[i], null, e.artist));
      }
      _layers = [for (final l in (CustomDiscs.metaOf(e.id)?.layers ?? const <CollageLayer>[])) l.copy()];
      _look = CustomDiscs.metaOf(e.id)?.look.copy() ?? CustomLook();
      _labelCtl.text = _look.labelText;
      _loadImages();
    }
  }

  @override
  void dispose() {
    _title.dispose();
    _artist.dispose();
    _labelCtl.dispose();
    super.dispose();
  }

  Future<void> _loadImages() async {
    for (final u in {for (final l in _layers) l.url}) {
      if (_images.containsKey(u)) continue;
      final i = await CollageImages.load(u);
      if (i != null && mounted) setState(() => _images[u] = i);
    }
  }

  List<String> _coversOfTracks() {
    final seen = <String>{};
    final out = <String>[];
    for (final t in _tracks) {
      final c = t.cover;
      if (c != null && c.isNotEmpty && seen.add(c)) out.add(c);
    }
    return out;
  }

  void _auto({bool mosaic = false, bool cut = false}) {
    if (cut) {
      final per = [for (final t in _tracks) if (t.cover != null && t.cover!.isNotEmpty) t.cover!];
      if (per.isEmpty) {
        _msg('Los temas elegidos no tienen portada');
        return;
      }
      setState(() {
        _layers = CollageLayout.cutouts(per, seed: ++_seed);
        _sel = -1;
      });
      _loadImages();
      return;
    }
    final urls = _coversOfTracks();
    if (urls.isEmpty) {
      _msg('Los temas elegidos no tienen portada');
      return;
    }
    setState(() {
      _layers = mosaic ? CollageLayout.mosaic(urls, seed: ++_seed) : CollageLayout.grid(urls);
      _sel = -1;
    });
    _loadImages();
  }

  void _msg(String s) => ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(s)));

  Future<void> _addTracks() async {
    final r = await Navigator.of(context).push<List<PickedTrack>>(
      MaterialPageRoute(builder: (_) => _TrackPicker(all: _byUrl.values.toList(), chosen: {for (final t in _tracks) t.url})),
    );
    if (r == null || r.isEmpty) return;
    setState(() => _tracks.addAll(r));
    if (_layers.isEmpty) _auto(cut: true);
  }

  Future<void> _addImage() async {
    final urls = <String>{
      for (final v in widget.store.items)
        if (!CustomDiscs.isCustom(v) && v.coverUrl != null && v.coverUrl!.isNotEmpty) v.coverUrl!,
    }.toList();
    final r = await Navigator.of(context).push<String>(MaterialPageRoute(builder: (_) => _CoverPicker(store: widget.store, urls: urls)));
    if (r == null) return;
    setState(() {
      _layers.add(CollageLayer(url: r, scale: .5));
      _sel = _layers.length - 1;
    });
    _loadImages();
  }

  void _start(ScaleStartDetails d) {
    final p = d.localFocalPoint;
    var hit = -1;
    for (var i = _layers.length - 1; i >= 0; i--) {
      if (CollagePainter.hit(_layers[i], p, _cs)) {
        hit = i;
        break;
      }
    }
    setState(() => _sel = hit);
    if (hit >= 0) {
      final l = _layers[hit];
      _f0 = p;
      _s0 = l.scale;
      _r0 = l.rot;
      _x0 = l.x;
      _y0 = l.y;
    }
  }

  void _update(ScaleUpdateDetails d) {
    if (_sel < 0 || _sel >= _layers.length) return;
    final l = _layers[_sel];
    setState(() {
      l.x = (_x0 + (d.localFocalPoint.dx - _f0.dx) / _cs.width).clamp(-.2, 1.2).toDouble();
      l.y = (_y0 + (d.localFocalPoint.dy - _f0.dy) / _cs.height).clamp(-.2, 1.2).toDouble();
      l.scale = (_s0 * d.scale).clamp(.1, 2.0).toDouble();
      l.rot = _r0 + d.rotation;
    });
  }

  Future<void> _save() async {
    final title = _title.text.trim();
    if (title.isEmpty) {
      _msg('Ponle un nombre');
      return;
    }
    if (_tracks.isEmpty) {
      _msg('Agrega al menos un tema');
      return;
    }
    setState(() => _saving = true);
    String? note;
    try {
      note = await CustomDiscs.save(
        widget.store,
        id: widget.existing?.id,
        title: title,
        artist: _artist.text.trim().isEmpty ? 'Mezclas' : _artist.text.trim(),
        cassette: _cassette,
        tracks: _tracks,
        layers: _layers,
        look: _look,
      );
    } catch (_) {
      if (mounted) {
        setState(() => _saving = false);
        _msg('No se pudo guardar');
      }
      return;
    }
    if (!mounted) return;
    final nav = ScaffoldMessenger.of(context);
    Navigator.of(context).pop();
    nav.showSnackBar(SnackBar(content: Text(note ?? 'Disco guardado')));
  }

  Widget _chip(IconData icon, String label, VoidCallback? onTap) =>
      ActionChip(avatar: Icon(icon, size: 18), label: Text(label), onPressed: onTap);

  @override
  Widget build(BuildContext context) {
    final sel = _sel >= 0 && _sel < _layers.length ? _layers[_sel] : null;
    return Scaffold(
      appBar: AppBar(title: Text(widget.existing == null ? 'Nuevo disco' : 'Editar disco')),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: FilledButton.icon(
            onPressed: _saving ? null : _save,
            icon: _saving
                ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.check),
            label: const Text('Guardar'),
          ),
        ),
      ),
      body: ListView(
        physics: _lock ? const NeverScrollableScrollPhysics() : null,
        padding: const EdgeInsets.all(16),
        children: [
          TextField(controller: _title, decoration: const InputDecoration(labelText: 'Nombre', border: OutlineInputBorder())),
          const SizedBox(height: 12),
          TextField(controller: _artist, decoration: const InputDecoration(labelText: 'Artista / autor', border: OutlineInputBorder())),
          const SizedBox(height: 12),
          SegmentedButton<bool>(
            segments: const [
              ButtonSegment(value: false, label: Text('Vinilo'), icon: Icon(Icons.album)),
              ButtonSegment(value: true, label: Text('Cassette'), icon: Icon(Icons.speaker_group)),
            ],
            selected: {_cassette},
            onSelectionChanged: (s) => setState(() => _cassette = s.first),
          ),
          const SizedBox(height: 16),
          Row(children: [
            Expanded(child: Text('Temas (${_tracks.length})', style: Theme.of(context).textTheme.titleMedium)),
            TextButton.icon(onPressed: _addTracks, icon: const Icon(Icons.add), label: const Text('Agregar')),
          ]),
          ReorderableListView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: _tracks.length,
            onReorder: (a, b) => setState(() {
              if (b > a) b--;
              _tracks.insert(b, _tracks.removeAt(a));
            }),
            itemBuilder: (_, i) {
              final t = _tracks[i];
              return ListTile(
                key: ValueKey('${t.url}#$i'),
                dense: true,
                contentPadding: EdgeInsets.zero,
                title: Text(t.title, maxLines: 1, overflow: TextOverflow.ellipsis),
                subtitle: Text(t.artist, maxLines: 1, overflow: TextOverflow.ellipsis),
                trailing: IconButton(icon: const Icon(Icons.close), onPressed: () => setState(() => _tracks.removeAt(i))),
              );
            },
          ),
          const SizedBox(height: 16),
          Text('Portada (collage)', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          Listener(
            onPointerDown: (_) => setState(() => _lock = true),
            onPointerUp: (_) => setState(() => _lock = false),
            onPointerCancel: (_) => setState(() => _lock = false),
            child: AspectRatio(
              aspectRatio: 1,
              child: LayoutBuilder(builder: (_, c) {
                _cs = Size(c.maxWidth, c.maxHeight);
                return ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onScaleStart: _start,
                    onScaleUpdate: _update,
                    child: CustomPaint(painter: CollagePainter(_layers, _images, selected: _sel), size: _cs),
                  ),
                );
              }),
            ),
          ),
          const SizedBox(height: 4),
          const Text('Toca una imagen y arrástrala; con dos dedos la giras y cambias su tamaño.',
              style: TextStyle(fontSize: 12, color: Colors.white60)),
          const SizedBox(height: 8),
          Wrap(spacing: 8, runSpacing: 4, children: [
            _chip(Icons.content_cut, 'Retazos', () => _auto(cut: true)),
            _chip(Icons.grid_view, 'Cuadrícula', () => _auto()),
            _chip(Icons.auto_awesome_mosaic, 'Mosaico', () => _auto(mosaic: true)),
            _chip(Icons.add_photo_alternate, 'Agregar imagen', _addImage),
            _chip(Icons.crop_square, 'Forma', sel == null ? null : () => setState(() => sel.shape = (sel.shape + 1) % 4)),
            _chip(Icons.rotate_90_degrees_cw, 'Girar 90°', sel == null ? null : () => setState(() => sel.rot += 1.5707963)),
            _chip(Icons.flip_to_front, 'Al frente', sel == null
                ? null
                : () => setState(() {
                      _layers.add(_layers.removeAt(_sel));
                      _sel = _layers.length - 1;
                    })),
            _chip(Icons.delete_outline, 'Quitar', sel == null
                ? null
                : () => setState(() {
                      _layers.removeAt(_sel);
                      _sel = -1;
                    })),
          ]),
          const SizedBox(height: 20),
          Text('Estilo', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          Center(child: _preview()),
          const SizedBox(height: 8),
          Wrap(spacing: 8, runSpacing: 4, children: [
            for (final p in _presets)
              ActionChip(
                label: Text(p.$1),
                onPressed: () => setState(() {
                  _look.style = p.$2;
                  _look.color = p.$3.value;
                  _look.tapeColor = p.$3.value;
                }),
              ),
          ]),
          const SizedBox(height: 8),
          if (!_cassette) ...[
            Wrap(spacing: 8, runSpacing: 4, children: [
              for (var i = 0; i < kDiscStyles.length; i++)
                ChoiceChip(
                  label: Text(kDiscStyles[i]),
                  selected: _look.style == i,
                  onSelected: (_) => setState(() => _look.style = i),
                ),
            ]),
          ],
          const SizedBox(height: 8),
          Wrap(spacing: 8, runSpacing: 8, children: [
            for (final c in kDiscColors)
              GestureDetector(
                onTap: () => setState(() {
                  _look.color = c.value;
                  _look.tapeColor = c.value;
                }),
                child: Container(
                  width: 34,
                  height: 34,
                  decoration: BoxDecoration(
                    color: c,
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: (_cassette ? _look.tapeColor : _look.color) == c.value ? Colors.white : Colors.white24,
                      width: 2.5,
                    ),
                  ),
                ),
              ),
            if (_cassette)
              ActionChip(label: const Text('Según portada'), onPressed: () => setState(() => _look.tapeColor = 0)),
          ]),
          if (!_cassette) ...[
            const SizedBox(height: 12),
            TextField(
              controller: _labelCtl,
              decoration: const InputDecoration(labelText: 'Texto curvo de la etiqueta (vacío = artista)', border: OutlineInputBorder()),
              onChanged: (t) => setState(() => _look.labelText = t.trim()),
            ),
            const SizedBox(height: 8),
            Row(children: [
              const Text('Numeración'),
              IconButton(onPressed: _look.volume > 0 ? () => setState(() => _look.volume--) : null, icon: const Icon(Icons.remove_circle_outline)),
              Text(_look.volume == 0 ? 'sin número' : 'Vol. ${_look.volume}'),
              IconButton(onPressed: () => setState(() => _look.volume++), icon: const Icon(Icons.add_circle_outline)),
            ]),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Sello propio (icono de la app)'),
              value: _look.stamp,
              onChanged: (v) => setState(() => _look.stamp = v),
            ),
          ],
        ],
      ),
    );
  }

  static const _presets = <(String, int, Color)>[
    ('Medianoche', 3, Color(0xFF1565C0)),
    ('Sangre', 6, Color(0xFFC62828)),
    ('Hielo', 5, Color(0xFF00838F)),
    ('Oro', 4, Color(0xFFFBC02D)),
    ('Bruma', 2, Color(0xFF455A64)),
    ('Jade', 1, Color(0xFF2E7D32)),
  ];

  Widget _preview() {
    final cover = _layers.isNotEmpty ? _layers.first.url : null;
    final v = Vinyl(
      id: 'cust_preview',
      title: _title.text.trim().isEmpty ? 'Título' : _title.text.trim(),
      artist: _artist.text.trim().isEmpty ? 'Mezclas' : _artist.text.trim(),
      year: DateTime.now().year,
      hue: 210,
      tracks: const [],
      coverUrl: cover,
    );
    if (_cassette) return SizedBox(height: 220, child: CassetteCard(vinyl: v, look: _look));
    return VinylDisc(vinyl: v, diameter: 220, tracks: math.max(1, _tracks.length), look: _look);
  }
}

/// Elige temas de toda la biblioteca.
class _TrackPicker extends StatefulWidget {
  const _TrackPicker({required this.all, required this.chosen});
  final List<PickedTrack> all;
  final Set<String> chosen;

  @override
  State<_TrackPicker> createState() => _TrackPickerState();
}

class _TrackPickerState extends State<_TrackPicker> {
  String _q = '';
  final Set<String> _on = {};

  List<PickedTrack> get _list {
    final q = _q.trim().toLowerCase();
    final l = [
      for (final t in widget.all)
        if (!widget.chosen.contains(t.url) && (q.isEmpty || t.title.toLowerCase().contains(q) || t.artist.toLowerCase().contains(q))) t,
    ];
    return q.isEmpty ? l.take(300).toList() : l.take(600).toList();
  }

  @override
  Widget build(BuildContext context) {
    final list = _list;
    return Scaffold(
      appBar: AppBar(
        title: TextField(
          autofocus: false,
          decoration: const InputDecoration(hintText: 'Buscar tema o artista', border: InputBorder.none),
          onChanged: (s) => setState(() => _q = s),
        ),
        actions: [
          TextButton(
            onPressed: () => setState(() => _on.addAll(list.map((t) => t.url))),
            child: const Text('Todos'),
          ),
        ],
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: FilledButton(
            onPressed: _on.isEmpty
                ? null
                : () => Navigator.of(context).pop([for (final t in widget.all) if (_on.contains(t.url)) t]),
            child: Text('Agregar ${_on.length}'),
          ),
        ),
      ),
      body: ListView.builder(
        itemCount: list.length,
        itemBuilder: (_, i) {
          final t = list[i];
          return CheckboxListTile(
            dense: true,
            value: _on.contains(t.url),
            onChanged: (v) => setState(() => v == true ? _on.add(t.url) : _on.remove(t.url)),
            title: Text(t.title, maxLines: 1, overflow: TextOverflow.ellipsis),
            subtitle: Text(t.artist, maxLines: 1, overflow: TextOverflow.ellipsis),
          );
        },
      ),
    );
  }
}

/// Biblioteca de imágenes (las portadas de tu biblioteca) para sumar al collage.
class _CoverPicker extends StatelessWidget {
  const _CoverPicker({required this.store, required this.urls});
  final VinylStore store;
  final List<String> urls;

  @override
  Widget build(BuildContext context) {
    final shown = urls.take(600).toList();
    return Scaffold(
      appBar: AppBar(title: const Text('Elige una imagen')),
      body: GridView.builder(
        padding: const EdgeInsets.all(8),
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: 3, mainAxisSpacing: 6, crossAxisSpacing: 6),
        itemCount: shown.length,
        itemBuilder: (_, i) => GestureDetector(
          onTap: () => Navigator.of(context).pop(shown[i]),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: buildCoverImage(shown[i], cacheWidth: 240, fallback: const ColoredBox(color: Color(0xFF2A2A33))),
          ),
        ),
      ),
    );
  }
}
