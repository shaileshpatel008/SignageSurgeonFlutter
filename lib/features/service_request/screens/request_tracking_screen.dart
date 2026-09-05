import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:razorpay_flutter/razorpay_flutter.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/services/quotation_pdf.dart';
import '../../../core/services/payment_receipt_pdf.dart';
import '../../../core/widgets/rejection_reason_dialog.dart';
import '../../../core/constants/app_routes.dart';
import '../../refund/screens/request_refund_screen.dart';
import '../../rating/screens/rating_card.dart';
import '../../support/screens/report_problem_screen.dart';

class RequestTrackingScreen extends StatefulWidget {
  const RequestTrackingScreen({super.key});

  @override
  State<RequestTrackingScreen> createState() => _RequestTrackingScreenState();
}

class _RequestTrackingScreenState extends State<RequestTrackingScreen> {
  final _razorpay = Razorpay();
  static const String _razorpayKeyId = 'rzp_test_TDKf4pilC4l0id';
  bool _busy = false;
  String? _requestId;
  String _collection = 'repair_requests';

  // Equipment transport charge (Ladder/H-Frame) — computed once per request
  // and shown in the on-screen quotation card, matching Cleaning's pattern.
  // Unlike Cleaning, distanceKm is already stored on these requests (from
  // the initial site-visit fee calc), so no fresh Google Maps call is needed.
  double? _equipmentTransportCharge;
  double? _equipmentTransportGst;
  double? _cachedTransportRate;
  // The flat per-request equipment fee (Ladder or H-Frame) — separate from
  // transport, not distance-based, admin-configurable from the same
  // app_settings/pricing_config document.
  double? _equipmentFee;
  String? _transportChargeComputedFor;
  String? _transportChargeError;

  double get _equipmentTransportTotal => (_equipmentTransportCharge ?? 0) + (_equipmentTransportGst ?? 0);

  Future<void> _maybeComputeTransportCharge(String requestId, Map<String, dynamic> data) async {
    if (_transportChargeComputedFor == requestId) return;
    final accessEquipment = data['accessEquipment'] as String?;
    if (accessEquipment != 'ladder' && accessEquipment != 'h_frame') {
      _transportChargeComputedFor = requestId;
      return;
    }
    _transportChargeComputedFor = requestId;
    try {
      final configDoc = await FirebaseFirestore.instance.collection('app_settings').doc('pricing_config').get();
      final config = configDoc.data();

      // Flat equipment fee — independent of distance, always applies once
      // Ladder/H-Frame is selected.
      final equipmentFee = accessEquipment == 'h_frame'
          ? (config?['hFrameEquipmentFee'] as num?)?.toDouble()
          : (config?['ladderEquipmentFee'] as num?)?.toDouble();

      // Distance-based transport charge — only if distance is available.
      final distanceKm = (data['distanceKm'] as num?)?.toDouble();
      final rate = (config?['transportPerKmRate'] as num?)?.toDouble();
      double? transportCharge;
      if (distanceKm != null && distanceKm > 0 && rate != null && rate > 0) {
        transportCharge = rate * distanceKm;
      }

      if (equipmentFee == null && transportCharge == null) {
        if (mounted) setState(() => _transportChargeError = 'No equipment pricing configured (app_settings/pricing_config missing ladderEquipmentFee/hFrameEquipmentFee/transportPerKmRate)');
        return;
      }

      if (mounted) {
        setState(() {
          _equipmentFee = equipmentFee;
          if (transportCharge != null) {
            _equipmentTransportCharge = transportCharge;
            _equipmentTransportGst = transportCharge * 0.18;
            _cachedTransportRate = rate;
          }
          _transportChargeError = null;
        });
      }
      // Persist so the web admin panel can read this directly too.
      try {
        await FirebaseFirestore.instance.collection(_collection).doc(requestId).update({
          if (equipmentFee != null) 'equipmentFee': equipmentFee,
          if (transportCharge != null) ...{
            'transportPerKmRateUsed': rate,
            'equipmentTransportCharge': transportCharge,
            'equipmentTransportGst': transportCharge * 0.18,
          },
        });
      } catch (_) {}
    } catch (e) {
      if (mounted) setState(() => _transportChargeError = 'Transport charge failed: $e');
    }
  }

  @override
  void initState() {
    super.initState();
    _razorpay.on(Razorpay.EVENT_PAYMENT_SUCCESS, _onPaymentSuccess);
    _razorpay.on(Razorpay.EVENT_PAYMENT_ERROR, _onPaymentError);
    _razorpay.on(Razorpay.EVENT_EXTERNAL_WALLET, (_) {});
  }

  @override
  void dispose() {
    _razorpay.clear();
    super.dispose();
  }

  Future<void> _rejectQuotation() async {
    if (_requestId == null) return;
    final result = await showRejectionReasonDialog(context);
    if (result == null) return;

    setState(() => _busy = true);
    try {
      await FirebaseFirestore.instance.collection(_collection).doc(_requestId).update({
        'trackingStage': 'quotation_rejected',
        'quotationRejectedAt': FieldValue.serverTimestamp(),
        'rejectionReason': result.fullReason,
      });
    } catch (_) {
      _showSnack('Could not reject quotation. Please try again.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _payQuotation(Map<String, dynamic> quotation) {
    setState(() => _busy = true);
    final serviceChargesNum = (quotation['serviceCharges'] as num?)?.toDouble() ?? 0;
    final additionalChargesNum = (quotation['additionalCharges'] as num?)?.toDouble() ?? 0;
    final gstPercentNum = (quotation['gstPercent'] as num?)?.toDouble() ?? 18;
    final subtotal = serviceChargesNum + additionalChargesNum + (_equipmentFee ?? 0) + (_equipmentTransportCharge ?? 0);
    final total = subtotal + (subtotal * gstPercentNum / 100);
    final amountPaise = (total * 100).round();
    final options = {
      'key': _razorpayKeyId,
      'amount': amountPaise,
      'currency': 'INR',
      'name': 'The Signage Surgeon',
      'description': 'Final Service Quotation Payment',
      'prefill': {'contact': FirebaseAuth.instance.currentUser?.phoneNumber ?? ''},
      'theme': {'color': '#FEC107'},
    };
    try {
      _razorpay.open(options);
    } catch (e) {
      _showSnack('Could not open payment screen. Please try again.');
      setState(() => _busy = false);
    }
  }

  void _onPaymentSuccess(PaymentSuccessResponse response) async {
    if (_requestId == null) return;
    try {
      await FirebaseFirestore.instance.collection(_collection).doc(_requestId).update({
        'trackingStage': 'quotation_paid',
        'quotationApprovedAt': FieldValue.serverTimestamp(),
        'quotationPaymentId': response.paymentId,
        'quotationPaymentStatus': 'paid',
      });
    } catch (e) {
      _showSnack('Payment succeeded but updating your request failed. Contact support with payment ID: ${response.paymentId}');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _onPaymentError(PaymentFailureResponse response) {
    if (mounted) setState(() => _busy = false);
    _showSnack('Payment failed or was cancelled. Tap Pay Now to retry.');
  }

  void _showSnack(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(backgroundColor: AppColors.red, content: Text(message, style: const TextStyle(color: Colors.white))),
    );
  }

  @override
  Widget build(BuildContext context) {
    final args = ModalRoute.of(context)?.settings.arguments;
    String? requestId;
    String collection = 'repair_requests';

    if (args is Map) {
      requestId = args['requestId'] as String?;
      collection = (args['collection'] as String?) ?? collection;
    } else if (args is String) {
      requestId = args;
    }
    _requestId = requestId;
    _collection = collection;

    if (requestId == null) {
      return Scaffold(
        backgroundColor: AppColors.offWhite,
        appBar: AppBar(backgroundColor: AppColors.offWhite, elevation: 0),
        body: const Center(child: Text('Request not found', style: TextStyle(color: AppColors.grey))),
      );
    }

    return Scaffold(
      backgroundColor: AppColors.offWhite,
      appBar: _buildAppBar(context),
      body: StreamBuilder<DocumentSnapshot>(
        stream: FirebaseFirestore.instance.collection(collection).doc(requestId).snapshots(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator(color: AppColors.yellow));
          }
          if (!snapshot.hasData || !snapshot.data!.exists) {
            return const Center(child: Text('This request could not be found.', style: TextStyle(color: AppColors.grey)));
          }

          final data = snapshot.data!.data() as Map<String, dynamic>;
          final quotationExists = data['finalQuotation'] != null;
          if (quotationExists) {
            WidgetsBinding.instance.addPostFrameCallback((_) => _maybeComputeTransportCharge(requestId!, data));
          }
          return _TrackingBody(
            requestId: requestId!,
            collection: collection,
            data: data,
            busy: _busy,
            equipmentTransportCharge: _equipmentTransportCharge,
            equipmentTransportGst: _equipmentTransportGst,
            transportRate: _cachedTransportRate,
            equipmentFee: _equipmentFee,
            transportChargeError: _transportChargeError,
            onReject: _rejectQuotation,
            onPay: _payQuotation,
          );
        },
      ),
    );
  }

  PreferredSizeWidget _buildAppBar(BuildContext context) {
    return AppBar(
      backgroundColor: AppColors.offWhite,
      elevation: 0,
      centerTitle: true,
      leading: GestureDetector(
        onTap: () => Navigator.of(context).popUntil((r) => r.isFirst),
        child: Container(
          margin: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: AppColors.white,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: AppColors.cardBorder),
          ),
          child: const Icon(Icons.home_outlined, color: AppColors.navy, size: 18),
        ),
      ),
      title: const Text('Track Your Request',
          style: TextStyle(color: AppColors.navy, fontSize: 17, fontWeight: FontWeight.w700)),
    );
  }
}

// Stage order (linear, except quotation_rejected which is a terminal branch
// off quotation_sent):
// submitted -> tech_assigned -> tech_en_route -> work_in_progress ->
// site_visit_completed -> quotation_sent -> quotation_approved/rejected ->
// quotation_paid -> tech_assigned_2 -> tech_en_route_2 -> work_in_progress_2 -> completed
const List<String> _stageOrder = [
  'submitted',
  'tech_assigned',
  'tech_en_route',
  'work_in_progress',
  'site_visit_completed',
  'quotation_sent',
  'quotation_approved',
  'quotation_paid',
  'tech_assigned_2',
  'tech_en_route_2',
  'work_in_progress_2',
  'completed',
];

class _TrackingBody extends StatelessWidget {
  final String requestId;
  final String collection;
  final Map<String, dynamic> data;
  final bool busy;
  final double? equipmentTransportCharge;
  final double? equipmentTransportGst;
  final double? transportRate;
  final double? equipmentFee;
  final String? transportChargeError;
  final VoidCallback onReject;
  final void Function(Map<String, dynamic> quotation) onPay;

  const _TrackingBody({
    required this.requestId,
    required this.collection,
    required this.data,
    required this.busy,
    this.equipmentTransportCharge,
    this.equipmentTransportGst,
    this.transportRate,
    this.equipmentFee,
    this.transportChargeError,
    required this.onReject,
    required this.onPay,
  });

  double get _equipmentTransportTotal => (equipmentTransportCharge ?? 0) + (equipmentTransportGst ?? 0);

  QuotationServiceCategory get _serviceCategory {
    switch (collection) {
      case 'rebranding_requests':
        return QuotationServiceCategory.rebranding;
      case 'new_signage_requests':
        return QuotationServiceCategory.newSignage;
      case 'repair_requests':
      default:
        return QuotationServiceCategory.repairing;
    }
  }

  ServiceCategory get _receiptServiceCategory {
    switch (collection) {
      case 'rebranding_requests':
        return ServiceCategory.rebranding;
      case 'new_signage_requests':
        return ServiceCategory.newSignage;
      case 'repair_requests':
      default:
        return ServiceCategory.repairing;
    }
  }

  /// Fetches the customer's saved profile (name, email, GST) once, at the
  /// moment a PDF is requested — not pre-loaded on every rebuild, since it's
  /// only needed for this occasional action.
  Future<Map<String, dynamic>?> _fetchCustomerProfile() async {
    final userId = data['userId'] as String?;
    if (userId == null) return null;
    try {
      final doc = await FirebaseFirestore.instance.collection('users').doc(userId).get();
      return doc.data();
    } catch (_) {
      return null;
    }
  }

  /// Loads the bundled brand assets for embedding in PDFs. Any asset that
  /// fails to load (e.g. not yet added to pubspec.yaml) is simply omitted —
  /// the PDF falls back to its text-only header / placeholder QR box rather
  /// than failing the whole generation.
  Future<({Uint8List? logo, Uint8List? mascot, Uint8List? qr})> _loadBrandAssets() async {
    Uint8List? logo, mascot, qr;
    try {
      logo = (await rootBundle.load('assets/images/logo.png')).buffer.asUint8List();
    } catch (_) {}
    try {
      mascot = (await rootBundle.load('assets/images/mascot.png')).buffer.asUint8List();
    } catch (_) {}
    try {
      qr = (await rootBundle.load('assets/images/qr_code.png')).buffer.asUint8List();
    } catch (_) {}
    return (logo: logo, mascot: mascot, qr: qr);
  }

  String get _stage => (data['trackingStage'] as String? ?? 'submitted').trim();
  bool get _rejected => _stage == 'quotation_rejected';

  int get _stageIndex {
    final i = _stageOrder.indexOf(_stage);
    return i == -1 ? 0 : i;
  }

  bool _reached(String stage) {
    if (_rejected) {
      // Once rejected, only steps up through quotation_sent are "reached".
      return _stageOrder.indexOf(stage) <= _stageOrder.indexOf('quotation_sent');
    }
    return _stageIndex >= _stageOrder.indexOf(stage);
  }

  @override
  Widget build(BuildContext context) {
    final signageType = data['signageType'] as String? ?? 'Service Request';
    final createdAt = data['createdAt'] as Timestamp?;
    final beyondRange = data['beyondServiceRange'] == true;
    final quotation = data['finalQuotation'] as Map<String, dynamic>?;

    final visit1Collapsed = _reached('quotation_sent');
    final visit2Started = _reached('quotation_paid') && !_rejected;

    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 30),
      children: [
        _summaryCard(signageType, createdAt, beyondRange),
        const SizedBox(height: 16),
        _siteVisitFeeReceiptCard(),
        if (!_reached('tech_assigned') && !_rejected && _stage != 'completed') ...[
          const SizedBox(height: 12),
          _cancelRequestButton(context),
        ],
        const SizedBox(height: 24),

        if (!visit1Collapsed) ...[
          _visitTracker(
            heading: null,
            techNameField: 'techName',
            visitDateField: 'visitDate',
            visitTimeStartField: 'visitTimeStart',
            visitTimeEndField: 'visitTimeEnd',
            arrivalOtpField: 'siteVisitArrivalOtp',
            completionOtpField: 'siteVisitCompletionOtp',
            assignedStage: 'tech_assigned',
            enRouteStage: 'tech_en_route',
            workInProgressStage: 'work_in_progress',
            doneStage: 'site_visit_completed',
            assignedTitle: 'Technician Assigned',
            enRouteTitle: 'Technician On The Way',
            workTitle: 'Problem Under Review',
            doneTitle: 'Site Visit Completed',
            submittedSubtitle: beyondRange
                ? 'We\'ve received your request. Our team will contact you shortly to schedule your visit.'
                : 'You will be notified shortly about your visit date and time.',
          ),
        ] else
          _collapsedRow('Site visit completed'),

        if (_stage == 'site_visit_completed' && quotation == null) ...[
          const SizedBox(height: 16),
          _preparingQuotationCard(),
        ],

        if (quotation != null) ...[
          const SizedBox(height: 20),
          _quotationSection(context, quotation),
        ],

        if (_rejected) ...[
          const SizedBox(height: 20),
          _rejectedCard(),
        ],

        if (visit2Started) ...[
          const SizedBox(height: 24),
          const Padding(
            padding: EdgeInsets.only(bottom: 4, left: 4),
            child: Text('Repair Work Visit', style: TextStyle(color: AppColors.navy, fontSize: 14, fontWeight: FontWeight.w700)),
          ),
          const SizedBox(height: 10),
          _visitTracker(
            heading: null,
            techNameField: 'techName2',
            visitDateField: 'visitDate2',
            visitTimeStartField: 'visitTimeStart2',
            visitTimeEndField: 'visitTimeEnd2',
            arrivalOtpField: 'workArrivalOtp',
            completionOtpField: 'workCompletionOtp',
            assignedStage: 'tech_assigned_2',
            enRouteStage: 'tech_en_route_2',
            workInProgressStage: 'work_in_progress_2',
            doneStage: 'completed',
            assignedTitle: 'Technician Assigned',
            enRouteTitle: 'Technician On The Way',
            workTitle: 'Work In Progress',
            doneTitle: 'Job Completed',
            skipFirstStep: true,
          ),
          if (_stage == 'completed') ...[
            const SizedBox(height: 12),
            _receiptCard(context, quotation),
            const SizedBox(height: 12),
            _requestRefundButton(context, quotation),
            const SizedBox(height: 12),
            RatingCard(
              collection: collection,
              requestId: requestId,
              serviceLabel: collection == 'rebranding_requests'
                  ? 'Rebranding'
                  : collection == 'new_signage_requests'
                      ? 'New Signage'
                      : 'Repairing',
            ),
            const SizedBox(height: 12),
            _reportProblemButton(context, collection == 'rebranding_requests'
                ? 'Rebranding'
                : collection == 'new_signage_requests'
                    ? 'New Signage'
                    : 'Repairing'),
          ],
        ],
      ],
    );
  }

  // ── One visit's mini-tracker (assigned -> en route -> work in progress -> done) ──

  Widget _visitTracker({
    required String? heading,
    required String techNameField,
    required String visitDateField,
    required String visitTimeStartField,
    required String visitTimeEndField,
    required String arrivalOtpField,
    required String completionOtpField,
    required String assignedStage,
    required String enRouteStage,
    required String workInProgressStage,
    required String doneStage,
    required String assignedTitle,
    required String enRouteTitle,
    required String workTitle,
    required String doneTitle,
    String? submittedSubtitle,
    bool skipFirstStep = false,
  }) {
    final techName = data[techNameField] as String?;
    final visitDate = data[visitDateField] as Timestamp?;
    final visitTimeStart = data[visitTimeStartField] as String?;
    final visitTimeEnd = data[visitTimeEndField] as String?;
    final arrivalOtp = data[arrivalOtpField] as String?;
    final completionOtp = data[completionOtpField] as String?;

    final children = <Widget>[];

    if (!skipFirstStep) {
      children.add(_stepTile(
        reached: true,
        isCurrent: _stage == 'submitted',
        icon: Icons.check_circle_outline,
        title: 'Request Submitted',
        subtitle: submittedSubtitle ?? '',
        isLast: false,
      ));
    }

    children.add(_stepTile(
      reached: _reached(assignedStage),
      isCurrent: _stage == assignedStage,
      icon: Icons.engineering_outlined,
      title: assignedTitle,
      subtitle: _reached(assignedStage)
          ? '${techName ?? 'Our technician'} will visit on ${_formatDate(visitDate)}${visitTimeStart != null ? ', $visitTimeStart - ${visitTimeEnd ?? ''}' : ''}'
          : 'Pending assignment — we\'ll notify you once scheduled.',
      isLast: false,
    ));

    children.add(_stepTile(
      reached: _reached(enRouteStage),
      isCurrent: _stage == enRouteStage,
      icon: Icons.directions_car_filled_outlined,
      title: enRouteTitle,
      subtitle: _reached(enRouteStage) ? 'Your technician is heading to your location.' : 'Not started yet.',
      isLast: false,
    ));

    if (_stage == enRouteStage && arrivalOtp != null) {
      children.add(Padding(
        padding: const EdgeInsets.only(top: 4, bottom: 4),
        child: _otpCard(arrivalOtp, 'Arrival OTP', 'Share this with your technician when they arrive.'),
      ));
    }

    children.add(_stepTile(
      reached: _reached(workInProgressStage),
      isCurrent: _stage == workInProgressStage,
      icon: Icons.build_circle_outlined,
      title: workTitle,
      subtitle: _reached(workInProgressStage) ? 'Your technician is currently working on this.' : 'Not started yet.',
      isLast: false,
    ));

    if (_stage == workInProgressStage && completionOtp != null) {
      children.add(Padding(
        padding: const EdgeInsets.only(top: 4, bottom: 4),
        child: _otpCard(completionOtp, 'Completion OTP', 'Share this with your technician once this step is finished.'),
      ));
    }

    children.add(_stepTile(
      reached: _reached(doneStage),
      isCurrent: false,
      icon: Icons.task_alt_outlined,
      title: doneTitle,
      subtitle: _reached(doneStage) ? 'Done.' : 'Not completed yet.',
      isLast: true,
    ));

    return Column(children: children);
  }

  Widget _collapsedRow(String label) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(color: AppColors.white, borderRadius: BorderRadius.circular(12), border: Border.all(color: AppColors.cardBorder)),
      child: Row(
        children: [
          const Icon(Icons.check_circle, color: AppColors.green, size: 18),
          const SizedBox(width: 10),
          Expanded(child: Text(label, style: const TextStyle(color: AppColors.navy, fontSize: 12.5, fontWeight: FontWeight.w600))),
        ],
      ),
    );
  }

  Widget _preparingQuotationCard() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.cardBorder),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.description_outlined, color: AppColors.yellowDark, size: 22),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Quotation Coming Soon', style: TextStyle(color: AppColors.navy, fontSize: 13.5, fontWeight: FontWeight.w700)),
                const SizedBox(height: 4),
                const Text(
                  'Our team is reviewing the findings from your site visit and preparing a detailed quotation for the required work. You will be notified as soon as it is ready for your review.',
                  style: TextStyle(color: AppColors.grey, fontSize: 12, height: 1.5),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _cancelRequestButton(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      child: OutlinedButton.icon(
        onPressed: () => _showCancelDialog(context),
        icon: const Icon(Icons.cancel_outlined, color: AppColors.grey, size: 16),
        label: const Text('Cancel Request', style: TextStyle(color: AppColors.grey, fontWeight: FontWeight.w600, fontSize: 12.5)),
        style: OutlinedButton.styleFrom(
          side: const BorderSide(color: AppColors.cardBorder, width: 1),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          padding: const EdgeInsets.symmetric(vertical: 12),
        ),
      ),
    );
  }

  Future<void> _showCancelDialog(BuildContext context) async {
    double cancellationChargePercent = 20; // fallback default, overridden below if configured
    try {
      final configDoc = await FirebaseFirestore.instance.collection('app_settings').doc('pricing_config').get();
      cancellationChargePercent = (configDoc.data()?['cancellationChargePercent'] as num?)?.toDouble() ?? 20;
    } catch (_) {}

    if (!context.mounted) return;
    final reasonController = TextEditingController();

    await showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Cancel This Request?'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'A cancellation charge of ${cancellationChargePercent.toStringAsFixed(0)}% of the site visit fee will apply, '
              'since a technician has not yet been assigned. The remaining amount will be refunded after review.',
              style: const TextStyle(fontSize: 13, height: 1.4),
            ),
            const SizedBox(height: 14),
            TextField(
              controller: reasonController,
              maxLines: 3,
              decoration: const InputDecoration(hintText: 'Reason for cancelling (optional)', border: OutlineInputBorder()),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogContext), child: const Text('Keep Request')),
          TextButton(
            onPressed: () async {
              Navigator.pop(dialogContext);
              await _cancelRequest(context, cancellationChargePercent, reasonController.text.trim());
            },
            child: const Text('Confirm Cancellation', style: TextStyle(color: AppColors.red)),
          ),
        ],
      ),
    );
  }

  Future<void> _cancelRequest(BuildContext context, double cancellationChargePercent, String reason) async {
    try {
      await FirebaseFirestore.instance.collection(collection).doc(requestId).update({
        'trackingStage': 'cancelled_by_customer',
        'cancelledAt': FieldValue.serverTimestamp(),
        'cancellationChargePercent': cancellationChargePercent,
      });

      final user = FirebaseAuth.instance.currentUser;
      final paymentId = data['paymentId'] as String?;
      if (user != null && paymentId != null && paymentId.trim().isNotEmpty) {
        await FirebaseFirestore.instance.collection('refund_requests').add({
          'requestId': requestId,
          'serviceCollection': collection,
          'userId': user.uid,
          'paymentAgainst': 'site_visit',
          'razorpayPaymentId': paymentId,
          'reason': reason.isNotEmpty
              ? 'Customer cancelled before technician assignment. Reason given: $reason'
              : 'Customer cancelled before technician assignment.',
          'status': 'pending',
          'createdAt': FieldValue.serverTimestamp(),
          'cancellationChargePercent': cancellationChargePercent,
        });
      }

      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Request cancelled. A refund request has been submitted for review.')),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Could not cancel request: $e')));
      }
    }
  }

  Widget _reportProblemButton(BuildContext context, String categoryLabel) {
    final signageType = data['signageType'] as String? ?? '';
    return SizedBox(
      width: double.infinity,
      child: OutlinedButton.icon(
        onPressed: () => Navigator.pushNamed(
          context,
          AppRoutes.reportProblem,
          arguments: {
            'collection': collection,
            'requestId': requestId,
            'serviceLabel': '$categoryLabel${signageType.isNotEmpty ? ' — $signageType' : ''}',
          },
        ),
        icon: const Icon(Icons.report_problem_outlined, color: AppColors.navy, size: 16),
        label: const Text('Report a Problem', style: TextStyle(color: AppColors.navy, fontWeight: FontWeight.w600, fontSize: 12.5)),
        style: OutlinedButton.styleFrom(
          side: const BorderSide(color: AppColors.cardBorder, width: 1),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          padding: const EdgeInsets.symmetric(vertical: 12),
        ),
      ),
    );
  }

  Widget _siteVisitFeeReceiptCard() {
    final paymentId = data['paymentId'] as String?;
    if (paymentId == null || paymentId.trim().isEmpty) return const SizedBox.shrink();

    final siteVisitFee = (data['siteVisitFee'] as num?)?.toDouble() ?? 0;
    final gstPercent = (data['gstPercent'] as num?)?.toDouble() ?? 18;
    final equipFee = (data['equipmentFee'] as num?)?.toDouble() ?? 0;
    final transportCharge = (data['equipmentTransportCharge'] as num?)?.toDouble() ?? 0;
    final accessEquipment = data['accessEquipment'] as String?;
    final subtotal = siteVisitFee + equipFee + transportCharge;
    final gstAmount = subtotal * (gstPercent / 100);
    final total = subtotal + gstAmount;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.green.withOpacity(0.35)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.check_circle, color: AppColors.green, size: 18),
              const SizedBox(width: 8),
              const Expanded(child: Text('Site Visit Fee — Paid', style: TextStyle(color: AppColors.navy, fontSize: 14, fontWeight: FontWeight.w700))),
            ],
          ),
          const SizedBox(height: 10),
          _feeRow('Visit Fee', '₹${siteVisitFee.toStringAsFixed(2)}'),
          if (equipFee > 0) _feeRow(accessEquipment == 'h_frame' ? 'H-Frame Equipment Fee' : 'Ladder Equipment Fee', '₹${equipFee.toStringAsFixed(2)}'),
          if (transportCharge > 0) _feeRow('Equipment Transport', '₹${transportCharge.toStringAsFixed(2)}'),
          _feeRow('GST (${gstPercent.toStringAsFixed(0)}%)', '₹${gstAmount.toStringAsFixed(2)}'),
          const Divider(color: AppColors.cardBorder, height: 18),
          _feeRow('Total Paid', '₹${total.toStringAsFixed(2)}', bold: true),
          const SizedBox(height: 4),
          Text('Payment ID: $paymentId', style: const TextStyle(color: AppColors.grey, fontSize: 10.5)),
        ],
      ),
    );
  }

  Widget _feeRow(String label, String value, {bool bold = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: TextStyle(color: AppColors.grey, fontSize: bold ? 13 : 12.5, fontWeight: bold ? FontWeight.w700 : FontWeight.w400)),
          Text(value, style: TextStyle(color: bold ? AppColors.red : AppColors.navy, fontSize: bold ? 14 : 12.5, fontWeight: FontWeight.w700)),
        ],
      ),
    );
  }

  Widget _summaryCard(String signageType, Timestamp? createdAt, bool beyondRange) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: AppColors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 10, offset: const Offset(0, 3))],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 44, height: 44,
                decoration: BoxDecoration(color: AppColors.yellow, borderRadius: BorderRadius.circular(12)),
                child: const Icon(Icons.receipt_long_outlined, color: Colors.white, size: 22),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(signageType, style: const TextStyle(color: AppColors.navy, fontSize: 15, fontWeight: FontWeight.w700)),
                    const SizedBox(height: 2),
                    Text('Submitted ${_formatDate(createdAt)}', style: const TextStyle(color: AppColors.grey, fontSize: 11.5)),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          const Divider(color: AppColors.cardBorder, height: 1),
          const SizedBox(height: 10),
          Row(
            children: [
              const Icon(Icons.tag, color: AppColors.grey, size: 13),
              const SizedBox(width: 5),
              Expanded(
                child: Text('Request ID: $requestId',
                    style: const TextStyle(color: AppColors.grey, fontSize: 11), overflow: TextOverflow.ellipsis),
              ),
            ],
          ),
          if (beyondRange) ...[
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(color: const Color(0xFFFFA500).withOpacity(0.12), borderRadius: BorderRadius.circular(8)),
              child: const Text('Outside standard fee slabs — visit charges to be confirmed by our team',
                  style: TextStyle(color: Color(0xFFFFA500), fontSize: 10.5, fontWeight: FontWeight.w600)),
            ),
          ],
        ],
      ),
    );
  }

  Widget _stepTile({
    required bool reached,
    required bool isCurrent,
    required IconData icon,
    required String title,
    required String subtitle,
    required bool isLast,
  }) {
    final color = reached ? AppColors.yellowDark : AppColors.greyLight;
    final textColor = reached ? AppColors.navy : AppColors.grey;

    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Column(
            children: [
              Container(
                width: 36, height: 36,
                decoration: BoxDecoration(
                  color: reached ? AppColors.yellow : AppColors.white,
                  shape: BoxShape.circle,
                  border: Border.all(color: color, width: isCurrent ? 2.5 : 1.5),
                ),
                child: Icon(icon, color: reached ? AppColors.navy : AppColors.greyLight, size: 18),
              ),
              if (!isLast)
                Expanded(
                  child: Container(
                    width: 2,
                    margin: const EdgeInsets.symmetric(vertical: 2),
                    color: reached ? AppColors.yellowDark : AppColors.greyLight,
                  ),
                ),
            ],
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Padding(
              padding: EdgeInsets.only(bottom: isLast ? 0 : 22, top: 6),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: TextStyle(color: textColor, fontSize: 14, fontWeight: isCurrent ? FontWeight.w800 : FontWeight.w700)),
                  const SizedBox(height: 4),
                  Text(subtitle, style: TextStyle(color: textColor.withOpacity(0.85), fontSize: 12, height: 1.4)),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _quotationSection(BuildContext context, Map<String, dynamic> quotation) {
    final serviceChargesNum = (quotation['serviceCharges'] as num?)?.toDouble() ?? 0;
    final additionalChargesNum = (quotation['additionalCharges'] as num?)?.toDouble() ?? 0;
    final gstPercentNum = (quotation['gstPercent'] as num?)?.toDouble() ?? 18;
    final transportChargeNum = equipmentTransportCharge ?? 0;
    final equipmentFeeNum = equipmentFee ?? 0;
    final accessEquipmentStr = quotation['accessEquipment'] as String?;
    // Single combined subtotal — Service + Additional + Equipment Fee +
    // Transport — with GST applied ONCE on that combined amount, matching
    // the web admin panel and the PDF. Admin's raw stored gstAmount/
    // totalPayable fields are no longer used directly here, since they were
    // computed before the auto equipment charges existed.
    final subtotal = serviceChargesNum + additionalChargesNum + equipmentFeeNum + transportChargeNum;
    final gstAmountNum = subtotal * (gstPercentNum / 100);
    final totalPayableNum = subtotal + gstAmountNum;
    final description = quotation['description']?.toString();
    final quotationNumber = quotation['quotationNumber']?.toString();

    // Description stays out of the label/value row list — long text gets its
    // own full-width paragraph instead of being squeezed into a value column.
    final rows = <MapEntry<String, String>>[
      MapEntry('Service Charges', '₹${serviceChargesNum.toStringAsFixed(2)}'),
      if (additionalChargesNum > 0) MapEntry('Additional Charges', '₹${additionalChargesNum.toStringAsFixed(2)}'),
      if (equipmentFeeNum > 0)
        MapEntry(accessEquipmentStr == 'h_frame' ? 'H-Frame Equipment Fee' : 'Ladder Equipment Fee', '₹${equipmentFeeNum.toStringAsFixed(2)}'),
      if (transportChargeNum > 0) MapEntry('Equipment Transport', '₹${transportChargeNum.toStringAsFixed(2)}'),
      MapEntry('GST (${gstPercentNum.toStringAsFixed(0)}%)', '₹${gstAmountNum.toStringAsFixed(2)}'),
      MapEntry('Total Payable', '₹${totalPayableNum.toStringAsFixed(2)}'),
    ];

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: AppColors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.yellowDark.withOpacity(0.5), width: 1),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 8, offset: const Offset(0, 3))],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.receipt_long_outlined, color: AppColors.yellowDark, size: 18),
              const SizedBox(width: 8),
              Expanded(child: Text('Final Service Quotation${quotationNumber != null ? ' #$quotationNumber' : ''}',
                  style: const TextStyle(color: AppColors.navy, fontSize: 14, fontWeight: FontWeight.w700))),
              if (_stage == 'quotation_approved' || _stage == 'quotation_paid' || _reached('quotation_paid'))
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(color: AppColors.green.withOpacity(0.15), borderRadius: BorderRadius.circular(6)),
                  child: const Text('Approved', style: TextStyle(color: AppColors.green, fontSize: 10, fontWeight: FontWeight.w700)),
                ),
            ],
          ),
          if (description != null && description.trim().isNotEmpty) ...[
            const SizedBox(height: 12),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(color: AppColors.offWhite, borderRadius: BorderRadius.circular(10)),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Work Description', style: TextStyle(color: AppColors.grey, fontSize: 11, fontWeight: FontWeight.w700)),
                  const SizedBox(height: 4),
                  Text(description, style: const TextStyle(color: AppColors.navy, fontSize: 12.5, height: 1.5)),
                ],
              ),
            ),
          ],
          const SizedBox(height: 12),
          if (transportChargeError != null) ...[
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(10),
              margin: const EdgeInsets.only(bottom: 10),
              decoration: BoxDecoration(color: AppColors.red.withOpacity(0.08), borderRadius: BorderRadius.circular(8)),
              child: Text(transportChargeError!, style: const TextStyle(color: AppColors.red, fontSize: 10.5)),
            ),
          ],
          ...rows.map((r) => _rowWidget(r.key, r.value)),
          const SizedBox(height: 14),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: () async {
                try {
                final profile = await _fetchCustomerProfile();
                final assets = await _loadBrandAssets();
                final serviceCharges = (quotation['serviceCharges'] as num?)?.toDouble() ?? 0;
                final additionalCharges = (quotation['additionalCharges'] as num?)?.toDouble() ?? 0;
                final gstPercentNum = (quotation['gstPercent'] as num?)?.toDouble() ?? 18;
                // Reuse the same value already shown on-screen and already
                // charged via Razorpay — guarantees the PDF always matches
                // exactly what the customer saw and paid.
                final transportCharge = equipmentTransportCharge ?? 0.0;
                final equipmentFeeCharge = equipmentFee ?? 0.0;
                final fullSubtotal = serviceCharges + additionalCharges + equipmentFeeCharge + transportCharge;
                final computedGstAmount = fullSubtotal * (gstPercentNum / 100);
                final computedGrandTotal = fullSubtotal + computedGstAmount;
                final now = DateTime.now();

                QuotationStatus status;
                if (_stage == 'quotation_rejected') {
                  status = QuotationStatus.rejected;
                } else if (_reached('quotation_paid')) {
                  status = QuotationStatus.approved;
                } else if (_stage == 'quotation_approved') {
                  status = QuotationStatus.approved;
                } else {
                  status = QuotationStatus.sent;
                }

                AccessEquipment? accessEquipment;
                switch (data['accessEquipment'] as String?) {
                  case 'ladder':
                    accessEquipment = AccessEquipment.ladder;
                    break;
                  case 'h_frame':
                    accessEquipment = AccessEquipment.hFrame;
                    break;
                  case 'not_needed':
                    accessEquipment = AccessEquipment.notNeeded;
                    break;
                }

                await QuotationPdf.generateAndShare(QuotationPdfData(
                  quotationNo: quotationNumber ?? requestId.substring(0, requestId.length < 8 ? requestId.length : 8),
                  requestId: requestId,
                  customerId: (data['userId'] as String?) ?? '',
                  date: now,
                  validTill: now.add(const Duration(days: 7)),
                  status: status,
                  customerName: (profile?['fullName'] as String?) ?? (profile?['businessName'] as String?) ?? 'Customer',
                  mobileNumber: FirebaseAuth.instance.currentUser?.phoneNumber,
                  email: profile?['email'] as String?,
                  siteAddress: (data['location'] as Map<String, dynamic>?)?['address'] as String?,
                  gstNumber: profile?['gstNumber'] as String?,
                  serviceCategory: _serviceCategory,
                  serviceType: (data['signageType'] as String?) ?? 'Service Request',
                  scopeOfWork: (description != null && description.trim().isNotEmpty)
                      ? description
                      : 'No additional description provided.',
                  // Note: this Firestore schema doesn't itemize by material/labour —
                  // it's a single service-charge line, so those tables are omitted
                  // and additionalCharges folds into the subtotal below.
                  serviceCharges: serviceCharges,
                  additionalCharges: additionalCharges,
                  subtotal: fullSubtotal,
                  discount: 0,
                  gstPercent: gstPercentNum,
                  grandTotal: computedGrandTotal,
                  paymentTerms: 'Advance payment is required before work begins.',
                  accessEquipment: accessEquipment,
                  ladderTentativePrice: (quotation['ladderTentativePrice'] as num?)?.toDouble(),
                  hFrameTentativePrice: (quotation['hFrameTentativePrice'] as num?)?.toDouble(),
                  equipmentFee: equipmentFeeCharge,
                  otherCharges: OtherCharges(
                    hFrameDailyRate: (quotation['hFrameDailyRate'] as num?)?.toDouble(),
                    transportPerKm: transportRate,
                    transportDistanceKm: (data['distanceKm'] as num?)?.toDouble(),
                  ),
                  logoBytes: assets.logo,
                  mascotBytes: assets.mascot,
                  qrCodeBytes: assets.qr,
                ));
                } catch (e) {
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(backgroundColor: AppColors.red, content: Text('PDF failed: $e', style: const TextStyle(color: Colors.white))),
                    );
                  }
                }
              },
              icon: const Icon(Icons.picture_as_pdf_outlined, color: AppColors.yellowDark, size: 16),
              label: const Text('Save as PDF', style: TextStyle(color: AppColors.yellowDark, fontWeight: FontWeight.w600, fontSize: 12.5)),
              style: OutlinedButton.styleFrom(
                side: const BorderSide(color: AppColors.yellowDark, width: 1),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                padding: const EdgeInsets.symmetric(vertical: 10),
              ),
            ),
          ),

          if (_stage == 'quotation_sent') ...[
            const SizedBox(height: 14),
            Row(
              children: [
                Expanded(
                  child: SizedBox(
                    height: 50,
                    child: ElevatedButton(
                      onPressed: busy ? null : onReject,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.red,
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        elevation: 0,
                      ),
                      child: const Text('REJECT', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 13)),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: SizedBox(
                    height: 50,
                    child: ElevatedButton(
                      onPressed: busy ? null : () => onPay(quotation),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.yellow,
                        foregroundColor: AppColors.navy,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        elevation: 0,
                      ),
                      child: busy
                          ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.navy))
                          : const Text('ACCEPT & PAY', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 12.5)),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _rejectedCard() {
    final reason = data['rejectionReason'] as String?;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.red.withOpacity(0.4), width: 1),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.cancel_outlined, color: AppColors.red, size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Quotation rejected. This request has been closed.',
                    style: TextStyle(color: AppColors.navy, fontSize: 12.5, height: 1.4)),
                if (reason != null) ...[
                  const SizedBox(height: 6),
                  Text('Reason: $reason', style: const TextStyle(color: AppColors.grey, fontSize: 11.5, height: 1.4)),
                ],
                const SizedBox(height: 4),
                const Text('Contact us if you\'d like a revised quote.',
                    style: TextStyle(color: AppColors.grey, fontSize: 11.5, height: 1.4)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _requestRefundButton(BuildContext context, Map<String, dynamic>? quotation) {
    final paymentOptions = <RefundablePayment>[];

    // Site-visit fee — paid at submission time, before any quotation existed.
    final siteVisitPaymentId = data['paymentId'] as String?;
    if (siteVisitPaymentId != null && siteVisitPaymentId.trim().isNotEmpty) {
      final siteVisitFee = (data['siteVisitFee'] as num?)?.toDouble() ?? 0;
      final siteVisitGstPercent = (data['gstPercent'] as num?)?.toDouble() ?? 18;
      final siteVisitSubtotal = siteVisitFee + (equipmentFee ?? 0) + (equipmentTransportCharge ?? 0);
      final siteVisitTotal = siteVisitSubtotal + (siteVisitSubtotal * siteVisitGstPercent / 100);
      paymentOptions.add(RefundablePayment(
        label: 'Site Visit Fee',
        paymentAgainst: 'site_visit',
        razorpayPaymentId: siteVisitPaymentId,
        amount: siteVisitTotal,
      ));
    }

    // Final quotation payment.
    final quotationPaymentId = data['quotationPaymentId'] as String?;
    if (quotationPaymentId != null && quotationPaymentId.trim().isNotEmpty) {
      final serviceChargesNum = quotation != null ? ((quotation['serviceCharges'] as num?)?.toDouble() ?? 0) : 0.0;
      final additionalChargesNum = quotation != null ? ((quotation['additionalCharges'] as num?)?.toDouble() ?? 0) : 0.0;
      final gstPercentNum = quotation != null ? ((quotation['gstPercent'] as num?)?.toDouble() ?? 18) : 18.0;
      final subtotal = serviceChargesNum + additionalChargesNum + (equipmentFee ?? 0) + (equipmentTransportCharge ?? 0);
      final total = subtotal + (subtotal * gstPercentNum / 100);
      paymentOptions.add(RefundablePayment(
        label: 'Final Quotation Payment',
        paymentAgainst: 'quotation',
        razorpayPaymentId: quotationPaymentId,
        amount: total,
      ));
    }

    if (paymentOptions.isEmpty) return const SizedBox.shrink();

    String categoryLabel;
    switch (collection) {
      case 'rebranding_requests':
        categoryLabel = 'Rebranding';
        break;
      case 'new_signage_requests':
        categoryLabel = 'New Signage';
        break;
      case 'repair_requests':
      default:
        categoryLabel = 'Repairing';
    }
    final signageType = data['signageType'] as String? ?? '';

    return SizedBox(
      width: double.infinity,
      child: OutlinedButton.icon(
        onPressed: () => Navigator.pushNamed(
          context,
          AppRoutes.requestRefund,
          arguments: {
            'collection': collection,
            'requestId': requestId,
            'serviceLabel': '$categoryLabel${signageType.isNotEmpty ? ' — $signageType' : ''}',
            'paymentOptions': paymentOptions,
          },
        ),
        icon: const Icon(Icons.currency_rupee_outlined, color: AppColors.red, size: 16),
        label: const Text('Request Refund', style: TextStyle(color: AppColors.red, fontWeight: FontWeight.w600, fontSize: 12.5)),
        style: OutlinedButton.styleFrom(
          side: const BorderSide(color: AppColors.red, width: 1),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          padding: const EdgeInsets.symmetric(vertical: 12),
        ),
      ),
    );
  }


  Widget _receiptCard(BuildContext context, Map<String, dynamic>? quotation) {
    final serviceChargesNum = quotation != null ? ((quotation['serviceCharges'] as num?)?.toDouble() ?? 0) : 0.0;
    final additionalChargesNum = quotation != null ? ((quotation['additionalCharges'] as num?)?.toDouble() ?? 0) : 0.0;
    final gstPercentNum = quotation != null ? ((quotation['gstPercent'] as num?)?.toDouble() ?? 18) : 18.0;
    final subtotal = serviceChargesNum + additionalChargesNum + (equipmentFee ?? 0) + (equipmentTransportCharge ?? 0);
    final actualTotalPaid = subtotal + (subtotal * gstPercentNum / 100);
    final rows = [
      MapEntry('Total Paid', '₹${actualTotalPaid.toStringAsFixed(2)}'),
      MapEntry('Payment ID', '${data['quotationPaymentId'] ?? '-'}'),
    ];
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.green.withOpacity(0.4), width: 1),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(Icons.check_circle, color: AppColors.green, size: 18),
              SizedBox(width: 8),
              Text('Payment Receipt', style: TextStyle(color: AppColors.navy, fontSize: 13, fontWeight: FontWeight.w700)),
            ],
          ),
          const SizedBox(height: 10),
          ...rows.map((r) => _rowWidget(r.key, r.value)),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: () async {
                try {
                final profile = await _fetchCustomerProfile();
                final assets = await _loadBrandAssets();
                final totalPayableNum = quotation != null ? ((quotation['totalPayable'] as num?)?.toDouble() ?? 0) : 0.0;
                final serviceChargesNum = quotation != null ? ((quotation['serviceCharges'] as num?)?.toDouble() ?? 0) : 0.0;
                final additionalChargesNum = quotation != null ? ((quotation['additionalCharges'] as num?)?.toDouble() ?? 0) : 0.0;
                final gstPercentNum = quotation != null ? ((quotation['gstPercent'] as num?)?.toDouble() ?? 18) : 18.0;

                await PaymentReceiptPdf.generateAndShare(PaymentReceiptData(
                  receiptNo: requestId.substring(0, requestId.length < 8 ? requestId.length : 8),
                  paymentId: data['quotationPaymentId'] as String?,
                  requestId: requestId,
                  quotationNo: quotation?['quotationNumber']?.toString(),
                  receiptDate: DateTime.now(),
                  paymentDate: DateTime.now(),
                  status: PaymentStatus.paid,
                  customerName: (profile?['fullName'] as String?) ?? (profile?['businessName'] as String?) ?? 'Customer',
                  mobileNumber: FirebaseAuth.instance.currentUser?.phoneNumber,
                  emailAddress: profile?['email'] as String?,
                  siteAddress: (data['location'] as Map<String, dynamic>?)?['address'] as String?,
                  gstNumber: profile?['gstNumber'] as String?,
                  serviceCategory: _receiptServiceCategory,
                  serviceType: (data['signageType'] as String?) ?? 'Service Request',
                  paymentAgainst: PaymentAgainst.finalPayment,
                  amountBeforeGst: serviceChargesNum + additionalChargesNum + (equipmentFee ?? 0) + (equipmentTransportCharge ?? 0),
                  serviceChargesItem: serviceChargesNum,
                  additionalChargesItem: additionalChargesNum,
                  equipmentFeeItem: equipmentFee,
                  transportChargeItem: equipmentTransportCharge,
                  accessEquipmentLabel: (data['accessEquipment'] as String?) == 'h_frame' ? 'H-Frame' : 'Ladder',
                  gstPercent: gstPercentNum,
                  totalAmount: totalPayableNum,
                  amountPaid: totalPayableNum,
                  balanceAmount: 0,
                  paymentMethod: PaymentMethod.upi,
                  logoBytes: assets.logo,
                  mascotBytes: assets.mascot,
                  qrCodeBytes: assets.qr,
                ));
                } catch (e) {
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(backgroundColor: AppColors.red, content: Text('PDF failed: $e', style: const TextStyle(color: Colors.white))),
                    );
                  }
                }
              },
              icon: const Icon(Icons.picture_as_pdf_outlined, color: AppColors.yellowDark, size: 16),
              label: const Text('Download Receipt', style: TextStyle(color: AppColors.yellowDark, fontWeight: FontWeight.w600, fontSize: 12.5)),
              style: OutlinedButton.styleFrom(
                side: const BorderSide(color: AppColors.yellowDark, width: 1),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                padding: const EdgeInsets.symmetric(vertical: 10),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _rowWidget(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(flex: 3, child: Text(label, style: const TextStyle(color: AppColors.grey, fontSize: 12.5))),
          const SizedBox(width: 10),
          Expanded(
            flex: 2,
            child: Text(value, textAlign: TextAlign.right, style: const TextStyle(color: AppColors.navy, fontSize: 12.5, fontWeight: FontWeight.w700)),
          ),
        ],
      ),
    );
  }

  Widget _otpCard(String otp, String label, String helperText) {
    return Container(
      margin: const EdgeInsets.only(left: 50),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.yellow.withOpacity(0.15),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.yellowDark, width: 1),
      ),
      child: Row(
        children: [
          const Icon(Icons.password_outlined, color: AppColors.yellowDark, size: 22),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: const TextStyle(color: AppColors.navy, fontSize: 12, fontWeight: FontWeight.w700)),
                const SizedBox(height: 4),
                Text(otp, style: const TextStyle(color: AppColors.navy, fontSize: 22, fontWeight: FontWeight.w800, letterSpacing: 4)),
                const SizedBox(height: 4),
                Text(helperText, style: const TextStyle(color: AppColors.grey, fontSize: 10.5, height: 1.3)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  String _num(dynamic v) {
    if (v == null) return '0';
    if (v is num) return v.toStringAsFixed(0);
    return v.toString();
  }

  String _formatDate(Timestamp? ts) {
    if (ts == null) return 'TBD';
    final dt = ts.toDate();
    const months = ['Jan','Feb','Mar','Apr','May','Jun','Jul','Aug','Sep','Oct','Nov','Dec'];
    return '${dt.day} ${months[dt.month - 1]} ${dt.year}';
  }
}