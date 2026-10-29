import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:launch_at_startup/launch_at_startup.dart';

/// Whether the app starts with the user's session.
abstract class Autostart {
  const Autostart();

  Future<bool> isEnabled();

  /// Returns the state afterwards.
  Future<bool> setEnabled(bool enabled);
}

/// No registration possible (tests, unsupported hosts): always off.
class NoAutostart extends Autostart {
  const NoAutostart();

  @override
  Future<bool> isEnabled() async => false;

  @override
  Future<bool> setEnabled(bool enabled) async => false;
}

/// Registers this executable with launch_at_startup: on Windows a `Run`
/// entry under HKCU for the current executable, no arguments (the layer
/// has no window to minimise).
class SystemAutostart extends Autostart {
  SystemAutostart({String appName = 'Agent Office'}) {
    launchAtStartup.setup(
      appName: appName,
      appPath: Platform.resolvedExecutable,
    );
  }

  @override
  Future<bool> isEnabled() async {
    try {
      return await launchAtStartup.isEnabled();
    } on Object catch (error) {
      debugPrint('autostart: $error');
      return false;
    }
  }

  @override
  Future<bool> setEnabled(bool enabled) async {
    try {
      if (enabled) {
        await launchAtStartup.enable();
      } else {
        await launchAtStartup.disable();
      }
    } on Object catch (error) {
      debugPrint('autostart: $error');
    }
    return isEnabled();
  }
}
