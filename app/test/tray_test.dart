import 'package:agent_office_app/desktop/tray.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

/// Records the calls tray_manager makes on its channel and lets the test
/// click a menu item by label, as the plugin would.
class FakeTrayChannel {
  FakeTrayChannel() {
    _messenger.setMockMethodCallHandler(channel, (call) async {
      calls.add(call);
      return null;
    });
  }

  static const MethodChannel channel = MethodChannel('tray_manager');
  final List<MethodCall> calls = [];

  TestDefaultBinaryMessenger get _messenger =>
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  List<String> get methods => [for (final c in calls) c.method];

  /// Labels of the last context menu set, separators as "-".
  List<String> get menuLabels {
    final last = calls.lastWhere((c) => c.method == 'setContextMenu');
    final menu = (last.arguments as Map)['menu'] as Map;
    return [
      for (final item in menu['items'] as List)
        (item as Map)['type'] == 'separator' ? '-' : item['label'] as String,
    ];
  }

  Future<void> click(String label) async {
    final last = calls.lastWhere((c) => c.method == 'setContextMenu');
    final menu = (last.arguments as Map)['menu'] as Map;
    final item = (menu['items'] as List).cast<Map>().firstWhere(
      (i) => i['label'] == label,
    );
    await _messenger.handlePlatformMessage(
      channel.name,
      const StandardMethodCodec().encodeMethodCall(
        MethodCall('onTrayMenuItemClick', {'id': item['id']}),
      ),
      (_) {},
    );
  }

  void dispose() => _messenger.setMockMethodCallHandler(channel, null);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('installs the icon and menu, routes clicks, flips pause', () async {
    final channel = FakeTrayChannel();
    addTearDown(channel.dispose);
    final events = <String>[];
    final tray = OfficeTray(
      onTogglePause: () => events.add('pause'),
      onSettings: () => events.add('settings'),
      onQuit: () => events.add('quit'),
    );
    await tray.install();
    expect(tray.isInstalled, isTrue);
    expect(channel.methods, ['setIcon', 'setToolTip', 'setContextMenu']);
    expect(
      (channel.calls.first.arguments as Map)['iconPath'],
      endsWith(OfficeTray.iconAsset),
    );
    expect(channel.menuLabels, ['Duraklat', 'Ayarlar', '-', 'Çıkış']);

    await channel.click('Ayarlar');
    await channel.click('Duraklat');
    await channel.click('Çıkış');
    expect(events, ['settings', 'pause', 'quit']);

    await tray.setPaused(true);
    expect(channel.menuLabels, ['Devam', 'Ayarlar', '-', 'Çıkış']);
    await tray.setPaused(true);
    expect(channel.methods.where((m) => m == 'setContextMenu'), hasLength(2));

    await tray.dispose();
    expect(channel.methods.last, 'destroy');
    expect(tray.isInstalled, isFalse);
  });

  test('without a tray plugin install is a no-op', () async {
    final tray = OfficeTray(
      onTogglePause: () {},
      onSettings: () {},
      onQuit: () {},
    );
    await tray.install();
    expect(tray.isInstalled, isFalse);
    await tray.setPaused(true);
    await tray.dispose();
  });
}
