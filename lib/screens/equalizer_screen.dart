import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../data/equalizer.dart';
import '../data/levels.dart';

/// Ecualizador funcional con panel plateado: interruptor, 5 bandas con fader y LED, presets.
class EqualizerScreen extends StatefulWidget {
  const EqualizerScreen({super.key});

  @override
  State<EqualizerScreen> createState() => _EqualizerScreenState();
}

class _EqualizerScreenState extends State<EqualizerScreen> {
  late final Future<bool> _ready = Eq.apply();

  String _hz(double f) => f >= 1000 ? '${(f / 1000).toStringAsFixed(f >= 10000 ? 0 : 1)} kHz' : '${f.round()} Hz';

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0F1116),
      appBar: AppBar(backgroundColor: const Color(0xFF0F1116), title: const Text('Ecualizador')),
      body: FutureBuilder<bool>(
        future: _ready,
        builder: (context, snap) {
          if (snap.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          final pr = Eq.params;
          if (snap.data != true || pr == null) {
            return const Center(
              child: Padding(
                padding: EdgeInsets.all(32),
                child: Text('Reproduce algo y vuelve a abrir el ecualizador.',
                    textAlign: TextAlign.center, style: TextStyle(color: Colors.white70)),
              ),
            );
          }
          return ValueListenableBuilder<bool>(
            valueListenable: Eq.enabled,
            builder: (context, on, _) {
              final n = pr.bands.length;
              double g(int i) => (i < Eq.gains.length ? Eq.gains[i] : 0.0).clamp(pr.minDecibels, pr.maxDecibels).toDouble();
              return Padding(
                padding: const EdgeInsets.fromLTRB(14, 4, 14, 18),
                child: Column(
                  children: [
                    if (!Eq.effectActive)
                      const Padding(
                        padding: EdgeInsets.only(bottom: 8),
                        child: Text(
                          'Reproduce algo para activar el ecualizador. Si no se nota, el motor de audio no admite el filtro.',
                          textAlign: TextAlign.center,
                          style: TextStyle(color: Colors.amberAccent, fontSize: 12),
                        ),
                      ),
                    Expanded(
                      child: Container(
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(18),
                          gradient: const LinearGradient(
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                            colors: [Color(0xFFD9DBE0), Color(0xFFA9ACB3), Color(0xFFC8CAD0)],
                          ),
                          boxShadow: const [BoxShadow(color: Colors.black54, blurRadius: 14, offset: Offset(0, 6))],
                        ),
                        padding: const EdgeInsets.fromLTRB(12, 14, 12, 12),
                        child: Column(
                          children: [
                            Row(
                              children: [
                                GestureDetector(
                                  onTap: () => Eq.setEnabled(!on),
                                  child: Container(
                                    width: 16,
                                    height: 16,
                                    decoration: BoxDecoration(
                                      shape: BoxShape.circle,
                                      color: on ? const Color(0xFF45E08A) : const Color(0xFF3A3D44),
                                      boxShadow: on ? const [BoxShadow(color: Color(0xAA45E08A), blurRadius: 10)] : null,
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Text(on ? 'ON' : 'OFF',
                                    style: const TextStyle(color: Color(0xFF22252B), fontWeight: FontWeight.w700, fontSize: 12)),
                                const Spacer(),
                                ValueListenableBuilder<double>(
                                  valueListenable: Levels.level,
                                  builder: (_, l, __) => _Needle(
                                    level: !on ? 0 : (Levels.live ? l : (g(0).abs() + g(n - 1).abs()) / (2 * pr.maxDecibels)),
                                    live: on && Levels.live,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 10),
                            Expanded(
                              child: Opacity(
                                opacity: on ? 1 : .55,
                                child: IgnorePointer(
                                  ignoring: !on,
                                  child: Row(
                                    children: [
                                      Column(
                                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                        children: [
                                          for (final t in ['+12', '0', '−12'])
                                            Text(t, style: const TextStyle(fontSize: 10, color: Color(0xFF3A3D44))),
                                        ],
                                      ),
                                      for (var i = 0; i < n; i++)
                                        Expanded(
                                          child: Column(
                                            children: [
                                              Expanded(
                                                child: RotatedBox(
                                                  quarterTurns: 3,
                                                  child: SliderTheme(
                                                    data: SliderTheme.of(context).copyWith(
                                                      trackHeight: 5,
                                                      activeTrackColor: const Color(0xFF101116),
                                                      inactiveTrackColor: const Color(0xFF101116),
                                                      thumbColor: const Color(0xFFF2F3F5),
                                                      overlayColor: Colors.black12,
                                                      thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 11, elevation: 4),
                                                    ),
                                                    child: Slider(
                                                      min: pr.minDecibels,
                                                      max: pr.maxDecibels,
                                                      value: g(i),
                                                      onChanged: (v) {
                                                        Eq.setGain(i, v);
                                                        setState(() {});
                                                      },
                                                      onChangeEnd: (_) => Eq.commit(),
                                                    ),
                                                  ),
                                                ),
                                              ),
                                              const SizedBox(height: 6),
                                              Container(
                                                width: 8,
                                                height: 8,
                                                decoration: BoxDecoration(
                                                  shape: BoxShape.circle,
                                                  color: on && g(i).abs() > .3 ? const Color(0xFF45E08A) : const Color(0xFF4A4D55),
                                                ),
                                              ),
                                              const SizedBox(height: 4),
                                              Text(_hz(pr.bands[i].centerFrequency),
                                                  style: const TextStyle(fontSize: 10, color: Color(0xFF22252B), fontWeight: FontWeight.w600)),
                                            ],
                                          ),
                                        ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    SizedBox(
                      height: 40,
                      child: ListView(
                        scrollDirection: Axis.horizontal,
                        children: [
                          for (final p in Eq.presets.keys)
                            Padding(
                              padding: const EdgeInsets.only(right: 8),
                              child: ActionChip(
                                label: Text(p),
                                onPressed: () async {
                                  if (!Eq.enabled.value) await Eq.setEnabled(true);
                                  await Eq.preset(p);
                                  if (mounted) setState(() {});
                                },
                              ),
                            ),
                        ],
                      ),
                    ),
                  ],
                ),
              );
            },
          );
        },
      ),
    );
  }
}

/// Medidor analógico con aguja (nivel 0 a 1).
class _Needle extends StatelessWidget {
  const _Needle({required this.level, this.live = false});
  final double level;
  final bool live;

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      tween: Tween(end: level.clamp(0.0, 1.0)),
      duration: Duration(milliseconds: live ? 80 : 450),
      curve: live ? Curves.linear : Curves.elasticOut,
      builder: (_, v, __) => CustomPaint(size: const Size(84, 46), painter: _NeedlePainter(v)),
    );
  }
}

class _NeedlePainter extends CustomPainter {
  _NeedlePainter(this.v);
  final double v;

  @override
  void paint(Canvas c, Size s) {
    final r = RRect.fromRectAndRadius(Offset.zero & s, const Radius.circular(6));
    c.drawRRect(r, Paint()..shader = const LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [Color(0xFFF4EBCF), Color(0xFFD9CCA3)]).createShader(r.outerRect));
    c.drawRRect(r, Paint()..style = PaintingStyle.stroke..strokeWidth = 1.5..color = const Color(0xFF14161C));
    final pivot = Offset(s.width / 2, s.height * 1.02);
    final rad = s.height * .86;
    const a0 = -2.35, a1 = -0.79; // arco de la escala
    for (var i = 0; i <= 10; i++) {
      final a = a0 + (a1 - a0) * i / 10;
      final hot = i >= 8;
      c.drawLine(pivot + Offset(math.cos(a), math.sin(a)) * rad * .88, pivot + Offset(math.cos(a), math.sin(a)) * rad,
          Paint()..strokeWidth = i % 5 == 0 ? 1.6 : .8..color = hot ? const Color(0xFFC0392B) : const Color(0xFF22252B));
    }
    final a = a0 + (a1 - a0) * v;
    c.save();
    c.clipRRect(r);
    c.drawLine(pivot, pivot + Offset(math.cos(a), math.sin(a)) * rad * .95, Paint()..strokeWidth = 1.6..strokeCap = StrokeCap.round..color = const Color(0xFF111111));
    c.restore();
    c.drawCircle(Offset(s.width / 2, s.height - 2), 4, Paint()..color = const Color(0xFF22252B));
  }

  @override
  bool shouldRepaint(covariant _NeedlePainter o) => o.v != v;
}
