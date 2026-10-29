#include "desktop_wallpaper.h"

#include <shobjidl.h>

namespace {

// The device path of the monitor at the screen origin, or nullptr. The caller
// frees the string with CoTaskMemFree.
LPWSTR PrimaryMonitorId(IDesktopWallpaper* wallpaper) {
  UINT count = 0;
  if (FAILED(wallpaper->GetMonitorDevicePathCount(&count))) {
    return nullptr;
  }
  for (UINT i = 0; i < count; ++i) {
    LPWSTR id = nullptr;
    if (FAILED(wallpaper->GetMonitorDevicePathAt(i, &id)) || id == nullptr) {
      continue;
    }
    RECT rect = {};
    if (SUCCEEDED(wallpaper->GetMonitorRECT(id, &rect)) && rect.left == 0 &&
        rect.top == 0) {
      return id;
    }
    CoTaskMemFree(id);
  }
  return nullptr;
}

}  // namespace

WallpaperInfo QueryWallpaper() {
  WallpaperInfo info;
  info.monitor = {0, 0, GetSystemMetrics(SM_CXSCREEN),
                  GetSystemMetrics(SM_CYSCREEN)};
  const int virtual_x = GetSystemMetrics(SM_XVIRTUALSCREEN);
  const int virtual_y = GetSystemMetrics(SM_YVIRTUALSCREEN);
  info.virtual_screen = {virtual_x, virtual_y,
                         virtual_x + GetSystemMetrics(SM_CXVIRTUALSCREEN),
                         virtual_y + GetSystemMetrics(SM_CYVIRTUALSCREEN)};

  IDesktopWallpaper* wallpaper = nullptr;
  if (FAILED(CoCreateInstance(__uuidof(DesktopWallpaper), nullptr, CLSCTX_ALL,
                              IID_PPV_ARGS(&wallpaper))) ||
      wallpaper == nullptr) {
    return info;
  }
  LPWSTR monitor_id = PrimaryMonitorId(wallpaper);
  LPWSTR path = nullptr;
  if (SUCCEEDED(wallpaper->GetWallpaper(monitor_id, &path)) &&
      path != nullptr) {
    info.path = path;
    CoTaskMemFree(path);
  }
  if (monitor_id != nullptr) {
    CoTaskMemFree(monitor_id);
  }
  DESKTOP_WALLPAPER_POSITION position = DWPOS_FILL;
  if (SUCCEEDED(wallpaper->GetPosition(&position))) {
    info.position = static_cast<int>(position);
  }
  COLORREF color = RGB(0, 0, 0);
  if (SUCCEEDED(wallpaper->GetBackgroundColor(&color))) {
    info.color = color;
  }
  wallpaper->Release();
  return info;
}
