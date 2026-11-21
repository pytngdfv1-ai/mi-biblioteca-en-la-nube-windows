import 'dart:convert';
import 'dart:typed_data';

import 'package:shared_preferences/shared_preferences.dart';

import '../models/vinyl.dart';
import '../widgets/collage.dart';
import 'cover_cache.dart';
import 'koofr_client.dart';
import 'koofr_settings.dart';
import 'studio_save.dart';
import 'vinyl_store.dart';

/// Un tema elegido de la biblioteca para un disco personalizado.
class PickedTrack {
  const PickedTrack(this.title, this.url, this.cover, this.artist);
  final String title;
  final String url;
  final String? cover;
  final String artist;
}

/// Aspecto del vinilo / cassette y de la etiqueta.
class CustomLook {
  CustomLook({
    this.style = 0,
    this.color = 0xFFC62828,
    this.labelText = '',
    this.volume = 0,
    this.stamp = false,
    this.tapeColor = 0,
  });

  /// Textura del vinilo (ver kDiscStyles) y su color.
  int style;
  int color;

  /// Texto curvo superior de la etiqueta (vacío = el artista).
  String labelText;

  /// Numeración "Vol. N" (0 = sin número).
  int volume;

  /// Sello propio (icono de la app) a los lados de la etiqueta.
  bool stamp;

  /// Color del cassette (0 = según la portada).
  int tapeColor;

  CustomLook copy() =>
      CustomLook(style: style, color: color, labelText: labelText, volume: volume, stamp: stamp, tapeColor: tapeColor);

  Map<String, dynamic> toJson() =>
      {'style': style, 'color': color, 'label': labelText, 'vol': volume, 'stamp': stamp, 'tape': tapeColor};

  factory CustomLook.fromJson(Map<String, dynamic> j) => CustomLook(
        style: (j['style'] as num?)?.toInt() ?? 0,
        color: (j['color'] as num?)?.toInt() ?? 0xFFC62828,
        labelText: j['label'] as String? ?? '',
        volume: (j['vol'] as num?)?.toInt() ?? 0,
        stamp: j['stamp'] == true,
        tapeColor: (j['tape'] as num?)?.toInt() ?? 0,
      );
}

/// Diseño guardado de un disco personalizado.
class CustomMeta {
  CustomMeta({this.layers = const [], CustomLook? look}) : look = look ?? CustomLook();
  List<CollageLayer> layers;
  CustomLook look;

  Map<String, dynamic> toJson() => {'layers': [for (final l in layers) l.toJson()], 'look': look.toJson()};

  factory CustomMeta.fromJson(Map<String, dynamic> j) => CustomMeta(
        layers: [
          for (final l in (j['layers'] as List? ?? const [])) CollageLayer.fromJson(Map<String, dynamic>.from(l as Map)),
        ],
        look: j['look'] is Map ? CustomLook.fromJson(Map<String, dynamic>.from(j['look'] as Map)) : null,
      );
}

/// Discos y cassettes armados por el usuario: temas de cualquier disco + collage como portada.
class CustomDiscs {
  static const _key = 'custom_meta_v1';
  static Map<String, CustomMeta> _meta = {};

  static bool isCustom(Vinyl v) => v.id.startsWith('cust_');

  static Future<void> load() async {
    try {
      final p = await SharedPreferences.getInstance();
      final raw = p.getString(_key);
      if (raw != null) {
        _meta = {
          for (final e in (jsonDecode(raw) as Map<String, dynamic>).entries)
            e.key: CustomMeta.fromJson(Map<String, dynamic>.from(e.value as Map)),
        };
      }
    } catch (_) {}
  }

  static CustomMeta? metaOf(String id) => _meta[id];

  /// Aspecto de un disco personalizado (null si no lo es).
  static CustomLook? lookOf(String id) => id.startsWith('cust_') ? _meta[id]?.look : null;

  static Future<void> _persist() async {
    final p = await SharedPreferences.getInstance();
    await p.setString(_key, jsonEncode({for (final e in _meta.entries) e.key: e.value.toJson()}));
  }

  /// Crea o actualiza el disco. Devuelve un mensaje sobre la copia en la nube (o null).
  static Future<String?> save(
    VinylStore store, {
    String? id,
    required String title,
    required String artist,
    required bool cassette,
    required List<PickedTrack> tracks,
    required List<CollageLayer> layers,
    CustomLook? look,
  }) async {
    final vid = id ?? 'cust_${DateTime.now().microsecondsSinceEpoch}';
    String? cover;
    String? note;
    if (layers.isNotEmpty) {
      final png = await renderCollage(layers);
      cover = await CoverCache.save('$vid-${DateTime.now().millisecondsSinceEpoch}', png, 'image/png');
      note = await _toCloud(title, png, tracks, layers, cassette, look);
    }
    Vinyl? old;
    for (final v in store.items) {
      if (v.id == vid) old = v;
    }
    final v = Vinyl(
      id: vid,
      title: title,
      artist: artist,
      year: old?.year ?? DateTime.now().year,
      hue: (title.hashCode.abs() % 360).toDouble(),
      tracks: [for (final t in tracks) t.title],
      trackUrls: [for (final t in tracks) t.url],
      coverUrl: cover ?? old?.coverUrl,
      owned: true,
      genre: 'Personalizados',
      cassette: cassette,
      coverManual: true,
      coverLocked: true,
    );
    await store.putCustom(v);
    _meta[vid] = CustomMeta(layers: [for (final l in layers) l.copy()], look: look?.copy());
    await _persist();
    return note;
  }

  static Future<void> delete(VinylStore store, String id) async {
    _meta.remove(id);
    await _persist();
    await store.remove(id);
  }

  /// Guarda la imagen y el diseño en la nube: _Personalizados/<nombre>/ (primera cuenta).
  static Future<String?> _toCloud(
      String title, Uint8List png, List<PickedTrack> tracks, List<CollageLayer> layers, bool cassette, CustomLook? look) async {
    if (KoofrAccounts.list.isEmpty) return null;
    try {
      final c = KoofrClient(KoofrAccounts.list.first);
      final dir = ['_Personalizados', StudioSave.safe(title)];
      await c.ensureDir(dir);
      final ok = await c.putBytes(dir, 'Portada.png', png, overwrite: true, type: 'image/png');
      final info = jsonEncode({
        'titulo': title,
        'tipo': cassette ? 'cassette' : 'vinilo',
        'temas': [for (final t in tracks) '${t.artist} – ${t.title}'],
        'collage': [for (final l in layers) l.toJson()],
        if (look != null) 'aspecto': look.toJson(),
      });
      await c.putBytes(dir, 'disco.json', Uint8List.fromList(utf8.encode(info)),
          overwrite: true, type: 'application/json');
      return ok ? 'Imagen guardada en la nube: _Personalizados/${dir.last}' : 'No se pudo guardar en la nube';
    } catch (_) {
      return 'No se pudo guardar en la nube';
    }
  }
}
