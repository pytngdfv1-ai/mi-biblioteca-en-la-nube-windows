import 'package:flutter/foundation.dart';
import 'package:just_audio/just_audio.dart';

/// En Windows no hay nivel real del audio: [real] queda en false y las pantallas
/// usan su animación simulada. Misma interfaz que en Android.
class Levels {
  static final ValueNotifier<double> level = ValueNotifier<double>(0);
  static double peak = 0;
  static bool real = false;
  static bool get live => false;

  static Future<void> init(AudioPlayer p) async {}
}
