import 'package:flutter/material.dart';

import '../data/cover_lookup.dart';
import '../models/vinyl.dart';
import 'cover_art.dart';

/// Portada que, si el disco no la tiene guardada, la busca en internet (una vez, con memoria)
/// para verse igual que en las bibliotecas. La usan Hojear y la línea de tiempo.
class LookupCover extends StatefulWidget {
  const LookupCover({super.key, required this.vinyl, this.radius = 6});
  final Vinyl vinyl;
  final double radius;
  static final Map<String, String> found = {};
  static final Set<String> _tried = {};

  @override
  State<LookupCover> createState() => _LookupCoverState();
}

class _LookupCoverState extends State<LookupCover> {
  @override
  void initState() {
    super.initState();
    _find();
  }

  Future<void> _find() async {
    final v = widget.vinyl;
    if (v.coverUrl != null || v.isDivider || !LookupCover._tried.add(v.id)) return;
    try {
      final hit = await CoverLookup.find(artist: v.artist, albums: [v.title], tracks: v.tracks, trackFirst: v.single);
      if (hit != null) {
        LookupCover.found[v.id] = hit.url;
        if (mounted) setState(() {});
      }
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    final v = widget.vinyl;
    final u = v.coverUrl == null ? LookupCover.found[v.id] : null;
    return CoverArt(vinyl: u == null ? v : v.copyWith(coverUrl: u), radius: widget.radius);
  }
}
