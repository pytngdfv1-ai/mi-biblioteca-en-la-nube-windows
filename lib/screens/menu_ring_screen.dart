import 'package:flutter/material.dart';

import '../data/tilt.dart';
import '../theme.dart';
import '../widgets/menu_icons.dart';
import '../widgets/ring_360.dart';

/// Entrada de un menú en anillo 360°.
class MenuRingItem {
  const MenuRingItem(this.label, this.sub, this.kind, this.model, this.onTap);
  final String label;
  final String sub;
  final MenuIconKind kind;
  final String? model;
  final VoidCallback onTap;
}

/// Menú secundario con el mismo giro 360° del menú principal: los iconos orbitan por la
/// pantalla y giran sobre sí mismos.
class MenuRingScreen extends StatefulWidget {
  const MenuRingScreen({super.key, required this.title, required this.items});
  final String title;
  final List<MenuRingItem> items;

  @override
  State<MenuRingScreen> createState() => _MenuRingScreenState();
}

class _MenuRingScreenState extends State<MenuRingScreen> {
  VoidCallback? _release;

  @override
  void initState() {
    super.initState();
    _release = Tilt.instance.acquire();
  }

  @override
  void dispose() {
    _release?.call();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final items = widget.items;
    return Scaffold(
      backgroundColor: AppColors.ink,
      appBar: AppBar(backgroundColor: AppColors.ink, title: Text(widget.title)),
      body: ValueListenableBuilder<Offset>(
        valueListenable: Tilt.instance.value,
        builder: (_, t, child) => Container(
          decoration: BoxDecoration(
            gradient: RadialGradient(
              center: Alignment(t.dx * -0.35, -0.1 + t.dy * 0.35),
              radius: 1.0,
              colors: const [Color(0xFF1B1B22), Color(0xFF050507)],
            ),
          ),
          child: child,
        ),
        child: Ring360(
          count: items.length,
          aspect: 0.9,
          gap: 2.3,
          scale: 2.2,
          itemBuilder: (_, i) => MenuIconCard(kind: items[i].kind, label: items[i].label),
          frontAwareBuilder: (_, i, isFront) =>
              MenuIconCard(kind: items[i].kind, label: items[i].label, model: items[i].model, front: isFront),
          onFront: (i) => items[i].onTap(),
          caption: (i) => (items[i].label, items[i].sub),
        ),
      ),
    );
  }
}
