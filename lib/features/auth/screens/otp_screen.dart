import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:pinput/pinput.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/constants/app_routes.dart';
import '../bloc/auth_bloc.dart';
import '../bloc/auth_event.dart';
import '../bloc/auth_state.dart';

class OtpScreen extends StatefulWidget {
  const OtpScreen({super.key});

  @override
  State<OtpScreen> createState() => _OtpScreenState();
}

class _OtpScreenState extends State<OtpScreen> {
  final TextEditingController _otpController = TextEditingController();
  String _phoneNumber = '';

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final args =
        ModalRoute.of(context)?.settings.arguments as Map<String, dynamic>?;
    _phoneNumber = args?['phoneNumber'] ?? '';
  }

  @override
  void dispose() {
    _otpController.dispose();
    super.dispose();
  }

  void _verifyOtp(BuildContext context) {
    if (_otpController.text.length == 6) {
      context.read<AuthBloc>().add(VerifyOtpEvent(_otpController.text));
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please enter the 6-digit OTP'),
          backgroundColor: AppColors.red,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final defaultPinTheme = PinTheme(
      width: 52,
      height: 56,
      textStyle: const TextStyle(
        fontSize: 22,
        color: AppColors.navy,
        fontWeight: FontWeight.bold,
      ),
      decoration: BoxDecoration(
        color: AppColors.white,
        borderRadius: BorderRadius.circular(10),
      ),
    );

    final focusedPinTheme = defaultPinTheme.copyWith(
      decoration: BoxDecoration(
        color: AppColors.white,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.yellow, width: 2.5),
      ),
    );

    return Scaffold(
      backgroundColor: AppColors.navy,
      body: BlocListener<AuthBloc, AuthState>(
        listener: (context, state) {
          if (state is OtpVerified) {
            if (state.isNewUser) {
              Navigator.pushNamedAndRemoveUntil(
                context,
                AppRoutes.success,
                (route) => false,
                arguments: {'isNewUser': true},
              );
            } else {
              Navigator.pushNamedAndRemoveUntil(
                context,
                AppRoutes.success,
                (route) => false,
                arguments: {'isNewUser': false},
              );
            }
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
            child: Column(
              children: [
                const Spacer(flex: 2),

                const Text('Create an account', style: AppTextStyles.heading2),

                const SizedBox(height: 12),

                Text(
                  'OTP sent to +91 $_phoneNumber',
                  style: AppTextStyles.bodyGrey,
                ),

                const SizedBox(height: 40),

                // OTP input
                Pinput(
                  length: 6,
                  controller: _otpController,
                  defaultPinTheme: defaultPinTheme,
                  focusedPinTheme: focusedPinTheme,
                  onCompleted: (_) => _verifyOtp(context),
                ),

                const SizedBox(height: 28),

                // LOG IN button
                BlocBuilder<AuthBloc, AuthState>(
                  builder: (context, state) {
                    final isLoading = state is AuthLoading;
                    return SizedBox(
                      width: double.infinity,
                      height: 52,
                      child: ElevatedButton(
                        onPressed: isLoading ? null : () => _verifyOtp(context),
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

                // Resend OTP
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Text(
                      "Didn't receive it?  ",
                      style: AppTextStyles.caption,
                    ),
                    GestureDetector(
                      onTap: () {
                        context.read<AuthBloc>().add(
                          ResendOtpEvent(_phoneNumber),
                        );
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text('OTP resent!'),
                            backgroundColor: AppColors.navyLight,
                          ),
                        );
                      },
                      child: const Text(
                        'Click here',
                        style: TextStyle(
                          fontSize: 12,
                          color: AppColors.yellow,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 24),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
