import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../theme/app_theme.dart';
import '../constants/app_routes.dart';

/// Shows the user's saved addresses in a bottom sheet. Returns the selected
/// address's data map (matching the `saved_addresses` subcollection schema)
/// or null if the user cancelled / picked nothing.
Future<Map<String, dynamic>?> showSavedAddressPicker(BuildContext context) {
  final user = FirebaseAuth.instance.currentUser;
  if (user == null) return Future.value(null);

  return showModalBottomSheet<Map<String, dynamic>>(
    context: context,
    backgroundColor: AppColors.white,
    isScrollControlled: true,
    shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(22))),
    builder: (sheetContext) => _SavedAddressPickerSheet(uid: user.uid),
  );
}

class _SavedAddressPickerSheet extends StatelessWidget {
  final String uid;
  const _SavedAddressPickerSheet({required this.uid});

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 14, 20, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 40, height: 4,
                decoration: BoxDecoration(color: AppColors.greyLight, borderRadius: BorderRadius.circular(2)),
              ),
            ),
            const SizedBox(height: 18),
            const Text('Select a Saved Address', style: TextStyle(color: AppColors.navy, fontSize: 16, fontWeight: FontWeight.w700)),
            const SizedBox(height: 14),
            ConstrainedBox(
              constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.5),
              child: StreamBuilder<QuerySnapshot>(
                stream: FirebaseFirestore.instance
                    .collection('users')
                    .doc(uid)
                    .collection('saved_addresses')
                    .orderBy('createdAt', descending: true)
                    .snapshots(),
                builder: (context, snapshot) {
                  if (snapshot.connectionState == ConnectionState.waiting) {
                    return const Padding(
                      padding: EdgeInsets.symmetric(vertical: 30),
                      child: Center(child: CircularProgressIndicator(color: AppColors.yellow)),
                    );
                  }
                  final docs = snapshot.data?.docs ?? [];
                  if (docs.isEmpty) {
                    return Padding(
                      padding: const EdgeInsets.symmetric(vertical: 20),
                      child: Column(
                        children: [
                          const Icon(Icons.location_off_outlined, color: AppColors.greyLight, size: 36),
                          const SizedBox(height: 10),
                          const Text('No saved addresses yet', style: TextStyle(color: AppColors.grey, fontSize: 13)),
                          const SizedBox(height: 14),
                          TextButton(
                            onPressed: () {
                              Navigator.pop(context);
                              Navigator.pushNamed(context, AppRoutes.manageAddresses);
                            },
                            child: const Text('Add one from Account → Manage Addresses',
                                style: TextStyle(color: AppColors.yellowDark, fontWeight: FontWeight.w600, fontSize: 12.5)),
                          ),
                        ],
                      ),
                    );
                  }
                  return ListView.separated(
                    shrinkWrap: true,
                    physics: const BouncingScrollPhysics(),
                    itemCount: docs.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 8),
                    itemBuilder: (context, i) {
                      final data = docs[i].data() as Map<String, dynamic>;
                      final label = data['label'] as String? ?? 'Address';
                      final address = data['address'] as String? ?? '';
                      return GestureDetector(
                        onTap: () => Navigator.pop(context, data),
                        child: Container(
                          padding: const EdgeInsets.all(14),
                          decoration: BoxDecoration(
                            color: AppColors.offWhite,
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: AppColors.cardBorder),
                          ),
                          child: Row(
                            children: [
                              Container(
                                width: 36, height: 36,
                                decoration: BoxDecoration(color: AppColors.yellow.withOpacity(0.2), borderRadius: BorderRadius.circular(9)),
                                child: Icon(
                                  label.toLowerCase() == 'home' ? Icons.home_outlined : label.toLowerCase() == 'office' ? Icons.business_outlined : Icons.location_on_outlined,
                                  color: AppColors.yellowDark, size: 18,
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(label, style: const TextStyle(color: AppColors.navy, fontSize: 13, fontWeight: FontWeight.w700)),
                                    const SizedBox(height: 2),
                                    Text(address, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(color: AppColors.grey, fontSize: 11.5, height: 1.3)),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}