import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../constants/app_routes.dart';
import '../navigation/navigator_key.dart';

/// Must be a top-level (or static) function — this is what lets the Flutter
/// engine call it even when the app is fully terminated. It doesn't need to
/// do anything itself: FCM already shows the system notification
/// automatically from the payload's `notification` block when the app isn't
/// in the foreground. This handler just needs to exist and be registered.
@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {}

class PushNotificationService {
  PushNotificationService._();
  static final PushNotificationService instance = PushNotificationService._();

  final FirebaseMessaging _messaging = FirebaseMessaging.instance;
  bool _initialized = false;

  /// Call once after login (e.g. in the home screen's initState, right
  /// alongside NotificationService.instance.start()).
  Future<void> init() async {
    if (_initialized) return;
    _initialized = true;

    // iOS + Android 13+ both require an explicit permission prompt.
    await _messaging.requestPermission(alert: true, badge: true, sound: true);

    await _saveTokenToFirestore();
    _messaging.onTokenRefresh.listen((_) => _saveTokenToFirestore());

    // App is open and in the foreground: FCM does NOT auto-show a system
    // notification in this state, so we show a lightweight in-app banner
    // instead, with a "View" action that deep-links the same as a tap would.
    FirebaseMessaging.onMessage.listen(_showForegroundBanner);

    // App was in the background (minimized) and the user tapped the
    // system notification to reopen it.
    FirebaseMessaging.onMessageOpenedApp.listen(_handleTap);

    // App was fully closed and the user tapped the system notification,
    // which cold-started the app. getInitialMessage only returns a value
    // on that exact cold-start path.
    final initialMessage = await _messaging.getInitialMessage();
    if (initialMessage != null) {
      // Wait a frame so the navigator has actually mounted before we push.
      WidgetsBinding.instance.addPostFrameCallback((_) => _handleTap(initialMessage));
    }
  }

  Future<void> _saveTokenToFirestore() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;
    try {
      final token = await _messaging.getToken();
      if (token == null) return;
      await FirebaseFirestore.instance.collection('users').doc(user.uid).set(
        {'fcmToken': token},
        SetOptions(merge: true),
      );
    } catch (_) {
      // Non-fatal — the customer simply won't get push until this succeeds
      // on a later app open. In-app notifications still work regardless.
    }
  }

  void _showForegroundBanner(RemoteMessage message) {
    final context = rootNavigatorKey.currentState?.overlay?.context;
    if (context == null) return;
    final title = message.notification?.title ?? 'Update';
    final body = message.notification?.body ?? '';

    final messenger = ScaffoldMessenger.of(context);
    // Clear any snackbar still showing first — otherwise a second
    // notification arriving quickly can make it look like the first one
    // never auto-dismissed, since the new one just replaces it.
    messenger.hideCurrentSnackBar();
    messenger.showSnackBar(
      SnackBar(
        content: Text(body.isNotEmpty ? '$title — $body' : title, maxLines: 2, overflow: TextOverflow.ellipsis),
        action: SnackBarAction(label: 'VIEW', onPressed: () => _handleTap(message)),
        duration: const Duration(seconds: 5),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  void _handleTap(RemoteMessage message) {
    final navigator = rootNavigatorKey.currentState;
    if (navigator == null) return;

    final collection = message.data['sourceCollection'] as String?;
    final requestId = message.data['sourceRequestId'] as String?;
    if (collection == null || collection.isEmpty || requestId == null || requestId.isEmpty) return;

    const dedicatedRoutes = {
      'cleaning_requests': AppRoutes.cleaningTracking,
      'amc_requests': AppRoutes.amcTracking,
      'sign_shoppy_interests': AppRoutes.signShoppyTracking,
    };

    final dedicated = dedicatedRoutes[collection];
    if (dedicated != null) {
      navigator.pushNamed(dedicated, arguments: requestId);
    } else {
      navigator.pushNamed(AppRoutes.requestTracking, arguments: {'collection': collection, 'requestId': requestId});
    }
  }

  /// Call on logout so a signed-out device stops receiving pushes meant for
  /// the previous account.
  Future<void> clearToken() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;
    try {
      await FirebaseFirestore.instance.collection('users').doc(user.uid).update({'fcmToken': FieldValue.delete()});
      await _messaging.deleteToken();
    } catch (_) {}
    _initialized = false;
  }
}