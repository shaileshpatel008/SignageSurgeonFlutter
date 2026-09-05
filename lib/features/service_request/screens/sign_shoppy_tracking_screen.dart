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
import '../../../core/widgets/rejection_reason_dialog.dart';
import '../../../core/constants/app_routes.dart';
import '../../refund/screens/request_refund_screen.dart';
import '../../rating/screens/rating_card.dart';
import '../../support/screens/report_problem_screen.dart';

class SignShoppyTrackingScreen extends StatefulWidget {
  const SignShoppyTrackingScreen({super.key});

  @override
  State<SignShoppyTrackingScreen> createState() => _SignShoppyTrackingScreenState();
}

class _SignShoppyTrackingScreenState extends State<SignShoppyTrackingScreen> {
  final _razorpay = Razorpay();
  static const String _razorpayKeyId = 'rzp_test_TDKf4pilC4l0id';
  bool _busy = false;
  String? _requestId;

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
      await FirebaseFirestore.instance.collection('sign_shoppy_interests').doc(_requestId).update({
        'orderPhase': 'quotation_rejected',
        'quotationRejectedAt': FieldValue.serverTimestamp(),
        'rejectionReason': result.fullReason,
      });
    } catch (_) {
      _showSnack('Could not reject quotation. Please try again.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _openPayNow(Map<String, dynamic> quotation) {
    setState(() => _busy = true);
    final total = (quotation['totalPayable'] as num?)?.toDouble() ?? 0;
    final amountPaise = (total * 100).round();
    final options = {
      'key': _razorpayKeyId,
      'amount': amountPaise,
      'currency': 'INR',
      'name': 'The Signage Surgeon',
      'description': 'Sign Shoppy Order Payment',
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
      final otp = (1000 + Random().nextInt(9000)).toString();
      await FirebaseFirestore.instance.collection('sign_shoppy_interests').doc(_requestId).update({
        'orderPhase': 'paid',
        'quotationApprovedAt': FieldValue.serverTimestamp(),
        'paymentId': response.paymentId,
        'paymentStatus': 'paid',
        'deliveryOtp': otp,
      });
    } catch (e) {
      _showSnack('Payment succeeded but updating your order failed. Contact support with payment ID: ${response.paymentId}');
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
    final requestId = ModalRoute.of(context)?.settings.arguments as String?;
    _requestId = requestId;

    if (requestId == null) {
      return Scaffold(
        backgroundColor: AppColors.offWhite,
        appBar: AppBar(backgroundColor: AppColors.serviceAccent, elevation: 0),
        body: const Center(child: Text('Order not found', style: TextStyle(color: AppColors.grey))),
      );
    }

    return Scaffold(
      backgroundColor: AppColors.offWhite,
      appBar: _buildAppBar(context),
      body: StreamBuilder<DocumentSnapshot>(
        stream: FirebaseFirestore.instance.collection('sign_shoppy_interests').doc(requestId).snapshots(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator(color: AppColors.yellow));
          }
          if (!snapshot.hasData || !snapshot.data!.exists) {
            return const Center(child: Text('This order could not be found.', style: TextStyle(color: AppColors.grey)));
          }
          final data = snapshot.data!.data() as Map<String, dynamic>;
          return _OrderBody(
            requestId: requestId,
            data: data,
            busy: _busy,
            onReject: _rejectQuotation,
            onPay: _openPayNow,
          );
        },
      ),
    );
  }

  PreferredSizeWidget _buildAppBar(BuildContext context) {
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
      title: const Text('Track Your Order', style: TextStyle(color: AppColors.navy, fontSize: 17, fontWeight: FontWeight.w700)),
    );
  }
}

class _OrderBody extends StatelessWidget {
  final String requestId;
  final Map<String, dynamic> data;
  final bool busy;
  final VoidCallback onReject;
  final void Function(Map<String, dynamic> quotation) onPay;

  const _OrderBody({
    required this.requestId,
    required this.data,
    required this.busy,
    required this.onReject,
    required this.onPay,
  });

  String get _phase => (data['orderPhase'] as String? ?? 'submitted').trim();

  int get _deliveryStageIndex {
    switch (_phase) {
      case 'order_confirmed':
        return 1;
      case 'order_on_the_way':
        return 2;
      case 'order_received':
        return 3;
      default:
        return 0;
    }
  }

  @override
  Widget build(BuildContext context) {
    final productName = data['productName'] as String? ?? 'Signage Product';
    final createdAt = data['createdAt'] as Timestamp?;
    final quotation = data['quotation'] as Map<String, dynamic>?;

    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 30),
      children: [
        _summaryCard(productName, createdAt),
        const SizedBox(height: 24),

        _phaseStep(
          icon: Icons.check_circle_outline,
          title: 'Request Submitted',
          subtitle: 'We\'ve received your interest in this product.',
          done: true,
        ),
        _phaseStep(
          icon: Icons.description_outlined,
          title: 'Quotation Coming',
          subtitle: _phase == 'submitted'
              ? 'Our team is checking availability and preparing a quotation for you.'
              : 'Quotation received — see details below.',
          done: _phase != 'submitted',
          isLast: quotation == null,
        ),

        if (quotation != null) ...[
          const SizedBox(height: 20),
          _quotationCard(context, quotation),
        ],

        if (_phase == 'quotation_rejected') ...[
          const SizedBox(height: 20),
          _rejectedCard(),
        ],

        if (_deliveryStageIndex >= 1 || _phase == 'paid') ...[
          const SizedBox(height: 24),
          const Padding(
            padding: EdgeInsets.only(bottom: 4, left: 4),
            child: Text('Delivery', style: TextStyle(color: AppColors.navy, fontSize: 14, fontWeight: FontWeight.w700)),
          ),
          const SizedBox(height: 10),
          _deliveryTracker(context),
        ],
      ],
    );
  }

  Widget _summaryCard(String productName, Timestamp? createdAt) {
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
                child: const Icon(Icons.storefront_outlined, color: Colors.white, size: 22),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(productName, style: const TextStyle(color: AppColors.navy, fontSize: 15, fontWeight: FontWeight.w700)),
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

  Widget _reportProblemButton(BuildContext context) {
    final productName = data['productName'] as String? ?? 'Signage Product';
    return SizedBox(
      width: double.infinity,
      child: OutlinedButton.icon(
        onPressed: () => Navigator.pushNamed(
          context,
          AppRoutes.reportProblem,
          arguments: {
            'collection': 'sign_shoppy_interests',
            'requestId': requestId,
            'serviceLabel': 'Sign Shoppy — $productName',
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
    final unitPriceNum = (quotation?['unitPrice'] as num?)?.toDouble() ?? 0;
    final quantityAvailableNum = double.tryParse(quotation?['quantityAvailable']?.toString() ?? '');
    final totalPiecePriceNum = (quantityAvailableNum != null) ? unitPriceNum * quantityAvailableNum : 0.0;
    final additionalChargesNum = (quotation?['additionalCharges'] as num?)?.toDouble() ?? 0;
    final gstPercentNum = (quotation?['gstPercent'] as num?)?.toDouble() ?? 18;
    final subtotal = totalPiecePriceNum + additionalChargesNum;
    final totalPayable = subtotal + (subtotal * gstPercentNum / 100);

    final productName = data['productName'] as String? ?? 'Signage Product';

    return SizedBox(
      width: double.infinity,
      child: OutlinedButton.icon(
        onPressed: () => Navigator.pushNamed(
          context,
          AppRoutes.requestRefund,
          arguments: {
            'collection': 'sign_shoppy_interests',
            'requestId': requestId,
            'serviceLabel': 'Sign Shoppy — $productName',
            'paymentOptions': [
              RefundablePayment(
                label: 'Order Payment',
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

  Widget _quotationCard(BuildContext context, Map<String, dynamic> quotation) {
    final unitPriceNum = (quotation['unitPrice'] as num?)?.toDouble() ?? 0;
    final quantityAvailable = quotation['quantityAvailable']?.toString();
    final quantityAvailableNum = double.tryParse(quantityAvailable ?? '');
    final totalPiecePriceNum = (quantityAvailableNum != null) ? unitPriceNum * quantityAvailableNum : 0.0;
    final availabilityNote = quotation['availabilityNote']?.toString();
    final additionalChargesNum = (quotation['additionalCharges'] as num?)?.toDouble() ?? 0;
    final gstPercentNum = (quotation['gstPercent'] as num?)?.toDouble() ?? 18;
    // Single combined subtotal with GST applied once, 2 decimal precision —
    // matches every other service's quotation card and the PDF.
    final subtotal = totalPiecePriceNum + additionalChargesNum;
    final gstAmountNum = subtotal * (gstPercentNum / 100);
    final totalPayableNum = subtotal + gstAmountNum;

    final pdfRows = <MapEntry<String, String>>[
      MapEntry('Unit Price', '₹${unitPriceNum.toStringAsFixed(2)}'),
      if (quantityAvailable != null) MapEntry('Quantity Available', quantityAvailable),
      if (totalPiecePriceNum > 0) MapEntry('Total Price (All Pieces)', '₹${totalPiecePriceNum.toStringAsFixed(2)}'),
      if (additionalChargesNum > 0) MapEntry('Additional Charges', '₹${additionalChargesNum.toStringAsFixed(2)}'),
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
              const Expanded(child: Text('Quotation', style: TextStyle(color: AppColors.navy, fontSize: 14, fontWeight: FontWeight.w700))),
              if (_phase == 'quotation_approved' || _deliveryStageIndex >= 1)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(color: AppColors.green.withOpacity(0.15), borderRadius: BorderRadius.circular(6)),
                  child: const Text('Approved', style: TextStyle(color: AppColors.green, fontSize: 10, fontWeight: FontWeight.w700)),
                ),
            ],
          ),
          if (availabilityNote != null && availabilityNote.trim().isNotEmpty) ...[
            const SizedBox(height: 12),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(color: const Color(0xFFFFA500).withOpacity(0.1), borderRadius: BorderRadius.circular(10)),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(Icons.info_outline, color: Color(0xFFFFA500), size: 16),
                  const SizedBox(width: 8),
                  Expanded(child: Text(availabilityNote, style: const TextStyle(color: AppColors.navy, fontSize: 12, height: 1.5))),
                ],
              ),
            ),
          ],
          const SizedBox(height: 12),
          ...pdfRows.map((r) => _rowWidget(r.key, r.value)),
          const SizedBox(height: 14),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: () async {
                try {
                  final profile = await _fetchCustomerProfileShared(data['userId'] as String?);
                  final assets = await _loadBrandAssetsShared();
                  await QuotationPdf.generateAndShare(QuotationPdfData(
                    quotationNo: quotation['quotationNumber']?.toString() ?? requestId.substring(0, requestId.length < 8 ? requestId.length : 8),
                    requestId: requestId,
                    customerId: (data['userId'] as String?) ?? '',
                    date: DateTime.now(),
                    validTill: DateTime.now().add(const Duration(days: 7)),
                    status: (_phase == 'quotation_approved' || _deliveryStageIndex >= 1) ? QuotationStatus.approved : QuotationStatus.sent,
                    customerName: (profile?['fullName'] as String?) ?? (profile?['businessName'] as String?) ?? 'Customer',
                    mobileNumber: FirebaseAuth.instance.currentUser?.phoneNumber,
                    email: profile?['email'] as String?,
                    siteAddress: (data['location'] as Map<String, dynamic>?)?['address'] as String?,
                    gstNumber: profile?['gstNumber'] as String?,
                    serviceCategory: QuotationServiceCategory.signShoppy,
                    serviceType: data['productName'] as String? ?? 'Signage Product',
                    scopeOfWork: (availabilityNote != null && availabilityNote.trim().isNotEmpty) ? availabilityNote : 'No additional notes provided.',
                    serviceCharges: totalPiecePriceNum,
                    additionalCharges: additionalChargesNum,
                    subtotal: subtotal,
                    discount: 0,
                    gstPercent: gstPercentNum,
                    grandTotal: totalPayableNum,
                    paymentTerms: 'Advance payment is required before dispatch.',
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

          if (_phase == 'quotation_sent') ...[
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
                const Text('Quotation rejected. This order has been closed.', style: TextStyle(color: AppColors.navy, fontSize: 12.5, height: 1.4)),
                if (reason != null) ...[
                  const SizedBox(height: 6),
                  Text('Reason: $reason', style: const TextStyle(color: AppColors.grey, fontSize: 11.5, height: 1.4)),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _deliveryTracker(BuildContext context) {
    final expectedDelivery = data['expectedDeliveryDate'] as Timestamp?;
    final deliveryOtp = data['deliveryOtp'] as String?;

    return Column(
      children: [
        _stepTile(
          index: 0,
          icon: Icons.payments_outlined,
          title: 'Order Confirmed',
          subtitle: _deliveryStageIndex >= 1
              ? 'Your order is confirmed. Expected delivery by ${_formatDate(expectedDelivery)}.'
              : 'Payment received — we\'ll confirm your order shortly.',
          isLast: false,
        ),
        _stepTile(
          index: 2,
          icon: Icons.local_shipping_outlined,
          title: 'Order On The Way',
          subtitle: _deliveryStageIndex >= 2 ? 'Your order is out for delivery.' : 'Not dispatched yet.',
          isLast: false,
        ),
        if (_deliveryStageIndex == 2 && deliveryOtp != null) ...[
          const SizedBox(height: 8),
          _otpCard(deliveryOtp),
        ],
        _stepTile(
          index: 3,
          icon: Icons.task_alt_outlined,
          title: 'Order Received',
          subtitle: _deliveryStageIndex >= 3 ? 'Delivered successfully. Thank you for your order!' : 'Not delivered yet.',
          isLast: true,
        ),
        if (_deliveryStageIndex >= 3) ...[
          const SizedBox(height: 16),
          _requestRefundButton(context),
          const SizedBox(height: 12),
          RatingCard(collection: 'sign_shoppy_interests', requestId: requestId, serviceLabel: 'Sign Shoppy'),
          const SizedBox(height: 12),
          _reportProblemButton(context),
        ],
      ],
    );
  }

  Widget _stepTile({required int index, required IconData icon, required String title, required String subtitle, required bool isLast}) {
    final reached = _deliveryStageIndex >= index;
    final isCurrent = _deliveryStageIndex == index;
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

  Widget _otpCard(String otp) {
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
                const Text('Delivery OTP', style: TextStyle(color: AppColors.navy, fontSize: 12, fontWeight: FontWeight.w700)),
                const SizedBox(height: 4),
                Text(otp, style: const TextStyle(color: AppColors.navy, fontSize: 22, fontWeight: FontWeight.w800, letterSpacing: 4)),
                const SizedBox(height: 4),
                const Text(
                  'Only share this with the delivery person once your order physically arrives — this confirms it reached you and not someone else.',
                  style: TextStyle(color: AppColors.grey, fontSize: 10.5, height: 1.3),
                ),
              ],
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
          Expanded(flex: 2, child: Text(value, textAlign: TextAlign.right, style: const TextStyle(color: AppColors.navy, fontSize: 12.5, fontWeight: FontWeight.w700))),
        ],
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

String _formatDate(Timestamp? ts) {
  if (ts == null) return 'TBD';
  final dt = ts.toDate();
  const months = ['Jan','Feb','Mar','Apr','May','Jun','Jul','Aug','Sep','Oct','Nov','Dec'];
  return '${dt.day} ${months[dt.month - 1]} ${dt.year}';
}