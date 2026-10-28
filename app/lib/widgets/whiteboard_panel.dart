import 'package:flutter/material.dart';
import 'package:office_core/office_core.dart';

import '../l10n_tr.dart';
import '../state/office_model.dart';
import '../state/seat_state.dart';
import 'event_row.dart';
import 'office_theme.dart';

/// Opens the whiteboard as a dialog that follows [model] while open.
Future<void> showWhiteboardDialog(BuildContext context, OfficeModel model) {
  return showDialog<void>(
    context: context,
    builder: (context) => Dialog(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 560, maxHeight: 620),
        child: ListenableBuilder(
          listenable: model,
          builder: (context, _) => WhiteboardPanel(
            tasks: model.snapshot.tasks,
            onClose: () => Navigator.of(context).pop(),
          ),
        ),
      ),
    ),
  );
}

/// The sticky notes as a list: tasks grouped by status, each with its
/// assignee chip. Root tasks come first in a group, subtasks indented.
class WhiteboardPanel extends StatelessWidget {
  const WhiteboardPanel({super.key, required this.tasks, this.onClose});

  static const Key closeButtonKey = Key('whiteboard.close');

  final List<TaskSnapshot> tasks;
  final VoidCallback? onClose;

  @override
  Widget build(BuildContext context) {
    final groups = <TaskStatus, List<TaskSnapshot>>{};
    for (final task in tasks) {
      groups.putIfAbsent(task.status, () => []).add(task);
    }
    final ordered = [
      for (final status in TaskStatus.values)
        if (groups.containsKey(status)) status,
    ];
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 12, 16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              const Icon(Icons.sticky_note_2_outlined, size: 20),
              const SizedBox(width: 8),
              const Expanded(
                child: Text(
                  Tr.whiteboard,
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
                ),
              ),
              if (onClose != null)
                IconButton(
                  key: closeButtonKey,
                  tooltip: Tr.close,
                  onPressed: onClose,
                  icon: const Icon(Icons.close_rounded, size: 20),
                ),
            ],
          ),
          const SizedBox(height: 8),
          if (tasks.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 24),
              child: Text(
                Tr.noTasks,
                style: TextStyle(color: OfficeColors.textFaint),
              ),
            )
          else
            Flexible(
              child: ListView(
                shrinkWrap: true,
                padding: const EdgeInsets.only(right: 8),
                children: [
                  for (final status in ordered)
                    _StatusGroup(
                      status: status,
                      tasks: _sorted(groups[status]!),
                    ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  static List<TaskSnapshot> _sorted(List<TaskSnapshot> group) {
    final roots = group.where((t) => t.isRoot).toList();
    final rest = group.where((t) => !t.isRoot).toList();
    return [...roots, ...rest];
  }
}

class _StatusGroup extends StatelessWidget {
  const _StatusGroup({required this.status, required this.tasks});

  final TaskStatus status;
  final List<TaskSnapshot> tasks;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Container(
                width: 10,
                height: 10,
                decoration: BoxDecoration(
                  color: OfficeColors.status(status),
                  borderRadius: BorderRadius.circular(2),
                  border: Border.all(color: OfficeColors.outline, width: 1.5),
                ),
              ),
              const SizedBox(width: 8),
              Text(
                '${Tr.statusLabel(status)} · ${tasks.length}',
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: OfficeColors.textMuted,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          for (final task in tasks) _TaskRow(task),
        ],
      ),
    );
  }
}

class _TaskRow extends StatelessWidget {
  const _TaskRow(this.task);

  final TaskSnapshot task;

  @override
  Widget build(BuildContext context) {
    final assignee = task.assignee;
    return Container(
      margin: EdgeInsets.only(left: task.isRoot ? 0 : 18, bottom: 6),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: OfficeColors.surfaceRaised,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: OfficeColors.outline, width: 1.5),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  task.title,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: task.isRoot ? FontWeight.w700 : FontWeight.w400,
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                if (task.resultSummary != null &&
                    task.resultSummary!.trim().isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Text(
                      firstLine(task.resultSummary!),
                      style: const TextStyle(
                        fontSize: 11,
                        color: OfficeColors.textMuted,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          if (task.attempt > 1)
            Padding(
              padding: const EdgeInsets.only(right: 6, top: 2),
              child: Text(
                '${Tr.attempt} ${task.attempt}',
                style: const TextStyle(
                  fontSize: 11,
                  color: OfficeColors.textFaint,
                ),
              ),
            ),
          if (assignee != null)
            SeatTag(assignee)
          else
            const Text(
              Tr.unassigned,
              style: TextStyle(fontSize: 11, color: OfficeColors.textFaint),
            ),
        ],
      ),
    );
  }
}
