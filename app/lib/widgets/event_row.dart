import 'package:flutter/material.dart';
import 'package:office_core/office_core.dart';

import '../l10n_tr.dart';
import 'office_theme.dart';

/// `HH:mm:ss` of [time], local clock.
String formatClock(DateTime time) {
  final t = time.toLocal();
  String two(int n) => n.toString().padLeft(2, '0');
  return '${two(t.hour)}:${two(t.minute)}:${two(t.second)}';
}

/// First line of [text], cut to [max] characters with an ellipsis.
String firstLine(String text, {int max = 120}) {
  final line = text
      .split(RegExp(r'\r?\n'))
      .map((l) => l.trim())
      .firstWhere((l) => l.isNotEmpty, orElse: () => '');
  if (line.length <= max) return line;
  return '${line.substring(0, max - 1)}…';
}

/// A short form of a session reference: the first 8 characters.
String shortRef(String ref) => ref.length <= 10 ? ref : ref.substring(0, 8);

/// A small solid tag with the desk's name in its colour.
class SeatTag extends StatelessWidget {
  const SeatTag(this.seat, {super.key});

  final Seat seat;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
      decoration: BoxDecoration(
        color: OfficeColors.seat(seat),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: OfficeColors.outline, width: 1.5),
      ),
      child: Text(
        Tr.seatName(seat),
        style: const TextStyle(
          color: OfficeColors.ink,
          fontSize: 11,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

/// One line of the event log: time, optional desk tag, kind, summary.
class EventRow extends StatelessWidget {
  const EventRow(this.event, {super.key, this.showSeat = true});

  final AgentEvent event;

  /// Hide the desk tag in lists that already belong to one desk.
  final bool showSeat;

  @override
  Widget build(BuildContext context) {
    const mono = TextStyle(
      fontFamily: 'monospace',
      fontFamilyFallback: OfficeFonts.monoFallback,
      fontSize: 11,
      color: OfficeColors.textFaint,
    );
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(formatClock(event.timestamp), style: mono),
          const SizedBox(width: 8),
          if (showSeat) ...[SeatTag(event.seat), const SizedBox(width: 8)],
          SizedBox(
            width: 72,
            child: Text(
              Tr.eventKindLabel(event.kind),
              style: const TextStyle(
                fontSize: 12,
                color: OfficeColors.textMuted,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          Expanded(
            child: Text(
              firstLine(event.summary),
              style: const TextStyle(fontSize: 12, color: OfficeColors.text),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }
}
