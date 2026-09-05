import 'package:flutter/material.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/constants/app_routes.dart';

class WelcomeScreen extends StatelessWidget {
  const WelcomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.navy,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 28),
          child: Column(
            children: [
              const Spacer(flex: 2),

              // Welcome text
              const Text(
                'Welcome to',
                style: TextStyle(
                  fontSize: 22,
                  color: AppColors.white,
                  // fontStyle: FontStyle.italic,
                ),
              ),
              const SizedBox(height: 28),

              // Logo — replace Icon with Image.asset('assets/images/mascot.png')
              // when you add your mascot image
              Image.asset('assets/images/logo.png', width: 220, height: 220),

              const SizedBox(height: 28),

              // Brand name
              const Text(
                'THE SIGNAGE SURGEON',
                style: AppTextStyles.yellowBold,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 6),
              const Text(
                'NEW LIFE FOR OLD SIGN',
                style: TextStyle(
                  fontSize: 12,
                  color: AppColors.grey,
                  letterSpacing: 2,
                ),
              ),
              const SizedBox(height: 12),
              const Text(
                'Start by creating an account',
                style: AppTextStyles.bodyGrey,
              ),

              const Spacer(flex: 3),

              // Login / Signup button
              SizedBox(
                width: double.infinity,
                height: 52,
                child: ElevatedButton(
                  onPressed: () =>
                      Navigator.pushNamed(context, AppRoutes.login),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.navyLight,
                    foregroundColor: AppColors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                  child: const Text(
                    'login / signup',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.w500),
                  ),
                ),
              ),
              const SizedBox(height: 32),
            ],
          ),
        ),
      ),
    );
  }
}
