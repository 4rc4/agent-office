import 'dart:ffi';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:sqlite3/open.dart';

/// On Windows `package:sqlite3` needs `sqlite3.dll`. The Flutter app ships it
/// through `sqlite3_flutter_libs`; the plain Dart CLI looks for a copy that
/// `run_office.ps1` downloads into `<package>/.local/sqlite3.dll`, or at the
/// path in the `OFFICE_SQLITE_DLL` environment variable. Returns the path used,
/// or null when nothing was overridden (other platforms, or no DLL found).
String? configureSqliteLibrary({Map<String, String>? environment}) {
  if (!Platform.isWindows) return null;
  final env = environment ?? Platform.environment;
  final candidates = <String>[
    if ((env['OFFICE_SQLITE_DLL'] ?? '').isNotEmpty) env['OFFICE_SQLITE_DLL']!,
    p.join(Directory.current.path, '.local', 'sqlite3.dll'),
    ..._ancestorsOf(
      Platform.script.toFilePath(),
    ).map((dir) => p.join(dir, '.local', 'sqlite3.dll')),
  ];
  for (final candidate in candidates) {
    if (File(candidate).existsSync()) {
      open.overrideFor(
        OperatingSystem.windows,
        () => DynamicLibrary.open(candidate),
      );
      return candidate;
    }
  }
  return null;
}

Iterable<String> _ancestorsOf(String path) sync* {
  var dir = p.dirname(path);
  for (var i = 0; i < 6; i++) {
    yield dir;
    final parent = p.dirname(dir);
    if (parent == dir) break;
    dir = parent;
  }
}
