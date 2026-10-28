import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../l10n_tr.dart';
import '../state/office_model.dart';
import 'office_theme.dart';

/// Opens the mailbox with the last report; follows [model] while open.
Future<void> showMailboxDialog(BuildContext context, OfficeModel model) {
  return showDialog<void>(
    context: context,
    builder: (context) => Dialog(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 640, maxHeight: 640),
        child: ListenableBuilder(
          listenable: model,
          builder: (context, _) => MailboxDialog(
            report: model.snapshot.lastReport,
            onClose: () => Navigator.of(context).pop(),
          ),
        ),
      ),
    ),
  );
}

/// The last finished root's report as selectable plain text (markdown is
/// shown as written, no renderer) with a copy button.
class MailboxDialog extends StatelessWidget {
  const MailboxDialog({super.key, required this.report, this.onClose});

  static const Key copyButtonKey = Key('mailbox.copy');
  static const Key closeButtonKey = Key('mailbox.close');
  static const Key reportTextKey = Key('mailbox.report');

  final String? report;
  final VoidCallback? onClose;

  bool get _hasReport => report != null && report!.trim().isNotEmpty;

  Future<void> _copy(BuildContext context) async {
    await Clipboard.setData(ClipboardData(text: report ?? ''));
    if (!context.mounted) return;
    ScaffoldMessenger.maybeOf(context)?.showSnackBar(
      const SnackBar(content: Text(Tr.copied), duration: Duration(seconds: 2)),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 12, 16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              const Icon(Icons.mail_outline_rounded, size: 20),
              const SizedBox(width: 8),
              const Expanded(
                child: Text(
                  Tr.mailbox,
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
                ),
              ),
              if (_hasReport)
                OutlinedButton.icon(
                  key: copyButtonKey,
                  onPressed: () => _copy(context),
                  icon: const Icon(Icons.copy_rounded, size: 16),
                  label: const Text(Tr.copy),
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
          const SizedBox(height: 12),
          if (!_hasReport)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 24),
              child: Text(
                Tr.noReport,
                style: TextStyle(color: OfficeColors.textFaint),
              ),
            )
          else
            Flexible(
              child: Container(
                decoration: BoxDecoration(
                  color: OfficeColors.surfaceSunken,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: OfficeColors.outline, width: 1.5),
                ),
                padding: const EdgeInsets.all(12),
                child: SingleChildScrollView(
                  child: SelectableText(
                    report!,
                    key: reportTextKey,
                    style: const TextStyle(fontSize: 13, height: 1.45),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
