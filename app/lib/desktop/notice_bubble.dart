import 'package:flutter/material.dart';

import '../l10n_tr.dart';
import '../state/seat_state.dart';
import '../widgets/office_theme.dart';
import 'bubble_sheet.dart';
import 'folder_name.dart';

/// The small card that pops over the mailbox when a report lands: its title,
/// the folder and the first line of the text. Tapping it opens the mailbox.
class NoticeBubble extends StatelessWidget {
  const NoticeBubble({
    super.key,
    required this.report,
    required this.onTap,
    this.pointerX = 0.5,
  });

  static const double width = 260;

  final OfficeReport report;
  final VoidCallback onTap;
  final double pointerX;

  @override
  Widget build(BuildContext context) {
    final firstLine = report.text
        .split(RegExp(r'\r?\n'))
        .map((l) => l.trim())
        .firstWhere(
          (l) => l.isNotEmpty && !l.startsWith('#'),
          orElse: () => '',
        );
    final folder = report.cwd.isEmpty ? '' : ' · ${folderName(report.cwd)}';
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: BubbleSheet(
        title: report.failed ? Tr.reportFailed : Tr.newReport,
        titleColor: report.failed ? OfficeColors.red : PixelColors.ink,
        onClose: onTap,
        pointerX: pointerX,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              '${report.title}$folder',
              style: PixelText.bodyStrong,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
            if (firstLine.isNotEmpty) ...[
              const SizedBox(height: 3),
              Text(
                firstLine,
                style: PixelText.muted,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ],
        ),
      ),
    );
  }
}
