# Office Upgrades Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Let the owner run the office from the desktop: model/effort and files per prompt, task bubbles with stop/steer and context %, a report notice, a TV with usage limits, permission balloons, a hotkey, and no overlapping stations.

**Architecture:** office_core grows task options, per-task stop/steer, approval round-trips and usage recording; the app's controller projects them into `OfficeSnapshot`; the desktop stage adds bubbles (task, TV, approval, notice) and the runner adds `peek` and a hotkey. Every feature lands as its own commit with tests.

**Tech Stack:** Dart 3.11 / Flutter 3.41.2, sqlite3, Win32 runner (C++17).

**Spec:** `docs/superpowers/specs/2026-10-29-office-upgrades-design.md`

## Global Constraints

- No new pub dependencies.
- User-facing strings only in `app/lib/l10n_tr.dart`.
- `dart format` on every touched Dart file; `flutter analyze` and `dart analyze` clean.
- Runner C++ compiles under `/W4 /WX`.

## Review Focus

1. Old `settings.json` without the new keys (and with `coffee` position) loads and keeps the TV where the coffee machine was → `OfficeSettings.fromJson` test.
2. Old `office.db` without the `options` column opens and gets the column → `TaskBoard` migration test.
3. A steer on a task whose session is not known yet restarts with the prompt plus the note, and does not burn an attempt → dispatcher test.
4. Two stations dragged towards each other stop at the gap in both directions → `StationLayout.dragTo` test.
5. A notice while a bubble is open must not steal the bubble (no peek while pinned) → stage test.

---

### Task 1: Task options in the board and adapters

**Files:**
- Modify: `packages/office_core/lib/src/model/task.dart` (TaskRecord.options)
- Modify: `packages/office_core/lib/src/board/schema.dart`, `task_board.dart` (column, migration, insertRoot options, subtasks copy)
- Modify: `packages/office_core/lib/src/adapters/claude_adapter.dart`, `codex_adapter.dart`, `cli/office_wiring.dart` (OfficeConfig defaults)
- Test: `packages/office_core/test/task_board_test.dart`, `claude_adapter_test.dart`, `codex_adapter_test.dart`

**Interfaces:**
- Produces: `TaskRecord.options: Map<String, String>`; `TaskBoard.insertRoot(prompt, cwd, {Map<String, String> options = const {}})`; `ClaudeAdapter({model = '', effort = ''})`, `buildArguments({..., Map<String, String> options = const {}})` emitting `--model X` / `--effort Y`; `CodexAdapter({model = '', reasoningEffort = ''})` emitting `-m X` and `-c model_reasoning_effort="Y"`; `OfficeConfig(claudeModel, claudeEffort, codexModel, codexEffort)`.

- [ ] Test: `insertRoot stores options and subtasks inherit them` (root `{model: 'opus'}` → subtask options equal).
- [ ] Test: `opening a v1 board adds the options column` (create a table without the column in memory, open, insert, read back `{}`).
- [ ] Test: Claude args contain `--model opus --effort high` when the task options say so, and nothing when empty; Codex args contain `-m gpt-5.1 -c model_reasoning_effort="low"`.
- [ ] Implement; run `dart test`; commit `Task options: model and effort per root, passed to the CLIs`.

### Task 2: Stop and steer a task

**Files:**
- Modify: `packages/office_core/lib/src/supervisor/dispatcher.dart`, `supervisor.dart`, `brain_protocol.dart`
- Test: `packages/office_core/test/supervisor_test.dart` (or new `steer_test.dart`)

**Interfaces:**
- `ResumeHint.sessionRef` becomes `String?`.
- `Dispatcher.stopTask(String id) -> Future<bool>`, `Dispatcher.steerTask(String id, String note) -> Future<bool>`.
- `Supervisor.stopTask(String id) -> Future<bool>`, `Supervisor.steerTask(String id, String note) -> Future<bool>`; `BrainProtocol.userNote(String note)`; `BrainProtocol.steerTurn(String note)`.

- [ ] Test: `stopTask fails the subtask without a retry` (FakeProcessRunner script that never exits; stop → status failed, note contains `stopped by user`, attempt 1).
- [ ] Test: `steerTask restarts with the note and the same session` (run has a session ref → the second start's `resumeRef` equals it and `initialMessage` contains the note; attempt budget unchanged).
- [ ] Test: `steerTask on a planned root reaches the next brain turn` (note appears in the results turn text).
- [ ] Implement; `dart test`; commit `Stop or steer one task from the office`.

### Task 3: Permission round-trip

**Files:**
- Modify: `claude_stream_parser.dart` (request id + input in raw), `claude_adapter.dart` (`--permission-prompt-tool stdio`, `ClaudeRun.answerControl`), `seat_adapter.dart` (`AgentRun.answerApproval` default unsupported), `dispatcher.dart`/`supervisor.dart` (record interaction, `answerApproval`).
- Test: `claude_stream_parser_test.dart`, `claude_adapter_test.dart`.

**Interfaces:** `AgentRun.answerApproval(String requestId, {required bool allow, String? message}) -> Future<void>`; `Supervisor.answerApproval(int interactionId, {required bool allow}) -> Future<bool>`; interaction payload `{request_id, tool, input, task_id}`.

- [ ] Test: parser yields `approvalRequested` with `raw['request_id']` and `raw['tool_name']`.
- [ ] Test: `answerControl` writes `{"type":"control_response","response":{"subtype":"success","request_id":"r1","response":{"behavior":"allow","updatedInput":{...}}}}` (and deny with message).
- [ ] Test: dispatcher adds a pending interaction on `approvalRequested`; `answerApproval` marks it answered and calls the run.
- [ ] Implement; commit `Permission requests travel to the office and back`.

### Task 4: Settings, model choices, prompt chips and attachments

**Files:**
- Modify: `app/lib/runtime/office_settings.dart`, `office_runtime.dart`, `desktop/settings_bubble.dart`, `desktop/prompt_bubble.dart`, `desktop/desktop_stage.dart`, `state/office_model.dart`, `state/office_controller.dart`, `l10n_tr.dart`, `test/support/fake_office_model.dart`
- Create: `app/lib/desktop/model_choices.dart`
- Test: `app/test/office_settings_test.dart` (new), `app/test/desktop_stage_test.dart`

**Interfaces:** `OfficeSettings.claudeModel/claudeEffort/codexModel/codexEffort`; `PromptOptions(model, effort)` and `OfficeModel.submit(prompt, {directSeat, cwd, PromptOptions? options})`; `PromptBubble(attachments, onPickFiles, onRemoveAttachment, options, onOptionsChanged)`; `attachmentSuffix(List<String> paths) -> String`.

- [ ] Test: settings round-trip with the four new keys and defaults for a file without them.
- [ ] Test: stage sends `prompt + attachmentSuffix` and the chosen options when the chips were changed.
- [ ] Implement; `flutter test`; commit `Model, effort and attachments per prompt`.

### Task 5: Drag without overlap, TV station, usage on the snapshot

**Files:**
- Modify: `app/lib/desktop/stations.dart`, `office_actors.dart`, `desktop_painter.dart`, `desktop_stage.dart`, `scene/furniture.dart` (paintTv), `state/seat_state.dart`, `state/office_controller.dart`, `l10n_tr.dart`
- Create: `app/lib/desktop/tv_bubble.dart`
- Test: `app/test/stations_test.dart` (new), `office_actors_test.dart`, `office_controller_test.dart`, `desktop_stage_test.dart`

**Interfaces:** `StationKind.tv`; `StationLayout.dragTo(StationKind kind, double fraction) -> double` (returns the clamped fraction and applies it); `StationState.bars: List<UsageBar>` (`UsageBar(seat, label, pct, resetsAt, dim)`); `OfficeSnapshot.usage: List<UsageSnapshot>`; `WorldPainter(lifted: StationKind?)`; `ActorMood.watch`.

- [ ] Test: `dragTo keeps a 16 px gap to the right neighbour and to the left one`.
- [ ] Test: controller records a `rateLimit` event into `board.recordUsage` and exposes it in `snapshot.usage`.
- [ ] Test: tapping the TV opens a bubble with the bar labels.
- [ ] Implement (settings key migration `coffee` → `tv`); commit `TV with usage bars replaces the coffee machine; stations stop at each other`.

### Task 6: Task bubble with context %, stop and steer

**Files:**
- Create: `app/lib/desktop/task_bubble.dart`
- Modify: `info_bubbles.dart` (WhiteboardBubble.onTaskTap), `desktop_stage.dart`, `state/seat_state.dart` (TaskSnapshot.contextUsed/contextWindow), `state/office_model.dart`, `office_controller.dart`, `desktop_painter.dart`/`actor_sprites.dart` (sweat), `l10n_tr.dart`
- Test: `office_controller_test.dart`, `desktop_stage_test.dart`

**Interfaces:** `OfficeModel.stopTask(String id)`, `steerTask(String id, String note)`, `eventsFor(String id) -> List<AgentEvent>`; `TaskSnapshot.contextPct -> double?`; `TaskBubble(task, events, seat, onStop, onSteer, onClose, onBack)`.

- [ ] Test: controller computes `contextUsed` from the last event's inputTokens and the window from `modelUsage.contextWindow`.
- [ ] Test: whiteboard note tap opens the task bubble; "Durdur" calls `stopTask('s1')`; "Yönlendir" with text calls `steerTask('s1', text)`.
- [ ] Implement; commit `Task bubble: context fill, stop and steer one task`.

### Task 7: Report notice and runner peek

**Files:**
- Modify: `app/windows/runner/desktop_layer.{h,cpp}`, `flutter_window.cpp`, `app/lib/desktop/desktop_layer.dart`, `desktop_stage.dart`, `test/support/fake_desktop_channel.dart`
- Create: `app/lib/desktop/notice_bubble.dart`
- Test: `desktop_stage_test.dart`

**Interfaces:** `DesktopLayer.peek(Duration)`; runner `peek` (int ms); `DesktopStage.noticeDuration = 15 s`.

- [ ] Test: a new unread report shows the notice text and calls `peek`; tapping it opens the mailbox and marks read; no peek while a bubble is open.
- [ ] Implement; commit `A new report shows a notice over the mailbox for 15 s`.

### Task 8: Approval balloon, hotkey, report buttons

**Files:**
- Modify: runner (`RegisterHotKey`, `WM_HOTKEY` → `hotkey`), `desktop_layer.dart` (`onHotkey`), `desktop_stage.dart`, `info_bubbles.dart` (mailbox buttons), `office_controller.dart` (approvals), `l10n_tr.dart`
- Create: `app/lib/desktop/approval_bubble.dart`, `app/lib/desktop/open_external.dart`
- Test: `desktop_stage_test.dart`

**Interfaces:** `OfficeSnapshot.approvals: List<ApprovalRequest>` (`id, taskId, seat, summary`); `OfficeModel.answerApproval(int id, {required bool allow})`; `OpenExternal(launch)` with `openFolder(path)`, `openInEditor(path)`, `editorAvailable`.

- [ ] Test: a pending approval shows the balloon; "İzin ver" calls `answerApproval(id, allow: true)`.
- [ ] Test: `hotkey` from the runner opens Claude's prompt bubble.
- [ ] Test: mailbox "Klasörü aç" launches `explorer.exe` with the cwd.
- [ ] Implement; commit `Approval balloon, Ctrl+Alt+Space, open the report folder`.

### Task 9: Build, live check, README

- [ ] `flutter run -d windows`; check: drag stops at neighbours, TV draws, notice appears after a report, hotkey opens the bubble, task bubble stops a running task.
- [ ] Update `app/windows/README-wallpaper.md` (peek, hotkey) and `docs/plan.md` status.
- [ ] Commit and push.
