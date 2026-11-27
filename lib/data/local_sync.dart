import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import '../models/vinyl.dart';
import 'cloud_upload.dart';
import 'koofr_client.dart';
import 'koofr_settings.dart';
import 'library_sync.dart';
import 'local_scanner.dart';
import 'upload_queue.dart';
import 'vinyl_store.dart';

/// Ajustes de «Subir lo nuevo»: carpeta del equipo, cuenta y carpeta de destino en la nube.
class LocalSyncConfig {
  LocalSyncConfig({
    this.path,
    this.accountId,
    this.dest,
    this.deleteLocal = false,
    this.auto = false,
    this.daily = false,
    this.wifiOnly = true,
    this.paused = false,
  });

  String? path;
  String? accountId;
  String? dest;
  bool deleteLocal;

  /// Revisar al abrir la app.
  bool auto;

  /// Revisar una vez al día con la app cerrada (WorkManager).
  bool daily;

  /// La tarea diaria solo corre con Wi-Fi.
  bool wifiOnly;

  /// Subida en pausa (no sube nada, ni a mano ni en segundo plano).
  bool paused;

  KoofrSettings? get account {
    if (KoofrAccounts.list.isEmpty) return null;
    for (final a in KoofrAccounts.list) {
      if (a.id == accountId) return a;
    }
    return accountId == null ? KoofrAccounts.list.first : null;
  }

  bool get ready {
    final a = account;
    if (a == null || (path ?? '').isEmpty) return false;
    return a.split != 'yes' || (dest ?? '').isNotEmpty;
  }

  static Future<LocalSyncConfig> load() async {
    final p = await SharedPreferences.getInstance();
    await p.reload();
    return LocalSyncConfig(
      path: p.getString('lsync_path'),
      accountId: p.getString('lsync_acct'),
      dest: p.getString('lsync_dest'),
      deleteLocal: p.getBool('lsync_del') ?? false,
      auto: p.getBool('lsync_auto') ?? false,
      daily: p.getBool('lsync_daily') ?? false,
      wifiOnly: p.getBool('lsync_wifi') ?? true,
      paused: p.getBool('lsync_pause') ?? false,
    );
  }

  Future<void> save() async {
    final p = await SharedPreferences.getInstance();
    Future<void> s(String k, String? v) async {
      if (v == null) {
        await p.remove(k);
      } else {
        await p.setString(k, v);
      }
    }

    await s('lsync_path', path);
    await s('lsync_acct', accountId);
    await s('lsync_dest', dest);
    await p.setBool('lsync_del', deleteLocal);
    await p.setBool('lsync_auto', auto);
    await p.setBool('lsync_daily', daily);
    await p.setBool('lsync_wifi', wifiOnly);
    await p.setBool('lsync_pause', paused);
  }
}

/// Un disco o tema del equipo que aún no se subió.
class SyncItem {
  SyncItem(this.v, this.sig, this.bytes);
  final Vinyl v;
  final String sig;
  final int bytes;
}

class SyncReport {
  SyncReport(this.ok, this.files, this.errors, {this.left = 0, this.note});
  final int ok;
  final int files;
  final List<String> errors;

  /// Cuántos quedan sin subir (pendientes, con error o en espera).
  final int left;
  final String? note;

  String get text {
    if (note != null && ok == 0 && errors.isEmpty) return note!;
    final t = ok == 0 && errors.isEmpty ? 'No hay nada nuevo para subir' : '$ok disco(s) o tema(s) subidos ($files archivos)';
    final extra = errors.isEmpty ? '' : '. Con error (${errors.length}): ${errors.take(3).join(' · ')}';
    final fin = note == null ? '' : '. $note';
    return '$t$extra$fin';
  }
}

/// Revisa la carpeta del equipo y sube a la nube lo que todavía no está.
/// Nunca pisa archivos que ya existen en la nube y verifica el tamaño de cada copia.
/// Sube primero los temas sueltos pequeños y después los discos grandes; si se corta la red,
/// reintenta con espera creciente y deja la cola guardada para seguir después.
class LocalSync {
  static const _doneKey = 'lsync_done';
  static bool running = false;

  static (String, int) _stat(Vinyl v) {
    var size = 0;
    for (final u in v.trackUrls) {
      try {
        size += File(Uri.parse(u).toFilePath()).lengthSync();
      } catch (_) {}
    }
    return ('${v.trackUrls.first}#${v.trackUrls.length}#$size', size);
  }

  /// En Windows no hacen falta permisos para leer carpetas.
  static Future<bool> hasAccess() async => true;

  static Future<bool> isPaused() async {
    final p = await SharedPreferences.getInstance();
    await p.reload();
    return p.getBool('lsync_pause') ?? false;
  }

  /// Lo nuevo de la carpeta (sin subir nada), en el orden en que se subiría.
  static Future<List<SyncItem>> plan(LocalSyncConfig c, {void Function(String)? onProgress}) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.reload();
    final done = (prefs.getStringList(_doneKey) ?? const <String>[]).toSet();
    final res = await LocalScanner().scan(c.path!, onProgress: onProgress);
    final items = <SyncItem>[];
    for (final v in res.albums) {
      if (v.trackUrls.isEmpty) continue;
      final s = _stat(v);
      if (!done.contains(s.$1)) items.add(SyncItem(v, s.$1, s.$2));
    }
    items.sort((a, b) {
      if (a.v.single != b.v.single) return a.v.single ? -1 : 1;
      return a.bytes.compareTo(b.bytes);
    });
    return items;
  }

  static bool _retryable(Object e) =>
      e is SocketException ||
      e is TimeoutException ||
      e is HandshakeException ||
      e is http.ClientException ||
      (e is KoofrException && RegExp(r'Error de Koofr \((5\d\d|429|408)\)').hasMatch(e.message));

  static Future<void> _beat(SharedPreferences p, [int? v]) => p.setInt('lsync_lock', v ?? DateTime.now().millisecondsSinceEpoch);

  /// Sube todo lo nuevo. Con [store] (app abierta) actualiza la biblioteca; sin él (tarea en segundo plano)
  /// la biblioteca se ajusta al abrir la app ([reconcile]). [limit] corta antes de empezar otro disco.
  static Future<SyncReport> runAll(
    LocalSyncConfig c, {
    VinylStore? store,
    void Function(String msg, double progress)? onProgress,
    Duration? limit,
    bool retryAll = false,
  }) async {
    if (running) return SyncReport(0, 0, [], note: 'Ya hay una subida en curso');
    final prefs = await SharedPreferences.getInstance();
    await prefs.reload();
    final t = DateTime.now().millisecondsSinceEpoch;
    if (t - (prefs.getInt('lsync_lock') ?? 0) < 120000) {
      return SyncReport(0, 0, [], note: 'Ya hay una subida en curso (otra tarea)');
    }
    running = true;
    try {
      if (c.paused || await isPaused()) return SyncReport(0, 0, [], note: 'Subida en pausa');
      final acct = c.account;
      if (!c.ready || acct == null) return SyncReport(0, 0, [], note: 'Falta elegir la carpeta, la nube o su carpeta de destino');
      await _beat(prefs);
      final items = await plan(c);
      final queue = await UploadQueue.load();
      for (final q in queue) {
        if (q.state == 'uploading') q.state = 'pending';
      }
      final bySig = {for (final q in queue) q.sig: q};
      for (final it in items) {
        final q = bySig[it.sig];
        if (q == null) {
          final n = QueueItem(sig: it.sig, id: it.v.id, title: it.v.title, artist: it.v.artist, single: it.v.single, bytes: it.bytes);
          queue.add(n);
          bySig[it.sig] = n;
        } else if (q.state == 'done') {
          q.state = 'pending';
        }
      }
      final sigs = items.map((e) => e.sig).toSet();
      queue.removeWhere((q) => q.state != 'done' && !sigs.contains(q.sig));
      await UploadQueue.save(queue);

      final done = (prefs.getStringList(_doneKey) ?? const <String>[]).toSet();
      final t0 = DateTime.now();
      var ok = 0, files = 0;
      final errors = <String>[];
      final removed = <String>[];
      String? note;
      var lastBeat = DateTime.now();
      for (var i = 0; i < items.length; i++) {
        final it = items[i];
        final q = bySig[it.sig]!;
        final nowMs = DateTime.now().millisecondsSinceEpoch;
        if (q.state == 'error' && q.next > nowMs && !retryAll) continue;
        if (await isPaused()) {
          note = 'Subida en pausa';
          break;
        }
        if (limit != null && DateTime.now().difference(t0) > limit) {
          note = 'Quedan discos para la próxima vez';
          break;
        }
        q.state = 'uploading';
        q.at = nowMs;
        await UploadQueue.save(queue);
        final v = it.v;
        var success = false;
        String? err;
        for (var attempt = 0; attempt < 4; attempt++) {
          try {
            final r = await CloudUpload.run(v, acct, dest: c.dest, cleanNames: true, flatSingles: true, onProgress: (m, p) {
              onProgress?.call('(${i + 1}/${items.length}) $m', (i + p) / items.length);
              if (DateTime.now().difference(lastBeat).inSeconds > 20) {
                lastBeat = DateTime.now();
                _beat(prefs);
              }
            });
            files += r.uploaded;
            if (store != null) {
              final cv = v.coverUrl;
              await store.addCarry({
                r.firstKey: {
                  'cover': cv != null && !cv.contains('koofr.net') ? cv : null,
                  'owned': v.owned,
                  'cassette': v.cassette,
                  'coverManual': v.coverManual,
                  'lang': v.lang,
                  'langManual': v.langManual,
                },
              });
            }
            success = true;
            err = null;
            break;
          } catch (e) {
            err = e is KoofrException ? e.message : '$e';
            if (!_retryable(e) || attempt == 3) break;
            final wait = const [5, 20, 60][attempt];
            onProgress?.call('Sin conexión; reintento en $wait s…', i / items.length);
            await _beat(prefs);
            await Future<void>.delayed(Duration(seconds: wait));
            if (await isPaused()) break;
          }
        }
        if (success) {
          q.state = 'done';
          q.error = null;
          q.at = DateTime.now().millisecondsSinceEpoch;
          done.add(it.sig);
          removed.add(v.id);
          ok++;
          if (c.deleteLocal) {
            try {
              await CloudUpload.deleteLocal(v);
            } catch (_) {}
          }
        } else {
          q.tries++;
          q.state = 'error';
          q.error = err ?? 'Pausada';
          // Espera creciente entre intentos: 10 min, 40 min, 2 h 40 min, 10 h 40 min, 24 h.
          final min = math.min(1440, 10 * math.pow(4, q.tries - 1).toInt());
          q.next = DateTime.now().add(Duration(minutes: min)).millisecondsSinceEpoch;
          errors.add('${v.title}: ${q.error}');
        }
        await UploadQueue.save(queue);
        await prefs.setStringList(_doneKey, done.toList());
        await _beat(prefs);
      }
      await prefs.setStringList(_doneKey, done.toList());
      if (store != null && removed.isNotEmpty) {
        await store.removeMany(removed);
        LibrarySync.refresh(acct, store);
      }
      final left = items.where((e) => bySig[e.sig]!.state != 'done').length;
      return SyncReport(ok, files, errors, left: left, note: note);
    } finally {
      running = false;
      try {
        await prefs.setInt('lsync_lock', 0);
      } catch (_) {}
    }
  }

  /// Quita de la biblioteca los discos del equipo que la tarea en segundo plano ya subió a la nube.
  static Future<void> reconcile(VinylStore store) async {
    final q = await UploadQueue.load();
    final ids = {
      for (final e in q)
        if (e.state == 'done' && e.id.isNotEmpty) e.id,
    };
    final stale = [
      for (final v in store.items)
        if (ids.contains(v.id) && (v.source ?? '').startsWith('local')) v.id,
    ];
    if (stale.isNotEmpty) await store.removeMany(stale);
  }

  /// Al abrir la app (si está activado): sube lo nuevo en silencio. Devuelve un aviso o null.
  static Future<String?> auto(VinylStore store) async {
    try {
      await reconcile(store);
      final c = await LocalSyncConfig.load();
      if (!c.auto || c.paused || !c.ready || !await hasAccess() || !Directory(c.path!).existsSync()) return null;
      LibrarySync.busy.value = 'Subiendo a la nube…';
      final r = await runAll(c, store: store);
      if (r.ok == 0 && r.errors.isEmpty) return null;
      return r.text;
    } catch (e) {
      return 'No se pudo subir lo nuevo: $e';
    } finally {
      LibrarySync.busy.value = null;
    }
  }
}
