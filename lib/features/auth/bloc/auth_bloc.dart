import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../repository/auth_repository.dart';
import 'auth_event.dart';
import 'auth_state.dart';

class AuthBloc extends Bloc<AuthEvent, AuthState> {
  final AuthRepository _authRepository;
  String? _verificationId;
  String? _phoneNumber;

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
            _phoneNumber = state.phoneNumber;
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
      await _emitSignedInState(userCredential.user, emit);
    } on FirebaseAuthException catch (e) {
      // Firebase can report an error here (e.g. session-expired, most
      // likely from a slow app-verification step upstream) even though
      // signInWithCredential actually went through underneath it. Trust
      // ground truth over the error: if we're genuinely signed in as this
      // exact phone number, treat it as success rather than showing an
      // error for a login that already worked.
      if (_isSignedInAs(_phoneNumber)) {
        await _emitSignedInState(_authRepository.currentUser, emit);
        return;
      }
      String message = 'Invalid OTP. Please try again.';
      if (e.code == 'session-expired') {
        message = 'OTP expired. Please resend.';
      }
      emit(AuthError(message, code: e.code));
    } catch (e) {
      if (_isSignedInAs(_phoneNumber)) {
        await _emitSignedInState(_authRepository.currentUser, emit);
        return;
      }
      emit(AuthError('Something went wrong. Please try again.'));
    }
  }

  bool _isSignedInAs(String? phoneNumber) {
    final user = _authRepository.currentUser;
    if (user == null || phoneNumber == null) return false;
    return user.phoneNumber?.endsWith(phoneNumber) ?? false;
  }

  Future<void> _emitSignedInState(User? user, Emitter<AuthState> emit) async {
    final isProfileComplete = await _authRepository.isProfileComplete(user!.uid);
    emit(OtpVerified(isNewUser: !isProfileComplete));
  }

  Future<void> _onResendOtp(
      ResendOtpEvent event, Emitter<AuthState> emit) async {
    add(SendOtpEvent(event.phoneNumber));
  }
}