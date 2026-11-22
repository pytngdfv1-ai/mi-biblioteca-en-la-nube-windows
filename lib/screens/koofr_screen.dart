import 'package:flutter/material.dart';

import '../data/koofr_settings.dart';
import '../data/library_sync.dart';
import '../data/vinyl_store.dart';
import 'koofr_account_screen.dart';

/// Lista de nubes (cuentas de Koofr). Todas forman una sola biblioteca.
class KoofrScreen extends StatefulWidget {
  const KoofrScreen({super.key, required this.store});

  final VinylStore store;

  @override
  State<KoofrScreen> createState() => _KoofrScreenState();
}

class _KoofrScreenState extends State<KoofrScreen> {
  Future<void> _open([KoofrSettings? a]) async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => KoofrAccountScreen(store: widget.store, account: a),
      ),
    );
    if (mounted) setState(() {});
  }

  /// Sincroniza en segundo plano: no bloquea la pantalla y se puede salir; el aviso aparece en el menú.
  void _syncAll() {
    LibrarySync.syncAll(widget.store);
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Sincronizando en segundo plano. Puedes seguir usando la app.')),
    );
  }

  @override
  Widget build(BuildContext context) {
    final accounts = KoofrAccounts.list;
    return Scaffold(
      appBar: AppBar(title: const Text('Nubes (Koofr)')),
      body: AnimatedBuilder(
        animation: widget.store,
        builder: (context, _) => ListView(
          padding: const EdgeInsets.all(20),
          children: [
            const Text(
              'Agrega las cuentas que quieras. Todas se unen en una sola biblioteca '
              'y se sincronizan al abrir la app. Ponle un género a cada nube para filtrar.\n'
              'Estructura: Música / Artista / Álbum / 01 - Pista.flac',
              style: TextStyle(color: Colors.white70),
            ),
            const SizedBox(height: 12),
            if (accounts.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 16),
                child: Text('Aún no hay cuentas.'),
              ),
            for (final a in accounts)
              Card(
                color: const Color(0xFF1B1D1B),
                child: ListTile(
                  leading: const Icon(Icons.cloud_outlined),
                  title: Text(a.genre.isEmpty ? a.name : '${a.name} · ${a.genre}'),
                  subtitle: Text(
                    '${a.email}\n'
                    '${widget.store.items.where((v) => v.source == a.id).length} álbumes',
                  ),
                  isThreeLine: true,
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => _open(a),
                ),
              ),
            const SizedBox(height: 12),
            FilledButton.icon(
              icon: const Icon(Icons.add),
              label: const Text('Agregar cuenta'),
              onPressed: () => _open(),
            ),
            if (accounts.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: ValueListenableBuilder<String?>(
                  valueListenable: LibrarySync.busy,
                  builder: (_, b, __) => OutlinedButton.icon(
                    icon: b != null
                        ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                        : const Icon(Icons.sync),
                    label: Text(b ?? 'Sincronizar todas'),
                    onPressed: b != null ? null : _syncAll,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
