import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';

/// How Windows places the wallpaper image on a monitor
/// (`DESKTOP_WALLPAPER_POSITION`, in that order).
enum WallpaperFit { center, tile, stretch, fit, fill, span }

/// The shell's wallpaper of the primary monitor, as the runner reports it on
/// the `wallpaper` channel call (`windows/runner/desktop_wallpaper.cpp`).
///
/// The desktop layer paints a copy of it as its backdrop: a window behind
/// the desktop icons is composed opaque, so looking transparent means
/// drawing what the desktop would show. Rectangles are physical screen
/// pixels.
@immutable
class WallpaperInfo {
  const WallpaperInfo({
    required this.path,
    required this.fit,
    required this.backgroundColor,
    required this.monitor,
    required this.virtualScreen,
  });

  /// Decodes the runner's map: `path`, `position` (the fit's index), `color`
  /// (a COLORREF, `0x00BBGGRR`), `monitor` and `virtualScreen` (`l,t,r,b`).
  factory WallpaperInfo.fromMap(Map<Object?, Object?> map) {
    final position =
        (map['position'] as num?)?.toInt() ?? WallpaperFit.fill.index;
    final color = (map['color'] as num?)?.toInt() ?? 0;
    return WallpaperInfo(
      path: map['path'] as String? ?? '',
      fit: position >= 0 && position < WallpaperFit.values.length
          ? WallpaperFit.values[position]
          : WallpaperFit.fill,
      backgroundColor: Color.fromARGB(
        0xFF,
        color & 0xFF,
        (color >> 8) & 0xFF,
        (color >> 16) & 0xFF,
      ),
      monitor: _rect(map['monitor']),
      virtualScreen: _rect(map['virtualScreen']),
    );
  }

  static Rect _rect(Object? value) {
    if (value is! List || value.length < 4) return Rect.zero;
    final n = [for (final v in value) (v as num?)?.toDouble() ?? 0];
    return Rect.fromLTRB(n[0], n[1], n[2], n[3]);
  }

  /// Image file; empty when the desktop is a solid colour.
  final String path;
  final WallpaperFit fit;

  /// Shown where the image does not reach, or instead of it.
  final Color backgroundColor;

  /// The primary monitor, in screen pixels.
  final Rect monitor;

  /// All monitors together; [WallpaperFit.span] stretches over it.
  final Rect virtualScreen;

  @override
  bool operator ==(Object other) =>
      other is WallpaperInfo &&
      other.path == path &&
      other.fit == fit &&
      other.backgroundColor == backgroundColor &&
      other.monitor == monitor &&
      other.virtualScreen == virtualScreen;

  @override
  int get hashCode =>
      Object.hash(path, fit, backgroundColor, monitor, virtualScreen);

  @override
  String toString() => 'WallpaperInfo($path, $fit, $backgroundColor)';
}

/// One placement of the image: [source] in image pixels, [destination] in
/// physical pixels relative to the monitor's top-left corner.
@immutable
class WallpaperTile {
  const WallpaperTile(this.source, this.destination);

  final Rect source;
  final Rect destination;

  @override
  bool operator ==(Object other) =>
      other is WallpaperTile &&
      other.source == source &&
      other.destination == destination;

  @override
  int get hashCode => Object.hash(source, destination);

  @override
  String toString() => 'WallpaperTile($source -> $destination)';
}

/// Where an image of [image] pixels goes on [info]'s monitor, the way the
/// shell places it. Empty for a degenerate image or monitor.
List<WallpaperTile> wallpaperTiles(Size image, WallpaperInfo info) {
  final monitor = info.monitor;
  if (image.isEmpty || monitor.isEmpty) return const [];
  final source = Offset.zero & image;
  final width = monitor.width;
  final height = monitor.height;
  switch (info.fit) {
    case WallpaperFit.stretch:
      return [WallpaperTile(source, Rect.fromLTWH(0, 0, width, height))];
    case WallpaperFit.center:
      return [WallpaperTile(source, _centered(image, monitor.size))];
    case WallpaperFit.fit:
      final scale = math.min(width / image.width, height / image.height);
      return [WallpaperTile(source, _centered(image * scale, monitor.size))];
    case WallpaperFit.fill:
      final scale = math.max(width / image.width, height / image.height);
      return [WallpaperTile(source, _centered(image * scale, monitor.size))];
    case WallpaperFit.span:
      final screen = info.virtualScreen.isEmpty ? monitor : info.virtualScreen;
      final scale = math.max(
        screen.width / image.width,
        screen.height / image.height,
      );
      final onScreen = _centered(
        image * scale,
        screen.size,
      ).shift(screen.topLeft - monitor.topLeft);
      return [WallpaperTile(source, onScreen)];
    case WallpaperFit.tile:
      return [
        for (var y = 0.0; y < height; y += image.height)
          for (var x = 0.0; x < width; x += image.width)
            WallpaperTile(
              source,
              Rect.fromLTWH(x, y, image.width, image.height),
            ),
      ];
  }
}

Rect _centered(Size size, Size within) => Rect.fromLTWH(
  ((within.width - size.width) / 2).floorToDouble(),
  ((within.height - size.height) / 2).floorToDouble(),
  size.width,
  size.height,
);

/// The wallpaper the stage paints: what the runner reported plus the decoded
/// image, when there is one.
class DesktopWallpaper {
  const DesktopWallpaper({required this.info, this.image});

  final WallpaperInfo info;

  /// Null for a solid-colour desktop or an unreadable file; the backdrop is
  /// then [WallpaperInfo.backgroundColor] alone.
  final ui.Image? image;

  /// Asks the runner ([query], normally `DesktopLayer.wallpaper`) for the
  /// current wallpaper and decodes its image. Returns [current] itself when
  /// the runner reports the same wallpaper, so callers can compare with
  /// `identical`; null without a runner (tests, Linux, `--window`).
  static Future<DesktopWallpaper?> load({
    required Future<WallpaperInfo?> Function() query,
    DesktopWallpaper? current,
  }) async {
    final info = await query();
    if (info == null) return null;
    if (current != null && current.info == info) return current;
    ui.Image? image;
    if (info.path.isNotEmpty) {
      try {
        image = await decodeImageFromList(await File(info.path).readAsBytes());
      } on Object catch (error) {
        debugPrint('wallpaper: ${info.path}: $error');
      }
    }
    return DesktopWallpaper(info: info, image: image);
  }
}
