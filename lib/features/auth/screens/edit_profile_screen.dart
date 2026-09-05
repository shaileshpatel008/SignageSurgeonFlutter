import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:image_picker/image_picker.dart';
import 'package:flutter_image_compress/flutter_image_compress.dart';
import '../../../core/theme/app_theme.dart';

class EditProfileScreen extends StatefulWidget {
  const EditProfileScreen({super.key});

  @override
  State<EditProfileScreen> createState() => _EditProfileScreenState();
}

class _EditProfileScreenState extends State<EditProfileScreen> {
  final _formKey = GlobalKey<FormState>();

  final _fullNameController = TextEditingController();
  final _emailController = TextEditingController();
  final _businessNameController = TextEditingController();
  final _designationController = TextEditingController();
  final _gstController = TextEditingController();

  String? _selectedCategory;
  String _mobileNumber = '';
  String? _photoUrl;
  File? _pickedPhoto;
  bool _loading = true;
  bool _saving = false;
  bool _uploadingPhoto = false;

  // Light input fill, sits on the off-white background.
  static const Color _inputBg = Color(0xFFF1F2F5);
  static const int _maxPhotoBytes = 800 * 1024; // ~800KB, small since it's just an avatar

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
    _loadProfile();
  }

  Future<void> _loadProfile() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    // Pre-fill phone
    final phone = user.phoneNumber ?? '';
    _mobileNumber = phone.startsWith('+91') ? phone.substring(3) : phone;

    try {
      final doc = await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .get();
      if (doc.exists && mounted) {
        final data = doc.data()!;
        _fullNameController.text = data['fullName'] ?? data['name'] ?? '';
        _emailController.text = data['email'] ?? '';
        _businessNameController.text = data['businessName'] ?? '';
        _designationController.text = data['designation'] ?? '';
        _gstController.text = data['gstNumber'] ?? '';
        _photoUrl = data['photoUrl'] as String?;
        _selectedCategory =
            (data['businessCategory'] as String?)?.isNotEmpty == true
            ? data['businessCategory']
            : null;
      }
    } catch (_) {}

    if (mounted) setState(() => _loading = false);
  }

  @override
  void dispose() {
    _fullNameController.dispose();
    _emailController.dispose();
    _businessNameController.dispose();
    _designationController.dispose();
    _gstController.dispose();
    super.dispose();
  }

  // ── Profile photo ────────────────────────────────────────────────────

  Future<void> _pickPhoto() async {
    final picker = ImagePicker();
    final source = await showModalBottomSheet<ImageSource>(
      context: context,
      backgroundColor: AppColors.white,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(18))),
      builder: (_) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 10),
            ListTile(
              leading: const Icon(Icons.camera_alt_outlined, color: AppColors.yellowDark),
              title: const Text('Take Photo', style: TextStyle(color: AppColors.navy)),
              onTap: () => Navigator.pop(context, ImageSource.camera),
            ),
            ListTile(
              leading: const Icon(Icons.photo_library_outlined, color: AppColors.yellowDark),
              title: const Text('Choose from Gallery', style: TextStyle(color: AppColors.navy)),
              onTap: () => Navigator.pop(context, ImageSource.gallery),
            ),
            if (_pickedPhoto != null || (_photoUrl != null && _photoUrl!.isNotEmpty))
              ListTile(
                leading: const Icon(Icons.delete_outline, color: AppColors.red),
                title: const Text('Remove Photo', style: TextStyle(color: AppColors.red)),
                onTap: () => Navigator.pop(context, null),
              ),
            const SizedBox(height: 10),
          ],
        ),
      ),
    );

    if (source == null) {
      if (_pickedPhoto != null || (_photoUrl != null && _photoUrl!.isNotEmpty)) {
        setState(() {
          _pickedPhoto = null;
          _photoUrl = null;
        });
      }
      return;
    }

    final picked = await picker.pickImage(source: source, imageQuality: 90, maxWidth: 800, maxHeight: 800);
    if (picked == null) return;
    setState(() => _pickedPhoto = File(picked.path));
  }

  Future<File> _compressPhotoIfNeeded(File file) async {
    final size = await file.length();
    if (size <= _maxPhotoBytes) return file;
    int quality = 85;
    File? result;
    final targetPath = '${file.path}_c_${DateTime.now().millisecondsSinceEpoch}.jpg';
    while (quality >= 30) {
      final compressed = await FlutterImageCompress.compressAndGetFile(file.path, targetPath, quality: quality);
      if (compressed == null) break;
      final compressedFile = File(compressed.path);
      final compressedSize = await compressedFile.length();
      if (compressedSize <= _maxPhotoBytes) { result = compressedFile; break; }
      quality -= 15;
    }
    return result ?? file;
  }

  Future<String?> _uploadPhotoIfNeeded(String uid) async {
    if (_pickedPhoto == null) return _photoUrl; // unchanged
    final compressed = await _compressPhotoIfNeeded(_pickedPhoto!);
    final ref = FirebaseStorage.instance.ref('profile_images/$uid/photo.jpg');
    await ref.putFile(compressed);
    return await ref.getDownloadURL();
  }

  Future<void> _saveProfile() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);

    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) return;

      setState(() => _uploadingPhoto = true);
      final photoUrl = await _uploadPhotoIfNeeded(user.uid);
      setState(() => _uploadingPhoto = false);

      await FirebaseFirestore.instance.collection('users').doc(user.uid).set({
        'fullName': _fullNameController.text.trim(),
        'name': _fullNameController.text.trim(),
        'email': _emailController.text.trim(),
        'businessName': _businessNameController.text.trim(),
        'businessCategory': _selectedCategory ?? '',
        'designation': _designationController.text.trim(),
        'gstNumber': _gstController.text.trim(),
        'photoUrl': photoUrl,
        'profileComplete': true,
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Profile updated successfully'),
            backgroundColor: AppColors.green,
          ),
        );
        Navigator.pop(context);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to update: $e'),
            backgroundColor: AppColors.red,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.dark,
      child: Scaffold(
        backgroundColor: AppColors.offWhite,
        body: SafeArea(
          child: _loading
              ? const Center(
                  child: CircularProgressIndicator(color: AppColors.yellow),
                )
              : Column(
                  children: [
                    // ── HEADER ──
                    Container(
                      padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
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
                          GestureDetector(
                            onTap: () => Navigator.pop(context),
                            child: Container(
                              width: 40,
                              height: 40,
                              decoration: BoxDecoration(
                                color: AppColors.offWhite,
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: const Icon(
                                Icons.arrow_back_ios_new,
                                color: AppColors.navy,
                                size: 18,
                              ),
                            ),
                          ),
                          const SizedBox(width: 14),
                          const Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Edit Profile',
                                  style: TextStyle(
                                    color: AppColors.navy,
                                    fontSize: 18,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                                Text(
                                  'Your current info is pre-filled below',
                                  style: TextStyle(
                                    color: AppColors.grey,
                                    fontSize: 11,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),

                    Expanded(
                      child: SingleChildScrollView(
                        physics: const BouncingScrollPhysics(),
                        padding: const EdgeInsets.fromLTRB(20, 24, 20, 40),
                        child: Form(
                          key: _formKey,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              // ── PROFILE PHOTO ──
                              Center(child: _buildPhotoPicker()),
                              const SizedBox(height: 28),

                              // ── PERSONAL ──
                              _sectionLabel('Personal Info'),
                              const SizedBox(height: 14),
                              _buildField(
                                controller: _fullNameController,
                                label: 'Full Name',
                                hint: 'Your full name',
                                icon: Icons.person_outline,
                                required: true,
                                validator: (v) =>
                                    (v == null || v.trim().isEmpty)
                                    ? 'Full name is required'
                                    : null,
                              ),
                              const SizedBox(height: 14),
                              _buildMobileField(),
                              const SizedBox(height: 14),
                              _buildField(
                                controller: _emailController,
                                label: 'Email Address',
                                hint: 'Your email (optional)',
                                icon: Icons.mail_outline,
                                required: false,
                                keyboardType: TextInputType.emailAddress,
                                validator: (v) {
                                  if (v == null || v.trim().isEmpty)
                                    return null;
                                  final emailRegex = RegExp(
                                    r'^[\w-\.]+@([\w-]+\.)+[\w-]{2,4}$',
                                  );
                                  if (!emailRegex.hasMatch(v.trim())) {
                                    return 'Enter a valid email';
                                  }
                                  return null;
                                },
                              ),

                              const SizedBox(height: 28),

                              // ── BUSINESS ──
                              _sectionLabel('Business Info'),
                              const SizedBox(height: 14),
                              _buildField(
                                controller: _businessNameController,
                                label: 'Business Name',
                                hint: 'Your business name',
                                icon: Icons.store_outlined,
                                required: true,
                                validator: (v) =>
                                    (v == null || v.trim().isEmpty)
                                    ? 'Business name is required'
                                    : null,
                              ),
                              const SizedBox(height: 14),
                              _buildCategoryDropdown(),
                              const SizedBox(height: 14),
                              _buildField(
                                controller: _designationController,
                                label: 'Designation',
                                hint: 'e.g. Owner, Manager',
                                icon: Icons.badge_outlined,
                                required: true,
                                validator: (v) =>
                                    (v == null || v.trim().isEmpty)
                                    ? 'Designation is required'
                                    : null,
                              ),

                              const SizedBox(height: 28),

                              // ── OTHER ──
                              _sectionLabel('Other Details'),
                              const SizedBox(height: 14),
                              _buildField(
                                controller: _gstController,
                                label: 'GST Number',
                                hint: 'GST number (optional)',
                                icon: Icons.receipt_outlined,
                                required: false,
                                inputFormatters: [
                                  UpperCaseTextFormatter(),
                                  LengthLimitingTextInputFormatter(15),
                                ],
                                validator: (v) {
                                  if (v == null || v.trim().isEmpty)
                                    return null;
                                  final gstRegex = RegExp(
                                    r'^[0-9]{2}[A-Z]{5}[0-9]{4}[A-Z]{1}[1-9A-Z]{1}Z[0-9A-Z]{1}$',
                                  );
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
                                  onPressed: _saving ? null : _saveProfile,
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: AppColors.yellow,
                                    foregroundColor: AppColors.navy,
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(14),
                                    ),
                                    elevation: 0,
                                  ),
                                  child: _saving
                                      ? Text(
                                          _uploadingPhoto ? 'Uploading photo...' : 'Saving...',
                                          style: const TextStyle(
                                            fontSize: 14,
                                            fontWeight: FontWeight.bold,
                                            color: AppColors.navy,
                                          ),
                                        )
                                      : const Text(
                                          'SAVE CHANGES',
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

  // ── Profile photo widget ─────────────────────────────────────────────

  Widget _buildPhotoPicker() {
    ImageProvider? backgroundImage;
    if (_pickedPhoto != null) {
      backgroundImage = FileImage(_pickedPhoto!);
    } else if (_photoUrl != null && _photoUrl!.isNotEmpty) {
      backgroundImage = NetworkImage(_photoUrl!);
    }

    return GestureDetector(
      onTap: _pickPhoto,
      child: Stack(
        children: [
          Container(
            width: 100,
            height: 100,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: AppColors.yellow,
              image: backgroundImage != null
                  ? DecorationImage(image: backgroundImage, fit: BoxFit.cover)
                  : null,
              boxShadow: [
                BoxShadow(color: Colors.black.withOpacity(0.08), blurRadius: 10, offset: const Offset(0, 3)),
              ],
            ),
            child: backgroundImage == null
                ? const Icon(Icons.person, color: AppColors.navy, size: 44)
                : null,
          ),
          Positioned(
            bottom: 0,
            right: 0,
            child: Container(
              width: 32,
              height: 32,
              decoration: BoxDecoration(
                color: AppColors.navy,
                shape: BoxShape.circle,
                border: Border.all(color: AppColors.offWhite, width: 2.5),
              ),
              child: const Icon(Icons.camera_alt, color: Colors.white, size: 16),
            ),
          ),
        ],
      ),
    );
  }

  // ── Reusable widgets (same style as profile_setup_screen) ────────────────

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
              horizontal: 16,
              vertical: 14,
            ),
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
              borderSide: const BorderSide(color: AppColors.yellow, width: 1.5),
            ),
            errorBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(color: AppColors.red, width: 1),
            ),
            focusedErrorBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(color: AppColors.red, width: 1.5),
            ),
            errorStyle: const TextStyle(color: AppColors.red, fontSize: 11),
          ),
        ),
      ],
    );
  }

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
              const Icon(Icons.phone_outlined, color: AppColors.grey, size: 20),
              const SizedBox(width: 12),
              Text(
                '+91 $_mobileNumber',
                style: const TextStyle(color: AppColors.navy, fontSize: 14),
              ),
              const Spacer(),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 4,
                ),
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
            'Number changes require OTP verification (coming soon)',
            style: TextStyle(color: AppColors.grey, fontSize: 11),
          ),
        ),
      ],
    );
  }

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
          icon: const Icon(
            Icons.keyboard_arrow_down,
            color: AppColors.grey,
            size: 22,
          ),
          decoration: InputDecoration(
            hintText: 'Select your business category',
            hintStyle: const TextStyle(color: AppColors.grey, fontSize: 13),
            filled: true,
            fillColor: _inputBg,
            prefixIcon: const Icon(
              Icons.category_outlined,
              color: AppColors.grey,
              size: 20,
            ),
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 16,
              vertical: 14,
            ),
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
              borderSide: const BorderSide(color: AppColors.yellow, width: 1.5),
            ),
            errorBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(color: AppColors.red, width: 1),
            ),
            errorStyle: const TextStyle(color: AppColors.red, fontSize: 11),
          ),
          items: _businessCategories
              .map((cat) => DropdownMenuItem(value: cat, child: Text(cat)))
              .toList(),
          onChanged: (val) => setState(() => _selectedCategory = val),
          validator: (v) => (v == null || v.isEmpty)
              ? 'Please select a business category'
              : null,
        ),
      ],
    );
  }

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

class UpperCaseTextFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    return newValue.copyWith(text: newValue.text.toUpperCase());
  }
}