import 'package:flutter/material.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/constants/app_routes.dart';

class ProfileSetupScreen extends StatelessWidget {
  const ProfileSetupScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.navy,
      appBar: AppBar(title: const Text('Complete Your Profile')),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.person_add, color: AppColors.yellow, size: 80),
            const SizedBox(height: 20),
            const Text('Profile Setup', style: AppTextStyles.heading2),
            const SizedBox(height: 12),
            const Text(
              'Coming soon — we will build this next!',
              style: AppTextStyles.bodyGrey,
            ),
            const SizedBox(height: 32),
            // Temp button to go to home for testing
            ElevatedButton(
              onPressed: () => Navigator.pushReplacementNamed(
                  context, AppRoutes.home),
              child: const Text('Skip for now (testing)'),
            ),
          ],
        ),
      ),
    );
  }
}