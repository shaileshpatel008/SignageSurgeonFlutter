import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/constants/app_routes.dart';

class SignShoppyProductScreen extends StatelessWidget {
  const SignShoppyProductScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final productId = ModalRoute.of(context)?.settings.arguments as String?;

    if (productId == null) {
      return Scaffold(
        backgroundColor: AppColors.offWhite,
        appBar: AppBar(backgroundColor: AppColors.serviceAccent, elevation: 0),
        body: const Center(child: Text('Product not found', style: TextStyle(color: AppColors.grey))),
      );
    }

    return Scaffold(
      backgroundColor: AppColors.offWhite,
      body: StreamBuilder<DocumentSnapshot>(
        stream: FirebaseFirestore.instance.collection('sign_shoppy_products').doc(productId).snapshots(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator(color: AppColors.yellow));
          }
          if (!snapshot.hasData || !snapshot.data!.exists) {
            return const Center(child: Text('This product could not be found.', style: TextStyle(color: AppColors.grey)));
          }
          final data = snapshot.data!.data() as Map<String, dynamic>;
          final imageUrl = data['imageUrl'] as String?;
          final name = data['name'] as String? ?? 'Signage Product';
          final description = data['shortDescription'] as String? ?? '';
          final category = data['category'] as String? ?? '';

          return SafeArea(
            child: Column(
              children: [
                Expanded(
                  child: ListView(
                    padding: EdgeInsets.zero,
                    children: [
                      AspectRatio(
                        aspectRatio: 1.3,
                        child: imageUrl != null && imageUrl.isNotEmpty
                            ? Image.network(imageUrl, fit: BoxFit.cover, errorBuilder: (_, __, ___) => _imagePlaceholder())
                            : _imagePlaceholder(),
                      ),
                      Padding(
                        padding: const EdgeInsets.all(20),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            if (category.isNotEmpty)
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                decoration: BoxDecoration(color: AppColors.yellow.withOpacity(0.2), borderRadius: BorderRadius.circular(8)),
                                child: Text(category, style: const TextStyle(color: AppColors.yellowDark, fontSize: 11, fontWeight: FontWeight.w700)),
                              ),
                            const SizedBox(height: 12),
                            Text(name, style: const TextStyle(color: AppColors.navy, fontSize: 20, fontWeight: FontWeight.w800)),
                            const SizedBox(height: 10),
                            Text(description, style: const TextStyle(color: AppColors.grey, fontSize: 13.5, height: 1.6)),
                            const SizedBox(height: 20),
                            Container(
                              padding: const EdgeInsets.all(14),
                              decoration: BoxDecoration(color: AppColors.white, borderRadius: BorderRadius.circular(12), border: Border.all(color: AppColors.cardBorder)),
                              child: const Row(
                                children: [
                                  Icon(Icons.info_outline, color: AppColors.grey, size: 16),
                                  SizedBox(width: 8),
                                  Expanded(
                                    child: Text(
                                      'Pricing and availability will be shared by our team after you register your interest.',
                                      style: TextStyle(color: AppColors.grey, fontSize: 11.5, height: 1.4),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                _bottomBar(context, productId, name, category),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _bottomBar(BuildContext context, String productId, String name, String category) {
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 14, 20, 14),
      decoration: BoxDecoration(
        color: AppColors.white,
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.08), blurRadius: 10, offset: const Offset(0, -3))],
      ),
      child: SafeArea(
        top: false,
        child: Row(
          children: [
            GestureDetector(
              onTap: () => Navigator.pop(context),
              child: Container(
                width: 46, height: 46,
                decoration: BoxDecoration(color: AppColors.offWhite, borderRadius: BorderRadius.circular(12), border: Border.all(color: AppColors.cardBorder)),
                child: const Icon(Icons.arrow_back_ios_new_rounded, color: AppColors.navy, size: 16),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: SizedBox(
                height: 50,
                child: ElevatedButton(
                  onPressed: () => Navigator.pushNamed(
                    context,
                    AppRoutes.signShoppyInterest,
                    arguments: {'productId': productId, 'productName': name, 'category': category},
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.yellow,
                    foregroundColor: AppColors.navy,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    elevation: 0,
                  ),
                  child: const Text("I'M INTERESTED", style: TextStyle(fontSize: 14.5, fontWeight: FontWeight.w800, letterSpacing: 0.3)),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _imagePlaceholder() {
    return Container(
      color: AppColors.offWhite,
      child: const Center(child: Icon(Icons.image_outlined, color: AppColors.greyLight, size: 48)),
    );
  }
}