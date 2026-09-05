import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../../../core/theme/app_theme.dart';

class ReportProblemScreen extends StatefulWidget {
  final String collection; // e.g. "repair_requests"
  final String requestId;
  final String serviceLabel; // e.g. "Repairing — Directional Signage", for display only

  const ReportProblemScreen({
    super.key,
    required this.collection,
    required this.requestId,
    required this.serviceLabel,
  });

  @override
  State<ReportProblemScreen> createState() => _ReportProblemScreenState();
}

class _ReportProblemScreenState extends State<ReportProblemScreen> {
  final _descriptionController = TextEditingController();
  bool _submitting = false;

  @override
  void dispose() {
    _descriptionController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_descriptionController.text.trim().isEmpty) {
      _showSnack('Please describe the problem before submitting.');
      return;
    }
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    setState(() => _submitting = true);
    try {
      await FirebaseFirestore.instance.collection('support_tickets').add({
        'requestId': widget.requestId,
        'serviceCollection': widget.collection,
        'userId': user.uid,
        'description': _descriptionController.text.trim(),
        'status': 'open',
        'adminResponse': null,
        'createdAt': FieldValue.serverTimestamp(),
      });
      if (mounted) {
        Navigator.pop(context);
        _showSnack('Your issue has been submitted. We\'ll get back to you here shortly.');
      }
    } catch (e) {
      _showSnack('Could not submit your issue: $e');
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  void _showSnack(String message) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.offWhite,
      appBar: AppBar(
        backgroundColor: AppColors.offWhite,
        elevation: 0,
        centerTitle: true,
        leading: GestureDetector(
          onTap: () => Navigator.pop(context),
          child: Container(
            margin: const EdgeInsets.all(10),
            decoration: BoxDecoration(color: AppColors.white, borderRadius: BorderRadius.circular(10), border: Border.all(color: AppColors.cardBorder)),
            child: const Icon(Icons.arrow_back_ios_new_rounded, color: AppColors.navy, size: 16),
          ),
        ),
        title: const Text('Report a Problem', style: TextStyle(color: AppColors.navy, fontSize: 17, fontWeight: FontWeight.w700)),
      ),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(color: AppColors.white, borderRadius: BorderRadius.circular(12), border: Border.all(color: AppColors.cardBorder)),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Request', style: TextStyle(color: AppColors.grey, fontSize: 11.5)),
                const SizedBox(height: 4),
                Text(widget.serviceLabel, style: const TextStyle(color: AppColors.navy, fontSize: 14.5, fontWeight: FontWeight.w700)),
              ],
            ),
          ),
          const SizedBox(height: 20),
          const Text('What went wrong?', style: TextStyle(color: AppColors.navy, fontSize: 13.5, fontWeight: FontWeight.w700)),
          const SizedBox(height: 10),
          TextField(
            controller: _descriptionController,
            maxLines: 6,
            decoration: InputDecoration(
              hintText: 'Describe the issue you\'re facing with this completed service...',
              filled: true,
              fillColor: AppColors.white,
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: AppColors.cardBorder)),
              enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: AppColors.cardBorder)),
              focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: AppColors.yellowDark)),
              contentPadding: const EdgeInsets.all(14),
            ),
          ),
          const SizedBox(height: 8),
          const Text(
            'Our team will review your issue and respond here — this could mean sending a technician back out, or '
            'a written response. You can track the status of this from "My Support Tickets" in your Account.',
            style: TextStyle(color: AppColors.grey, fontSize: 11.5, height: 1.4),
          ),
          const SizedBox(height: 28),
          SizedBox(
            width: double.infinity,
            height: 52,
            child: ElevatedButton(
              onPressed: _submitting ? null : _submit,
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.yellow,
                foregroundColor: AppColors.navy,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                elevation: 0,
              ),
              child: _submitting
                  ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.navy))
                  : const Text('Submit', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 14.5)),
            ),
          ),
        ],
      ),
    );
  }
}