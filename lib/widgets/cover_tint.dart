import 'package:flutter/material.dart';

import '../data/cover_color.dart';

/// Fondo oscuro que toma el tono de la portada (con transición suave).
class CoverTint extends StatelessWidget {
  const CoverTint({super.key, required this.url, required this.base, required this.builder});

  final String? url;
  final Color base;
  final Widget Function(BuildContext context, Color background) builder;

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<Color?>(
      future: CoverColor.of(url),
      initialData: CoverColor.peek(url),
      builder: (context, snap) {
        final end = snap.data != null ? CoverColor.background(snap.data!) : base;
        return TweenAnimationBuilder<Color?>(
          tween: ColorTween(end: end),
          duration: const Duration(milliseconds: 500),
          builder: (ctx, c, _) => builder(ctx, c ?? base),
        );
      },
    );
  }
}
