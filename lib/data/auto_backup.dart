import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'backup.dart';
import 'koofr_client.dart';
import 'koofr_settings.dart';
import 'vinyl_store.dart';

/// Copia de seguridad automática en la nube: tras cada cambio, espera unos segundos
/// y sube la copia cifrada a la carpeta "_respaldo" de la primera cuenta.
class AutoBackup {
  static const folder = '_respaldo';
  static const file = 'MiBiblioteca.vinylbackup';
  static const _keyName = 'auto_backup_key';
  static const _secure = FlutterSecureStorage();

  static final ValueNotifier<bool> enabled = ValueNotifier<bool>(false);
  static final ValueNotifier<String> status = ValueNotifier<String>('');
  static Timer? _timer;
  static bool _running = false, _again = false;
  static VinylStore? _store;

  static Future<void> init(VinylStore store) async {
    _store = store;
    try {
      final p = await SharedPreferences.getInstance();
      enabled.value = (p.getBool('auto_backup') ?? false) && (await _secure.read(key: _keyName)) != null;
    } catch (_) {}
    store.addListener(_changed);
  }

  static void _changed() {
    if (!enabled.value) return;
    _timer?.cancel();
    _timer = Timer(const Duration(seconds: 25), run);
  }

  /// Activa con la [password] elegida (se guarda cifrada en el equipo) y sube una copia.
  static Future<void> enable(String password) async {
    await _secure.write(key: _keyName, value: password);
    try {
      final p = await SharedPreferences.getInstance();
      await p.setBool('auto_backup', true);
    } catch (_) {}
    enabled.value = true;
    await run();
  }

  static Future<void> disable() async {
    _timer?.cancel();
    enabled.value = false;
    try {
      final p = await SharedPreferences.getInstance();
      await p.setBool('auto_backup', false);
    } catch (_) {}
    await _secure.delete(key: _keyName);
    status.value = '';
  }

  static Future<void> run() async {
    final store = _store;
    if (store == null || !enabled.value) return;
    if (_running) {
      _again = true;
      return;
    }
    _running = true;
    try {
      final pw = await _secure.read(key: _keyName);
      if (pw == null) return;
      if (KoofrAccounts.list.isEmpty) {
        status.value = 'Sin cuenta de nube para guardar la copia.';
        return;
      }
      status.value = 'Guardando copia en la nube…';
      final bytes = await BackupService.build(pw, store);
      final cl = KoofrClient(KoofrAccounts.list.first);
      await cl.ensureDir([folder]);
      final ok = await cl.putBytes([folder], file, bytes, type: 'application/octet-stream');
      final t = DateTime.now();
      status.value = ok
          ? 'Última copia en la nube: ${t.day}/${t.month} ${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}'
          : 'No se pudo guardar la copia en la nube.';
    } catch (_) {
      status.value = 'No se pudo guardar la copia en la nube.';
    } finally {
      _running = false;
      if (_again) {
        _again = false;
        _changed();
      }
    }
  }
}
