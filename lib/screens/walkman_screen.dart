import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import '../platform/haptic.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../audio/player_service.dart';
import '../data/cassette_face.dart';
import '../data/objects3d.dart';
import '../models/vinyl.dart';

String _fmt(Duration d) {
  final m = d.inMinutes, s = d.inSeconds % 60;
  return '$m:${s.toString().padLeft(2, '0')}';
}

/// Walkman portátil (Sony TPS-L2): modelo 3D de frente, carretes que giran en la ventana,
/// teclas de cassette (rebobinar y avanzar mantenidos), contador y pilas que se gastan al escuchar.
class WalkmanScreen extends StatefulWidget {
  const WalkmanScreen({super.key, required this.vinyl});
  final Vinyl vinyl;

  @override
  State<WalkmanScreen> createState() => _WalkmanScreenState();
}

class _WalkmanScreenState extends State<WalkmanScreen> with SingleTickerProviderStateMixin {
  static const _kBattery = 'walkman_battery_v1';
  final _ps = PlayerService.instance;
  late final AnimationController _spin = AnimationController(vsync: this, duration: const Duration(seconds: 3));
  Timer? _timer;
  Timer? _seek;
  double _battery = 1;
  int _tick = 0;
  bool _seeking = false;
  ui.Image? _face;
  ui.Image? _cover;

  Vinyl get v => widget.vinyl;
  bool get _playing => _ps.player.playing && _ps.nowPlaying.value?.id == v.id;

  @override
  void initState() {
    super.initState();
    _loadBattery();
    _loadFace();
    _timer = Timer.periodic(const Duration(milliseconds: 250), (_) {
      if (!mounted) return;
      if (_playing || _seeking) {
        if (!_spin.isAnimating) _spin.repeat();
        // Las pilas se gastan escuchando: ~1 % cada 2 minutos.
        if (_playing && ++_tick % 480 == 0) _drain(.01);
      } else if (_spin.isAnimating) {
        _spin.stop();
      }
      setState(() {});
    });
    _start();
  }

  Future<void> _start() async {
    try {
      await _ps.start(v);
    } catch (_) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('No se pudo reproducir')));
    }
  }

  /// Cassette que está sonando: se dibuja entero y la ventana del Walkman muestra solo su parte central.
  Future<void> _loadFace() async {
    try {
      ui.Image? cover;
      try {
        cover = await Objects3D.loadImage(v.coverUrl);
      } catch (_) {}
      final f = await CassetteFace.build(v, cover: cover, w: 700);
      if (mounted) setState(() { _face = f; _cover = cover; });
    } catch (_) {}
  }

  Future<void> _loadBattery() async {
    try {
      final p = await SharedPreferences.getInstance();
      final b = p.getDouble(_kBattery);
      if (b != null && mounted) setState(() => _battery = b.clamp(0.0, 1.0));
    } catch (_) {}
  }

  Future<void> _drain(double by) async {
    _battery = (_battery - by).clamp(0.0, 1.0);
    try {
      (await SharedPreferences.getInstance()).setDouble(_kBattery, _battery);
    } catch (_) {}
  }

  Future<void> _newBatteries() async {
    Haptic.mediumImpact();
    setState(() => _battery = 1);
    try {
      (await SharedPreferences.getInstance()).setDouble(_kBattery, 1);
    } catch (_) {}
    if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Pilas nuevas puestas')));
  }

  @override
  void dispose() {
    _timer?.cancel();
    _seek?.cancel();
    _spin.dispose();
    super.dispose();
  }

  Future<void> _toggle() async {
    Haptic.selectionClick();
    if (_ps.player.playing) {
      await _ps.player.pause();
    } else {
      await _ps.player.play();
    }
  }

  void _startSeek(int dir) {
    Haptic.selectionClick();
    _seeking = true;
    _seek?.cancel();
    _seek = Timer.periodic(const Duration(milliseconds: 140), (_) {
      final dur = _ps.player.duration ?? Duration.zero;
      var t = _ps.player.position + Duration(seconds: 4 * dir);
      if (t < Duration.zero) t = Duration.zero;
      if (dur > Duration.zero && t > dur) t = dur;
      _ps.player.seek(t);
    });
  }

  void _stopSeek() {
    _seek?.cancel();
    _seeking = false;
  }

  @override
  Widget build(BuildContext context) {
    final idx = (_ps.player.currentIndex ?? 0).clamp(0, math.max(0, v.tracks.length - 1)).toInt();
    final title = v.tracks.isEmpty ? v.title : v.tracks[idx];
    final pos = _ps.player.position;
    final dur = _ps.player.duration ?? Duration.zero;
    final prog = dur.inMilliseconds > 0 ? (pos.inMilliseconds / dur.inMilliseconds).clamp(0.0, 1.0) : 0.0;
    final low = _battery < .15;
    return Scaffold(
      backgroundColor: const Color(0xFF101014),
      appBar: AppBar(backgroundColor: Colors.transparent, title: Text(v.title, maxLines: 1, overflow: TextOverflow.ellipsis)),
      body: Column(children: [
        Expanded(
          child: Center(
            child: LayoutBuilder(builder: (context, c) {
              const ar = 720 / 980;
              final w = math.min(c.maxWidth - 60, (c.maxHeight - 10) * ar);
              final h = w / ar;
              return SizedBox(
                width: w,
                height: h,
                child: Stack(children: [
                  Positioned.fill(child: Image.asset('assets/models3d/walkman_front.webp', fit: BoxFit.fill, filterQuality: FilterQuality.high)),
                  // Ventana del cassette: carretes que giran y contador
                  Positioned(
                    left: w * .262,
                    top: h * .366,
                    width: w * .232,
                    height: h * .434,
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(w * .01),
                      child: Container(
                        color: const Color(0xFF1B1B1E),
                        child: AnimatedBuilder(
                          animation: _spin,
                          builder: (_, __) => CustomPaint(
                            painter: _WindowPainter(_spin.value * 2 * math.pi * (_seeking ? 3 : 1), prog, '${idx + 1}/${v.tracks.length}', '${v.title} – ${v.artist}', _cover, v.hue),
                          ),
                        ),
                      ),
                    ),
                  ),
                ]),
              );
            }),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(24, 4, 24, 0),
          child: Column(children: [
            Text(title, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 16)),
            Text(v.artist, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Colors.white70, fontSize: 12)),
            const SizedBox(height: 6),
            Row(children: [
              Text(_fmt(pos), style: const TextStyle(color: Colors.white70, fontSize: 11)),
              const SizedBox(width: 8),
              Expanded(child: LinearProgressIndicator(value: prog, minHeight: 4, color: const Color(0xFFF0A540), backgroundColor: Colors.white12)),
              const SizedBox(width: 8),
              Text(_fmt(dur), style: const TextStyle(color: Colors.white70, fontSize: 11)),
            ]),
          ]),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 14),
          child: Row(mainAxisAlignment: MainAxisAlignment.spaceEvenly, children: [
            _Key(icon: Icons.skip_previous, onTap: () => _ps.goTrack(idx - 1)),
            _Key(icon: Icons.fast_rewind, onHoldStart: () => _startSeek(-1), onHoldEnd: _stopSeek),
            _Key(icon: _playing ? Icons.pause : Icons.play_arrow, onTap: _toggle, hot: true),
            _Key(icon: Icons.fast_forward, onHoldStart: () => _startSeek(1), onHoldEnd: _stopSeek),
            _Key(icon: Icons.skip_next, onTap: () => _ps.goTrack(idx + 1)),
            InkWell(
              onTap: _newBatteries,
              borderRadius: BorderRadius.circular(8),
              child: Padding(
                padding: const EdgeInsets.all(6),
                child: Column(mainAxisSize: MainAxisSize.min, children: [
                  Icon(low ? Icons.battery_alert : Icons.battery_full, color: low ? Colors.redAccent : Colors.white70),
                  Text('${(_battery * 100).round()}%', style: TextStyle(color: low ? Colors.redAccent : Colors.white54, fontSize: 10)),
                ]),
              ),
            ),
          ]),
        ),
      ]),
    );
  }
}

class _Key extends StatelessWidget {
  const _Key({required this.icon, this.onTap, this.onHoldStart, this.onHoldEnd, this.hot = false});
  final IconData icon;
  final VoidCallback? onTap, onHoldStart, onHoldEnd;
  final bool hot;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      onLongPressStart: onHoldStart == null ? null : (_) => onHoldStart!(),
      onLongPressEnd: onHoldEnd == null ? null : (_) => onHoldEnd!(),
      onLongPressCancel: onHoldEnd,
      child: Container(
        width: 46,
        height: 46,
        decoration: BoxDecoration(
          color: hot ? const Color(0xFFF0A540) : const Color(0xFF2A2F3A),
          borderRadius: BorderRadius.circular(10),
          boxShadow: const [BoxShadow(color: Colors.black54, blurRadius: 4, offset: Offset(0, 2))],
        ),
        child: Icon(icon, color: hot ? Colors.black87 : Colors.white70),
      ),
    );
  }
}

class _WindowPainter extends CustomPainter {
  _WindowPainter(this.angle, this.prog, this.counter, this.label, this.cover, this.hue);
  final double angle, prog, hue;
  final String counter, label;
  final ui.Image? cover;

  @override
  void paint(Canvas c, Size s) {
    final W = s.width, H = s.height;
    c.drawRect(Offset.zero & s, Paint()..color = const Color(0xFF17171B));
    // Papel de la etiqueta (borde izquierdo), con el título escrito de arriba abajo.
    final paperW = W * .30;
    c.drawRect(Rect.fromLTWH(0, 0, paperW, H), Paint()..color = HSLColor.fromAHSL(1, hue % 360, .28, .88).toColor());
    c.drawLine(Offset(paperW * .22, 0), Offset(paperW * .22, H), Paint()..color = const Color(0x66D04040)..strokeWidth = 1);
    c.save();
    c.translate(paperW * .5, H * .04);
    c.rotate(math.pi / 2);
    final tp = TextPainter(
      text: TextSpan(text: label, style: TextStyle(fontSize: paperW * .5, fontFamily: 'cursive', fontWeight: FontWeight.w700, color: const Color(0xFF1F3C88))),
      textDirection: TextDirection.ltr,
      maxLines: 1,
      ellipsis: '…',
    )..layout(maxWidth: H * .8);
    tp.paint(c, Offset(0, -tp.height / 2));
    c.restore();
    // Franjas rojas y blancas a ambos lados de la ventana de cinta.
    final tint = HSLColor.fromAHSL(1, hue % 360, .65, .48).toColor();
    void stripes(double x0, double x1) {
      final area = Rect.fromLTWH(x0, 0, x1 - x0, H);
      if (cover != null) {
        c.save();
        c.clipRect(area);
        final k = math.max(area.width / cover!.width, area.height / cover!.height);
        c.drawImageRect(cover!, Rect.fromLTWH(0, 0, cover!.width.toDouble(), cover!.height.toDouble()),
            Rect.fromCenter(center: area.center, width: cover!.width * k, height: cover!.height * k), Paint()..filterQuality = FilterQuality.low);
        c.restore();
      }
      final n = 4;
      final sw = (x1 - x0) / (n * 2);
      for (var i = 0; i < n; i++) {
        c.drawRect(Rect.fromLTWH(x0 + sw * 2 * i, 0, sw, H), Paint()..color = tint.withOpacity(cover != null ? .55 : 1));
      }
    }
    stripes(paperW, W * .40);
    stripes(W * .93, W);
    // Ventana oscura brillante con los carretes.
    final win = Rect.fromLTWH(W * .40, H * .05, W * .53, H * .90);
    final wr = RRect.fromRectAndRadius(win, Radius.circular(W * .03));
    c.drawRRect(wr, Paint()..shader = const LinearGradient(colors: [Color(0xFF2B2B31), Color(0xFF0E0E11)], begin: Alignment.topLeft, end: Alignment.bottomRight).createShader(win));
    c.save();
    c.clipRRect(wr);
    final cx = win.center.dx;
    final r = win.width * .40;
    for (final top in [true, false]) {
      final p = Offset(cx, top ? H * .27 : H * .73);
      final wound = top ? (1 - .35 * prog) : (.65 + .35 * prog);
      c.drawCircle(p, r * 1.25 * wound, Paint()..color = const Color(0xFF3B2A20));
      c.drawCircle(p, r, Paint()..color = const Color(0xFF0A0A0C));
      c.drawCircle(p, r * .86, Paint()..style = PaintingStyle.stroke..strokeWidth = r * .06..color = const Color(0xFF35353B));
      // tres dientes en Y
      for (var i = 0; i < 3; i++) {
        final a = angle + i * 2 * math.pi / 3 - math.pi / 2;
        c.drawLine(p, p + Offset(math.cos(a), math.sin(a)) * r * .62, Paint()..color = const Color(0xFFEDEDEF)..strokeWidth = math.max(1.5, r * .16)..strokeCap = StrokeCap.round);
      }
      c.drawCircle(p, r * .14, Paint()..color = const Color(0xFF0A0A0C));
    }
    // Reflejo diagonal
    c.drawPath(
        Path()
          ..moveTo(win.left, win.top + H * .25)
          ..lineTo(win.right, win.top + H * .02)
          ..lineTo(win.right, win.top + H * .22)
          ..lineTo(win.left, win.top + H * .5)
          ..close(),
        Paint()..color = const Color(0x14FFFFFF));
    c.restore();
    c.drawRRect(wr, Paint()..style = PaintingStyle.stroke..strokeWidth = 1.2..color = const Color(0xFF55555C));
    // Contador sobre el papel
    final ct = TextPainter(
      text: TextSpan(text: counter, style: TextStyle(color: const Color(0xFF3B3B3B), fontSize: paperW * .3, fontWeight: FontWeight.w800)),
      textDirection: TextDirection.ltr,
    )..layout();
    c.save();
    c.translate(paperW * .62, H * .98);
    c.rotate(-math.pi / 2);
    ct.paint(c, Offset(0, -ct.height / 2));
    c.restore();
  }

  @override
  bool shouldRepaint(covariant _WindowPainter o) => o.angle != angle || o.prog != prog || o.counter != counter || o.label != label || o.cover != cover || o.hue != hue;
}
