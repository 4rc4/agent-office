import 'dart:io';

import 'package:office_core/office_core.dart';

/// Opens a report's folder in Explorer or in VS Code. [launch] starts a
/// program detached (tests record instead); [resolve] finds `code` on PATH
/// (null when it is not there, which hides the editor button).
class OpenExternal {
  OpenExternal({
    Future<void> Function(String executable, List<String> arguments)? launch,
    String? Function(String name)? resolve,
  }) : _launch = launch ?? _detached,
       _code = (resolve ?? _onPath)('code');

  final Future<void> Function(String executable, List<String> arguments)
  _launch;
  final String? _code;

  /// Whether VS Code was found on PATH.
  bool get editorAvailable => _code != null;

  Future<void> openFolder(String path) => _launch('explorer.exe', [path]);

  Future<void> openInEditor(String path) async {
    final code = _code;
    if (code == null) return;
    await _launch(code, [path]);
  }

  static Future<void> _detached(String executable, List<String> arguments) {
    return Process.start(
      executable,
      arguments,
      mode: ProcessStartMode.detached,
    ).then<void>((_) {}, onError: (Object _) {});
  }

  /// The resolved path of [name], or null when PATH has no such program.
  static String? _onPath(String name) {
    final resolved = resolveExecutable(name);
    return resolved == name ? null : resolved;
  }
}
