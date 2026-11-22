import 'package:flutter/material.dart';

import '../audio/player_service.dart';
import '../data/cajon.dart';
import '../data/vinyl_store.dart';
import '../models/vinyl.dart';
import '../widgets/lookup_cover.dart';
import 'info_screen.dart';
import 'library_actions.dart';

/// Hojear: portadas y fichas de las mismas bibliotecas, sin sonido salvo que lo pidas.
class BrowseScreen extends StatefulWidget {
  const BrowseScreen({super.key, required this.store});
  final VinylStore store;

  @override
  State<BrowseScreen> createState() => _BrowseScreenState();
}

class _BrowseScreenState extends State<BrowseScreen> {
  int _lib = -1; // -1 = todas
  String _q = '';

  List<Vinyl> get _list {
    final q = _q.trim().toLowerCase();
    return [
      for (final v in widget.store.items)
        if (!v.isDivider &&
            (_lib < 0 || Cajon.all[_lib].matches(v)) &&
            (q.isEmpty || v.title.toLowerCase().contains(q) || v.artist.toLowerCase().contains(q)))
          v
    ];
  }

  void _ficha(Vinyl v) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF16161B),
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(18))),
      builder: (ctx) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: .78,
        maxChildSize: .95,
        builder: (_, sc) => ListView(controller: sc, padding: const EdgeInsets.all(18), children: [
          Center(child: SizedBox(width: 220, height: 220, child: LookupCover(vinyl: v, radius: 8))),
          const SizedBox(height: 14),
          Text(v.title, textAlign: TextAlign.center, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: Colors.white)),
          Text(v.artist, textAlign: TextAlign.center, style: const TextStyle(color: Colors.white70, fontSize: 15)),
          const SizedBox(height: 8),
          Wrap(alignment: WrapAlignment.center, spacing: 8, children: [
            if (v.year > 0) Chip(label: Text('${v.year}')),
            if (v.genre != null && v.genre!.isNotEmpty) Chip(label: Text(v.genre!)),
            Chip(label: Text(v.lang == 'en' ? 'Inglés' : v.lang == 'es' ? 'Español' : 'Sin idioma')),
            Chip(label: Text(v.single ? 'Tema suelto' : '${v.tracks.length} temas')),
            if (v.cassette) const Chip(label: Text('Cassette')),
          ]),
          const SizedBox(height: 10),
          Row(children: [
            Expanded(
              child: FilledButton.icon(
                icon: const Icon(Icons.play_arrow),
                label: const Text('Escuchar'),
                onPressed: () {
                  Navigator.of(ctx).pop();
                  openStage(context, widget.store, v);
                },
              ),
            ),
            const SizedBox(width: 10),
            OutlinedButton.icon(
              icon: const Icon(Icons.article_outlined),
              label: const Text('Info'),
              onPressed: () => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => InfoScreen(vinyl: v, store: widget.store))),
            ),
            const SizedBox(width: 10),
            OutlinedButton.icon(
              icon: const Icon(Icons.bolt),
              label: const Text('Vista rápida'),
              onPressed: () async {
                // 15 s del primer tema, sin abrir el disco.
                try {
                  await PlayerService.instance.start(v);
                  Future.delayed(const Duration(seconds: 15), () => PlayerService.instance.player.pause());
                } catch (_) {}
              },
            ),
          ]),
          const Divider(height: 26),
          for (var i = 0; i < v.tracks.length; i++)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 3),
              child: Text('${i + 1}. ${v.tracks[i]}', style: const TextStyle(color: Color(0xFFD9D5C8))),
            ),
        ]),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final list = _list;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Hojear'),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(96),
          child: Column(children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: TextField(
                decoration: const InputDecoration(hintText: 'Buscar', prefixIcon: Icon(Icons.search), isDense: true),
                onChanged: (t) => setState(() => _q = t),
              ),
            ),
            SizedBox(
              height: 48,
              child: ListView(scrollDirection: Axis.horizontal, padding: const EdgeInsets.symmetric(horizontal: 8), children: [
                Padding(
                  padding: const EdgeInsets.all(4),
                  child: ChoiceChip(label: const Text('Todas'), selected: _lib < 0, onSelected: (_) => setState(() => _lib = -1)),
                ),
                for (var i = 0; i < Cajon.all.length; i++)
                  Padding(
                    padding: const EdgeInsets.all(4),
                    child: ChoiceChip(label: Text(Cajon.all[i].name), selected: _lib == i, onSelected: (_) => setState(() => _lib = i)),
                  ),
              ]),
            ),
          ]),
        ),
      ),
      body: list.isEmpty
          ? const Center(child: Text('Sin discos'))
          : GridView.builder(
              padding: const EdgeInsets.all(10),
              gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(maxCrossAxisExtent: 130, mainAxisSpacing: 8, crossAxisSpacing: 8),
              itemCount: list.length,
              itemBuilder: (_, i) => GestureDetector(onTap: () => _ficha(list[i]), child: LookupCover(vinyl: list[i])),
            ),
    );
  }
}
