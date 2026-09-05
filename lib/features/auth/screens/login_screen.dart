import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.navy,
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

                  const Text(
                    'Create an account',
                    style: AppTextStyles.heading2,
                  ),

                  const SizedBox(height: 40),

                  // Phone number field
                  TextFormField(
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

                  // Terms text
                  const Text(
                    'By signing up you agree to our Privacy Policy and Terms',
                    style: AppTextStyles.caption,
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 24),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}