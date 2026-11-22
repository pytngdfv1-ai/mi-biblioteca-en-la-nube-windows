import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;

import '../data/agent_index.dart';
import '../data/album_json.dart';
import '../data/fetch_bytes.dart';
import '../data/koofr_client.dart';
import '../data/koofr_settings.dart';
import '../data/vinyl_store.dart';
import '../models/vinyl.dart';
import 'info_screen.dart';

/// Todo lo del agente de la nube: resumen, pendientes, duplicados, historial, tareas y ejecutar.
class AgentScreen extends StatefulWidget {
  const AgentScreen({super.key, this.store});
  final VinylStore? store;

  @override
  State<AgentScreen> createState() => _AgentScreenState();
}

class _AgentScreenState extends State<AgentScreen> {
  KoofrSettings? _acc;
  bool _loading = true;
  String? _error;
  String _informe = '';
  String _pendientes = '';
  Map<String, dynamic> _estado = {};
  List<dynamic> _hist = [];
  List<Map<String, dynamic>> _faltas = [];

  @override
  void initState() {
    super.initState();
    _acc = KoofrAccounts.list.isEmpty ? null : KoofrAccounts.list.first;
    _load();
  }

  /// Carpeta donde el agente escribe (se detecta entre variantes: Música / Musica).
  String? _folder;
  String _diag = '';

  List<String> get _folders {
    final f = _acc!.folder.trim();
    return {f, f.replaceAll('ú', 'u').replaceAll('Ú', 'U'), f.replaceAll('u', 'ú'), 'Musica', 'Música', ''}.toList();
  }

  String _urlIn(String folder, String file) {
    final a = _acc!;
    final base = Uri.parse(a.baseUrl);
    final u = base.replace(pathSegments: [
      ...base.pathSegments.where((s) => s.isNotEmpty),
      ...folder.split('/').where((s) => s.isNotEmpty),
      '_agente',
      file,
    ]);
    return KoofrSettings.tag(u.toString(), a.id);
  }

  String _url(String file) => _urlIn(_folder ?? _acc!.folder, file);

  Future<String?> _read(String file) async {
    try {
      return utf8.decode(await fetchBytes(_url(file)));
    } catch (e) {
      _diag += '$file: ${e.toString().replaceAll(RegExp(r'https?://\S+'), '')}\n';
      return null;
    }
  }

  Future<void> _detectFolder() async {
    for (final f in _folders) {
      for (final file in const ['estado.json', 'informe.md']) {
        try {
          await fetchBytes(_urlIn(f, file));
          _folder = f;
          return;
        } catch (_) {}
      }
    }
    _folder = null;
  }

  Future<void> _load() async {
    if (_acc == null) {
      setState(() {
        _loading = false;
        _error = 'Primero conecta tu nube en Ajustes.';
      });
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
    });
    _diag = '';
    await _detectFolder();
    final r = await Future.wait([_read('informe.md'), _read('pendientes.md'), _read('estado.json'), _read('historial.json')]);
    final idx = await AgentIndex.entries(refresh: true);
    if (!mounted) return;
    setState(() {
      _faltas = [
        for (final e in idx)
          if (((e['falta'] as List?) ?? const []).isNotEmpty) e,
      ];
      _informe = r[0] ?? '';
      _pendientes = r[1] ?? '';
      try {
        _estado = r[2] == null ? {} : jsonDecode(r[2]!) as Map<String, dynamic>;
      } catch (_) {
        _estado = {};
      }
      try {
        _hist = r[3] == null ? [] : jsonDecode(r[3]!) as List<dynamic>;
      } catch (_) {
        _hist = [];
      }
      _loading = false;
      if (r.every((x) => x == null)) {
        _error = 'No encuentro la carpeta _agente en tu nube (probé: ${_folders.where((f) => f.isNotEmpty).join(', ')}).\n'
            'Si el agente aún no corrió, usa la pestaña Ejecutar.\n\n$_diag';
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 6,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Agente'),
          actions: [IconButton(tooltip: 'Actualizar', icon: const Icon(Icons.refresh), onPressed: _load)],
          bottom: const TabBar(isScrollable: true, tabs: [
            Tab(text: 'Resumen'),
            Tab(text: 'Pendientes'),
            Tab(text: 'Duplicados'),
            Tab(text: 'Historial'),
            Tab(text: 'Tareas'),
            Tab(text: 'Ejecutar'),
          ]),
        ),
        body: _loading
            ? const Center(child: CircularProgressIndicator())
            : TabBarView(children: [
                _resumen(),
                _pendientesTab(),
                _duplicados(),
                _historial(),
                _tareas(),
                _ejecutar(),
              ]),
      ),
    );
  }

  Widget _msg(String t) => Center(child: Padding(padding: const EdgeInsets.all(24), child: Text(t, textAlign: TextAlign.center)));

  // ---- Resumen ----
  Widget _resumen() {
    if (_informe.isEmpty) return ListView(padding: const EdgeInsets.all(20), children: [Text(_error ?? 'Sin informe todavía.')]);
    final lines = _informe.split('\n');
    return ListView(padding: const EdgeInsets.all(16), children: [
      for (final l in lines)
        if (l.startsWith('# '))
          Padding(padding: const EdgeInsets.only(bottom: 10), child: Text(l.substring(2), style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w800)))
        else if (l.trim().isNotEmpty)
          Padding(padding: const EdgeInsets.symmetric(vertical: 2), child: Text(l.replaceFirst(RegExp(r'^\s*-\s'), '• '), style: const TextStyle(height: 1.35))),
    ]);
  }

  // ---- Pendientes ----
  /// Abre la ficha del álbum del índice, en el campo que falta.
  void _abrirFicha(Map<String, dynamic> e, String campo) {
    final store = widget.store;
    Vinyl? found;
    if (store != null) {
      final ruta = AlbumJson.norm(('${e['ruta']}').split('/').where((x) => x.isNotEmpty));
      for (final v in store.items) {
        if (v.isDivider) continue;
        final dir = AlbumJson.of(v)?.dir;
        if (dir != null && AlbumJson.norm(dir) == ruta) {
          found = v;
          break;
        }
      }
      found ??= store.items.where((v) => !v.isDivider && AgentIndex.key(v.artist, v.title) == AgentIndex.key('${e['artista']}', '${e['titulo']}')).firstOrNull;
    }
    if (found == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('No encuentro ese álbum en la biblioteca. Sincroniza la nube.')));
      return;
    }
    Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => InfoScreen(vinyl: found!, focus: campo)));
  }

  Widget _pendientesTab() {
    final items = <String, List<(String, String)>>{};
    String? cur;
    for (final l in _pendientes.split('\n')) {
      if (l.startsWith('## ')) {
        cur = l.substring(3).trim();
        items[cur] = [];
      } else if (cur != null && l.startsWith('- ')) {
        final i = l.indexOf(': ');
        if (i > 0) items[cur]!.add((l.substring(2, i), l.substring(i + 2).trim()));
      }
    }
    if (items.isEmpty && _faltas.isEmpty) return _msg(_pendientes.isEmpty ? 'Sin datos.' : 'Nada pendiente.');
    return ListView(children: [
      if (_faltas.isNotEmpty) ...[
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
          child: Text('Por completar (${_faltas.length} álbumes) — toca para editar',
              style: const TextStyle(fontWeight: FontWeight.w800, color: Colors.amber)),
        ),
        for (final e in _faltas)
          ExpansionTile(
            leading: const Icon(Icons.cancel, color: Colors.redAccent, size: 20),
            title: Text('${e['artista']} – ${e['titulo']}', maxLines: 1, overflow: TextOverflow.ellipsis),
            subtitle: Text('Falta: ${(e['falta'] as List).join(', ')}', style: const TextStyle(fontSize: 12)),
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Wrap(spacing: 8, runSpacing: 4, children: [
                    for (final f in (e['falta'] as List).cast<String>())
                      ActionChip(
                        avatar: const Icon(Icons.edit_outlined, size: 16),
                        label: Text(f),
                        onPressed: () => _abrirFicha(e, f),
                      ),
                  ]),
                ),
              ),
            ],
          ),
        const Divider(height: 24),
      ],
      for (final e in items.entries)
        ExpansionTile(
          title: Text(e.key, maxLines: 1, overflow: TextOverflow.ellipsis),
          subtitle: Text('${e.value.length} por resolver'),
          children: [
            for (final (kind, url) in e.value)
              ListTile(
                dense: true,
                title: Text(kind),
                subtitle: Text(url, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 11)),
                trailing: IconButton(
                  tooltip: 'Copiar enlace',
                  icon: const Icon(Icons.copy, size: 18),
                  onPressed: () {
                    Clipboard.setData(ClipboardData(text: url));
                    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Enlace copiado')));
                  },
                ),
              ),
          ],
        ),
    ]);
  }

  // ---- Duplicados ----
  List<String> _segs(String path) {
    final folder = _acc!.folder.split('/').where((s) => s.isNotEmpty).toList();
    final p = path.split('/').where((s) => s.isNotEmpty).toList();
    var i = 0;
    while (i < folder.length && i < p.length && folder[i].toLowerCase() == p[i].toLowerCase()) {
      i++;
    }
    return p.sublist(i);
  }

  Widget _duplicados() {
    final d = (_estado['duplicados'] as Map?)?.cast<String, dynamic>() ?? {};
    if (d.isEmpty) return _msg('Nada por revisar.');
    return ListView(children: [
      for (final e in d.entries)
        Card(
          margin: const EdgeInsets.fromLTRB(12, 8, 12, 0),
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(e.key.split('/').last, style: const TextStyle(fontWeight: FontWeight.w800)),
              const SizedBox(height: 6),
              Text('❌ Mal colocado: ${e.key}', style: const TextStyle(fontSize: 12, color: Color(0xFFFF8A80))),
              for (final x in (e.value['destinos'] as List? ?? const []))
                Text('✅ Bien colocado: ${x['dest']}${x['motivo'] != null ? ' (${x['motivo']})' : ''}',
                    style: const TextStyle(fontSize: 12, color: Color(0xFF9CCC65))),
              Align(
                alignment: Alignment.centerRight,
                child: TextButton.icon(
                  icon: const Icon(Icons.delete_outline, size: 18),
                  label: const Text('Borrar el mal colocado'),
                  onPressed: () => _borrar(e.key),
                ),
              ),
            ]),
          ),
        ),
    ]);
  }

  Future<void> _borrar(String path) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Borrar de la nube'),
        content: Text('Se borra la carpeta mal colocada (la copia bien colocada queda):\n\n$path\n\nNo se puede deshacer.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Cancelar')),
          FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('Borrar')),
        ],
      ),
    );
    if (ok != true || _acc == null) return;
    try {
      await KoofrClient(_acc!).remove(_segs(path), isDir: true);
      _estado['duplicados'] = (Map<String, dynamic>.from(_estado['duplicados'] as Map))..remove(path);
      await http.put(
        Uri.parse(_url('estado.json').split('#').first),
        headers: {..._acc!.headers, 'Content-Type': 'application/json'},
        body: utf8.encode(jsonEncode(_estado)),
      );
      if (mounted) setState(() {});
    } catch (_) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('No se pudo borrar')));
    }
  }

  // ---- Historial (calendario) ----
  DateTime _mes = DateTime(DateTime.now().year, DateTime.now().month);
  String? _dia;

  Widget _historial() {
    final byDay = {for (final h in _hist) (h['fecha'] as String): h as Map<String, dynamic>};
    if (byDay.isEmpty) return _msg('Sin historial todavía.');
    final first = DateTime(_mes.year, _mes.month, 1);
    final days = DateTime(_mes.year, _mes.month + 1, 0).day;
    final lead = (first.weekday + 6) % 7;
    const meses = ['enero', 'febrero', 'marzo', 'abril', 'mayo', 'junio', 'julio', 'agosto', 'septiembre', 'octubre', 'noviembre', 'diciembre'];
    String key(int d) => '${_mes.year}-${_mes.month.toString().padLeft(2, '0')}-${d.toString().padLeft(2, '0')}';
    final sel = _dia == null ? null : byDay[_dia];
    return ListView(padding: const EdgeInsets.all(12), children: [
      Row(children: [
        IconButton(icon: const Icon(Icons.chevron_left), onPressed: () => setState(() => _mes = DateTime(_mes.year, _mes.month - 1))),
        Expanded(child: Text('${meses[_mes.month - 1]} ${_mes.year}', textAlign: TextAlign.center, style: const TextStyle(fontWeight: FontWeight.w800))),
        IconButton(icon: const Icon(Icons.chevron_right), onPressed: () => setState(() => _mes = DateTime(_mes.year, _mes.month + 1))),
      ]),
      Row(children: [for (final d in const ['L', 'M', 'M', 'J', 'V', 'S', 'D']) Expanded(child: Center(child: Text(d, style: const TextStyle(color: Colors.white54))))]),
      GridView.count(
        crossAxisCount: 7,
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        children: [
          for (var i = 0; i < lead; i++) const SizedBox(),
          for (var d = 1; d <= days; d++)
            GestureDetector(
              onTap: () => setState(() => _dia = key(d)),
              child: Container(
                margin: const EdgeInsets.all(3),
                decoration: BoxDecoration(
                  color: byDay.containsKey(key(d)) ? const Color(0xFFFF8A3D).withOpacity(.85) : Colors.white10,
                  borderRadius: BorderRadius.circular(8),
                  border: _dia == key(d) ? Border.all(color: Colors.white, width: 2) : null,
                ),
                child: Center(child: Text('$d', style: TextStyle(color: byDay.containsKey(key(d)) ? Colors.black : Colors.white54))),
              ),
            ),
        ],
      ),
      const SizedBox(height: 10),
      if (sel != null) ...[
        Text(_dia!, style: const TextStyle(fontWeight: FontWeight.w800)),
        Text('Álbumes revisados: ${sel['procesados']} de ${sel['total']}'),
        for (final e in ((sel['acciones'] as Map?) ?? const {}).entries) Text('• ${_accion(e.key as String)}: ${e.value}'),
        if (((sel['acciones'] as Map?) ?? const {}).isEmpty) const Text('Sin cambios.'),
      ] else
        const Text('Toca un día marcado para ver lo que hizo.', style: TextStyle(color: Colors.white54)),
    ]);
  }

  static String _accion(String k) => const {
        'portada': 'Portadas nuevas',
        'contraportada': 'Contraportadas nuevas',
        'metadatos': 'Metadatos',
        'acentos': 'Nombres corregidos (copia)',
        'portada_hd': 'Portadas HD',
        'ligeras': 'Versiones livianas',
        'texto': 'Textos de libretos',
        'libreto': 'Libretos armados',
        'letras': 'Álbumes con letras',
        'ficha': 'Fichas album.json',
        'completo': 'Ya completos',
      }[k] ??
      k;

  // ---- Tareas manuales ----
  Widget _tareas() {
    final albums = (_estado['albums'] as Map?)?.cast<String, dynamic>() ?? {};
    final tasks = <(int, String, String)>[];
    albums.forEach((p, v) {
      final name = p.split('/').where((s) => s.isNotEmpty).toList();
      final t = name.length >= 2 ? '${name[name.length - 2]} – ${name.last}' : name.isEmpty ? p : name.last;
      if (v['cover'] == false) tasks.add((3, t, 'Falta la portada'));
      if (v['meta'] == false) tasks.add((2, t, 'Faltan datos (año, género, pistas)'));
      if (v['back'] == false && v['cover'] == true) tasks.add((1, t, 'Falta la contraportada'));
    });
    final pend = (_estado['pendientes'] as Map?)?.length ?? 0;
    if (tasks.isEmpty && pend == 0) return _msg('No hay tareas. ¡Todo en orden!');
    tasks.sort((a, b) => b.$1.compareTo(a.$1));
    return ListView(children: [
      if (pend > 0) ListTile(leading: const Icon(Icons.link), title: Text('$pend álbumes con descargas manuales'), subtitle: const Text('Mira la pestaña Pendientes')),
      for (final (pr, t, what) in tasks.take(200))
        ListTile(
          dense: true,
          leading: Icon(Icons.flag, color: pr == 3 ? const Color(0xFFFF8A80) : pr == 2 ? const Color(0xFFFFCC80) : Colors.white38),
          title: Text(t, maxLines: 1, overflow: TextOverflow.ellipsis),
          subtitle: Text(what),
        ),
    ]);
  }

  // ---- Ejecutar ahora ----
  final _tokenCtl = TextEditingController();
  final _repoCtl = TextEditingController(text: 'pytngdfv1-ai/vinyl-solutions');
  bool _dry = false;
  bool _tokenLoaded = false;
  String? _runMsg;
  static const _store = FlutterSecureStorage();

  Future<void> _loadToken() async {
    if (_tokenLoaded) return;
    _tokenLoaded = true;
    try {
      _tokenCtl.text = await _store.read(key: 'agent_gh_token') ?? '';
      _repoCtl.text = await _store.read(key: 'agent_gh_repo') ?? _repoCtl.text;
      if (mounted) setState(() {});
    } catch (_) {}
  }

  Future<void> _run() async {
    final t = _tokenCtl.text.trim();
    final repo = _repoCtl.text.trim();
    if (t.isEmpty || repo.isEmpty) return;
    setState(() => _runMsg = 'Enviando…');
    try {
      await _store.write(key: 'agent_gh_token', value: t);
      await _store.write(key: 'agent_gh_repo', value: repo);
      final r = await http.post(
        Uri.parse('https://api.github.com/repos/$repo/actions/workflows/agent.yml/dispatches'),
        headers: {'Authorization': 'Bearer $t', 'Accept': 'application/vnd.github+json', 'X-GitHub-Api-Version': '2022-11-28'},
        body: jsonEncode({'ref': 'main', 'inputs': {'dry_run': _dry ? 'true' : 'false', 'max_albums': '40'}}),
      );
      setState(() => _runMsg = r.statusCode == 204
          ? 'Agente en marcha. Mira el resultado en unos minutos (actualiza con ↻).'
          : 'GitHub respondió ${r.statusCode}. Revisa el permiso del token (Actions: lectura y escritura).');
    } catch (_) {
      setState(() => _runMsg = 'Sin conexión.');
    }
  }

  String? _ordenMsg;

  Future<void> _pedir() async {
    if (_acc == null) return;
    setState(() => _ordenMsg = 'Enviando pedido…');
    final folder = _folder ?? _acc!.folder;
    try {
      final dir = _urlIn(folder, 'x').split('#').first;
      final target = Uri.parse(dir.substring(0, dir.length - 1) + 'orden.json');
      final r = await http.put(
        target,
        headers: {..._acc!.headers, 'Content-Type': 'application/json'},
        body: utf8.encode(jsonEncode({'pendiente': true, 'dry': _dry, 'pedido': DateTime.now().toUtc().toIso8601String()})),
      );
      if (r.statusCode == 404 || r.statusCode == 409) {
        // La carpeta _agente puede no existir todavía.
        await http.Request('MKCOL', Uri.parse(dir.substring(0, dir.length - 1).replaceFirst(RegExp(r'/?$'), '/')))
            .send();
      }
      setState(() => _ordenMsg = r.statusCode >= 200 && r.statusCode < 300
          ? 'Pedido guardado. El agente lo toma en su corrida de la madrugada (una por día, 03:17) y verás el resultado al actualizar.'
          : 'No se pudo guardar el pedido (${r.statusCode}).');
    } catch (_) {
      setState(() => _ordenMsg = 'Sin conexión.');
    }
  }

  Widget _ejecutar() {
    _loadToken();
    return ListView(padding: const EdgeInsets.all(16), children: [
      const Text('Pedir ejecución (sin token)', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
      const SizedBox(height: 6),
      const Text(
        'Deja un pedido en tu nube; el agente lo toma en su corrida diaria de la madrugada (03:17 de Uruguay). No necesita nada más.',
        style: TextStyle(color: Colors.white60, fontSize: 12),
      ),
      SwitchListTile(contentPadding: EdgeInsets.zero, title: const Text('Solo probar (no escribe nada)'), value: _dry, onChanged: (v) => setState(() => _dry = v)),
      FilledButton.icon(onPressed: _pedir, icon: const Icon(Icons.schedule_send), label: const Text('Pedir ejecución')),
      if (_ordenMsg != null) Padding(padding: const EdgeInsets.only(top: 12), child: Text(_ordenMsg!)),
      const Divider(height: 36),
      const Text('Ejecutar al instante (con token)', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
      const SizedBox(height: 6),
      const Text(
        'Corre solo todos los días. Para lanzarlo a mano pega un token de GitHub '
        '(Settings → Developer settings → Fine-grained token, con permiso Actions: Read and write sobre el repositorio). '
        'Se guarda cifrado en el equipo.',
        style: TextStyle(color: Colors.white60, fontSize: 12),
      ),
      const SizedBox(height: 12),
      TextField(controller: _repoCtl, decoration: const InputDecoration(labelText: 'Repositorio (usuario/nombre)')),
      const SizedBox(height: 8),
      TextField(controller: _tokenCtl, obscureText: true, decoration: const InputDecoration(labelText: 'Token de GitHub')),
      SwitchListTile(contentPadding: EdgeInsets.zero, title: const Text('Solo probar (no escribe nada)'), value: _dry, onChanged: (v) => setState(() => _dry = v)),
      FilledButton.icon(onPressed: _run, icon: const Icon(Icons.play_arrow), label: const Text('Ejecutar ahora')),
      if (_runMsg != null) Padding(padding: const EdgeInsets.only(top: 12), child: Text(_runMsg!)),
    ]);
  }
}
