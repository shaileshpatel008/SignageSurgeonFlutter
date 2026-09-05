import 'package:flutter/material.dart';
import '../../core/theme/app_theme.dart';

class ComingSoonScreen extends StatelessWidget {
  const ComingSoonScreen({super.key});

  static const Color _bg = Color(0xFF0A1628);
  static const Color _card = Color(0xFF111F3A);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bg,
      appBar: AppBar(
        backgroundColor: _bg,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new,
              color: Colors.white, size: 20),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text(
          'Sign Shoppy',
          style: TextStyle(
            color: Colors.white,
            fontSize: 16,
            fontWeight: FontWeight.bold,
          ),
        ),
        centerTitle: true,
      ),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 32),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              // Icon container
              Container(
                width: 120,
                height: 120,
                decoration: BoxDecoration(
                  color: _card,
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: AppColors.yellow.withOpacity(0.3),
                    width: 2,
                  ),
                ),
                child: const Icon(
                  Icons.storefront_outlined,
                  color: AppColors.yellow,
                  size: 56,
                ),
              ),
              const SizedBox(height: 32),
              // Coming Soon badge
              Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 20, vertical: 8),
                decoration: BoxDecoration(
                  color: AppColors.yellow.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(30),
                  border: Border.all(
                    color: AppColors.yellow.withOpacity(0.4),
                    width: 1,
                  ),
                ),
                child: const Text(
                  '🚀  COMING SOON',
                  style: TextStyle(
                    color: AppColors.yellow,
                    fontSize: 13,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 1.5,
                  ),
                ),
              ),
              const SizedBox(height: 20),
              const Text(
                'Sign Shoppy',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 28,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 12),
              const Text(
                'We\'re building something exciting — a dedicated marketplace for all your signage needs. Shop materials, products, and accessories right from the app.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Colors.white54,
                  fontSize: 14,
                  height: 1.6,
                ),
              ),
              const SizedBox(height: 40),
              // Go back button
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: () => Navigator.pop(context),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.yellow,
                    foregroundColor: _bg,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    elevation: 0,
                  ),
                  child: const Text(
                    'Go Back',
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}