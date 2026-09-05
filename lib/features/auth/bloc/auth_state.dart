abstract class AuthState {}

class AuthInitial extends AuthState {}

class AuthLoading extends AuthState {}

class OtpSent extends AuthState {
  final String verificationId;
  final String phoneNumber;
  OtpSent({required this.verificationId, required this.phoneNumber});
}

class OtpVerified extends AuthState {
  final bool isNewUser; // true = go to profile setup, false = go to home
  OtpVerified({required this.isNewUser});
}

class AuthError extends AuthState {
  final String message;
  AuthError(this.message);
}