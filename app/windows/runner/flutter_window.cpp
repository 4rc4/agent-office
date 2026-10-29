#include "flutter_window.h"

#include <flutter/standard_method_codec.h>

#include <optional>
#include <string>
#include <utility>
#include <vector>

#include "desktop_wallpaper.h"
#include "flutter/generated_plugin_registrant.h"
#include "utils.h"

namespace {

constexpr char kDesktopChannel[] = "agent_office/desktop";

flutter::EncodableValue RectValue(const RECT& rect) {
  return flutter::EncodableValue(flutter::EncodableList{
      flutter::EncodableValue(static_cast<int32_t>(rect.left)),
      flutter::EncodableValue(static_cast<int32_t>(rect.top)),
      flutter::EncodableValue(static_cast<int32_t>(rect.right)),
      flutter::EncodableValue(static_cast<int32_t>(rect.bottom))});
}

}  // namespace

FlutterWindow::FlutterWindow(const flutter::DartProject& project)
    : project_(project) {}

FlutterWindow::~FlutterWindow() {}

bool FlutterWindow::OnCreate() {
  if (!Win32Window::OnCreate()) {
    return false;
  }

  RECT frame = GetClientArea();

  // The size here must match the window dimensions to avoid unnecessary surface
  // creation / destruction in the startup path.
  flutter_controller_ = std::make_unique<flutter::FlutterViewController>(
      frame.right - frame.left, frame.bottom - frame.top, project_);
  // Ensure that basic setup of the controller was successful.
  if (!flutter_controller_->engine() || !flutter_controller_->view()) {
    return false;
  }
  RegisterPlugins(flutter_controller_->engine());
  SetChildContent(flutter_controller_->view()->GetNativeWindow());

  desktop_channel_ =
      std::make_unique<flutter::MethodChannel<flutter::EncodableValue>>(
          flutter_controller_->engine()->messenger(), kDesktopChannel,
          &flutter::StandardMethodCodec::GetInstance());
  desktop_channel_->SetMethodCallHandler(
      [this](const flutter::MethodCall<flutter::EncodableValue>& call,
             std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>>
                 result) { HandleDesktopCall(call, std::move(result)); });
  if (IsLayer()) {
    desktop_layer_ = std::make_unique<DesktopLayer>(GetHandle());
  }

  flutter_controller_->engine()->SetNextFrameCallback([&]() {
    this->Show();
  });

  // Flutter can complete the first frame before the "show window" callback is
  // registered. The following call ensures a frame is pending to ensure the
  // window is shown. It is a no-op if the first frame hasn't completed yet.
  flutter_controller_->ForceRedraw();

  return true;
}

void FlutterWindow::OnDestroy() {
  if (desktop_channel_) {
    desktop_channel_->SetMethodCallHandler(nullptr);
    desktop_channel_ = nullptr;
  }
  desktop_layer_ = nullptr;
  if (flutter_controller_) {
    flutter_controller_ = nullptr;
  }

  Win32Window::OnDestroy();
}

void FlutterWindow::HandleDesktopCall(
    const flutter::MethodCall<flutter::EncodableValue>& call,
    std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result) {
  const std::string& method = call.method_name();
  if (method == "screenSize") {
    result->Success(flutter::EncodableValue(flutter::EncodableList{
        flutter::EncodableValue(GetSystemMetrics(SM_CXSCREEN)),
        flutter::EncodableValue(GetSystemMetrics(SM_CYSCREEN))}));
    return;
  }
  if (method == "wallpaper") {
    const WallpaperInfo info = QueryWallpaper();
    result->Success(flutter::EncodableValue(flutter::EncodableMap{
        {flutter::EncodableValue("path"),
         flutter::EncodableValue(Utf8FromUtf16(info.path.c_str()))},
        {flutter::EncodableValue("position"),
         flutter::EncodableValue(info.position)},
        {flutter::EncodableValue("color"),
         flutter::EncodableValue(static_cast<int32_t>(info.color))},
        {flutter::EncodableValue("monitor"), RectValue(info.monitor)},
        {flutter::EncodableValue("virtualScreen"),
         RectValue(info.virtual_screen)},
    }));
    return;
  }
  if (method == "quit") {
    // Same path as the close button: Flutter's lifecycle handling, then
    // WM_DESTROY ends the message loop.
    PostMessage(GetHandle(), WM_CLOSE, 0, 0);
    result->Success();
    return;
  }
  if (!desktop_layer_) {
    // Plain window: nothing to park or raise.
    result->Success(flutter::EncodableValue(false));
    return;
  }
  if (method == "enterWallpaperMode") {
    result->Success(flutter::EncodableValue(desktop_layer_->Enter()));
  } else if (method == "bringToFront") {
    desktop_layer_->Pin();
    result->Success();
  } else if (method == "sendToBack") {
    desktop_layer_->Release();
    result->Success();
  } else if (method == "peek") {
    const auto* ms = std::get_if<int32_t>(call.arguments());
    desktop_layer_->Peek(ms == nullptr || *ms <= 0 ? 15000 : static_cast<UINT>(*ms));
    result->Success();
  } else if (method == "setHitRects") {
    const auto* flat = std::get_if<std::vector<double>>(call.arguments());
    if (flat == nullptr) {
      result->Error("bad_args", "setHitRects wants a Float64List of l,t,r,b");
      return;
    }
    std::vector<RECT> rects;
    for (size_t i = 0; i + 3 < flat->size(); i += 4) {
      RECT rect = {static_cast<LONG>((*flat)[i]),
                   static_cast<LONG>((*flat)[i + 1]),
                   static_cast<LONG>((*flat)[i + 2]),
                   static_cast<LONG>((*flat)[i + 3])};
      rects.push_back(rect);
    }
    desktop_layer_->SetHitRects(std::move(rects));
    result->Success();
  } else {
    result->NotImplemented();
  }
}

LRESULT
FlutterWindow::MessageHandler(HWND hwnd, UINT const message,
                              WPARAM const wparam,
                              LPARAM const lparam) noexcept {
  // Give Flutter, including plugins, an opportunity to handle window messages.
  if (flutter_controller_) {
    std::optional<LRESULT> result =
        flutter_controller_->HandleTopLevelWindowProc(hwnd, message, wparam,
                                                      lparam);
    if (result) {
      return *result;
    }
  }

  switch (message) {
    case WM_FONTCHANGE:
      flutter_controller_->engine()->ReloadSystemFonts();
      break;
    case WM_TIMER:
      if (desktop_layer_ && wparam == DesktopLayer::kTimerId) {
        if (desktop_layer_->Poll() && desktop_channel_) {
          desktop_channel_->InvokeMethod("focusLost", nullptr);
        }
        return 0;
      }
      if (desktop_layer_ && wparam == DesktopLayer::kPeekTimerId) {
        desktop_layer_->EndPeek();
        return 0;
      }
      break;
    case WM_NCHITTEST:
      // Outside the hit rects the layer is not ours to click. While raised
      // the window region already clips those parts away; this covers the
      // moment before the first region is applied.
      if (desktop_layer_ && desktop_layer_->entered()) {
        const POINT point = {
            static_cast<LONG>(static_cast<SHORT>(LOWORD(lparam))),
            static_cast<LONG>(static_cast<SHORT>(HIWORD(lparam)))};
        return desktop_layer_->Contains(point) ? HTCLIENT : HTTRANSPARENT;
      }
      break;
  }

  return Win32Window::MessageHandler(hwnd, message, wparam, lparam);
}
