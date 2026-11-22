import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

/// Objeto 3D hecho por el agente: hoja de cuadros girando. Arrastra para girar; sin tocar, gira solo despacio.
class SpriteObject extends StatefulWidget {
  const SpriteObject({super.key, required this.image, required this.frames, required this.cols, this.onTap});
  final ui.Image image;
  final int frames;
  final int cols;
  final VoidCallback? onTap;

  @override
  State<SpriteObject> createState() => _SpriteObjectState();
}

class _SpriteObjectState extends State<SpriteObject> {
  double _pos = 0; // en cuadros
  Timer? _auto;
  bool _drag = false;

  @override
  void initState() {
    super.initState();
    _auto = Timer.periodic(const Duration(milliseconds: 90), (_) {
      if (!_drag && mounted) setState(() => _pos = (_pos + 0.12) % widget.frames);
    });
  }

  @override
  void dispose() {
    _auto?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: widget.onTap,
      onPanStart: (_) => _drag = true,
      onPanUpdate: (d) => setState(() => _pos = (_pos - d.delta.dx / 14) % widget.frames),
      onPanEnd: (_) => _drag = false,
      onPanCancel: () => _drag = false,
      child: AspectRatio(aspectRatio: 1, child: CustomPaint(painter: _P(widget.image, widget.frames, widget.cols, _pos))),
    );
  }
}

class _P extends CustomPainter {
  _P(this.img, this.frames, this.cols, this.pos);
  final ui.Image img;
  final int frames, cols;
  final double pos;

  @override
  void paint(Canvas canvas, Size size) {
    final rows = (frames / cols).ceil();
    final fw = img.width / cols, fh = img.height / rows;
    final i = pos.floor() % frames;
    final src = Rect.fromLTWH((i % cols) * fw, (i ~/ cols) * fh, fw, fh);
    canvas.drawImageRect(img, src, Offset.zero & size, Paint()..filterQuality = FilterQuality.medium);
  }

  @override
  bool shouldRepaint(covariant _P old) => old.pos != pos || old.img != img;
}
