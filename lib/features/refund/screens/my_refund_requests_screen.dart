import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../../../core/theme/app_theme.dart';

class MyRefundRequestsScreen extends StatelessWidget {
  const MyRefundRequestsScreen({super.key});

  static const Map<String, String> _serviceLabels = {
    'repair_requests': 'Repairing',
    'rebranding_requests': 'Rebranding',
    'new_signage_requests': 'New Signage',
    'cleaning_requests': 'Signage Cleaning',
    'amc_requests': 'AMC',
    'sign_shoppy_interests': 'Sign Shoppy',
  };

  static const Map<String, String> _paymentAgainstLabels = {
    'site_visit': 'Site Visit Fee',
    'quotation': 'Quotation Payment',
    'audit': 'Audit Fee',
    'final': 'Final Payment',
  };

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;

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
        title: const Text('My Refund Requests', style: TextStyle(color: AppColors.navy, fontSize: 17, fontWeight: FontWeight.w700)),
      ),
      body: user == null
          ? const Center(child: Text('Please log in', style: TextStyle(color: AppColors.grey)))
          : StreamBuilder<QuerySnapshot>(
              stream: FirebaseFirestore.instance
                  .collection('refund_requests')
                  .where('userId', isEqualTo: user.uid)
                  .snapshots(),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator(color: AppColors.yellow));
                }
                final docs = (snapshot.data?.docs ?? []).toList()
                  ..sort((a, b) {
                    final aTime = (a.data() as Map<String, dynamic>)['createdAt'] as Timestamp?;
                    final bTime = (b.data() as Map<String, dynamic>)['createdAt'] as Timestamp?;
                    if (aTime == null || bTime == null) return 0;
                    return bTime.compareTo(aTime); // descending, newest first
                  });
                if (docs.isEmpty) {
                  return Center(
                    child: Padding(
                      padding: const EdgeInsets.all(32),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Icon(Icons.currency_rupee_outlined, color: AppColors.greyLight, size: 48),
                          const SizedBox(height: 16),
                          const Text('No refund requests yet', style: TextStyle(color: AppColors.navy, fontSize: 15, fontWeight: FontWeight.w700)),
                          const SizedBox(height: 8),
                          const Text(
                            'If you request a refund for any completed service, you\'ll be able to track its status here.',
                            textAlign: TextAlign.center,
                            style: TextStyle(color: AppColors.grey, fontSize: 12.5),
                          ),
                        ],
                      ),
                    ),
                  );
                }
                return ListView.builder(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
                  itemCount: docs.length,
                  itemBuilder: (context, i) {
                    final data = docs[i].data() as Map<String, dynamic>;
                    return _refundCard(data);
                  },
                );
              },
            ),
    );
  }

  Widget _refundCard(Map<String, dynamic> data) {
    final serviceLabel = _serviceLabels[data['serviceCollection']] ?? 'Service';
    final paymentAgainstLabel = _paymentAgainstLabels[data['paymentAgainst']] ?? 'Payment';
    final amount = (data['amount'] as num?)?.toDouble();
    final reason = data['reason'] as String? ?? '';
    final status = data['status'] as String? ?? 'pending';
    final errorMessage = data['errorMessage'] as String?;
    final createdAt = data['createdAt'] as Timestamp?;

    final statusStyle = _statusStyle(status);

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.cardBorder),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 8, offset: const Offset(0, 2))],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Text('$serviceLabel — $paymentAgainstLabel', style: const TextStyle(color: AppColors.navy, fontSize: 14, fontWeight: FontWeight.w700)),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(color: statusStyle.bg, borderRadius: BorderRadius.circular(8)),
                child: Text(statusStyle.label, style: TextStyle(color: statusStyle.fg, fontSize: 10.5, fontWeight: FontWeight.w800)),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            amount != null ? 'Refund Amount: ₹${amount.toStringAsFixed(2)}' : 'Refund Amount: Pending Admin Review',
            style: TextStyle(color: amount != null ? AppColors.navy : AppColors.grey, fontSize: 13, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 6),
          Text(reason, style: const TextStyle(color: AppColors.grey, fontSize: 12.5, height: 1.4)),
          if (errorMessage != null && errorMessage.trim().isNotEmpty) ...[
            const SizedBox(height: 10),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(color: AppColors.red.withOpacity(0.08), borderRadius: BorderRadius.circular(8)),
              child: Text(errorMessage, style: const TextStyle(color: AppColors.red, fontSize: 11.5)),
            ),
          ],
          const SizedBox(height: 10),
          Text(_formatDate(createdAt), style: const TextStyle(color: AppColors.greyLight, fontSize: 10.5)),
        ],
      ),
    );
  }

  ({String label, Color bg, Color fg}) _statusStyle(String status) {
    switch (status) {
      case 'pending':
        return (label: 'PENDING REVIEW', bg: AppColors.yellow.withOpacity(0.15), fg: AppColors.yellowDark);
      case 'ready_to_process':
        return (label: 'APPROVED', bg: AppColors.yellow.withOpacity(0.15), fg: AppColors.yellowDark);
      case 'processing':
        return (label: 'PROCESSING', bg: const Color(0xFF3B5BDB).withOpacity(0.12), fg: const Color(0xFF3B5BDB));
      case 'completed':
        return (label: 'COMPLETED', bg: AppColors.green.withOpacity(0.15), fg: AppColors.green);
      case 'failed':
        return (label: 'FAILED', bg: AppColors.red.withOpacity(0.1), fg: AppColors.red);
      default:
        return (label: status.toUpperCase(), bg: AppColors.greyLight.withOpacity(0.3), fg: AppColors.grey);
    }
  }

  String _formatDate(Timestamp? ts) {
    if (ts == null) return '';
    final dt = ts.toDate();
    const months = ['Jan','Feb','Mar','Apr','May','Jun','Jul','Aug','Sep','Oct','Nov','Dec'];
    return 'Requested ${dt.day} ${months[dt.month - 1]} ${dt.year}';
  }
}