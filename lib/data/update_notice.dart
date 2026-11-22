import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

import '../screens/novedades_screen.dart';
import 'agent_index.dart';

/// Avisa dentro de la app si hay una versión más nueva (el agente deja _agente/version.json).
class UpdateNotice {
  static const current = String.fromEnvironment('APP_VERSION', defaultValue: '');
  static bool _checked = false;
  static const defaultUrl = 'https://github.com/pytngdfv1-ai/vinyl-solutions-windows/releases/latest';

  /// Abre la página de descarga en el navegador (si no puede, copia el enlace).
  static Future<void> open(BuildContext context, [String? url]) async {
    final u = (url == null || url.isEmpty) ? defaultUrl : url;
    var ok = false;
    try {
      ok = await launchUrl(Uri.parse(u), mode: LaunchMode.externalApplication);
    } catch (_) {}
    if (!ok) {
      await Clipboard.setData(ClipboardData(text: u));
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Enlace copiado: pégalo en el navegador')));
      }
    }
  }

  static List<int> _parts(String v) => [for (final p in v.split('.')) int.tryParse(p) ?? 0];

  static bool isNewer(String a, String b) {
    final x = _parts(a), y = _parts(b);
    for (var i = 0; i < 3; i++) {
      final p = i < x.length ? x[i] : 0, q = i < y.length ? y[i] : 0;
      if (p != q) return p > q;
    }
    return false;
  }

  static Future<void> check(BuildContext context) async {
    // En Windows las actualizaciones las gestiona el actualizador propio (WinSparkle);
    // version.json del agente es de la app de Android.
    if (true || _checked || current.isEmpty) return;
    _checked = true;
    try {
      final j = await AgentFiles.readJson('version.json');
      final ver = (j?['version'] ?? '').toString();
      if (j == null || ver.isEmpty || !isNewer(ver, current)) return;
      final p = await SharedPreferences.getInstance();
      if (p.getString('update_dismissed') == ver) return;
      if (!context.mounted) return;
      final url = (j['url'] ?? '').toString();
      final titulo = (j['titulo'] ?? '').toString();
      final extra = titulo.isEmpty ? '' : ' · $titulo';
      final m = ScaffoldMessenger.of(context);
      m.showMaterialBanner(MaterialBanner(
        content: Text('Nueva versión $ver$extra. Tienes la $current.'),
        leading: const Icon(Icons.system_update),
        actions: [
          TextButton(
            onPressed: () {
              m.hideCurrentMaterialBanner();
              p.setString('update_dismissed', ver);
            },
            child: const Text('Luego'),
          ),
          TextButton(
            onPressed: () {
              m.hideCurrentMaterialBanner();
              open(context, url);
            },
            child: const Text('Descargar'),
          ),
          TextButton(
            onPressed: () {
              m.hideCurrentMaterialBanner();
              Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const NovedadesScreen()));
            },
            child: const Text('Novedades'),
          ),
        ],
      ));
    } catch (_) {}
  }
}
