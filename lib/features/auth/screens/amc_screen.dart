import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/constants/app_routes.dart';

class AmcScreen extends StatelessWidget {
  const AmcScreen({super.key});

  String _formatDate(dynamic timestamp) {
    if (timestamp == null) return 'N/A';
    final dt = (timestamp as Timestamp).toDate();
    const months = [
      'Jan','Feb','Mar','Apr','May','Jun',
      'Jul','Aug','Sep','Oct','Nov','Dec'
    ];
    return '${dt.day} ${months[dt.month - 1]} ${dt.year}';
  }

  int _daysLeft(dynamic timestamp) {
    if (timestamp == null) return 0;
    final dt = (timestamp as Timestamp).toDate();
    return dt.difference(DateTime.now()).inDays;
  }

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.dark,
      child: Scaffold(
        backgroundColor: AppColors.offWhite,
        body: SafeArea(
          child: Column(
            children: [
              // ── HEADER ──
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
                child: Row(
                  children: [
                    GestureDetector(
                      onTap: () => Navigator.pop(context),
                      child: Container(
                        width: 40,
                        height: 40,
                        decoration: BoxDecoration(
                          color: AppColors.white,
                          borderRadius: BorderRadius.circular(12),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withOpacity(0.06),
                              blurRadius: 8,
                              offset: const Offset(0, 2),
                            ),
                          ],
                        ),
                        child: const Icon(Icons.arrow_back_ios_new,
                            color: AppColors.navy, size: 18),
                      ),
                    ),
                    const SizedBox(width: 14),
                    const Expanded(
                      child: Text(
                        'AMC Plans',
                        style: TextStyle(
                          color: AppColors.navy,
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 20),

              Expanded(
                child: SingleChildScrollView(
                  physics: const BouncingScrollPhysics(),
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 32),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // ── EXPLORE CTA ──
                      GestureDetector(
                        onTap: () => Navigator.pushNamed(
                            context, AppRoutes.amcPlans),
                        child: Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(20),
                          decoration: BoxDecoration(
                            gradient: const LinearGradient(
                              colors: [
                                Color(0xFF1A3A6B),
                                Color(0xFF0F2547)
                              ],
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                            ),
                            borderRadius: BorderRadius.circular(16),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withOpacity(0.15),
                                blurRadius: 14,
                                offset: const Offset(0, 6),
                              ),
                            ],
                          ),
                          child: Row(
                            children: [
                              Container(
                                width: 50,
                                height: 50,
                                decoration: BoxDecoration(
                                  color: AppColors.yellow,
                                  shape: BoxShape.circle,
                                ),
                                child: const Icon(Icons.shield_outlined,
                                    color: AppColors.navy, size: 26),
                              ),
                              const SizedBox(width: 16),
                              const Expanded(
                                child: Column(
                                  crossAxisAlignment:
                                      CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      'Explore AMC Plans',
                                      style: TextStyle(
                                        color: Colors.white,
                                        fontSize: 15,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                    SizedBox(height: 4),
                                    Text(
                                      'Annual maintenance for your signage.\nProtect your investment all year long.',
                                      style: TextStyle(
                                          color: Colors.white70,
                                          fontSize: 12,
                                          height: 1.5),
                                    ),
                                  ],
                                ),
                              ),
                              const Icon(Icons.arrow_forward_ios,
                                  color: AppColors.yellow, size: 16),
                            ],
                          ),
                        ),
                      ),

                      const SizedBox(height: 28),

                      if (user == null) ...[
                        _emptyState('Please log in to view your AMC plans'),
                      ] else ...[
                        // ── ACTIVE PLANS ──
                        _sectionLabel('Active Plans'),
                        const SizedBox(height: 14),
                        StreamBuilder<QuerySnapshot>(
                          stream: FirebaseFirestore.instance
                              .collection('amc_contracts')
                              .where('userId', isEqualTo: user.uid)
                              .where('status', isEqualTo: 'active')
                              .snapshots(),
                          builder: (context, snapshot) {
                            if (snapshot.connectionState ==
                                ConnectionState.waiting) {
                              return const Center(
                                child: Padding(
                                  padding: EdgeInsets.all(20),
                                  child: CircularProgressIndicator(
                                      color: AppColors.yellow),
                                ),
                              );
                            }
                            if (!snapshot.hasData ||
                                snapshot.data!.docs.isEmpty) {
                              return _noPlansCard(
                                  'No active AMC plans yet',
                                  'Tap "Explore AMC Plans" above to get started');
                            }
                            return Column(
                              children: snapshot.data!.docs
                                  .map((doc) => _amcCard(
                                      doc.data()
                                          as Map<String, dynamic>,
                                      true))
                                  .toList(),
                            );
                          },
                        ),

                        const SizedBox(height: 28),

                        // ── INACTIVE / EXPIRED ──
                        _sectionLabel('Past Plans'),
                        const SizedBox(height: 14),
                        StreamBuilder<QuerySnapshot>(
                          stream: FirebaseFirestore.instance
                              .collection('amc_contracts')
                              .where('userId', isEqualTo: user.uid)
                              .where('status',
                                  whereIn: ['expired', 'inactive'])
                              .snapshots(),
                          builder: (context, snapshot) {
                            if (snapshot.connectionState ==
                                ConnectionState.waiting) {
                              return const SizedBox.shrink();
                            }
                            if (!snapshot.hasData ||
                                snapshot.data!.docs.isEmpty) {
                              return _noPlansCard(
                                  'No past plans', null);
                            }
                            return Column(
                              children: snapshot.data!.docs
                                  .map((doc) => _amcCard(
                                      doc.data()
                                          as Map<String, dynamic>,
                                      false))
                                  .toList(),
                            );
                          },
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _sectionLabel(String title) {
    return Row(
      children: [
        Container(
          width: 3,
          height: 16,
          decoration: BoxDecoration(
            color: AppColors.yellow,
            borderRadius: BorderRadius.circular(2),
          ),
        ),
        const SizedBox(width: 8),
        Text(
          title,
          style: const TextStyle(
            color: AppColors.navy,
            fontSize: 15,
            fontWeight: FontWeight.bold,
          ),
        ),
      ],
    );
  }

  Widget _amcCard(Map<String, dynamic> data, bool isActive) {
    final siteName = data['siteName'] ?? 'Signage AMC';
    final planName = data['planName'] ?? 'Standard Plan';
    final expiryTimestamp = data['expiryDate'];
    final startTimestamp = data['startDate'];
    final daysLeft = _daysLeft(expiryTimestamp);
    final expiryStr = _formatDate(expiryTimestamp);
    final startStr = _formatDate(startTimestamp);
    final isExpiringSoon = isActive && daysLeft <= 30;

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
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
        border: isExpiringSoon
            ? Border.all(color: AppColors.red.withOpacity(0.35), width: 1)
            : null,
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: isActive
                        ? AppColors.yellow
                        : AppColors.greyLight,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(
                    Icons.shield_outlined,
                    color: isActive ? AppColors.navy : AppColors.grey,
                    size: 22,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        siteName,
                        style: const TextStyle(
                          color: AppColors.navy,
                          fontSize: 14,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      Text(
                        planName,
                        style: const TextStyle(
                            color: AppColors.grey, fontSize: 12),
                      ),
                    ],
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 10, vertical: 5),
                  decoration: BoxDecoration(
                    color: isActive
                        ? AppColors.green.withOpacity(0.13)
                        : AppColors.greyLight,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    isActive ? 'ACTIVE' : 'EXPIRED',
                    style: TextStyle(
                      color: isActive ? AppColors.green : AppColors.grey,
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 0.5,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            const Divider(color: AppColors.greyLight, height: 1),
            const SizedBox(height: 14),
            Row(
              children: [
                _infoChip(Icons.calendar_today_outlined, 'Start',
                    startStr),
                const SizedBox(width: 12),
                _infoChip(
                  Icons.event_outlined,
                  isActive ? 'Expires' : 'Expired',
                  expiryStr,
                  valueColor: isExpiringSoon ? AppColors.red : null,
                ),
                if (isActive) ...[
                  const SizedBox(width: 12),
                  _infoChip(
                    Icons.timelapse_outlined,
                    'Days Left',
                    '$daysLeft',
                    valueColor: isExpiringSoon
                        ? AppColors.red
                        : AppColors.green,
                  ),
                ],
              ],
            ),
            if (isExpiringSoon) ...[
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: AppColors.red.withOpacity(0.08),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                      color: AppColors.red.withOpacity(0.3), width: 1),
                ),
                child: const Row(
                  children: [
                    Icon(Icons.warning_amber_outlined,
                        color: AppColors.red, size: 16),
                    SizedBox(width: 8),
                    Text(
                      'Expiring soon — contact us to renew',
                      style: TextStyle(
                          color: AppColors.red,
                          fontSize: 12,
                          fontWeight: FontWeight.w600),
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _infoChip(IconData icon, String label, String value,
      {Color? valueColor}) {
    return Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: AppColors.grey, size: 12),
              const SizedBox(width: 4),
              Text(label,
                  style: const TextStyle(
                      color: AppColors.grey, fontSize: 10)),
            ],
          ),
          const SizedBox(height: 3),
          Text(
            value,
            style: TextStyle(
              color: valueColor ?? AppColors.navy,
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  Widget _noPlansCard(String title, String? subtitle) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppColors.white,
        borderRadius: BorderRadius.circular(14),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        children: [
          const Icon(Icons.shield_outlined,
              color: AppColors.greyLight, size: 32),
          const SizedBox(height: 10),
          Text(title,
              style:
                  const TextStyle(color: AppColors.grey, fontSize: 13)),
          if (subtitle != null) ...[
            const SizedBox(height: 4),
            Text(subtitle,
                textAlign: TextAlign.center,
                style: const TextStyle(
                    color: AppColors.greyLight, fontSize: 11)),
          ],
        ],
      ),
    );
  }

  Widget _emptyState(String message) {
    return Center(
      child: Text(message,
          style: const TextStyle(color: AppColors.grey, fontSize: 14)),
    );
  }
}