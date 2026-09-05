import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:geolocator/geolocator.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import '../../../core/theme/app_theme.dart';

// ── Google API key (same one used in AndroidManifest.xml) ──
// Restricted to: Android app (com.signagesurgeon.app), Geocoding API,
// Places API (New), Maps SDK for Android/iOS.
const String _kGoogleApiKey = 'AIzaSyD8v_obWHOLaRYIlSL2vlOjlSYFChOEvmE';
const String _kAndroidPackage = 'com.signagesurgeon.app';
const String _kAndroidCert = 'FF441CA235828F075250E7B23268A62CBDD930B2';

class CreateRequestScreen extends StatefulWidget {
  const CreateRequestScreen({super.key});

  @override
  State<CreateRequestScreen> createState() => _CreateRequestScreenState();
}

class _CreateRequestScreenState extends State<CreateRequestScreen> {
  // Light input fill, sits inside white cards.
  static const Color _inputFill = Color(0xFFF7F8FA);

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

  // ── Location / Maps state ──
  final _searchController = TextEditingController();
  final FocusNode _searchFocus = FocusNode();
  Timer? _debounce;
  List<Map<String, String>> _suggestions = [];
  bool _searchLoading = false;
  bool _locating = false;

  GoogleMapController? _mapController;
  LatLng? _pinPosition;
  static const LatLng _defaultCenter = LatLng(23.0225, 72.5714); // Ahmedabad

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
    _searchController.dispose();
    _searchFocus.dispose();
    _debounce?.cancel();
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

  // ─────────────────────────────────────────────
  // PLACES AUTOCOMPLETE (New API)
  // ─────────────────────────────────────────────
  void _onSearchChanged(String input) {
    _debounce?.cancel();
    if (input.trim().length < 3) {
      setState(() => _suggestions = []);
      return;
    }
    _debounce = Timer(const Duration(milliseconds: 400), () => _fetchAutocomplete(input));
  }

  Future<void> _fetchAutocomplete(String input) async {
    setState(() => _searchLoading = true);
    try {
      final uri = Uri.parse('https://places.googleapis.com/v1/places:autocomplete');
      final res = await http.post(
        uri,
        headers: {
          'Content-Type': 'application/json',
          'X-Goog-Api-Key': _kGoogleApiKey,
          'X-Android-Package': _kAndroidPackage,
          'X-Android-Cert': _kAndroidCert,
        },
        body: jsonEncode({
          'input': input,
          'includedRegionCodes': ['in'],
          'locationBias': {
            'circle': {
              'center': {'latitude': 23.0225, 'longitude': 72.5714},
              'radius': 50000.0,
            }
          },
        }),
      );

      if (res.statusCode == 200) {
        final data = jsonDecode(res.body) as Map<String, dynamic>;
        final preds = (data['suggestions'] as List<dynamic>? ?? []);
        setState(() {
          _suggestions = preds.map((p) {
            final placePrediction = p['placePrediction'] as Map<String, dynamic>;
            return {
              'placeId': placePrediction['placeId'] as String,
              'text': placePrediction['text']['text'] as String,
            };
          }).toList();
        });
      } else {
        debugPrint('Autocomplete error: ${res.statusCode} ${res.body}');
      }
    } catch (e) {
      debugPrint('Autocomplete exception: $e');
    } finally {
      if (mounted) setState(() => _searchLoading = false);
    }
  }

  Future<void> _selectSuggestion(Map<String, String> suggestion) async {
    setState(() {
      _suggestions = [];
      _searchController.text = suggestion['text'] ?? '';
      _searchLoading = true;
    });
    FocusScope.of(context).unfocus();

    try {
      final placeId = suggestion['placeId'];
      final uri = Uri.parse('https://places.googleapis.com/v1/places/$placeId');
      final res = await http.get(
        uri,
        headers: {
          'X-Goog-Api-Key': _kGoogleApiKey,
          'X-Android-Package': _kAndroidPackage,
          'X-Android-Cert': _kAndroidCert,
          'X-Goog-FieldMask': 'location,addressComponents,formattedAddress',
        },
      );

      if (res.statusCode == 200) {
        final data = jsonDecode(res.body) as Map<String, dynamic>;
        final loc = data['location'] as Map<String, dynamic>;
        final lat = (loc['latitude'] as num).toDouble();
        final lng = (loc['longitude'] as num).toDouble();
        _applyAddressComponents(data['addressComponents'] as List<dynamic>? ?? []);
        _movePin(LatLng(lat, lng));
      } else {
        debugPrint('Place details error: ${res.statusCode} ${res.body}');
      }
    } catch (e) {
      debugPrint('Place details exception: $e');
    } finally {
      if (mounted) setState(() => _searchLoading = false);
    }
  }

  // ─────────────────────────────────────────────
  // CURRENT LOCATION
  // ─────────────────────────────────────────────
  Future<void> _useCurrentLocation() async {
    setState(() => _locating = true);
    try {
      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Location permission is required to use this feature.')),
          );
        }
        return;
      }

      final serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Please enable location services.')),
          );
        }
        return;
      }

      final pos = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
      );
      final latLng = LatLng(pos.latitude, pos.longitude);
      await _reverseGeocode(latLng);
      _movePin(latLng);
    } catch (e) {
      debugPrint('Location error: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not fetch current location.')),
        );
      }
    } finally {
      if (mounted) setState(() => _locating = false);
    }
  }

  // ─────────────────────────────────────────────
  // REVERSE GEOCODE (used for pin drag + current location)
  // ─────────────────────────────────────────────
  Future<void> _reverseGeocode(LatLng point) async {
    try {
      final uri = Uri.parse(
        'https://maps.googleapis.com/maps/api/geocode/json'
        '?latlng=${point.latitude},${point.longitude}&key=$_kGoogleApiKey',
      );
      final res = await http.get(uri);
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body) as Map<String, dynamic>;
        final results = data['results'] as List<dynamic>? ?? [];
        if (results.isNotEmpty) {
          final first = results.first as Map<String, dynamic>;
          _applyAddressComponents(first['address_components'] as List<dynamic>? ?? []);
          _searchController.text = first['formatted_address'] as String? ?? '';
        }
      }
    } catch (e) {
      debugPrint('Reverse geocode exception: $e');
    }
  }

  void _applyAddressComponents(List<dynamic> components) {
    String area = '', city = '', pincode = '', building = '';
    for (final c in components) {
      final types = List<String>.from(c['types'] ?? c['type'] ?? []);
      final name = (c['longText'] ?? c['long_name'] ?? '') as String;
      if (types.contains('sublocality') || types.contains('sublocality_level_1')) {
        area = name;
      } else if (types.contains('locality')) {
        city = name;
      } else if (types.contains('postal_code')) {
        pincode = name;
      } else if (types.contains('premise') || types.contains('neighborhood')) {
        building = name;
      }
    }
    setState(() {
      if (area.isNotEmpty) _areaController.text = area;
      if (city.isNotEmpty) _cityController.text = city;
      if (pincode.isNotEmpty) _pincodeController.text = pincode;
      if (building.isNotEmpty && _buildingController.text.isEmpty) {
        _buildingController.text = building;
      }
    });
  }

  void _movePin(LatLng point) {
    setState(() => _pinPosition = point);
    _mapController?.animateCamera(CameraUpdate.newLatLngZoom(point, 16));
  }

  void _onMarkerDragEnd(LatLng point) {
    setState(() => _pinPosition = point);
    _reverseGeocode(point);
  }

  // ─────────────────────────────────────────────
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
          'lat':         _pinPosition?.latitude,
          'lng':         _pinPosition?.longitude,
        },
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final config     = _serviceConfig[_serviceType] ?? _serviceConfig['repairing']!;
    final categories = List<String>.from(config['categories'] as List);

    return Scaffold(
      backgroundColor: AppColors.offWhite,
      appBar: _buildAppBar(config['title'] as String),
      body: Theme(
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
              const SizedBox(height: 10),
              _buildLocationSearch(),
              const SizedBox(height: 10),
              _buildCurrentLocationButton(),
              const SizedBox(height: 12),
              _buildMap(),
              const SizedBox(height: 16),
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
      backgroundColor: AppColors.offWhite,
      elevation: 0,
      centerTitle: true,
      leading: GestureDetector(
        onTap: () => Navigator.pop(context),
        child: Container(
          margin: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: AppColors.white,
            borderRadius: BorderRadius.circular(10),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.06),
                blurRadius: 8,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: const Icon(Icons.arrow_back_ios_new_rounded,
              color: AppColors.navy, size: 16),
        ),
      ),
      title: Text(
        title,
        style: const TextStyle(
          color: AppColors.navy,
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
            color: AppColors.yellow,
            borderRadius: BorderRadius.circular(2),
          ),
        ),
        const SizedBox(width: 8),
        Text(
          label,
          style: const TextStyle(
            color: AppColors.navy,
            fontSize: 14,
            fontWeight: FontWeight.w700,
            letterSpacing: 0.2,
          ),
        ),
      ],
    );
  }

  // ── Search box + suggestions dropdown ──
  Widget _buildLocationSearch() {
    return Column(
      children: [
        Container(
          decoration: BoxDecoration(
            color: AppColors.white,
            borderRadius: BorderRadius.circular(12),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.05),
                blurRadius: 10,
                offset: const Offset(0, 3),
              ),
            ],
          ),
          child: TextField(
            controller: _searchController,
            focusNode: _searchFocus,
            onChanged: _onSearchChanged,
            style: const TextStyle(color: AppColors.navy, fontSize: 14),
            decoration: InputDecoration(
              filled: true,
              fillColor: AppColors.white,
              hintText: 'Search for your address',
              hintStyle: const TextStyle(color: AppColors.grey, fontSize: 14),
              prefixIcon: const Icon(Icons.search, color: AppColors.yellowDark, size: 20),
              suffixIcon: _searchLoading
                  ? const Padding(
                      padding: EdgeInsets.all(14),
                      child: SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                    )
                  : null,
              border: InputBorder.none,
              enabledBorder: InputBorder.none,
              focusedBorder: InputBorder.none,
              contentPadding: const EdgeInsets.symmetric(vertical: 14, horizontal: 16),
            ),
          ),
        ),
        if (_suggestions.isNotEmpty)
          Container(
            margin: const EdgeInsets.only(top: 6),
            decoration: BoxDecoration(
              color: AppColors.white,
              borderRadius: BorderRadius.circular(12),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.06),
                  blurRadius: 10,
                  offset: const Offset(0, 3),
                ),
              ],
            ),
            child: Column(
              children: _suggestions.map((s) {
                return InkWell(
                  onTap: () => _selectSuggestion(s),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                    child: Row(
                      children: [
                        const Icon(Icons.location_on_outlined, color: AppColors.grey, size: 16),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            s['text'] ?? '',
                            style: const TextStyle(color: AppColors.navy, fontSize: 13),
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              }).toList(),
            ),
          ),
      ],
    );
  }

  Widget _buildCurrentLocationButton() {
    return SizedBox(
      width: double.infinity,
      child: OutlinedButton.icon(
        onPressed: _locating ? null : _useCurrentLocation,
        icon: _locating
            ? const SizedBox(
                width: 14,
                height: 14,
                child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.yellowDark),
              )
            : const Icon(Icons.my_location, size: 16, color: AppColors.yellowDark),
        label: Text(
          _locating ? 'Fetching location...' : 'Use Current Location',
          style: const TextStyle(
            color: AppColors.navy,
            fontSize: 13,
            fontWeight: FontWeight.w600,
          ),
        ),
        style: OutlinedButton.styleFrom(
          backgroundColor: AppColors.white,
          side: const BorderSide(color: AppColors.greyLight),
          padding: const EdgeInsets.symmetric(vertical: 12),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
      ),
    );
  }

  Widget _buildMap() {
    return ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: SizedBox(
        height: 200,
        child: Stack(
          children: [
            GoogleMap(
              initialCameraPosition: CameraPosition(
                target: _pinPosition ?? _defaultCenter,
                zoom: _pinPosition != null ? 16 : 12,
              ),
              onMapCreated: (c) => _mapController = c,
              markers: {
                if (_pinPosition != null)
                  Marker(
                    markerId: const MarkerId('selected-location'),
                    position: _pinPosition!,
                    draggable: true,
                    onDragEnd: _onMarkerDragEnd,
                  ),
              },
              onTap: (point) {
                _movePin(point);
                _reverseGeocode(point);
              },
              myLocationButtonEnabled: false,
              zoomControlsEnabled: false,
            ),
            if (_pinPosition == null)
              Container(
                color: Colors.black.withOpacity(0.03),
                alignment: Alignment.center,
                child: const Text(
                  'Search or tap the map to drop a pin',
                  style: TextStyle(color: AppColors.grey, fontSize: 12),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildDropdown(List<String> categories) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 10,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 2),
      child: DropdownButtonFormField<String>(
        value: _selectedCategory,
        dropdownColor: AppColors.white,
        iconEnabledColor: AppColors.yellowDark,
        isExpanded: true,
        style: const TextStyle(
          color: AppColors.navy,
          fontSize: 14,
          fontWeight: FontWeight.w500,
        ),
        hint: const Text(
          'Select a category',
          style: TextStyle(color: AppColors.grey, fontSize: 14),
        ),
        decoration: const InputDecoration(
          filled: true,
          fillColor: AppColors.white,
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
                          color: AppColors.navy, fontSize: 14)),
                ))
            .toList(),
        onChanged: (val) => setState(() => _selectedCategory = val),
      ),
    );
  }

  Widget _buildDescriptionField() {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 10,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: TextFormField(
        controller: _descController,
        maxLines: 4,
        maxLength: 200,
        style: const TextStyle(
            color: AppColors.navy, fontSize: 14, height: 1.5),
        decoration: const InputDecoration(
          filled: true,
          fillColor: AppColors.white,
          hintText: 'Describe your problem here...',
          hintStyle: TextStyle(color: AppColors.grey, fontSize: 14),
          contentPadding: EdgeInsets.all(16),
          border: InputBorder.none,
          enabledBorder: InputBorder.none,
          focusedBorder: InputBorder.none,
          errorBorder: InputBorder.none,
          counterStyle: TextStyle(color: AppColors.grey, fontSize: 11),
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
        color: AppColors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 10,
            offset: const Offset(0, 3),
          ),
        ],
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
          color: AppColors.navy, fontSize: 14, fontWeight: FontWeight.w400),
      validator: validator,
      decoration: InputDecoration(
        filled: true,
        fillColor: AppColors.white,
        hintText: hint,
        hintStyle: const TextStyle(color: AppColors.grey, fontSize: 13),
        prefixIcon: Icon(icon, color: AppColors.yellowDark, size: 18),
        border: InputBorder.none,
        enabledBorder: InputBorder.none,
        focusedBorder: InputBorder.none,
        contentPadding:
            const EdgeInsets.symmetric(vertical: 14, horizontal: 16),
        errorStyle:
            const TextStyle(color: AppColors.red, fontSize: 11),
      ),
    );
  }

  Widget _locationDivider() => const Divider(
        color: AppColors.greyLight,
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
          backgroundColor: AppColors.yellow,
          foregroundColor: AppColors.navy,
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14)),
          elevation: 2,
          shadowColor: AppColors.yellow.withOpacity(0.4),
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