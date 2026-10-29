import 'dart:io';

import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;

/// Loads Roboto and the Material icon font from the Flutter SDK's cache so
/// goldens show real glyphs instead of the test font's boxes.
///
/// Best effort: when the cache is not where the running test shell implies,
/// nothing is loaded and text renders in Ahem (the goldens then differ).
/// Returns whether any font was loaded.
Future<bool> loadSdkFonts() async {
  final dir = sdkMaterialFontsDir();
  if (dir == null) return false;
  final roboto = await _load('Roboto', dir, const [
    'Roboto-Regular.ttf',
    'Roboto-Medium.ttf',
    'Roboto-Bold.ttf',
  ]);
  final icons = await _load('MaterialIcons', dir, const [
    'MaterialIcons-Regular.otf',
  ]);
  return roboto || icons;
}

/// Loads the bundled pixel face (`assets/fonts`, family `PixelFont`) from
/// the asset bundle, so pixel titles and buttons measure as in the app
/// instead of as the test font's wide boxes.
Future<void> loadPixelFont() async {
  final loader = FontLoader('PixelFont')
    ..addFont(rootBundle.load('assets/fonts/VT323-Regular.ttf'));
  await loader.load();
}

/// `bin/cache/artifacts/material_fonts` of the SDK running this test, looked
/// up from `FLUTTER_ROOT`, from the test shell path
/// (`bin/cache/artifacts/engine/<platform>/flutter_tester`) and from the Dart
/// VM path (`bin/cache/dart-sdk/bin/dart`). Null when none exists.
String? sdkMaterialFontsDir() {
  final exeDir = p.dirname(Platform.resolvedExecutable);
  final root = Platform.environment['FLUTTER_ROOT'];
  final candidates = [
    if (root != null && root.isNotEmpty)
      p.join(root, 'bin', 'cache', 'artifacts', 'material_fonts'),
    p.join(exeDir, '..', '..', 'material_fonts'),
    p.join(exeDir, '..', '..', 'artifacts', 'material_fonts'),
  ];
  for (final dir in candidates) {
    if (File(p.join(dir, 'Roboto-Regular.ttf')).existsSync()) {
      return p.normalize(dir);
    }
  }
  return null;
}

Future<bool> _load(String family, String dir, List<String> files) async {
  final loader = FontLoader(family);
  var any = false;
  for (final name in files) {
    final file = File(p.join(dir, name));
    if (!file.existsSync()) continue;
    any = true;
    loader.addFont(
      file.readAsBytes().then((bytes) => ByteData.sublistView(bytes)),
    );
  }
  if (any) await loader.load();
  return any;
}
