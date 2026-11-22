import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Interruptor de Ajustes: objetos 3D generados por el agente (apagado por defecto).
class Objetos3dFlag {
  static const _k = 'objetos3d_agente_on';
  static final ValueNotifier<bool> enabled = ValueNotifier<bool>(false);

  static Future<void> load() async {
    try {
      enabled.value = (await SharedPreferences.getInstance()).getBool(_k) ?? false;
    } catch (_) {}
  }

  static Future<void> set(bool on) async {
    enabled.value = on;
    try {
      await (await SharedPreferences.getInstance()).setBool(_k, on);
    } catch (_) {}
  }
}
