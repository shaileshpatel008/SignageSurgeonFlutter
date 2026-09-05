import 'dart:async';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../bloc/auth_state.dart';

class AuthRepository {
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  User? get currentUser => _auth.currentUser;

  Future<bool> isProfileComplete(String uid) async {
    final doc = await _firestore.collection('users').doc(uid).get();
    if (!doc.exists) return false;
    final data = doc.data();
    if (data == null) return false;
    return data['fullName'] != null &&
        data['businessName'] != null &&
        data['address'] != null;
  }

  Stream<AuthState> sendOtpStream({required String phoneNumber}) {
    final controller = StreamController<AuthState>();

    _auth.verifyPhoneNumber(
      phoneNumber: phoneNumber,
      timeout: const Duration(seconds: 60),
      verificationCompleted: (PhoneAuthCredential credential) async {
        try {
          final userCredential = await _auth.signInWithCredential(credential);
          final uid = userCredential.user!.uid;
          final complete = await isProfileComplete(uid);
          if (!controller.isClosed) {
            controller.add(OtpVerified(isNewUser: !complete));
            controller.close();
          }
        } catch (e) {
          if (!controller.isClosed) {
            controller.addError('Auto verification failed.');
            controller.close();
          }
        }
      },
      verificationFailed: (FirebaseAuthException e) {
        String message = 'Verification failed. Please try again.';
        if (e.code == 'invalid-phone-number') {
          message = 'Invalid phone number. Please check and try again.';
        } else if (e.code == 'too-many-requests') {
          message = 'Too many attempts. Please try after some time.';
        } else if (e.code == 'operation-not-allowed') {
          message = 'SMS not enabled. Please contact support.';
        }
        print('AUTH ERROR CODE: ${e.code}');
        print('AUTH ERROR MSG: ${e.message}');
        if (!controller.isClosed) {
          controller.addError(message);
          controller.close();
        }
      },
      codeSent: (String verificationId, int? resendToken) {
        if (!controller.isClosed) {
          controller.add(OtpSent(
            verificationId: verificationId,
            phoneNumber: phoneNumber.replaceFirst('+91', ''),
          ));
          controller.close();
        }
      },
      codeAutoRetrievalTimeout: (_) {},
    );

    return controller.stream;
  }

  Future<UserCredential> verifyOtp({
    required String verificationId,
    required String otp,
  }) async {
    final credential = PhoneAuthProvider.credential(
      verificationId: verificationId,
      smsCode: otp,
    );
    return await _auth.signInWithCredential(credential);
  }

  Future<void> signOut() async {
    await _auth.signOut();
  }
}