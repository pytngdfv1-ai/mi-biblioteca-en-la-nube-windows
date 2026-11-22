import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Duración de cada tema (se aprende al reproducir) para dibujar los surcos del disco
/// con un ancho proporcional a lo que dura cada tema.
class TrackDurations {
  static const _key = 'track_dur_v1';
  static Map<String, List<int>> _d = {};
  static bool _loaded = false;
  static final ValueNotifier<int> version = ValueNotifier<int>(0);

  static Future<void> load() async {
    if (_loaded) return;
    _loaded = true;
    try {
      final raw = (await SharedPreferences.getInstance()).getString(_key);
      if (raw != null) {
        _d = {for (final e in (jsonDecode(raw) as Map).entries) e.key as String: [for (final x in e.value as List) (x as num).toInt()]};
        version.value++;
      }
    } catch (_) {}
  }

  static Future<void> learn(String id, int index, int ms, int count) async {
    if (ms < 1000 || index < 0 || index >= count) return;
    final l = _d[id] ?? List<int>.filled(count, 0);
    if (l.length != count) return _reset(id, index, ms, count);
    if ((l[index] - ms).abs() < 500) return;
    l[index] = ms;
    _d[id] = l;
    version.value++;
    _save();
  }

  static void _reset(String id, int index, int ms, int count) {
    final l = List<int>.filled(count, 0);
    l[index] = ms;
    _d[id] = l;
    version.value++;
    _save();
  }

  static Future<void> _save() async {
    try {
      (await SharedPreferences.getInstance()).setString(_key, jsonEncode(_d));
    } catch (_) {}
  }

  /// Límites acumulados (0..1, desde el borde exterior) de cada tema: n+1 valores.
  static List<double> bounds(String id, int n) {
    n = n.clamp(1, 31);
    final l = _d[id];
    final known = l == null || l.length != n ? <int>[] : l.where((x) => x > 0).toList();
    final avg = known.isEmpty ? 1.0 : known.reduce((a, b) => a + b) / known.length;
    final w = [
      for (var i = 0; i < n; i++)
        (l != null && l.length == n && l[i] > 0 ? l[i].toDouble() : avg).clamp(avg * .35, avg * 4.0).toDouble()
    ];
    final sum = w.fold<double>(0, (a, b) => a + b);
    final out = <double>[0];
    for (final x in w) {
      out.add(out.last + x / sum);
    }
    return out;
  }
}
