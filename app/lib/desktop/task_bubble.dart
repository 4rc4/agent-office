import 'package:flutter/material.dart';
import 'package:office_core/office_core.dart';

import '../l10n_tr.dart';
import '../state/seat_state.dart';
import '../widgets/office_theme.dart';
import 'bubble_sheet.dart';

/// One task from the whiteboard, up close: status, desk and attempt, how
/// full its session's context is, the last few events, and two controls:
/// "Yönlendir" sends a note the session continues with ([onSteer]),
/// "Durdur" ends this task alone ([onStop]). [onBack] returns to the board.
class TaskBubble extends StatefulWidget {
  const TaskBubble({
    super.key,
    required this.task,
    required this.events,
    required this.onStop,
    required this.onSteer,
    required this.onBack,
    required this.onClose,
    this.pointerX = 0.5,
  });

  static const Key stopKey = Key('task.stop');
  static const Key steerKey = Key('task.steer');
  static const Key steerFieldKey = Key('task.steerField');
  static const Key backKey = Key('task.back');

  /// How many of [events] are shown, newest last.
  static const int shownEvents = 5;

  final TaskSnapshot task;

  /// Events of this task, oldest first.
  final List<AgentEvent> events;
  final VoidCallback onStop;
  final ValueChanged<String> onSteer;
  final VoidCallback onBack;
  final VoidCallback onClose;
  final double pointerX;

  @override
  State<TaskBubble> createState() => _TaskBubbleState();
}

class _TaskBubbleState extends State<TaskBubble> {
  final TextEditingController _note = TextEditingController();

  @override
  void dispose() {
    _note.dispose();
    super.dispose();
  }

  void _steer() {
    final note = _note.text.trim();
    if (note.isEmpty) return;
    widget.onSteer(note);
  }

  @override
  Widget build(BuildContext context) {
    final task = widget.task;
    final open = !task.status.isTerminal;
    final pct = task.contextPct;
    final events = widget.events.length > TaskBubble.shownEvents
        ? widget.events.sublist(widget.events.length - TaskBubble.shownEvents)
        : widget.events;
    final who = task.assignee == null
        ? Tr.unassigned
        : Tr.seatName(task.assignee!);
    return BubbleSheet(
      title: Tr.taskDetails,
      onClose: widget.onClose,
      pointerX: widget.pointerX,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            task.title,
            style: PixelText.bodyStrong,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: 4),
          Text(
            '${Tr.statusLabel(task.status)} · $who · ${Tr.attempt} '
            '${task.attempt}',
            style: PixelText.muted,
          ),
          if (pct != null) ...[
            const SizedBox(height: 6),
            Row(
              children: [
                Expanded(
                  child: Text(
                    '${Tr.contextLabel}: %${(pct * 100).round()} '
                    '(${_k(task.contextUsed)} / ${_k(task.contextWindow)})',
                    style: PixelText.muted,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 3),
            ClipRRect(
              borderRadius: BorderRadius.circular(3),
              child: LinearProgressIndicator(
                value: pct.clamp(0, 1).toDouble(),
                minHeight: 6,
                backgroundColor: PixelColors.paperEdge,
                color: OfficeColors.usage(pct),
              ),
            ),
          ],
          const SizedBox(height: 6),
          Text(Tr.lastEvents, style: PixelText.faint),
          if (events.isEmpty)
            const Text(Tr.noEvents, style: PixelText.muted)
          else
            for (final event in events)
              Text(
                event.summary.trim().isEmpty
                    ? Tr.eventKindLabel(event.kind)
                    : event.summary.trim(),
                style: PixelText.body,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
          if (open) ...[
            const SizedBox(height: 8),
            TextField(
              key: TaskBubble.steerFieldKey,
              controller: _note,
              style: PixelText.body,
              cursorColor: PixelColors.ink,
              onSubmitted: (_) => _steer(),
              decoration: InputDecoration(
                isDense: true,
                filled: true,
                fillColor: PixelColors.paperLight,
                hintText: task.assignee == Seat.gpt
                    ? Tr.steerGptHint
                    : Tr.steerHint,
                hintStyle: PixelText.faint,
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 8,
                ),
                enabledBorder: const OutlineInputBorder(
                  borderRadius: BorderRadius.all(Radius.circular(6)),
                  borderSide: BorderSide(
                    color: PixelColors.paperEdge,
                    width: 1.5,
                  ),
                ),
                focusedBorder: const OutlineInputBorder(
                  borderRadius: BorderRadius.all(Radius.circular(6)),
                  borderSide: BorderSide(color: PixelColors.ink, width: 2),
                ),
              ),
            ),
          ],
          const SizedBox(height: 8),
          Row(
            children: [
              SheetButton(
                key: TaskBubble.backKey,
                label: Tr.back,
                icon: Icons.arrow_back_rounded,
                onPressed: widget.onBack,
              ),
              const Spacer(),
              if (open) ...[
                SheetButton(
                  key: TaskBubble.stopKey,
                  label: Tr.stop,
                  icon: Icons.stop_rounded,
                  onPressed: widget.onStop,
                ),
                const SizedBox(width: 6),
                SheetButton(
                  key: TaskBubble.steerKey,
                  label: Tr.steer,
                  icon: Icons.alt_route_rounded,
                  filled: true,
                  onPressed: _steer,
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }

  static String _k(int tokens) => tokens >= 1000
      ? '${(tokens / 1000).toStringAsFixed(tokens >= 100000 ? 0 : 1)}k'
      : '$tokens';
}
