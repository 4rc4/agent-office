#include "desktop_layer.h"

#include <cwchar>
#include <utility>

namespace {

// Progman spawns a WorkerW behind the desktop icons on this message.
constexpr UINT kSpawnWorkerW = 0x052C;

// Cursor watch period in milliseconds.
constexpr UINT kPollMs = 40;

// Pixels of this colour are see-through. Must match DesktopStage.keyColor in
// lib/desktop/desktop_stage.dart (0xFF010203).
constexpr COLORREF kColorKey = RGB(1, 2, 3);

bool HasClass(HWND window, const wchar_t* class_name) {
  wchar_t name[64] = {};
  if (window == nullptr || GetClassNameW(window, name, 64) == 0) {
    return false;
  }
  return wcscmp(name, class_name) == 0;
}

// Whether |window| belongs to the desktop (icons or wallpaper) rather than
// to an application window or the taskbar.
bool IsDesktopWindow(HWND window) {
  HWND root = GetAncestor(window, GA_ROOT);
  return HasClass(root, L"Progman") || HasClass(root, L"WorkerW");
}

// EnumWindows callback for Windows 10 and early 11: the WorkerW behind the
// icons is the top-level WorkerW right after the one holding
// SHELLDLL_DefView.
BOOL CALLBACK FindWorkerWBehindIcons(HWND top, LPARAM result) {
  if (FindWindowExW(top, nullptr, L"SHELLDLL_DefView", nullptr) == nullptr) {
    return TRUE;
  }
  *reinterpret_cast<HWND*>(result) =
      FindWindowExW(nullptr, top, L"WorkerW", nullptr);
  return FALSE;
}

int ScreenWidth() { return GetSystemMetrics(SM_CXSCREEN); }

int ScreenHeight() { return GetSystemMetrics(SM_CYSCREEN); }

}  // namespace

DesktopLayer::DesktopLayer(HWND window) : window_(window) {}

// static
void DesktopLayer::MakeTransparent(HWND window) {
  LONG_PTR ex_style = GetWindowLongPtr(window, GWL_EXSTYLE);
  SetWindowLongPtr(window, GWL_EXSTYLE, ex_style | WS_EX_LAYERED);
  SetLayeredWindowAttributes(window, kColorKey, 0, LWA_COLORKEY);
}

// static
HWND DesktopLayer::FindWorkerW() {
  HWND progman = FindWindowW(L"Progman", nullptr);
  if (progman == nullptr) {
    return nullptr;
  }
  DWORD_PTR unused = 0;
  SendMessageTimeoutW(progman, kSpawnWorkerW, 0, 0, SMTO_NORMAL, 1000,
                      &unused);
  SendMessageTimeoutW(progman, kSpawnWorkerW, 0xD, 0x1, SMTO_NORMAL, 1000,
                      &unused);
  // Windows 11 24H2 and later: the WorkerW is a child of Progman.
  HWND workerw = FindWindowExW(progman, nullptr, L"WorkerW", nullptr);
  if (workerw == nullptr) {
    EnumWindows(FindWorkerWBehindIcons, reinterpret_cast<LPARAM>(&workerw));
  }
  return workerw;
}

bool DesktopLayer::Enter() {
  if (entered_) {
    return workerw_ != nullptr;
  }
  entered_ = true;
  workerw_ = FindWorkerW();
  if (workerw_ != nullptr) {
    Lower();
  } else {
    Raise(false);
  }
  SetTimer(window_, kTimerId, kPollMs, nullptr);
  return workerw_ != nullptr;
}

void DesktopLayer::Pin() {
  pinned_ = true;
  if (raised_) {
    SetClickThrough(false);
    SetForegroundWindow(window_);
  } else {
    Raise(true);
  }
}

void DesktopLayer::Release() { pinned_ = false; }

void DesktopLayer::SetHitRects(std::vector<RECT> rects) {
  rects_ = std::move(rects);
}

bool DesktopLayer::Contains(POINT screen_point) const {
  RECT bounds = {};
  if (!GetWindowRect(window_, &bounds)) {
    return false;
  }
  const POINT local = {screen_point.x - bounds.left,
                       screen_point.y - bounds.top};
  for (const RECT& rect : rects_) {
    if (PtInRect(&rect, local)) {
      return true;
    }
  }
  return false;
}

bool DesktopLayer::Poll() {
  POINT cursor = {};
  if (!GetCursorPos(&cursor)) {
    return false;
  }
  const bool inside = Contains(cursor);

  bool focus_lost = false;
  if (pinned_) {
    HWND foreground = GetForegroundWindow();
    DWORD process = 0;
    if (foreground != nullptr) {
      GetWindowThreadProcessId(foreground, &process);
      // The folder picker is ours too, so compare processes, not windows.
      focus_lost = process != GetCurrentProcessId();
    }
    if (focus_lost) {
      // Dart closes its bubble and calls sendToBack; do not wait for it.
      pinned_ = false;
    }
  }

  if (raised_) {
    if (!pinned_ && !inside && workerw_ != nullptr) {
      Lower();
    } else {
      SetClickThrough(!inside);
    }
  } else if (inside) {
    HWND under = WindowFromPoint(cursor);
    if (under != nullptr && IsDesktopWindow(under)) {
      Raise(false);
    }
  }
  return focus_lost;
}

void DesktopLayer::Raise(bool activate) {
  raised_ = true;
  SetParent(window_, nullptr);
  UINT flags = SWP_SHOWWINDOW;
  if (!activate) {
    flags |= static_cast<UINT>(SWP_NOACTIVATE);
  }
  SetWindowPos(window_, HWND_TOPMOST, 0, 0, ScreenWidth(), ScreenHeight(),
               flags);
  if (activate) {
    SetForegroundWindow(window_);
  }
}

void DesktopLayer::Lower() {
  raised_ = false;
  SetClickThrough(false);
  if (GetForegroundWindow() == window_) {
    // Hand activation to the next window before becoming a child.
    ShowWindow(window_, SW_HIDE);
  }
  SetWindowPos(window_, HWND_NOTOPMOST, 0, 0, 0, 0,
               SWP_NOMOVE | SWP_NOSIZE | SWP_NOACTIVATE);
  SetParent(window_, workerw_);
  // Child coordinates are relative to WorkerW, whose client area starts at
  // the virtual screen's origin; keep the layer on the primary monitor.
  POINT origin = {0, 0};
  MapWindowPoints(nullptr, workerw_, &origin, 1);
  SetWindowPos(window_, nullptr, origin.x, origin.y, ScreenWidth(),
               ScreenHeight(), SWP_NOZORDER | SWP_NOACTIVATE | SWP_SHOWWINDOW);
}

void DesktopLayer::SetClickThrough(bool on) {
  if (click_through_ == on) {
    return;
  }
  click_through_ = on;
  LONG_PTR ex_style = GetWindowLongPtr(window_, GWL_EXSTYLE);
  if (on) {
    ex_style |= WS_EX_TRANSPARENT;
  } else {
    ex_style &= ~static_cast<LONG_PTR>(WS_EX_TRANSPARENT);
  }
  SetWindowLongPtr(window_, GWL_EXSTYLE, ex_style);
}
