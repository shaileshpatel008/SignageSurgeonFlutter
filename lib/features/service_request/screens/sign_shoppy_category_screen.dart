import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/constants/app_routes.dart';

class SignShoppyCategoryScreen extends StatelessWidget {
  const SignShoppyCategoryScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final category = ModalRoute.of(context)?.settings.arguments as String? ?? '';

    return Scaffold(
      backgroundColor: AppColors.offWhite,
      appBar: AppBar(
        backgroundColor: AppColors.serviceAccent,
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
        title: Text(category, style: const TextStyle(color: AppColors.navy, fontSize: 16, fontWeight: FontWeight.w700)),
      ),
      body: StreamBuilder<QuerySnapshot>(
        stream: FirebaseFirestore.instance
            .collection('sign_shoppy_products')
            .where('category', isEqualTo: category)
            .where('active', isEqualTo: true)
            .snapshots(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator(color: AppColors.yellow));
          }
          final docs = snapshot.data?.docs ?? [];
          if (docs.isEmpty) {
            return _emptyState(category);
          }
          return GridView.builder(
            padding: const EdgeInsets.all(20),
            itemCount: docs.length,
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 2, crossAxisSpacing: 14, mainAxisSpacing: 14, childAspectRatio: 0.72,
            ),
            itemBuilder: (_, i) {
              final data = docs[i].data() as Map<String, dynamic>;
              return _productCard(context, docs[i].id, data);
            },
          );
        },
      ),
    );
  }

  Widget _emptyState(String category) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 72, height: 72,
              decoration: BoxDecoration(color: AppColors.white, shape: BoxShape.circle, boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 8, offset: const Offset(0, 2))]),
              child: const Icon(Icons.storefront_outlined, color: AppColors.greyLight, size: 34),
            ),
            const SizedBox(height: 16),
            Text('$category is coming soon', style: const TextStyle(color: AppColors.navy, fontSize: 14, fontWeight: FontWeight.w700), textAlign: TextAlign.center),
            const SizedBox(height: 8),
            const Text('We\'re adding products to this category. Check back soon!', style: TextStyle(color: AppColors.grey, fontSize: 12), textAlign: TextAlign.center),
          ],
        ),
      ),
    );
  }

  Widget _productCard(BuildContext context, String productId, Map<String, dynamic> data) {
    final imageUrl = data['imageUrl'] as String?;
    final name = data['name'] as String? ?? 'Signage Product';
    final description = data['shortDescription'] as String? ?? '';

    return GestureDetector(
      onTap: () => Navigator.pushNamed(context, AppRoutes.signShoppyProduct, arguments: productId),
      child: Container(
        decoration: BoxDecoration(
          color: AppColors.white,
          borderRadius: BorderRadius.circular(14),
          boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 8, offset: const Offset(0, 2))],
        ),
        clipBehavior: Clip.antiAlias,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            AspectRatio(
              aspectRatio: 1.2,
              child: imageUrl != null && imageUrl.isNotEmpty
                  ? Image.network(imageUrl, fit: BoxFit.cover, errorBuilder: (_, __, ___) => _imagePlaceholder())
                  : _imagePlaceholder(),
            ),
            Padding(
              padding: const EdgeInsets.all(10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(name, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: AppColors.navy, fontSize: 12.5, fontWeight: FontWeight.w700)),
                  const SizedBox(height: 3),
                  Text(description, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(color: AppColors.grey, fontSize: 10.5, height: 1.3)),
                ],
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
      child: const Center(child: Icon(Icons.image_outlined, color: AppColors.greyLight, size: 32)),
    );
  }
}