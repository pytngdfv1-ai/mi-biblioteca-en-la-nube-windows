import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';

import 'koofr_client.dart';
import 'koofr_settings.dart';
import 'library_order.dart';
import 'library_settings.dart';
import 'vinyl_store.dart';

/// Sincronización de las cuentas de Koofr con la biblioteca.
class LibrarySync {
  /// Mensaje mientras se sincroniza en segundo plano (null = inactivo).
  static final ValueNotifier<String?> busy = ValueNotifier<String?>(null);
  /// Avance real de la sincronización al abrir (0 a 1) y paso actual.
  static final ValueNotifier<double> progress = ValueNotifier<double>(0);
  static final ValueNotifier<String> step = ValueNotifier<String>('');
  /// Discos nuevos detectados en la última sincronización al abrir.
  static final ValueNotifier<int> newCount = ValueNotifier<int>(0);
  static bool _running = false;

  /// Sincroniza una cuenta y devuelve un resumen. Lanza si no puede conectar.
  static Future<String> syncAccount(
    KoofrSettings a,
    VinylStore store, {
    void Function(String)? onProgress,
    bool keepIfEmpty = false,
  }) async {
    final client = KoofrClient(a);
    final reuse = {
      for (final v in store.items)
        if (sourceInAccount(v.source, a.id)) v.id: v,
    };
    final result = await client.scan(onProgress: onProgress, reuse: reuse);
    if (result.albums.isEmpty && keepIfEmpty) return 'Sin cambios';
    // Si detectó carpetas por categoría (Inglés / Español…), lo recuerda.
    await KoofrAccounts.upsert(client.detectedSplit == true ? a.copyWith(split: 'yes') : a);
    await store.replaceAccount(
      a.id,
      result.albums,
      genre: a.genre.trim().isEmpty ? null : a.genre.trim(),
    );
    unawaited(store.reclassify());
    final min = LibrarySettings.minTracks;
    return result.albums.isEmpty
        ? 'Conectado, pero no encontré álbumes completos. ${client.diagnostic}\n${result.summary(min)}'
        : result.summary(min);
  }

  /// Vuelve a leer una cuenta en segundo plano (por ejemplo, tras mover carpetas).
  static Future<void> refresh(KoofrSettings a, VinylStore store) async {
    busy.value = 'Actualizando ${a.name}…';
    try {
      await syncAccount(a, store, keepIfEmpty: true);
    } catch (_) {
      // Se conserva lo guardado.
    } finally {
      busy.value = null;
    }
  }

  /// Sincroniza todas las cuentas guardadas (al abrir la app).
  static Future<void> syncAll(VinylStore store) async {
    if (_running || KoofrAccounts.list.isEmpty) {
      progress.value = 1;
      return;
    }
    _running = true;
    final before = {for (final v in store.items) v.id};
    try {
      final list = List.of(KoofrAccounts.list);
      for (var i = 0; i < list.length; i++) {
        final a = list[i];
        busy.value = 'Sincronizando ${a.name}…';
        step.value = 'Sincronizando ${a.name} (${i + 1}/${list.length})';
        var calls = 0;
        try {
          await syncAccount(a, store, keepIfEmpty: true, onProgress: (_) {
            calls++;
            progress.value = (i + (1 - math.exp(-calls / 30))) / list.length;
          });
        } catch (_) {
          // Sin conexión o contraseña cambiada: se conserva lo guardado.
        }
        progress.value = (i + 1) / list.length;
      }
    } finally {
      if (before.isNotEmpty) {
        newCount.value = store.items.where((v) => v.owned && v.trackUrls.isNotEmpty && !before.contains(v.id)).length;
      }
      _running = false;
      busy.value = null;
      progress.value = 1;
      step.value = 'Listo';
    }
  }
}
