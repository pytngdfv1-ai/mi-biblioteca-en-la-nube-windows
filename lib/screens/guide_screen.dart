import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../widgets/spin_model.dart';

/// Guía de la app: una página por función, con su objeto 3D (se puede girar).
class GuideScreen extends StatefulWidget {
  const GuideScreen({super.key});

  static const _key = 'guide_seen_v1';

  /// Abre la guía automáticamente la primera vez.
  static Future<void> showFirstTime(BuildContext context) async {
    try {
      final p = await SharedPreferences.getInstance();
      if (p.getBool(_key) ?? false) return;
      await p.setBool(_key, true);
      if (context.mounted) {
        await Navigator.of(context).push(MaterialPageRoute(builder: (_) => const GuideScreen()));
      }
    } catch (_) {}
  }

  @override
  State<GuideScreen> createState() => _GuideScreenState();
}

class _Page {
  const _Page(this.title, this.text, {this.model, this.icon});
  final String title;
  final String text;
  final String? model;
  final IconData? icon;
}

const _pages = <_Page>[
  _Page('Bienvenido', 'Tu biblioteca de música en la nube, con discos, cassettes y reproductores de verdad. '
      'Desliza para recorrer la guía.', icon: Icons.library_music),
  _Page('Menú principal', 'Gira el anillo con el dedo y toca un icono para entrar. Cada objeto 3D se puede girar.',
      icon: Icons.donut_large),
  _Page('Reproductores', 'Todos los reproductores en un solo icono. Tócalo y elige: tocadiscos, deck, DJ, cinta o iPod.',
      model: 'players'),
  _Page('Bibliotecas', 'Entra y elige Discos o Cassettes para ver tus bibliotecas (álbumes, inglés, español y sueltos) en esa versión.',
      model: 'crate'),
  _Page('Tocadiscos', 'Álbumes y sueltos en disco. Toca la carátula para darla vuelta y ver los temas; '
      'toca el plato para play/pausa. "Contraportada" muestra el reverso.', model: 'technics'),
  _Page('Deck de cassettes', 'Lo mismo, pero en cassette: caja, pestaña y cinta que gira.', model: 'cassette_player'),
  _Page('Bandejas DJ', 'Mezcla tus playlists con dos bandejas y crossfader.', model: 'dj'),
  _Page('Cinta abierta', 'Reproduce todo con carretes que giran según la cinta restante y vúmetros con el nivel real del audio.',
      model: 'melodia'),
  _Page('Buscador de portadas', 'Cover Studio: busca, recorta y guarda portadas y contraportadas; '
      'crea discos personalizados con collage de recortes.', model: 'covers_search'),
  _Page('Buscador de temas y álbumes', 'Busca por tema, álbum o artista en toda tu biblioteca.', model: 'lupa'),
  _Page('Ajustes', 'Cuenta de la nube, copias de seguridad, bibliotecas y opciones. El menú se desliza para ver todo.',
      model: 'gear'),
  _Page('Ecualizador', 'Graves, medios y agudos reales para todo lo que suena, con aguja que sigue el nivel del audio. '
      'Pide permiso de micrófono solo para medir el nivel interno del reproductor (no graba).', icon: Icons.graphic_eq),
  _Page('iPod', 'Rueda: gira para el volumen, toca los bordes para anterior/siguiente y el centro para play/pausa.',
      model: 'ipod'),
  _Page('Línea de tiempo', 'El icono de reloj arriba ordena tu biblioteca por años de lanzamiento.', icon: Icons.timeline),
  _Page('Agente en la nube', 'Cada día completa metadatos, descarga portadas y contraportadas, y ordena por artista '
      '(copia, sin borrar). Revisa los avisos en la carpeta _agente: informe, pendientes y duplicados.',
      icon: Icons.cloud_sync_outlined),
  _Page('Listo', 'Puedes volver a abrir esta guía con el icono "?" del menú principal.', icon: Icons.check_circle_outline),
];

class _GuideScreenState extends State<GuideScreen> {
  final _ctrl = PageController();
  int _i = 0;

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final last = _i == _pages.length - 1;
    return Scaffold(
      backgroundColor: const Color(0xFF101014),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        title: const Text('Guía'),
        actions: [TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Saltar'))],
      ),
      body: Column(children: [
        Expanded(
          child: PageView.builder(
            controller: _ctrl,
            itemCount: _pages.length,
            onPageChanged: (i) => setState(() => _i = i),
            itemBuilder: (_, i) {
              final p = _pages[i];
              return Padding(
                padding: const EdgeInsets.symmetric(horizontal: 28),
                child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                  SizedBox(
                    height: 230,
                    width: 230,
                    child: p.model != null
                        ? SpinModel(folder: p.model!, enabled: i == _i)
                        : Icon(p.icon ?? Icons.help_outline, size: 110, color: const Color(0xFFFF8A3D)),
                  ),
                  const SizedBox(height: 24),
                  Text(p.title, textAlign: TextAlign.center, style: const TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.w800)),
                  const SizedBox(height: 12),
                  Text(p.text, textAlign: TextAlign.center, style: const TextStyle(color: Color(0xFFD9D5C8), fontSize: 15, height: 1.4)),
                ]),
              );
            },
          ),
        ),
        Row(mainAxisAlignment: MainAxisAlignment.center, children: [
          for (var i = 0; i < _pages.length; i++)
            Container(
              width: i == _i ? 18 : 7,
              height: 7,
              margin: const EdgeInsets.all(3),
              decoration: BoxDecoration(color: i == _i ? const Color(0xFFFF8A3D) : Colors.white24, borderRadius: BorderRadius.circular(4)),
            ),
        ]),
        Padding(
          padding: const EdgeInsets.fromLTRB(24, 10, 24, 22),
          child: SizedBox(
            width: double.infinity,
            child: FilledButton(
              onPressed: () => last
                  ? Navigator.of(context).pop()
                  : _ctrl.nextPage(duration: const Duration(milliseconds: 300), curve: Curves.easeOut),
              child: Text(last ? 'Empezar' : 'Siguiente'),
            ),
          ),
        ),
      ]),
    );
  }
}
