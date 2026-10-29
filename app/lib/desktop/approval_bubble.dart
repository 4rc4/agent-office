import 'package:flutter/material.dart';

import '../l10n_tr.dart';
import '../state/seat_state.dart';
import '../widgets/office_theme.dart';
import 'bubble_sheet.dart';

/// The balloon over a character that asked for permission: what the tool
/// wants to do, "İzin ver" and "Reddet". The answer goes back to the CLI
/// through [onAnswer].
class ApprovalBubble extends StatelessWidget {
  const ApprovalBubble({
    super.key,
    required this.request,
    required this.onAnswer,
    this.pointerX = 0.5,
  });

  static const Key allowKey = Key('approval.allow');
  static const Key denyKey = Key('approval.deny');
  static const double width = 300;

  final ApprovalRequest request;
  final void Function(bool allow) onAnswer;
  final double pointerX;

  @override
  Widget build(BuildContext context) {
    final summary = request.summary.replaceFirst(RegExp(r'^approval:\s*'), '');
    return BubbleSheet(
      title: '${Tr.seatName(request.seat)} · ${Tr.permissionTitle}',
      titleColor: OfficeColors.red,
      onClose: () => onAnswer(false),
      pointerX: pointerX,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            summary,
            style: PixelText.body,
            maxLines: 4,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              const Spacer(),
              SheetButton(
                key: ApprovalBubble.denyKey,
                label: Tr.deny,
                icon: Icons.block_rounded,
                onPressed: () => onAnswer(false),
              ),
              const SizedBox(width: 6),
              SheetButton(
                key: ApprovalBubble.allowKey,
                label: Tr.allow,
                icon: Icons.check_rounded,
                filled: true,
                onPressed: () => onAnswer(true),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
