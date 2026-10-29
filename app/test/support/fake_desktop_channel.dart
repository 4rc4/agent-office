import 'package:agent_office_app/desktop/desktop_layer.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

/// Stands in for the Windows runner on the `agent_office/desktop` channel:
/// records every call and answers like a runner that found WorkerW.
class FakeDesktopChannel {
  FakeDesktopChannel() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(DesktopLayer.defaultChannel, _handle);
  }

  final List<MethodCall> calls = [];

  /// Method names in call order.
  List<String> get methods => [for (final c in calls) c.method];

  /// Flat l,t,r,b lists of every `setHitRects` call, in order.
  List<List<double>> get hitRectCalls => [
    for (final c in calls)
      if (c.method == 'setHitRects') (c.arguments as List<double>).toList(),
  ];

  Future<Object?> _handle(MethodCall call) async {
    calls.add(call);
    return switch (call.method) {
      'enterWallpaperMode' => true,
      'screenSize' => <Object?>[1920, 1080],
      _ => null,
    };
  }

  /// Delivers a runner-to-Dart call, e.g. `focusLost`.
  Future<void> callDart(String method) async {
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    await messenger.handlePlatformMessage(
      DesktopLayer.channelName,
      const StandardMethodCodec().encodeMethodCall(MethodCall(method)),
      (_) {},
    );
  }

  void dispose() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(DesktopLayer.defaultChannel, null);
  }
}
