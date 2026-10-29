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
// one of the hit rects Dart reported (a station, a character, an open bubble)
// and the desktop is what lies under it, the window is raised to a topmost
// top-level window and gets real hover and click events; it goes back behind
// the icons when the cursor leaves, unless Dart pinned it in front (a bubble
// is open).
//
// There is no transparency down there: a child of WorkerW is composed opaque
// (DWM per-pixel alpha does not apply, and a layered colour key swallows
// Flutter's DirectX output altogether), so Dart paints a copy of the desktop
// wallpaper as its backdrop (see desktop_wallpaper.h). While raised, the
// window is clipped with SetWindowRgn to the hit rects under the cursor (all
// of them while pinned): the rest of the screen stays whatever it was, and
// clicks there reach the icons, the taskbar and other windows as usual.
class DesktopLayer {
 public:
  explicit DesktopLayer(HWND window);

  // Timer id of the cursor watch (WM_TIMER wparam).
  static constexpr UINT_PTR kTimerId = 0x4F46;

  // Timer id that ends a |Peek| (WM_TIMER wparam).
  static constexpr UINT_PTR kPeekTimerId = 0x4F47;

  // Finds (spawning it when needed) the WorkerW behind the desktop icons, or
  // nullptr when the shell does not provide one.
  static HWND FindWorkerW();

  // Re-parents the window under WorkerW and starts the cursor watch. Returns
  // false when no WorkerW was found; the window then stays a topmost overlay
  // clipped to the hit rects.
  bool Enter();

  // Keeps the window in front, activated and showing every hit rect, until
  // |Release| (a bubble is open).
  void Pin();
  void Release();

  // Shows every hit rect over other windows for |ms| without activating
  // the window (a report notice); |EndPeek| runs on the timer and lowers
  // the window again unless it is pinned or hovered.
  void Peek(UINT ms);
  void EndPeek();

  // Window-relative physical-pixel rectangles where the window takes mouse
  // input and, while raised, is visible at all. For the full-screen layer
  // these are screen pixels.
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

  // Clips the raised window to the hit rects under the cursor, or to all of
  // them while pinned. No-op when the set did not change.
  void ApplyRegion();

  HWND window_;
  HWND workerw_ = nullptr;
  bool entered_ = false;
  bool raised_ = true;
  bool pinned_ = false;
  bool peeking_ = false;
  std::vector<RECT> rects_;

  // The rects the current window region was built from.
  std::vector<RECT> region_rects_;
  bool has_region_ = false;
};

#endif  // RUNNER_DESKTOP_LAYER_H_
