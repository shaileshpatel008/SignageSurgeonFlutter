import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../../../core/theme/app_theme.dart';

/// Drop this into any tracking screen's "completed" state. It checks
/// whether the customer already rated this specific request and shows
/// either the star-input form (first time) or a read-only summary of
/// what they submitted (every time after).
class RatingCard extends StatefulWidget {
  final String collection; // e.g. "repair_requests"
  final String requestId;
  final String serviceLabel; // e.g. "Repairing", for display only

  const RatingCard({
    super.key,
    required this.collection,
    required this.requestId,
    required this.serviceLabel,
  });

  @override
  State<RatingCard> createState() => _RatingCardState();
}

class _RatingCardState extends State<RatingCard> {
  bool _loading = true;
  Map<String, dynamic>? _existingRating;
  int _selectedStars = 0;
  final _commentController = TextEditingController();
  bool _submitting = false;

  @override
  void initState() {
    super.initState();
    _loadExistingRating();
  }

  @override
  void dispose() {
    _commentController.dispose();
    super.dispose();
  }

  Future<void> _loadExistingRating() async {
    try {
      final query = await FirebaseFirestore.instance
          .collection('ratings')
          .where('requestId', isEqualTo: widget.requestId)
          .limit(1)
          .get();
      if (mounted) {
        setState(() {
          _existingRating = query.docs.isNotEmpty ? query.docs.first.data() : null;
          _loading = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _submit() async {
    if (_selectedStars == 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please select a star rating.')),
      );
      return;
    }
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    setState(() => _submitting = true);
    try {
      await FirebaseFirestore.instance.collection('ratings').add({
        'requestId': widget.requestId,
        'serviceCollection': widget.collection,
        'userId': user.uid,
        'stars': _selectedStars,
        'comment': _commentController.text.trim(),
        'createdAt': FieldValue.serverTimestamp(),
      });
      if (mounted) {
        setState(() {
          _existingRating = {
            'stars': _selectedStars,
            'comment': _commentController.text.trim(),
          };
        });
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Thanks for your feedback!')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Could not submit rating: $e')));
      }
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const SizedBox.shrink();

    if (_existingRating != null) {
      final stars = (_existingRating!['stars'] as num?)?.toInt() ?? 0;
      final comment = _existingRating!['comment'] as String? ?? '';
      return Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: AppColors.white,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: AppColors.cardBorder),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Your Rating', style: TextStyle(color: AppColors.navy, fontSize: 13.5, fontWeight: FontWeight.w700)),
            const SizedBox(height: 8),
            Row(
              children: List.generate(5, (i) => Icon(
                    i < stars ? Icons.star : Icons.star_border,
                    color: AppColors.yellowDark,
                    size: 22,
                  )),
            ),
            if (comment.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(comment, style: const TextStyle(color: AppColors.grey, fontSize: 12.5, height: 1.4)),
            ],
          ],
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.yellowDark.withOpacity(0.4)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('How was your ${widget.serviceLabel} experience?', style: const TextStyle(color: AppColors.navy, fontSize: 14, fontWeight: FontWeight.w700)),
          const SizedBox(height: 12),
          Row(
            children: List.generate(5, (i) {
              final starIndex = i + 1;
              return GestureDetector(
                onTap: () => setState(() => _selectedStars = starIndex),
                child: Padding(
                  padding: const EdgeInsets.only(right: 6),
                  child: Icon(
                    starIndex <= _selectedStars ? Icons.star : Icons.star_border,
                    color: AppColors.yellowDark,
                    size: 30,
                  ),
                ),
              );
            }),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _commentController,
            maxLines: 3,
            decoration: InputDecoration(
              hintText: 'Add a comment (optional)',
              filled: true,
              fillColor: AppColors.offWhite,
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide.none),
              contentPadding: const EdgeInsets.all(12),
            ),
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: _submitting ? null : _submit,
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.yellow,
                foregroundColor: AppColors.navy,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                elevation: 0,
                padding: const EdgeInsets.symmetric(vertical: 12),
              ),
              child: _submitting
                  ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.navy))
                  : const Text('Submit Rating', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
            ),
          ),
        ],
      ),
    );
  }
}