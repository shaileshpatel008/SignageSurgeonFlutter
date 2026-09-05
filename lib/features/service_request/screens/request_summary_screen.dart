import 'dart:io';
import 'package:flutter/material.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/constants/app_routes.dart';

class RequestSummaryScreen extends StatelessWidget {
  const RequestSummaryScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final args = ModalRoute.of(context)!.settings.arguments as Map<String, dynamic>? ?? {};

    final String category    = args['category']    ?? '';
    final String description = args['description'] ?? '';
    final String priority    = args['priority']    ?? 'Normal';
    final String siteName    = args['siteName']    ?? '';
    final String address     = args['address']     ?? '';
    final List<File> photos  = (args['photos']  as List?)?.cast<File>() ?? [];
    final File? video        = args['video'] as File?;

    final String serviceLabel = _formatCategory(category);
    final String locationLabel = [siteName, address]
        .where((s) => s.isNotEmpty).join(', ');
    final String mediaLabel =
        '${photos.length} Photo${photos.length == 1 ? '' : 's'}'
        '${video != null ? ', 1 Video' : ''}';

    return Scaffold(
      backgroundColor: AppColors.offWhite,
      appBar: AppBar(
        backgroundColor: AppColors.offWhite,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded, color: AppColors.navy),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text(
          'Request Summary',
          style: TextStyle(
            color: AppColors.navy,
            fontSize: 18,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // ── Instruction ───────────────────────────────────────
                    const Text(
                      'Please review your request',
                      style: TextStyle(
                        color: AppColors.grey,
                        fontSize: 13,
                      ),
                    ),
                    const SizedBox(height: 20),

                    // ── Summary card ──────────────────────────────────────
                    Container(
                      width: double.infinity,
                      decoration: BoxDecoration(
                        color: AppColors.white,
                        borderRadius: BorderRadius.circular(16),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withOpacity(0.06),
                            blurRadius: 10,
                            offset: const Offset(0, 3),
                          ),
                        ],
                      ),
                      child: Column(
                        children: [
                          _SummaryRow(
                            icon: Icons.build_rounded,
                            title: 'Service',
                            value: serviceLabel.isEmpty
                                ? 'Not selected'
                                : serviceLabel,
                            isFirst: true,
                          ),
                          _Divider(),
                          _SummaryRow(
                            icon: Icons.error_outline_rounded,
                            title: 'Problem',
                            value: description.isEmpty
                                ? 'No description'
                                : description,
                          ),
                          _Divider(),
                          _SummaryRow(
                            icon: Icons.flag_rounded,
                            title: 'Priority',
                            value: priority,
                            valueBadge: priority == 'Emergency',
                          ),
                          _Divider(),
                          _SummaryRow(
                            icon: Icons.location_on_rounded,
                            title: 'Location',
                            value: locationLabel.isEmpty
                                ? 'Not set'
                                : locationLabel,
                          ),
                          _Divider(),
                          _SummaryRow(
                            icon: Icons.photo_library_rounded,
                            title: 'Photos / Videos',
                            value: mediaLabel,
                            isLast: true,
                          ),
                        ],
                      ),
                    ),

                    // ── Photo strip ───────────────────────────────────────
                    if (photos.isNotEmpty) ...[
                      const SizedBox(height: 24),
                      const Text(
                        'Uploaded Photos',
                        style: TextStyle(
                          color: AppColors.navy,
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 12),
                      SizedBox(
                        height: 80,
                        child: ListView.separated(
                          scrollDirection: Axis.horizontal,
                          itemCount: photos.length,
                          separatorBuilder: (_, __) =>
                              const SizedBox(width: 10),
                          itemBuilder: (ctx, i) => GestureDetector(
                            onTap: () => Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) => _FullScreenPhoto(
                                    file: photos[i]),
                              ),
                            ),
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(10),
                              child: Image.file(
                                photos[i],
                                width: 80,
                                height: 80,
                                fit: BoxFit.cover,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],

                    // ── Video row ─────────────────────────────────────────
                    if (video != null) ...[
                      const SizedBox(height: 20),
                      const Text(
                        'Uploaded Video',
                        style: TextStyle(
                          color: AppColors.navy,
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 12),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 14, vertical: 12),
                        decoration: BoxDecoration(
                          color: AppColors.white,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                              color: AppColors.yellow.withOpacity(0.4)),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withOpacity(0.05),
                              blurRadius: 8,
                              offset: const Offset(0, 2),
                            ),
                          ],
                        ),
                        child: Row(
                          children: [
                            Container(
                              width: 38, height: 38,
                              decoration: BoxDecoration(
                                color: AppColors.yellow.withOpacity(0.18),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: const Icon(
                                  Icons.play_circle_fill_rounded,
                                  color: AppColors.yellowDark, size: 22),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Text(
                                video.path.split('/').last,
                                style: const TextStyle(
                                    color: AppColors.navy, fontSize: 13),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            const Icon(Icons.check_circle_rounded,
                                color: AppColors.green, size: 18),
                          ],
                        ),
                      ),
                    ],

                    const SizedBox(height: 20),

                    // ── Terms note ────────────────────────────────────────
                    Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: AppColors.yellow.withOpacity(0.10),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                            color: AppColors.yellow.withOpacity(0.3)),
                      ),
                      child: const Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Icon(Icons.info_outline_rounded,
                              color: AppColors.yellowDark, size: 16),
                          SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              'By submitting this request, you confirm that the '
                              'information provided is accurate and site access '
                              'will be made available for inspection.',
                              style: TextStyle(
                                  color: Color(0xFF6B7280), fontSize: 12,
                                  height: 1.5),
                            ),
                          ),
                        ],
                      ),
                    ),

                    const SizedBox(height: 16),
                  ],
                ),
              ),
            ),

            // ── Bottom bar ────────────────────────────────────────────────
            Container(
              padding: const EdgeInsets.fromLTRB(20, 14, 20, 20),
              decoration: BoxDecoration(
                color: AppColors.white,
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.06),
                    blurRadius: 12,
                    offset: const Offset(0, -4),
                  ),
                ],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Edit row
                  GestureDetector(
                    onTap: () {
                      // Go back 2 screens to edit
                      int count = 0;
                      Navigator.popUntil(context, (_) => count++ >= 2);
                    },
                    child: const Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.edit_rounded, color: AppColors.grey, size: 14),
                        SizedBox(width: 6),
                        Text(
                          'Edit Request',
                          style: TextStyle(
                              color: AppColors.grey, fontSize: 13,
                              decoration: TextDecoration.underline,
                              decorationColor: AppColors.grey),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 14),
                  SizedBox(
                    width: double.infinity,
                    height: 54,
                    child: ElevatedButton(
                      onPressed: () {
                        Navigator.pushNamed(context, AppRoutes.visitCharge,
                            arguments: args);
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.yellow,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                        elevation: 0,
                      ),
                      child: const Text(
                        'Submit Request',
                        style: TextStyle(
                          color: AppColors.navy,
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _formatCategory(String raw) {
    switch (raw.toLowerCase()) {
      case 'repairing':    return 'LED Signage Repair';
      case 'rebranding':   return 'Rebranding';
      case 'new_signage':  return 'New Signage';
      case 'cleaning':     return 'Signage Cleaning';
      default:             return raw;
    }
  }
}

// ============================================================================
//  Supporting widgets
// ============================================================================

class _SummaryRow extends StatelessWidget {
  final IconData icon;
  final String title;
  final String value;
  final bool isFirst;
  final bool isLast;
  final bool valueBadge;

  const _SummaryRow({
    required this.icon,
    required this.title,
    required this.value,
    this.isFirst  = false,
    this.isLast   = false,
    this.valueBadge = false,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(
        16, isFirst ? 18 : 14, 16, isLast ? 18 : 14),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 36, height: 36,
            decoration: BoxDecoration(
              color: AppColors.yellow.withOpacity(0.15),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(icon, color: AppColors.yellowDark, size: 18),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                      color: AppColors.grey, fontSize: 11,
                      fontWeight: FontWeight.w500),
                ),
                const SizedBox(height: 4),
                valueBadge
                    ? Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                          color: AppColors.red.withOpacity(0.12),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Text(
                          value,
                          style: const TextStyle(
                              color: AppColors.red,
                              fontSize: 13,
                              fontWeight: FontWeight.w600),
                        ),
                      )
                    : Text(
                        value,
                        style: const TextStyle(
                            color: AppColors.navy,
                            fontSize: 14,
                            fontWeight: FontWeight.w500,
                            height: 1.4),
                      ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _Divider extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return const Divider(
      height: 1,
      thickness: 1,
      color: AppColors.greyLight,
      indent: 16,
      endIndent: 16,
    );
  }
}

class _FullScreenPhoto extends StatelessWidget {
  final File file;
  const _FullScreenPhoto({required this.file});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded,
              color: Colors.white),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: Center(
        child: InteractiveViewer(
          child: Image.file(file, fit: BoxFit.contain),
        ),
      ),
    );
  }
}