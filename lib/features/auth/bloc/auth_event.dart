abstract class AuthEvent {}

class SendOtpEvent extends AuthEvent {
  final String phoneNumber;
  SendOtpEvent(this.phoneNumber);
}

class VerifyOtpEvent extends AuthEvent {
  final String otp;
  VerifyOtpEvent(this.otp);
}

class ResendOtpEvent extends AuthEvent {
  final String phoneNumber;
  ResendOtpEvent(this.phoneNumber);
}