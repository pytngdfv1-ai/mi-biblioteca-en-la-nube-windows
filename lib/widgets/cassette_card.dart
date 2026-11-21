import 'package:flutter/material.dart';

import '../data/cover_color.dart';
import '../models/vinyl.dart';
import 'cover_art.dart';

/// Cassette de frente: la portada completa en el centro y, arriba y abajo, relleno con el
/// color predominante de la portada. Carcasa transparente, solo con un borde fino.
class CassetteCard extends StatefulWidget {
  const CassetteCard({super.key, required this.vinyl});
  final Vinyl vinyl;

  @override
  State<CassetteCard> createState() => _CassetteCardState();
}

class _CassetteCardState extends State<CassetteCard> {
  late Future<List<Color>?> _color = CoverColor.edges(widget.vinyl.coverUrl);

  @override
  void didUpdateWidget(covariant CassetteCard old) {
    super.didUpdateWidget(old);
    if (old.vinyl.coverUrl != widget.vinyl.coverUrl) _color = CoverColor.edges(widget.vinyl.coverUrl);
  }

  @override
  Widget build(BuildContext context) {
    final v = widget.vinyl;
    final hueColor = HSLColor.fromAHSL(1, v.hue % 360, 0.5, 0.22).toColor();
    return Center(
      child: AspectRatio(
        aspectRatio: 0.63,
        child: FutureBuilder<List<Color>?>(
          future: _color,
          initialData: CoverColor.peekEdges(widget.vinyl.coverUrl),
          builder: (context, snap) {
            final topC = snap.data?[0] ?? hueColor;
            final botC = snap.data?[1] ?? hueColor;
            Widget fill(bool top, String text, {bool bold = false}) => Expanded(
                  child: Container(
                    alignment: top ? Alignment.bottomCenter : Alignment.topCenter,
                    padding: const EdgeInsets.fromLTRB(8, 6, 8, 6),
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: top ? Alignment.topCenter : Alignment.bottomCenter,
                        end: top ? Alignment.bottomCenter : Alignment.topCenter,
                        colors: [Color.lerp(top ? topC : botC, Colors.black, 0.3)!, top ? topC : botC],
                      ),
                    ),
                    child: Text(
                      text,
                      maxLines: 2,
                      textAlign: TextAlign.center,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: bold ? 13 : 10,
                        fontWeight: bold ? FontWeight.w800 : FontWeight.w600,
                        letterSpacing: bold ? 0 : 1.2,
                        shadows: const [Shadow(color: Colors.black87, blurRadius: 4)],
                      ),
                    ),
                  ),
                );
            final title = v.single && v.tracks.isNotEmpty ? v.tracks.first : v.title;
            return Container(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.white38, width: 1.5),
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(6.5),
                child: Column(
                  children: [
                    fill(true, v.artist.toUpperCase()),
                    AspectRatio(aspectRatio: 1, child: CoverArt(vinyl: v, radius: 0)),
                    fill(false, title, bold: true),
                  ],
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}
