import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Historial de actualizaciones: cada versión es un título; al tocarla se ve lo que se agregó y lo que se quitó.
class NovedadesScreen extends StatefulWidget {
  const NovedadesScreen({super.key});

  @override
  State<NovedadesScreen> createState() => _NovedadesScreenState();
}

class _NovedadesScreenState extends State<NovedadesScreen> {
  List<dynamic> _items = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    rootBundle.loadString('assets/novedades.json').then((s) {
      if (mounted) {
        setState(() {
          _items = jsonDecode(s) as List<dynamic>;
          _loading = false;
        });
      }
    }).catchError((_) {
      if (mounted) setState(() => _loading = false);
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Novedades')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _items.isEmpty
              ? const Center(child: Text('Sin datos'))
              : ListView.builder(
                  itemCount: _items.length,
                  itemBuilder: (_, i) {
                    final e = _items[i] as Map<String, dynamic>;
                    final add = (e['agrega'] as List).cast<String>();
                    final del = (e['quita'] as List).cast<String>();
                    final v = e['v'] as String;
                    return ExpansionTile(
                      shape: const Border(),
                      title: Text(e['titulo'] as String, style: const TextStyle(fontWeight: FontWeight.w700)),
                      subtitle: Text(RegExp(r'^\d').hasMatch(v) ? 'Versión $v' : v, style: const TextStyle(color: Color(0xFFFF8A3D), fontSize: 12)),
                      childrenPadding: const EdgeInsets.fromLTRB(18, 0, 18, 12),
                      expandedCrossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (add.isNotEmpty) ...[
                          const Text('Se agregó', style: TextStyle(color: Color(0xFF9CCC65), fontWeight: FontWeight.w800)),
                          for (final a in add) Padding(padding: const EdgeInsets.only(top: 4), child: Text('• $a')),
                        ],
                        if (del.isNotEmpty) ...[
                          SizedBox(height: add.isNotEmpty ? 10 : 0),
                          const Text('Se quitó', style: TextStyle(color: Color(0xFFFF8A80), fontWeight: FontWeight.w800)),
                          for (final a in del) Padding(padding: const EdgeInsets.only(top: 4), child: Text('• $a')),
                        ],
                      ],
                    );
                  },
                ),
    );
  }
}
