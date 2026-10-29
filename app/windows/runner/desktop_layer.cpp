#include "desktop_layer.h"

#include <cwchar>
#include <utility>

namespace {

// Progman spawns a WorkerW behind the desktop icons on this message.
constexpr UINT kSpawnWorkerW = 0x052C;

// Cursor watch period in milliseconds.
constexpr UINT kPollMs = 40;

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

bool SameRects(const std::vector<RECT>& a, const std::vector<RECT>& b) {
  if (a.size() != b.size()) {
    return false;
  }
  for (size_t i = 0; i < a.size(); ++i) {
    if (!EqualRect(&a[i], &b[i])) {
      return false;
    }
  }
  return true;
}

// The cursor in window coordinates, or nullopt-like failure as false.
bool CursorInWindow(HWND window, POINT* local) {
  POINT cursor = {};
  RECT bounds = {};
  if (!GetCursorPos(&cursor) || !GetWindowRect(window, &bounds)) {
    return false;
  }
  local->x = cursor.x - bounds.left;
  local->y = cursor.y - bounds.top;
  return true;
}

}  // namespace

DesktopLayer::DesktopLayer(HWND window) : window_(window) {}

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
    ApplyRegion();
    SetForegroundWindow(window_);
  } else {
    Raise(true);
  }
}

void DesktopLayer::Release() {
  pinned_ = false;
  if (raised_) {
    ApplyRegion();
  }
}

void DesktopLayer::Peek(UINT ms) {
  peeking_ = true;
  if (raised_) {
    ApplyRegion();
  } else {
    Raise(false);
  }
  SetTimer(window_, kPeekTimerId, ms, nullptr);
}

void DesktopLayer::EndPeek() {
  KillTimer(window_, kPeekTimerId);
  if (!peeking_) {
    return;
  }
  peeking_ = false;
  Poll();
}

void DesktopLayer::SetHitRects(std::vector<RECT> rects) {
  rects_ = std::move(rects);
  if (raised_) {
    ApplyRegion();
  }
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
    if (!pinned_ && !peeking_ && !inside && workerw_ != nullptr) {
      Lower();
    } else {
      ApplyRegion();
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
  ApplyRegion();
  if (activate) {
    SetForegroundWindow(window_);
  }
}

void DesktopLayer::Lower() {
  raised_ = false;
  if (has_region_) {
    // Behind the icons the whole backdrop must show again.
    SetWindowRgn(window_, nullptr, FALSE);
    has_region_ = false;
    region_rects_.clear();
  }
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

void DesktopLayer::ApplyRegion() {
  POINT local = {};
  const bool have_cursor = CursorInWindow(window_, &local);
  std::vector<RECT> visible;
  for (const RECT& rect : rects_) {
    if (pinned_ || peeking_ || (have_cursor && PtInRect(&rect, local))) {
      visible.push_back(rect);
    }
  }
  if (has_region_ && SameRects(visible, region_rects_)) {
    return;
  }
  HRGN region = CreateRectRgn(0, 0, 0, 0);
  for (const RECT& rect : visible) {
    HRGN part = CreateRectRgnIndirect(&rect);
    CombineRgn(region, region, part, RGN_OR);
    DeleteObject(part);
  }
  // The system owns |region| from here on.
  SetWindowRgn(window_, region, TRUE);
  region_rects_ = std::move(visible);
  has_region_ = true;
}
