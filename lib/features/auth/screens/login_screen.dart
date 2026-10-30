import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/constants/app_routes.dart';
import '../bloc/auth_bloc.dart';
import '../bloc/auth_event.dart';
import '../bloc/auth_state.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final TextEditingController _phoneController = TextEditingController();
  final _formKey = GlobalKey<FormState>();

  // Play Store requires a working, reachable privacy policy link inside
  // the app (the plain, non-tappable text here previously didn't link
  // anywhere) — same URLs account_screen.dart links Terms & Conditions to.
  static const String _privacyPolicyUrl =
      'https://www.thesignagesurgeon.com/privacy-policy';
  static const String _termsAndConditionsUrl =
      'https://www.thesignagesurgeon.com/terms-and-conditions';

  @override
  void dispose() {
    _phoneController.dispose();
    super.dispose();
  }

  void _sendOtp(BuildContext context) {
    if (_formKey.currentState!.validate()) {
      context.read<AuthBloc>().add(SendOtpEvent(_phoneController.text.trim()));
    }
  }

  Future<void> _openUrl(String url) async {
    final uri = Uri.parse(url);
    final launched = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!launched && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not open the link. Please try again.')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.dark,
      child: Scaffold(
        backgroundColor: AppColors.offWhite,
        body: BlocListener<AuthBloc, AuthState>(
          listener: (context, state) {
            if (state is OtpSent) {
              Navigator.pushNamed(
                context,
                AppRoutes.otp,
                arguments: {
                  'verificationId': state.verificationId,
                  'phoneNumber': state.phoneNumber,
                },
              );
            } else if (state is AuthError) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text(state.message),
                  backgroundColor: AppColors.red,
                ),
              );
            }
          },
          child: SafeArea(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 28),
              child: Form(
                key: _formKey,
                child: Column(
                  children: [
                    const Spacer(flex: 2),

                    // Locally overridden — AppTextStyles.heading2 is hardcoded
                    // white and is still shared by screens on the dark theme.
                    const Text(
                      'Create an account',
                      style: TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.bold,
                        color: AppColors.navy,
                        letterSpacing: 0.3,
                      ),
                    ),

                    const SizedBox(height: 40),

                    // Phone number field
                    Container(
                      decoration: BoxDecoration(
                        color: AppColors.white,
                        borderRadius: BorderRadius.circular(10),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withOpacity(0.05),
                            blurRadius: 10,
                            offset: const Offset(0, 3),
                          ),
                        ],
                      ),
                      child: TextFormField(
                        controller: _phoneController,
                        keyboardType: TextInputType.phone,
                        inputFormatters: [
                          FilteringTextInputFormatter.digitsOnly,
                          LengthLimitingTextInputFormatter(10),
                        ],
                        style: const TextStyle(
                          color: AppColors.navy,
                          fontSize: 16,
                          fontWeight: FontWeight.w500,
                        ),
                        decoration: const InputDecoration(
                          hintText: 'Enter Mobile Number',
                          hintStyle: TextStyle(color: AppColors.grey),
                          prefixText: '+91  ',
                          prefixStyle: TextStyle(
                            color: AppColors.navy,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        validator: (value) {
                          if (value == null || value.isEmpty) {
                            return 'Please enter your mobile number';
                          }
                          if (value.length != 10) {
                            return 'Enter a valid 10-digit mobile number';
                          }
                          return null;
                        },
                      ),
                    ),

                    const SizedBox(height: 20),

                    // LOG IN button
                    BlocBuilder<AuthBloc, AuthState>(
                      builder: (context, state) {
                        final isLoading = state is AuthLoading;
                        return SizedBox(
                          width: double.infinity,
                          height: 52,
                          child: ElevatedButton(
                            onPressed:
                                isLoading ? null : () => _sendOtp(context),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: const Color(0xFFFEC514),
                              foregroundColor: AppColors.navy,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(10),
                              ),
                              elevation: 0,
                            ),
                            child: isLoading
                                ? const SizedBox(
                                    width: 22,
                                    height: 22,
                                    child: CircularProgressIndicator(
                                      color: AppColors.navy,
                                      strokeWidth: 2.5,
                                    ),
                                  )
                                : const Text(
                                    'LOG IN',
                                    style: AppTextStyles.buttonText,
                                  ),
                          ),
                        );
                      },
                    ),

                    const Spacer(flex: 3),

                    // Terms text — "Privacy Policy" and "Terms" are real
                    // tappable links now, not just words in a static string.
                    Text.rich(
                      TextSpan(
                        style: const TextStyle(fontSize: 12, color: AppColors.grey),
                        children: [
                          const TextSpan(text: 'By signing up you agree to our '),
                          TextSpan(
                            text: 'Privacy Policy',
                            style: const TextStyle(fontWeight: FontWeight.w700, color: AppColors.navy),
                            recognizer: TapGestureRecognizer()..onTap = () => _openUrl(_privacyPolicyUrl),
                          ),
                          const TextSpan(text: ' and '),
                          TextSpan(
                            text: 'Terms',
                            style: const TextStyle(fontWeight: FontWeight.w700, color: AppColors.navy),
                            recognizer: TapGestureRecognizer()..onTap = () => _openUrl(_termsAndConditionsUrl),
                          ),
                        ],
                      ),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 24),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}