import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/constants/app_routes.dart';

class ProfileSetupScreen extends StatefulWidget {
  const ProfileSetupScreen({super.key});

  @override
  State<ProfileSetupScreen> createState() => _ProfileSetupScreenState();
}

class _ProfileSetupScreenState extends State<ProfileSetupScreen> {
  final _formKey = GlobalKey<FormState>();

  final _fullNameController = TextEditingController();
  final _emailController = TextEditingController();
  final _businessNameController = TextEditingController();
  final _designationController = TextEditingController();
  final _addressController = TextEditingController();
  final _gstController = TextEditingController();

  String? _selectedCategory;
  String _mobileNumber = '';
  bool _isSaving = false;

  // Light input fill, sits inside white cards / on the off-white background.
  static const Color _inputBg = Color(0xFFF7F8FA);

  static const List<String> _businessCategories = [
    'Retail Shop',
    'Restaurant / Food & Beverage',
    'Hotel / Hospitality',
    'Hospital / Clinic',
    'Education / Institute',
    'Real Estate',
    'Automobile',
    'Salon / Beauty',
    'Pharma / Medical Store',
    'Corporate / Office',
    'Mall / Commercial Complex',
    'Other',
  ];

  @override
  void initState() {
    super.initState();
    _loadMobileNumber();
  }

  void _loadMobileNumber() {
    final user = FirebaseAuth.instance.currentUser;
    if (user != null && user.phoneNumber != null) {
      // Strip +91 prefix for display
      final phone = user.phoneNumber!;
      setState(() {
        _mobileNumber = phone.startsWith('+91')
            ? phone.substring(3)
            : phone;
      });
    }
  }

  @override
  void dispose() {
    _fullNameController.dispose();
    _emailController.dispose();
    _businessNameController.dispose();
    _designationController.dispose();
    _addressController.dispose();
    _gstController.dispose();
    super.dispose();
  }

  Future<void> _saveProfile() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isSaving = true);

    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) return;

      await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .set({
        'fullName': _fullNameController.text.trim(),
        'name': _fullNameController.text.trim(), // for home screen greeting
        'phone': user.phoneNumber ?? '',
        'email': _emailController.text.trim(),
        'businessName': _businessNameController.text.trim(),
        'businessCategory': _selectedCategory ?? '',
        'designation': _designationController.text.trim(),
        'address': _addressController.text.trim(),
        'gstNumber': _gstController.text.trim(),
        'city': 'Ahmedabad', // default until GPS is added
        'profileComplete': true,
        'createdAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

      if (mounted) {
        Navigator.pushReplacementNamed(context, AppRoutes.home);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to save profile: $e'),
            backgroundColor: AppColors.red,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.dark,
      child: Scaffold(
        backgroundColor: AppColors.offWhite,
        body: SafeArea(
          child: Column(
            children: [
              _buildHeader(),
              Expanded(
                child: SingleChildScrollView(
                  physics: const BouncingScrollPhysics(),
                  padding: const EdgeInsets.fromLTRB(20, 24, 20, 40),
                  child: Form(
                    key: _formKey,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // ── PERSONAL INFO SECTION ──
                        _sectionLabel('Personal Info'),
                        const SizedBox(height: 14),
                        _buildField(
                          controller: _fullNameController,
                          label: 'Full Name',
                          hint: 'Enter your full name',
                          icon: Icons.person_outline,
                          required: true,
                          validator: (v) => (v == null || v.trim().isEmpty)
                              ? 'Full name is required'
                              : null,
                        ),
                        const SizedBox(height: 14),
                        _buildMobileField(),
                        const SizedBox(height: 14),
                        _buildField(
                          controller: _emailController,
                          label: 'Email Address',
                          hint: 'Enter your email (optional)',
                          icon: Icons.mail_outline,
                          required: false,
                          keyboardType: TextInputType.emailAddress,
                          validator: (v) {
                            if (v == null || v.trim().isEmpty) return null;
                            final emailRegex = RegExp(
                                r'^[\w-\.]+@([\w-]+\.)+[\w-]{2,4}$');
                            if (!emailRegex.hasMatch(v.trim())) {
                              return 'Enter a valid email address';
                            }
                            return null;
                          },
                        ),

                        const SizedBox(height: 28),

                        // ── BUSINESS INFO SECTION ──
                        _sectionLabel('Business Info'),
                        const SizedBox(height: 14),
                        _buildField(
                          controller: _businessNameController,
                          label: 'Business Name',
                          hint: 'Enter your business name',
                          icon: Icons.store_outlined,
                          required: true,
                          validator: (v) => (v == null || v.trim().isEmpty)
                              ? 'Business name is required'
                              : null,
                        ),
                        const SizedBox(height: 14),
                        _buildCategoryDropdown(),
                        const SizedBox(height: 14),
                        _buildField(
                          controller: _designationController,
                          label: 'Designation',
                          hint: 'e.g. Owner, Manager, Director',
                          icon: Icons.badge_outlined,
                          required: true,
                          validator: (v) => (v == null || v.trim().isEmpty)
                              ? 'Designation is required'
                              : null,
                        ),

                        const SizedBox(height: 28),

                        // ── LOCATION SECTION ──
                        _sectionLabel('Location'),
                        const SizedBox(height: 14),
                        _buildField(
                          controller: _addressController,
                          label: 'Address',
                          hint: 'Shop / Office address',
                          icon: Icons.location_on_outlined,
                          required: true,
                          maxLines: 3,
                          validator: (v) => (v == null || v.trim().isEmpty)
                              ? 'Address is required'
                              : null,
                        ),
                        const SizedBox(height: 14),
                        _buildGoogleLocationPlaceholder(),

                        const SizedBox(height: 28),

                        // ── OTHER SECTION ──
                        _sectionLabel('Other Details'),
                        const SizedBox(height: 14),
                        _buildField(
                          controller: _gstController,
                          label: 'GST Number',
                          hint: 'Enter GST number (optional)',
                          icon: Icons.receipt_outlined,
                          required: false,
                          inputFormatters: [
                            UpperCaseTextFormatter(),
                            LengthLimitingTextInputFormatter(15),
                          ],
                          validator: (v) {
                            if (v == null || v.trim().isEmpty) return null;
                            final gstRegex = RegExp(
                                r'^[0-9]{2}[A-Z]{5}[0-9]{4}[A-Z]{1}[1-9A-Z]{1}Z[0-9A-Z]{1}$');
                            if (!gstRegex.hasMatch(v.trim())) {
                              return 'Enter a valid 15-digit GST number';
                            }
                            return null;
                          },
                        ),

                        const SizedBox(height: 36),

                        // ── SAVE BUTTON ──
                        SizedBox(
                          width: double.infinity,
                          height: 54,
                          child: ElevatedButton(
                            onPressed: _isSaving ? null : _saveProfile,
                            style: ElevatedButton.styleFrom(
                              backgroundColor: AppColors.yellow,
                              foregroundColor: AppColors.navy,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(14),
                              ),
                              elevation: 0,
                            ),
                            child: _isSaving
                                ? const SizedBox(
                                    width: 22,
                                    height: 22,
                                    child: CircularProgressIndicator(
                                      color: AppColors.navy,
                                      strokeWidth: 2.5,
                                    ),
                                  )
                                : const Text(
                                    'SAVE & CONTINUE',
                                    style: TextStyle(
                                      fontSize: 15,
                                      fontWeight: FontWeight.bold,
                                      letterSpacing: 1,
                                      color: AppColors.navy,
                                    ),
                                  ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ─── HEADER ─────────────────────────────────────────────────────────────────

  Widget _buildHeader() {
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 18),
      decoration: BoxDecoration(
        color: AppColors.white,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: AppColors.yellow.withOpacity(0.18),
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Icon(
              Icons.person_add_alt_1_outlined,
              color: AppColors.yellowDark,
              size: 22,
            ),
          ),
          const SizedBox(width: 14),
          const Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Complete Your Profile',
                style: TextStyle(
                  color: AppColors.navy,
                  fontSize: 17,
                  fontWeight: FontWeight.bold,
                ),
              ),
              SizedBox(height: 2),
              Text(
                'This helps us serve you better',
                style: TextStyle(color: AppColors.grey, fontSize: 12),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // ─── SECTION LABEL ──────────────────────────────────────────────────────────

  Widget _sectionLabel(String title) {
    return Row(
      children: [
        Container(
          width: 3,
          height: 16,
          decoration: BoxDecoration(
            color: AppColors.yellow,
            borderRadius: BorderRadius.circular(2),
          ),
        ),
        const SizedBox(width: 8),
        Text(
          title,
          style: const TextStyle(
            color: AppColors.navy,
            fontSize: 14,
            fontWeight: FontWeight.w700,
            letterSpacing: 0.5,
          ),
        ),
      ],
    );
  }

  // ─── GENERIC FIELD ──────────────────────────────────────────────────────────

  Widget _buildField({
    required TextEditingController controller,
    required String label,
    required String hint,
    required IconData icon,
    required bool required,
    TextInputType keyboardType = TextInputType.text,
    int maxLines = 1,
    List<TextInputFormatter>? inputFormatters,
    String? Function(String?)? validator,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _fieldLabel(label, required: required),
        const SizedBox(height: 6),
        TextFormField(
          controller: controller,
          keyboardType: keyboardType,
          maxLines: maxLines,
          inputFormatters: inputFormatters,
          style: const TextStyle(color: AppColors.navy, fontSize: 14),
          validator: validator,
          decoration: InputDecoration(
            hintText: hint,
            hintStyle: const TextStyle(color: AppColors.grey, fontSize: 13),
            filled: true,
            fillColor: _inputBg,
            prefixIcon: Icon(icon, color: AppColors.grey, size: 20),
            contentPadding: const EdgeInsets.symmetric(
                horizontal: 16, vertical: 14),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide.none,
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide.none,
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide:
                  const BorderSide(color: AppColors.yellow, width: 1.5),
            ),
            errorBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide:
                  const BorderSide(color: AppColors.red, width: 1),
            ),
            focusedErrorBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide:
                  const BorderSide(color: AppColors.red, width: 1.5),
            ),
            errorStyle: const TextStyle(color: AppColors.red, fontSize: 11),
          ),
        ),
      ],
    );
  }

  // ─── MOBILE FIELD (locked) ───────────────────────────────────────────────────

  Widget _buildMobileField() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _fieldLabel('Mobile Number', required: true),
        const SizedBox(height: 6),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          decoration: BoxDecoration(
            color: _inputBg,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(
            children: [
              const Icon(Icons.phone_outlined,
                  color: AppColors.grey, size: 20),
              const SizedBox(width: 12),
              Text(
                '+91 $_mobileNumber',
                style: const TextStyle(
                  color: AppColors.navy,
                  fontSize: 14,
                ),
              ),
              const Spacer(),
              Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: AppColors.yellow.withOpacity(0.18),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: const Text(
                  'VERIFIED',
                  style: TextStyle(
                    color: AppColors.yellowDark,
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 0.5,
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 4),
        const Padding(
          padding: EdgeInsets.only(left: 4),
          child: Text(
            'Number can be changed from Profile settings',
            style: TextStyle(color: AppColors.grey, fontSize: 11),
          ),
        ),
      ],
    );
  }

  // ─── CATEGORY DROPDOWN ──────────────────────────────────────────────────────

  Widget _buildCategoryDropdown() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _fieldLabel('Business Category', required: true),
        const SizedBox(height: 6),
        DropdownButtonFormField<String>(
          value: _selectedCategory,
          dropdownColor: AppColors.white,
          style: const TextStyle(color: AppColors.navy, fontSize: 14),
          icon: const Icon(Icons.keyboard_arrow_down,
              color: AppColors.grey, size: 22),
          decoration: InputDecoration(
            hintText: 'Select your business category',
            hintStyle:
                const TextStyle(color: AppColors.grey, fontSize: 13),
            filled: true,
            fillColor: _inputBg,
            prefixIcon: const Icon(Icons.category_outlined,
                color: AppColors.grey, size: 20),
            contentPadding: const EdgeInsets.symmetric(
                horizontal: 16, vertical: 14),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide.none,
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide.none,
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide:
                  const BorderSide(color: AppColors.yellow, width: 1.5),
            ),
            errorBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide:
                  const BorderSide(color: AppColors.red, width: 1),
            ),
            errorStyle:
                const TextStyle(color: AppColors.red, fontSize: 11),
          ),
          items: _businessCategories
              .map((cat) => DropdownMenuItem(
                    value: cat,
                    child: Text(cat),
                  ))
              .toList(),
          onChanged: (val) => setState(() => _selectedCategory = val),
          validator: (v) => (v == null || v.isEmpty)
              ? 'Please select a business category'
              : null,
        ),
      ],
    );
  }

  // ─── GOOGLE LOCATION PLACEHOLDER ────────────────────────────────────────────

  Widget _buildGoogleLocationPlaceholder() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: _inputBg,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              color: AppColors.yellow.withOpacity(0.18),
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.my_location,
                color: AppColors.yellowDark, size: 20),
          ),
          const SizedBox(width: 14),
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Google Location Pin',
                  style: TextStyle(
                    color: AppColors.navy,
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                SizedBox(height: 3),
                Text(
                  'Coming soon — GPS pin drop will be available here',
                  style: TextStyle(color: AppColors.grey, fontSize: 11),
                ),
              ],
            ),
          ),
          Container(
            padding:
                const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: AppColors.greyLight,
              borderRadius: BorderRadius.circular(6),
            ),
            child: const Text(
              'SOON',
              style: TextStyle(
                color: AppColors.grey,
                fontSize: 10,
                fontWeight: FontWeight.bold,
                letterSpacing: 0.5,
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ─── FIELD LABEL ────────────────────────────────────────────────────────────

  Widget _fieldLabel(String label, {required bool required}) {
    return Row(
      children: [
        Text(
          label,
          style: const TextStyle(
            color: AppColors.navy,
            fontSize: 13,
            fontWeight: FontWeight.w600,
          ),
        ),
        if (required) ...[
          const SizedBox(width: 4),
          const Text(
            '*',
            style: TextStyle(
              color: AppColors.red,
              fontSize: 13,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ],
    );
  }
}

// ─── UPPERCASE FORMATTER (for GST) ──────────────────────────────────────────

class UpperCaseTextFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
      TextEditingValue oldValue, TextEditingValue newValue) {
    return newValue.copyWith(text: newValue.text.toUpperCase());
  }
}