import 'package:flutter/material.dart';

import '../l10n_tr.dart';
import '../widgets/office_theme.dart';
import 'bubble_sheet.dart';
import 'stations.dart';

/// What the TV shows, in words: one line per usage window with its bar,
/// the percentage and the reset time; a token line for a seat whose CLI
/// reports no limits.
class TvBubble extends StatelessWidget {
  const TvBubble({
    super.key,
    required this.bars,
    required this.onClose,
    this.pointerX = 0.5,
  });

  final List<UsageBar> bars;
  final VoidCallback onClose;
  final double pointerX;

  @override
  Widget build(BuildContext context) {
    return BubbleSheet(
      title: Tr.usageLimits,
      onClose: onClose,
      pointerX: pointerX,
      child: bars.isEmpty
          ? const Text(Tr.noUsage, style: PixelText.muted)
          : Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisSize: MainAxisSize.min,
              children: [for (final bar in bars) _row(bar)],
            ),
    );
  }

  Widget _row(UsageBar bar) {
    final label = bar.dim
        ? '${Tr.seatName(bar.seat)} · ${Tr.tokensOnly}'
        : '${Tr.seatName(bar.seat)} · ${Tr.windowLabel(bar.window)}';
    final value = bar.dim
        ? '${bar.tokens} ${Tr.tokensIn}'
        : '%${(bar.pct * 100).round()}';
    final resets = bar.resetsAt;
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Expanded(child: Text(label, style: PixelText.bodyStrong)),
              Text(value, style: PixelText.body),
            ],
          ),
          const SizedBox(height: 3),
          ClipRRect(
            borderRadius: BorderRadius.circular(3),
            child: LinearProgressIndicator(
              value: bar.pct.clamp(0, 1).toDouble(),
              minHeight: 6,
              backgroundColor: PixelColors.paperEdge,
              color: bar.dim
                  ? PixelColors.inkMuted
                  : OfficeColors.usage(bar.pct),
            ),
          ),
          if (resets != null && !bar.dim)
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Text(Tr.resetsAt(resets), style: PixelText.faint),
            ),
        ],
      ),
    );
  }
}
