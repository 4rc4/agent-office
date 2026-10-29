import 'package:path/path.dart' as p;

/// The last segment of a folder path, whichever separator it uses: the
/// stage runs on Windows but its tests on Linux, and settings may hold
/// either style.
String folderName(String path) {
  final context = path.contains('\\') ? p.windows : p.context;
  final name = context.basename(path);
  return name.isEmpty ? path : name;
}
