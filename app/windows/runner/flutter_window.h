#ifndef RUNNER_FLUTTER_WINDOW_H_
#define RUNNER_FLUTTER_WINDOW_H_

#include <flutter/dart_project.h>
#include <flutter/encodable_value.h>
#include <flutter/flutter_view_controller.h>
#include <flutter/method_channel.h>

#include <memory>

#include "desktop_layer.h"
#include "win32_window.h"

// A window that hosts a Flutter view and answers the `agent_office/desktop`
// channel (lib/desktop/desktop_layer.dart). When created with
// Win32Window::CreateLayer it also owns the DesktopLayer that keeps the
// window behind the desktop icons.
class FlutterWindow : public Win32Window {
 public:
  // Creates a new FlutterWindow hosting a Flutter view running |project|.
  explicit FlutterWindow(const flutter::DartProject& project);
  virtual ~FlutterWindow();

 protected:
  // Win32Window:
  bool OnCreate() override;
  void OnDestroy() override;
  LRESULT MessageHandler(HWND window, UINT const message, WPARAM const wparam,
                         LPARAM const lparam) noexcept override;

 private:
  // Handles one call from Dart on the desktop channel.
  void HandleDesktopCall(
      const flutter::MethodCall<flutter::EncodableValue>& call,
      std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result);

  // The project to run.
  flutter::DartProject project_;

  // The Flutter instance hosted by this window.
  std::unique_ptr<flutter::FlutterViewController> flutter_controller_;

  // Dart <-> runner calls about the desktop layer.
  std::unique_ptr<flutter::MethodChannel<flutter::EncodableValue>>
      desktop_channel_;

  // Wallpaper-mode behaviour; null for a plain window (--window, --room).
  std::unique_ptr<DesktopLayer> desktop_layer_;
};

#endif  // RUNNER_FLUTTER_WINDOW_H_
