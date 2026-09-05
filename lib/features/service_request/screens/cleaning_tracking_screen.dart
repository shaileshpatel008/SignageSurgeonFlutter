import 'package:flutter/material.dart';
import 'dart:math';
import 'dart:typed_data';
import 'package:flutter/services.dart' show rootBundle;
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:razorpay_flutter/razorpay_flutter.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/services/quotation_pdf.dart';
import '../../../core/services/payment_receipt_pdf.dart';
import '../../../core/services/distance_fee_service.dart';
import '../../../core/widgets/rejection_reason_dialog.dart';
import '../../../core/constants/app_routes.dart';
import '../../refund/screens/request_refund_screen.dart';
import '../../rating/screens/rating_card.dart';
import '../../support/screens/report_problem_screen.dart';

class CleaningTrackingScreen extends StatefulWidget {
  const CleaningTrackingScreen({super.key});

  @override
  State<CleaningTrackingScreen> createState() => _CleaningTrackingScreenState();
}

class _CleaningTrackingScreenState extends State<CleaningTrackingScreen> {
  final _razorpay = Razorpay();
  static const String _razorpayKeyId = 'rzp_test_TDKf4pilC4l0id';
  bool _paying = false;
  bool _approving = false;
  bool _rejecting = false;
  String? _requestId;

  // Equipment transport charge (Ladder/H-Frame) — computed once per request,
  // shown in the quotation card and folded into the actual payment amount.
  double? _equipmentTransportCharge;
  double? _equipmentTransportGst;
  bool _loadingTransportCharge = false;
  String? _transportChargeError;
  String? _transportChargeComputedFor;
  double? _cachedTransportRate;
  double? _cachedTransportDistanceKm;
  // The flat per-request equipment fee (Ladder or H-Frame) — separate from
  // transport, not distance-based.
  double? _equipmentFee;

  double get _equipmentTransportTotal => (_equipmentTransportCharge ?? 0) + (_equipmentTransportGst ?? 0);

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

  /// Computes the equipment fee + transport charge once per request (not on
  /// every rebuild) so the customer sees the real, correct total in the
  /// quotation card BEFORE they pay — not just in the PDF afterward.
  Future<void> _maybeComputeTransportCharge(String requestId, Map<String, dynamic> data) async {
    if (_transportChargeComputedFor == requestId) return;
    final accessEquipment = data['accessEquipment'] as String?;
    if (accessEquipment != 'ladder' && accessEquipment != 'h_frame') {
      _transportChargeComputedFor = requestId;
      return;
    }

    _transportChargeComputedFor = requestId; // mark immediately to prevent duplicate concurrent calls
    if (mounted) setState(() => _loadingTransportCharge = true);
    try {
      final configDoc = await FirebaseFirestore.instance
          .collection('app_settings')
          .doc('pricing_config')
          .get()
          .timeout(const Duration(seconds: 12));
      final config = configDoc.data();

      // Flat equipment fee — independent of distance/location, always
      // applies once Ladder/H-Frame is selected.
      final equipmentFee = accessEquipment == 'h_frame'
          ? (config?['hFrameEquipmentFee'] as num?)?.toDouble()
          : (config?['ladderEquipmentFee'] as num?)?.toDouble();

      // Distance-based transport charge — only if location is available.
      // Cleaning has no existing distance/fee-slab system, so unlike the
      // other services, distance isn't already stored — fetch it on demand
      // here, only when actually needed for a transport charge.
      final rate = (config?['transportPerKmRate'] as num?)?.toDouble();
      double? distanceKm;
      double? transportCharge;
      final loc = data['location'] as Map<String, dynamic>?;
      final lat = (loc?['lat'] as num?)?.toDouble();
      final lng = (loc?['lng'] as num?)?.toDouble();
      if (rate != null && rate > 0 && lat != null && lng != null) {
        distanceKm = await DistanceFeeService.getRoadDistanceKm(destLat: lat, destLng: lng)
            .timeout(const Duration(seconds: 15));
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
            _equipmentTransportGst = transportCharge! * 0.18;
            _cachedTransportRate = rate;
            _cachedTransportDistanceKm = distanceKm;
          }
          _transportChargeError = null;
        });
      }
      // Write back to Firestore so the web admin panel can read this directly
      // rather than needing to replicate the distance calculation itself.
      try {
        await FirebaseFirestore.instance.collection('cleaning_requests').doc(requestId).update({
          if (equipmentFee != null) 'equipmentFee': equipmentFee,
          if (transportCharge != null) ...{
            'distanceKm': distanceKm,
            'transportPerKmRateUsed': rate,
            'equipmentTransportCharge': transportCharge,
            'equipmentTransportGst': transportCharge * 0.18,
          },
        });
      } catch (_) {}
    } catch (e) {
      // Surfaced now instead of silently doing nothing, so failures are
      // actually visible during testing rather than looking like a stuck
      // loading state.
      if (mounted) setState(() => _transportChargeError = 'Transport charge calculation failed: $e');
    } finally {
      if (mounted) setState(() => _loadingTransportCharge = false);
    }
  }

  Future<void> _rejectQuotation() async {
    if (_requestId == null) return;
    final result = await showRejectionReasonDialog(context);
    if (result == null) return;

    setState(() => _rejecting = true);
    try {
      await FirebaseFirestore.instance.collection('cleaning_requests').doc(_requestId).update({
        'cleaningPhase': 'rejected',
        'quotationRejectedAt': FieldValue.serverTimestamp(),
        'rejectionReason': result.fullReason,
      });
    } catch (_) {
      _showSnack('Could not reject quotation. Please try again.');
    } finally {
      if (mounted) setState(() => _rejecting = false);
    }
  }

  void _openPayNow(Map<String, dynamic> quotation) {
    setState(() => _paying = true);
    final serviceCharges = (quotation['serviceCharges'] as num?)?.toDouble() ?? 0;
    final additionalCharges = (quotation['additionalCharges'] as num?)?.toDouble() ?? 0;
    final gstPercent = (quotation['gstPercent'] as num?)?.toDouble() ?? 18;
    final subtotal = serviceCharges + additionalCharges + (_equipmentFee ?? 0) + (_equipmentTransportCharge ?? 0);
    final totalPayable = subtotal + (subtotal * gstPercent / 100);
    final amountPaise = (totalPayable * 100).round();
    final options = {
      'key': _razorpayKeyId,
      'amount': amountPaise,
      'currency': 'INR',
      'name': 'The Signage Surgeon',
      'description': 'Signage Cleaning Service Payment',
      'prefill': {'contact': FirebaseAuth.instance.currentUser?.phoneNumber ?? ''},
      'theme': {'color': '#FEC107'},
    };
    try {
      _razorpay.open(options);
    } catch (e) {
      _showSnack('Could not open payment screen. Please try again.');
      setState(() => _paying = false);
    }
  }

  void _onPaymentSuccess(PaymentSuccessResponse response) async {
    if (_requestId == null) return;
    try {
      String genOtp() => (1000 + Random().nextInt(9000)).toString();
      await FirebaseFirestore.instance.collection('cleaning_requests').doc(_requestId).update({
        'cleaningPhase': 'active',
        'quotationApprovedAt': FieldValue.serverTimestamp(),
        'paymentId': response.paymentId,
        'paymentStatus': 'paid',
        'equipmentTransportCharge': _equipmentTransportCharge,
        'equipmentTransportGst': _equipmentTransportGst,
        'trackingStage': 'submitted',
        'startingOtp': genOtp(),
        'completionOtp': genOtp(),
        'visitDate': null, 'visitTimeStart': null, 'visitTimeEnd': null,
        'completedAt': null,
      });
    } catch (e) {
      _showSnack('Payment succeeded but updating your request failed. Contact support with payment ID: ${response.paymentId}');
    } finally {
      if (mounted) setState(() => _paying = false);
    }
  }

  void _onPaymentError(PaymentFailureResponse response) {
    if (mounted) setState(() => _paying = false);
    _showSnack('Payment failed or was cancelled. Tap Pay Now to retry.');
  }

  void _showSnack(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(backgroundColor: AppColors.red, content: Text(message, style: const TextStyle(color: Colors.white))),
    );
  }

  @override
  Widget build(BuildContext context) {
    final requestId = ModalRoute.of(context)?.settings.arguments as String?;
    _requestId = requestId;

    if (requestId == null) {
      return Scaffold(
        backgroundColor: AppColors.offWhite,
        appBar: AppBar(backgroundColor: AppColors.serviceAccent, elevation: 0),
        body: const Center(child: Text('Request not found', style: TextStyle(color: AppColors.grey))),
      );
    }

    return Scaffold(
      backgroundColor: AppColors.offWhite,
      appBar: _buildAppBar(),
      body: StreamBuilder<DocumentSnapshot>(
        stream: FirebaseFirestore.instance.collection('cleaning_requests').doc(requestId).snapshots(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator(color: AppColors.yellow));
          }
          if (!snapshot.hasData || !snapshot.data!.exists) {
            return const Center(child: Text('This request could not be found.', style: TextStyle(color: AppColors.grey)));
          }
          final data = snapshot.data!.data() as Map<String, dynamic>;
          final phase = data['cleaningPhase'] as String? ?? 'awaiting_quotation';

          if (phase == 'active') {
            return _ActiveTrackerBody(requestId: requestId, data: data);
          }

          if (phase == 'quotation_review' || phase == 'awaiting_payment') {
            WidgetsBinding.instance.addPostFrameCallback((_) => _maybeComputeTransportCharge(requestId, data));
          }

          return _QuotationPhaseBody(
            requestId: requestId,
            data: data,
            approving: _approving,
            paying: _paying,
            rejecting: _rejecting,
            equipmentTransportCharge: _equipmentTransportCharge,
            equipmentTransportGst: _equipmentTransportGst,
            transportRate: _cachedTransportRate,
            transportDistanceKm: _cachedTransportDistanceKm,
            loadingTransportCharge: _loadingTransportCharge,
            equipmentFee: _equipmentFee,
            transportChargeError: _transportChargeError,
            onReject: _rejectQuotation,
            onPayNow: _openPayNow,
          );
        },
      ),
    );
  }

  PreferredSizeWidget _buildAppBar() {
    return AppBar(
      backgroundColor: AppColors.serviceAccent,
      elevation: 0,
      centerTitle: true,
      leading: GestureDetector(
        onTap: () => Navigator.of(context).popUntil((r) => r.isFirst),
        child: Container(
          margin: const EdgeInsets.all(10),
          decoration: BoxDecoration(color: AppColors.white, borderRadius: BorderRadius.circular(10), border: Border.all(color: AppColors.cardBorder)),
          child: const Icon(Icons.home_outlined, color: AppColors.navy, size: 18),
        ),
      ),
      title: const Text('Cleaning Request', style: TextStyle(color: AppColors.navy, fontSize: 17, fontWeight: FontWeight.w700)),
    );
  }
}

// ── Phase 1: awaiting_quotation / quotation_review / awaiting_payment / rejected ──

class _QuotationPhaseBody extends StatelessWidget {
  final String requestId;
  final Map<String, dynamic> data;
  final bool approving;
  final bool paying;
  final bool rejecting;
  final double? equipmentTransportCharge;
  final double? equipmentTransportGst;
  final double? transportRate;
  final double? transportDistanceKm;
  final bool loadingTransportCharge;
  final double? equipmentFee;
  final String? transportChargeError;
  final VoidCallback onReject;
  final void Function(Map<String, dynamic> quotation) onPayNow;

  const _QuotationPhaseBody({
    required this.requestId,
    required this.data,
    required this.approving,
    required this.paying,
    required this.rejecting,
    this.equipmentTransportCharge,
    this.equipmentTransportGst,
    this.transportRate,
    this.transportDistanceKm,
    this.loadingTransportCharge = false,
    this.equipmentFee,
    this.transportChargeError,
    required this.onReject,
    required this.onPayNow,
  });

  double get _equipmentTransportTotal => (equipmentTransportCharge ?? 0) + (equipmentTransportGst ?? 0);

  Future<Map<String, dynamic>?> _fetchCustomerProfile() => _fetchCustomerProfileShared(data['userId'] as String?);

  Future<({Uint8List? logo, Uint8List? mascot, Uint8List? qr})> _loadBrandAssets() => _loadBrandAssetsShared();

  @override
  Widget build(BuildContext context) {
    final phase = data['cleaningPhase'] as String? ?? 'awaiting_quotation';
    final quotation = data['quotation'] as Map<String, dynamic>?;
    final createdAt = data['createdAt'] as Timestamp?;

    if (phase == 'rejected') {
      return ListView(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 30),
        children: [
          _summaryCard(data, createdAt),
          const SizedBox(height: 24),
          _rejectedCard(),
        ],
      );
    }

    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 30),
      children: [
        _summaryCard(data, createdAt),
        const SizedBox(height: 24),

        _phaseStep(
          icon: Icons.check_circle_outline,
          title: 'Request Submitted',
          subtitle: 'Your cleaning request has been received.',
          done: true,
        ),
        _phaseStep(
          icon: Icons.description_outlined,
          title: 'Quotation Preparation',
          subtitle: phase == 'awaiting_quotation'
              ? 'Our team is reviewing your request and preparing a quotation.'
              : 'Quotation received — see details below.',
          done: phase != 'awaiting_quotation',
          isLast: quotation == null,
        ),

        if (quotation != null) ...[
          const SizedBox(height: 20),
          _quotationCard(context, quotation, phase),
          const SizedBox(height: 20),

          if (phase == 'quotation_review')
            Row(
              children: [
                Expanded(
                  child: SizedBox(
                    height: 50,
                    child: ElevatedButton(
                      onPressed: rejecting ? null : onReject,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.red,
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
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
                      onPressed: paying ? null : () => onPayNow(quotation),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.yellow,
                        foregroundColor: AppColors.navy,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                        elevation: 0,
                      ),
                      child: paying
                          ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.navy))
                          : const Text('ACCEPT & PAY', style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w800, letterSpacing: 0.3)),
                    ),
                  ),
                ),
              ],
            ),
        ],
      ],
    );
  }

  Widget _summaryCard(Map<String, dynamic> data, Timestamp? createdAt) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: AppColors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 10, offset: const Offset(0, 3))],
      ),
      child: Row(
        children: [
          Container(
            width: 44, height: 44,
            decoration: BoxDecoration(color: AppColors.yellow, borderRadius: BorderRadius.circular(12)),
            child: const Icon(Icons.cleaning_services_outlined, color: Colors.white, size: 22),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(data['signageType'] as String? ?? 'Signage Cleaning', style: const TextStyle(color: AppColors.navy, fontSize: 15, fontWeight: FontWeight.w700)),
                const SizedBox(height: 2),
                Text('Submitted ${_formatDate(createdAt)}', style: const TextStyle(color: AppColors.grey, fontSize: 11.5)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _phaseStep({required IconData icon, required String title, required String subtitle, required bool done, bool isLast = false}) {
    final color = done ? AppColors.yellowDark : AppColors.greyLight;
    final textColor = done ? AppColors.navy : AppColors.grey;
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Column(
            children: [
              Container(
                width: 36, height: 36,
                decoration: BoxDecoration(color: done ? AppColors.yellow : AppColors.white, shape: BoxShape.circle, border: Border.all(color: color, width: 1.5)),
                child: Icon(icon, color: done ? AppColors.navy : AppColors.greyLight, size: 18),
              ),
              if (!isLast)
                Expanded(child: Container(width: 2, margin: const EdgeInsets.symmetric(vertical: 2), color: done ? AppColors.yellowDark : AppColors.greyLight)),
            ],
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Padding(
              padding: EdgeInsets.only(bottom: isLast ? 0 : 20, top: 6),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: TextStyle(color: textColor, fontSize: 14, fontWeight: FontWeight.w700)),
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

  static const String _disclaimerText =
      'This quotation is based on the details you provided — no on-site assessment visit is conducted for this service. '
      'When our team arrives, they will verify the actual signage condition, size, and other details against what was submitted. '
      'If the details are found to be incorrect, additional charges may apply, and work will not proceed until you accept a revised '
      'quotation with the correct, verified details. If payment has already been made based on incorrect details, no refund will be '
      'issued for this reason — you may still proceed with the service by paying the revised quotation amount. '
      'We are not responsible for pre-existing damage or malfunction (e.g. faulty LED components) discovered during cleaning, unless '
      'caused by our team\'s negligence during the service.';

  Widget _quotationCard(BuildContext context, Map<String, dynamic> quotation, String phase) {
    final serviceCharges = (quotation['serviceCharges'] as num?)?.toDouble() ?? 0;
    final additionalCharges = (quotation['additionalCharges'] as num?)?.toDouble() ?? 0;
    final gstPercent = (quotation['gstPercent'] as num?)?.toDouble() ?? 18;
    final transportCharge = equipmentTransportCharge ?? 0;
    final equipmentFeeCharge = equipmentFee ?? 0;
    final accessEquipmentStr = data['accessEquipment'] as String?;
    final validity = quotation['validityDate'] as Timestamp?;
    final notes = quotation['notes']?.toString();
    final quotationNumber = quotation['quotationNumber']?.toString();
    // Single combined subtotal with GST applied once — matches the web admin
    // panel and the PDF. Admin's raw stored gstAmount/totalPayable are not
    // used directly, since they predate the auto equipment charges.
    final subtotal = serviceCharges + additionalCharges + equipmentFeeCharge + transportCharge;
    final gstAmount = subtotal * (gstPercent / 100);
    final totalPayable = subtotal + gstAmount;

    final pdfRows = <MapEntry<String, String>>[
      MapEntry('Service Charges', '₹${serviceCharges.toStringAsFixed(2)}'),
      if (additionalCharges > 0) MapEntry('Additional Charges', '₹${additionalCharges.toStringAsFixed(2)}'),
      if (equipmentFeeCharge > 0)
        MapEntry(accessEquipmentStr == 'h_frame' ? 'H-Frame Equipment Fee' : 'Ladder Equipment Fee', '₹${equipmentFeeCharge.toStringAsFixed(2)}'),
      if (transportCharge > 0) MapEntry('Equipment Transport', '₹${transportCharge.toStringAsFixed(2)}'),
      MapEntry('GST (${gstPercent.toStringAsFixed(0)}%)', '₹${gstAmount.toStringAsFixed(2)}'),
      MapEntry('Total Payable', '₹${totalPayable.toStringAsFixed(2)}'),
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
              Expanded(child: Text('Quotation${quotationNumber != null ? ' #$quotationNumber' : ''}',
                  style: const TextStyle(color: AppColors.navy, fontSize: 14, fontWeight: FontWeight.w700))),
              if (phase == 'awaiting_payment')
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(color: AppColors.green.withOpacity(0.15), borderRadius: BorderRadius.circular(6)),
                  child: const Text('Approved', style: TextStyle(color: AppColors.green, fontSize: 10, fontWeight: FontWeight.w700)),
                ),
            ],
          ),
          const SizedBox(height: 12),
          if (loadingTransportCharge) ...[
            const Text('Calculating equipment transport charge...', style: TextStyle(color: AppColors.grey, fontSize: 10.5)),
            const SizedBox(height: 6),
          ],
          if (!loadingTransportCharge && transportChargeError != null) ...[
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(10),
              margin: const EdgeInsets.only(bottom: 10),
              decoration: BoxDecoration(color: AppColors.red.withOpacity(0.08), borderRadius: BorderRadius.circular(8)),
              child: Text(transportChargeError!, style: const TextStyle(color: AppColors.red, fontSize: 10.5)),
            ),
          ],
          ...pdfRows.map((r) => _quoteRow(r.key, r.value)),
          if (validity != null) ...[
            const SizedBox(height: 10),
            Text('Valid until ${_formatDate(validity)}', style: const TextStyle(color: AppColors.grey, fontSize: 11)),
          ],
          if (notes != null && notes.trim().isNotEmpty) ...[
            const SizedBox(height: 10),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(color: AppColors.offWhite, borderRadius: BorderRadius.circular(10)),
              child: Text(notes, style: const TextStyle(color: AppColors.navy, fontSize: 12, height: 1.5)),
            ),
          ],
          const SizedBox(height: 12),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: const Color(0xFFFFA500).withOpacity(0.08),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: const Color(0xFFFFA500).withOpacity(0.3), width: 1),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Row(
                  children: [
                    Icon(Icons.info_outline, color: Color(0xFFFFA500), size: 16),
                    SizedBox(width: 8),
                    Text('Please Read Before Approving', style: TextStyle(color: AppColors.navy, fontSize: 12, fontWeight: FontWeight.w700)),
                  ],
                ),
                const SizedBox(height: 8),
                Text(_disclaimerText, style: const TextStyle(color: AppColors.navy, fontSize: 11, height: 1.6)),
              ],
            ),
          ),
          const SizedBox(height: 14),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: () async {
                try {
                final profile = await _fetchCustomerProfile();
                final assets = await _loadBrandAssets();
                final now = DateTime.now();

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

                // Reuse the same value already computed for the on-screen
                // quotation card and the actual payment — guarantees the PDF
                // always matches exactly what the customer paid.
                final transportCharge = equipmentTransportCharge ?? 0.0;
                final equipmentFeeCharge = equipmentFee ?? 0.0;
                final fullSubtotal = serviceCharges + additionalCharges + equipmentFeeCharge + transportCharge;
                final computedGstAmount = fullSubtotal * (gstPercent / 100);
                final computedGrandTotal = fullSubtotal + computedGstAmount;

                await QuotationPdf.generateAndShare(QuotationPdfData(
                  quotationNo: quotationNumber ?? requestId.substring(0, requestId.length < 8 ? requestId.length : 8),
                  requestId: requestId,
                  customerId: (data['userId'] as String?) ?? '',
                  date: now,
                  validTill: validity?.toDate() ?? now.add(const Duration(days: 7)),
                  status: phase == 'awaiting_payment' ? QuotationStatus.approved : QuotationStatus.sent,
                  customerName: (profile?['fullName'] as String?) ?? (profile?['businessName'] as String?) ?? 'Customer',
                  mobileNumber: FirebaseAuth.instance.currentUser?.phoneNumber,
                  email: profile?['email'] as String?,
                  siteAddress: (data['location'] as Map<String, dynamic>?)?['address'] as String?,
                  gstNumber: profile?['gstNumber'] as String?,
                  serviceCategory: QuotationServiceCategory.cleaning,
                  serviceType: (data['signageType'] as String?) ?? 'Signage Cleaning',
                  scopeOfWork: (notes != null && notes.trim().isNotEmpty) ? notes : 'No additional notes provided.',
                  serviceCharges: serviceCharges,
                  additionalCharges: additionalCharges,
                  subtotal: fullSubtotal,
                  discount: 0,
                  gstPercent: gstPercent,
                  grandTotal: computedGrandTotal,
                  paymentTerms: 'Advance payment is required before work begins.',
                  accessEquipment: accessEquipment,
                  ladderTentativePrice: (quotation['ladderTentativePrice'] as num?)?.toDouble(),
                  hFrameTentativePrice: (quotation['hFrameTentativePrice'] as num?)?.toDouble(),
                  equipmentFee: equipmentFeeCharge,
                  otherCharges: OtherCharges(
                    hFrameDailyRate: (quotation['hFrameDailyRate'] as num?)?.toDouble(),
                    transportPerKm: transportRate,
                    transportDistanceKm: transportDistanceKm,
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
                const Text('Quotation rejected. This request has been closed.', style: TextStyle(color: AppColors.navy, fontSize: 12.5, height: 1.4)),
                if (reason != null) ...[
                  const SizedBox(height: 6),
                  Text('Reason: $reason', style: const TextStyle(color: AppColors.grey, fontSize: 11.5, height: 1.4)),
                ],
                const SizedBox(height: 4),
                const Text('Contact us if you\'d like a revised quote.', style: TextStyle(color: AppColors.grey, fontSize: 11.5, height: 1.4)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _quoteRow(String label, String value, {bool bold = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(flex: 3, child: Text(label, style: TextStyle(color: bold ? AppColors.navy : AppColors.grey, fontSize: bold ? 14 : 12.5, fontWeight: bold ? FontWeight.w700 : FontWeight.w400))),
          const SizedBox(width: 10),
          Expanded(flex: 2, child: Text(value, textAlign: TextAlign.right, style: TextStyle(color: bold ? AppColors.yellowDark : AppColors.navy, fontSize: bold ? 16 : 12.5, fontWeight: bold ? FontWeight.w800 : FontWeight.w600))),
        ],
      ),
    );
  }
}

// ── Phase 2: active (post-payment) — Assigned / On The Way (Starting OTP) / Completed (Completion OTP) ──

class _ActiveTrackerBody extends StatelessWidget {
  final String requestId;
  final Map<String, dynamic> data;

  const _ActiveTrackerBody({required this.requestId, required this.data});

  int get _stageIndex {
    final stage = (data['trackingStage'] as String? ?? 'submitted').trim();
    switch (stage) {
      case 'tech_assigned':
        return 1;
      case 'tech_en_route':
        return 2;
      case 'work_in_progress':
        return 3;
      case 'completed':
        return 4;
      default:
        return 0;
    }
  }

  @override
  Widget build(BuildContext context) {
    final createdAt = data['createdAt'] as Timestamp?;
    final visitDate = data['visitDate'] as Timestamp?;
    final visitTimeStart = data['visitTimeStart'] as String?;
    final visitTimeEnd = data['visitTimeEnd'] as String?;
    final completedAt = data['completedAt'] as Timestamp?;
    final startingOtp = data['startingOtp'] as String?;
    final completionOtp = data['completionOtp'] as String?;

    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 30),
      children: [
        _summaryCard(createdAt),
        const SizedBox(height: 24),
        _stepTile(
          index: 0,
          icon: Icons.payments_outlined,
          title: 'Payment Confirmed',
          subtitle: 'Your payment was received. We\'ll notify you once our team is scheduled.',
          isLast: false,
        ),
        _stepTile(
          index: 1,
          icon: Icons.groups_outlined,
          title: 'Team Assigned',
          subtitle: _stageIndex >= 1
              ? 'Our team will visit on ${_formatDate(visitDate)}${visitTimeStart != null ? ', $visitTimeStart - ${visitTimeEnd ?? ''}' : ''}'
              : 'Pending assignment — we\'ll notify you once scheduled.',
          isLast: false,
        ),
        _stepTile(
          index: 2,
          icon: Icons.directions_car_filled_outlined,
          title: 'Team On The Way',
          subtitle: _stageIndex >= 2 ? 'Our cleaning team is heading to your location.' : 'Not started yet.',
          isLast: false,
        ),
        if (_stageIndex == 2 && startingOtp != null) ...[
          const SizedBox(height: 8),
          _otpCard(startingOtp, 'Starting OTP', 'Share this with the team member when they arrive to begin the service.'),
        ],
        _stepTile(
          index: 3,
          icon: Icons.cleaning_services_outlined,
          title: 'Cleaning In Progress',
          subtitle: _stageIndex >= 3 ? 'Our team is currently cleaning your signage.' : 'Not started yet.',
          isLast: false,
        ),
        if (_stageIndex == 3 && completionOtp != null) ...[
          const SizedBox(height: 8),
          _otpCard(completionOtp, 'Completion OTP', 'Share this with the team once the cleaning work is finished.'),
        ],
        _stepTile(
          index: 4,
          icon: Icons.task_alt_outlined,
          title: 'Cleaning Completed',
          subtitle: _stageIndex >= 4 ? 'Completed on ${_formatDate(completedAt)}. Thank you for choosing us!' : 'Not completed yet.',
          isLast: true,
        ),
        if (_stageIndex == 4) ...[
          const SizedBox(height: 16),
          _receiptCard(context),
          const SizedBox(height: 12),
          _requestRefundButton(context),
          const SizedBox(height: 12),
          RatingCard(collection: 'cleaning_requests', requestId: requestId, serviceLabel: 'Signage Cleaning'),
          const SizedBox(height: 12),
          _reportProblemButton(context),
        ],
      ],
    );
  }

  Widget _receiptCard(BuildContext context) {
    final quotation = data['quotation'] as Map<String, dynamic>?;
    final serviceCharges = quotation != null ? ((quotation['serviceCharges'] as num?)?.toDouble() ?? 0) : 0.0;
    final additionalCharges = quotation != null ? ((quotation['additionalCharges'] as num?)?.toDouble() ?? 0) : 0.0;
    final gstPercent = quotation != null ? ((quotation['gstPercent'] as num?)?.toDouble() ?? 18) : 18.0;
    // These were already persisted to Firestore when the quotation card
    // computed them, before payment — reading them here (rather than
    // needing live State) guarantees the receipt matches what was paid.
    final equipmentFeeVal = (data['equipmentFee'] as num?)?.toDouble() ?? 0;
    final transportChargeVal = (data['equipmentTransportCharge'] as num?)?.toDouble() ?? 0;
    final subtotal = serviceCharges + additionalCharges + equipmentFeeVal + transportChargeVal;
    final totalPayable = subtotal + (subtotal * gstPercent / 100);
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
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: () async {
                try {
                  final profile = await _fetchCustomerProfileShared(data['userId'] as String?);
                  final assets = await _loadBrandAssetsShared();
                  await PaymentReceiptPdf.generateAndShare(PaymentReceiptData(
                    receiptNo: requestId.substring(0, requestId.length < 8 ? requestId.length : 8),
                    paymentId: data['paymentId'] as String?,
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
                    serviceCategory: ServiceCategory.cleaning,
                    serviceType: (data['signageType'] as String?) ?? 'Signage Cleaning',
                    paymentAgainst: PaymentAgainst.finalPayment,
                    amountBeforeGst: subtotal,
                    serviceChargesItem: serviceCharges,
                    additionalChargesItem: additionalCharges,
                    equipmentFeeItem: equipmentFeeVal,
                    transportChargeItem: transportChargeVal,
                    accessEquipmentLabel: (data['accessEquipment'] as String?) == 'h_frame' ? 'H-Frame' : 'Ladder',
                    gstPercent: gstPercent,
                    totalAmount: totalPayable,
                    amountPaid: totalPayable,
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

  Widget _reportProblemButton(BuildContext context) {
    final signageType = data['signageType'] as String? ?? '';
    return SizedBox(
      width: double.infinity,
      child: OutlinedButton.icon(
        onPressed: () => Navigator.pushNamed(
          context,
          AppRoutes.reportProblem,
          arguments: {
            'collection': 'cleaning_requests',
            'requestId': requestId,
            'serviceLabel': 'Signage Cleaning${signageType.isNotEmpty ? ' — $signageType' : ''}',
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

  Widget _requestRefundButton(BuildContext context) {
    final paymentId = data['paymentId'] as String?;
    if (paymentId == null || paymentId.trim().isEmpty) return const SizedBox.shrink();

    final quotation = data['quotation'] as Map<String, dynamic>?;
    final serviceCharges = quotation != null ? ((quotation['serviceCharges'] as num?)?.toDouble() ?? 0) : 0.0;
    final additionalCharges = quotation != null ? ((quotation['additionalCharges'] as num?)?.toDouble() ?? 0) : 0.0;
    final gstPercent = quotation != null ? ((quotation['gstPercent'] as num?)?.toDouble() ?? 18) : 18.0;
    final equipmentFeeVal = (data['equipmentFee'] as num?)?.toDouble() ?? 0;
    final transportChargeVal = (data['equipmentTransportCharge'] as num?)?.toDouble() ?? 0;
    final subtotal = serviceCharges + additionalCharges + equipmentFeeVal + transportChargeVal;
    final totalPayable = subtotal + (subtotal * gstPercent / 100);

    final signageType = data['signageType'] as String? ?? '';

    return SizedBox(
      width: double.infinity,
      child: OutlinedButton.icon(
        onPressed: () => Navigator.pushNamed(
          context,
          AppRoutes.requestRefund,
          arguments: {
            'collection': 'cleaning_requests',
            'requestId': requestId,
            'serviceLabel': 'Signage Cleaning${signageType.isNotEmpty ? ' — $signageType' : ''}',
            'paymentOptions': [
              RefundablePayment(
                label: 'Cleaning Payment',
                paymentAgainst: 'quotation',
                razorpayPaymentId: paymentId,
                amount: totalPayable,
              ),
            ],
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

  Widget _summaryCard(Timestamp? createdAt) {
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
                child: const Icon(Icons.cleaning_services_outlined, color: Colors.white, size: 22),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(data['signageType'] as String? ?? 'Signage Cleaning', style: const TextStyle(color: AppColors.navy, fontSize: 15, fontWeight: FontWeight.w700)),
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
              Expanded(child: Text('Request ID: $requestId', style: const TextStyle(color: AppColors.grey, fontSize: 11), overflow: TextOverflow.ellipsis)),
            ],
          ),
        ],
      ),
    );
  }

  Widget _stepTile({required int index, required IconData icon, required String title, required String subtitle, required bool isLast}) {
    final reached = _stageIndex >= index;
    final isCurrent = _stageIndex == index;
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
                decoration: BoxDecoration(color: reached ? AppColors.yellow : AppColors.white, shape: BoxShape.circle, border: Border.all(color: color, width: isCurrent ? 2.5 : 1.5)),
                child: Icon(icon, color: reached ? AppColors.navy : AppColors.greyLight, size: 18),
              ),
              if (!isLast)
                Expanded(child: Container(width: 2, margin: const EdgeInsets.symmetric(vertical: 2), color: reached ? AppColors.yellowDark : AppColors.greyLight)),
            ],
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Padding(
              padding: EdgeInsets.only(bottom: isLast ? 0 : 26, top: 6),
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

  Widget _otpCard(String otp, String label, String helperText) {
    return Container(
      margin: const EdgeInsets.only(left: 50),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(color: AppColors.yellow.withOpacity(0.15), borderRadius: BorderRadius.circular(14), border: Border.all(color: AppColors.yellowDark, width: 1)),
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
}

Future<Map<String, dynamic>?> _fetchCustomerProfileShared(String? userId) async {
  if (userId == null) return null;
  try {
    final doc = await FirebaseFirestore.instance.collection('users').doc(userId).get();
    return doc.data();
  } catch (_) {
    return null;
  }
}

Future<({Uint8List? logo, Uint8List? mascot, Uint8List? qr})> _loadBrandAssetsShared() async {
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

String _formatDate(Timestamp? ts) {
  if (ts == null) return 'TBD';
  final dt = ts.toDate();
  const months = ['Jan','Feb','Mar','Apr','May','Jun','Jul','Aug','Sep','Oct','Nov','Dec'];
  return '${dt.day} ${months[dt.month - 1]} ${dt.year}';
}