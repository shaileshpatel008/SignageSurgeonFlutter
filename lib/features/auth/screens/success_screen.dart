import 'package:flutter/material.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/constants/app_routes.dart';

class SuccessScreen extends StatefulWidget {
  const SuccessScreen({super.key});

  @override
  State<SuccessScreen> createState() => _SuccessScreenState();
}

class _SuccessScreenState extends State<SuccessScreen>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _scaleAnim;
  late Animation<double> _fadeAnim;
  bool _isNewUser = true;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 700),
    );
    _scaleAnim = Tween<double>(
      begin: 0.5,
      end: 1.0,
    ).animate(CurvedAnimation(parent: _controller, curve: Curves.elasticOut));
    _fadeAnim = Tween<double>(
      begin: 0,
      end: 1,
    ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeIn));
    _controller.forward();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final args =
        ModalRoute.of(context)?.settings.arguments as Map<String, dynamic>?;
    _isNewUser = args?['isNewUser'] ?? true;

    // Auto-navigate after 2.5 seconds
    Future.delayed(const Duration(milliseconds: 2500), () {
      if (!mounted) return;
      if (_isNewUser) {
        Navigator.pushReplacementNamed(context, AppRoutes.profileSetup);
      } else {
        Navigator.pushReplacementNamed(context, AppRoutes.home);
      }
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.navy,
      body: SafeArea(
        child: Center(
          child: FadeTransition(
            opacity: _fadeAnim,
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                // Yellow checkmark circle
                ScaleTransition(
                  scale: _scaleAnim,
                  child: Container(
                    width: 110,
                    height: 110,
                    decoration: const BoxDecoration(
                      color: AppColors.yellow,
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.check,
                      color: AppColors.white,
                      size: 60,
                    ),
                  ),
                ),

                const SizedBox(height: 24),

                const Text('Success!', style: AppTextStyles.yellowBold),

                const SizedBox(height: 48),

                Image.asset('assets/images/logo.png', width: 200, height: 200),

                const SizedBox(height: 32),

                const Text(
                  'Our team is ready!',
                  style: AppTextStyles.yellowBold,
                ),

                const SizedBox(height: 12),

                const Text('Taking you in...', style: AppTextStyles.bodyGrey),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
