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
import 'bubble_sheet.dart';
import 'desktop_layer.dart';
import 'desktop_painter.dart';
import 'info_bubbles.dart';
import 'office_actors.dart';
import 'prompt_bubble.dart';
import 'stations.dart';

/// Which bubble is open.
enum _BubbleKind { prompt, status, whiteboard, mailbox }

class _OpenBubble {
  const _OpenBubble(this.kind, {this.seat, this.station});

  final _BubbleKind kind;
  final Seat? seat;
  final StationKind? station;
}

/// The live office on the desktop: stations along an invisible floor line
/// [floorFromBottom] logical pixels above the bottom of the screen, Claude
/// and GPT walking between them as the [model] reports what they do, and
/// one bubble at a time over whatever was clicked.
///
/// No Scaffold: in wallpaper mode the backdrop is the runner's colour key
/// ([keyColor], see through), in [windowed] mode a dark surface. Clicking an
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
    this.windowed = false,
    this.animate = true,
  });

  static Key actorKey(Seat seat) => Key('stage.actor.${seat.name}');
  static Key stationKey(StationKind kind) => Key('stage.station.${kind.name}');
  static const Key backdropKey = Key('stage.backdrop');

  /// Colour the runner makes transparent (`kColorKey` in
  /// `windows/runner/desktop_layer.cpp`).
  static const Color keyColor = Color(0xFF010203);

  /// Floor line height above the bottom edge: room for the taskbar.
  static const double floorFromBottom = 120;

  /// Device pixels per sprite pixel.
  static const int scale = 4;

  /// Clock period while something moves.
  static const Duration tickPeriod = Duration(milliseconds: 100);

  final OfficeModel model;
  final DesktopLayer layer;

  /// Station positions and recent folders come from here; changes go to
  /// [onSettingsChanged] (the caller saves them).
  final OfficeSettings settings;
  final ValueChanged<OfficeSettings>? onSettingsChanged;

  /// Plain window fallback (`--window`): dark background, no colour key.
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
  int _tick = 0;
  Seat? _hovered;
  _OpenBubble? _bubble;
  late String? _folder =
      _settings.recentFolders.firstOrNull ?? widget.model.cwd;
  final GlobalKey _bubbleKey = GlobalKey();
  final FocusNode _stageFocus = FocusNode(debugLabel: 'desktopStage');
  List<Rect> _reportedRects = const [];

  @override
  void initState() {
    super.initState();
    widget.model.addListener(_onModel);
    widget.layer.onFocusLost = _closeBubble;
  }

  @override
  void dispose() {
    widget.model.removeListener(_onModel);
    if (widget.layer.onFocusLost == _closeBubble) {
      widget.layer.onFocusLost = null;
    }
    _clock?.cancel();
    _wake?.cancel();
    _stageFocus.dispose();
    super.dispose();
  }

  // ---- model and clock -----------------------------------------------------

  void _onModel() {
    final choreo = _choreo;
    if (choreo != null) {
      choreo.apply(widget.model.snapshot);
      if (!widget.animate) choreo.settle();
    }
    if (mounted) setState(() {});
    _syncClock();
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
      case StationKind.coffee:
        break;
    }
  }

  Future<void> _send(Seat seat, String prompt) async {
    final folder = _folder ?? widget.model.cwd;
    _closeBubble();
    _updateSettings(
      _settings.copyWith(recentFolders: _settings.withRecentFolder(folder)),
    );
    try {
      await widget.model.submit(
        prompt,
        directSeat: seat == Seat.gpt ? Seat.gpt : null,
        cwd: folder,
      );
    } on Object catch (error) {
      debugPrint('desktop stage: submit failed: $error');
    }
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
    final fraction = ((layout.centerX(kind) + dx) / layout.width).clamp(
      StationLayout.minFraction,
      StationLayout.maxFraction,
    );
    setState(() => layout.fractions[kind] = fraction);
  }

  void _dropStation() {
    final layout = _layout!;
    _choreo?.relayout(layout);
    if (!widget.animate) _choreo?.settle();
    _updateSettings(_settings.copyWith(stationPositions: layout.toSettings()));
    _syncClock();
  }

  // ---- hit rects -----------------------------------------------------------

  void _reportHitRects(List<Rect> rects) {
    final box = _bubbleKey.currentContext?.findRenderObject();
    final stage = context.findRenderObject();
    final all = [
      for (final r in rects) r.inflate(4),
      if (box is RenderBox && box.hasSize && stage is RenderBox)
        (box.localToGlobal(Offset.zero, ancestor: stage) & box.size).inflate(4),
    ];
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
    var brewing = false;
    for (final actor in _choreo!.actors.values) {
      final desk = StationKind.deskOf(actor.seat);
      final atDesk = !actor.walking && actor.station == desk;
      screens[actor.seat] = atDesk && actor.mood != ActorMood.stand
          ? screenFor(actor.visual)
          : ScreenMode.off;
      brewing |= actor.mood == ActorMood.coffee && !actor.walking;
    }
    return StationState(
      screens: screens,
      notes: snapshot.tasks.take(6).toList(),
      flagUp: snapshot.unreadReports > 0,
      brewing: brewing,
    );
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
                keyColor: DesktopStage.keyColor,
                hovered: _hovered,
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
        if (_bubble != null)
          _bubbleWidget(size, _bubble!, snapshot, stationRects, actorRects),
      ],
    );
  }

  /// The open bubble above its anchor, horizontally centred on it but kept
  /// inside the screen, its pointer aimed at the anchor.
  Widget _bubbleWidget(
    Size size,
    _OpenBubble bubble,
    OfficeSnapshot snapshot,
    Map<StationKind, Rect> stationRects,
    Map<Seat, Rect> actorRects,
  ) {
    final anchor = bubble.seat != null
        ? actorRects[bubble.seat!]!
        : stationRects[bubble.station!]!;
    const margin = 16.0;
    final wanted = bubble.kind == _BubbleKind.prompt
        ? PromptBubble.width
        : infoBubbleWidth;
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
      ),
      _BubbleKind.mailbox => MailboxBubble(
        key: _bubbleKey,
        reports: snapshot.reports,
        pointerX: pointerX,
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
