import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

/// Generates a simple branded PDF (title + subtitle + label/value rows +
/// optional footer note) and opens the native share sheet so the customer
/// can save it, email it, or send it wherever they like.
class PdfReceiptHelper {
  static Future<void> generateAndShare({
    required String title,
    required String subtitle,
    required List<MapEntry<String, String>> rows,
    String? footerNote,
    required String filename,
  }) async {
    final doc = pw.Document();
    doc.addPage(
      pw.Page(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(32),
        build: (context) => pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Text('The Signage Surgeon',
                style: pw.TextStyle(fontSize: 20, fontWeight: pw.FontWeight.bold, color: PdfColors.blue900)),
            pw.SizedBox(height: 4),
            pw.Text(title, style: pw.TextStyle(fontSize: 16, fontWeight: pw.FontWeight.bold)),
            pw.SizedBox(height: 2),
            pw.Text(subtitle, style: const pw.TextStyle(fontSize: 10, color: PdfColors.grey700)),
            pw.SizedBox(height: 16),
            pw.Divider(color: PdfColors.grey400),
            pw.SizedBox(height: 8),
            ...rows.map(
              (e) => pw.Padding(
                padding: const pw.EdgeInsets.symmetric(vertical: 5),
                child: pw.Row(
                  mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                  children: [
                    pw.Text(e.key, style: const pw.TextStyle(fontSize: 11, color: PdfColors.grey800)),
                    pw.Text(e.value, style: pw.TextStyle(fontSize: 11, fontWeight: pw.FontWeight.bold)),
                  ],
                ),
              ),
            ),
            if (footerNote != null) ...[
              pw.SizedBox(height: 20),
              pw.Divider(color: PdfColors.grey400),
              pw.SizedBox(height: 8),
              pw.Text(footerNote, style: const pw.TextStyle(fontSize: 9, color: PdfColors.grey600)),
            ],
            pw.SizedBox(height: 24),
            pw.Text('Generated on ${DateTime.now().toString().split('.').first}',
                style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey500)),
          ],
        ),
      ),
    );
    await Printing.sharePdf(bytes: await doc.save(), filename: filename);
  }
}