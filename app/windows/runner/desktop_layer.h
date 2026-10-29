#ifndef RUNNER_DESKTOP_LAYER_H_
#define RUNNER_DESKTOP_LAYER_H_

#include <windows.h>

#include <vector>

// Keeps the Flutter window on the desktop, behind the icons, the way
// Wallpaper Engine and Lively do: the window is re-parented under the WorkerW
// that Progman spawns behind SHELLDLL_DefView (the icon list view).
//
// A window down there never receives mouse input, because the icon list view
// covers the whole screen. So a timer watches the cursor: while it is inside
// one of the hit rects Dart reported (the character, an open bubble) and the
// desktop is what lies under it, the window is raised to a topmost top-level
// window and gets real hover and click events; it goes back behind the icons
// when the cursor leaves, unless Dart pinned it in front (a bubble is open).
// While raised, the window is click-through (WS_EX_TRANSPARENT) outside the
// hit rects, so desktop icons and the taskbar stay usable.
//
// Transparency is a colour key: DWM per-pixel alpha does not apply to a child
// of WorkerW, so Dart paints DesktopStage.keyColor wherever the desktop should
// show and the layered window makes exactly that colour see-through.
class DesktopLayer {
 public:
  explicit DesktopLayer(HWND window);

  // Timer id of the cursor watch (WM_TIMER wparam).
  static constexpr UINT_PTR kTimerId = 0x4F46;

  // Makes |window| a layered window whose key colour is see-through.
  static void MakeTransparent(HWND window);

  // Finds (spawning it when needed) the WorkerW behind the desktop icons, or
  // nullptr when the shell does not provide one.
  static HWND FindWorkerW();

  // Re-parents the window under WorkerW and starts the cursor watch. Returns
  // false when no WorkerW was found; the window then stays a topmost overlay
  // and the watch still handles click-through.
  bool Enter();

  // Keeps the window in front, activated, until |Release| (a bubble is open).
  void Pin();
  void Release();

  // Window-relative physical-pixel rectangles where the window takes mouse
  // input. For the full-screen layer these are screen pixels.
  void SetHitRects(std::vector<RECT> rects);

  // Whether a screen point lies inside one of the hit rects.
  bool Contains(POINT screen_point) const;

  // Whether |Enter| has been called.
  bool entered() const { return entered_; }

  // One step of the cursor watch (on WM_TIMER). Returns true when the window
  // lost the foreground while pinned, so Dart can close its bubble.
  bool Poll();

 private:
  void Raise(bool activate);
  void Lower();
  void SetClickThrough(bool on);

  HWND window_;
  HWND workerw_ = nullptr;
  bool entered_ = false;
  bool raised_ = true;
  bool pinned_ = false;
  bool click_through_ = false;
  std::vector<RECT> rects_;
};

#endif  // RUNNER_DESKTOP_LAYER_H_
