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
import 'features/auth/screens/home_screen.dart';
import 'features/auth/screens/my_requests_screen.dart';
import 'features/auth/screens/amc_screen.dart';
import 'features/auth/screens/notifications_screen.dart';
import 'features/auth/screens/account_screen.dart';
import 'features/auth/screens/edit_profile_screen.dart';
import 'features/coming_soon/coming_soon_screen.dart';
import 'features/service_request/screens/create_request_screen.dart';
import 'features/service_request/screens/amc_coming_soon_screen.dart';
import 'features/service_request/screens/upload_media_screen.dart';
import 'features/service_request/screens/request_summary_screen.dart';
import 'features/service_request/screens/repairing_request_screen.dart';
import 'features/service_request/screens/request_tracking_screen.dart';
import 'features/service_request/screens/rebranding_request_screen.dart';
import 'features/service_request/screens/new_signage_request_screen.dart';
import 'features/service_request/screens/cleaning_request_screen.dart';
import 'features/service_request/screens/cleaning_tracking_screen.dart';
import 'features/service_request/screens/amc_request_screen.dart';
import 'features/service_request/screens/amc_tracking_screen.dart';
import 'features/service_request/screens/sign_shoppy_screen.dart';
import 'features/service_request/screens/sign_shoppy_category_screen.dart';
import 'features/service_request/screens/sign_shoppy_product_screen.dart';
import 'features/service_request/screens/sign_shoppy_interest_screen.dart';
import 'features/service_request/screens/sign_shoppy_screen.dart';
import 'features/service_request/screens/sign_shoppy_tracking_screen.dart';
import 'features/service_request/screens/contact_us_screen.dart';
import 'features/auth/screens/manage_addresses_screen.dart';
import 'features/service_request/screens/about_screen.dart';
import 'features/refund/screens/my_refund_requests_screen.dart';
import 'features/refund/screens/request_refund_screen.dart';
import 'features/support/screens/my_support_tickets_screen.dart';
import 'features/support/screens/report_problem_screen.dart';
import 'core/navigation/navigator_key.dart';

class SignageSurgeonApp extends StatelessWidget {
  const SignageSurgeonApp({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (_) => AuthBloc(AuthRepository()),
      child: MaterialApp(
        navigatorKey: rootNavigatorKey,
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
          AppRoutes.myRequests: (_) => const MyRequestsScreen(),
          AppRoutes.amc: (_) => const AmcScreen(),
          AppRoutes.notifications: (_) => const NotificationsScreen(),
          AppRoutes.account: (_) => const AccountScreen(),
          AppRoutes.editProfile: (_) => const EditProfileScreen(),
          AppRoutes.comingSoon: (_) => const ComingSoonScreen(),
          AppRoutes.serviceRequest: (_) => const CreateRequestScreen(),
          AppRoutes.createRequest: (_) => const CreateRequestScreen(),
          AppRoutes.amcPlans: (_) => const AmcComingSoonScreen(),
          AppRoutes.uploadMedia: (_) => const UploadMediaScreen(),
          AppRoutes.requestSummary: (_) => const RequestSummaryScreen(),
          AppRoutes.repairingRequest: (_) => const RepairingRequestScreen(),
          AppRoutes.requestTracking: (_) => const RequestTrackingScreen(),
          AppRoutes.rebrandingRequest: (_) => const RebrandingRequestScreen(),
          AppRoutes.newSignageRequest: (_) => const NewSignageRequestScreen(),
          AppRoutes.cleaningRequest: (_) => const CleaningRequestScreen(),
          AppRoutes.cleaningTracking: (_) => const CleaningTrackingScreen(),
          AppRoutes.amcRequest: (_) => const AmcRequestScreen(),
          AppRoutes.amcTracking: (_) => const AmcTrackingScreen(),
          AppRoutes.comingSoon: (_) => const SignShoppyScreen(), // if you want it to replace the old placeholder route
          AppRoutes.signShoppyCategory: (_) => const SignShoppyCategoryScreen(),
          AppRoutes.signShoppyProduct:  (_) => const SignShoppyProductScreen(),
          AppRoutes.signShoppyInterest: (_) => const SignShoppyInterestScreen(),
          AppRoutes.signShoppy: (_) => const SignShoppyScreen(),
          AppRoutes.signShoppyTracking: (_) => const SignShoppyTrackingScreen(),
          AppRoutes.contactUs: (_) => const ContactUsScreen(),
          AppRoutes.manageAddresses: (_) => const ManageAddressesScreen(),
          AppRoutes.aboutUs: (_) => const AboutScreen(),
          AppRoutes.myRefundRequests: (_) => const MyRefundRequestsScreen(),
          AppRoutes.requestRefund: (context) {
            final args = ModalRoute.of(context)!.settings.arguments as Map<String, dynamic>;
            return RequestRefundScreen(
              collection: args['collection'] as String,
              requestId: args['requestId'] as String,
              serviceLabel: args['serviceLabel'] as String,
              paymentOptions: args['paymentOptions'] as List<RefundablePayment>,
            );
          },
          AppRoutes.mySupportTickets: (_) => const MySupportTicketsScreen(),
          AppRoutes.reportProblem: (context) {
            final args = ModalRoute.of(context)!.settings.arguments as Map<String, dynamic>;
            return ReportProblemScreen(
              collection: args['collection'] as String,
              requestId: args['requestId'] as String,
              serviceLabel: args['serviceLabel'] as String,
            );
          },
        },
      ),
    );
  }
}