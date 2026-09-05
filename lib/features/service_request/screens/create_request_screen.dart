import 'package:flutter/material.dart';

class CreateRequestScreen extends StatefulWidget {
  const CreateRequestScreen({super.key});

  @override
  State<CreateRequestScreen> createState() => _CreateRequestScreenState();
}

class _CreateRequestScreenState extends State<CreateRequestScreen> {
  static const Color _bg            = Color(0xFF0A1628);
  static const Color _card          = Color(0xFF111F3A);
  static const Color _yellow        = Color(0xFFFFD700);
  static const Color _textPrimary   = Color(0xFFFFFFFF);
  static const Color _textSecondary = Color(0xFF8A9BB8);
  static const Color _inputBorder   = Color(0xFF1E3A5F);
  static const Color _inputFill     = Color(0xFF0D1E35);

  static const Map<String, Map<String, dynamic>> _serviceConfig = {
    'repairing': {
      'title': 'Repairing Request',
      'categories': [
        'LED Signage Repair',
        'Neon Sign Repair',
        'Flex / Vinyl Banner Fix',
        'ACP Board Repair',
        'Backlit Board Repair',
        'Glow Sign Board Repair',
        'Digital Display Panel Repair',
        'Standee / Display Board Repair',
        'Channel Letter Repair',
        'Pylon / Totem Sign Repair',
      ],
    },
    'rebranding': {
      'title': 'Rebranding Request',
      'categories': [
        'Logo Change',
        'Brand Color Update',
        'Full Signage Overhaul',
        'Name / Text Change',
        'Franchise Rebranding',
        'Partial Signage Update',
        'Font / Typography Change',
        'New Brand Identity Rollout',
      ],
    },
    'new_signage': {
      'title': 'New Signage Request',
      'categories': [
        'LED Signage (New)',
        'Neon Sign (New)',
        'ACP Board (New)',
        'Flex / Vinyl Print (New)',
        '3D Letter Signage',
        'Digital Display Unit',
        'Glow Sign Board (New)',
        'Standee / Display (New)',
        'Channel Letter Sign (New)',
        'Pylon / Totem Sign (New)',
      ],
    },
    'cleaning': {
      'title': 'Signage Cleaning Request',
      'categories': [
        'Surface / Dust Cleaning',
        'Deep Cleaning',
        'Anti-Graffiti Treatment',
        'Weather Stain Removal',
        'LED Panel Cleaning',
        'Full Unit Cleaning',
        'Chemical Wash',
        'Post-Rain Cleaning',
      ],
    },
  };

  // serviceType is stored in state after initState reads the route argument
  late String _serviceType;
  bool _initialized = false;

  String? _selectedCategory;
  final _formKey            = GlobalKey<FormState>();
  final _descController     = TextEditingController();
  final _houseController    = TextEditingController();
  final _buildingController = TextEditingController();
  final _areaController     = TextEditingController();
  final _cityController     = TextEditingController();
  final _pincodeController  = TextEditingController();

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_initialized) {
      _serviceType = ModalRoute.of(context)?.settings.arguments as String? ?? 'repairing';
      _initialized = true;
    }
  }

  @override
  void dispose() {
    _descController.dispose();
    _houseController.dispose();
    _buildingController.dispose();
    _areaController.dispose();
    _cityController.dispose();
    _pincodeController.dispose();
    super.dispose();
  }

  String get _mergedLocation {
    final parts = [
      _houseController.text.trim(),
      _buildingController.text.trim(),
      _areaController.text.trim(),
      _cityController.text.trim(),
    ].where((e) => e.isNotEmpty).join(', ');
    final pin = _pincodeController.text.trim();
    return pin.isNotEmpty ? '$parts - $pin' : parts;
  }

  void _onContinue() {
    if (_formKey.currentState!.validate()) {
      Navigator.pushNamed(
        context,
        '/upload-media',
        arguments: {
          'category':    _serviceType,
          'description': _descController.text.trim(),
          'priority':    'Normal',
          'siteName':    _buildingController.text.trim(),
          'address':     '${_houseController.text.trim()}, ${_buildingController.text.trim()}, ${_areaController.text.trim()}, ${_cityController.text.trim()} - ${_pincodeController.text.trim()}',
        },
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final config     = _serviceConfig[_serviceType] ?? _serviceConfig['repairing']!;
    final categories = List<String>.from(config['categories'] as List);

    return Scaffold(
      backgroundColor: _bg,
      appBar: _buildAppBar(config['title'] as String),
      body: Theme(
        // Override any global InputDecorationTheme for this screen only
        data: Theme.of(context).copyWith(
          inputDecorationTheme: const InputDecorationTheme(
            filled: true,
            fillColor: _inputFill,
            border: InputBorder.none,
            enabledBorder: InputBorder.none,
            focusedBorder: InputBorder.none,
            errorBorder: InputBorder.none,
          ),
        ),
        child: Form(
          key: _formKey,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(20, 24, 20, 20),
            children: [
              _sectionLabel('Service Category'),
              const SizedBox(height: 10),
              _buildDropdown(categories),
              const SizedBox(height: 28),
              _sectionLabel('Problem Description'),
              const SizedBox(height: 10),
              _buildDescriptionField(),
              const SizedBox(height: 28),
              _sectionLabel('Location Details'),
              const SizedBox(height: 6),
              _buildLocationNote(),
              const SizedBox(height: 10),
              _buildLocationFields(),
              const SizedBox(height: 36),
              _buildContinueButton(),
              const SizedBox(height: 30),
            ],
          ),
        ),
      ),
    );
  }

  PreferredSizeWidget _buildAppBar(String title) {
    return AppBar(
      backgroundColor: _bg,
      elevation: 0,
      centerTitle: true,
      leading: GestureDetector(
        onTap: () => Navigator.pop(context),
        child: Container(
          margin: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: _card,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: _inputBorder),
          ),
          child: const Icon(Icons.arrow_back_ios_new_rounded,
              color: Colors.white, size: 16),
        ),
      ),
      title: Text(
        title,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 17,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.3,
        ),
      ),
    );
  }

  Widget _sectionLabel(String label) {
    return Row(
      children: [
        Container(
          width: 3,
          height: 16,
          decoration: BoxDecoration(
            color: _yellow,
            borderRadius: BorderRadius.circular(2),
          ),
        ),
        const SizedBox(width: 8),
        Text(
          label,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 14,
            fontWeight: FontWeight.w700,
            letterSpacing: 0.2,
          ),
        ),
      ],
    );
  }

  Widget _buildLocationNote() {
    return const Row(
      children: [
        Icon(Icons.info_outline, color: Color(0xFF8A9BB8), size: 13),
        SizedBox(width: 6),
        Text(
          'Maps auto-fill coming soon',
          style: TextStyle(color: Color(0xFF8A9BB8), fontSize: 11),
        ),
      ],
    );
  }

  Widget _buildDropdown(List<String> categories) {
    return Container(
      decoration: BoxDecoration(
        color: _inputFill,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: _inputBorder, width: 1),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 2),
      child: DropdownButtonFormField<String>(
        value: _selectedCategory,
        dropdownColor: _inputFill,
        iconEnabledColor: _yellow,
        isExpanded: true,
        style: const TextStyle(
          color: _textPrimary,
          fontSize: 14,
          fontWeight: FontWeight.w500,
        ),
        hint: const Text(
          'Select a category',
          style: TextStyle(color: _textSecondary, fontSize: 14),
        ),
        decoration: const InputDecoration(
          filled: true,
          fillColor: _inputFill,
          border: InputBorder.none,
          enabledBorder: InputBorder.none,
          focusedBorder: InputBorder.none,
          errorBorder: InputBorder.none,
          contentPadding: EdgeInsets.zero,
        ),
        validator: (v) => v == null ? 'Please select a category' : null,
        items: categories
            .map((c) => DropdownMenuItem(
                  value: c,
                  child: Text(c,
                      style: const TextStyle(
                          color: _textPrimary, fontSize: 14)),
                ))
            .toList(),
        onChanged: (val) => setState(() => _selectedCategory = val),
      ),
    );
  }

  Widget _buildDescriptionField() {
    return Container(
      decoration: BoxDecoration(
        color: _inputFill,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: _inputBorder, width: 1),
      ),
      child: TextFormField(
        controller: _descController,
        maxLines: 4,
        maxLength: 200,
        style: const TextStyle(
            color: _textPrimary, fontSize: 14, height: 1.5),
        decoration: const InputDecoration(
          filled: true,
          fillColor: _inputFill,
          hintText: 'Describe your problem here...',
          hintStyle: TextStyle(color: _textSecondary, fontSize: 14),
          contentPadding: EdgeInsets.all(16),
          border: InputBorder.none,
          enabledBorder: InputBorder.none,
          focusedBorder: InputBorder.none,
          errorBorder: InputBorder.none,
          counterStyle: TextStyle(color: _textSecondary, fontSize: 11),
        ),
        validator: (v) => (v == null || v.trim().isEmpty)
            ? 'Please describe the problem'
            : null,
      ),
    );
  }

  Widget _buildLocationFields() {
    return Container(
      decoration: BoxDecoration(
        color: _inputFill,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: _inputBorder, width: 1),
      ),
      child: Column(
        children: [
          _locationRow(
            controller: _houseController,
            hint: 'House / Shop No.  (e.g. B-204)',
            icon: Icons.home_outlined,
            validator: (v) =>
                (v == null || v.trim().isEmpty) ? 'Required' : null,
          ),
          _locationDivider(),
          _locationRow(
            controller: _buildingController,
            hint: 'Building / Society Name',
            icon: Icons.apartment_outlined,
            validator: (v) =>
                (v == null || v.trim().isEmpty) ? 'Required' : null,
          ),
          _locationDivider(),
          _locationRow(
            controller: _areaController,
            hint: 'Area / Street  (e.g. Satellite)',
            icon: Icons.map_outlined,
            validator: (v) =>
                (v == null || v.trim().isEmpty) ? 'Required' : null,
          ),
          _locationDivider(),
          _locationRow(
            controller: _cityController,
            hint: 'City  (e.g. Ahmedabad)',
            icon: Icons.location_city_outlined,
            validator: (v) =>
                (v == null || v.trim().isEmpty) ? 'Required' : null,
          ),
          _locationDivider(),
          _locationRow(
            controller: _pincodeController,
            hint: 'Pincode  (e.g. 380015)',
            icon: Icons.pin_drop_outlined,
            keyboardType: TextInputType.number,
            validator: (v) {
              if (v == null || v.trim().isEmpty) return 'Required';
              if (v.trim().length != 6) return 'Invalid pincode';
              return null;
            },
          ),
        ],
      ),
    );
  }

  Widget _locationRow({
    required TextEditingController controller,
    required String hint,
    required IconData icon,
    TextInputType keyboardType = TextInputType.text,
    String? Function(String?)? validator,
  }) {
    return TextFormField(
      controller: controller,
      keyboardType: keyboardType,
      style: const TextStyle(
          color: _textPrimary, fontSize: 14, fontWeight: FontWeight.w400),
      validator: validator,
      decoration: InputDecoration(
        filled: true,
        fillColor: _inputFill,
        hintText: hint,
        hintStyle: const TextStyle(color: _textSecondary, fontSize: 13),
        prefixIcon: Icon(icon, color: _yellow.withOpacity(0.7), size: 18),
        border: InputBorder.none,
        enabledBorder: InputBorder.none,
        focusedBorder: InputBorder.none,
        contentPadding:
            const EdgeInsets.symmetric(vertical: 14, horizontal: 16),
        errorStyle:
            const TextStyle(color: Color(0xFFFF6B6B), fontSize: 11),
      ),
    );
  }

  Widget _locationDivider() => const Divider(
        color: _inputBorder,
        height: 1,
        indent: 14,
        endIndent: 14,
      );

  Widget _buildContinueButton() {
    return SizedBox(
      width: double.infinity,
      height: 54,
      child: ElevatedButton(
        onPressed: _onContinue,
        style: ElevatedButton.styleFrom(
          backgroundColor: _yellow,
          foregroundColor: Colors.black,
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14)),
          elevation: 2,
          shadowColor: _yellow.withOpacity(0.4),
        ),
        child: const Text(
          'Continue',
          style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w800,
              letterSpacing: 0.5),
        ),
      ),
    );
  }
}