import 'dart:io';

import 'package:flutter/widgets.dart';

import 'app.dart';
import 'bootstrap.dart';
import 'runtime/office_runtime.dart';
import 'state/office_ticker.dart';
import 'widgets/startup_error_screen.dart';

/// Entry point of the Agent Office window.
///
/// Loads `settings.json` from the app support folder (defaults with the
/// current folder as `cwd` when that fails), starts the office runtime,
/// binds the animation clock to the window lifecycle and shows the office.
/// `--fake` (or `AGENT_OFFICE_FAKE=1`) replays canned vendor output so the
/// window can be demoed without `claude` or `codex` installed. When the
/// runtime cannot start, the window explains why instead of crashing.
Future<void> main(List<String> args) async {
  WidgetsFlutterBinding.ensureInitialized();
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
