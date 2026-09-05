import 'package:flutter/material.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/constants/app_routes.dart';

class SignShoppyScreen extends StatelessWidget {
  const SignShoppyScreen({super.key});

  static const List<Map<String, dynamic>> _categories = [
    {'name': 'Mandatory Signage', 'icon': Icons.priority_high_rounded},
    {'name': 'Safety Signage', 'icon': Icons.health_and_safety_outlined},
    {'name': 'Directional Signage', 'icon': Icons.signpost_outlined},
    {'name': 'Facility Signage', 'icon': Icons.apartment_outlined},
    {'name': 'Office Signage', 'icon': Icons.business_center_outlined},
    {'name': 'Industrial Signage', 'icon': Icons.precision_manufacturing_outlined},
    {'name': 'Parking Signage', 'icon': Icons.local_parking_outlined},
    {'name': 'General Signage', 'icon': Icons.branding_watermark_outlined},
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.offWhite,
      appBar: _buildAppBar(context),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 30),
        children: [
          const Text(
            'SIGN SHOPPY IS GETTING READY',
            style: TextStyle(color: AppColors.navy, fontSize: 20, fontWeight: FontWeight.w800, height: 1.3),
          ),
          const SizedBox(height: 10),
          const Text(
            'Ready-to-order mandatory, safety, directional and business signage is coming soon. '
            'Explore our growing signage collection and register your interest. Our team will assist '
            'you with availability and pricing.',
            style: TextStyle(color: AppColors.grey, fontSize: 13, height: 1.6),
          ),
          const SizedBox(height: 28),
          const Text('Browse Categories', style: TextStyle(color: AppColors.navy, fontSize: 15, fontWeight: FontWeight.w700)),
          const SizedBox(height: 14),
          GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: _categories.length,
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 2, crossAxisSpacing: 12, mainAxisSpacing: 12, childAspectRatio: 1.15,
            ),
            itemBuilder: (_, i) => _categoryCard(context, _categories[i]),
          ),
        ],
      ),
    );
  }

  PreferredSizeWidget _buildAppBar(BuildContext context) {
    return AppBar(
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
      title: const Text('Sign Shoppy', style: TextStyle(color: AppColors.navy, fontSize: 17, fontWeight: FontWeight.w700)),
    );
  }

  Widget _categoryCard(BuildContext context, Map<String, dynamic> category) {
    return GestureDetector(
      onTap: () => Navigator.pushNamed(context, AppRoutes.signShoppyCategory, arguments: category['name']),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: AppColors.white,
          borderRadius: BorderRadius.circular(14),
          boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 8, offset: const Offset(0, 2))],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Container(
              width: 42, height: 42,
              decoration: BoxDecoration(color: AppColors.yellow.withOpacity(0.2), borderRadius: BorderRadius.circular(10)),
              child: Icon(category['icon'] as IconData, color: AppColors.yellowDark, size: 22),
            ),
            const SizedBox(height: 10),
            Text(
              category['name'] as String,
              style: const TextStyle(color: AppColors.navy, fontSize: 12.5, fontWeight: FontWeight.w700, height: 1.3),
            ),
          ],
        ),
      ),
    );
  }
}