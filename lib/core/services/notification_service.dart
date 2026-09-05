import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

/// Watches every trackable request collection for the logged-in user and
/// generates an in-app notification the moment a stage/phase field changes —
/// whether that change came from the customer's own action (payment, approve,
/// reject) or from an admin editing Firestore directly.
///
/// Since there's no admin app or Cloud Function yet, this is the only way to
/// surface admin-side changes to the customer. It works whether the app is
/// open when the change happens, or closed and reopened later — the
/// `lastNotifiedStage` field written back onto each request document is what
/// prevents the same stage from notifying twice.
class NotificationService {
  NotificationService._();
  static final NotificationService instance = NotificationService._();

  final List<StreamSubscription<QuerySnapshot>> _subs = [];
  bool _started = false;

  // ── Per-collection config: which field holds the "current stage", and
  // the human-readable title/body for each value that field can take. ──

  static const _collections = <String, _CollectionConfig>{
    'repair_requests': _CollectionConfig(
      stageField: 'trackingStage',
      labelField: 'signageType',
      defaultLabel: 'Repairing Request',
      messages: {
        'tech_assigned': _Msg('Technician Assigned', 'A technician has been assigned to your repair request.'),
        'tech_en_route': _Msg('Technician On The Way', 'Your technician is heading to your location. Check the OTP on your tracking page.'),
        'work_in_progress': _Msg('Assessment In Progress', 'Your technician has arrived and is reviewing the issue.'),
        'site_visit_completed': _Msg('Site Visit Completed', 'We\'re preparing your service quotation.'),
        'quotation_sent': _Msg('Quotation Ready', 'Your repair quotation is ready to review.'),
        'quotation_rejected': _Msg('Request Closed', 'Your quotation was rejected and the request is now closed.'),
        'quotation_paid': _Msg('Payment Successful', 'Your repair work will begin shortly.'),
        'tech_assigned_2': _Msg('Technician Assigned', 'A technician has been assigned for your repair work.'),
        'tech_en_route_2': _Msg('Technician On The Way', 'Your technician is heading over to start the repair. Check the OTP on your tracking page.'),
        'work_in_progress_2': _Msg('Repair Work Started', 'Your repair is now in progress.'),
        'completed': _Msg('Job Completed', 'Your repair request has been completed. Thank you!'),
      },
    ),
    'rebranding_requests': _CollectionConfig(
      stageField: 'trackingStage',
      labelField: 'signageType',
      defaultLabel: 'Rebranding Request',
      messages: {
        'tech_assigned': _Msg('Technician Assigned', 'A technician has been assigned to your rebranding request.'),
        'tech_en_route': _Msg('Technician On The Way', 'Your technician is heading to your location. Check the OTP on your tracking page.'),
        'work_in_progress': _Msg('Assessment In Progress', 'Your technician has arrived and is reviewing the work needed.'),
        'site_visit_completed': _Msg('Site Visit Completed', 'We\'re preparing your service quotation.'),
        'quotation_sent': _Msg('Quotation Ready', 'Your rebranding quotation is ready to review.'),
        'quotation_rejected': _Msg('Request Closed', 'Your quotation was rejected and the request is now closed.'),
        'quotation_paid': _Msg('Payment Successful', 'Your rebranding work will begin shortly.'),
        'tech_assigned_2': _Msg('Technician Assigned', 'A technician has been assigned for your rebranding work.'),
        'tech_en_route_2': _Msg('Technician On The Way', 'Your technician is heading over to start work. Check the OTP on your tracking page.'),
        'work_in_progress_2': _Msg('Work Started', 'Your rebranding work is now in progress.'),
        'completed': _Msg('Job Completed', 'Your rebranding request has been completed. Thank you!'),
      },
    ),
    'new_signage_requests': _CollectionConfig(
      stageField: 'trackingStage',
      labelField: 'signageType',
      defaultLabel: 'New Signage Request',
      messages: {
        'tech_assigned': _Msg('Technician Assigned', 'A technician has been assigned to your new signage request.'),
        'tech_en_route': _Msg('Technician On The Way', 'Your technician is heading to your location. Check the OTP on your tracking page.'),
        'work_in_progress': _Msg('Assessment In Progress', 'Your technician has arrived and is reviewing the installation.'),
        'site_visit_completed': _Msg('Site Visit Completed', 'We\'re preparing your service quotation.'),
        'quotation_sent': _Msg('Quotation Ready', 'Your new signage quotation is ready to review.'),
        'quotation_rejected': _Msg('Request Closed', 'Your quotation was rejected and the request is now closed.'),
        'quotation_paid': _Msg('Payment Successful', 'Your installation work will begin shortly.'),
        'tech_assigned_2': _Msg('Technician Assigned', 'A technician has been assigned for your installation.'),
        'tech_en_route_2': _Msg('Technician On The Way', 'Your technician is heading over to start installation. Check the OTP on your tracking page.'),
        'work_in_progress_2': _Msg('Installation Started', 'Your new signage installation is now in progress.'),
        'completed': _Msg('Job Completed', 'Your new signage request has been completed. Thank you!'),
      },
    ),
    'cleaning_requests': _CollectionConfig(
      stageField: 'trackingStage',
      phaseField: 'cleaningPhase',
      labelField: 'signageType',
      defaultLabel: 'Signage Cleaning',
      messages: {
        // cleaningPhase values
        'quotation_review': _Msg('Quotation Ready', 'Your cleaning service quotation is ready to review.'),
        'rejected': _Msg('Request Closed', 'Your quotation was rejected and the request is now closed.'),
        'active': _Msg('Payment Successful', 'Your cleaning team will be scheduled shortly.'),
        // trackingStage values (only relevant once cleaningPhase == active)
        'tech_assigned': _Msg('Team Assigned', 'A cleaning team has been assigned to your request.'),
        'tech_en_route': _Msg('Team On The Way', 'Your cleaning team is heading over. Check the Starting OTP on your tracking page.'),
        'work_in_progress': _Msg('Cleaning In Progress', 'Your cleaning service is now in progress. Check the Completion OTP on your tracking page.'),
        'completed': _Msg('Cleaning Completed', 'Your signage cleaning has been completed. Thank you!'),
      },
    ),
    'amc_requests': _CollectionConfig(
      stageField: 'amcPhase',
      labelField: 'requirementType',
      defaultLabel: 'Signage AMC',
      messages: {
        'audit_proposal_sent': _Msg('Audit Proposal Ready', 'Your AMC audit fee proposal is ready to review.'),
        'audit_paid': _Msg('Payment Successful', 'Your signage audit will be scheduled shortly.'),
        'audit_scheduled': _Msg('Audit Scheduled', 'Your AMC audit visit has been scheduled.'),
        'audit_in_progress': _Msg('Audit Team On The Way', 'Your audit team is heading to your location.'),
        'audit_completed': _Msg('Audit Completed', 'We\'re preparing your AMC quotation.'),
        'final_quotation_sent': _Msg('AMC Quotation Ready', 'Your final AMC quotation is ready to review and pay.'),
        'amc_confirmed': _Msg('AMC Confirmed', 'Your Signage AMC has been confirmed. Thank you!'),
      },
    ),
    'sign_shoppy_interests': _CollectionConfig(
      stageField: 'orderPhase',
      labelField: 'productName',
      defaultLabel: 'Sign Shoppy Order',
      messages: {
        'quotation_sent': _Msg('Quotation Ready', 'A quotation for your product interest is ready to review.'),
        'quotation_rejected': _Msg('Order Closed', 'Your quotation was rejected and the order is now closed.'),
        'paid': _Msg('Payment Successful', 'Your order will be confirmed shortly.'),
        'order_confirmed': _Msg('Order Confirmed', 'Your order has been confirmed with an expected delivery date.'),
        'order_on_the_way': _Msg('Order On The Way', 'Your order is out for delivery. Check the Delivery OTP on your tracking page.'),
        'order_received': _Msg('Order Delivered', 'Your order has been delivered. Thank you!'),
      },
    ),
  };

  /// Call once after login (e.g. in the home screen's initState).
  void start() {
    if (_started) return;
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;
    _started = true;

    for (final entry in _collections.entries) {
      final collectionName = entry.key;
      final config = entry.value;
      final sub = FirebaseFirestore.instance
          .collection(collectionName)
          .where('userId', isEqualTo: user.uid)
          .snapshots()
          .listen((snapshot) {
        for (final doc in snapshot.docs) {
          _checkAndNotify(collectionName, config, doc, user.uid);
        }
      });
      _subs.add(sub);
    }
  }

  /// Call on logout to stop listening.
  void stop() {
    for (final s in _subs) {
      s.cancel();
    }
    _subs.clear();
    _started = false;
  }

  Future<void> _checkAndNotify(
    String collectionName,
    _CollectionConfig config,
    QueryDocumentSnapshot doc,
    String uid,
  ) async {
    final data = doc.data() as Map<String, dynamic>;

    // For Cleaning, the meaningful "current stage" depends on which phase
    // we're in — cleaningPhase while pre-payment, trackingStage once active.
    String? currentStage;
    if (config.phaseField != null) {
      final phase = (data[config.phaseField!] as String?)?.trim();
      if (phase == 'active') {
        currentStage = (data[config.stageField] as String?)?.trim();
      } else {
        currentStage = phase;
      }
    } else {
      currentStage = (data[config.stageField] as String?)?.trim();
    }

    if (currentStage == null) return;
    final msg = config.messages[currentStage];
    if (msg == null) return; // not a stage we notify on (e.g. 'submitted')

    final lastNotified = (data['lastNotifiedStage'] as String?)?.trim();
    if (lastNotified == currentStage) return; // already notified this exact stage

    final label = (data[config.labelField] as String?) ?? config.defaultLabel;

    try {
      // Write the notification.
      await FirebaseFirestore.instance
          .collection('users')
          .doc(uid)
          .collection('notifications')
          .add({
        'title': msg.title,
        'body': '$label — ${msg.body}',
        'createdAt': FieldValue.serverTimestamp(),
        'read': false,
        'sourceCollection': collectionName,
        'sourceRequestId': doc.id,
      });

      // Mark this stage as notified so it never fires again for this doc.
      await FirebaseFirestore.instance
          .collection(collectionName)
          .doc(doc.id)
          .update({'lastNotifiedStage': currentStage});
    } catch (_) {
      // Silently ignore — worst case, the customer just doesn't get this
      // one notification; it shouldn't crash anything else.
    }
  }
}

class _CollectionConfig {
  final String stageField;
  final String? phaseField;
  final String labelField;
  final String defaultLabel;
  final Map<String, _Msg> messages;

  const _CollectionConfig({
    required this.stageField,
    this.phaseField,
    required this.labelField,
    required this.defaultLabel,
    required this.messages,
  });
}

class _Msg {
  final String title;
  final String body;
  const _Msg(this.title, this.body);
}