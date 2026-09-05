import 'package:flutter/material.dart';
import 'dart:typed_data';
import 'package:flutter/services.dart' show rootBundle;
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:razorpay_flutter/razorpay_flutter.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/services/quotation_pdf.dart';
import '../../../core/services/payment_receipt_pdf.dart';
import '../../../core/services/distance_fee_service.dart';
import '../../../core/constants/app_routes.dart';
import '../../refund/screens/request_refund_screen.dart';
import '../../rating/screens/rating_card.dart';
import '../../support/screens/report_problem_screen.dart';

class AmcTrackingScreen extends StatefulWidget {
  const AmcTrackingScreen({super.key});

  @override
  State<AmcTrackingScreen> createState() => _AmcTrackingScreenState();
}

class _AmcTrackingScreenState extends State<AmcTrackingScreen> {
  final _razorpay = Razorpay();
  static const String _razorpayKeyId = 'rzp_test_TDKf4pilC4l0id';
  bool _busy = false;
  String? _requestId;
  String? _pendingPaymentType; // 'audit_proposal' | 'final'

  // Equipment fee (flat) + transport charge (distance-based) for the audit
  // visit — only relevant at the audit proposal stage, since the final AMC
  // quotation is an ongoing contract, not a specific site visit.
  double? _equipmentFee;
  double? _equipmentTransportCharge;
  double? _cachedTransportRate;
  double? _cachedDistanceKm;
  bool _loadingEquipmentCharges = false;
  String? _equipmentChargeError;
  String? _equipmentChargeComputedFor;

  Future<void> _maybeComputeEquipmentCharges(String requestId, Map<String, dynamic> data) async {
    if (_equipmentChargeComputedFor == requestId) return;
    final accessEquipment = data['accessEquipment'] as String?;
    if (accessEquipment != 'ladder' && accessEquipment != 'h_frame') {
      _equipmentChargeComputedFor = requestId;
      return;
    }
    _equipmentChargeComputedFor = requestId;
    if (mounted) setState(() => _loadingEquipmentCharges = true);
    try {
      final configDoc = await FirebaseFirestore.instance
          .collection('app_settings')
          .doc('pricing_config')
          .get()
          .timeout(const Duration(seconds: 12));
      final config = configDoc.data();

      final equipmentFee = accessEquipment == 'h_frame'
          ? (config?['hFrameEquipmentFee'] as num?)?.toDouble()
          : (config?['ladderEquipmentFee'] as num?)?.toDouble();

      final rate = (config?['transportPerKmRate'] as num?)?.toDouble();
      double? distanceKm;
      double? transportCharge;
      final locations = (data['locations'] as List?) ?? [];
      if (rate != null && rate > 0 && locations.isNotEmpty) {
        final firstLoc = locations.first as Map<String, dynamic>?;
        final lat = (firstLoc?['lat'] as num?)?.toDouble();
        final lng = (firstLoc?['lng'] as num?)?.toDouble();
        if (lat != null && lng != null) {
          distanceKm = await DistanceFeeService.getRoadDistanceKm(destLat: lat, destLng: lng)
              .timeout(const Duration(seconds: 15));
          transportCharge = rate * distanceKm;
        }
      }

      if (equipmentFee == null && transportCharge == null) {
        if (mounted) setState(() => _equipmentChargeError = 'No equipment pricing configured (app_settings/pricing_config missing ladderEquipmentFee/hFrameEquipmentFee/transportPerKmRate)');
        return;
      }

      if (mounted) {
        setState(() {
          _equipmentFee = equipmentFee;
          if (transportCharge != null) {
            _equipmentTransportCharge = transportCharge;
            _cachedTransportRate = rate;
            _cachedDistanceKm = distanceKm;
          }
          _equipmentChargeError = null;
        });
      }
      try {
        await FirebaseFirestore.instance.collection('amc_requests').doc(requestId).update({
          if (equipmentFee != null) 'equipmentFee': equipmentFee,
          if (transportCharge != null) ...{
            'distanceKm': distanceKm,
            'transportPerKmRateUsed': rate,
            'equipmentTransportCharge': transportCharge,
          },
        });
      } catch (_) {}
    } catch (e) {
      if (mounted) setState(() => _equipmentChargeError = 'Equipment charge calculation failed: $e');
    } finally {
      if (mounted) setState(() => _loadingEquipmentCharges = false);
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

  void _payAuditProposal(Map<String, dynamic> proposal) {
    _pendingPaymentType = 'audit_proposal';
    final auditFee = (proposal['auditFee'] as num?)?.toDouble() ?? 0;
    final gstPercent = (proposal['gstPercent'] as num?)?.toDouble() ?? 18;
    // Single combined subtotal — Audit Fee + Equipment Fee + Transport —
    // with GST applied once, matching the quotation card display.
    final subtotal = auditFee + (_equipmentFee ?? 0) + (_equipmentTransportCharge ?? 0);
    final total = subtotal + subtotal * (gstPercent / 100);
    _openRazorpay(total, 'AMC Initial Signage Audit Fee (Custom Proposal)');
  }

  void _payFinalQuotation(Map<String, dynamic> quotation) {
    _pendingPaymentType = 'final';
    final commercial = (quotation['commercialValue'] as num?)?.toDouble() ?? 0;
    final gstPercent = (quotation['gstPercent'] as num?)?.toDouble() ?? 18;
    _openRazorpay(commercial + commercial * (gstPercent / 100), 'Signage AMC — Final Payment');
  }

  void _openRazorpay(double amount, String description) {
    setState(() => _busy = true);
    final amountPaise = (amount * 100).round();
    final options = {
      'key': _razorpayKeyId,
      'amount': amountPaise,
      'currency': 'INR',
      'name': 'The Signage Surgeon',
      'description': description,
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
      if (_pendingPaymentType == 'audit_proposal') {
        await FirebaseFirestore.instance.collection('amc_requests').doc(_requestId).update({
          'amcPhase': 'audit_paid',
          'auditProposalApprovedAt': FieldValue.serverTimestamp(),
          'auditPaymentId': response.paymentId,
          'auditPaymentStatus': 'paid',
        });
      } else if (_pendingPaymentType == 'final') {
        await FirebaseFirestore.instance.collection('amc_requests').doc(_requestId).update({
          'amcPhase': 'amc_confirmed',
          'finalPaymentId': response.paymentId,
          'finalPaymentStatus': 'paid',
          'amcConfirmedAt': FieldValue.serverTimestamp(),
        });
      }
    } catch (e) {
      _showSnack('Payment succeeded but updating your request failed. Contact support with payment ID: ${response.paymentId}');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _onPaymentError(PaymentFailureResponse response) {
    if (mounted) setState(() => _busy = false);
    _showSnack('Payment failed or was cancelled. Please try again.');
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
        stream: FirebaseFirestore.instance.collection('amc_requests').doc(requestId).snapshots(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator(color: AppColors.yellow));
          }
          if (!snapshot.hasData || !snapshot.data!.exists) {
            return const Center(child: Text('This request could not be found.', style: TextStyle(color: AppColors.grey)));
          }
          final data = snapshot.data!.data() as Map<String, dynamic>;
          if (data['amcPhase'] == 'audit_proposal_sent') {
            WidgetsBinding.instance.addPostFrameCallback((_) => _maybeComputeEquipmentCharges(requestId, data));
          }
          return _AmcBody(
            requestId: requestId,
            data: data,
            busy: _busy,
            equipmentFee: _equipmentFee,
            equipmentTransportCharge: _equipmentTransportCharge,
            transportRate: _cachedTransportRate,
            distanceKm: _cachedDistanceKm,
            loadingEquipmentCharges: _loadingEquipmentCharges,
            equipmentChargeError: _equipmentChargeError,
            onPayAuditProposal: _payAuditProposal,
            onPayFinalQuotation: _payFinalQuotation,
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
      title: const Text('AMC Status', style: TextStyle(color: AppColors.navy, fontSize: 17, fontWeight: FontWeight.w700)),
    );
  }
}

class _AmcBody extends StatelessWidget {
  final String requestId;
  final Map<String, dynamic> data;
  final bool busy;
  final double? equipmentFee;
  final double? equipmentTransportCharge;
  final double? transportRate;
  final double? distanceKm;
  final bool loadingEquipmentCharges;
  final String? equipmentChargeError;
  final void Function(Map<String, dynamic> proposal) onPayAuditProposal;
  final void Function(Map<String, dynamic> quotation) onPayFinalQuotation;

  const _AmcBody({
    required this.requestId,
    required this.data,
    required this.busy,
    this.equipmentFee,
    this.equipmentTransportCharge,
    this.transportRate,
    this.distanceKm,
    this.loadingEquipmentCharges = false,
    this.equipmentChargeError,
    required this.onPayAuditProposal,
    required this.onPayFinalQuotation,
  });

  String get _phase => data['amcPhase'] as String? ?? 'inquiry_submitted';

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 30),
      children: [
        _summaryCard(),
        const SizedBox(height: 16),
        _auditFeeReceiptCard(),
        if (data['amcPhase'] == 'audit_paid') ...[
          const SizedBox(height: 12),
          _cancelRequestButton(context),
        ],
        const SizedBox(height: 24),
        ..._buildPhaseContent(context),
      ],
    );
  }

  Widget _reportProblemButton(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      child: OutlinedButton.icon(
        onPressed: () => Navigator.pushNamed(
          context,
          AppRoutes.reportProblem,
          arguments: {
            'collection': 'amc_requests',
            'requestId': requestId,
            'serviceLabel': 'AMC',
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
    double cancellationChargePercent = 20;
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
              'A cancellation charge of ${cancellationChargePercent.toStringAsFixed(0)}% of the audit fee will apply, '
              'since your audit visit has not yet been scheduled. The remaining amount will be refunded after review.',
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
      await FirebaseFirestore.instance.collection('amc_requests').doc(requestId).update({
        'amcPhase': 'cancelled_by_customer',
        'cancelledAt': FieldValue.serverTimestamp(),
        'cancellationChargePercent': cancellationChargePercent,
      });

      final user = FirebaseAuth.instance.currentUser;
      final auditPaymentId = data['auditPaymentId'] as String?;
      if (user != null && auditPaymentId != null && auditPaymentId.trim().isNotEmpty) {
        await FirebaseFirestore.instance.collection('refund_requests').add({
          'requestId': requestId,
          'serviceCollection': 'amc_requests',
          'userId': user.uid,
          'paymentAgainst': 'audit',
          'razorpayPaymentId': auditPaymentId,
          'reason': reason.isNotEmpty
              ? 'Customer cancelled before audit visit was scheduled. Reason given: $reason'
              : 'Customer cancelled before audit visit was scheduled.',
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

  Widget _auditFeeReceiptCard() {
    final paymentId = data['auditPaymentId'] as String?;
    if (paymentId == null || paymentId.trim().isEmpty) return const SizedBox.shrink();

    final proposal = data['auditFeeProposal'] as Map<String, dynamic>?;
    final auditFeeNum = (proposal?['auditFee'] as num?)?.toDouble() ?? (data['totalAuditFee'] as num?)?.toDouble() ?? 0;
    final gstPercentNum = (proposal?['gstPercent'] as num?)?.toDouble() ?? 18;
    final equipmentFeeVal = (data['equipmentFee'] as num?)?.toDouble() ?? 0;
    final transportVal = (data['equipmentTransportCharge'] as num?)?.toDouble() ?? 0;
    final accessEquipment = data['accessEquipment'] as String?;
    final subtotal = auditFeeNum + equipmentFeeVal + transportVal;
    final gstAmount = subtotal * (gstPercentNum / 100);
    final total = subtotal > 0 ? subtotal + gstAmount : ((data['totalPayable'] as num?)?.toDouble() ?? 0);

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
              const Expanded(child: Text('AMC Audit Fee — Paid', style: TextStyle(color: AppColors.navy, fontSize: 14, fontWeight: FontWeight.w700))),
            ],
          ),
          const SizedBox(height: 10),
          _feeRow('Audit Fee', '₹${auditFeeNum.toStringAsFixed(2)}'),
          if (equipmentFeeVal > 0) _feeRow(accessEquipment == 'h_frame' ? 'H-Frame Equipment Fee' : 'Ladder Equipment Fee', '₹${equipmentFeeVal.toStringAsFixed(2)}'),
          if (transportVal > 0) _feeRow('Equipment Transport', '₹${transportVal.toStringAsFixed(2)}'),
          _feeRow('GST (${gstPercentNum.toStringAsFixed(0)}%)', '₹${gstAmount.toStringAsFixed(2)}'),
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

  Widget _summaryCard() {
    final createdAt = data['createdAt'] as Timestamp?;
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
            child: const Icon(Icons.shield_outlined, color: Colors.white, size: 22),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(data['requirementType'] as String? ?? 'Signage AMC', style: const TextStyle(color: AppColors.navy, fontSize: 15, fontWeight: FontWeight.w700)),
                const SizedBox(height: 2),
                Text('Submitted ${_formatDate(createdAt)} · ${data['locationCountRange'] ?? ''}', style: const TextStyle(color: AppColors.grey, fontSize: 11.5)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  List<Widget> _buildPhaseContent(BuildContext context) {
    switch (_phase) {
      case 'inquiry_submitted':
        return [
          _phaseCard(
            icon: Icons.hourglass_top_outlined,
            title: 'Inquiry Submitted',
            body: 'Your AMC inquiry has been received. Our team is reviewing your requirement and will prepare a custom AMC Initial Signage Audit Fee proposal.',
          ),
        ];

      case 'audit_proposal_sent':
        final proposal = data['auditFeeProposal'] as Map<String, dynamic>? ?? {};
        final auditFeeNum = (proposal['auditFee'] as num?)?.toDouble() ?? 0;
        final gstPercentNum = (proposal['gstPercent'] as num?)?.toDouble() ?? 18;
        final accessEquipmentStr = data['accessEquipment'] as String?;
        // Single combined subtotal — Audit Fee + Equipment Fee + Transport —
        // with GST applied once, matching every other service.
        final auditSubtotal = auditFeeNum + (equipmentFee ?? 0) + (equipmentTransportCharge ?? 0);
        final auditGst = auditSubtotal * (gstPercentNum / 100);
        final auditTotal = auditSubtotal + auditGst;
        return [
          if (loadingEquipmentCharges)
            const Padding(
              padding: EdgeInsets.only(bottom: 10),
              child: Text('Calculating equipment charges...', style: TextStyle(color: AppColors.grey, fontSize: 11)),
            ),
          if (!loadingEquipmentCharges && equipmentChargeError != null)
            Container(
              width: double.infinity,
              margin: const EdgeInsets.only(bottom: 10),
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(color: AppColors.red.withOpacity(0.08), borderRadius: BorderRadius.circular(8)),
              child: Text(equipmentChargeError!, style: const TextStyle(color: AppColors.red, fontSize: 10.5)),
            ),
          _quotationCard(
            context: context,
            title: 'AMC Initial Signage Audit Fee Proposal',
            rows: [
              MapEntry('Locations Covered', '${proposal['locationsCovered'] ?? '-'}'),
              MapEntry('Audit Fee', '₹${auditFeeNum.toStringAsFixed(2)}'),
              if (equipmentFee != null)
                MapEntry(accessEquipmentStr == 'h_frame' ? 'H-Frame Equipment Fee' : 'Ladder Equipment Fee', '₹${equipmentFee!.toStringAsFixed(2)}'),
              if (equipmentTransportCharge != null)
                MapEntry('Equipment Transport', '₹${equipmentTransportCharge!.toStringAsFixed(2)}'),
              MapEntry('GST (${gstPercentNum.toStringAsFixed(0)}%)', '₹${auditGst.toStringAsFixed(2)}'),
              MapEntry('Total Payable', '₹${auditTotal.toStringAsFixed(2)}'),
            ],
            notes: proposal['notes'] as String?,
            pdfTitle: 'AMC Audit Fee Proposal',
            pdfFilename: 'AMC_Audit_Proposal_$requestId.pdf',
            onGeneratePdf: () async {
              final profile = await _fetchCustomerProfileShared(data['userId'] as String?);
              final assets = await _loadBrandAssetsShared();
              AccessEquipment? accessEquipmentEnum;
              switch (accessEquipmentStr) {
                case 'ladder':
                  accessEquipmentEnum = AccessEquipment.ladder;
                  break;
                case 'h_frame':
                  accessEquipmentEnum = AccessEquipment.hFrame;
                  break;
                case 'not_needed':
                  accessEquipmentEnum = AccessEquipment.notNeeded;
                  break;
              }
              await QuotationPdf.generateAndShare(QuotationPdfData(
                quotationNo: 'AUDIT-${requestId.substring(0, requestId.length < 8 ? requestId.length : 8)}',
                requestId: requestId,
                customerId: (data['userId'] as String?) ?? '',
                date: DateTime.now(),
                validTill: DateTime.now().add(const Duration(days: 7)),
                status: QuotationStatus.sent,
                customerName: (profile?['fullName'] as String?) ?? (profile?['businessName'] as String?) ?? 'Customer',
                mobileNumber: FirebaseAuth.instance.currentUser?.phoneNumber,
                email: profile?['email'] as String?,
                siteAddress: _firstLocationAddress(data),
                gstNumber: profile?['gstNumber'] as String?,
                serviceCategory: QuotationServiceCategory.amc,
                serviceType: 'AMC Initial Signage Audit',
                scopeOfWork: (proposal['notes'] as String?)?.trim().isNotEmpty == true ? proposal['notes'] as String : 'Initial signage audit visit to assess AMC coverage requirements.',
                serviceCharges: auditFeeNum,
                additionalCharges: 0,
                subtotal: auditSubtotal,
                discount: 0,
                gstPercent: gstPercentNum,
                grandTotal: auditTotal,
                paymentTerms: 'Advance payment is required before the audit visit.',
                accessEquipment: accessEquipmentEnum,
                equipmentFee: equipmentFee ?? 0,
                otherCharges: OtherCharges(
                  transportPerKm: transportRate,
                  transportDistanceKm: distanceKm,
                ),
                logoBytes: assets.logo,
                mascotBytes: assets.mascot,
                qrCodeBytes: assets.qr,
              ));
            },
          ),
          const SizedBox(height: 18),
          _actionButton(
            label: 'ACCEPT & PAY',
            onPressed: busy ? null : () => onPayAuditProposal(proposal),
            busy: busy,
          ),
        ];

      case 'audit_paid':
      case 'audit_scheduled':
      case 'audit_in_progress':
      case 'audit_completed':
        return [
          _receiptCard(
            context: context,
            title: 'Audit Fee Payment Confirmed',
            rows: _auditReceiptRows(),
            pdfFilename: 'AMC_Audit_Receipt_$requestId.pdf',
            onGeneratePdf: () async {
              final profile = await _fetchCustomerProfileShared(data['userId'] as String?);
              final assets = await _loadBrandAssetsShared();
              final proposal = data['auditFeeProposal'] as Map<String, dynamic>?;
              // Two possible data shapes depending on the audit path taken —
              // fall back to the top-level totals if the proposal map is
              // missing or empty, so the receipt never shows Rs. 0.00 just
              // because one path wasn't checked.
              final auditFeeNum = (proposal?['auditFee'] as num?)?.toDouble() ?? (data['totalAuditFee'] as num?)?.toDouble() ?? 0;
              final gstPercentNum = (proposal?['gstPercent'] as num?)?.toDouble() ?? 18;
              final equipmentFeeVal = (data['equipmentFee'] as num?)?.toDouble() ?? 0;
              final transportVal = (data['equipmentTransportCharge'] as num?)?.toDouble() ?? 0;
              final subtotal = auditFeeNum + equipmentFeeVal + transportVal;
              final totalPaid = subtotal > 0 ? subtotal + subtotal * (gstPercentNum / 100) : ((data['totalPayable'] as num?)?.toDouble() ?? 0);
              await PaymentReceiptPdf.generateAndShare(PaymentReceiptData(
                receiptNo: 'AUDIT-${requestId.substring(0, requestId.length < 8 ? requestId.length : 8)}',
                paymentId: data['auditPaymentId'] as String?,
                requestId: requestId,
                receiptDate: DateTime.now(),
                paymentDate: DateTime.now(),
                status: PaymentStatus.paid,
                customerName: (profile?['fullName'] as String?) ?? (profile?['businessName'] as String?) ?? 'Customer',
                mobileNumber: FirebaseAuth.instance.currentUser?.phoneNumber,
                emailAddress: profile?['email'] as String?,
                gstNumber: profile?['gstNumber'] as String?,
                serviceCategory: ServiceCategory.amc,
                serviceType: 'AMC Initial Signage Audit',
                paymentAgainst: PaymentAgainst.siteVisit,
                amountBeforeGst: subtotal,
                serviceChargesItem: auditFeeNum,
                equipmentFeeItem: equipmentFeeVal,
                transportChargeItem: transportVal,
                accessEquipmentLabel: (data['accessEquipment'] as String?) == 'h_frame' ? 'H-Frame' : 'Ladder',
                gstPercent: gstPercentNum,
                totalAmount: totalPaid,
                amountPaid: totalPaid,
                balanceAmount: 0,
                paymentMethod: PaymentMethod.upi,
                logoBytes: assets.logo,
                mascotBytes: assets.mascot,
                qrCodeBytes: assets.qr,
              ));
            },
          ),
          const SizedBox(height: 12),
          _requestRefundButton(context, paymentAgainst: 'audit'),
          const SizedBox(height: 24),
          ..._auditTracker(),
          if (_phase == 'audit_completed') ...[
            const SizedBox(height: 20),
            _phaseCard(
              icon: Icons.description_outlined,
              title: 'Preparing Your AMC Quotation',
              body: 'Our team is preparing your final Signage Asset / Audit Sheet and AMC quotation. We\'ll notify you once it\'s ready.',
            ),
          ],
        ];

      case 'final_quotation_sent':
        final quotation = data['finalQuotation'] as Map<String, dynamic>? ?? {};
        final commercialNum = (quotation['commercialValue'] as num?)?.toDouble() ?? 0;
        final gstPercentNum = (quotation['gstPercent'] as num?)?.toDouble() ?? 18;
        final gstNum = commercialNum * (gstPercentNum / 100);
        final totalNum = commercialNum + gstNum;
        return [
          ..._auditTracker(collapsed: true),
          const SizedBox(height: 20),
          _quotationCard(
            context: context,
            title: 'AMC Quotation',
            rows: [
              MapEntry('AMC Scope', '${quotation['scope'] ?? '-'}'),
              MapEntry('Covered Locations', '${quotation['coveredLocations'] ?? '-'}'),
              MapEntry('Covered Signage Assets', '${quotation['coveredAssets'] ?? '-'}'),
              MapEntry('Maintenance Coverage', '${quotation['maintenanceCoverage'] ?? '-'}'),
              MapEntry('Service / Visit Frequency', '${quotation['visitFrequency'] ?? '-'}'),
              MapEntry('AMC Period', '${quotation['amcPeriod'] ?? '-'}'),
              MapEntry('Commercial Value', '₹${commercialNum.toStringAsFixed(2)}'),
              MapEntry('GST (${gstPercentNum.toStringAsFixed(0)}%)', '₹${gstNum.toStringAsFixed(2)}'),
              MapEntry('Total Payable', '₹${totalNum.toStringAsFixed(2)}'),
            ],
            notes: quotation['termsNotes'] as String?,
            pdfTitle: 'AMC Quotation',
            pdfFilename: 'AMC_Quotation_$requestId.pdf',
            onGeneratePdf: () async {
              final profile = await _fetchCustomerProfileShared(data['userId'] as String?);
              final assets = await _loadBrandAssetsShared();
              final scopeText = [
                if (quotation['scope'] != null) 'Scope: ${quotation['scope']}',
                if (quotation['coveredLocations'] != null) 'Covered Locations: ${quotation['coveredLocations']}',
                if (quotation['coveredAssets'] != null) 'Covered Signage Assets: ${quotation['coveredAssets']}',
                if (quotation['maintenanceCoverage'] != null) 'Maintenance Coverage: ${quotation['maintenanceCoverage']}',
                if (quotation['visitFrequency'] != null) 'Service / Visit Frequency: ${quotation['visitFrequency']}',
                if (quotation['amcPeriod'] != null) 'AMC Period: ${quotation['amcPeriod']}',
              ].join('\n');
              await QuotationPdf.generateAndShare(QuotationPdfData(
                quotationNo: 'AMC-${requestId.substring(0, requestId.length < 8 ? requestId.length : 8)}',
                requestId: requestId,
                customerId: (data['userId'] as String?) ?? '',
                date: DateTime.now(),
                validTill: DateTime.now().add(const Duration(days: 7)),
                status: QuotationStatus.sent,
                customerName: (profile?['fullName'] as String?) ?? (profile?['businessName'] as String?) ?? 'Customer',
                mobileNumber: FirebaseAuth.instance.currentUser?.phoneNumber,
                email: profile?['email'] as String?,
                siteAddress: _firstLocationAddress(data),
                gstNumber: profile?['gstNumber'] as String?,
                serviceCategory: QuotationServiceCategory.amc,
                serviceType: 'AMC - ${quotation['amcPeriod'] ?? 'Annual Maintenance Contract'}',
                scopeOfWork: scopeText.isNotEmpty ? scopeText : 'AMC coverage as agreed.',
                serviceCharges: commercialNum,
                additionalCharges: 0,
                subtotal: commercialNum,
                discount: 0,
                gstPercent: gstPercentNum,
                grandTotal: totalNum,
                paymentTerms: 'Advance payment is required to confirm AMC coverage.',
                warranty: quotation['termsNotes'] as String?,
                logoBytes: assets.logo,
                mascotBytes: assets.mascot,
                qrCodeBytes: assets.qr,
              ));
            },
          ),
          const SizedBox(height: 18),
          _actionButton(
            label: 'ACCEPT & PAY',
            onPressed: busy ? null : () => onPayFinalQuotation(quotation),
            busy: busy,
          ),
        ];

      case 'amc_confirmed':
        final quotation = data['finalQuotation'] as Map<String, dynamic>? ?? {};
        final commercialNum = (quotation['commercialValue'] as num?)?.toDouble() ?? 0;
        final gstPercentNum = (quotation['gstPercent'] as num?)?.toDouble() ?? 18;
        final totalNum = commercialNum + commercialNum * (gstPercentNum / 100);
        return [
          _phaseCard(
            icon: Icons.verified_outlined,
            title: 'AMC Confirmed',
            body: 'Your Signage AMC has been confirmed successfully. Our team will proceed according to the mutually agreed AMC scope and service terms.',
            highlight: true,
          ),
          const SizedBox(height: 18),
          _receiptCard(
            context: context,
            title: 'Final Payment Receipt',
            rows: [
              MapEntry('AMC Period', '${quotation['amcPeriod'] ?? '-'}'),
              MapEntry('Amount Paid', '₹${totalNum.toStringAsFixed(2)}'),
              MapEntry('Payment ID', '${data['finalPaymentId'] ?? '-'}'),
            ],
            pdfFilename: 'AMC_Final_Receipt_$requestId.pdf',
            onGeneratePdf: () async {
              final profile = await _fetchCustomerProfileShared(data['userId'] as String?);
              final assets = await _loadBrandAssetsShared();
              await PaymentReceiptPdf.generateAndShare(PaymentReceiptData(
                receiptNo: 'AMC-${requestId.substring(0, requestId.length < 8 ? requestId.length : 8)}',
                paymentId: data['finalPaymentId'] as String?,
                requestId: requestId,
                receiptDate: DateTime.now(),
                paymentDate: DateTime.now(),
                status: PaymentStatus.paid,
                customerName: (profile?['fullName'] as String?) ?? (profile?['businessName'] as String?) ?? 'Customer',
                mobileNumber: FirebaseAuth.instance.currentUser?.phoneNumber,
                emailAddress: profile?['email'] as String?,
                gstNumber: profile?['gstNumber'] as String?,
                serviceCategory: ServiceCategory.amc,
                serviceType: 'AMC - ${quotation['amcPeriod'] ?? 'Annual Maintenance Contract'}',
                paymentAgainst: PaymentAgainst.amc,
                amountBeforeGst: commercialNum,
                serviceChargesItem: commercialNum,
                gstPercent: gstPercentNum,
                totalAmount: totalNum,
                amountPaid: totalNum,
                balanceAmount: 0,
                paymentMethod: PaymentMethod.upi,
                logoBytes: assets.logo,
                mascotBytes: assets.mascot,
                qrCodeBytes: assets.qr,
              ));
            },
          ),
          const SizedBox(height: 12),
          _requestRefundButton(context, paymentAgainst: 'final'),
          const SizedBox(height: 12),
          RatingCard(collection: 'amc_requests', requestId: requestId, serviceLabel: 'AMC'),
          const SizedBox(height: 12),
          _reportProblemButton(context),
        ];

      default:
        return [
          _phaseCard(icon: Icons.info_outline, title: 'Processing', body: 'We\'re processing your AMC request.'),
        ];
    }
  }

  List<MapEntry<String, String>> _auditReceiptRows() {
    final locations = (data['locations'] as List?) ?? [];
    final proposal = data['auditFeeProposal'] as Map<String, dynamic>?;
    final equipmentFeeVal = (data['equipmentFee'] as num?)?.toDouble() ?? 0;
    final transportVal = (data['equipmentTransportCharge'] as num?)?.toDouble() ?? 0;
    final accessEquipmentStr = data['accessEquipment'] as String?;
    if (proposal != null) {
      final auditFeeNum = (proposal['auditFee'] as num?)?.toDouble() ?? 0;
      final gstPercentNum = (proposal['gstPercent'] as num?)?.toDouble() ?? 18;
      final subtotal = auditFeeNum + equipmentFeeVal + transportVal;
      final total = subtotal + subtotal * (gstPercentNum / 100);
      return [
        MapEntry('Locations Covered', '${proposal['locationsCovered'] ?? '-'}'),
        if (equipmentFeeVal > 0)
          MapEntry(accessEquipmentStr == 'h_frame' ? 'H-Frame Equipment Fee' : 'Ladder Equipment Fee', '₹${equipmentFeeVal.toStringAsFixed(2)}'),
        if (transportVal > 0) MapEntry('Equipment Transport', '₹${transportVal.toStringAsFixed(2)}'),
        MapEntry('Total Payable', '₹${total.toStringAsFixed(2)}'),
        MapEntry('Payment ID', '${data['auditPaymentId'] ?? '-'}'),
      ];
    }
    return [
      MapEntry('Locations', '${locations.length}'),
      MapEntry('Total Audit Fee', '₹${((data['totalAuditFee'] as num?)?.toDouble() ?? 0).toStringAsFixed(2)}'),
      MapEntry('GST', '₹${((data['totalGst'] as num?)?.toDouble() ?? 0).toStringAsFixed(2)}'),
      MapEntry('Total Paid', '₹${((data['totalPayable'] as num?)?.toDouble() ?? 0).toStringAsFixed(2)}'),
      MapEntry('Payment ID', '${data['auditPaymentId'] ?? '-'}'),
    ];
  }

  // ── Audit visit tracker (3 steps, reused style) ─────────────────────────

  int get _auditStageIndex {
    switch (_phase) {
      case 'audit_scheduled':
        return 1;
      case 'audit_in_progress':
        return 2;
      case 'audit_completed':
      case 'final_quotation_sent':
      case 'amc_confirmed':
        return 3;
      default:
        return 0;
    }
  }

  List<Widget> _auditTracker({bool collapsed = false}) {
    if (collapsed) {
      return [
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(color: AppColors.white, borderRadius: BorderRadius.circular(12), border: Border.all(color: AppColors.cardBorder)),
          child: const Row(
            children: [
              Icon(Icons.check_circle, color: AppColors.green, size: 18),
              SizedBox(width: 10),
              Expanded(child: Text('AMC Initial Signage Audit completed', style: TextStyle(color: AppColors.navy, fontSize: 12.5, fontWeight: FontWeight.w600))),
            ],
          ),
        ),
      ];
    }

    final techName = data['auditTeamName'] as String?;
    final visitDate = data['auditVisitDate'] as Timestamp?;
    final visitTimeStart = data['auditVisitTimeStart'] as String?;
    final visitTimeEnd = data['auditVisitTimeEnd'] as String?;

    return [
      const Padding(
        padding: EdgeInsets.only(bottom: 12),
        child: Text('AMC Initial Signage Audit', style: TextStyle(color: AppColors.navy, fontSize: 14, fontWeight: FontWeight.w700)),
      ),
      _stepTile(
        index: 0,
        icon: Icons.payments_outlined,
        title: 'Audit Fee Paid',
        subtitle: 'We\'ll notify you once the audit team is scheduled.',
        isLast: false,
      ),
      _stepTile(
        index: 1,
        icon: Icons.event_available_outlined,
        title: 'Audit Team Scheduled',
        subtitle: _auditStageIndex >= 1
            ? '${techName ?? 'Our team'} will visit on ${_formatDate(visitDate)}${visitTimeStart != null ? ', $visitTimeStart - ${visitTimeEnd ?? ''}' : ''}'
            : 'Pending scheduling.',
        isLast: false,
      ),
      _stepTile(
        index: 2,
        icon: Icons.hourglass_top_outlined,
        title: 'Audit In Progress',
        subtitle: _auditStageIndex == 2
            ? '${techName ?? 'Our team'} is on-site conducting the signage audit.'
            : (_auditStageIndex > 2 ? 'Audit visit completed.' : 'Not started yet.'),
        isLast: false,
      ),
      _stepTile(
        index: 3,
        icon: Icons.fact_check_outlined,
        title: 'Audit Completed',
        subtitle: _auditStageIndex >= 3 ? 'Signage audit completed. Preparing your quotation.' : 'Not completed yet.',
        isLast: true,
      ),
    ];
  }

  Widget _stepTile({required int index, required IconData icon, required String title, required String subtitle, required bool isLast}) {
    final reached = _auditStageIndex >= index;
    final textColor = reached ? AppColors.navy : AppColors.grey;
    final color = reached ? AppColors.yellowDark : AppColors.greyLight;
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Column(
            children: [
              Container(
                width: 36, height: 36,
                decoration: BoxDecoration(color: reached ? AppColors.yellow : AppColors.white, shape: BoxShape.circle, border: Border.all(color: color, width: 1.5)),
                child: Icon(icon, color: reached ? AppColors.navy : AppColors.greyLight, size: 18),
              ),
              if (!isLast)
                Expanded(child: Container(width: 2, margin: const EdgeInsets.symmetric(vertical: 2), color: reached ? AppColors.yellowDark : AppColors.greyLight)),
            ],
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Padding(
              padding: EdgeInsets.only(bottom: isLast ? 0 : 22, top: 6),
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

  // ── Shared card widgets ─────────────────────────────────────────────────

  Widget _phaseCard({required IconData icon, required String title, required String body, bool highlight = false}) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: AppColors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: highlight ? AppColors.green : AppColors.cardBorder, width: highlight ? 1.5 : 1),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: highlight ? AppColors.green : AppColors.serviceAccent, size: 24),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: const TextStyle(color: AppColors.navy, fontSize: 14, fontWeight: FontWeight.w700)),
                const SizedBox(height: 4),
                Text(body, style: const TextStyle(color: AppColors.grey, fontSize: 12, height: 1.4)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _quotationCard({
    required BuildContext context,
    required String title,
    required List<MapEntry<String, String>> rows,
    String? statusChip,
    String? notes,
    required String pdfTitle,
    required String pdfFilename,
    required Future<void> Function() onGeneratePdf,
  }) {
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
              Expanded(child: Text(title, style: const TextStyle(color: AppColors.navy, fontSize: 14, fontWeight: FontWeight.w700))),
              if (statusChip != null)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(color: AppColors.green.withOpacity(0.15), borderRadius: BorderRadius.circular(6)),
                  child: Text(statusChip, style: const TextStyle(color: AppColors.green, fontSize: 10, fontWeight: FontWeight.w700)),
                ),
            ],
          ),
          const SizedBox(height: 12),
          ...rows.map((r) => _rowWidget(r.key, r.value)),
          if (notes != null && notes.trim().isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(notes, style: const TextStyle(color: AppColors.grey, fontSize: 11.5, height: 1.4)),
          ],
          const SizedBox(height: 14),
          _pdfButton(
            label: 'Save as PDF',
            onTap: () async {
              try {
                await onGeneratePdf();
              } catch (e) {
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(backgroundColor: AppColors.red, content: Text('PDF failed: $e', style: const TextStyle(color: Colors.white))),
                  );
                }
              }
            },
          ),
        ],
      ),
    );
  }

  Widget _requestRefundButton(BuildContext context, {required String paymentAgainst}) {
    String? paymentId;
    double amount;
    String label;

    if (paymentAgainst == 'audit') {
      paymentId = data['auditPaymentId'] as String?;
      final proposal = data['auditFeeProposal'] as Map<String, dynamic>?;
      final auditFeeNum = (proposal?['auditFee'] as num?)?.toDouble() ?? (data['totalAuditFee'] as num?)?.toDouble() ?? 0;
      final gstPercentNum = (proposal?['gstPercent'] as num?)?.toDouble() ?? 18;
      final equipmentFeeVal = (data['equipmentFee'] as num?)?.toDouble() ?? 0;
      final transportVal = (data['equipmentTransportCharge'] as num?)?.toDouble() ?? 0;
      final subtotal = auditFeeNum + equipmentFeeVal + transportVal;
      amount = subtotal > 0 ? subtotal + subtotal * (gstPercentNum / 100) : ((data['totalPayable'] as num?)?.toDouble() ?? 0);
      label = 'AMC Audit Fee';
    } else {
      paymentId = data['finalPaymentId'] as String?;
      final quotation = data['finalQuotation'] as Map<String, dynamic>? ?? {};
      final commercialNum = (quotation['commercialValue'] as num?)?.toDouble() ?? 0;
      final gstPercentNum = (quotation['gstPercent'] as num?)?.toDouble() ?? 18;
      amount = commercialNum + commercialNum * (gstPercentNum / 100);
      label = 'AMC Final Payment';
    }

    if (paymentId == null || paymentId.trim().isEmpty) return const SizedBox.shrink();

    return SizedBox(
      width: double.infinity,
      child: OutlinedButton.icon(
        onPressed: () => Navigator.pushNamed(
          context,
          AppRoutes.requestRefund,
          arguments: {
            'collection': 'amc_requests',
            'requestId': requestId,
            'serviceLabel': 'AMC',
            'paymentOptions': [
              RefundablePayment(
                label: label,
                paymentAgainst: paymentAgainst,
                razorpayPaymentId: paymentId!,
                amount: amount,
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

  Widget _receiptCard({
    required BuildContext context,
    required String title,
    required List<MapEntry<String, String>> rows,
    required String pdfFilename,
    required Future<void> Function() onGeneratePdf,
  }) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: AppColors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.green.withOpacity(0.4), width: 1),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.check_circle, color: AppColors.green, size: 18),
              const SizedBox(width: 8),
              Expanded(child: Text(title, style: const TextStyle(color: AppColors.navy, fontSize: 14, fontWeight: FontWeight.w700))),
            ],
          ),
          const SizedBox(height: 12),
          ...rows.map((r) => _rowWidget(r.key, r.value)),
          const SizedBox(height: 14),
          _pdfButton(
            label: 'Download Receipt',
            onTap: () async {
              try {
                await onGeneratePdf();
              } catch (e) {
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(backgroundColor: AppColors.red, content: Text('PDF failed: $e', style: const TextStyle(color: Colors.white))),
                  );
                }
              }
            },
          ),
        ],
      ),
    );
  }

  Widget _rowWidget(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            flex: 4,
            child: Text(label, style: const TextStyle(color: AppColors.grey, fontSize: 12.5)),
          ),
          const SizedBox(width: 10),
          Expanded(
            flex: 6,
            child: Text(
              value,
              textAlign: TextAlign.right,
              softWrap: true,
              style: const TextStyle(color: AppColors.navy, fontSize: 12.5, fontWeight: FontWeight.w700),
            ),
          ),
        ],
      ),
    );
  }

  Widget _pdfButton({required String label, required VoidCallback onTap}) {
    return SizedBox(
      width: double.infinity,
      child: OutlinedButton.icon(
        onPressed: onTap,
        icon: const Icon(Icons.picture_as_pdf_outlined, color: AppColors.serviceAccent, size: 16),
        label: Text(label, style: const TextStyle(color: AppColors.serviceAccent, fontWeight: FontWeight.w600, fontSize: 12.5)),
        style: OutlinedButton.styleFrom(
          side: const BorderSide(color: AppColors.serviceAccent, width: 1),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          padding: const EdgeInsets.symmetric(vertical: 10),
        ),
      ),
    );
  }

  Widget _actionButton({required String label, required VoidCallback? onPressed, required bool busy}) {
    return SizedBox(
      width: double.infinity,
      height: 54,
      child: ElevatedButton(
        onPressed: onPressed,
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColors.yellow,
          foregroundColor: AppColors.navy,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          elevation: 2,
        ),
        child: busy
            ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.navy))
            : Text(label, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800, letterSpacing: 0.5)),
      ),
    );
  }

  String _num(dynamic v) {
    if (v == null) return '0';
    if (v is num) return v.toStringAsFixed(0);
    return v.toString();
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

String? _firstLocationAddress(Map<String, dynamic> data) {
  final locations = data['locations'] as List?;
  if (locations == null || locations.isEmpty) return null;
  final first = locations.first as Map<String, dynamic>?;
  return first?['address'] as String?;
}

String _formatDate(Timestamp? ts) {
  if (ts == null) return 'TBD';
  final dt = ts.toDate();
  const months = ['Jan','Feb','Mar','Apr','May','Jun','Jul','Aug','Sep','Oct','Nov','Dec'];
  return '${dt.day} ${months[dt.month - 1]} ${dt.year}';
}