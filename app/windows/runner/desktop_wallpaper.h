#ifndef RUNNER_DESKTOP_WALLPAPER_H_
#define RUNNER_DESKTOP_WALLPAPER_H_

#include <windows.h>

#include <string>

// What the shell paints behind the desktop icons on the primary monitor, read
// through IDesktopWallpaper. The desktop layer draws a copy of it as its own
// backdrop: a window parked under WorkerW is composed opaque (neither DWM
// alpha nor a layered colour key reaches Flutter's DirectX output there), so
// the only way to look transparent is to paint what the desktop would show.
struct WallpaperInfo {
  // Image file; empty when the desktop is a solid colour.
  std::wstring path;

  // DESKTOP_WALLPAPER_POSITION: 0 center, 1 tile, 2 stretch, 3 fit, 4 fill,
  // 5 span.
  int position = 4;

  // Shown where the image does not reach (fit, center) or instead of it.
  COLORREF color = RGB(0, 0, 0);

  // The primary monitor and the virtual screen, in screen pixels; "span"
  // stretches the image over the latter.
  RECT monitor = {};
  RECT virtual_screen = {};
};

// Reads the current wallpaper of the primary monitor. COM must be initialised
// on the calling thread (main.cpp does). Falls back to a black solid colour
// when the shell interface is unavailable.
WallpaperInfo QueryWallpaper();

#endif  // RUNNER_DESKTOP_WALLPAPER_H_
