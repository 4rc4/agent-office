import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:tray_manager/tray_manager.dart';

import '../l10n_tr.dart';

/// The tray icon and its menu: "Duraklat"/"Devam", "Ayarlar" and "Çıkış".
///
/// The layer has no window chrome, so this is how the user reaches the
/// office when no character is in sight. Left or right click pops the menu.
/// Without a tray plugin (tests, Linux) [install] is a no-op.
class OfficeTray with TrayListener {
  OfficeTray({
    required this.onTogglePause,
    required this.onSettings,
    required this.onQuit,
    TrayManager? manager,
  }) : _tray = manager ?? trayManager;

  /// The icon asset (`tool/make_icon.py`); tray_manager resolves it under
  /// `data/flutter_assets` next to the executable.
  static const String iconAsset = 'assets/icons/tray_icon.ico';

  static const String pauseKey = 'pause';
  static const String settingsKey = 'settings';
  static const String quitKey = 'quit';

  final VoidCallback onTogglePause;
  final VoidCallback onSettings;
  final VoidCallback onQuit;
  final TrayManager _tray;
  bool _paused = false;
  bool _installed = false;

  bool get isInstalled => _installed;

  /// Shows the icon with the menu for [paused].
  Future<void> install({bool paused = false}) async {
    _paused = paused;
    try {
      await _tray.setIcon(iconAsset);
      await _tray.setToolTip(Tr.appTitle);
      await _tray.setContextMenu(_menu());
    } on MissingPluginException {
      return;
    } on PlatformException catch (error) {
      debugPrint('tray: ${error.message}');
      return;
    }
    _tray.addListener(this);
    _installed = true;
  }

  /// Flips the first item between "Duraklat" and "Devam".
  Future<void> setPaused(bool paused) async {
    if (!_installed || paused == _paused) return;
    _paused = paused;
    await _tray.setContextMenu(_menu());
  }

  /// Removes the icon.
  Future<void> dispose() async {
    if (!_installed) return;
    _installed = false;
    _tray.removeListener(this);
    try {
      await _tray.destroy();
    } on PlatformException {
      // Already gone.
    }
  }

  Menu _menu() => Menu(
    items: [
      MenuItem(key: pauseKey, label: _paused ? Tr.resume : Tr.pause),
      MenuItem(key: settingsKey, label: Tr.settings),
      MenuItem.separator(),
      MenuItem(key: quitKey, label: Tr.quit),
    ],
  );

  @override
  void onTrayIconMouseDown() => unawaited(_tray.popUpContextMenu());

  @override
  void onTrayIconRightMouseDown() => unawaited(_tray.popUpContextMenu());

  @override
  void onTrayMenuItemClick(MenuItem menuItem) {
    switch (menuItem.key) {
      case pauseKey:
        onTogglePause();
      case settingsKey:
        onSettings();
      case quitKey:
        onQuit();
    }
  }
}
