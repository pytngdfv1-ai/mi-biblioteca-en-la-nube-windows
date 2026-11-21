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
  bool _dark = false;
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
    final body = _dark ? const [Color(0xFF3A3A40), Color(0xFF111114)] : const [Color(0xFFF3F3F5), Color(0xFFC9CAD0)];
    final ink = _dark ? Colors.white : const Color(0xFF55565C);
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
          final w = math.min(c.maxWidth - 40, (c.maxHeight - 20) * .6);
          final h = w / .6;
          final wheel = w * .74;
          return Container(
            width: w,
            height: h,
            padding: EdgeInsets.all(w * .06),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(w * .11),
              gradient: LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: body),
              boxShadow: const [BoxShadow(color: Colors.black87, blurRadius: 24, offset: Offset(0, 12))],
            ),
            child: Column(children: [
              GestureDetector(
                onLongPress: () => setState(() => _dark = !_dark),
                child: Container(
                  height: h * .36,
                  padding: EdgeInsets.all(w * .035),
                  decoration: BoxDecoration(
                    color: const Color(0xFFD3E4EA),
                    borderRadius: BorderRadius.circular(w * .03),
                    border: Border.all(color: Colors.black54, width: 3),
                    gradient: const LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [Color(0xFFE2EFF3), Color(0xFFBCD2DA)]),
                  ),
                  child: DefaultTextStyle(
                    style: const TextStyle(color: Color(0xFF16222A), fontSize: 12),
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Row(children: [
                        Text(showVol ? 'Volumen' : 'Reproduciendo', style: const TextStyle(fontWeight: FontWeight.w800)),
                        const Spacer(),
                        Icon(_playing ? Icons.play_arrow : Icons.pause, size: 14, color: const Color(0xFF16222A)),
                        const Icon(Icons.battery_full, size: 14, color: Color(0xFF16222A)),
                      ]),
                      const Divider(height: 8, color: Color(0x5516222A)),
                      Expanded(
                        child: showVol
                            ? Center(
                                child: LinearProgressIndicator(
                                  value: _vol,
                                  minHeight: 10,
                                  color: const Color(0xFF16222A),
                                  backgroundColor: const Color(0x3316222A),
                                ),
                              )
                            : Row(children: [
                                SizedBox(width: h * .13, height: h * .13, child: CoverArt(vinyl: v, radius: 3)),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Column(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.start, children: [
                                    Text(title, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 13)),
                                    Text(v.artist, maxLines: 1, overflow: TextOverflow.ellipsis),
                                    Text('${idx + 1} de ${v.tracks.length}', style: const TextStyle(fontSize: 10)),
                                  ]),
                                ),
                              ]),
                      ),
                      Row(children: [
                        Text(_fmt(pos), style: const TextStyle(fontSize: 10)),
                        const SizedBox(width: 6),
                        Expanded(
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(4),
                            child: LinearProgressIndicator(value: prog, minHeight: 7, color: const Color(0xFF2B79C2), backgroundColor: const Color(0x3316222A)),
                          ),
                        ),
                        const SizedBox(width: 6),
                        Text('-${_fmt(dur - pos < Duration.zero ? Duration.zero : dur - pos)}', style: const TextStyle(fontSize: 10)),
                      ]),
                    ]),
                  ),
                ),
              ),
              const Spacer(),
              SizedBox(
                width: wheel,
                height: wheel,
                child: GestureDetector(
                  onTapUp: (d) => _tapWheel(d.localPosition, wheel / 2),
                  onPanStart: (d) => _lastAngle = math.atan2(d.localPosition.dy - wheel / 2, d.localPosition.dx - wheel / 2),
                  onPanUpdate: (d) => _spin(d.localPosition, wheel / 2),
                  child: Stack(alignment: Alignment.center, children: [
                    Container(
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        gradient: RadialGradient(colors: _dark ? const [Color(0xFF2A2A2F), Color(0xFF0A0A0C)] : const [Color(0xFFFFFFFF), Color(0xFFD6D7DC)]),
                        boxShadow: const [BoxShadow(color: Colors.black26, blurRadius: 6, offset: Offset(0, 3))],
                      ),
                    ),
                    Container(
                      width: wheel * .32,
                      height: wheel * .32,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        gradient: LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: body.reversed.toList()),
                        border: Border.all(color: Colors.black12),
                      ),
                    ),
                    Positioned(top: wheel * .08, child: Text('MENU', style: TextStyle(color: ink, fontWeight: FontWeight.w800, fontSize: wheel * .06))),
                    Positioned(right: wheel * .08, child: Icon(Icons.fast_forward, color: ink, size: wheel * .1)),
                    Positioned(left: wheel * .08, child: Icon(Icons.fast_rewind, color: ink, size: wheel * .1)),
                    Positioned(bottom: wheel * .07, child: Icon(Icons.play_arrow, color: ink, size: wheel * .1)),
                  ]),
                ),
              ),
              const Spacer(),
            ]),
          );
        }),
      ),
    );
  }
}
