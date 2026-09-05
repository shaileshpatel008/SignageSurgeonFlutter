import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../../../core/theme/app_theme.dart';

class MySupportTicketsScreen extends StatelessWidget {
  const MySupportTicketsScreen({super.key});

  static const Map<String, String> _serviceLabels = {
    'repair_requests': 'Repairing',
    'rebranding_requests': 'Rebranding',
    'new_signage_requests': 'New Signage',
    'cleaning_requests': 'Signage Cleaning',
    'amc_requests': 'AMC',
    'sign_shoppy_interests': 'Sign Shoppy',
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
        title: const Text('My Support Tickets', style: TextStyle(color: AppColors.navy, fontSize: 17, fontWeight: FontWeight.w700)),
      ),
      body: user == null
          ? const Center(child: Text('Please log in', style: TextStyle(color: AppColors.grey)))
          : StreamBuilder<QuerySnapshot>(
              // No orderBy alongside this where() — avoids requiring a
              // composite index (same fix applied to My Refund Requests).
              // Sorted client-side below instead.
              stream: FirebaseFirestore.instance
                  .collection('support_tickets')
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
                    return bTime.compareTo(aTime);
                  });
                if (docs.isEmpty) {
                  return Center(
                    child: Padding(
                      padding: const EdgeInsets.all(32),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Icon(Icons.support_agent_outlined, color: AppColors.greyLight, size: 48),
                          const SizedBox(height: 16),
                          const Text('No support tickets yet', style: TextStyle(color: AppColors.navy, fontSize: 15, fontWeight: FontWeight.w700)),
                          const SizedBox(height: 8),
                          const Text(
                            'If you report a problem with any completed service, you\'ll be able to track it here.',
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
                    return _ticketCard(data);
                  },
                );
              },
            ),
    );
  }

  Widget _ticketCard(Map<String, dynamic> data) {
    final serviceLabel = _serviceLabels[data['serviceCollection']] ?? 'Service';
    final description = data['description'] as String? ?? '';
    final status = data['status'] as String? ?? 'open';
    final adminResponse = data['adminResponse'] as String?;
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
              Expanded(child: Text(serviceLabel, style: const TextStyle(color: AppColors.navy, fontSize: 14, fontWeight: FontWeight.w700))),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(color: statusStyle.bg, borderRadius: BorderRadius.circular(8)),
                child: Text(statusStyle.label, style: TextStyle(color: statusStyle.fg, fontSize: 10.5, fontWeight: FontWeight.w800)),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(description, style: const TextStyle(color: AppColors.grey, fontSize: 12.5, height: 1.4)),
          if (adminResponse != null && adminResponse.trim().isNotEmpty) ...[
            const SizedBox(height: 12),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(color: AppColors.green.withOpacity(0.08), borderRadius: BorderRadius.circular(8)),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Our Response', style: TextStyle(color: AppColors.green, fontSize: 10.5, fontWeight: FontWeight.w800)),
                  const SizedBox(height: 4),
                  Text(adminResponse, style: const TextStyle(color: AppColors.navy, fontSize: 12.5, height: 1.4)),
                ],
              ),
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
      case 'open':
        return (label: 'OPEN', bg: AppColors.yellow.withOpacity(0.15), fg: AppColors.yellowDark);
      case 'in_progress':
        return (label: 'IN PROGRESS', bg: const Color(0xFF3B5BDB).withOpacity(0.12), fg: const Color(0xFF3B5BDB));
      case 'resolved':
        return (label: 'RESOLVED', bg: AppColors.green.withOpacity(0.15), fg: AppColors.green);
      default:
        return (label: status.toUpperCase(), bg: AppColors.greyLight.withOpacity(0.3), fg: AppColors.grey);
    }
  }

  String _formatDate(Timestamp? ts) {
    if (ts == null) return '';
    final dt = ts.toDate();
    const months = ['Jan','Feb','Mar','Apr','May','Jun','Jul','Aug','Sep','Oct','Nov','Dec'];
    return 'Reported ${dt.day} ${months[dt.month - 1]} ${dt.year}';
  }
}