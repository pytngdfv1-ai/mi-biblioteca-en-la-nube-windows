import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Cómo se ve el menú principal y el interior de cada biblioteca.
class UiSettings {
  /// Menú principal en anillo 360° (si no, el clásico de cajones).
  static final ValueNotifier<bool> homeRing = ValueNotifier<bool>(true);

  /// Interior de cada biblioteca en anillos 360° (si no, la caja de discos clásica).
  static final ValueNotifier<bool> libRing = ValueNotifier<bool>(true);

  /// Animaciones al abrir un disco o cassette.
  static final ValueNotifier<bool> animations = ValueNotifier<bool>(true);

  static Future<void> setAnimations(bool v) async {
    animations.value = v;
    try {
      final p = await SharedPreferences.getInstance();
      await p.setBool('ui_animations', v);
    } catch (_) {}
  }

  /// Modo ahorro: apaga shader, sensores, desgaste, sombras dinámicas y animaciones 3D.
  static final ValueNotifier<bool> powerSave = ValueNotifier<bool>(false);

  /// Efectos visuales activos (lo contrario del modo ahorro).
  static bool get fx => !powerSave.value;

  static Future<void> setPowerSave(bool v) async {
    powerSave.value = v;
    try {
      final p = await SharedPreferences.getInstance();
      await p.setBool('ui_power_save', v);
    } catch (_) {}
  }

  /// Color de la base del tocadiscos (0 madera, 1 negro, 2 plata, 3 rojo, 4 azul).
  static final ValueNotifier<int> plinth = ValueNotifier<int>(0);
  static const plinthNames = ['Madera', 'Negro', 'Plata', 'Rojo', 'Azul', 'Según la portada'];
  static const plinthCover = 5;
  static const _plinthColors = <List<Color>>[
    [Color(0xFF3A2A1E), Color(0xFF241A13), Color(0xFF2E2118)],
    [Color(0xFF2B2B2F), Color(0xFF111113), Color(0xFF1D1D20)],
    [Color(0xFFB9BCC2), Color(0xFF8E9197), Color(0xFFA6A9AF)],
    [Color(0xFF8E2A22), Color(0xFF55180F), Color(0xFF722119)],
    [Color(0xFF254A7A), Color(0xFF122740), Color(0xFF1C3B63)],
  ];
  static List<Color> get plinthColors => _plinthColors[plinth.value >= 0 && plinth.value < _plinthColors.length ? plinth.value : 0];

  /// Degradado de base a partir del color de una portada.
  static List<Color> tintFrom(Color c) {
    final h = HSLColor.fromColor(c);
    Color l(double v) => h.withSaturation((h.saturation * .8).clamp(.2, .7)).withLightness(v).toColor();
    return [l(.26), l(.12), l(.19)];
  }

  static Future<void> setPlinth(int v) async {
    plinth.value = v;
    try {
      final p = await SharedPreferences.getInstance();
      await p.setInt('ui_plinth', v);
    } catch (_) {}
  }

  static Future<void> load() async {
    try {
      final p = await SharedPreferences.getInstance();
      homeRing.value = p.getBool('ui_home_ring') ?? true;
      libRing.value = p.getBool('ui_lib_ring') ?? true;
      animations.value = p.getBool('ui_animations') ?? true;
      powerSave.value = p.getBool('ui_power_save') ?? false;
      plinth.value = p.getInt('ui_plinth') ?? 0;
    } catch (_) {}
  }

  static Future<void> setHome(bool v) async {
    homeRing.value = v;
    try {
      final p = await SharedPreferences.getInstance();
      await p.setBool('ui_home_ring', v);
    } catch (_) {}
  }

  static Future<void> setLib(bool v) async {
    libRing.value = v;
    try {
      final p = await SharedPreferences.getInstance();
      await p.setBool('ui_lib_ring', v);
    } catch (_) {}
  }
}
