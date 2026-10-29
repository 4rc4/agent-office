import 'dart:ui';

import 'package:agent_office_app/desktop/wallpaper.dart';
import 'package:flutter_test/flutter_test.dart';

const _monitor = Rect.fromLTWH(0, 0, 1920, 1080);

WallpaperInfo info(
  WallpaperFit fit, {
  Rect virtualScreen = _monitor,
  String path = r'C:\wall.jpg',
}) => WallpaperInfo(
  path: path,
  fit: fit,
  backgroundColor: const Color(0xFF000000),
  monitor: _monitor,
  virtualScreen: virtualScreen,
);

void main() {
  group('WallpaperInfo.fromMap', () {
    test('decodes the runner map, COLORREF included', () {
      final decoded = WallpaperInfo.fromMap({
        'path': r'C:\pic.png',
        'position': 3,
        'color': 0x00CC8811, // 0x00BBGGRR: red 0x11, green 0x88, blue 0xCC
        'monitor': [0, 0, 1920, 1080],
        'virtualScreen': [-1920, 0, 1920, 1080],
      });
      expect(decoded.path, r'C:\pic.png');
      expect(decoded.fit, WallpaperFit.fit);
      expect(decoded.backgroundColor, const Color(0xFF1188CC));
      expect(decoded.monitor, _monitor);
      expect(decoded.virtualScreen, const Rect.fromLTRB(-1920, 0, 1920, 1080));
    });

    test('falls back to fill, black and empty rects', () {
      final decoded = WallpaperInfo.fromMap({'position': 9});
      expect(decoded.path, '');
      expect(decoded.fit, WallpaperFit.fill);
      expect(decoded.backgroundColor, const Color(0xFF000000));
      expect(decoded.monitor, Rect.zero);
    });
  });

  group('wallpaperTiles', () {
    const landscape = Size(3840, 2160);
    const portrait = Size(1000, 2000);

    test('fill scales up to cover and centres the overflow', () {
      final tiles = wallpaperTiles(portrait, info(WallpaperFit.fill));
      // 1000x2000 on 1920x1080: scale 1.92 -> 1920x3840, centred vertically.
      expect(tiles, [
        const WallpaperTile(
          Rect.fromLTWH(0, 0, 1000, 2000),
          Rect.fromLTWH(0, -1380, 1920, 3840),
        ),
      ]);
    });

    test('fit scales down to show everything and centres', () {
      final tiles = wallpaperTiles(portrait, info(WallpaperFit.fit));
      // scale 0.54 -> 540x1080, centred horizontally.
      expect(tiles.single.destination, const Rect.fromLTWH(690, 0, 540, 1080));
    });

    test('stretch ignores the aspect ratio', () {
      final tiles = wallpaperTiles(portrait, info(WallpaperFit.stretch));
      expect(tiles.single.destination, _monitor);
    });

    test('center keeps the image at 1:1', () {
      final tiles = wallpaperTiles(landscape, info(WallpaperFit.center));
      expect(
        tiles.single.destination,
        const Rect.fromLTWH(-960, -540, 3840, 2160),
      );
    });

    test('tile repeats from the top-left corner', () {
      final tiles = wallpaperTiles(
        const Size(800, 600),
        info(WallpaperFit.tile),
      );
      expect(tiles, hasLength(3 * 2));
      expect(tiles.first.destination, const Rect.fromLTWH(0, 0, 800, 600));
      expect(tiles.last.destination, const Rect.fromLTWH(1600, 600, 800, 600));
    });

    test('span covers the virtual screen and shows this monitor\'s part', () {
      // A second monitor to the left: the virtual screen is 3840x1080 and the
      // primary monitor is its right half.
      final tiles = wallpaperTiles(
        landscape,
        info(
          WallpaperFit.span,
          virtualScreen: const Rect.fromLTRB(-1920, 0, 1920, 1080),
        ),
      );
      // scale 1 -> 3840x2160 centred on the virtual screen: y from -540,
      // x from -1920 in screen space, so -1920 relative to this monitor.
      expect(
        tiles.single.destination,
        const Rect.fromLTWH(-1920, -540, 3840, 2160),
      );
    });

    test('is empty for a degenerate image', () {
      expect(wallpaperTiles(Size.zero, info(WallpaperFit.fill)), isEmpty);
    });
  });

  test(
    'DesktopWallpaper.load keeps the current copy for the same info',
    () async {
      final same = info(WallpaperFit.fill, path: '');
      final current = DesktopWallpaper(info: same);
      final next = await DesktopWallpaper.load(
        query: () async => same,
        current: current,
      );
      expect(identical(next, current), isTrue);
      final none = await DesktopWallpaper.load(query: () async => null);
      expect(none, isNull);
      final solid = await DesktopWallpaper.load(
        query: () async => info(WallpaperFit.center, path: ''),
      );
      expect(solid?.image, isNull);
      expect(solid?.info.fit, WallpaperFit.center);
    },
  );
}
