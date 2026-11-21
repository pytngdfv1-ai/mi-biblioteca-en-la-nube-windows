import 'data/objects3d.dart';
import 'data/auto_backup.dart';
import 'screens/splash_screen.dart';
import 'data/equalizer.dart';
import 'package:flutter/material.dart';
import 'package:just_audio_media_kit/just_audio_media_kit.dart';
import 'package:window_manager/window_manager.dart';

import 'audio/app_audio.dart';
import 'audio/dj_session.dart';
import 'audio/player_service.dart';
import 'data/booklet_lite.dart';
import 'data/cajon.dart';
import 'data/discogs.dart';
import 'data/koofr_settings.dart';
import 'data/library_settings.dart';
import 'data/library_sync.dart';
import 'data/playlists.dart';
import 'data/tilt.dart';
import 'data/ui_settings.dart';
import 'data/vinyl_store.dart';
import 'platform/audio_hook.dart';
import 'platform/desktop_shell.dart';
import 'platform/updater.dart';
import 'theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Audio en Windows (just_audio no trae soporte nativo): libmpv vía media_kit.
  JustAudioMediaKit.ensureInitialized(windows: true, linux: false);
  installAudioHook(); // ecualizador: engancha el filtro de mpv a cada reproductor
  await windowManager.ensureInitialized();
  await windowManager.waitUntilReadyToShow(
    const WindowOptions(
      size: Size(1180, 800),
      minimumSize: Size(560, 640),
      center: true,
      title: 'Mi Biblioteca',
      backgroundColor: Color(0xFF0E0E0D),
    ),
    () async {
      await windowManager.show();
      await windowManager.focus();
    },
  );
  final store = VinylStore();
  await store.load();
  await LibrarySettings.load();
  await ChestNames.load();
  await UiSettings.load();
  await Eq.load();
  await Discogs.load();
  await BookletLite.load();
  await KoofrAccounts.load();
  await Objects3D.load();
  await AutoBackup.init(store);
  await Playlists.instance.load();
  try {
    await AppAudio.init();
  } catch (_) {}
  PlayerService.beforeStart = DjSession.stop;
  // Sincroniza las nubes al abrir (en segundo plano); el inicio espera a que termine.
  final sync = LibrarySync.syncAll(store);
  runApp(VinylApp(store: store, ready: sync));
  sync.whenComplete(() => Objects3D.sync(store.items));
  // Busca actualizaciones en segundo plano.
  initUpdater();
}

class VinylApp extends StatelessWidget {
  const VinylApp({super.key, required this.store, required this.ready});

  final VinylStore store;
  final Future<void> ready;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Mi Biblioteca',
      debugShowCheckedModeBanner: false,
      navigatorKey: navigatorKey,
      scrollBehavior: const DesktopScrollBehavior(),
      theme: buildAppTheme(),
      builder: (context, child) => Listener(
        // La luz del brillo sigue al ratón (en Android usa el acelerómetro).
        onPointerHover: (e) => Tilt.instance.pointer(e.position, MediaQuery.sizeOf(context)),
        child: DesktopShortcuts(child: child ?? const SizedBox.shrink()),
      ),
      home: SplashScreen(store: store, ready: ready),
    );
  }
}
