import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'wallpaper.dart';

/// Dart side of the Windows "wallpaper layer": the borderless full-screen
/// window the runner keeps behind the desktop icons.
///
/// Every method is a call over the `agent_office/desktop` [MethodChannel]
/// handled in `windows/runner/flutter_window.cpp`. Without a handler (tests,
/// Linux, the `--window` fallback) calls are swallowed, so the stage never
/// has to care whether the layer exists. The runner calls back `focusLost`
/// when the user clicked elsewhere while the layer was in front; the stage
/// closes its bubble on [onFocusLost].
///
/// Rectangles and sizes cross the channel in physical screen pixels.
class DesktopLayer {
  DesktopLayer({MethodChannel? channel, this.onFocusLost, this.onHotkey})
    : channel = channel ?? defaultChannel {
    this.channel.setMethodCallHandler(_onRunnerCall);
  }

  /// The channel name shared with the runner.
  static const String channelName = 'agent_office/desktop';

  static const MethodChannel defaultChannel = MethodChannel(channelName);

  final MethodChannel channel;

  /// Called when the runner reports that the layer lost the foreground while
  /// it was pinned in front (a bubble was open). The stage sets it.
  VoidCallback? onFocusLost;

  /// Called when the runner's global hotkey (Ctrl+Alt+Space) fired.
  VoidCallback? onHotkey;

  /// Re-parents the window under the WorkerW behind the desktop icons and
  /// starts the runner's cursor watch. Returns true when the window is
  /// behind the icons; false when no WorkerW was found and the window stays
  /// a topmost overlay (still click-through outside the hit rects).
  Future<bool> enterWallpaperMode() async =>
      await _call<bool>('enterWallpaperMode') ?? false;

  /// Pins the layer in front as a normal topmost window so the text field
  /// can take keyboard focus. Call while a bubble is open.
  Future<void> bringToFront() => _call<void>('bringToFront');

  /// Shows the layer over other windows for [duration] without taking
  /// focus (a report notice). Only the hit rects Dart reported are visible;
  /// the runner lowers the layer again when the time is up unless a bubble
  /// pinned it or the pointer is on a rect.
  Future<void> peek(Duration duration) =>
      _call<void>('peek', duration.inMilliseconds);

  /// Lifts [bringToFront]: the runner re-parents the layer under WorkerW
  /// again once the pointer leaves the hit rects.
  Future<void> sendToBack() => _call<void>('sendToBack');

  /// Screen-pixel rectangles where the layer takes mouse input (the
  /// character, an open bubble). Everywhere else it is click-through.
  Future<void> setHitRects(List<Rect> rects) {
    final flat = Float64List(rects.length * 4);
    for (var i = 0; i < rects.length; i++) {
      final r = rects[i];
      flat[i * 4] = r.left;
      flat[i * 4 + 1] = r.top;
      flat[i * 4 + 2] = r.right;
      flat[i * 4 + 3] = r.bottom;
    }
    return _call<void>('setHitRects', flat);
  }

  /// Size of the primary monitor in physical pixels; [Size.zero] without a
  /// runner.
  Future<Size> screenSize() async {
    final list = await _call<List<Object?>>('screenSize');
    if (list == null || list.length < 2) return Size.zero;
    return Size((list[0]! as num).toDouble(), (list[1]! as num).toDouble());
  }

  /// The shell's wallpaper of the primary monitor (the stage paints a copy
  /// of it as its backdrop); null without a runner.
  Future<WallpaperInfo?> wallpaper() async {
    final map = await _call<Map<Object?, Object?>>('wallpaper');
    return map == null ? null : WallpaperInfo.fromMap(map);
  }

  /// Closes the window: the runner posts WM_CLOSE, which runs the normal
  /// exit path (lifecycle observers, then the message loop ends).
  Future<void> quit() => _call<void>('quit');

  Future<T?> _call<T>(String method, [Object? arguments]) async {
    try {
      return await channel.invokeMethod<T>(method, arguments);
    } on MissingPluginException {
      return null;
    } on PlatformException catch (e) {
      debugPrint('desktop layer: $method failed: ${e.message}');
      return null;
    }
  }

  Future<Object?> _onRunnerCall(MethodCall call) async {
    if (call.method == 'focusLost') onFocusLost?.call();
    if (call.method == 'hotkey') onHotkey?.call();
    return null;
  }
}
