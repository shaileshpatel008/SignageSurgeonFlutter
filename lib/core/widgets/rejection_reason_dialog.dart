import 'package:flutter/material.dart';
import '../theme/app_theme.dart';

class RejectionResult {
  final String reason;
  final String? otherText;
  RejectionResult(this.reason, this.otherText);

  /// Combined string ready to save straight into Firestore.
  String get fullReason => reason == 'Other' && otherText != null && otherText!.trim().isNotEmpty
      ? 'Other: ${otherText!.trim()}'
      : reason;
}

const List<String> _rejectionReasons = [
  'Price is High',
  'Scope / Requirement Not Matching',
  'Need Changes in Quotation',
  'Project Postponed',
  'Selected Another Option',
  'Other',
];

/// Shows the standard rejection-reason picker. Returns null if the user
/// cancels, otherwise a [RejectionResult] with the chosen reason (and a
/// required free-text detail if "Other" was picked).
Future<RejectionResult?> showRejectionReasonDialog(BuildContext context) {
  String? selected;
  final otherController = TextEditingController();

  return showDialog<RejectionResult>(
    context: context,
    builder: (dialogContext) => StatefulBuilder(
      builder: (dialogContext, setDialogState) {
        final canSubmit = selected != null && (selected != 'Other' || otherController.text.trim().isNotEmpty);
        return AlertDialog(
          backgroundColor: AppColors.white,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: const Text('Reject Quotation', style: TextStyle(color: AppColors.navy, fontSize: 16, fontWeight: FontWeight.w700)),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Please let us know why:', style: TextStyle(color: AppColors.grey, fontSize: 12.5)),
                const SizedBox(height: 6),
                ..._rejectionReasons.map((r) => RadioListTile<String>(
                      contentPadding: EdgeInsets.zero,
                      dense: true,
                      activeColor: AppColors.yellowDark,
                      title: Text(r, style: const TextStyle(color: AppColors.navy, fontSize: 13)),
                      value: r,
                      groupValue: selected,
                      onChanged: (v) => setDialogState(() => selected = v),
                    )),
                if (selected == 'Other') ...[
                  const SizedBox(height: 6),
                  TextField(
                    controller: otherController,
                    onChanged: (_) => setDialogState(() {}),
                    style: const TextStyle(color: AppColors.navy, fontSize: 13),
                    decoration: InputDecoration(
                      hintText: 'Please specify',
                      hintStyle: const TextStyle(color: AppColors.grey, fontSize: 12.5),
                      filled: true,
                      fillColor: AppColors.offWhite,
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide.none),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                    ),
                  ),
                ],
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('Cancel', style: TextStyle(color: AppColors.grey)),
            ),
            TextButton(
              onPressed: canSubmit
                  ? () => Navigator.pop(
                        dialogContext,
                        RejectionResult(selected!, selected == 'Other' ? otherController.text.trim() : null),
                      )
                  : null,
              child: const Text('Submit', style: TextStyle(color: AppColors.red, fontWeight: FontWeight.w700)),
            ),
          ],
        );
      },
    ),
  );
}