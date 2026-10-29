import 'dart:async';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/gestures.dart' show DragStartBehavior;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:office_core/office_core.dart';

import '../l10n_tr.dart';
import '../runtime/office_settings.dart';
import '../scene/screens.dart';
import '../scene/sprites.dart';
import '../state/office_model.dart';
import '../state/seat_state.dart';
import 'autostart.dart';
import 'bubble_sheet.dart';
import 'desktop_layer.dart';
import 'approval_bubble.dart';
import 'desktop_painter.dart';
import 'info_bubbles.dart';
import 'model_choices.dart';
import 'notice_bubble.dart';
import 'open_external.dart';
import 'office_actors.dart';
import 'prompt_bubble.dart';
import 'settings_bubble.dart';
import 'stations.dart';
import 'task_bubble.dart';
import 'tv_bubble.dart';
import '../widgets/office_theme.dart';
import 'wallpaper.dart';

/// Requests that reach the stage from outside the widget tree (the tray).
class DesktopCommands extends ChangeNotifier {
  bool _settingsRequested = false;

  /// Opens the settings bubble.
  void openSettings() {
    _settingsRequested = true;
    notifyListeners();
  }

  /// Whether [openSettings] was called since the last take.
  bool takeSettingsRequest() {
    final requested = _settingsRequested;
    _settingsRequested = false;
    return requested;
  }
}

/// Which bubble is open.
enum _BubbleKind { prompt, status, whiteboard, mailbox, settings, tv, task }

class _OpenBubble {
  const _OpenBubble(this.kind, {this.seat, this.station, this.taskId});

  final _BubbleKind kind;

  /// The task a [_BubbleKind.task] bubble shows.
  final String? taskId;
  final Seat? seat;
  final StationKind? station;
}

/// The live office on the desktop: stations along an invisible floor line
/// [floorFromBottom] logical pixels above the bottom of the screen, Claude
/// and GPT walking between them as the [model] reports what they do, and
/// one bubble at a time over whatever was clicked.
///
/// No Scaffold: in wallpaper mode the backdrop is a copy of the desktop
/// wallpaper ([initialWallpaper], re-read every [wallpaperPollPeriod] so a
/// slideshow or a new picture follows), in [windowed] mode a dark surface.
/// Clicking an
/// idle character opens the prompt bubble (Claude plans an office task, GPT
/// gets a direct one), a working one its status; the whiteboard lists the
/// tasks, the mailbox shows the reports. Stations drag along the floor and
/// their positions go to [onSettingsChanged] with the recent folders. Hit
/// rects of every station, character and bubble reach the runner after each
/// layout. The 100 ms clock runs only while someone walks or animates.
class DesktopStage extends StatefulWidget {
  const DesktopStage({
    super.key,
    required this.model,
    required this.layer,
    required this.settings,
    this.onSettingsChanged,
    this.commands,
    this.autostart = const NoAutostart(),
    this.initialWallpaper,
    this.pickFiles,
    this.openExternal,
    this.windowed = false,
    this.animate = true,
  });

  static Key actorKey(Seat seat) => Key('stage.actor.${seat.name}');
  static Key stationKey(StationKind kind) => Key('stage.station.${kind.name}');
  static const Key backdropKey = Key('stage.backdrop');
  static const Key tvCaptionKey = Key('stage.tvCaption');

  /// How often the wallpaper is re-read from the runner (a window behind
  /// the icons gets no change broadcasts).
  static const Duration wallpaperPollPeriod = Duration(seconds: 5);

  /// Floor line height above the bottom edge: room for the taskbar.
  static const double floorFromBottom = 120;

  /// Device pixels per sprite pixel.
  static const int scale = 4;

  /// Context fill from which a character sweats.
  static const double sweatAt = 0.8;

  /// How long the report notice stays over the mailbox.
  static const Duration noticeDuration = Duration(seconds: 15);

  /// How long a permission balloon is held over other windows.
  static const Duration approvalPeek = Duration(minutes: 2);

  /// Clock period while something moves.
  static const Duration tickPeriod = Duration(milliseconds: 100);

  final OfficeModel model;
  final DesktopLayer layer;

  /// Station positions and recent folders come from here; changes go to
  /// [onSettingsChanged] (the caller saves them).
  final OfficeSettings settings;
  final ValueChanged<OfficeSettings>? onSettingsChanged;

  /// Tray requests (open the settings).
  final DesktopCommands? commands;

  /// Backs the "Windows ile başlat" switch of the settings bubble.
  final Autostart autostart;

  /// The wallpaper copy of the first frame (`main` loads it before the
  /// window shows); null paints the desktop background colour.
  final DesktopWallpaper? initialWallpaper;

  /// Picks files to attach to a prompt; null uses the native picker
  /// (`openFiles`). Tests inject a fake.
  final Future<List<String>> Function()? pickFiles;

  /// Opens report folders in Explorer / VS Code; null builds the real one.
  final OpenExternal? openExternal;

  /// Plain window fallback (`--window`): dark background, no wallpaper.
  final bool windowed;

  /// Runs the clock and the idle schedule; tests switch it off and every
  /// walk completes at once.
  final bool animate;

  @override
  State<DesktopStage> createState() => _DesktopStageState();
}

class _DesktopStageState extends State<DesktopStage> {
  late OfficeSettings _settings = widget.settings;
  StationLayout? _layout;
  Choreographer? _choreo;
  Timer? _clock;
  Timer? _wake;
  Timer? _wallpaperClock;
  late DesktopWallpaper? _wallpaper = widget.initialWallpaper;
  int _tick = 0;
  Seat? _hovered;
  StationKind? _dragging;
  _OpenBubble? _bubble;
  late String? _folder =
      _settings.recentFolders.firstOrNull ?? widget.model.cwd;
  final GlobalKey _bubbleKey = GlobalKey();
  final GlobalKey _noticeKey = GlobalKey();
  final GlobalKey _approvalKey = GlobalKey();
  late final OpenExternal _external = widget.openExternal ?? OpenExternal();
  int? _peekedApproval;
  OfficeReport? _notice;
  Timer? _noticeTimer;
  String? _noticedRootId;
  PromptOptions _options = const PromptOptions();
  List<String> _attachments = const [];
  final FocusNode _stageFocus = FocusNode(debugLabel: 'desktopStage');
  List<Rect> _reportedRects = const [];

  @override
  void initState() {
    super.initState();
    widget.model.addListener(_onModel);
    widget.commands?.addListener(_onCommand);
    widget.layer.onFocusLost = _closeBubble;
    widget.layer.onHotkey = _onHotkey;
    _watchApprovals(widget.model.snapshot);
    if (!widget.windowed && widget.animate) {
      _wallpaperClock = Timer.periodic(
        DesktopStage.wallpaperPollPeriod,
        (_) => unawaited(_refreshWallpaper()),
      );
    }
  }

  /// Re-reads the wallpaper; repaints only when the runner reports a
  /// different one.
  Future<void> _refreshWallpaper() async {
    final current = _wallpaper;
    final next = await DesktopWallpaper.load(
      query: widget.layer.wallpaper,
      current: current,
    );
    if (!mounted || next == null || identical(next, current)) return;
    setState(() => _wallpaper = next);
    current?.image?.dispose();
  }

  @override
  void dispose() {
    widget.model.removeListener(_onModel);
    widget.commands?.removeListener(_onCommand);
    if (widget.layer.onFocusLost == _closeBubble) {
      widget.layer.onFocusLost = null;
    }
    if (widget.layer.onHotkey == _onHotkey) {
      widget.layer.onHotkey = null;
    }
    _clock?.cancel();
    _wake?.cancel();
    _noticeTimer?.cancel();
    _wallpaperClock?.cancel();
    _wallpaper?.image?.dispose();
    _stageFocus.dispose();
    super.dispose();
  }

  // ---- model and clock -----------------------------------------------------

  void _onModel() {
    final choreo = _choreo;
    final snapshot = widget.model.snapshot;
    if (choreo != null) {
      choreo.apply(snapshot);
      if (!widget.animate) choreo.settle();
    }
    _watchApprovals(snapshot);
    final latest = snapshot.reports.firstOrNull;
    if (latest != null &&
        snapshot.unreadReports > 0 &&
        latest.rootId != _noticedRootId) {
      _noticedRootId = latest.rootId;
      _showNotice(latest);
    }
    if (mounted) setState(() {});
    _syncClock();
  }

  /// A new permission request peeks the layer over other windows so its
  /// balloon is seen, unless a bubble already holds the layer in front.
  void _watchApprovals(OfficeSnapshot snapshot) {
    final approval = snapshot.approvals.firstOrNull;
    if (approval == null || approval.id == _peekedApproval) return;
    _peekedApproval = approval.id;
    if (_bubble == null) {
      unawaited(widget.layer.peek(DesktopStage.approvalPeek));
    }
  }

  /// Pops the report card over the mailbox for [DesktopStage.noticeDuration]
  /// and asks the runner to show it over other windows, unless a bubble
  /// already holds the layer in front.
  void _showNotice(OfficeReport report) {
    _noticeTimer?.cancel();
    _notice = report;
    _noticeTimer = Timer(DesktopStage.noticeDuration, _hideNotice);
    if (_bubble == null) {
      unawaited(widget.layer.peek(DesktopStage.noticeDuration));
    }
  }

  void _hideNotice() {
    _noticeTimer?.cancel();
    _noticeTimer = null;
    if (_notice == null || !mounted) return;
    setState(() => _notice = null);
  }

  /// Ctrl+Alt+Space: Claude's bubble, or close what is open.
  void _onHotkey() {
    if (!mounted) return;
    if (_bubble != null) {
      _closeBubble();
      return;
    }
    _tapActor(Seat.claude);
  }

  void _tapNotice() {
    _hideNotice();
    widget.model.markReportsRead();
    _open(const _OpenBubble(_BubbleKind.mailbox, station: StationKind.mailbox));
  }

  /// Starts or stops the 100 ms clock and the idle wake-up timer.
  void _syncClock() {
    final choreo = _choreo;
    if (!widget.animate || choreo == null) return;
    final wanted = choreo.needsTicks || _hovered != null;
    if (wanted) {
      _clock ??= Timer.periodic(DesktopStage.tickPeriod, _onTick);
    } else {
      _clock?.cancel();
      _clock = null;
    }
    _wake?.cancel();
    _wake = null;
    final at = choreo.nextWake;
    if (at != null) {
      var delay = at.difference(DateTime.now());
      if (delay.isNegative) delay = Duration.zero;
      _wake = Timer(delay, () {
        _wake = null;
        _choreo?.wake();
        if (mounted) setState(() {});
        _syncClock();
      });
    }
  }

  void _onTick(Timer _) {
    final choreo = _choreo;
    if (choreo == null) return;
    final moving = choreo.step(DesktopStage.tickPeriod);
    setState(() => _tick++);
    if (!moving && _hovered == null) _syncClock();
  }

  void _onCommand() {
    if (widget.commands?.takeSettingsRequest() ?? false) {
      _open(const _OpenBubble(_BubbleKind.settings));
    }
  }

  // ---- bubbles -------------------------------------------------------------

  void _open(_OpenBubble bubble) {
    setState(() => _bubble = bubble);
    unawaited(widget.layer.bringToFront());
  }

  void _closeBubble() {
    if (_bubble == null || !mounted) return;
    setState(() => _bubble = null);
    _stageFocus.requestFocus();
    unawaited(widget.layer.sendToBack());
  }

  void _tapActor(Seat seat) {
    final open = _bubble;
    if (open != null && open.seat == seat) {
      _closeBubble();
      return;
    }
    final visual = widget.model.snapshot.seat(seat).visual;
    final idle = switch (visual) {
      SeatVisual.idle || SeatVisual.empty || SeatVisual.sleeping => true,
      _ => false,
    };
    if (idle) {
      _options = _settings.defaultOptions(seat);
      _attachments = const [];
    }
    _open(
      _OpenBubble(idle ? _BubbleKind.prompt : _BubbleKind.status, seat: seat),
    );
  }

  void _tapStation(StationKind kind) {
    final open = _bubble;
    if (open != null && open.station == kind) {
      _closeBubble();
      return;
    }
    switch (kind) {
      case StationKind.whiteboard:
        _open(_OpenBubble(_BubbleKind.whiteboard, station: kind));
      case StationKind.mailbox:
        widget.model.markReportsRead();
        _open(_OpenBubble(_BubbleKind.mailbox, station: kind));
      case StationKind.deskClaude:
      case StationKind.deskGpt:
        _tapActor(kind.owner!);
      case StationKind.tv:
        _open(_OpenBubble(_BubbleKind.tv, station: kind));
    }
  }

  Future<void> _send(Seat seat, String prompt) async {
    final folder = _folder ?? widget.model.cwd;
    final text = '$prompt${attachmentSuffix(_attachments)}';
    final options = _options;
    _attachments = const [];
    _closeBubble();
    _updateSettings(
      _settings.copyWith(recentFolders: _settings.withRecentFolder(folder)),
    );
    try {
      await widget.model.submit(
        text,
        directSeat: seat == Seat.gpt ? Seat.gpt : null,
        cwd: folder,
        options: options,
      );
    } on Object catch (error) {
      debugPrint('desktop stage: submit failed: $error');
    }
  }

  Future<void> _pickFiles() async {
    List<String> picked;
    try {
      final custom = widget.pickFiles;
      picked = custom != null
          ? await custom()
          : [for (final f in await openFiles()) f.path];
    } on MissingPluginException {
      return;
    }
    if (!mounted || picked.isEmpty) return;
    setState(() {
      _attachments = [
        ..._attachments,
        for (final path in picked)
          if (!_attachments.contains(path)) path,
      ];
    });
  }

  Future<void> _pickFolder() async {
    try {
      final picked = await getDirectoryPath(
        initialDirectory: _folder,
        confirmButtonText: Tr.chooseFolder,
      );
      if (picked != null && mounted) setState(() => _folder = picked);
    } on MissingPluginException {
      // No native picker here (tests, unsupported host): keep the folder.
    }
  }

  void _updateSettings(OfficeSettings next) {
    if (next == _settings) return;
    _settings = next;
    widget.onSettingsChanged?.call(next);
  }

  /// Esc at the stage level: closes an open bubble (when the field did not
  /// take the key), otherwise quits.
  KeyEventResult _onStageKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent ||
        event.logicalKey != LogicalKeyboardKey.escape) {
      return KeyEventResult.ignored;
    }
    if (_bubble != null) {
      _closeBubble();
    } else {
      unawaited(widget.layer.quit());
    }
    return KeyEventResult.handled;
  }

  // ---- stations ------------------------------------------------------------

  void _dragStation(StationKind kind, double dx) {
    final layout = _layout!;
    final wanted = (layout.centerX(kind) + dx) / layout.width;
    setState(() {
      _dragging = kind;
      layout.dragTo(kind, wanted);
    });
  }

  void _dropStation() {
    final layout = _layout!;
    _dragging = null;
    _choreo?.relayout(layout);
    if (!widget.animate) _choreo?.settle();
    _updateSettings(_settings.copyWith(stationPositions: layout.toSettings()));
    _syncClock();
  }

  // ---- hit rects -----------------------------------------------------------

  void _reportHitRects(List<Rect> rects) {
    final stage = context.findRenderObject();
    Rect? boxOf(GlobalKey key) {
      final box = key.currentContext?.findRenderObject();
      if (box is! RenderBox || !box.hasSize || stage is! RenderBox) {
        return null;
      }
      return (box.localToGlobal(Offset.zero, ancestor: stage) & box.size)
          .inflate(4);
    }

    final bubble = boxOf(_bubbleKey);
    final notice = _notice == null ? null : boxOf(_noticeKey);
    final approval = boxOf(_approvalKey);
    final List<Rect> all;
    if (notice != null && bubble == null && approval == null) {
      // While the notice peeks over other windows only it and the mailbox
      // take the mouse; the rest of the office stays behind the icons.
      all = [_layout!.rect(StationKind.mailbox).inflate(4), notice];
    } else {
      all = [for (final r in rects) r.inflate(4), ?bubble, ?notice, ?approval];
    }
    if (_sameRects(all, _reportedRects)) return;
    _reportedRects = all;
    final dpr = MediaQuery.devicePixelRatioOf(context);
    unawaited(
      widget.layer.setHitRects([
        for (final r in all)
          Rect.fromLTRB(
            (r.left * dpr).floorToDouble(),
            (r.top * dpr).floorToDouble(),
            (r.right * dpr).ceilToDouble(),
            (r.bottom * dpr).ceilToDouble(),
          ),
      ]),
    );
  }

  static bool _sameRects(List<Rect> a, List<Rect> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }

  // ---- layout --------------------------------------------------------------

  /// The layout for [size], rebuilt when the screen changes; the
  /// choreographer is created with the first one.
  StationLayout _layoutFor(Size size) {
    final floorY = size.height - DesktopStage.floorFromBottom;
    var layout = _layout;
    if (layout == null ||
        layout.width != size.width ||
        layout.floorY != floorY) {
      layout = StationLayout(
        width: size.width,
        floorY: floorY,
        fractions: layout?.toSettings() ?? _settings.stationPositions,
        scale: DesktopStage.scale,
      );
      _layout = layout;
      final choreo = _choreo;
      if (choreo == null) {
        _choreo = Choreographer(layout: layout)
          ..apply(widget.model.snapshot)
          ..settle();
        WidgetsBinding.instance.addPostFrameCallback((_) => _syncClock());
      } else {
        choreo.relayout(layout);
        if (!widget.animate) choreo.settle();
      }
    }
    return layout;
  }

  Rect _actorRect(Actor actor) {
    const s = DesktopStage.scale;
    const rows = 1 + spriteEarRows + spriteHeight;
    return Rect.fromLTWH(
      (actor.x - spriteWidth * s / 2).roundToDouble(),
      _layout!.floorY - rows * s,
      (spriteWidth * s).toDouble(),
      (rows * s).toDouble(),
    );
  }

  StationState _stationState(OfficeSnapshot snapshot) {
    final screens = <Seat, ScreenMode>{};
    for (final actor in _choreo!.actors.values) {
      final desk = StationKind.deskOf(actor.seat);
      final atDesk = !actor.walking && actor.station == desk;
      screens[actor.seat] = atDesk && actor.mood != ActorMood.stand
          ? screenFor(actor.visual)
          : ScreenMode.off;
    }
    return StationState(
      screens: screens,
      notes: snapshot.tasks.take(6).toList(),
      flagUp: snapshot.unreadReports > 0,
      bars: usageBars(snapshot),
    );
  }

  /// The TV's bars: every rate-limit window the CLIs reported (Claude's
  /// 5-hour and weekly), then a dim token bar for a seat without limits.
  static List<UsageBar> usageBars(OfficeSnapshot snapshot) {
    final bars = <UsageBar>[];
    for (final seat in const [Seat.claude, Seat.gpt]) {
      final windows = snapshot.usage.where((u) => u.seat == seat).toList()
        ..sort((a, b) => a.window.compareTo(b.window));
      if (windows.isEmpty) {
        final tokens = snapshot.seat(seat).tokensIn;
        if (tokens > 0) {
          bars.add(
            UsageBar(
              seat: seat,
              window: 'tokens',
              pct: (tokens / 400000).clamp(0, 1).toDouble(),
              dim: true,
              tokens: tokens,
            ),
          );
        }
        continue;
      }
      for (final u in windows) {
        bars.add(
          UsageBar(
            seat: seat,
            window: u.window,
            pct: (u.usedPct / 100).clamp(0, 1).toDouble(),
            resetsAt: u.resetsAt,
          ),
        );
      }
    }
    return bars;
  }

  @override
  Widget build(BuildContext context) {
    return Focus(
      focusNode: _stageFocus,
      autofocus: true,
      onKeyEvent: _onStageKey,
      child: Material(
        type: MaterialType.transparency,
        child: LayoutBuilder(
          builder: (context, constraints) => _buildStage(constraints.biggest),
        ),
      ),
    );
  }

  Widget _buildStage(Size size) {
    final layout = _layoutFor(size);
    final choreo = _choreo!;
    final snapshot = widget.model.snapshot;
    final actors = choreo.actors.values.toList();
    final stationRects = {
      for (final kind in StationKind.values) kind: layout.rect(kind),
    };
    final actorRects = {for (final a in actors) a.seat: _actorRect(a)};
    final hitRects = [...stationRects.values, ...actorRects.values];
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _reportHitRects(hitRects);
    });
    return Stack(
      children: [
        Positioned.fill(
          child: GestureDetector(
            key: DesktopStage.backdropKey,
            behavior: HitTestBehavior.opaque,
            onTap: _closeBubble,
            child: CustomPaint(
              painter: WorldPainter(
                layout: layout,
                actors: actors,
                state: _stationState(snapshot),
                frame: _tick % 4,
                tick: _tick,
                wallpaper: _wallpaper,
                devicePixelRatio: MediaQuery.devicePixelRatioOf(context),
                hovered: _hovered,
                lifted: _dragging,
                sweating: sweating(snapshot),
                windowed: widget.windowed,
              ),
            ),
          ),
        ),
        for (final e in stationRects.entries)
          Positioned.fromRect(
            rect: e.value,
            child: MouseRegion(
              cursor: SystemMouseCursors.grab,
              child: GestureDetector(
                key: DesktopStage.stationKey(e.key),
                behavior: HitTestBehavior.opaque,
                onTap: () => _tapStation(e.key),
                dragStartBehavior: DragStartBehavior.down,
                onPanUpdate: (d) => _dragStation(e.key, d.delta.dx),
                onPanEnd: (_) => _dropStation(),
                onPanCancel: _dropStation,
              ),
            ),
          ),
        for (final e in actorRects.entries)
          Positioned.fromRect(
            rect: e.value,
            child: MouseRegion(
              cursor: SystemMouseCursors.click,
              onEnter: (_) {
                setState(() => _hovered = e.key);
                _syncClock();
              },
              onExit: (_) {
                setState(() => _hovered = null);
                _syncClock();
              },
              child: GestureDetector(
                key: DesktopStage.actorKey(e.key),
                behavior: HitTestBehavior.opaque,
                onTap: () => _tapActor(e.key),
              ),
            ),
          ),
        if (_bubble?.kind != _BubbleKind.tv)
          ?_tvCaption(size, snapshot, stationRects[StationKind.tv]!),
        if (snapshot.approvals.isNotEmpty)
          _approvalWidget(size, snapshot.approvals.first, actorRects),
        if (_notice != null)
          _noticeWidget(size, _notice!, stationRects[StationKind.mailbox]!),
        if (_bubble != null)
          _bubbleWidget(size, _bubble!, snapshot, stationRects, actorRects),
      ],
    );
  }

  /// The usage numbers under the TV (below the floor line, clear of the
  /// characters' bubbles), always on (no tap needed): one line
  /// per bar with the percentage and the reset time. Takes no clicks and is
  /// not a hit rect, so it stays behind the desktop icons. Null without
  /// usage data.
  Widget? _tvCaption(Size size, OfficeSnapshot snapshot, Rect tv) {
    final bars = usageBars(snapshot);
    if (bars.isEmpty) return null;
    const width = 340.0;
    const margin = 8.0;
    final left = (tv.center.dx - width / 2).clamp(
      margin,
      size.width - width - margin,
    );
    const text = TextStyle(
      color: Color(0xFFF4EEDC),
      fontSize: 12,
      height: 1.3,
      fontWeight: FontWeight.w600,
    );
    return Positioned(
      left: left,
      top: tv.bottom + 6,
      width: width,
      child: IgnorePointer(
        key: DesktopStage.tvCaptionKey,
        child: Align(
          alignment: Alignment.topCenter,
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: const Color(0xD91A1D3D),
              borderRadius: BorderRadius.circular(6),
              border: Border.all(color: OfficeColors.outline, width: 1.5),
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  for (final bar in bars)
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          width: 8,
                          height: 8,
                          margin: const EdgeInsets.only(right: 6),
                          decoration: BoxDecoration(
                            color: bar.dim
                                ? PixelColors.inkMuted
                                : OfficeColors.usage(bar.pct),
                            borderRadius: BorderRadius.circular(2),
                          ),
                        ),
                        Flexible(child: Text(_captionLine(bar), style: text)),
                      ],
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  static String _captionLine(UsageBar bar) {
    final seat = Tr.seatName(bar.seat);
    if (bar.dim) {
      final k = (bar.tokens / 1000).toStringAsFixed(
        bar.tokens >= 100000 ? 0 : 1,
      );
      return '$seat · ${k}k ${Tr.tokensOnly}';
    }
    final pct = '%${(bar.pct * 100).round()}';
    final resets = bar.resetsAt;
    return '$seat · ${Tr.windowLabel(bar.window)} $pct'
        '${resets == null ? '' : ' · ${Tr.resetsAt(resets)}'}';
  }

  /// The oldest pending permission request, as a balloon over its seat.
  Widget _approvalWidget(
    Size size,
    ApprovalRequest request,
    Map<Seat, Rect> actorRects,
  ) {
    final layout = _layout!;
    final anchor =
        actorRects[request.seat] ??
        Rect.fromLTWH(layout.userSpotX - 1, layout.floorY - 96, 2, 96);
    const margin = 16.0;
    final width = ApprovalBubble.width.clamp(0.0, size.width - 2 * margin);
    final tipX = anchor.center.dx;
    final left = (tipX - width / 2).clamp(margin, size.width - width - margin);
    return Positioned(
      left: left,
      bottom: size.height - (anchor.top - BubbleSheet.pointerHeight / 4),
      width: width,
      child: ApprovalBubble(
        key: _approvalKey,
        request: request,
        pointerX: (tipX - left) / width,
        onAnswer: (allow) =>
            unawaited(widget.model.answerApproval(request.id, allow: allow)),
      ),
    );
  }

  /// The report notice above the mailbox, kept inside the screen.
  Widget _noticeWidget(Size size, OfficeReport report, Rect anchor) {
    const margin = 16.0;
    final width = NoticeBubble.width.clamp(0.0, size.width - 2 * margin);
    final tipX = anchor.center.dx;
    final left = (tipX - width / 2).clamp(margin, size.width - width - margin);
    return Positioned(
      left: left,
      bottom: size.height - (anchor.top - BubbleSheet.pointerHeight / 4),
      width: width,
      child: NoticeBubble(
        key: _noticeKey,
        report: report,
        pointerX: (tipX - left) / width,
        onTap: _tapNotice,
      ),
    );
  }

  /// The open bubble above its anchor, horizontally centred on it but kept
  /// inside the screen, its pointer aimed at the anchor.
  /// The task bubble, or the whiteboard again when the task left the
  /// board.
  Widget _taskBubble(OfficeSnapshot snapshot, String taskId, double pointerX) {
    final task = snapshot.task(taskId);
    if (task == null) {
      return WhiteboardBubble(
        key: _bubbleKey,
        tasks: snapshot.tasks,
        pointerX: pointerX,
        onClose: _closeBubble,
      );
    }
    return TaskBubble(
      key: _bubbleKey,
      task: task,
      events: snapshot.eventsFor(taskId),
      pointerX: pointerX,
      onBack: () => _open(
        const _OpenBubble(
          _BubbleKind.whiteboard,
          station: StationKind.whiteboard,
        ),
      ),
      onStop: () {
        unawaited(widget.model.stopTask(taskId));
        _closeBubble();
      },
      onSteer: (note) {
        unawaited(widget.model.steerTask(taskId, note));
        _closeBubble();
      },
      onClose: _closeBubble,
    );
  }

  /// Seats whose current task's context is at least [DesktopStage.sweatAt].
  static Set<Seat> sweating(OfficeSnapshot snapshot) => {
    for (final seat in snapshot.seats)
      if (seat.currentTaskId != null &&
          (snapshot.task(seat.currentTaskId!)?.contextPct ?? 0) >=
              DesktopStage.sweatAt)
        seat.seat,
  };

  Widget _bubbleWidget(
    Size size,
    _OpenBubble bubble,
    OfficeSnapshot snapshot,
    Map<StationKind, Rect> stationRects,
    Map<Seat, Rect> actorRects,
  ) {
    final layout = _layout!;
    final anchor = bubble.seat != null
        ? actorRects[bubble.seat!]!
        : bubble.station != null
        ? stationRects[bubble.station!]!
        : Rect.fromLTWH(layout.userSpotX - 1, layout.floorY - 96, 2, 96);
    const margin = 16.0;
    final wanted = switch (bubble.kind) {
      _BubbleKind.prompt => PromptBubble.width,
      _BubbleKind.settings => SettingsBubble.width,
      _ => infoBubbleWidth,
    };
    final width = wanted.clamp(0.0, size.width - 2 * margin);
    final tipX = anchor.center.dx;
    final left = (tipX - width / 2).clamp(margin, size.width - width - margin);
    final pointerX = (tipX - left) / width;
    final Widget child = switch (bubble.kind) {
      _BubbleKind.prompt => PromptBubble(
        key: _bubbleKey,
        title: bubble.seat == Seat.gpt ? Tr.askGpt : Tr.whatShallWeDo,
        folder: _folder,
        recentFolders: _settings.recentFolders,
        pointerX: pointerX,
        seat: bubble.seat!,
        options: _options,
        onOptionsChanged: (o) => setState(() => _options = o),
        attachments: _attachments,
        onPickFiles: _pickFiles,
        onRemoveAttachment: (path) => setState(() {
          _attachments = [
            for (final a in _attachments)
              if (a != path) a,
          ];
        }),
        onSend: (prompt) => _send(bubble.seat!, prompt),
        onClose: _closeBubble,
        onPickFolder: _pickFolder,
        onFolderChosen: (f) => setState(() => _folder = f),
      ),
      _BubbleKind.status => StatusBubble(
        key: _bubbleKey,
        seat: snapshot.seat(bubble.seat!),
        pointerX: pointerX,
        onStop: () {
          unawaited(widget.model.stopAll());
          _closeBubble();
        },
        onClose: _closeBubble,
      ),
      _BubbleKind.whiteboard => WhiteboardBubble(
        key: _bubbleKey,
        tasks: snapshot.tasks,
        pointerX: pointerX,
        onClose: _closeBubble,
        onTaskTap: (task) => _open(
          _OpenBubble(
            _BubbleKind.task,
            station: StationKind.whiteboard,
            taskId: task.id,
          ),
        ),
      ),
      _BubbleKind.task => _taskBubble(snapshot, bubble.taskId!, pointerX),
      _BubbleKind.mailbox => MailboxBubble(
        key: _bubbleKey,
        reports: snapshot.reports,
        pointerX: pointerX,
        onClose: _closeBubble,
        onOpenFolder: (r) => unawaited(_external.openFolder(r.cwd)),
        onOpenEditor: _external.editorAvailable
            ? (r) => unawaited(_external.openInEditor(r.cwd))
            : null,
      ),
      _BubbleKind.tv => TvBubble(
        key: _bubbleKey,
        bars: usageBars(snapshot),
        pointerX: pointerX,
        onClose: _closeBubble,
      ),
      _BubbleKind.settings => SettingsBubble(
        key: _bubbleKey,
        settings: _settings,
        autostart: widget.autostart,
        pointerX: pointerX,
        onSave: _updateSettings,
        onClose: _closeBubble,
      ),
    };
    return Positioned(
      left: left,
      bottom: size.height - (anchor.top - BubbleSheet.pointerHeight / 4),
      width: width,
      child: child,
    );
  }
}
