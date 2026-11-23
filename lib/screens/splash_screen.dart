import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../data/agent_index.dart';
import '../data/library_sync.dart';
import '../data/update_notice.dart';
import '../data/vinyl_store.dart';
import 'home_screen.dart';

/// Inicio: disco girando con el icono como etiqueta, brazo que baja y una pista que avanza
/// mientras carga; todo respira suavemente. Al terminar, el menú aparece con un desvanecimiento.
class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key, required this.store, required this.ready});
  final VinylStore store;
  final Future<void> ready;

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: const Duration(seconds: 3))..repeat();
  final _sw = Stopwatch()..start();
  bool _ready = false, _gone = false;
  double _finish = -1; // segundos en que terminó la carga
  double _p = 0; // avance mostrado (suavizado)
  bool _skip = false;
  String _nueva = '';
  String _nuevaUrl = '';

  @override
  void initState() {
    super.initState();
    Future.any<void>([widget.ready, Future<void>.delayed(const Duration(seconds: 40))]).whenComplete(() {
      _ready = true;
      if (_nueva.isEmpty) _checkVersion();
    });
    _checkVersion();
    _c.addListener(_tick);
  }

  Future<void> _checkVersion() async {
    try {
      final j = await AgentFiles.readJson('version.json');
      final ver = (j?['version'] ?? '').toString();
      if (false && ver.isNotEmpty && UpdateNotice.current.isNotEmpty && UpdateNotice.isNewer(ver, UpdateNotice.current) && mounted) {
        setState(() {
          _nueva = ver;
          _nuevaUrl = (j?['url'] ?? '').toString();
        });
      }
    } catch (_) {}
  }

  void _tick() {
    final t = _sw.elapsedMilliseconds / 1000;
    final target = _ready ? 1.0 : LibrarySync.progress.value.clamp(0.0, .98);
    _p += (target - _p) * .07;
    if (_ready && _finish < 0 && t > 1.6 && _p > .97) _finish = t;
    if (_skip && _finish < 0) _finish = t;
    if (_finish >= 0 && t - _finish > .5 && !_gone && mounted) {
      _gone = true;
      Navigator.of(context).pushReplacement(PageRouteBuilder<void>(
        transitionDuration: const Duration(milliseconds: 500),
        pageBuilder: (_, __, ___) => HomeScreen(store: widget.store),
        transitionsBuilder: (_, a, __, child) => FadeTransition(opacity: a, child: child),
      ));
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0B0B10),
      body: AnimatedBuilder(
        animation: _c,
        builder: (context, _) {
          final t = _sw.elapsedMilliseconds / 1000;
          final breathe = 1 + .018 * math.sin(t * 2.2);
          final drop = Curves.easeOutCubic.transform((t / .9).clamp(0.0, 1.0));
          final p = _p.clamp(0.0, 1.0);
          final name = Curves.easeIn.transform(((t - .5) / .8).clamp(0.0, 1.0));
          return LayoutBuilder(builder: (context, c) {
            final d = math.min(c.maxWidth * .74, c.maxHeight * .46);
            return Center(
              child: Transform.scale(
                scale: breathe,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    SizedBox(
                      width: d * 1.3,
                      height: d * 1.15,
                      child: Stack(
                        alignment: Alignment.center,
                        children: [
                          Positioned(
                            left: 0,
                            bottom: 0,
                            width: d,
                            height: d,
                            child: Transform.rotate(
                              angle: _c.value * 2 * math.pi,
                              child: Stack(
                                alignment: Alignment.center,
                                children: [
                                  CustomPaint(size: Size.square(d), painter: _DiscPainter()),
                                  ClipOval(child: Image.asset('assets/icon/app_icon.png', width: d * .4, height: d * .4, fit: BoxFit.cover)),
                                ],
                              ),
                            ),
                          ),
                          Positioned.fill(child: CustomPaint(painter: _ArmPainter(d, drop, p, _c.value))),
                        ],
                      ),
                    ),
                    SizedBox(height: d * .12),
                    Opacity(
                      opacity: name,
                      child: Column(children: [
                        const Text('Mi Biblioteca en la nube',
                            style: TextStyle(color: Color(0xFFEBDDBF), fontSize: 26, fontWeight: FontWeight.w300, letterSpacing: 2)),
                        const SizedBox(height: 14),
                        SizedBox(
                          width: d * .8,
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(2),
                            child: LinearProgressIndicator(
                              value: p,
                              minHeight: 3,
                              backgroundColor: const Color(0xFF23232B),
                              valueColor: const AlwaysStoppedAnimation(Color(0xFFEBDDBF)),
                            ),
                          ),
                        ),
                        const SizedBox(height: 8),
                        ValueListenableBuilder<String>(
                          valueListenable: LibrarySync.step,
                          builder: (_, m, __) => Text(
                            m.isEmpty ? 'Cargando…' : '$m · ${(p * 100).round()} %',
                            style: const TextStyle(color: Color(0x99EBDDBF), fontSize: 12),
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          UpdateNotice.current.isEmpty ? 'Versión de desarrollo' : 'Versión ${UpdateNotice.current}',
                          style: const TextStyle(color: Color(0x99EBDDBF), fontSize: 12),
                        ),
                        if (_nueva.isNotEmpty)
                          Padding(
                            padding: const EdgeInsets.only(top: 4),
                            child: TextButton.icon(
                              onPressed: () => UpdateNotice.open(context, _nuevaUrl),
                              icon: const Icon(Icons.download, size: 18, color: Color(0xFFE8C14A)),
                              label: Text('Actualización disponible: $_nueva · Descargar',
                                  style: const TextStyle(color: Color(0xFFE8C14A), fontSize: 13, fontWeight: FontWeight.w600)),
                            ),
                          ),
                        SizedBox(
                          height: 40,
                          child: t > 4 && !_ready
                              ? TextButton(onPressed: () => _skip = true, child: const Text('Entrar ya'))
                              : null,
                        ),
                      ]),
                    ),
                  ],
                ),
              ),
            );
          });
        },
      ),
    );
  }
}

class _DiscPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size s) {
    final o = s.center(Offset.zero), r = s.width / 2;
    canvas.drawCircle(o, r, Paint()..color = const Color(0xFF101014));
    for (var k = .46; k < .98; k += .03) {
      canvas.drawCircle(o, r * k, Paint()..style = PaintingStyle.stroke..strokeWidth = .8..color = const Color(0x1AFFFFFF));
    }
    canvas.drawCircle(
      o,
      r,
      Paint()
        ..shader = const SweepGradient(colors: [Color(0x00FFFFFF), Color(0x2EFFFFFF), Color(0x00FFFFFF), Color(0x2EFFFFFF), Color(0x00FFFFFF)])
            .createShader(Rect.fromCircle(center: o, radius: r)),
    );
    canvas.drawCircle(o, r, Paint()..style = PaintingStyle.stroke..strokeWidth = 2..color = const Color(0xFF2A2A31));
  }

  @override
  bool shouldRepaint(covariant _DiscPainter o) => false;
}

class _ArmPainter extends CustomPainter {
  _ArmPainter(this.d, this.drop, this.p, this.spin);
  final double d, drop, p, spin;

  @override
  void paint(Canvas canvas, Size s) {
    final r = d / 2;
    final c = Offset(r, s.height - r); // centro del disco
    final pivot = Offset(c.dx + r * 1.12, c.dy - r * 1.02);
    final len = r * 1.25;
    // radio del surco donde apoya la aguja: baja desde fuera del disco y avanza hacia el centro
    final rad = drop < 1 ? r * (1.3 - .37 * drop) : r * (.93 - .48 * p);
    final dv = pivot - c;
    final dist = dv.distance;
    final a = (rad * rad - len * len + dist * dist) / (2 * dist);
    final h = math.sqrt(math.max(0, rad * rad - a * a));
    final u = dv / dist;
    final nrm = Offset(-u.dy, u.dx);
    final needle = c + u * a + nrm * h;
    final dir = (needle - pivot) / (needle - pivot).distance;
    final lift = (1 - drop);

    // sombra
    canvas.drawLine(pivot + const Offset(3, 7), needle + Offset(3 + 6 * lift, 7 + 8 * lift),
        Paint()..strokeWidth = 5..strokeCap = StrokeCap.round..color = Color.fromRGBO(0, 0, 0, .35));
    // contrapeso (detrás del pivote)
    final back = pivot - dir * (r * .3);
    canvas.drawLine(pivot, back, Paint()..strokeWidth = 5..strokeCap = StrokeCap.round..color = const Color(0xFF16161A));
    canvas.drawLine(back + dir * (r * .06), back - dir * (r * .02), Paint()..strokeWidth = 14..strokeCap = StrokeCap.round..color = const Color(0xFF0E0E10));
    // brazo: tubo negro con un codo, como el del tocadiscos del menú
    final elbow = pivot + dir * (len * .28);
    canvas.drawLine(pivot, elbow, Paint()..strokeWidth = 5..strokeCap = StrokeCap.round..color = const Color(0xFF16161A));
    final head = needle - dir * (r * .12);
    canvas.drawLine(elbow, head, Paint()..strokeWidth = 4.2..strokeCap = StrokeCap.round..color = const Color(0xFF1E1E23));
    // cabezal con cápsula blanca
    canvas.drawLine(head, needle, Paint()..strokeWidth = 11..strokeCap = StrokeCap.round..color = const Color(0xFF0E0E10));
    canvas.drawLine(head + dir * (r * .035), needle - dir * (r * .005), Paint()..strokeWidth = 6.5..strokeCap = StrokeCap.round..color = Colors.white);
    // base del pivote
    canvas.drawCircle(pivot, 15, Paint()..color = const Color(0xFF111113));
    canvas.drawCircle(pivot, 15, Paint()..style = PaintingStyle.stroke..strokeWidth = 1.5..color = const Color(0xFF3A3A42));
    canvas.drawCircle(pivot, 6, Paint()..color = const Color(0xFFC9CCD2));
    canvas.drawCircle(pivot, 2.4, Paint()..color = const Color(0xFF2A2A31));
  }

  @override
  bool shouldRepaint(covariant _ArmPainter o) => true;
}
