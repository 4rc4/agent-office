import 'package:agent_office_app/desktop/desktop_app.dart';
import 'package:agent_office_app/desktop/desktop_layer.dart';
import 'package:agent_office_app/desktop/open_external.dart';
import 'package:agent_office_app/runtime/office_settings.dart';
import 'package:agent_office_app/state/seat_state.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:office_core/office_core.dart';

import 'fake_office_model.dart';

/// The folder the fake model works in and the chips it remembers.
const String repoFolder = r'C:\work\repo';
const String otherFolder = r'C:\work\agent-office';

const OfficeSettings testSettings = OfficeSettings(
  cwd: repoFolder,
  recentFolders: [repoFolder, otherFolder],
);

/// Both desks busy: Claude typing on the root, GPT in a shell on a subtask;
/// four notes on the board and one unread report in the mailbox.
OfficeSnapshot workingSnapshot() {
  const tasks = [
    TaskSnapshot(
      id: 'r1',
      rootId: 'r1',
      title: 'Testleri yeşile çevir',
      status: TaskStatus.running,
      isRoot: true,
      assignee: Seat.claude,
      cwd: repoFolder,
    ),
    TaskSnapshot(
      id: 's1',
      rootId: 'r1',
      title: 'Widget testini düzelt',
      status: TaskStatus.running,
      isRoot: false,
      assignee: Seat.gpt,
      cwd: repoFolder,
    ),
    TaskSnapshot(
      id: 's2',
      rootId: 'r1',
      title: 'Analyzer uyarısı',
      status: TaskStatus.done,
      isRoot: false,
      assignee: Seat.claude,
      cwd: repoFolder,
    ),
    TaskSnapshot(
      id: 's3',
      rootId: 'r1',
      title: 'Golden güncelle',
      status: TaskStatus.queued,
      isRoot: false,
      cwd: repoFolder,
    ),
  ];
  return OfficeSnapshot(
    seats: const [
      SeatSnapshot(
        seat: Seat.claude,
        visual: SeatVisual.typing,
        currentTaskId: 'r1',
        currentTaskTitle: 'Testleri yeşile çevir',
        lastSummary: 'Testler yeşile döndü, birleştirme bekleniyor',
        tokensIn: 18240,
        tokensOut: 2310,
      ),
      SeatSnapshot(
        seat: Seat.gpt,
        visual: SeatVisual.shell,
        currentTaskId: 's1',
        currentTaskTitle: 'Widget testini düzelt',
        lastSummary: 'flutter test çalışıyor',
        tokensIn: 9120,
        tokensOut: 1480,
      ),
      SeatSnapshot(seat: Seat.gemini, visual: SeatVisual.empty),
    ],
    tasks: tasks,
    busy: true,
    lastReport: '# Rapor\n\nREADME güncellendi.',
    reports: [
      OfficeReport(
        rootId: 'r0',
        title: 'README için kurulum bölümü',
        cwd: otherFolder,
        text: '# Rapor\n\nREADME güncellendi.',
        finishedAt: DateTime(2026, 10, 29, 9, 30),
      ),
    ],
    unreadReports: 1,
    statusLine: 'GPT çalışıyor: Widget testini düzelt',
  );
}

/// Pumps the desktop app at [size] with [model] and no animation.
Future<void> pumpDesktop(
  WidgetTester tester,
  FakeOfficeModel model, {
  Size size = const Size(1280, 720),
  double dpr = 1,
  bool windowed = false,
  ValueChanged<OfficeSettings>? onSettingsChanged,
  OfficeSettings settings = testSettings,
  Future<List<String>> Function()? pickFiles,
  OpenExternal? openExternal,
}) async {
  tester.view.physicalSize = size * dpr;
  tester.view.devicePixelRatio = dpr;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    DesktopApp(
      model: model,
      layer: DesktopLayer(),
      settings: settings,
      onSettingsChanged: onSettingsChanged,
      pickFiles: pickFiles,
      openExternal: openExternal,
      windowed: windowed,
      animate: false,
    ),
  );
  // Second pump: the post-frame hit-rect report reaches the channel.
  await tester.pump();
}
