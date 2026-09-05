import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/constants/app_routes.dart';

class NotificationsScreen extends StatelessWidget {
  const NotificationsScreen({super.key});

  static const Map<String, String> _dedicatedTrackingRoutes = {
    'cleaning_requests': AppRoutes.cleaningTracking,
    'amc_requests': AppRoutes.amcTracking,
    'sign_shoppy_interests': AppRoutes.signShoppyTracking,
  };

  void _openSource(BuildContext context, String? collection, String? requestId) {
    if (collection == null || requestId == null) return;
    final dedicated = _dedicatedTrackingRoutes[collection];
    if (dedicated != null) {
      Navigator.pushNamed(context, dedicated, arguments: requestId);
    } else {
      Navigator.pushNamed(context, AppRoutes.requestTracking,
          arguments: {'collection': collection, 'requestId': requestId});
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;

    return Scaffold(
      backgroundColor: AppColors.offWhite,
      appBar: _buildAppBar(context, user?.uid),
      body: user == null
          ? const Center(child: Text('Please log in', style: TextStyle(color: AppColors.grey)))
          : StreamBuilder<QuerySnapshot>(
              stream: FirebaseFirestore.instance
                  .collection('users')
                  .doc(user.uid)
                  .collection('notifications')
                  .orderBy('createdAt', descending: true)
                  .limit(100)
                  .snapshots(),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator(color: AppColors.yellow));
                }
                final docs = snapshot.data?.docs ?? [];
                if (docs.isEmpty) {
                  return _emptyState();
                }
                return ListView.builder(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
                  itemCount: docs.length,
                  itemBuilder: (context, i) {
                    final doc = docs[i];
                    final data = doc.data() as Map<String, dynamic>;
                    return _notificationCard(context, user.uid, doc.id, data);
                  },
                );
              },
            ),
    );
  }

  PreferredSizeWidget _buildAppBar(BuildContext context, String? uid) {
    return AppBar(
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
      title: const Text('Notifications', style: TextStyle(color: AppColors.navy, fontSize: 17, fontWeight: FontWeight.w700)),
      actions: [
        if (uid != null)
          TextButton(
            onPressed: () => _markAllRead(uid),
            child: const Text('Mark all read', style: TextStyle(color: AppColors.yellowDark, fontSize: 12, fontWeight: FontWeight.w600)),
          ),
      ],
    );
  }

  Future<void> _markAllRead(String uid) async {
    final query = await FirebaseFirestore.instance
        .collection('users')
        .doc(uid)
        .collection('notifications')
        .where('read', isEqualTo: false)
        .get();
    final batch = FirebaseFirestore.instance.batch();
    for (final doc in query.docs) {
      batch.update(doc.reference, {'read': true});
    }
    await batch.commit();
  }

  Future<void> _deleteNotification(BuildContext context, String uid, String docId) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: AppColors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Delete this notification?', style: TextStyle(color: AppColors.navy, fontSize: 16)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel', style: TextStyle(color: AppColors.grey))),
          TextButton(onPressed: () => Navigator.pop(context, true), child: const Text('Delete', style: TextStyle(color: AppColors.red, fontWeight: FontWeight.w700))),
        ],
      ),
    );
    if (confirmed != true) return;
    await FirebaseFirestore.instance
        .collection('users')
        .doc(uid)
        .collection('notifications')
        .doc(docId)
        .delete();
  }

  Widget _emptyState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.notifications_none_outlined, color: AppColors.greyLight, size: 48),
            const SizedBox(height: 16),
            const Text('No notifications yet', style: TextStyle(color: AppColors.navy, fontSize: 15, fontWeight: FontWeight.w700)),
            const SizedBox(height: 8),
            const Text('Updates about your requests will appear here.',
                textAlign: TextAlign.center, style: TextStyle(color: AppColors.grey, fontSize: 12.5)),
          ],
        ),
      ),
    );
  }

  Widget _notificationCard(BuildContext context, String uid, String docId, Map<String, dynamic> data) {
    final title = data['title'] as String? ?? 'Update';
    final body = data['body'] as String? ?? '';
    final read = data['read'] == true;
    final createdAt = data['createdAt'] as Timestamp?;
    final sourceCollection = data['sourceCollection'] as String?;
    final sourceRequestId = data['sourceRequestId'] as String?;

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.white,
        borderRadius: BorderRadius.circular(14),
        border: read ? null : Border.all(color: AppColors.yellowDark.withOpacity(0.4), width: 1),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 8, offset: const Offset(0, 2))],
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          GestureDetector(
            onTap: () async {
              if (!read) {
                await FirebaseFirestore.instance
                    .collection('users')
                    .doc(uid)
                    .collection('notifications')
                    .doc(docId)
                    .update({'read': true});
              }
              if (context.mounted) _openSource(context, sourceCollection, sourceRequestId);
            },
            child: Container(
              width: 40, height: 40,
              decoration: BoxDecoration(
                color: read ? AppColors.greyLight.withOpacity(0.3) : AppColors.yellow.withOpacity(0.2),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(
                read ? Icons.notifications_none_outlined : Icons.notifications_active_outlined,
                color: read ? AppColors.grey : AppColors.yellowDark,
                size: 20,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: GestureDetector(
              onTap: () async {
                if (!read) {
                  await FirebaseFirestore.instance
                      .collection('users')
                      .doc(uid)
                      .collection('notifications')
                      .doc(docId)
                      .update({'read': true});
                }
                if (context.mounted) _openSource(context, sourceCollection, sourceRequestId);
              },
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(title, style: TextStyle(color: AppColors.navy, fontSize: 13.5, fontWeight: read ? FontWeight.w600 : FontWeight.w800)),
                      ),
                      if (!read)
                        Container(width: 8, height: 8, decoration: const BoxDecoration(color: AppColors.yellowDark, shape: BoxShape.circle)),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(body, style: const TextStyle(color: AppColors.grey, fontSize: 12, height: 1.4)),
                  const SizedBox(height: 6),
                  Text(_formatTime(createdAt), style: const TextStyle(color: AppColors.greyLight, fontSize: 10.5)),
                ],
              ),
            ),
          ),
          GestureDetector(
            onTap: () => _deleteNotification(context, uid, docId),
            child: Padding(
              padding: const EdgeInsets.only(left: 8, top: 2),
              child: Icon(Icons.delete_outline, color: AppColors.grey.withOpacity(0.7), size: 20),
            ),
          ),
        ],
      ),
    );
  }

  String _formatTime(Timestamp? ts) {
    if (ts == null) return '';
    final dt = ts.toDate();
    final now = DateTime.now();
    final diff = now.difference(dt);
    if (diff.inMinutes < 1) return 'Just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    if (diff.inDays < 7) return '${diff.inDays}d ago';
    const months = ['Jan','Feb','Mar','Apr','May','Jun','Jul','Aug','Sep','Oct','Nov','Dec'];
    return '${dt.day} ${months[dt.month - 1]} ${dt.year}';
  }
}