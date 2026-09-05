import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/constants/app_routes.dart';

class WelcomeScreen extends StatelessWidget {
  const WelcomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.dark,
      child: Scaffold(
        backgroundColor: AppColors.offWhite,
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
                    color: AppColors.navy,
                  ),
                ),
                const SizedBox(height: 28),

                // Logo — transparent-background version (no white halo on
                // the light background)
                Image.asset(
                  'assets/images/logo.png',
                  width: 220,
                ),

                const SizedBox(height: 28),

                // Brand name — locally overridden from AppTextStyles.yellowBold
                // (pure yellow text has weak contrast on a light background)
                const Text(
                  'THE SIGNAGE SURGEON',
                  style: TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.bold,
                    color: AppColors.navy,
                    letterSpacing: 1,
                  ),
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
                      backgroundColor: AppColors.yellow,
                      foregroundColor: AppColors.navy,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                      elevation: 0,
                    ),
                    child: const Text(
                      'login / signup',
                      style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                    ),
                  ),
                ),
                const SizedBox(height: 32),
              ],
            ),
          ),
        ),
      ),
    );
  }
}