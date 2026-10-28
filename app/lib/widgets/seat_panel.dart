import 'package:flutter/material.dart';
import 'package:office_core/office_core.dart';

import '../l10n_tr.dart';
import '../state/seat_state.dart';
import 'event_row.dart';
import 'office_theme.dart';

/// Details of one desk: who sits there, what they do, the task, the session,
/// tokens, XP and that desk's last events.
///
/// Height must be bounded by the parent (a 320 px side column or a sheet).
class SeatPanel extends StatelessWidget {
  const SeatPanel({
    super.key,
    required this.seat,
    required this.events,
    required this.onClose,
    this.maxEvents = 20,
  });

  static const Key closeButtonKey = Key('seatPanel.close');

  final SeatSnapshot seat;

  /// The whole office log; the panel keeps this desk's newest [maxEvents].
  final List<AgentEvent> events;
  final VoidCallback onClose;
  final int maxEvents;

  List<AgentEvent> get _ownEvents {
    final own = events.where((e) => e.seat == seat.seat).toList();
    final start = own.length > maxEvents ? own.length - maxEvents : 0;
    return own.sublist(start).reversed.toList();
  }

  @override
  Widget build(BuildContext context) {
    final own = _ownEvents;
    return Container(
      color: OfficeColors.surface,
      padding: const EdgeInsets.fromLTRB(16, 12, 8, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _header(),
          const SizedBox(height: 6),
          // Everything below the header scrolls, so the panel also fits the
          // short bottom-sheet variant.
          Expanded(
            child: ListView(
              padding: const EdgeInsets.only(right: 8, top: 4),
              children: [
                _StateChip(visual: seat.visual),
                const SizedBox(height: 12),
                _InfoRow(Tr.currentTask, seat.currentTaskTitle ?? Tr.noTask),
                _InfoRow(
                  Tr.session,
                  seat.sessionRef == null
                      ? Tr.noSession
                      : shortRef(seat.sessionRef!),
                  mono: seat.sessionRef != null,
                ),
                _InfoRow(
                  Tr.tokens,
                  '${seat.tokensIn} ${Tr.tokensIn} · '
                  '${seat.tokensOut} ${Tr.tokensOut}',
                ),
                _InfoRow(Tr.xp, '${seat.xp}'),
                if (seat.lastSummary.isNotEmpty) ...[
                  const SizedBox(height: 6),
                  Text(
                    firstLine(seat.lastSummary),
                    style: const TextStyle(
                      fontSize: 12,
                      color: OfficeColors.textMuted,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
                const SizedBox(height: 12),
                const Divider(height: 1, thickness: 1.5),
                const SizedBox(height: 8),
                Text(
                  Tr.lastEvents,
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: OfficeColors.textMuted,
                  ),
                ),
                const SizedBox(height: 4),
                if (own.isEmpty)
                  const Text(
                    Tr.noEvents,
                    style: TextStyle(color: OfficeColors.textFaint),
                  )
                else
                  for (final event in own) EventRow(event, showSeat: false),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _header() {
    return Row(
      children: [
        Container(
          width: 12,
          height: 12,
          decoration: BoxDecoration(
            color: OfficeColors.seat(seat.seat),
            borderRadius: BorderRadius.circular(3),
            border: Border.all(color: OfficeColors.outline, width: 1.5),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            Tr.seatName(seat.seat),
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
          ),
        ),
        IconButton(
          key: closeButtonKey,
          tooltip: Tr.close,
          onPressed: onClose,
          icon: const Icon(Icons.close_rounded, size: 20),
        ),
      ],
    );
  }
}

class _StateChip extends StatelessWidget {
  const _StateChip({required this.visual});

  final SeatVisual visual;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.centerLeft,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          color: OfficeColors.surfaceRaised,
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: OfficeColors.outline, width: 1.5),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 8,
              height: 8,
              decoration: BoxDecoration(
                color: OfficeColors.visual(visual),
                shape: BoxShape.circle,
                border: Border.all(color: OfficeColors.outline, width: 1.5),
              ),
            ),
            const SizedBox(width: 6),
            Text(Tr.visualLabel(visual), style: const TextStyle(fontSize: 12)),
          ],
        ),
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  const _InfoRow(this.label, this.value, {this.mono = false});

  final String label;
  final String value;
  final bool mono;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 64,
            child: Text(
              label,
              style: const TextStyle(
                fontSize: 12,
                color: OfficeColors.textFaint,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: TextStyle(
                fontSize: 13,
                fontFamily: mono ? 'monospace' : null,
                fontFamilyFallback: mono ? OfficeFonts.monoFallback : null,
              ),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }
}
