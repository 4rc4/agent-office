# Office upgrades (2026-10-29): control, visibility, polish

## Intent

The desktop office works end to end (characters behind the icons, prompts
reach `claude.cmd`). The owner now wants to *run* the office from the desktop
rather than watch it: pick the model and thinking level per prompt, hand
files to a task, see what each running session is doing (including how full
its context is), stop or steer it, get told when a report lands without
clicking the mailbox, and see the subscription limits on a TV. Two visual
problems go with it: dragging a station lets it slide under another one, and
the coffee machine does nothing.

## Goals

1. Model and effort chosen in Ayarlar (per seat default) and overridden per
   prompt in the bubble; passed to `claude --model/--effort` and
   `codex -m / -c model_reasoning_effort`.
2. Files or images attached to a prompt from a picker; the agent reads them
   by path.
3. Whiteboard notes open a task bubble: status, last events, tokens, context
   fill %, "Durdur" (this task only) and "Yönlendir" (a message the session
   continues with).
4. Context fill % per running session on the whiteboard and the task bubble;
   a character above 80 % sweats.
5. Stations never overlap while dragged; the dragged one lifts a little.
6. A new report shows a notice bubble over the mailbox for 15 s, raised over
   other windows, without a click; clicking it opens the mailbox.
7. The coffee machine becomes a TV: usage bars (5 h / weekly per seat, reset
   time); idle characters watch it. Clicking the TV shows the numbers.
8. Permission requests from Claude show as a balloon over the character with
   "İzin ver / Reddet"; the answer goes back to the CLI.
9. Ctrl+Alt+Space opens Claude's prompt bubble over everything.
10. The report in the mailbox has "Klasörü aç" and "VS Code" buttons.

## Non-goals

- Drag-and-drop of files onto the bubble (needs a new native plugin).
- Codex rate limits: `codex exec --json` does not report them; the TV shows
  Codex tokens only.
- Windows toast notifications; the raised notice bubble replaces them.
- Resuming a steered Codex thread mid-turn: Codex restarts with the note.

## Anti-goals

- Stealing focus: the notice bubble and the TV never activate the window;
  only the hotkey and a click do.
- A steer that silently loses the user's message, or a stop that retries.
- Blocking the UI thread with process launches or file reads.

## Decisions (how it gets made)

### Core (`packages/office_core`)

- `TaskRecord.options: Map<String, String>` (`model`, `effort`; empty =
  adapter default). New `options TEXT NOT NULL DEFAULT '{}'` column, added
  with `ALTER TABLE` when missing; `schemaVersion` becomes 2. Subtasks copy
  the root's options.
- `ClaudeAdapter(model:, effort:)` and `CodexAdapter(model:, reasoningEffort:)`
  take defaults from `OfficeConfig`; a task's options override them in
  `buildArguments`.
- `Dispatcher.stopTask(id)` stops the active run and marks the task `failed`
  with note `stopped by user` (no retry). `Dispatcher.steerTask(id, note)`
  stops the run and re-arms the task with a `ResumeHint` whose `sessionRef`
  may be null (fresh start with the prompt plus the note); a steer does not
  consume an attempt.
- `Supervisor.stopTask(id)` / `steerTask(id, note)`: a subtask goes to the
  dispatcher; a direct root to its single subtask; a planned root records a
  note the brain receives at its next turn (`BrainProtocol.userNote`), and
  `stopTask` on a planned root stops its subtasks and closes the brain, so
  the root fails with `stopped by user`.
- Claude runs pass `--permission-prompt-tool stdio`. The parser turns
  `control_request/can_use_tool` into `approvalRequested` carrying
  `request_id`, tool name and input in `raw`; `ClaudeRun.answerControl(
  requestId, {allow, message})` writes the `control_response` line. The
  adapter exposes pending requests through `AgentRun.pendingApprovals` and
  the dispatcher records each one on the board (`interactions`); answering
  through `Supervisor.answerApproval(interactionId, allow)` writes the
  response and marks the interaction answered.
- Usage: a `rateLimit` event's `raw['rate_limit_info']` is recorded with
  `TaskBoard.recordUsage` by the app controller (window =
  `rateLimitType`, `usedPct = utilization * 100`, `source = 'claude-cli'`).

### App (`app`)

- `OfficeSettings` gains `claudeModel`, `claudeEffort`, `codexModel`,
  `codexEffort` (empty string = CLI default). Choices are fixed lists in
  `lib/desktop/model_choices.dart`: Claude models `opus`, `sonnet`, `haiku`;
  efforts `low`, `medium`, `high`, `max`; Codex models `gpt-5.1-codex`,
  `gpt-5.1`, `gpt-5-codex-mini`; efforts `low`, `medium`, `high`.
- `OfficeModel.submit(prompt, {directSeat, cwd, options})`,
  `stopTask(id)`, `steerTask(id, note)`, `answerApproval(id, allow)`,
  `eventsFor(taskId)`.
- `OfficeSnapshot` gains `usage: List<UsageSnapshot>`, `approvals:
  List<ApprovalRequest>`; `TaskSnapshot` gains `contextUsed`,
  `contextWindow` (`contextPct` derived). Context: the last `inputTokens` of
  any event of the task (Claude's input+cache = the whole prompt) over the
  window: Claude `modelUsage[*].contextWindow` from the result, else
  1 000 000 when the model name contains `[1m]`, else 200 000; Codex
  400 000.
- Stations: `StationKind.coffee` → `tv` (settings key `coffee` migrates to
  `tv`). `StationLayout.dragTo(kind, fraction)` clamps to the neighbours in
  the current order with a 16 px gap. `WorldPainter.lifted` draws the
  dragged prop 4 px higher. `ActorMood.coffee` → `watch`; idle wander goes
  to the TV one time in four.
- TV sprite: 28×26, a low stand and a wide screen showing up to three bars
  (Claude 5h, Claude weekly, GPT tokens as a dimmed bar) in seat colours;
  `TvBubble` lists each bar with the reset time ("14:30'da sıfırlanır").
- Notice: the stage keeps `_notice` (the newest unread report) for 15 s and
  asks the runner to `peek(15000)`; while a notice shows, only the mailbox
  and notice rects are reported as hit rects. Runner `peek(ms)` raises
  without activating, shows all reported rects, and lowers on the timer
  unless pinned or hovered.
- Hotkey: the runner registers Ctrl+Alt+Space and calls Dart `hotkey`; the
  stage opens Claude's prompt bubble.
- Prompt bubble: a model chip and an effort chip (popup menus seeded from
  the settings), a "Dosya" button (`openFiles`) with removable chips; the
  sent prompt ends with `Ekli dosyalar (yoluyla oku):` and one path per line.
- Task bubble (`TaskBubble`): title, status, assignee, attempt, context bar,
  last five events, tokens of the seat, "Durdur" and "Yönlendir" (a one-line
  field; empty for a GPT task shows the restart note).
- Approval balloon: `ApprovalBubble` over the character: tool summary,
  "İzin ver" / "Reddet"; the seat shows `waitingUser` meanwhile.
- Mailbox: "Klasörü aç" runs `explorer.exe <cwd>`; "VS Code" runs `code`
  resolved on PATH and is hidden when it is not found.

## Constraints

- Flutter 3.41.2 / Dart 3.11; no new pub dependencies.
- All user-facing text in `l10n_tr.dart`, Turkish, short.
- Tests: `dart test` in office_core, `flutter test --exclude-tags=golden` in
  app, both green; new widget tests run with `--timeout 60s`.
- The Windows runner compiles under `/W4 /WX`.

## Left to the builder

- Exact pixel art of the TV and the sweat drop.
- Layout of the chips inside the 360 px prompt bubble.
- Ordering of bars on the TV when a window is unknown.
