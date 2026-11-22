import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import '../platform/haptic.dart';
import 'package:flutter/services.dart';

import '../audio/player_service.dart';
import '../models/vinyl.dart';
import '../widgets/cover_art.dart';

String _fmt(Duration d) {
  final m = d.inMinutes, s = d.inSeconds % 60;
  return '$m:${s.toString().padLeft(2, '0')}';
}

/// Reproductor tipo iPod: pantalla con portada y progreso, rueda táctil (girar = volumen con "clic",
/// tocar los bordes = anterior / siguiente / pausa / volver).
class IpodScreen extends StatefulWidget {
  const IpodScreen({super.key, required this.vinyl});
  final Vinyl vinyl;

  @override
  State<IpodScreen> createState() => _IpodScreenState();
}

class _IpodScreenState extends State<IpodScreen> {
  final _ps = PlayerService.instance;
  Timer? _timer;
  double _vol = 1;
  double _lastAngle = 0;
  double _acc = 0;
  DateTime _volShown = DateTime(2000);

  Vinyl get v => widget.vinyl;

  @override
  void initState() {
    super.initState();
    _vol = _ps.player.volume;
    _timer = Timer.periodic(const Duration(milliseconds: 250), (_) {
      if (mounted) setState(() {});
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

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  bool get _playing => _ps.player.playing && _ps.nowPlaying.value?.id == v.id;

  Future<void> _toggle() async {
    if (_ps.player.playing) {
      await _ps.player.pause();
    } else {
      await _ps.player.play();
    }
  }

  void _tapWheel(Offset p, double r) {
    final d = p - Offset(r, r);
    Haptic.selectionClick();
    if (d.distance < r * .34) {
      _toggle();
      return;
    }
    final a = math.atan2(d.dy, d.dx);
    if (a > -math.pi * .75 && a <= -math.pi * .25) {
      Navigator.of(context).maybePop();
    } else if (a > -math.pi * .25 && a <= math.pi * .25) {
      _ps.goTrack((_ps.player.currentIndex ?? 0) + 1);
    } else if (a > math.pi * .25 && a <= math.pi * .75) {
      _toggle();
    } else {
      _ps.goTrack((_ps.player.currentIndex ?? 0) - 1);
    }
  }

  void _spin(Offset p, double r) {
    final d = p - Offset(r, r);
    final a = math.atan2(d.dy, d.dx);
    var da = a - _lastAngle;
    if (da > math.pi) da -= 2 * math.pi;
    if (da < -math.pi) da += 2 * math.pi;
    _lastAngle = a;
    _acc += da;
    if (_acc.abs() > .22) {
      Haptic.selectionClick();
      _vol = (_vol + (_acc > 0 ? .04 : -.04)).clamp(0.0, 1.0);
      _acc = 0;
      _ps.player.setVolume(_vol);
      _volShown = DateTime.now();
    }
  }

  @override
  Widget build(BuildContext context) {
    const ink = Color(0xFF16222A);
    final idx = (_ps.player.currentIndex ?? 0).clamp(0, math.max(0, v.tracks.length - 1)).toInt();
    final title = v.tracks.isEmpty ? v.title : v.tracks[idx];
    final pos = _ps.player.position;
    final dur = _ps.player.duration ?? Duration.zero;
    final prog = dur.inMilliseconds > 0 ? (pos.inMilliseconds / dur.inMilliseconds).clamp(0.0, 1.0) : 0.0;
    final showVol = DateTime.now().difference(_volShown).inMilliseconds < 1400;
    return Scaffold(
      backgroundColor: const Color(0xFF101014),
      appBar: AppBar(backgroundColor: Colors.transparent, title: Text(v.title, maxLines: 1, overflow: TextOverflow.ellipsis)),
      body: Center(
        child: LayoutBuilder(builder: (context, c) {
          final w = math.min(c.maxWidth - 40, (c.maxHeight - 20) * .5683);
          final h = w / .5683;
          final wheel = w * .9;
          final wcx = w * .506, wcy = h * .688;
          final sx = w * .139, sy = h * .035, sw = w * .73, sh = h * .342;
          return SizedBox(
            width: w,
            height: h,
            child: Stack(children: [
              // Mismo modelo 3D del icono del menú, vista frontal en alta resolución.
              Positioned.fill(child: Image.asset('assets/models3d/ipod_front.webp', fit: BoxFit.fill, filterQuality: FilterQuality.high)),
              // Pantalla funcional
              Positioned(
                left: sx, top: sy, width: sw, height: sh,
                child: Container(
                  padding: EdgeInsets.all(w * .02),
                  color: const Color(0xFFCDD6C4),
                  child: DefaultTextStyle(
                    style: const TextStyle(color: ink, fontSize: 11),
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Row(children: [
                        Icon(_playing ? Icons.play_arrow : Icons.pause, size: 13, color: ink),
                        const Spacer(),
                        Text(showVol ? 'Volumen' : 'Reproduciendo', style: const TextStyle(fontWeight: FontWeight.w800)),
                        const Spacer(),
                        const Icon(Icons.battery_full, size: 13, color: ink),
                      ]),
                      const Divider(height: 6, thickness: 1.5, color: ink),
                      Expanded(
                        child: showVol
                            ? Center(child: LinearProgressIndicator(value: _vol, minHeight: 9, color: ink, backgroundColor: const Color(0x3316222A)))
                            : Row(children: [
                                SizedBox(width: sh * .46, height: sh * .46, child: CoverArt(vinyl: v, radius: 1)),
                                const SizedBox(width: 6),
                                Expanded(
                                  child: Column(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.start, children: [
                                    Text(title, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 12)),
                                    Text(v.artist, maxLines: 1, overflow: TextOverflow.ellipsis),
                                    Text(v.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 9)),
                                    Text('${idx + 1} de ${v.tracks.length}', style: const TextStyle(fontSize: 9)),
                                  ]),
                                ),
                              ]),
                      ),
                      Row(children: [
                        Text(_fmt(pos), style: const TextStyle(fontSize: 9)),
                        const SizedBox(width: 4),
                        Expanded(
                          child: LinearProgressIndicator(value: prog, minHeight: 6, color: ink, backgroundColor: const Color(0x3316222A)),
                        ),
                        const SizedBox(width: 4),
                        Text('-${_fmt(dur - pos < Duration.zero ? Duration.zero : dur - pos)}', style: const TextStyle(fontSize: 9)),
                      ]),
                    ]),
                  ),
                ),
              ),
              // Rueda funcional sobre la rueda del modelo
              Positioned(
                left: wcx - wheel / 2,
                top: wcy - wheel / 2,
                width: wheel,
                height: wheel,
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTapUp: (d) => _tapWheel(d.localPosition, wheel / 2),
                  onPanStart: (d) => _lastAngle = math.atan2(d.localPosition.dy - wheel / 2, d.localPosition.dx - wheel / 2),
                  onPanUpdate: (d) => _spin(d.localPosition, wheel / 2),
                  child: Stack(alignment: Alignment.center, children: [
                    Positioned(top: wheel * .06, child: Text('MENU', style: TextStyle(color: const Color(0xFF6A6B72), fontWeight: FontWeight.w800, fontSize: wheel * .06))),
                    Positioned(right: wheel * .05, child: Icon(Icons.fast_forward, color: const Color(0xFF6A6B72), size: wheel * .1)),
                    Positioned(left: wheel * .05, child: Icon(Icons.fast_rewind, color: const Color(0xFF6A6B72), size: wheel * .1)),
                    Positioned(bottom: wheel * .05, child: Icon(Icons.play_arrow, color: const Color(0xFF6A6B72), size: wheel * .1)),
                  ]),
                ),
              ),
            ]),
          );
        }),
      ),
    );
  }
}
