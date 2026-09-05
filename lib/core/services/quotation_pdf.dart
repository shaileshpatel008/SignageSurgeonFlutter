import 'dart:typed_data';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

enum QuotationStatus { draft, sent, viewed, approved, rejected, expired, cancelled }

class MaterialItem {
  final String item;
  final String description;
  final double qty;
  final String unit;
  final double rate;
  final double amount;
  const MaterialItem({
    required this.item,
    required this.description,
    required this.qty,
    required this.unit,
    required this.rate,
    required this.amount,
  });
}

class LabourItem {
  final String description;
  final double qty;
  final double rate;
  final double amount;
  const LabourItem({
    required this.description,
    required this.qty,
    required this.rate,
    required this.amount,
  });
}

/// All optional "other charges" — pass 0 or null to omit a row entirely.
class OtherCharges {
  final double? siteVisit;
  final double? freight;
  final double? crane;
  final double? lift;
  final double? scaffolding;
  final double? equipment;
  final double? hFrameDailyRate;
  final double? transportPerKm;
  // The actual road distance for this request — required alongside
  // transportPerKm to compute the real transport charge. Without this, the
  // per-km rate alone is meaningless as a line-item total.
  final double? transportDistanceKm;

  const OtherCharges({
    this.siteVisit,
    this.freight,
    this.crane,
    this.lift,
    this.scaffolding,
    this.equipment,
    this.hFrameDailyRate,
    this.transportPerKm,
    this.transportDistanceKm,
  });

  /// The actual computed transport charge (rate × distance) — this is what
  /// should be folded into the taxable subtotal, not the raw per-km rate.
  double get transportChargeTotal {
    if ((transportPerKm ?? 0) <= 0 || (transportDistanceKm ?? 0) <= 0) return 0;
    return transportPerKm! * transportDistanceKm!;
  }

  List<MapEntry<String, double>> get rows => [
        if ((siteVisit ?? 0) > 0) MapEntry('Site Visit Charges', siteVisit!),
        if ((freight ?? 0) > 0) MapEntry('Freight Charges', freight!),
        if ((crane ?? 0) > 0) MapEntry('Crane Charges', crane!),
        if ((lift ?? 0) > 0) MapEntry('Lift Charges', lift!),
        if ((scaffolding ?? 0) > 0) MapEntry('Scaffolding Charges', scaffolding!),
        if ((equipment ?? 0) > 0) MapEntry('Equipment Charges', equipment!),
        if ((hFrameDailyRate ?? 0) > 0) MapEntry('H-Frame (Palak) — Per Day Charges', hFrameDailyRate!),
        if (transportChargeTotal > 0)
          MapEntry(
            'Transport (${transportDistanceKm!.toStringAsFixed(1)} km @ Rs.${transportPerKm!.toStringAsFixed(0)}/km)',
            transportChargeTotal,
          ),
      ];
}

enum QuotationServiceCategory { repairing, rebranding, newSignage, cleaning, amc, signShoppy }

/// Which access equipment the customer selected during booking — a
/// compulsory choice for site-visit services per the finalized Founder rule.
enum AccessEquipment { ladder, hFrame, notNeeded }

class QuotationPdfData {
  final String quotationNo;
  final String requestId;
  final String customerId;
  final DateTime date;
  final DateTime validTill;
  final QuotationStatus status;

  final String customerName;
  final String? concernPerson;
  final String? mobileNumber;
  final String? email;
  final String? siteAddress;
  final String? gstNumber;

  final QuotationServiceCategory serviceCategory;
  final String serviceType;

  final String scopeOfWork;
  final List<MaterialItem> materialItems;
  final List<LabourItem> labourItems;
  final OtherCharges otherCharges;

  // Kept separate (rather than only a combined subtotal) so the merged
  // charges/summary section can list each component individually, exactly
  // matching the in-app quotation card.
  final double serviceCharges;
  final double additionalCharges;
  final double subtotal;
  final double discount;
  final double gstPercent; // fixed at 18 per finalized business rule
  final double grandTotal;

  final String paymentTerms;
  final String? warranty;

  // Access equipment (Ladder / H-Frame / Not Needed) — only relevant for
  // site-visit services. Pass null if not applicable to this service.
  final AccessEquipment? accessEquipment;
  final double? ladderTentativePrice;
  final double? hFrameTentativePrice;
  // The ACTUAL flat equipment fee being charged (Ladder or H-Frame), set by
  // the global app_settings/pricing_config.ladderEquipmentFee /
  // hFrameEquipmentFee — separate from the transport charge, and separate
  // from the tentative-price fields above (which are informational only).
  final double equipmentFee;

  // Optional brand assets — pass raw image bytes (PNG recommended).
  final Uint8List? logoBytes;
  final Uint8List? mascotBytes;
  final Uint8List? qrCodeBytes;

  const QuotationPdfData({
    required this.quotationNo,
    required this.requestId,
    required this.customerId,
    required this.date,
    required this.validTill,
    required this.status,
    required this.customerName,
    this.concernPerson,
    this.mobileNumber,
    this.email,
    this.siteAddress,
    this.gstNumber,
    required this.serviceCategory,
    required this.serviceType,
    required this.scopeOfWork,
    this.materialItems = const [],
    this.labourItems = const [],
    this.otherCharges = const OtherCharges(),
    this.serviceCharges = 0,
    this.additionalCharges = 0,
    required this.subtotal,
    required this.discount,
    this.gstPercent = 18,
    required this.grandTotal,
    required this.paymentTerms,
    this.warranty,
    this.accessEquipment,
    this.ladderTentativePrice,
    this.hFrameTentativePrice,
    this.equipmentFee = 0,
    this.logoBytes,
    this.mascotBytes,
    this.qrCodeBytes,
  });

  /// True once `validTill` has passed and the quotation was never approved.
  /// Callers should treat this as authoritative over a stale `status` value
  /// that hasn't been refreshed since expiry.
  bool get isExpiredNow =>
      DateTime.now().isAfter(validTill) &&
      status != QuotationStatus.approved &&
      status != QuotationStatus.rejected &&
      status != QuotationStatus.cancelled;

  double get gstAmount => (subtotal - discount) * (gstPercent / 100);
  double get cgstAmount => gstAmount / 2;
  double get sgstAmount => gstAmount / 2;
}

class QuotationPdf {
  static const PdfColor _red = PdfColor.fromInt(0xFFE2000F);
  static const PdfColor _black = PdfColors.black;
  static const PdfColor _grey = PdfColor.fromInt(0xFF6B7280);
  static const PdfColor _lightGrey = PdfColor.fromInt(0xFFE5E7EB);
  static const PdfColor _greyCard = PdfColor.fromInt(0xFFF6F7F8);
  static const PdfColor _draftBg = PdfColor.fromInt(0xFFF1F2F4);
  static const PdfColor _sentBg = PdfColor.fromInt(0xFFEFF4FF);
  static const PdfColor _sentFg = PdfColor.fromInt(0xFF3B5BDB);
  static const PdfColor _approvedBg = PdfColor.fromInt(0xFFE8F8EE);
  static const PdfColor _approvedFg = PdfColor.fromInt(0xFF16A34A);
  static const PdfColor _rejectedBg = PdfColor.fromInt(0xFFFDE8E9);
  static const PdfColor _amberBg = PdfColor.fromInt(0xFFFFF6E5);
  static const PdfColor _amberFg = PdfColor.fromInt(0xFFB45309);

  /// Strips anything unsafe for a file path — a slash in an admin-entered
  /// quotation number (e.g. "QAh/01") was silently crashing the share step
  /// on Android, since it got read as a non-existent subfolder.
  static String _sanitizeFilename(String input) {
    final cleaned = input.replaceAll(RegExp(r'[^A-Za-z0-9_-]'), '_');
    return cleaned.isEmpty ? 'Document' : cleaned;
  }

  static Future<void> generateAndShare(QuotationPdfData rawData) async {
    // Expiry is derived at generation time, not trusted from a possibly
    // stale `status` value the caller passed in.
    final d = rawData.isExpiredNow
        ? QuotationPdfData(
            quotationNo: rawData.quotationNo, requestId: rawData.requestId, customerId: rawData.customerId,
            date: rawData.date, validTill: rawData.validTill, status: QuotationStatus.expired,
            customerName: rawData.customerName, concernPerson: rawData.concernPerson, mobileNumber: rawData.mobileNumber,
            email: rawData.email, siteAddress: rawData.siteAddress, gstNumber: rawData.gstNumber,
            serviceCategory: rawData.serviceCategory, serviceType: rawData.serviceType, scopeOfWork: rawData.scopeOfWork,
            materialItems: rawData.materialItems, labourItems: rawData.labourItems, otherCharges: rawData.otherCharges,
            serviceCharges: rawData.serviceCharges, additionalCharges: rawData.additionalCharges,
            subtotal: rawData.subtotal, discount: rawData.discount, gstPercent: rawData.gstPercent, grandTotal: rawData.grandTotal,
            paymentTerms: rawData.paymentTerms, warranty: rawData.warranty, accessEquipment: rawData.accessEquipment,
            ladderTentativePrice: rawData.ladderTentativePrice, hFrameTentativePrice: rawData.hFrameTentativePrice,
            equipmentFee: rawData.equipmentFee,
            logoBytes: rawData.logoBytes, mascotBytes: rawData.mascotBytes, qrCodeBytes: rawData.qrCodeBytes,
          )
        : rawData;

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
                  child: pw.Text('THE SIGNAGE SURGEON',
                      style: pw.TextStyle(fontSize: 50, fontWeight: pw.FontWeight.bold, color: _black)),
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
              _customerDetails(d),
              _divider(),
              _serviceDetails(d),
              _divider(),
              _scopeOfWork(d),
              _divider(),
              if (d.accessEquipment != null) ...[_accessEquipmentSection(d), _divider()],
              if (d.materialItems.isNotEmpty) ...[_materialTable(d), _divider()],
              if (d.labourItems.isNotEmpty) ...[_labourTable(d), _divider()],
              _chargesAndSummary(d),
              pw.SizedBox(height: 14),
              _paymentTerms(d),
              pw.SizedBox(height: 14),
              _bankDetailsAndQr(d),
              pw.SizedBox(height: 14),
              _acceptanceNote(),
              pw.SizedBox(height: 14),
              _authorizedSignatory(),
              pw.SizedBox(height: 14),
              _termsAndConditions(d),
              pw.SizedBox(height: 20),
              _footer(),
            ],
          ),
        ],
      ),
    );

    await Printing.sharePdf(bytes: await doc.save(), filename: 'Quotation_${_sanitizeFilename(d.quotationNo)}.pdf');
  }

  // ── Header ───────────────────────────────────────────────────────────

  static pw.Widget _header(QuotationPdfData d) {
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
            pw.Text('QUOTATION', style: pw.TextStyle(fontSize: 13, fontWeight: pw.FontWeight.bold, color: _red, letterSpacing: 1)),
            pw.SizedBox(height: 6),
            _miniKv('Quotation No.', d.quotationNo),
            _miniKv('Request ID', d.requestId),
            _miniKv('Customer ID', d.customerId),
            _miniKv('Date', _fmtDate(d.date)),
            _miniKv('Quotation Valid Till', '${_fmtDate(d.validTill)} (7 Days)'),
            pw.SizedBox(height: 6),
            _statusBadge(d.status),
          ],
        ),
      ],
    );
  }

  static pw.Widget _miniKv(String label, String value) {
    return pw.Padding(
      padding: const pw.EdgeInsets.only(bottom: 2),
      child: pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.end,
        children: [
          pw.Text('$label: ', style: pw.TextStyle(fontSize: 8, color: _grey)),
          pw.Text(value, style: pw.TextStyle(fontSize: 8.5, color: _black, fontWeight: pw.FontWeight.bold)),
        ],
      ),
    );
  }

  static pw.Widget _statusBadge(QuotationStatus status) {
    late String label;
    late PdfColor bg, fg;
    switch (status) {
      case QuotationStatus.draft:
        label = 'DRAFT'; bg = _draftBg; fg = _grey;
        break;
      case QuotationStatus.sent:
        label = 'SENT'; bg = _sentBg; fg = _sentFg;
        break;
      case QuotationStatus.viewed:
        label = 'VIEWED'; bg = _sentBg; fg = _sentFg;
        break;
      case QuotationStatus.approved:
        label = 'APPROVED'; bg = _approvedBg; fg = _approvedFg;
        break;
      case QuotationStatus.rejected:
        label = 'REJECTED'; bg = _rejectedBg; fg = _red;
        break;
      case QuotationStatus.expired:
        label = 'EXPIRED'; bg = _amberBg; fg = _amberFg;
        break;
      case QuotationStatus.cancelled:
        label = 'CANCELLED'; bg = _draftBg; fg = _grey;
        break;
    }
    return pw.Container(
      padding: const pw.EdgeInsets.symmetric(horizontal: 12, vertical: 5),
      decoration: pw.BoxDecoration(color: bg, borderRadius: pw.BorderRadius.circular(6), border: pw.Border.all(color: _red, width: 0.75)),
      child: pw.Text(label, style: pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold, color: fg)),
    );
  }

  // ── Shared helpers ────────────────────────────────────────────────────

  static pw.Widget _divider() => pw.Padding(
        padding: const pw.EdgeInsets.symmetric(vertical: 10),
        child: pw.Divider(color: _lightGrey, thickness: 1),
      );

  static pw.Widget _sectionTitle(String title) => pw.Padding(
        padding: const pw.EdgeInsets.only(bottom: 8),
        child: pw.Text(title, style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold, color: _red, letterSpacing: 0.8)),
      );

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

  static pw.Widget _kvGrid(List<MapEntry<String, String>> rows, {int columns = 2}) {
    final filtered = rows.where((r) => r.value.trim().isNotEmpty).toList();
    if (filtered.isEmpty) return pw.SizedBox();
    final chunks = <List<MapEntry<String, String>>>[];
    for (var i = 0; i < filtered.length; i += columns) {
      chunks.add(filtered.sublist(i, i + columns > filtered.length ? filtered.length : i + columns));
    }
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: chunks.map((chunk) {
        return pw.Padding(
          padding: const pw.EdgeInsets.only(bottom: 6),
          child: pw.Row(
            children: chunk.map((e) => pw.Expanded(child: _kv(e.key, e.value))).toList()
              ..addAll(List.generate(columns - chunk.length, (_) => pw.Expanded(child: pw.SizedBox()))),
          ),
        );
      }).toList(),
    );
  }

  static String _fmtDate(DateTime dt) {
    const months = ['Jan','Feb','Mar','Apr','May','Jun','Jul','Aug','Sep','Oct','Nov','Dec'];
    return '${dt.day} ${months[dt.month - 1]} ${dt.year}';
  }

  static String _categoryLabel(QuotationServiceCategory c) {
    switch (c) {
      case QuotationServiceCategory.repairing: return 'Repairing';
      case QuotationServiceCategory.rebranding: return 'Rebranding';
      case QuotationServiceCategory.newSignage: return 'New Signage';
      case QuotationServiceCategory.cleaning: return 'Signage Cleaning';
      case QuotationServiceCategory.amc: return 'AMC';
      case QuotationServiceCategory.signShoppy: return 'Sign Shoppy';
    }
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

  // ── Customer / Service ───────────────────────────────────────────────

  static pw.Widget _customerDetails(QuotationPdfData d) {
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        _sectionTitle('CUSTOMER DETAILS'),
        _kvGrid([
          MapEntry('Customer Name', d.customerName),
          MapEntry('Concern Person', d.concernPerson ?? ''),
          MapEntry('Mobile Number', d.mobileNumber ?? ''),
          MapEntry('Email', d.email ?? ''),
          MapEntry('Site Address', d.siteAddress ?? ''),
          MapEntry('GST Number', d.gstNumber ?? ''),
        ], columns: 2),
      ],
    );
  }

  static pw.Widget _serviceDetails(QuotationPdfData d) {
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

  // ── Scope of Work ────────────────────────────────────────────────────

  static pw.Widget _scopeOfWork(QuotationPdfData d) {
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        _sectionTitle('SCOPE OF WORK'),
        pw.Container(
          width: double.infinity,
          padding: const pw.EdgeInsets.all(12),
          decoration: pw.BoxDecoration(color: _greyCard, borderRadius: pw.BorderRadius.circular(8)),
          child: pw.Text(
            d.scopeOfWork,
            softWrap: true,
            style: pw.TextStyle(fontSize: 9.5, color: _black, height: 1.6),
          ),
        ),
      ],
    );
  }

  // ── Access Equipment (Ladder / H-Frame / Not Needed) ────────────────

  static pw.Widget _accessEquipmentSection(QuotationPdfData d) {
    String label;
    switch (d.accessEquipment!) {
      case AccessEquipment.ladder:
        label = 'Ladder';
        break;
      case AccessEquipment.hFrame:
        label = 'H-Frame (Palak)';
        break;
      case AccessEquipment.notNeeded:
        label = 'Not Needed';
        break;
    }

    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        _sectionTitle('ACCESS EQUIPMENT'),
        _kv('Customer Selection', label),
        pw.SizedBox(height: 6),
        if (d.ladderTentativePrice != null || d.hFrameTentativePrice != null)
          _kvGrid([
            if (d.ladderTentativePrice != null) MapEntry('Ladder (Tentative)', 'Rs. ${d.ladderTentativePrice!.toStringAsFixed(2)}'),
            if (d.hFrameTentativePrice != null) MapEntry('H-Frame (Tentative)', 'Rs. ${d.hFrameTentativePrice!.toStringAsFixed(2)}'),
          ], columns: 2),
        if (d.accessEquipment == AccessEquipment.notNeeded) ...[
          pw.SizedBox(height: 6),
          pw.Container(
            width: double.infinity,
            padding: const pw.EdgeInsets.all(8),
            decoration: pw.BoxDecoration(color: _amberBg, borderRadius: pw.BorderRadius.circular(6)),
            child: pw.Text(
              'No access equipment was arranged for this visit. On arrival, the team will wait up to 30 minutes for the '
              'customer to arrange suitable equipment on-site. If arranged, additional charges will apply. If the customer '
              'is unable or unwilling to arrange it, the visit cannot proceed and no refund shall be applicable.',
              style: pw.TextStyle(fontSize: 7.5, color: _black, height: 1.35),
              softWrap: true,
            ),
          ),
        ],
      ],
    );
  }

  // ── Material Table ───────────────────────────────────────────────────

  static pw.Widget _materialTable(QuotationPdfData d) {
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        _sectionTitle('MATERIAL'),
        pw.Table(
          border: pw.TableBorder.all(color: _lightGrey, width: 0.75),
          columnWidths: const {
            0: pw.FlexColumnWidth(1.4),
            1: pw.FlexColumnWidth(2.4),
            2: pw.FlexColumnWidth(0.8),
            3: pw.FlexColumnWidth(0.8),
            4: pw.FlexColumnWidth(1.1),
            5: pw.FlexColumnWidth(1.2),
          },
          children: [
            _tableHeaderRow(['Item', 'Description', 'Qty', 'Unit', 'Rate', 'Amount']),
            ...d.materialItems.map((m) => _tableRow([
                  m.item,
                  m.description,
                  m.qty.toStringAsFixed(m.qty % 1 == 0 ? 0 : 2),
                  m.unit,
                  m.rate.toStringAsFixed(2),
                  m.amount.toStringAsFixed(2),
                ])),
          ],
        ),
      ],
    );
  }

  // ── Labour Table ──────────────────────────────────────────────────────

  static pw.Widget _labourTable(QuotationPdfData d) {
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        _sectionTitle('LABOUR'),
        pw.Table(
          border: pw.TableBorder.all(color: _lightGrey, width: 0.75),
          columnWidths: const {
            0: pw.FlexColumnWidth(3),
            1: pw.FlexColumnWidth(1),
            2: pw.FlexColumnWidth(1.2),
            3: pw.FlexColumnWidth(1.3),
          },
          children: [
            _tableHeaderRow(['Description', 'Qty', 'Rate', 'Amount']),
            ...d.labourItems.map((l) => _tableRow([
                  l.description,
                  l.qty.toStringAsFixed(l.qty % 1 == 0 ? 0 : 2),
                  l.rate.toStringAsFixed(2),
                  l.amount.toStringAsFixed(2),
                ])),
          ],
        ),
      ],
    );
  }

  static pw.TableRow _tableHeaderRow(List<String> headers) {
    return pw.TableRow(
      decoration: const pw.BoxDecoration(color: PdfColor.fromInt(0xFFF6F7F8)),
      children: headers
          .map((h) => pw.Padding(
                padding: const pw.EdgeInsets.symmetric(horizontal: 6, vertical: 6),
                child: pw.Text(h, style: pw.TextStyle(fontSize: 8, fontWeight: pw.FontWeight.bold, color: _black)),
              ))
          .toList(),
    );
  }

  static pw.TableRow _tableRow(List<String> cells) {
    return pw.TableRow(
      children: cells
          .map((c) => pw.Padding(
                padding: const pw.EdgeInsets.symmetric(horizontal: 6, vertical: 6),
                child: pw.Text(c, softWrap: true, style: const pw.TextStyle(fontSize: 8.5)),
              ))
          .toList(),
    );
  }

  // ── Other Charges ─────────────────────────────────────────────────────

  static pw.Widget _chargesAndSummary(QuotationPdfData d) {
    pw.Widget row(String label, double amount, {bool bold = false, bool negative = false}) {
      return pw.Padding(
        padding: const pw.EdgeInsets.symmetric(vertical: 4),
        child: pw.Row(
          mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
          children: [
            pw.Text(label, style: pw.TextStyle(fontSize: bold ? 10.5 : 9.5, color: bold ? _black : _grey, fontWeight: bold ? pw.FontWeight.bold : pw.FontWeight.normal)),
            pw.Text('${negative ? '- ' : ''}Rs. ${amount.toStringAsFixed(2)}', style: pw.TextStyle(fontSize: bold ? 11 : 9.5, color: bold ? _red : _black, fontWeight: bold ? pw.FontWeight.bold : pw.FontWeight.normal)),
          ],
        ),
      );
    }

    // Named charges (site visit/freight/crane/lift/scaffolding/equipment/
    // hFrameDailyRate) — everything EXCEPT transport, which gets its own
    // clearly-labelled row below, matching the app's quotation card order.
    final namedCharges = d.otherCharges.rows.where((r) => !r.key.startsWith('Transport')).toList();

    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.stretch,
      children: [
        _sectionTitle('PAYMENT'),
        if (d.serviceCharges > 0) row('Service Charges', d.serviceCharges),
        if (d.additionalCharges > 0) row('Additional Charges', d.additionalCharges),
        ...namedCharges.map((r) => row(r.key, r.value)),
        if (d.equipmentFee > 0)
          row(
            d.accessEquipment == AccessEquipment.hFrame ? 'H-Frame Equipment Fee' : 'Ladder Equipment Fee',
            d.equipmentFee,
          ),
        if (d.otherCharges.transportChargeTotal > 0)
          row(
            'Equipment Transport (${d.otherCharges.transportDistanceKm!.toStringAsFixed(1)} km @ Rs.${d.otherCharges.transportPerKm!.toStringAsFixed(0)}/km)',
            d.otherCharges.transportChargeTotal,
          ),
        if (d.discount > 0) row('Discount', d.discount, negative: true),
        row('GST @${d.gstPercent.toStringAsFixed(0)}%', d.gstAmount),
        pw.SizedBox(height: 10),
        pw.Container(
          padding: const pw.EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: pw.BoxDecoration(color: _red, borderRadius: pw.BorderRadius.circular(8)),
          child: pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
            children: [
              pw.Text('GRAND TOTAL', style: pw.TextStyle(fontSize: 12, fontWeight: pw.FontWeight.bold, color: PdfColors.white, letterSpacing: 0.5)),
              pw.Text('Rs. ${d.grandTotal.toStringAsFixed(2)}', style: pw.TextStyle(fontSize: 14, fontWeight: pw.FontWeight.bold, color: PdfColors.white)),
            ],
          ),
        ),
      ],
    );
  }

  // ── Payment Terms ─────────────────────────────────────────────────────

  static pw.Widget _paymentTerms(QuotationPdfData d) {
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        _sectionTitle('PAYMENT TERMS'),
        pw.Text(d.paymentTerms, softWrap: true, style: const pw.TextStyle(fontSize: 9.5, color: _black)),
      ],
    );
  }

  // ── Bank Details + QR (real image if provided, placeholder otherwise) ──

  static pw.Widget _bankDetailsAndQr(QuotationPdfData d) {
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

  // ── Customer Acceptance ───────────────────────────────────────────────

  static pw.Widget _acceptanceNote() {
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        _sectionTitle('CUSTOMER ACCEPTANCE'),
        pw.Text(
          'This quotation is accepted digitally by tapping "ACCEPT & PAY" in the app. Payment success is the sole '
          'confirmation of acceptance. No physical signature, separate OTP approval, or separate acceptance step is required.',
          softWrap: true,
          style: pw.TextStyle(fontSize: 9, color: _grey, height: 1.5),
        ),
      ],
    );
  }

  // ── Authorized Signatory ─────────────────────────────────────────────

  static pw.Widget _authorizedSignatory() {
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        _sectionTitle('AUTHORIZED SIGNATORY'),
        pw.Text('Concept3 The Design Workshop', style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold, color: _black)),
        pw.Text('(Operating Brand: THE SIGNAGE SURGEON)', style: pw.TextStyle(fontSize: 8.5, color: _grey)),
      ],
    );
  }

  // ── Terms & Conditions — wording tightened to match the finalized text ──

  static String _categorySpecificTerm(QuotationServiceCategory c) {
    switch (c) {
      case QuotationServiceCategory.repairing:
        return 'Repairing: Hidden or internal defects discovered during repair may require a revised quotation.';
      case QuotationServiceCategory.rebranding:
        return 'Rebranding: Customer-approved artwork will be treated as final.';
      case QuotationServiceCategory.newSignage:
        return 'New Signage: Civil/structural work is excluded unless specifically mentioned.';
      case QuotationServiceCategory.cleaning:
        return 'Signage Cleaning: Any weak, damaged, broken, loose, cracked or deteriorated signage/parts that break '
            'or get damaged during the cleaning process shall not be the responsibility of The Signage Surgeon.';
      case QuotationServiceCategory.amc:
        return 'AMC: Only services covered under the selected AMC plan are included. Spare parts/consumables are '
            'chargeable unless specifically included.';
      case QuotationServiceCategory.signShoppy:
        return 'Sign Shoppy: Any delay caused by freight, courier or transportation services shall not be the '
            'responsibility of The Signage Surgeon.';
    }
  }

  static pw.Widget _termsAndConditions(QuotationPdfData d) {
    final terms = <String>[
      'Quotation validity: 7 days from the date of issue.',
      'Advance payment is required before work initiation.',
      'Additional work outside the approved scope requires customer approval.',
      'GST @18% applicable (CGST 9% + SGST 9%, or applicable IGST treatment where required).',
      _categorySpecificTerm(d.serviceCategory),
      'Cancellation after technician assignment may attract applicable charges as per the approved cancellation policy.',
      'Refunds shall be handled according to the finalized The Signage Surgeon Refund Policy.',
      if (d.warranty != null && d.warranty!.trim().isNotEmpty) 'Warranty: ${d.warranty}',
    ];

    return pw.Container(
      width: double.infinity,
      padding: const pw.EdgeInsets.all(14),
      decoration: pw.BoxDecoration(color: _greyCard, borderRadius: pw.BorderRadius.circular(8)),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Text('TERMS & CONDITIONS', style: pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold, color: _red, letterSpacing: 0.6)),
          pw.SizedBox(height: 8),
          ...terms.map((t) => pw.Padding(
                padding: const pw.EdgeInsets.only(bottom: 5),
                child: pw.Row(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    pw.Text('-  ', style: pw.TextStyle(fontSize: 8.5, color: _grey, fontWeight: pw.FontWeight.bold)),
                    pw.Expanded(child: pw.Text(t, softWrap: true, style: pw.TextStyle(fontSize: 8.5, color: _grey, height: 1.4))),
                  ],
                ),
              )),
        ],
      ),
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