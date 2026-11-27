import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

/// Un disco o tema de la cola de subida (pendiente, subiendo, subido o con error).
class QueueItem {
  QueueItem({
    required this.sig,
    required this.id,
    required this.title,
    required this.artist,
    required this.single,
    required this.bytes,
    this.state = 'pending',
    this.error,
    this.tries = 0,
    this.next = 0,
    int? at,
  }) : at = at ?? DateTime.now().millisecondsSinceEpoch;

  final String sig;
  final String id;
  final String title;
  final String artist;
  final bool single;
  final int bytes;

  /// 'pending' | 'uploading' | 'done' | 'error'
  String state;
  String? error;
  int tries;

  /// No reintentar antes de esta hora (ms desde 1970).
  int next;
  int at;

  Map<String, dynamic> toJson() => {
        'sig': sig,
        'id': id,
        'title': title,
        'artist': artist,
        'single': single,
        'bytes': bytes,
        'state': state,
        'error': error,
        'tries': tries,
        'next': next,
        'at': at,
      };

  factory QueueItem.fromJson(Map<String, dynamic> j) => QueueItem(
        sig: j['sig'] as String,
        id: j['id'] as String? ?? '',
        title: j['title'] as String? ?? '',
        artist: j['artist'] as String? ?? '',
        single: j['single'] as bool? ?? false,
        bytes: (j['bytes'] as num?)?.toInt() ?? 0,
        state: j['state'] as String? ?? 'pending',
        error: j['error'] as String?,
        tries: (j['tries'] as num?)?.toInt() ?? 0,
        next: (j['next'] as num?)?.toInt() ?? 0,
        at: (j['at'] as num?)?.toInt(),
      );
}

/// Cola de subida guardada en el equipo (la comparten la app y la tarea en segundo plano).
class UploadQueue {
  static const _key = 'lsync_queue_v1';

  static Future<List<QueueItem>> load() async {
    final p = await SharedPreferences.getInstance();
    await p.reload();
    final raw = p.getString(_key);
    if (raw == null) return [];
    try {
      return [
        for (final j in jsonDecode(raw) as List) QueueItem.fromJson((j as Map).cast<String, dynamic>()),
      ];
    } catch (_) {
      return [];
    }
  }

  static Future<void> save(List<QueueItem> items) async {
    // Del historial de subidos se conservan los últimos 150.
    final done = items.where((e) => e.state == 'done').toList()..sort((a, b) => b.at.compareTo(a.at));
    final keep = done.take(150).toSet();
    final out = [
      for (final e in items)
        if (e.state != 'done' || keep.contains(e)) e,
    ];
    final p = await SharedPreferences.getInstance();
    await p.setString(_key, jsonEncode([for (final e in out) e.toJson()]));
  }

  /// Vuelve a poner en pendiente los errores (todos, o solo [sig]) sin esperar el turno.
  static Future<void> retryErrors({String? sig}) async {
    final q = await load();
    for (final e in q) {
      if (e.state == 'error' && (sig == null || e.sig == sig)) {
        e.state = 'pending';
        e.next = 0;
      }
    }
    await save(q);
  }

  static Future<void> clearDone() async {
    final q = await load();
    q.removeWhere((e) => e.state == 'done');
    await save(q);
  }
}
