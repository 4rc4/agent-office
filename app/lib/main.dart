import 'dart:io';

import 'package:flutter/widgets.dart';

import 'app.dart';
import 'bootstrap.dart';
import 'desktop/desktop_app.dart';
import 'desktop/desktop_layer.dart';
import 'runtime/office_runtime.dart';
import 'state/office_ticker.dart';
import 'widgets/startup_error_screen.dart';

/// Entry point.
///
/// Default: the desktop stage on the wallpaper layer, a transparent
/// full-screen window the runner parks behind the desktop icons once the
/// first frame is up (`DesktopLayer.enterWallpaperMode`). `--window` shows
/// the same stage in a plain dark window instead, `--room` opens the old
/// pixel-room window ([runRoom]). `--fake` is read by the room only until
/// the engine is wired to the stage.
Future<void> main(List<String> args) async {
  WidgetsFlutterBinding.ensureInitialized();
  if (args.contains(Bootstrap.roomFlag)) return runRoom(args);

  final windowed = args.contains(Bootstrap.windowFlag);
  final layer = DesktopLayer();
  runApp(
    DesktopApp(
      layer: layer,
      windowed: windowed,
      initialFolder: Directory.current.path,
    ),
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

/// The pixel-room window: loads `settings.json` from the app support folder
/// (defaults with the current folder as `cwd` when that fails), starts the
/// office runtime, binds the animation clock to the window lifecycle and
/// shows the office. `--fake` (or `AGENT_OFFICE_FAKE=1`) replays canned
/// vendor output so the window can be demoed without `claude` or `codex`
/// installed. When the runtime cannot start, the window explains why
/// instead of crashing.
Future<void> runRoom(List<String> args) async {
  final settings = Bootstrap.applyFakeMode(
    await Bootstrap.loadSettingsOrDefaults(),
    fake: Bootstrap.wantsFakeMode(args, Platform.environment),
  );
  final OfficeRuntime runtime;
  try {
    runtime = await OfficeRuntime.start(settings);
  } on Object catch (error) {
    runApp(StartupErrorScreen(settings: settings, error: error));
    return;
  }
  final ticker = OfficeTicker(runtime.controller);
  Future<void> shutDown() async {
    ticker.dispose();
    await runtime.close();
  }

  WidgetsBinding.instance.addObserver(
    OfficeLifecycleObserver(ticker: ticker, closeRuntime: shutDown),
  );
  runApp(AgentOfficeApp(model: runtime.controller, tick: ticker.tick));
}
