import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'core/theme/app_theme.dart';
import 'core/constants/app_routes.dart';
import 'features/auth/bloc/auth_bloc.dart';
import 'features/auth/repository/auth_repository.dart';
import 'features/auth/screens/splash_screen.dart';
import 'features/auth/screens/welcome_screen.dart';
import 'features/auth/screens/login_screen.dart';
import 'features/auth/screens/otp_screen.dart';
import 'features/auth/screens/success_screen.dart';
import 'features/auth/screens/profile_setup_screen.dart';
import 'features/coming_soon/coming_soon_screen.dart';
import 'features/service_request/screens/create_request_screen.dart';
import 'features/service_request/screens/amc_coming_soon_screen.dart';
import 'features/auth/screens/home_screen.dart';
import 'features/service_request/screens/upload_media_screen.dart';
import 'features/service_request/screens/request_summary_screen.dart';

class SignageSurgeonApp extends StatelessWidget {
  const SignageSurgeonApp({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (_) => AuthBloc(AuthRepository()),
      child: MaterialApp(
        title: 'The Signage Surgeon',
        debugShowCheckedModeBanner: false,
        theme: AppTheme.theme,
        initialRoute: AppRoutes.splash,
        routes: {
          AppRoutes.splash: (_) => const SplashScreen(),
          AppRoutes.welcome: (_) => const WelcomeScreen(),
          AppRoutes.login: (_) => const LoginScreen(),
          AppRoutes.otp: (_) => const OtpScreen(),
          AppRoutes.success: (_) => const SuccessScreen(),
          AppRoutes.profileSetup: (_) => const ProfileSetupScreen(),
          AppRoutes.home: (_) => const HomeScreen(),
          AppRoutes.comingSoon: (_) => const ComingSoonScreen(),
          AppRoutes.serviceRequest: (_) => const CreateRequestScreen(),
          AppRoutes.createRequest: (_) => const CreateRequestScreen(),
          AppRoutes.amcPlans: (_) => const AmcComingSoonScreen(),
          AppRoutes.uploadMedia: (context) => const UploadMediaScreen(),
          AppRoutes.requestSummary: (context) => const RequestSummaryScreen(),
        },
      ),
    );
  }
}
