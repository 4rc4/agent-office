import 'dart:async';
import 'dart:io';

import 'package:flutter/widgets.dart';

import 'bootstrap.dart';
import 'desktop/autostart.dart';
import 'desktop/desktop_app.dart';
import 'desktop/desktop_layer.dart';
import 'desktop/desktop_stage.dart';
import 'desktop/tray.dart';
import 'desktop/wallpaper.dart';
import 'runtime/office_runtime.dart';
import 'runtime/office_settings.dart';
import 'widgets/startup_error_screen.dart';

/// Entry point.
///
/// The live office on the wallpaper layer, a full-screen window the runner
/// parks behind the desktop icons once the first frame is up
/// (`DesktopLayer.enterWallpaperMode`); it paints a copy of the desktop
/// wallpaper, loaded here so the first frame already shows it. The office
/// runtime starts from
/// `settings.json` (`--fake` replays canned vendor output) and resumes
/// interrupted work; station positions, recent folders and the settings
/// sheet are saved back there. A tray icon pauses the office, opens the
/// settings and quits; quitting stops the agents first. `--window` shows
/// the same stage in a plain dark window.
Future<void> main(List<String> args) async {
  WidgetsFlutterBinding.ensureInitialized();
  final windowed = args.contains(Bootstrap.windowFlag);
  final stored = await Bootstrap.loadSettingsOrDefaults();
  final settings = Bootstrap.applyFakeMode(
    stored,
    fake: Bootstrap.wantsFakeMode(args, Platform.environment),
  );
  final OfficeRuntime runtime;
  try {
    runtime = await OfficeRuntime.start(settings);
  } on Object catch (error) {
    runApp(StartupErrorScreen(settings: settings, error: error));
    return;
  }
  final controller = runtime.controller;
  final layer = DesktopLayer();
  final wallpaper = windowed
      ? null
      : await DesktopWallpaper.load(query: layer.wallpaper);
  final commands = DesktopCommands();
  final tray = OfficeTray(
    onTogglePause: () => unawaited(controller.setPaused(!controller.paused)),
    onSettings: commands.openSettings,
    onQuit: () => unawaited(layer.quit()),
  );
  Future<void> shutDown() async {
    await tray.dispose();
    await controller.stopAll();
    await runtime.close();
  }

  WidgetsBinding.instance.addObserver(
    OfficeLifecycleObserver(closeRuntime: shutDown),
  );
  runApp(
    DesktopApp(
      model: controller,
      layer: layer,
      settings: stored,
      onSettingsChanged: (next) => unawaited(_save(next)),
      commands: commands,
      autostart: SystemAutostart(),
      wallpaper: wallpaper,
      windowed: windowed,
    ),
  );
  unawaited(tray.install(paused: controller.paused));
  controller.addListener(
    () => unawaited(tray.setPaused(controller.snapshot.paused)),
  );
  if (windowed) return;
  WidgetsBinding.instance.addPostFrameCallback((_) async {
    final behind = await layer.enterWallpaperMode();
    debugPrint(
      behind
          ? 'desktop layer: behind the desktop icons'
          : 'desktop layer: no WorkerW, staying a topmost overlay',
    );
  });
}

Future<void> _save(OfficeSettings settings) async {
  try {
    await settings.save();
  } on Object catch (error) {
    debugPrint('settings: save failed: $error');
  }
}
