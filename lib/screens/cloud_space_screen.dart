import 'package:flutter/material.dart';

import '../data/koofr_client.dart';
import '../data/koofr_settings.dart';

/// Espacio total y usado de cada nube conectada.
class CloudSpaceScreen extends StatefulWidget {
  const CloudSpaceScreen({super.key});

  @override
  State<CloudSpaceScreen> createState() => _CloudSpaceScreenState();
}

class _CloudSpaceScreenState extends State<CloudSpaceScreen> {
  final Map<String, (int, int?)?> _q = {};
  final Set<String> _done = {};

  @override
  void initState() {
    super.initState();
    for (final a in KoofrAccounts.list) {
      KoofrClient(a).quota().then((r) {
        if (mounted) {
          setState(() {
            _q[a.id] = r;
            _done.add(a.id);
          });
        }
      }).catchError((_) {
        if (mounted) setState(() => _done.add(a.id));
      });
    }
  }

  static String _fmt(num b) {
    const u = ['B', 'KB', 'MB', 'GB', 'TB'];
    var x = b.toDouble(), i = 0;
    while (x >= 1024 && i < u.length - 1) {
      x /= 1024;
      i++;
    }
    return '${x.toStringAsFixed(i < 2 ? 0 : 1)} ${u[i]}';
  }

  @override
  Widget build(BuildContext context) {
    final accts = KoofrAccounts.list;
    return Scaffold(
      appBar: AppBar(title: const Text('Espacio en las nubes')),
      body: accts.isEmpty
          ? const Center(child: Text('No hay nubes conectadas'))
          : ListView(padding: const EdgeInsets.all(16), children: [
              for (final a in accts) _card(a),
            ]),
    );
  }

  Widget _card(KoofrSettings a) {
    final q = _q[a.id];
    final loading = !_done.contains(a.id);
    Widget body;
    if (loading) {
      body = const LinearProgressIndicator();
    } else if (q == null) {
      body = const Text('La nube no informa su espacio.', style: TextStyle(color: Colors.white60));
    } else {
      final used = q.$1, avail = q.$2;
      final total = avail == null ? null : used + avail;
      final frac = total == null || total == 0 ? null : (used / total).clamp(0.0, 1.0);
      body = Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        if (frac != null) LinearProgressIndicator(value: frac, minHeight: 8, borderRadius: BorderRadius.circular(4)),
        const SizedBox(height: 8),
        Text(total == null
            ? 'Usado: ${_fmt(used)}'
            : 'Usado ${_fmt(used)} de ${_fmt(total)} · libre ${_fmt(avail!)} (${(frac! * 100).round()} %)'),
        if (frac != null && frac > .9)
          const Padding(
            padding: EdgeInsets.only(top: 4),
            child: Text('Queda poco espacio', style: TextStyle(color: Colors.redAccent)),
          ),
      ]);
    }
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            const Icon(Icons.cloud_outlined),
            const SizedBox(width: 8),
            Expanded(child: Text(a.name, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16))),
          ]),
          const SizedBox(height: 10),
          body,
        ]),
      ),
    );
  }
}
