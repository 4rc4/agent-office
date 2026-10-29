import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:office_core/office_core.dart';

import '../l10n_tr.dart';
import '../state/seat_state.dart';
import '../widgets/office_theme.dart';
import 'bubble_sheet.dart';
import 'folder_name.dart';

/// Width of the information bubbles.
const double infoBubbleWidth = 340;

/// What a working character is up to: its state, the task, the last thing
/// it said, tokens, and a stop button.
class StatusBubble extends StatelessWidget {
  const StatusBubble({
    super.key,
    required this.seat,
    required this.onStop,
    required this.onClose,
    this.pointerX = 0.5,
  });

  static const Key stopButtonKey = Key('bubble.stop');

  final SeatSnapshot seat;
  final VoidCallback onStop;
  final VoidCallback onClose;
  final double pointerX;

  @override
  Widget build(BuildContext context) {
    final summary = seat.lastSummary.trim();
    return BubbleSheet(
      title: '${Tr.seatName(seat.seat)} · ${Tr.visualLabel(seat.visual)}',
      onClose: onClose,
      pointerX: pointerX,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          _line(Tr.currentTask, seat.currentTaskTitle ?? Tr.noTask),
          const SizedBox(height: 4),
          Text(
            summary.isEmpty ? Tr.noSummary : summary,
            style: PixelText.body,
            maxLines: 3,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              Expanded(
                child: Text(
                  '${Tr.tokens}: ${seat.tokensIn} ${Tr.tokensIn} · '
                  '${seat.tokensOut} ${Tr.tokensOut}',
                  style: PixelText.muted,
                ),
              ),
              SheetButton(
                key: stopButtonKey,
                label: Tr.stop,
                icon: Icons.stop_rounded,
                onPressed: onStop,
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _line(String label, String value) => Row(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      SizedBox(width: 56, child: Text(label, style: PixelText.muted)),
      Expanded(
        child: Text(
          value,
          style: PixelText.bodyStrong,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
        ),
      ),
    ],
  );
}

/// The task list, grouped by root task: the root's title with its folder,
/// then its subtasks with their status and desk.
class WhiteboardBubble extends StatelessWidget {
  const WhiteboardBubble({
    super.key,
    required this.tasks,
    required this.onClose,
    this.onTaskTap,
    this.pointerX = 0.5,
  });

  static Key taskKey(String id) => Key('whiteboard.task.$id');

  final List<TaskSnapshot> tasks;
  final VoidCallback onClose;

  /// A note was tapped: the stage opens the task bubble.
  final ValueChanged<TaskSnapshot>? onTaskTap;
  final double pointerX;

  @override
  Widget build(BuildContext context) {
    final roots = tasks.where((t) => t.isRoot).toList();
    final orphans = tasks
        .where((t) => !t.isRoot && !roots.any((r) => r.id == t.rootId))
        .toList();
    return BubbleSheet(
      title: Tr.whiteboard,
      onClose: onClose,
      pointerX: pointerX,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxHeight: 280),
        child: tasks.isEmpty
            ? const Text(Tr.noTasks, style: PixelText.muted)
            : SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    for (final root in roots) ...[
                      _rootLine(root),
                      for (final t in tasks)
                        if (!t.isRoot && t.rootId == root.id) _taskLine(t),
                      const SizedBox(height: 6),
                    ],
                    for (final t in orphans) _taskLine(t),
                  ],
                ),
              ),
      ),
    );
  }

  Widget _tappable(TaskSnapshot task, Widget child) => InkWell(
    key: WhiteboardBubble.taskKey(task.id),
    onTap: onTaskTap == null ? null : () => onTaskTap!(task),
    child: child,
  );

  Widget _rootLine(TaskSnapshot root) {
    final folder = root.cwd.isEmpty ? '' : ' · ${folderName(root.cwd)}';
    return _tappable(
      root,
      Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _statusDot(root.status),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              '${root.title}$folder',
              style: PixelText.bodyStrong,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          Text(Tr.statusLabel(root.status), style: PixelText.faint),
        ],
      ),
    );
  }

  Widget _taskLine(TaskSnapshot task) {
    final who = task.assignee == null
        ? ''
        : ' · ${Tr.seatName(task.assignee!)}';
    return _tappable(
      task,
      Padding(
        padding: const EdgeInsets.only(left: 14, top: 2),
        child: Row(
          children: [
            _statusDot(task.status),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                task.title,
                style: PixelText.body,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            Text('${Tr.statusLabel(task.status)}$who', style: PixelText.faint),
          ],
        ),
      ),
    );
  }

  Widget _statusDot(TaskStatus status) => Container(
    width: 10,
    height: 10,
    margin: const EdgeInsets.only(top: 4),
    decoration: BoxDecoration(
      color: OfficeColors.status(status),
      border: Border.all(color: PixelColors.ink, width: 1.5),
      borderRadius: BorderRadius.circular(2),
    ),
  );
}

/// The mailbox: the newest report as a letter with a copy button, and the
/// older ones as a short list to switch to.
class MailboxBubble extends StatefulWidget {
  const MailboxBubble({
    super.key,
    required this.reports,
    required this.onClose,
    this.onOpenFolder,
    this.onOpenEditor,
    this.pointerX = 0.5,
  });

  static const Key copyButtonKey = Key('bubble.copy');
  static const Key letterKey = Key('bubble.letter');
  static const Key openFolderKey = Key('bubble.openFolder');
  static const Key openEditorKey = Key('bubble.openEditor');

  /// Newest first.
  final List<OfficeReport> reports;
  final VoidCallback onClose;

  /// "Klasörü aç" / "VS Code" for the shown report; null hides the button.
  final ValueChanged<OfficeReport>? onOpenFolder;
  final ValueChanged<OfficeReport>? onOpenEditor;
  final double pointerX;

  @override
  State<MailboxBubble> createState() => _MailboxBubbleState();
}

class _MailboxBubbleState extends State<MailboxBubble> {
  int _selected = 0;
  bool _copied = false;

  Future<void> _copy(OfficeReport report) async {
    await Clipboard.setData(ClipboardData(text: report.text));
    if (mounted) setState(() => _copied = true);
  }

  @override
  Widget build(BuildContext context) {
    final reports = widget.reports;
    final report = reports.isEmpty
        ? null
        : reports[_selected.clamp(0, reports.length - 1)];
    return BubbleSheet(
      title: Tr.mailbox,
      onClose: widget.onClose,
      pointerX: widget.pointerX,
      child: report == null
          ? const Text(Tr.noReport, style: PixelText.muted)
          : Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  '${report.failed ? Tr.reportFailed : Tr.reportFrom}: '
                  '${report.title}'
                  '${report.cwd.isEmpty ? '' : ' · ${folderName(report.cwd)}'}',
                  style: PixelText.bodyStrong,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 6),
                Container(
                  key: MailboxBubble.letterKey,
                  constraints: const BoxConstraints(maxHeight: 220),
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: PixelColors.letter,
                    border: Border.all(
                      color: PixelColors.paperEdge,
                      width: 1.5,
                    ),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: SingleChildScrollView(
                    child: SelectableText(
                      report.text.trim().isEmpty ? Tr.noReport : report.text,
                      style: PixelText.body,
                    ),
                  ),
                ),
                if (report.cwd.isNotEmpty &&
                    (widget.onOpenFolder != null ||
                        widget.onOpenEditor != null)) ...[
                  const SizedBox(height: 6),
                  Wrap(
                    spacing: 6,
                    runSpacing: 4,
                    children: [
                      if (widget.onOpenFolder != null)
                        SheetButton(
                          key: MailboxBubble.openFolderKey,
                          label: Tr.openFolder,
                          icon: Icons.folder_open_rounded,
                          onPressed: () => widget.onOpenFolder!(report),
                        ),
                      if (widget.onOpenEditor != null)
                        SheetButton(
                          key: MailboxBubble.openEditorKey,
                          label: Tr.openEditor,
                          icon: Icons.code_rounded,
                          onPressed: () => widget.onOpenEditor!(report),
                        ),
                    ],
                  ),
                ],
                const SizedBox(height: 8),
                Row(
                  children: [
                    if (reports.length > 1)
                      Expanded(
                        child: Text(
                          '${Tr.olderReports}: ${reports.length - 1}',
                          style: PixelText.faint,
                        ),
                      )
                    else
                      const Spacer(),
                    SheetButton(
                      key: MailboxBubble.copyButtonKey,
                      label: _copied ? Tr.copied : Tr.copy,
                      icon: Icons.copy_rounded,
                      onPressed: () => _copy(report),
                    ),
                  ],
                ),
                if (reports.length > 1) ...[
                  const SizedBox(height: 4),
                  Wrap(
                    spacing: 4,
                    runSpacing: 4,
                    children: [
                      for (var i = 0; i < reports.length && i < 5; i++)
                        ChoiceChip(
                          label: Text(
                            reports[i].title,
                            style: PixelText.faint,
                            overflow: TextOverflow.ellipsis,
                          ),
                          selected: i == _selected,
                          onSelected: (_) => setState(() {
                            _selected = i;
                            _copied = false;
                          }),
                          selectedColor: PixelColors.tab,
                          backgroundColor: PixelColors.paperLight,
                          side: const BorderSide(color: PixelColors.paperEdge),
                          padding: EdgeInsets.zero,
                          visualDensity: VisualDensity.compact,
                          materialTapTargetSize:
                              MaterialTapTargetSize.shrinkWrap,
                          showCheckmark: false,
                        ),
                    ],
                  ),
                ],
              ],
            ),
    );
  }
}
