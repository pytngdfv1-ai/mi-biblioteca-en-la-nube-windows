import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../data/musicbrainz.dart';
import '../data/vinyl_store.dart';
import '../models/vinyl.dart';
import '../widgets/cover_art.dart';
import 'library_actions.dart';

/// Línea de tiempo: la biblioteca ordenada por año de lanzamiento, con los años detectados.
class TimelineScreen extends StatefulWidget {
  const TimelineScreen({super.key, required this.store});
  final VinylStore store;

  @override
  State<TimelineScreen> createState() => _TimelineScreenState();
}

class _TimelineScreenState extends State<TimelineScreen> {
  static const _key = 'timeline_years_v1';
  Map<String, int> _found = {};
  bool _newestFirst = false;
  bool _busy = false;
  int _done = 0, _total = 0;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final p = await SharedPreferences.getInstance();
      final raw = p.getString(_key);
      if (raw != null && mounted) {
        setState(() => _found = {for (final e in (jsonDecode(raw) as Map).entries) e.key as String: (e.value as num).toInt()});
      }
    } catch (_) {}
  }

  int _year(Vinyl v) => v.year > 0 ? v.year : (_found[v.id] ?? 0);

  List<Vinyl> get _all => [for (final v in widget.store.items) if (!v.isDivider) v];

  Future<void> _detect() async {
    final todo = [for (final v in _all) if (_year(v) == 0 && !v.single) v].take(40).toList();
    if (todo.isEmpty) return;
    setState(() {
      _busy = true;
      _done = 0;
      _total = todo.length;
    });
    for (final v in todo) {
      try {
        final r = await MusicBrainz.release(v.artist, v.title);
        if (r != null && r.year > 0) _found[v.id] = r.year;
      } catch (_) {}
      if (mounted) setState(() => _done++);
    }
    try {
      final p = await SharedPreferences.getInstance();
      await p.setString(_key, jsonEncode(_found));
    } catch (_) {}
    if (mounted) setState(() => _busy = false);
  }

  @override
  Widget build(BuildContext context) {
    final byYear = <int, List<Vinyl>>{};
    for (final v in _all) {
      (byYear[_year(v)] ??= []).add(v);
    }
    final years = byYear.keys.where((y) => y > 0).toList()..sort();
    if (_newestFirst) years.setAll(0, years.reversed.toList());
    final noYear = byYear[0] ?? const <Vinyl>[];
    final items = <Widget>[];
    int? decade;
    for (final y in years) {
      final d = y ~/ 10 * 10;
      if (d != decade) {
        decade = d;
        items.add(Padding(
          padding: const EdgeInsets.fromLTRB(16, 20, 16, 4),
          child: Text(d >= 2000 ? 'Década de $d' : 'Años ${(d % 100).toString().padLeft(2, '0')}',
              style: const TextStyle(color: Colors.amber, fontWeight: FontWeight.w800, letterSpacing: 1)),
        ));
      }
      items.add(_row(context, '$y', byYear[y]!));
    }
    if (noYear.isNotEmpty) items.add(_row(context, 'Sin año', noYear));
    return Scaffold(
      appBar: AppBar(
        title: const Text('Línea de tiempo'),
        actions: [
          IconButton(
            tooltip: _newestFirst ? 'Del más antiguo' : 'Del más reciente',
            icon: Icon(_newestFirst ? Icons.arrow_downward : Icons.arrow_upward),
            onPressed: () => setState(() => _newestFirst = !_newestFirst),
          ),
          IconButton(
            tooltip: 'Detectar años que faltan',
            icon: const Icon(Icons.manage_search),
            onPressed: _busy ? null : _detect,
          ),
        ],
        bottom: _busy
            ? PreferredSize(
                preferredSize: const Size.fromHeight(3),
                child: LinearProgressIndicator(value: _total == 0 ? null : _done / _total),
              )
            : null,
      ),
      body: items.isEmpty ? const Center(child: Text('Sin discos')) : ListView(padding: const EdgeInsets.only(bottom: 40), children: items),
    );
  }

  Widget _row(BuildContext context, String label, List<Vinyl> list) {
    return IntrinsicHeight(
      child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        SizedBox(
          width: 64,
          child: Column(children: [
            Container(width: 2, height: 10, color: Colors.white24),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
              decoration: BoxDecoration(color: Colors.amber, borderRadius: BorderRadius.circular(10)),
              child: Text(label, style: const TextStyle(color: Colors.black, fontSize: 11, fontWeight: FontWeight.w800)),
            ),
            Expanded(child: Container(width: 2, color: Colors.white24)),
          ]),
        ),
        Expanded(
          child: SizedBox(
            height: 112,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.only(right: 12, top: 8, bottom: 8),
              itemCount: list.length,
              separatorBuilder: (_, __) => const SizedBox(width: 8),
              itemBuilder: (_, i) => GestureDetector(
                onTap: () => openStage(context, widget.store, list[i]),
                child: SizedBox(width: 96, height: 96, child: CoverArt(vinyl: list[i], radius: 6)),
              ),
            ),
          ),
        ),
      ]),
    );
  }
}
