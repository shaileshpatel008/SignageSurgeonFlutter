import 'dart:typed_data';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

enum PaymentStatus { paid, partiallyPaid, failed, refunded, refundProcessing }

enum ServiceCategory { repairing, rebranding, newSignage, cleaning, amc, signShoppy }

enum PaymentAgainst { siteVisit, advance, partial, finalPayment, amc, signShoppyOrder, other }

enum PaymentMethod { upi, creditCard, debitCard, netBanking, cash, cheque, wallet }

/// Every field the receipt can display. Pass null / empty for anything that
/// doesn't apply to a given payment — the layout skips blank rows instead of
/// showing empty labels.
///
/// Note per finalized business rule: Site Visit / Assessment Fee is
/// collected BEFORE the visit happens, so this receipt intentionally has no
/// visit date / assigned vendor / assigned executive fields — don't add them.
class PaymentReceiptData {
  final String receiptNo;
  final String? paymentId;
  final String? transactionId;
  final String requestId;
  final String? quotationNo;
  final DateTime receiptDate;
  final DateTime? paymentDate;
  final PaymentStatus status;

  final String customerName;
  final String? concernPerson;
  final String? mobileNumber;
  final String? emailAddress;
  final String? siteAddress;
  final String? gstNumber;

  final ServiceCategory serviceCategory;
  final String serviceType;

  final PaymentAgainst paymentAgainst;
  final String? paymentAgainstOther;

  final double amountBeforeGst;
  // Optional itemized breakdown shown above "Amount Before GST" — all
  // optional since simpler payments (e.g. a plain site-visit fee) don't
  // need them.
  final double? serviceChargesItem;
  final double? additionalChargesItem;
  final double? equipmentFeeItem;
  final double? transportChargeItem;
  final String? accessEquipmentLabel; // e.g. "Ladder" or "H-Frame", for the fee row's label
  final double gstPercent; // fixed at 18 per finalized business rule
  final double totalAmount;
  final double amountPaid;
  final double balanceAmount;

  final PaymentMethod? paymentMethod;
  final String? referenceNumber;
  final String? transactionNumber;
  final String? collectedBy;

  // Optional brand assets — pass raw image bytes (PNG recommended).
  final Uint8List? logoBytes;
  final Uint8List? mascotBytes;
  final Uint8List? qrCodeBytes;

  const PaymentReceiptData({
    required this.receiptNo,
    this.paymentId,
    this.transactionId,
    required this.requestId,
    this.quotationNo,
    required this.receiptDate,
    this.paymentDate,
    required this.status,
    required this.customerName,
    this.concernPerson,
    this.mobileNumber,
    this.emailAddress,
    this.siteAddress,
    this.gstNumber,
    required this.serviceCategory,
    required this.serviceType,
    required this.paymentAgainst,
    this.paymentAgainstOther,
    required this.amountBeforeGst,
    this.serviceChargesItem,
    this.additionalChargesItem,
    this.equipmentFeeItem,
    this.transportChargeItem,
    this.accessEquipmentLabel,
    this.gstPercent = 18,
    required this.totalAmount,
    required this.amountPaid,
    required this.balanceAmount,
    this.paymentMethod,
    this.referenceNumber,
    this.transactionNumber,
    this.collectedBy,
    this.logoBytes,
    this.mascotBytes,
    this.qrCodeBytes,
  });

  double get gstAmount => amountBeforeGst * (gstPercent / 100);
  double get cgstAmount => gstAmount / 2;
  double get sgstAmount => gstAmount / 2;
}

class PaymentReceiptPdf {
  static const PdfColor _red = PdfColor.fromInt(0xFFE2000F);
  static const PdfColor _black = PdfColors.black;
  static const PdfColor _grey = PdfColor.fromInt(0xFF6B7280);
  static const PdfColor _lightGrey = PdfColor.fromInt(0xFFE5E7EB);
  static const PdfColor _greenBg = PdfColor.fromInt(0xFFE8F8EE);
  static const PdfColor _green = PdfColor.fromInt(0xFF16A34A);
  static const PdfColor _amberBg = PdfColor.fromInt(0xFFFFF6E5);
  static const PdfColor _amber = PdfColor.fromInt(0xFFB45309);
  static const PdfColor _redBg = PdfColor.fromInt(0xFFFDE8E9);
  static const PdfColor _greyBg = PdfColor.fromInt(0xFFF1F2F4);

  static String _sanitizeFilename(String input) {
    final cleaned = input.replaceAll(RegExp(r'[^A-Za-z0-9_-]'), '_');
    return cleaned.isEmpty ? 'Document' : cleaned;
  }

  static Future<void> generateAndShare(PaymentReceiptData d) async {
    final doc = pw.Document();

    doc.addPage(
      pw.MultiPage(
        pageTheme: pw.PageTheme(
          pageFormat: PdfPageFormat.a4,
          margin: const pw.EdgeInsets.fromLTRB(36, 36, 36, 30),
          buildBackground: (context) => pw.FullPage(
            ignoreMargins: true,
            child: pw.Center(
              child: pw.Transform.rotate(
                angle: 0.5,
                child: pw.Opacity(
                  opacity: 0.04,
                  child: pw.Text(
                    'THE SIGNAGE SURGEON',
                    style: pw.TextStyle(fontSize: 60, fontWeight: pw.FontWeight.bold, color: _black),
                  ),
                ),
              ),
            ),
          ),
        ),
        build: (context) => [
          pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              _header(d),
              _divider(),
              _legalDetails(),
              _divider(),
              _receiptInfo(d),
              _divider(),
              _customerDetails(d),
              _divider(),
              _serviceDetails(d),
              _divider(),
              _paymentAgainstSection(d),
              _divider(),
              _amountTable(d),
              _divider(),
              _paymentMethodSection(d),
              _divider(),
              _bankDetailsAndQr(d),
              pw.SizedBox(height: 14),
              _summaryCard(d),
              pw.SizedBox(height: 14),
              _notes(),
              pw.SizedBox(height: 20),
              _footer(),
            ],
          ),
        ],
      ),
    );

    final serviceLabel = _sanitizeFilename(d.serviceType);
    await Printing.sharePdf(bytes: await doc.save(), filename: 'Payment_Receipt_${serviceLabel}_${_sanitizeFilename(d.receiptNo)}.pdf');
  }

  // ── Header ───────────────────────────────────────────────────────────

  static pw.Widget _header(PaymentReceiptData d) {
    return pw.Row(
      mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Row(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            if (d.logoBytes != null) ...[
              pw.Image(pw.MemoryImage(d.logoBytes!), width: 40, height: 40),
              pw.SizedBox(width: 10),
            ],
            pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Text('THE SIGNAGE SURGEON', style: pw.TextStyle(fontSize: 20, fontWeight: pw.FontWeight.bold, color: _black)),
                pw.SizedBox(height: 2),
                pw.Text('NEW LIFE FOR OLD SIGNS.', style: pw.TextStyle(fontSize: 9, color: _grey, fontStyle: pw.FontStyle.italic)),
              ],
            ),
          ],
        ),
        pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.end,
          children: [
            pw.Text('PAYMENT RECEIPT', style: pw.TextStyle(fontSize: 13, fontWeight: pw.FontWeight.bold, color: _red, letterSpacing: 1)),
            pw.SizedBox(height: 8),
            _statusBadge(d.status, large: true),
          ],
        ),
      ],
    );
  }

  static pw.Widget _statusBadge(PaymentStatus status, {bool large = false}) {
    late String label;
    late PdfColor bg, fg;
    switch (status) {
      case PaymentStatus.paid:
        label = 'PAID'; bg = _greenBg; fg = _green;
        break;
      case PaymentStatus.partiallyPaid:
        label = 'PARTIALLY PAID'; bg = _amberBg; fg = _amber;
        break;
      case PaymentStatus.failed:
        label = 'FAILED'; bg = _redBg; fg = _red;
        break;
      case PaymentStatus.refunded:
        label = 'REFUNDED'; bg = _greyBg; fg = _grey;
        break;
      case PaymentStatus.refundProcessing:
        label = 'REFUND PROCESSING'; bg = _amberBg; fg = _amber;
        break;
    }
    return pw.Container(
      padding: pw.EdgeInsets.symmetric(horizontal: large ? 14 : 10, vertical: large ? 7 : 4),
      decoration: pw.BoxDecoration(color: bg, borderRadius: pw.BorderRadius.circular(6)),
      child: pw.Text(label, style: pw.TextStyle(fontSize: large ? 12 : 9, fontWeight: pw.FontWeight.bold, color: fg)),
    );
  }

  // ── Section helpers ──────────────────────────────────────────────────

  static pw.Widget _divider() => pw.Padding(
        padding: const pw.EdgeInsets.symmetric(vertical: 10),
        child: pw.Divider(color: _lightGrey, thickness: 1),
      );

  static pw.Widget _sectionTitle(String title) => pw.Padding(
        padding: const pw.EdgeInsets.only(bottom: 8),
        child: pw.Text(title, style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold, color: _red, letterSpacing: 0.8)),
      );

  static pw.Widget _kvGrid(List<MapEntry<String, String>> rows, {int columns = 2}) {
    final filtered = rows.where((r) => r.value.trim().isNotEmpty).toList();
    if (filtered.isEmpty) return pw.SizedBox();
    final rowsOfPairs = <List<MapEntry<String, String>>>[];
    for (var i = 0; i < filtered.length; i += columns) {
      rowsOfPairs.add(filtered.sublist(i, i + columns > filtered.length ? filtered.length : i + columns));
    }
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: rowsOfPairs.map((pair) {
        return pw.Padding(
          padding: const pw.EdgeInsets.only(bottom: 6),
          child: pw.Row(
            children: pair.map((e) => pw.Expanded(child: _kv(e.key, e.value))).toList()
              ..addAll(List.generate(columns - pair.length, (_) => pw.Expanded(child: pw.SizedBox()))),
          ),
        );
      }).toList(),
    );
  }

  static pw.Widget _kv(String label, String value) {
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Text(label, style: pw.TextStyle(fontSize: 8, color: _grey)),
        pw.SizedBox(height: 2),
        pw.Text(value, style: pw.TextStyle(fontSize: 10, color: _black, fontWeight: pw.FontWeight.bold), softWrap: true),
      ],
    );
  }

  static String _fmtDate(DateTime? dt) {
    if (dt == null) return '';
    const months = ['Jan','Feb','Mar','Apr','May','Jun','Jul','Aug','Sep','Oct','Nov','Dec'];
    return '${dt.day} ${months[dt.month - 1]} ${dt.year}';
  }

  // ── Legal Details ────────────────────────────────────────────────────

  static pw.Widget _legalDetails() {
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Text('Concept3 The Design Workshop', style: pw.TextStyle(fontSize: 11, fontWeight: pw.FontWeight.bold, color: _black)),
        pw.SizedBox(height: 8),
        _kvGrid([
          const MapEntry('GSTIN', '24ALXPP8173D1ZK'),
          const MapEntry('PAN', 'ALXPP8173D'),
          const MapEntry('Email', 'mail@thesignagesurgeon.com'),
          const MapEntry('Website', 'www.thesignagesurgeon.com'),
          const MapEntry('Support', '+91 8141004505'),
        ], columns: 3),
      ],
    );
  }

  // ── Receipt Information ──────────────────────────────────────────────

  static pw.Widget _receiptInfo(PaymentReceiptData d) {
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        _sectionTitle('RECEIPT INFORMATION'),
        _kvGrid([
          MapEntry('Receipt No.', d.receiptNo),
          MapEntry('Payment ID', d.paymentId ?? '-'),
          MapEntry('Transaction ID', d.transactionId ?? '-'),
          MapEntry('Request ID', d.requestId),
          MapEntry('Quotation No.', d.quotationNo ?? '-'),
          MapEntry('Receipt Date', _fmtDate(d.receiptDate)),
          MapEntry('Payment Date', _fmtDate(d.paymentDate)),
        ], columns: 3),
      ],
    );
  }

  // ── Customer Details ─────────────────────────────────────────────────

  static pw.Widget _customerDetails(PaymentReceiptData d) {
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        _sectionTitle('CUSTOMER DETAILS'),
        _kvGrid([
          MapEntry('Customer Name', d.customerName),
          MapEntry('Concern Person', d.concernPerson ?? ''),
          MapEntry('Mobile Number', d.mobileNumber ?? ''),
          MapEntry('Email Address', d.emailAddress ?? ''),
          MapEntry('Site Address', d.siteAddress ?? ''),
          MapEntry('GST Number', d.gstNumber ?? ''),
        ], columns: 2),
      ],
    );
  }

  // ── Service Details ──────────────────────────────────────────────────

  static String _categoryLabel(ServiceCategory c) {
    switch (c) {
      case ServiceCategory.repairing: return 'Repairing';
      case ServiceCategory.rebranding: return 'Rebranding';
      case ServiceCategory.newSignage: return 'New Signage';
      case ServiceCategory.cleaning: return 'Signage Cleaning';
      case ServiceCategory.amc: return 'AMC';
      case ServiceCategory.signShoppy: return 'Sign Shoppy';
    }
  }

  static pw.Widget _serviceDetails(PaymentReceiptData d) {
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        _sectionTitle('SERVICE DETAILS'),
        _kvGrid([
          MapEntry('Service Category', _categoryLabel(d.serviceCategory)),
          MapEntry('Service Type', d.serviceType),
        ], columns: 2),
      ],
    );
  }

  // ── Payment Against ──────────────────────────────────────────────────

  static String _paymentAgainstLabel(PaymentAgainst p, String? other) {
    switch (p) {
      case PaymentAgainst.siteVisit: return 'Site Visit Charges';
      case PaymentAgainst.advance: return 'Advance Payment';
      case PaymentAgainst.partial: return 'Partial Payment';
      case PaymentAgainst.finalPayment: return 'Final Payment';
      case PaymentAgainst.amc: return 'AMC Payment';
      case PaymentAgainst.signShoppyOrder: return 'Sign Shoppy Order';
      case PaymentAgainst.other: return other?.isNotEmpty == true ? other! : 'Other';
    }
  }

  static pw.Widget _paymentAgainstSection(PaymentReceiptData d) {
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        _sectionTitle('PAYMENT DETAILS'),
        _kv('Payment Against', _paymentAgainstLabel(d.paymentAgainst, d.paymentAgainstOther)),
      ],
    );
  }

  // ── Amount Table (now with CGST/SGST split) ──────────────────────────

  static pw.Widget _amountTable(PaymentReceiptData d) {
    pw.Widget row(String label, double amount, {bool bold = false}) {
      return pw.Container(
        padding: const pw.EdgeInsets.symmetric(vertical: 7),
        decoration: pw.BoxDecoration(border: pw.Border(bottom: pw.BorderSide(color: _lightGrey, width: 0.5))),
        child: pw.Row(
          mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
          children: [
            pw.Text(label, style: pw.TextStyle(fontSize: bold ? 10.5 : 9.5, color: _black, fontWeight: bold ? pw.FontWeight.bold : pw.FontWeight.normal)),
            pw.Text('Rs. ${amount.toStringAsFixed(2)}', style: pw.TextStyle(fontSize: bold ? 11 : 9.5, color: bold ? _red : _black, fontWeight: bold ? pw.FontWeight.bold : pw.FontWeight.normal)),
          ],
        ),
      );
    }

    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        _sectionTitle('PAYMENT INFORMATION'),
        if (d.serviceChargesItem != null && d.serviceChargesItem! > 0) row('Service Charges', d.serviceChargesItem!),
        if (d.additionalChargesItem != null && d.additionalChargesItem! > 0) row('Additional Charges', d.additionalChargesItem!),
        if (d.equipmentFeeItem != null && d.equipmentFeeItem! > 0)
          row('${d.accessEquipmentLabel ?? 'Equipment'} Fee', d.equipmentFeeItem!),
        if (d.transportChargeItem != null && d.transportChargeItem! > 0) row('Equipment Transport', d.transportChargeItem!),
        row('Amount Before GST', d.amountBeforeGst),
        row('GST @${d.gstPercent.toStringAsFixed(0)}%', d.gstAmount),
        row('Total Amount', d.totalAmount, bold: true),
        row('Amount Paid', d.amountPaid),
        row('Balance Amount', d.balanceAmount),
      ],
    );
  }

  // ── Payment Method ───────────────────────────────────────────────────

  static String? _methodLabel(PaymentMethod? m) {
    if (m == null) return null;
    switch (m) {
      case PaymentMethod.upi: return 'UPI';
      case PaymentMethod.creditCard: return 'Credit Card';
      case PaymentMethod.debitCard: return 'Debit Card';
      case PaymentMethod.netBanking: return 'Net Banking';
      case PaymentMethod.cash: return 'Cash';
      case PaymentMethod.cheque: return 'Cheque';
      case PaymentMethod.wallet: return 'Wallet';
    }
  }

  static pw.Widget _paymentMethodSection(PaymentReceiptData d) {
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        _sectionTitle('PAYMENT METHOD'),
        _kvGrid([
          MapEntry('Method', _methodLabel(d.paymentMethod) ?? ''),
          MapEntry('Reference Number', d.referenceNumber ?? ''),
          MapEntry('Transaction Number', d.transactionNumber ?? ''),
          MapEntry('Collected By', d.collectedBy ?? ''),
        ], columns: 2),
      ],
    );
  }

  // ── Bank Details + QR (real image if provided, placeholder otherwise) ──

  static pw.Widget _bankDetailsAndQr(PaymentReceiptData d) {
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        _sectionTitle('BANK DETAILS'),
        _kv('Account Name', 'CONCEPT3 THE DESIGN WORKSHOP'),
        pw.SizedBox(height: 6),
        _kv('Bank', 'Kalupur Commercial Co-operative Bank'),
        pw.SizedBox(height: 6),
        _kv('Account Number', '01520102838'),
        pw.SizedBox(height: 6),
        _kv('IFSC', 'KCCB0VSR015'),
        pw.SizedBox(height: 6),
        _kv('Branch', 'Vastrapur, Ahmedabad, Gujarat'),
      ],
    );
  }

  // ── Payment Summary Card ─────────────────────────────────────────────

  static pw.Widget _summaryCard(PaymentReceiptData d) {
    return pw.Container(
      width: double.infinity,
      padding: const pw.EdgeInsets.all(16),
      decoration: pw.BoxDecoration(
        color: _greyBg,
        borderRadius: pw.BorderRadius.circular(8),
        border: pw.Border.all(color: _lightGrey, width: 1),
      ),
      child: pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
        crossAxisAlignment: pw.CrossAxisAlignment.center,
        children: [
          pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Text('PAYMENT SUMMARY', style: pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold, color: _red, letterSpacing: 0.8)),
              pw.SizedBox(height: 10),
              pw.Row(children: [
                pw.SizedBox(width: 110, child: pw.Text('Total Invoice', style: pw.TextStyle(fontSize: 9.5, color: _grey))),
                pw.Text('Rs. ${d.totalAmount.toStringAsFixed(2)}', style: pw.TextStyle(fontSize: 10, color: _black, fontWeight: pw.FontWeight.bold)),
              ]),
              pw.SizedBox(height: 4),
              pw.Row(children: [
                pw.SizedBox(width: 110, child: pw.Text('Total Paid', style: pw.TextStyle(fontSize: 9.5, color: _grey))),
                pw.Text('Rs. ${d.amountPaid.toStringAsFixed(2)}', style: pw.TextStyle(fontSize: 10, color: _black, fontWeight: pw.FontWeight.bold)),
              ]),
              pw.SizedBox(height: 4),
              pw.Row(children: [
                pw.SizedBox(width: 110, child: pw.Text('Outstanding Amount', style: pw.TextStyle(fontSize: 9.5, color: _grey))),
                pw.Text('Rs. ${d.balanceAmount.toStringAsFixed(2)}', style: pw.TextStyle(fontSize: 11, color: _red, fontWeight: pw.FontWeight.bold)),
              ]),
            ],
          ),
          _statusBadge(d.status, large: true),
        ],
      ),
    );
  }

  // ── Notes ────────────────────────────────────────────────────────────

  static pw.Widget _notes() {
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        _sectionTitle('NOTES'),
        pw.Text(
          'This receipt confirms the payment received. Work completion does not indicate full payment unless Outstanding Amount is Rs. 0.00.',
          style: pw.TextStyle(fontSize: 9, color: _grey, height: 1.5),
        ),
      ],
    );
  }

  // ── Footer ───────────────────────────────────────────────────────────

  static pw.Widget _footer() {
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.center,
      children: [
        pw.Divider(color: _lightGrey, thickness: 1),
        pw.SizedBox(height: 8),
        pw.Text('Generated by THE SIGNAGE SURGEON App', style: pw.TextStyle(fontSize: 8.5, color: _grey)),
        pw.SizedBox(height: 2),
        pw.Text('This is a system-generated document and does not require a physical signature.',
            style: pw.TextStyle(fontSize: 8, color: _grey)),
      ],
    );
  }
}