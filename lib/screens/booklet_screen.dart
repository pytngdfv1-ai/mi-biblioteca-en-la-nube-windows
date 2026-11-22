import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:pdfx/pdfx.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../audio/player_service.dart';

import '../data/booklet_lite.dart';
import '../data/fetch_bytes.dart';
import '../data/images_to_pdf.dart';
import '../data/vinyl_store.dart';
import '../models/vinyl.dart';
import '../widgets/cover_art.dart';

/// Libreto del álbum: páginas (imágenes) y PDFs, todo dentro de la app.
class BookletScreen extends StatelessWidget {
  const BookletScreen({super.key, required this.vinyl, this.store});

  final Vinyl vinyl;
  final VinylStore? store;

  static String _name(String url) {
    var n = Uri.parse(url).pathSegments.lastWhere((s) => s.isNotEmpty, orElse: () => 'PDF');
    try {
      n = Uri.decodeComponent(n);
    } catch (_) {}
    return n.replaceAll(RegExp(r'\.pdf$', caseSensitive: false), '');
  }

  static String _stem(String url) {
    var n = Uri.parse(url).pathSegments.lastWhere((s) => s.isNotEmpty, orElse: () => '');
    try {
      n = Uri.decodeComponent(n);
    } catch (_) {}
    final i = n.lastIndexOf('.');
    return i > 0 ? n.substring(0, i) : n;
  }

  @override
  Widget build(BuildContext context) {
    // Las páginas livianas guardadas junto a un PDF se muestran en la pestaña de ese PDF.
    final images = [for (final u in vinyl.booklet) if (!BookletLite.isLitePage(u)) u];
    // Versiones livianas hechas por el agente: 'Libreto liviano - imagenes/<nombre>.webp'.
    final lite = <String, String>{
      for (final u in vinyl.booklet)
        if (Uri.decodeFull(Uri.parse(u).removeFragment().path).contains('/Libreto liviano - imagenes/')) _stem(u): u,
    };
    final tabs = <String>[
      if (images.isNotEmpty) 'Imágenes (${images.length})',
      for (final p in vinyl.pdfs) _name(p),
    ];
    final views = <Widget>[
      if (images.isNotEmpty) _ImagesTab(vinyl: vinyl, store: store, urls: images, lite: lite),
      for (final p in vinyl.pdfs) _PdfTab(url: p, remote: BookletLite.remotePages(vinyl, p)),
    ];
    return DefaultTabController(
      length: tabs.length,
      child: Scaffold(
        backgroundColor: Colors.black,
        appBar: AppBar(
          backgroundColor: Colors.black,
          title: Text('Libreto · ${vinyl.title}', maxLines: 1, overflow: TextOverflow.ellipsis),
          bottom: tabs.length > 1
              ? TabBar(isScrollable: true, tabs: [for (final t in tabs) Tab(text: t)])
              : null,
        ),
        body: TabBarView(
          physics: const NeverScrollableScrollPhysics(),
          children: views,
        ),
        bottomNavigationBar: const _ReadingBar(),
      ),
    );
  }
}

/// Pestaña de imágenes: visor y botón para crear un PDF con ellas.
class _ImagesTab extends StatefulWidget {
  const _ImagesTab({required this.vinyl, required this.store, required this.urls, this.lite = const {}});

  final Map<String, String> lite;
  final Vinyl vinyl;
  final VinylStore? store;
  final List<String> urls;

  @override
  State<_ImagesTab> createState() => _ImagesTabState();
}

class _ImagesTabState extends State<_ImagesTab> with AutomaticKeepAliveClientMixin {
  String? _progress;
  String? _msg;
  bool _grid = false;
  int _start = 0;
  List<String> _order = [];

  String get _prefKey => 'booklet_order_${widget.vinyl.id}';

  @override
  void initState() {
    super.initState();
    SharedPreferences.getInstance().then((p) {
      final raw = p.getString(_prefKey);
      if (raw != null && mounted) setState(() => _order = List<String>.from(jsonDecode(raw) as List));
    }).catchError((_) {});
  }

  /// Páginas en el orden elegido (las nuevas al final, en orden natural).
  List<String> get _ordered {
    if (_order.isEmpty) return widget.urls;
    final idx = {for (var i = 0; i < _order.length; i++) _order[i]: i};
    final l = [...widget.urls];
    l.sort((a, b) => (idx[a] ?? 1 << 20).compareTo(idx[b] ?? 1 << 20));
    return l;
  }

  String _show(String u) => widget.lite[BookletScreen._stem(u)] ?? u;

  Future<void> _reorder() async {
    final l = [..._ordered];
    final res = await showDialog<List<String>>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setL) => AlertDialog(
          title: const Text('Orden de las páginas'),
          content: SizedBox(
            width: double.maxFinite,
            height: 380,
            child: ReorderableListView(
              onReorder: (a, b) => setL(() {
                if (b > a) b--;
                l.insert(b, l.removeAt(a));
              }),
              children: [
                for (var i = 0; i < l.length; i++)
                  ListTile(
                    key: ValueKey(l[i]),
                    dense: true,
                    leading: SizedBox(width: 36, height: 36, child: buildCoverImage(_show(l[i]), cacheWidth: 120, fit: BoxFit.cover, fallback: const SizedBox())),
                    title: Text('Página ${i + 1}'),
                    trailing: const Icon(Icons.drag_handle),
                  ),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancelar')),
            TextButton(onPressed: () => Navigator.pop(ctx, <String>[]), child: const Text('Orden natural')),
            FilledButton(onPressed: () => Navigator.pop(ctx, l), child: const Text('Guardar')),
          ],
        ),
      ),
    );
    if (res == null) return;
    try {
      final p = await SharedPreferences.getInstance();
      if (res.isEmpty) {
        await p.remove(_prefKey);
      } else {
        await p.setString(_prefKey, jsonEncode(res));
      }
    } catch (_) {}
    if (mounted) setState(() => _order = res);
  }

  @override
  bool get wantKeepAlive => true;

  Future<void> _makePdf() async {
    setState(() {
      _msg = null;
      _progress = 'Preparando…';
    });
    try {
      final bytes = await ImagesToPdf.build(
        _ordered,
        onProgress: (d, t) {
          if (mounted) setState(() => _progress = '$d / $t');
        },
      );
      final url = await ImagesToPdf.saveInAlbumFolder(widget.vinyl, bytes);
      await widget.store?.addPdf(widget.vinyl.id, url);
      final name = Uri.decodeFull(Uri.parse(url).pathSegments.last);
      if (mounted) {
        setState(() => _msg = 'PDF creado en la carpeta del disco: $name');
      }
    } catch (e) {
      if (mounted) setState(() => _msg = 'No se pudo crear el PDF: $e');
    }
    if (mounted) setState(() => _progress = null);
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          child: Row(
            children: [
              if (_progress != null) ...[
                const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)),
                const SizedBox(width: 10),
                Text('Creando PDF… $_progress'),
              ] else
                TextButton.icon(
                  icon: const Icon(Icons.picture_as_pdf_outlined),
                  label: const Text('Crear PDF con estas imágenes'),
                  onPressed: _makePdf,
                ),
              const Spacer(),
              IconButton(
                tooltip: _grid ? 'Ver páginas' : 'Ver galería',
                icon: Icon(_grid ? Icons.view_carousel_outlined : Icons.grid_view),
                onPressed: () => setState(() => _grid = !_grid),
              ),
              IconButton(tooltip: 'Orden de las páginas', icon: const Icon(Icons.swap_vert), onPressed: _reorder),
            ],
          ),
        ),
        if (_msg != null)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Text(_msg!, style: const TextStyle(fontSize: 12, color: Colors.white70)),
          ),
        Expanded(
          child: _grid
              ? GridView.builder(
                  padding: const EdgeInsets.all(8),
                  gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(maxCrossAxisExtent: 150, mainAxisSpacing: 6, crossAxisSpacing: 6),
                  itemCount: _ordered.length,
                  itemBuilder: (_, i) => GestureDetector(
                    onTap: () => setState(() {
                      _start = i;
                      _grid = false;
                    }),
                    child: buildCoverImage(_show(_ordered[i]), cacheWidth: 400, fit: BoxFit.cover, fallback: const SizedBox()),
                  ),
                )
              : _Pages(key: ValueKey('p$_start${_order.length}'), urls: [for (final u in _ordered) _show(u)], initial: _start),
        ),
      ],
    );
  }
}

/// Imágenes del libreto: desliza para cambiar de página, pellizca para ampliar.
class _Pages extends StatefulWidget {
  const _Pages({super.key, required this.urls, this.initial = 0});

  final List<String> urls;
  final int initial;

  @override
  State<_Pages> createState() => _PagesState();
}

class _PagesState extends State<_Pages> {
  late int _page = widget.initial.clamp(0, widget.urls.isEmpty ? 0 : widget.urls.length - 1);
  late final PageController _pc = PageController(initialPage: _page);

  @override
  void dispose() {
    _pc.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    const broken = Center(child: Icon(Icons.broken_image_outlined, color: Colors.white38, size: 48));
    return Stack(
      children: [
        PageView.builder(
          controller: _pc,
          itemCount: widget.urls.length,
          onPageChanged: (i) => setState(() => _page = i),
          itemBuilder: (_, i) => InteractiveViewer(
            minScale: 1,
            maxScale: 5,
            child: Center(
              child: buildCoverImage(
                widget.urls[i],
                cacheWidth: 1600,
                fit: BoxFit.contain,
                fallback: broken,
              ),
            ),
          ),
        ),
        Positioned(
          left: 0,
          right: 0,
          bottom: 16,
          child: Center(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
              decoration: BoxDecoration(
                color: Colors.black54,
                borderRadius: BorderRadius.circular(16),
              ),
              child: Text('${_page + 1} / ${widget.urls.length}'),
            ),
          ),
        ),
      ],
    );
  }
}

/// Un PDF del álbum: se puede ver el original o su versión liviana (imágenes WebP).
class _PdfTab extends StatefulWidget {
  const _PdfTab({required this.url, this.remote});

  final String url;

  /// Páginas livianas ya guardadas junto al PDF (hechas en otro equipo).
  final List<String>? remote;

  @override
  State<_PdfTab> createState() => _PdfTabState();
}

class _PdfTabState extends State<_PdfTab> with AutomaticKeepAliveClientMixin {
  PdfDocument? _ctl;
  String? _error;
  String? _progress; // "3 / 12" mientras convierte
  int _liteBytes = 0;

  @override
  bool get wantKeepAlive => true;

  List<String>? get _pages => BookletLite.pagesOf(widget.url) ?? widget.remote;
  bool get _lite => _pages != null && BookletLite.preferLite(widget.url);

  @override
  void initState() {
    super.initState();
    _afterChange();
  }

  Future<void> _afterChange() async {
    if (BookletLite.pagesOf(widget.url) != null) {
      final n = await BookletLite.sizeOf(widget.url);
      if (mounted) setState(() => _liteBytes = n);
    }
    if (!_lite) await _loadPdf();
  }

  Future<void> _loadPdf() async {
    if (_ctl != null) return;
    try {
      final bytes = await fetchBytes(widget.url);
      if (!mounted) return;
      final doc = await PdfDocument.openData(bytes);
      if (!mounted) {
        await doc.close();
        return;
      }
      setState(() => _ctl = doc);
    } catch (e) {
      if (mounted) setState(() => _error = 'No se pudo abrir el PDF: $e');
    }
  }

  Future<void> _convert() async {
    setState(() {
      _error = null;
      _progress = 'Preparando…';
    });
    try {
      await BookletLite.convert(
        widget.url,
        onProgress: (d, t) {
          if (mounted) setState(() => _progress = '$d / $t');
        },
      );
      _liteBytes = await BookletLite.sizeOf(widget.url);
      _error = BookletLite.lastNote;
    } catch (e) {
      _error = 'No se pudo convertir: $e';
    }
    if (mounted) setState(() => _progress = null);
  }

  Future<void> _setLite(bool v) async {
    await BookletLite.setUseLite(widget.url, v);
    if (mounted) setState(() {});
    if (!v) await _loadPdf();
  }

  Future<void> _remove() async {
    await BookletLite.remove(widget.url);
    if (mounted) setState(() => _liteBytes = 0);
    await _loadPdf();
  }

  @override
  void dispose() {
    _ctl?.close();
    super.dispose();
  }

  Future<void> _showText() async {
    final u = Uri.parse(widget.url);
    final segs = [...u.pathSegments];
    var stem = Uri.decodeComponent(segs.last);
    stem = stem.replaceAll(RegExp(r'\.pdf$', caseSensitive: false), '');
    segs[segs.length - 1] = 'Texto - $stem.txt';
    String? text;
    try {
      text = utf8.decode(await fetchBytes(u.replace(pathSegments: segs).toString()));
    } catch (_) {}
    if (!mounted) return;
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF16161B),
      builder: (_) => _TextSheet(text: text),
    );
  }

  String _mb(int b) => '${(b / 1048576).toStringAsFixed(1)} MB';

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final hasLite = _pages != null;
    final hasLocal = BookletLite.pagesOf(widget.url) != null;
    final useLite = _lite;
    final c = _ctl;

    Widget body;
    if (useLite) {
      body = _Pages(urls: _pages!);
    } else if (_error != null && c == null) {
      body = Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(_error!, textAlign: TextAlign.center),
        ),
      );
    } else if (c == null) {
      body = const Center(child: CircularProgressIndicator());
    } else {
      body = _PdfPages(doc: c);
    }

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          child: Row(
            children: [
              if (_progress != null) ...[
                const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)),
                const SizedBox(width: 10),
                Text('Convirtiendo… $_progress'),
              ] else if (hasLite) ...[
                Expanded(
                  child: SegmentedButton<bool>(
                    showSelectedIcon: false,
                    segments: [
                      const ButtonSegment(value: false, label: Text('PDF original')),
                      ButtonSegment(value: true, label: Text(hasLocal ? 'Liviana · ${_mb(_liteBytes)}' : 'Liviana (nube)')),
                    ],
                    selected: {useLite},
                    onSelectionChanged: (s) => _setLite(s.first),
                  ),
                ),
                if (hasLocal)
                  IconButton(
                    tooltip: 'Quitar versión liviana',
                    icon: const Icon(Icons.delete_outline),
                    onPressed: _remove,
                  ),
              ] else
                TextButton.icon(
                  icon: const Icon(Icons.compress),
                  label: const Text('Convertir a versión liviana'),
                  onPressed: _convert,
                ),
              IconButton(tooltip: 'Texto del libreto (buscar, copiar letras)', icon: const Icon(Icons.text_snippet_outlined), onPressed: _showText),
              if (_error != null && c != null) const Icon(Icons.error_outline, color: Colors.redAccent),
            ],
          ),
        ),
        if (_error != null && (c != null || useLite))
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Text(_error!, style: const TextStyle(color: Colors.redAccent, fontSize: 12)),
          ),
        Expanded(child: body),
      ],
    );
  }
}


/// Páginas del PDF dibujadas como imagen (funciona igual en Windows); muestra el error real si falla.
class _PdfPages extends StatefulWidget {
  const _PdfPages({required this.doc});

  final PdfDocument doc;

  @override
  State<_PdfPages> createState() => _PdfPagesState();
}

class _PdfPagesState extends State<_PdfPages> {
  final Map<int, Future<Uint8List>> _pages = {};

  Future<Uint8List> _render(int n) {
    return _pages.putIfAbsent(n, () async {
      final page = await widget.doc.getPage(n);
      try {
        const targetW = 1400.0;
        final img = await page.render(
          width: targetW,
          height: targetW * page.height / page.width,
          format: PdfPageImageFormat.png,
          backgroundColor: '#FFFFFF',
        );
        if (img == null) throw Exception('No se pudo dibujar la página $n');
        return img.bytes;
      } finally {
        await page.close();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return InteractiveViewer(
      minScale: 1,
      maxScale: 5,
      child: ListView.builder(
        padding: const EdgeInsets.symmetric(vertical: 8),
        itemCount: widget.doc.pagesCount,
        itemBuilder: (_, i) => Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          child: FutureBuilder<Uint8List>(
            future: _render(i + 1),
            builder: (_, snap) {
              if (snap.hasError) {
                return Padding(
                  padding: const EdgeInsets.all(16),
                  child: SelectableText('Página ${i + 1}: ${snap.error}',
                      style: const TextStyle(color: Colors.redAccent)),
                );
              }
              if (!snap.hasData) {
                return const SizedBox(height: 300, child: Center(child: CircularProgressIndicator()));
              }
              return Image.memory(snap.data!, fit: BoxFit.fitWidth, gaplessPlayback: true);
            },
          ),
        ),
      ),
    );
  }
}


/// Barra de reproducción para leer el libreto mientras suena el disco.
class _ReadingBar extends StatelessWidget {
  const _ReadingBar();

  @override
  Widget build(BuildContext context) {
    final ps = PlayerService.instance;
    return ValueListenableBuilder(
      valueListenable: ps.nowPlaying,
      builder: (_, v, __) {
        if (v == null) return const SizedBox.shrink();
        return StreamBuilder<bool>(
          stream: ps.player.playingStream,
          builder: (_, snap) {
            final playing = snap.data ?? false;
            final i = (ps.player.currentIndex ?? 0).clamp(0, v.tracks.isEmpty ? 0 : v.tracks.length - 1).toInt();
            return Container(
              color: const Color(0xFF17171C),
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: SafeArea(
                top: false,
                child: Row(children: [
                  SizedBox(width: 36, height: 36, child: CoverArt(vinyl: v, radius: 4)),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(v.tracks.isEmpty ? v.title : v.tracks[i], maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 13)),
                  ),
                  IconButton(icon: const Icon(Icons.skip_previous), onPressed: () => ps.goTrack(i - 1)),
                  IconButton(
                    icon: Icon(playing ? Icons.pause : Icons.play_arrow),
                    onPressed: () => playing ? ps.player.pause() : ps.player.play(),
                  ),
                  IconButton(icon: const Icon(Icons.skip_next), onPressed: () => ps.goTrack(i + 1)),
                ]),
              ),
            );
          },
        );
      },
    );
  }
}


/// Texto del libreto (lo prepara el agente con OCR): buscar y copiar.
class _TextSheet extends StatefulWidget {
  const _TextSheet({required this.text});
  final String? text;

  @override
  State<_TextSheet> createState() => _TextSheetState();
}

class _TextSheetState extends State<_TextSheet> {
  String _q = '';

  @override
  Widget build(BuildContext context) {
    final t = widget.text;
    final h = MediaQuery.of(context).size.height * .8;
    if (t == null || t.trim().isEmpty) {
      return SizedBox(
        height: 160,
        child: const Center(child: Padding(padding: EdgeInsets.all(24), child: Text('Todavía no hay texto de este libreto. Lo prepara el agente de la nube.', textAlign: TextAlign.center))),
      );
    }
    final q = _q.trim().toLowerCase();
    final lines = t.split('\n');
    final shown = q.isEmpty ? lines : lines.where((l) => l.toLowerCase().contains(q)).toList();
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: SizedBox(
        height: h,
        child: Column(children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 12, 4, 4),
            child: Row(children: [
              Expanded(child: TextField(decoration: const InputDecoration(hintText: 'Buscar en el libreto', prefixIcon: Icon(Icons.search), isDense: true), onChanged: (v) => setState(() => _q = v))),
              IconButton(
                tooltip: 'Copiar todo',
                icon: const Icon(Icons.copy),
                onPressed: () {
                  Clipboard.setData(ClipboardData(text: t));
                  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Texto copiado')));
                },
              ),
            ]),
          ),
          Expanded(
            child: shown.isEmpty
                ? const Center(child: Text('Sin resultados'))
                : ListView(padding: const EdgeInsets.all(14), children: [SelectableText(shown.join('\n'), style: const TextStyle(height: 1.4, fontSize: 14))]),
          ),
        ]),
      ),
    );
  }
}
