import 'dart:async';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../l10n_tr.dart';
import '../widgets/office_theme.dart';
import 'desktop_character.dart';
import 'desktop_layer.dart';
import 'speech_bubble.dart';

/// The desktop stage: one character standing on an invisible floor line
/// [floorFromBottom] logical pixels above the bottom of the screen, a
/// [SpeechBubble] over it while open and a short debug list of what was
/// sent under it.
///
/// The tree has no Scaffold: in wallpaper mode the background is the
/// runner's colour key ([keyColor], see through), in [windowed] mode a dark
/// surface with a faint floor line. Hover bobs the character, a click opens
/// the bubble (and pins the layer in front), Esc or send closes it (and
/// sends the layer back); Esc with no bubble open quits. After every layout
/// the character's and the bubble's rectangles go to the runner as hit
/// rects in physical pixels.
class DesktopStage extends StatefulWidget {
  const DesktopStage({
    super.key,
    required this.layer,
    this.windowed = false,
    this.animate = true,
    this.initialFolder,
  });

  static const Key characterKey = Key('stage.character');
  static const Key backdropKey = Key('stage.backdrop');
  static const Key logKey = Key('stage.log');

  /// Colour the runner makes transparent (`kColorKey` in
  /// `windows/runner/desktop_layer.cpp`); the stage paints nothing else
  /// where the desktop should show.
  static const Color keyColor = Color(0xFF010203);

  /// Floor line height above the bottom edge: room for the taskbar.
  static const double floorFromBottom = 120;

  /// Horizontal position of the character's centre as a fraction of width.
  static const double characterX = 0.30;

  /// Sprite scale (device pixels per sprite pixel).
  static const int characterScale = 4;

  /// How long the character types after a prompt was sent.
  static const Duration typingBurst = Duration(seconds: 4);

  /// Most recent sent prompts shown under the character.
  static const int logLength = 3;

  final DesktopLayer layer;

  /// Plain window fallback (`--window`): dark background, no colour key.
  final bool windowed;

  /// Runs the animation clock; tests switch it off.
  final bool animate;

  /// Folder shown in the bubble until the user picks another.
  final String? initialFolder;

  @override
  State<DesktopStage> createState() => _DesktopStageState();
}

class _DesktopStageState extends State<DesktopStage> {
  Timer? _clock;
  Timer? _typing;
  int _tick = 0;
  bool _hovered = false;
  bool _bubbleOpen = false;
  DesktopVisual _visual = DesktopVisual.idle;
  late String? _folder = widget.initialFolder;
  final List<String> _log = [];
  final GlobalKey _bubbleKey = GlobalKey();
  final FocusNode _stageFocus = FocusNode(debugLabel: 'desktopStage');
  List<Rect> _reportedRects = const [];

  @override
  void initState() {
    super.initState();
    widget.layer.onFocusLost = _closeBubble;
    if (widget.animate) {
      _clock = Timer.periodic(const Duration(milliseconds: 250), (_) {
        setState(() => _tick++);
      });
    }
  }

  @override
  void dispose() {
    if (widget.layer.onFocusLost == _closeBubble) {
      widget.layer.onFocusLost = null;
    }
    _clock?.cancel();
    _typing?.cancel();
    _stageFocus.dispose();
    super.dispose();
  }

  // ---- bubble --------------------------------------------------------------

  void _toggleBubble() {
    if (_bubbleOpen) {
      _closeBubble();
    } else {
      setState(() => _bubbleOpen = true);
      unawaited(widget.layer.bringToFront());
    }
  }

  void _closeBubble() {
    if (!_bubbleOpen || !mounted) return;
    setState(() => _bubbleOpen = false);
    _stageFocus.requestFocus();
    unawaited(widget.layer.sendToBack());
  }

  void _send(String prompt) {
    final entry = '$prompt  ·  ${_folder ?? Tr.noFolder}';
    debugPrint('desktop stage: send "$prompt" in ${_folder ?? '-'}');
    setState(() {
      _log.insert(0, entry);
      if (_log.length > DesktopStage.logLength) _log.removeLast();
      _visual = DesktopVisual.typing;
    });
    _typing?.cancel();
    _typing = Timer(DesktopStage.typingBurst, () {
      if (mounted) setState(() => _visual = DesktopVisual.idle);
    });
    _closeBubble();
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

  /// Esc at the stage level: closes an open bubble (when the field did not
  /// take the key), otherwise quits.
  KeyEventResult _onStageKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent ||
        event.logicalKey != LogicalKeyboardKey.escape) {
      return KeyEventResult.ignored;
    }
    if (_bubbleOpen) {
      _closeBubble();
    } else {
      unawaited(widget.layer.quit());
    }
    return KeyEventResult.handled;
  }

  // ---- hit rects -----------------------------------------------------------

  /// Sends the character's and the bubble's rectangles (physical pixels)
  /// to the runner when they changed since the last report.
  void _reportHitRects(Rect character) {
    final box = _bubbleKey.currentContext?.findRenderObject();
    final stage = context.findRenderObject();
    final rects = [
      character.inflate(4),
      if (box is RenderBox && box.hasSize && stage is RenderBox)
        (box.localToGlobal(Offset.zero, ancestor: stage) & box.size).inflate(4),
    ];
    if (_sameRects(rects, _reportedRects)) return;
    _reportedRects = rects;
    final dpr = MediaQuery.devicePixelRatioOf(context);
    unawaited(
      widget.layer.setHitRects([
        for (final r in rects)
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

  @override
  Widget build(BuildContext context) {
    // No Scaffold: a transparent Material gives the text field, the buttons
    // and the theme's text style a home without painting anything.
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
    final floorY = size.height - DesktopStage.floorFromBottom;
    final characterSize = const DesktopCharacter(
      visual: DesktopVisual.idle,
      tick: 0,
      scale: DesktopStage.characterScale,
    ).size;
    final character = Rect.fromLTWH(
      (size.width * DesktopStage.characterX - characterSize.width / 2)
          .roundToDouble(),
      floorY - characterSize.height,
      characterSize.width,
      characterSize.height,
    );
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _reportHitRects(character);
    });
    return Stack(
      children: [
        Positioned.fill(
          child: GestureDetector(
            key: DesktopStage.backdropKey,
            behavior: HitTestBehavior.opaque,
            onTap: _closeBubble,
            child: CustomPaint(
              painter: _BackdropPainter(
                windowed: widget.windowed,
                floorY: floorY,
              ),
            ),
          ),
        ),
        Positioned.fromRect(
          rect: character,
          child: MouseRegion(
            cursor: SystemMouseCursors.click,
            onEnter: (_) => setState(() => _hovered = true),
            onExit: (_) => setState(() => _hovered = false),
            child: GestureDetector(
              key: DesktopStage.characterKey,
              behavior: HitTestBehavior.opaque,
              onTap: _toggleBubble,
              child: DesktopCharacter(
                visual: _visual,
                tick: _tick,
                hovered: _hovered,
                scale: DesktopStage.characterScale,
              ),
            ),
          ),
        ),
        if (_log.isNotEmpty)
          Positioned(
            left: character.left - 60,
            top: floorY + 6,
            width: character.width + 200,
            child: _DebugLog(entries: _log),
          ),
        if (_bubbleOpen) _bubble(size, character),
      ],
    );
  }

  /// The bubble above the character, horizontally centred on it but kept
  /// inside the screen, its pointer aimed at the head.
  Widget _bubble(Size size, Rect character) {
    const margin = 16.0;
    final width = (SpeechBubble.width).clamp(0.0, size.width - 2 * margin);
    final tipX = character.center.dx;
    final left = (tipX - width / 2).clamp(margin, size.width - width - margin);
    final ears = (DesktopStage.characterScale * 1).toDouble();
    return Positioned(
      left: left,
      bottom: size.height - (character.top - ears),
      width: width,
      child: SpeechBubble(
        key: _bubbleKey,
        folder: _folder,
        pointerX: (tipX - left) / width,
        onSend: _send,
        onClose: _closeBubble,
        onPickFolder: _pickFolder,
      ),
    );
  }
}

/// The colour key (wallpaper mode) or the dark surface with a floor line
/// (`--window`).
class _BackdropPainter extends CustomPainter {
  const _BackdropPainter({required this.windowed, required this.floorY});

  final bool windowed;
  final double floorY;

  @override
  void paint(Canvas canvas, Size size) {
    final bg = Paint()
      ..color = windowed ? OfficeColors.background : DesktopStage.keyColor;
    canvas.drawRect(Offset.zero & size, bg);
    if (!windowed) return;
    canvas.drawRect(
      Rect.fromLTWH(0, floorY, size.width, 1),
      Paint()..color = OfficeColors.outline,
    );
  }

  @override
  bool shouldRepaint(_BackdropPainter old) =>
      old.windowed != windowed || old.floorY != floorY;
}

/// The last few sent prompts, cream text on ink pills, newest first.
class _DebugLog extends StatelessWidget {
  const _DebugLog({required this.entries});

  final List<String> entries;

  @override
  Widget build(BuildContext context) {
    return Column(
      key: DesktopStage.logKey,
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        for (final entry in entries)
          Container(
            margin: const EdgeInsets.only(bottom: 3),
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
              color: OfficeColors.surface,
              borderRadius: BorderRadius.circular(6),
              border: Border.all(color: OfficeColors.outline, width: 1.5),
            ),
            child: Text(
              '${Tr.sentLabel}: $entry',
              style: const TextStyle(fontSize: 12, color: OfficeColors.text),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
      ],
    );
  }
}
