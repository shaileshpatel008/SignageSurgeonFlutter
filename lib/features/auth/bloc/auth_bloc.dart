import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../repository/auth_repository.dart';
import 'auth_event.dart';
import 'auth_state.dart';

class AuthBloc extends Bloc<AuthEvent, AuthState> {
  final AuthRepository _authRepository;
  String? _verificationId;

  AuthBloc(this._authRepository) : super(AuthInitial()) {
    on<SendOtpEvent>(_onSendOtp);
    on<VerifyOtpEvent>(_onVerifyOtp);
    on<ResendOtpEvent>(_onResendOtp);
  }

  Future<void> _onSendOtp(SendOtpEvent event, Emitter<AuthState> emit) async {
    emit(AuthLoading());
    try {
      await emit.forEach<AuthState>(
        _authRepository.sendOtpStream(phoneNumber: '+91${event.phoneNumber}'),
        onData: (state) {
          if (state is OtpSent) {
            _verificationId = state.verificationId;
          }
          return state;
        },
        onError: (error, _) => AuthError(error.toString()),
      );
    } catch (e) {
      emit(AuthError('Something went wrong. Please try again.'));
    }
  }

  Future<void> _onVerifyOtp(
      VerifyOtpEvent event, Emitter<AuthState> emit) async {
    if (_verificationId == null) {
      emit(AuthError('Session expired. Please resend OTP.'));
      return;
    }
    emit(AuthLoading());
    try {
      final userCredential = await _authRepository.verifyOtp(
        verificationId: _verificationId!,
        otp: event.otp,
      );
      final uid = userCredential.user!.uid;
      final isProfileComplete = await _authRepository.isProfileComplete(uid);
      emit(OtpVerified(isNewUser: !isProfileComplete));
    } on FirebaseAuthException catch (e) {
      String message = 'Invalid OTP. Please try again.';
      if (e.code == 'session-expired') {
        message = 'OTP expired. Please resend.';
      }
      emit(AuthError(message));
    } catch (e) {
      emit(AuthError('Something went wrong. Please try again.'));
    }
  }

  Future<void> _onResendOtp(
      ResendOtpEvent event, Emitter<AuthState> emit) async {
    add(SendOtpEvent(event.phoneNumber));
  }
}