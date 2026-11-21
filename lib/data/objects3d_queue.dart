import 'package:flutter/foundation.dart';

import '../models/vinyl.dart';
import 'objects3d.dart';

/// Cola de generación de objetos 3D: sigue trabajando aunque salgas de la pantalla.
/// Se puede sumar más trabajo mientras corre.
class Objects3DQueue {
  static final ValueNotifier<bool> busy = ValueNotifier<bool>(false);
  static final ValueNotifier<int> done = ValueNotifier<int>(0);
  static final ValueNotifier<int> total = ValueNotifier<int>(0);
  static final ValueNotifier<String> message = ValueNotifier<String>('');

  static final List<Vinyl> _todo = [];
  static final List<Vinyl> _drop = [];
  static bool _looping = false;

  static void add({List<Vinyl> todo = const [], List<Vinyl> drop = const []}) {
    if (!_looping) {
      done.value = 0;
      total.value = 0;
    }
    for (final v in todo) {
      if (!_todo.any((x) => x.id == v.id)) {
        _todo.add(v);
        total.value++;
      }
    }
    for (final v in drop) {
      if (!_drop.any((x) => x.id == v.id)) {
        _drop.add(v);
        total.value++;
      }
    }
    if (!_looping && (_todo.isNotEmpty || _drop.isNotEmpty)) _loop();
  }

  static void cancel() => Objects3D.cancel = true;

  static Future<void> _loop() async {
    _looping = true;
    Objects3D.cancel = false;
    busy.value = true;
    while (!Objects3D.cancel && (_drop.isNotEmpty || _todo.isNotEmpty)) {
      if (_drop.isNotEmpty) {
        final v = _drop.removeAt(0);
        message.value = v.title;
        try {
          await Objects3D.remove(v);
        } catch (_) {}
      } else {
        final v = _todo.removeAt(0);
        message.value = v.title;
        try {
          await Objects3D.generate(v);
        } catch (_) {}
      }
      done.value++;
      // Cede el hilo para que la app siga fluida.
      await Future<void>.delayed(const Duration(milliseconds: 60));
    }
    if (Objects3D.cancel) {
      _todo.clear();
      _drop.clear();
    }
    _looping = false;
    busy.value = false;
    message.value = '';
    done.value = 0;
    total.value = 0;
  }
}
