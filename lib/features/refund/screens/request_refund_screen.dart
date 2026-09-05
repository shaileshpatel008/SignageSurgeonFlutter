import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../../../core/theme/app_theme.dart';

/// One payment that could be refunded — some services have exactly one
/// (Cleaning, Sign Shoppy), others have two (Repairing/Rebranding/New
/// Signage's site-visit + quotation payments, AMC's audit + final
/// payments). The customer picks which one(s) this request covers.
///
/// `amount` is kept here (tracking screens already compute it) but is
/// intentionally never shown to the customer or written to Firestore —
/// the admin decides and enters the actual refund amount themselves after
/// reviewing the reason against policy/T&Cs.
class RefundablePayment {
  final String label; // shown to the customer, e.g. "Final Quotation Payment"
  final String paymentAgainst; // "site_visit" | "quotation" | "audit" | "final"
  final String razorpayPaymentId;
  final double amount;

  const RefundablePayment({
    required this.label,
    required this.paymentAgainst,
    required this.razorpayPaymentId,
    required this.amount,
  });
}

class RequestRefundScreen extends StatefulWidget {
  final String collection; // e.g. "repair_requests"
  final String requestId;
  final String serviceLabel; // e.g. "Repairing — Directional Signage", for display only
  final List<RefundablePayment> paymentOptions;

  const RequestRefundScreen({
    super.key,
    required this.collection,
    required this.requestId,
    required this.serviceLabel,
    required this.paymentOptions,
  });

  @override
  State<RequestRefundScreen> createState() => _RequestRefundScreenState();
}

class _RequestRefundScreenState extends State<RequestRefundScreen> {
  late Set<String> _selectedPaymentAgainst; // paymentAgainst values the customer checked
  final _reasonController = TextEditingController();
  bool _submitting = false;

  @override
  void initState() {
    super.initState();
    // Pre-select everything by default — customer can uncheck what doesn't apply.
    _selectedPaymentAgainst = widget.paymentOptions.map((p) => p.paymentAgainst).toSet();
  }

  @override
  void dispose() {
    _reasonController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_selectedPaymentAgainst.isEmpty) {
      _showSnack('Please select at least one payment you\'re requesting a refund for.');
      return;
    }
    if (_reasonController.text.trim().isEmpty) {
      _showSnack('Please tell us the reason for this refund request.');
      return;
    }
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    setState(() => _submitting = true);
    try {
      // One document per selected payment — keeps each refund independently
      // reviewable and processable (a request touching two payments might
      // reasonably get approved for one and declined for the other).
      final batch = FirebaseFirestore.instance.batch();
      final selectedPayments = widget.paymentOptions.where((p) => _selectedPaymentAgainst.contains(p.paymentAgainst));

      for (final payment in selectedPayments) {
        final ref = FirebaseFirestore.instance.collection('refund_requests').doc();
        batch.set(ref, {
          'requestId': widget.requestId,
          'serviceCollection': widget.collection,
          'userId': user.uid,
          'paymentAgainst': payment.paymentAgainst,
          'razorpayPaymentId': payment.razorpayPaymentId,
          'reason': _reasonController.text.trim(),
          'status': 'pending',
          'createdAt': FieldValue.serverTimestamp(),
          // Intentionally no `amount` here — the admin sets this after
          // reviewing the reason against policy/T&Cs, before approving.
        });
      }
      await batch.commit();

      if (mounted) {
        Navigator.pop(context);
        _showSnack('Refund request submitted. We\'ll review it and update you here.');
      }
    } catch (e) {
      _showSnack('Could not submit refund request: $e');
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  void _showSnack(String message) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.offWhite,
      appBar: AppBar(
        backgroundColor: AppColors.offWhite,
        elevation: 0,
        centerTitle: true,
        leading: GestureDetector(
          onTap: () => Navigator.pop(context),
          child: Container(
            margin: const EdgeInsets.all(10),
            decoration: BoxDecoration(color: AppColors.white, borderRadius: BorderRadius.circular(10), border: Border.all(color: AppColors.cardBorder)),
            child: const Icon(Icons.arrow_back_ios_new_rounded, color: AppColors.navy, size: 16),
          ),
        ),
        title: const Text('Request Refund', style: TextStyle(color: AppColors.navy, fontSize: 17, fontWeight: FontWeight.w700)),
      ),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(color: AppColors.white, borderRadius: BorderRadius.circular(12), border: Border.all(color: AppColors.cardBorder)),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Request', style: TextStyle(color: AppColors.grey, fontSize: 11.5)),
                const SizedBox(height: 4),
                Text(widget.serviceLabel, style: const TextStyle(color: AppColors.navy, fontSize: 14.5, fontWeight: FontWeight.w700)),
              ],
            ),
          ),
          const SizedBox(height: 20),

          const Text('Which payment(s) is this refund for?', style: TextStyle(color: AppColors.navy, fontSize: 13.5, fontWeight: FontWeight.w700)),
          const SizedBox(height: 4),
          const Text(
            'Select all that apply. Our team will review your reason against policy and confirm which of these are eligible.',
            style: TextStyle(color: AppColors.grey, fontSize: 11.5),
          ),
          const SizedBox(height: 10),
          ...widget.paymentOptions.map((option) {
            final selected = _selectedPaymentAgainst.contains(option.paymentAgainst);
            return Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: GestureDetector(
                onTap: () => setState(() {
                  if (selected) {
                    _selectedPaymentAgainst.remove(option.paymentAgainst);
                  } else {
                    _selectedPaymentAgainst.add(option.paymentAgainst);
                  }
                }),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                  decoration: BoxDecoration(
                    color: selected ? AppColors.yellow.withOpacity(0.12) : AppColors.white,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: selected ? AppColors.yellowDark : AppColors.cardBorder, width: selected ? 1.5 : 1),
                  ),
                  child: Row(
                    children: [
                      Icon(selected ? Icons.check_box : Icons.check_box_outline_blank, color: selected ? AppColors.yellowDark : AppColors.greyLight, size: 20),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(option.label, style: const TextStyle(color: AppColors.navy, fontSize: 13.5, fontWeight: FontWeight.w700)),
                      ),
                    ],
                  ),
                ),
              ),
            );
          }),
          const SizedBox(height: 20),

          const Text('Reason for Refund', style: TextStyle(color: AppColors.navy, fontSize: 13.5, fontWeight: FontWeight.w700)),
          const SizedBox(height: 10),
          TextField(
            controller: _reasonController,
            maxLines: 5,
            decoration: InputDecoration(
              hintText: 'Please explain why you\'re requesting this refund...',
              filled: true,
              fillColor: AppColors.white,
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: AppColors.cardBorder)),
              enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: AppColors.cardBorder)),
              focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: AppColors.yellowDark)),
              contentPadding: const EdgeInsets.all(14),
            ),
          ),
          const SizedBox(height: 8),
          const Text(
            'Refund requests are reviewed by our team before being processed. Eligibility and the refund amount are '
            'determined based on our Terms & Conditions and the reason provided — you\'ll be able to track the status '
            'and outcome of this request from "My Refund Requests" in your Account.',
            style: TextStyle(color: AppColors.grey, fontSize: 11.5, height: 1.4),
          ),
          const SizedBox(height: 28),
          SizedBox(
            width: double.infinity,
            height: 52,
            child: ElevatedButton(
              onPressed: _submitting ? null : _submit,
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.yellow,
                foregroundColor: AppColors.navy,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                elevation: 0,
              ),
              child: _submitting
                  ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.navy))
                  : const Text('Submit Refund Request', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 14.5)),
            ),
          ),
        ],
      ),
    );
  }
}