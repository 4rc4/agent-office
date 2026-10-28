import 'package:flutter/material.dart';
import 'package:office_core/office_core.dart';

import '../l10n_tr.dart';
import '../state/office_model.dart';
import 'event_row.dart';
import 'office_theme.dart';

/// Opens the full event log as a bottom sheet that follows [model].
Future<void> showEventLogSheet(BuildContext context, OfficeModel model) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    constraints: const BoxConstraints(maxWidth: 900),
    builder: (context) => FractionallySizedBox(
      heightFactor: 0.7,
      child: ListenableBuilder(
        listenable: model,
        builder: (context, _) => EventLogSheet(
          events: model.snapshot.recentEvents,
          onClose: () => Navigator.of(context).pop(),
        ),
      ),
    ),
  );
}

/// Every recent event of the office, newest first, with desk tags.
class EventLogSheet extends StatelessWidget {
  const EventLogSheet({super.key, required this.events, this.onClose});

  static const Key closeButtonKey = Key('eventLog.close');

  /// Newest last, as the snapshot keeps them; the sheet reverses.
  final List<AgentEvent> events;
  final VoidCallback? onClose;

  @override
  Widget build(BuildContext context) {
    final newestFirst = events.reversed.toList();
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 12, 12, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              const Icon(Icons.receipt_long_outlined, size: 20),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  '${Tr.events} · ${events.length}',
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                  ),
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
          Expanded(
            child: newestFirst.isEmpty
                ? const Align(
                    alignment: Alignment.topLeft,
                    child: Text(
                      Tr.noEvents,
                      style: TextStyle(color: OfficeColors.textFaint),
                    ),
                  )
                : ListView.builder(
                    padding: const EdgeInsets.only(right: 8),
                    itemCount: newestFirst.length,
                    itemBuilder: (context, i) => EventRow(newestFirst[i]),
                  ),
          ),
        ],
      ),
    );
  }
}
