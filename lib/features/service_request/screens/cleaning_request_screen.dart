import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';
import 'package:flutter_image_compress/flutter_image_compress.dart';
import 'package:geolocator/geolocator.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/saved_address_picker.dart';
import '../../../core/constants/app_routes.dart';

class CleaningRequestScreen extends StatefulWidget {
  const CleaningRequestScreen({super.key});

  @override
  State<CleaningRequestScreen> createState() => _CleaningRequestScreenState();
}

class _CleaningRequestScreenState extends State<CleaningRequestScreen> {
  static const String _mapsApiKey = 'AIzaSyD8v_obWHOLaRYIlSL2vlOjlSYFChOEvmE';

  // ── Options (from Founder Input Master Doc 04) ───────────────────────────
  static const List<String> _signageTypes = [
    'LED / Illuminated Signage', 'Acrylic Signage', 'Channel Letter Signage',
    'ACP Fascia / Signage', 'Glow Sign Board', 'Neon / LED Neon Signage',
    'Pylon / Totem Sign', 'Directional Signage', 'Indoor Signage',
    'Rooftop Signage', 'Multiple Signages', 'Other / Not Sure',
  ];

  static const List<String> _quantityOptions = [
    '1 Signage', '2–5 Signages', '6–10 Signages', '11–25 Signages', 'More Than 25 Signages',
  ];

  static const List<String> _sizeOptions = [
    'Small — Up to 10 Sq. Ft.', 'Medium — 11 to 50 Sq. Ft.',
    'Large — 51 to 100 Sq. Ft.', 'Extra Large — Above 100 Sq. Ft.',
    'Multiple Signages / Different Sizes', 'Not Sure',
  ];

  static const List<String> _heightOptions = [
    'Ground Level', 'Up to 10 Ft.', '11 to 20 Ft.', '21 to 40 Ft.',
    'Above 40 Ft.', 'Multiple Signages at Different Heights', 'Not Sure',
  ];

  static const List<String> _illuminationOptions = [
    'Yes — Fully Illuminated', 'Yes — Partially Illuminated',
    'No — Non-Illuminated', 'Multiple Signages with Different Types', 'Not Sure',
  ];

  static const List<String> _installationAreas = [
    'Building Front / Fascia', 'Main Entrance', 'Shop / Showroom Front',
    'Rooftop', 'Pylon / Totem', 'Indoor Area', 'Parking Area',
    'Factory / Industrial Premises', 'Roadside / Outdoor', 'Multiple Areas',
    'Other / Not Sure',
  ];

  static const List<String> _photoSlotLabels = [
    'Full Signage Photo', 'Front View', 'Close-up View', 'Wider Installation Area',
  ];

  // ── Form state ─────────────────────────────────────────────────────────
  final _formKey = GlobalKey<FormState>();
  String? _signageType;
  String? _quantity;
  String? _approxSize;
  String? _installationHeight;
  String? _accessEquipment; // 'ladder' | 'h_frame' | 'not_needed' — compulsory
  String? _illumination;
  String? _installationArea;

  final _signageTypeOtherController = TextEditingController();
  final _installationAreaOtherController = TextEditingController();

  // 4 named slots + up to 1 extra (max 5 total, per doc)
  final Map<int, File?> _photoSlots = {0: null, 1: null, 2: null, 3: null};
  final List<File> _extraPhotos = [];

  // Location — same broken-out pattern as the other services
  final _houseController = TextEditingController();
  final _buildingController = TextEditingController();
  final _areaController = TextEditingController();
  final _landmarkController = TextEditingController();
  final _cityController = TextEditingController(text: 'Ahmedabad');
  final _pincodeController = TextEditingController();
  final _searchController = TextEditingController();

  double? _lat;
  double? _lng;
  static const double _defaultMapLat = 23.0225;
  static const double _defaultMapLng = 72.5714;
  GoogleMapController? _mapController;
  List<Map<String, String>> _suggestions = [];
  bool _searching = false;
  bool _fetchingLocation = false;

  List<String> _serviceableCities = ['Ahmedabad', 'Gandhinagar'];
  bool _cityUnavailable = false;
  Timer? _cityDebounce;

  bool _submitting = false;

  @override
  void initState() {
    super.initState();
    _loadServiceableCities();
    _loadEquipmentFeesForDisplay();
  }

  double? _ladderFeeDisplay;
  double? _hFrameFeeDisplay;

  Future<void> _loadEquipmentFeesForDisplay() async {
    try {
      final doc = await FirebaseFirestore.instance.collection('app_settings').doc('pricing_config').get();
      if (mounted) {
        setState(() {
          _ladderFeeDisplay = (doc.data()?['ladderEquipmentFee'] as num?)?.toDouble();
          _hFrameFeeDisplay = (doc.data()?['hFrameEquipmentFee'] as num?)?.toDouble();
        });
      }
    } catch (_) {}
  }

  Future<void> _loadServiceableCities() async {
    try {
      final doc = await FirebaseFirestore.instance.collection('app_settings').doc('serviceability').get();
      if (doc.exists) {
        final cities = doc.data()?['cities'] as List?;
        if (cities != null && cities.isNotEmpty) {
          setState(() => _serviceableCities = cities.map((c) => c.toString()).toList());
        }
      }
    } catch (_) {}
  }

  @override
  void dispose() {
    _cityDebounce?.cancel();
    _signageTypeOtherController.dispose();
    _installationAreaOtherController.dispose();
    _houseController.dispose();
    _buildingController.dispose();
    _areaController.dispose();
    _landmarkController.dispose();
    _cityController.dispose();
    _pincodeController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  bool _isOther(String? value) => value != null && value.toLowerCase().contains('other');

  String? get _effectiveSignageType =>
      (_isOther(_signageType) && _signageTypeOtherController.text.trim().isNotEmpty)
          ? _signageTypeOtherController.text.trim() : _signageType;
  String? get _effectiveInstallationArea =>
      (_isOther(_installationArea) && _installationAreaOtherController.text.trim().isNotEmpty)
          ? _installationAreaOtherController.text.trim() : _installationArea;

  String get _mergedAddress {
    final parts = [
      _houseController.text.trim(),
      _buildingController.text.trim(),
      _areaController.text.trim(),
      if (_landmarkController.text.trim().isNotEmpty) 'Near ${_landmarkController.text.trim()}',
      _cityController.text.trim(),
    ].where((e) => e.isNotEmpty).join(', ');
    final pin = _pincodeController.text.trim();
    return pin.isNotEmpty ? '$parts - $pin' : parts;
  }

  // ── Photo picking (min 3, max 5 total per doc) ─────────────────────────

  int get _filledPhotoCount => _photoSlots.values.where((f) => f != null).length + _extraPhotos.length;
  bool get _canAddMorePhotos => _filledPhotoCount < 5;

  Future<File?> _pickImage() async {
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
              leading: const Icon(Icons.camera_alt_outlined, color: AppColors.serviceAccent),
              title: const Text('Take Photo', style: TextStyle(color: AppColors.navy)),
              onTap: () => Navigator.pop(context, ImageSource.camera),
            ),
            ListTile(
              leading: const Icon(Icons.photo_library_outlined, color: AppColors.serviceAccent),
              title: const Text('Choose from Gallery', style: TextStyle(color: AppColors.navy)),
              onTap: () => Navigator.pop(context, ImageSource.gallery),
            ),
            const SizedBox(height: 10),
          ],
        ),
      ),
    );
    if (source == null) return null;
    final picked = await picker.pickImage(source: source, imageQuality: 90);
    if (picked == null) return null;
    return File(picked.path);
  }

  Future<void> _pickPhoto(int slotIndex) async {
    final file = await _pickImage();
    if (file == null) return;
    setState(() => _photoSlots[slotIndex] = file);
  }

  Future<void> _pickExtraPhoto() async {
    if (!_canAddMorePhotos) {
      _showSnack('Maximum 5 photos allowed.');
      return;
    }
    final file = await _pickImage();
    if (file == null) return;
    setState(() => _extraPhotos.add(file));
  }

  void _removePhoto(int slotIndex) => setState(() => _photoSlots[slotIndex] = null);
  void _removeExtraPhoto(int index) => setState(() => _extraPhotos.removeAt(index));

  static const int _maxImageBytes = 1536 * 1024;

  Future<File> _compressImageIfNeeded(File file) async {
    final size = await file.length();
    if (size <= _maxImageBytes) return file;
    int quality = 85;
    File? result;
    final targetPath = '${file.path}_c_${DateTime.now().millisecondsSinceEpoch}.jpg';
    while (quality >= 30) {
      final compressed = await FlutterImageCompress.compressAndGetFile(file.path, targetPath, quality: quality);
      if (compressed == null) break;
      final compressedFile = File(compressed.path);
      final compressedSize = await compressedFile.length();
      if (compressedSize <= _maxImageBytes) { result = compressedFile; break; }
      quality -= 15;
    }
    return result ?? file;
  }

  // ── Location (identical pattern to the other 3 services) ──────────────

  static const Map<String, String> _androidHeaders = {
    'X-Android-Package': 'com.signagesurgeon.app',
    'X-Android-Cert': 'FF441CA235828F075250E7B23268A62CBDD930B2',
  };

  Future<void> _useSavedAddress() async {
    final saved = await showSavedAddressPicker(context);
    if (saved == null) return;
    setState(() {
      _houseController.text = saved['houseNo'] as String? ?? '';
      _buildingController.text = saved['building'] as String? ?? '';
      _areaController.text = saved['area'] as String? ?? '';
      _landmarkController.text = saved['landmark'] as String? ?? '';
      _cityController.text = saved['city'] as String? ?? '';
      _pincodeController.text = saved['pincode'] as String? ?? '';
      _lat = (saved['lat'] as num?)?.toDouble();
      _lng = (saved['lng'] as num?)?.toDouble();
      _searchController.clear();
      _suggestions = [];
    });
    if (_lat != null && _lng != null) {
      _mapController?.animateCamera(CameraUpdate.newLatLng(LatLng(_lat!, _lng!)));
      _checkCityServiceable();
    }
  }

  Future<void> _useCurrentLocation() async {
    setState(() => _fetchingLocation = true);
    try {
      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.denied || permission == LocationPermission.deniedForever) {
        _showSnack('Location permission denied. Please enable it in settings.');
        setState(() => _fetchingLocation = false);
        return;
      }
      final position = await Geolocator.getCurrentPosition(desiredAccuracy: LocationAccuracy.high);
      await _applyLocation(position.latitude, position.longitude);
    } catch (e) {
      _showSnack('Could not fetch current location. Please try again.');
    } finally {
      if (mounted) setState(() => _fetchingLocation = false);
    }
  }

  Future<void> _applyLocation(double lat, double lng) async {
    setState(() {
      _lat = lat;
      _lng = lng;
      _searchController.clear();
      _suggestions = [];
    });
    _mapController?.animateCamera(CameraUpdate.newLatLng(LatLng(lat, lng)));
    await _reverseGeocodeAndFill(lat, lng);
    _checkCityServiceable();
  }

  Future<void> _reverseGeocodeAndFill(double lat, double lng) async {
    try {
      final uri = Uri.parse('https://maps.googleapis.com/maps/api/geocode/json?latlng=$lat,$lng&key=$_mapsApiKey');
      final response = await http.get(uri, headers: _androidHeaders);
      if (response.statusCode == 200) {
        final json = jsonDecode(response.body);
        final results = json['results'] as List?;
        if (results != null && results.isNotEmpty) _fillFromAddressComponents(results[0]);
      }
    } catch (_) {}
  }

  void _fillFromAddressComponents(Map<String, dynamic> result) {
    final components = result['address_components'] as List? ?? [];
    String streetNumber = '', route = '', sublocality = '', locality = '', postalCode = '';
    for (final c in components) {
      final types = (c['types'] as List).cast<String>();
      final name = c['long_name'] as String;
      if (types.contains('street_number')) streetNumber = name;
      if (types.contains('route')) route = name;
      if (types.contains('sublocality') || types.contains('sublocality_level_1') || types.contains('sublocality_level_2')) {
        if (sublocality.isEmpty) sublocality = name;
      }
      if (types.contains('locality') || types.contains('postal_town') || types.contains('administrative_area_level_2')) {
        if (locality.isEmpty) locality = name;
      }
      if (types.contains('postal_code')) postalCode = name;
    }
    final buildingText = [streetNumber, route].where((e) => e.isNotEmpty).join(' ');
    setState(() {
      if (buildingText.isNotEmpty) _buildingController.text = buildingText;
      if (sublocality.isNotEmpty) _areaController.text = sublocality;
      if (locality.isNotEmpty) _cityController.text = locality;
      if (postalCode.isNotEmpty) _pincodeController.text = postalCode;
    });
  }

  Future<void> _onSearchChanged(String query) async {
    if (query.trim().length < 3) {
      setState(() => _suggestions = []);
      return;
    }
    setState(() => _searching = true);
    try {
      final uri = Uri.parse('https://places.googleapis.com/v1/places:autocomplete');
      final response = await http.post(
        uri,
        headers: {'Content-Type': 'application/json', 'X-Goog-Api-Key': _mapsApiKey, ..._androidHeaders},
        body: jsonEncode({'input': query, 'includedRegionCodes': ['in']}),
      );
      if (response.statusCode == 200) {
        final json = jsonDecode(response.body);
        final suggestions = json['suggestions'] as List? ?? [];
        setState(() {
          _suggestions = suggestions
              .where((s) => s['placePrediction'] != null)
              .map<Map<String, String>>((s) {
                final pred = s['placePrediction'];
                return {'description': pred['text']['text'] as String, 'place_id': pred['placeId'] as String};
              })
              .toList();
        });
      }
    } catch (_) {
    } finally {
      if (mounted) setState(() => _searching = false);
    }
  }

  Future<void> _selectSuggestion(Map<String, String> suggestion) async {
    try {
      final placeId = suggestion['place_id'];
      final uri = Uri.parse('https://places.googleapis.com/v1/places/$placeId');
      final response = await http.get(
        uri,
        headers: {'X-Goog-Api-Key': _mapsApiKey, 'X-Goog-FieldMask': 'formattedAddress,location,addressComponents', ..._androidHeaders},
      );
      if (response.statusCode == 200) {
        final result = jsonDecode(response.body);
        final loc = result['location'];
        final lat = (loc['latitude'] as num).toDouble();
        final lng = (loc['longitude'] as num).toDouble();
        setState(() {
          _lat = lat;
          _lng = lng;
          _searchController.clear();
          _suggestions = [];
        });
        _mapController?.animateCamera(CameraUpdate.newLatLng(LatLng(lat, lng)));
        _fillFromNewApiAddressComponents(result);
        _checkCityServiceable();
      }
    } catch (_) {
      _showSnack('Could not fetch location details. Please try again.');
    }
  }

  void _fillFromNewApiAddressComponents(Map<String, dynamic> result) {
    final components = result['addressComponents'] as List? ?? [];
    String streetNumber = '', route = '', sublocality = '', locality = '', postalCode = '';
    for (final c in components) {
      final types = (c['types'] as List).cast<String>();
      final name = c['longText'] as String? ?? '';
      if (types.contains('street_number')) streetNumber = name;
      if (types.contains('route')) route = name;
      if (types.contains('sublocality') || types.contains('sublocality_level_1') || types.contains('sublocality_level_2')) {
        if (sublocality.isEmpty) sublocality = name;
      }
      if (types.contains('locality') || types.contains('postal_town') || types.contains('administrative_area_level_2')) {
        if (locality.isEmpty) locality = name;
      }
      if (types.contains('postal_code')) postalCode = name;
    }
    final buildingText = [streetNumber, route].where((e) => e.isNotEmpty).join(' ');
    setState(() {
      if (buildingText.isNotEmpty) _buildingController.text = buildingText;
      if (sublocality.isNotEmpty) _areaController.text = sublocality;
      if (locality.isNotEmpty) _cityController.text = locality;
      if (postalCode.isNotEmpty) _pincodeController.text = postalCode;
    });
  }

  bool _isCityServiceable(String city) {
    final normalized = city.trim().toLowerCase();
    if (normalized.isEmpty) return false;
    return _serviceableCities.any((c) => c.trim().toLowerCase() == normalized);
  }

  void _checkCityServiceable() {
    setState(() => _cityUnavailable = !_isCityServiceable(_cityController.text));
  }

  // ── Submit (no fee, no payment — per Founder doc) ──────────────────────

  bool get _canSubmit =>
      !_cityUnavailable &&
      _signageType != null &&
      _quantity != null &&
      _approxSize != null &&
      _installationHeight != null &&
      _accessEquipment != null &&
      _illumination != null &&
      _installationArea != null &&
      _filledPhotoCount >= 3 &&
      _houseController.text.trim().isNotEmpty &&
      _areaController.text.trim().isNotEmpty &&
      _lat != null &&
      _lng != null;

  Future<void> _onSubmitPressed() async {
    if (!_canSubmit) {
      _showSnack('Please complete all required fields and select 3 to 5 photos.');
      return;
    }
    setState(() => _submitting = true);
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) throw Exception('Not logged in');

      final requestId = FirebaseFirestore.instance.collection('cleaning_requests').doc().id;
      final photoUrls = await _uploadPhotos(requestId);

      await FirebaseFirestore.instance.collection('cleaning_requests').doc(requestId).set({
        'userId': user.uid,
        'createdAt': FieldValue.serverTimestamp(),
        'cleaningPhase': 'awaiting_quotation',
        'signageType': _effectiveSignageType,
        'signageQuantity': _quantity,
        'approximateSize': _approxSize,
        'installationHeight': _installationHeight,
        'accessEquipment': _accessEquipment,
        'illumination': _illumination,
        'installationArea': _effectiveInstallationArea,
        'photoUrls': photoUrls,
        'location': {
          'houseNo': _houseController.text.trim(),
          'building': _buildingController.text.trim(),
          'area': _areaController.text.trim(),
          'landmark': _landmarkController.text.trim(),
          'city': _cityController.text.trim(),
          'pincode': _pincodeController.text.trim(),
          'address': _mergedAddress,
          'lat': _lat,
          'lng': _lng,
        },
        'quotation': null,
      });

      if (mounted) {
        setState(() => _submitting = false);
        Navigator.pushReplacementNamed(context, AppRoutes.cleaningTracking, arguments: requestId);
      }
    } catch (e) {
      _showSnack('Something went wrong submitting your request. Please try again.');
      setState(() => _submitting = false);
    }
  }

  Future<List<String>> _uploadPhotos(String requestId) async {
    final urls = <String>[];
    for (int i = 0; i < 4; i++) {
      final file = _photoSlots[i];
      if (file == null) continue;
      final compressed = await _compressImageIfNeeded(file);
      final ref = FirebaseStorage.instance.ref('cleaning_requests/$requestId/photo_$i.jpg');
      await ref.putFile(compressed);
      urls.add(await ref.getDownloadURL());
    }
    for (int i = 0; i < _extraPhotos.length; i++) {
      final compressed = await _compressImageIfNeeded(_extraPhotos[i]);
      final ref = FirebaseStorage.instance.ref('cleaning_requests/$requestId/extra_$i.jpg');
      await ref.putFile(compressed);
      urls.add(await ref.getDownloadURL());
    }
    return urls;
  }

  void _showSnack(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(backgroundColor: AppColors.red, content: Text(message, style: const TextStyle(color: Colors.white))),
    );
  }

  // ── Build ──────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.offWhite,
      appBar: _buildAppBar(),
      body: Theme(
        data: Theme.of(context).copyWith(
          inputDecorationTheme: const InputDecorationTheme(
            filled: true, fillColor: AppColors.white,
            border: InputBorder.none, enabledBorder: InputBorder.none,
            focusedBorder: InputBorder.none, errorBorder: InputBorder.none,
            disabledBorder: InputBorder.none,
          ),
        ),
        child: Form(
          key: _formKey,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(20, 20, 20, 20),
            children: [
              _sectionLabel('1. Signage Type'),
              const SizedBox(height: 10),
              _buildDropdown(_signageType, _signageTypes, 'What type of signage needs cleaning?', (v) => setState(() => _signageType = v)),
              if (_isOther(_signageType)) _otherField(_signageTypeOtherController, 'Please specify'),
              const SizedBox(height: 24),

              _sectionLabel('2. Signage Quantity'),
              const SizedBox(height: 10),
              _buildDropdown(_quantity, _quantityOptions, 'Approximately how many signages?', (v) => setState(() => _quantity = v)),
              const SizedBox(height: 24),

              _sectionLabel('3. Approximate Size'),
              const SizedBox(height: 10),
              _buildDropdown(_approxSize, _sizeOptions, 'Approximately what is the signage size?', (v) => setState(() => _approxSize = v)),
              const SizedBox(height: 24),

              _sectionLabel('4. Installation Height'),
              const SizedBox(height: 10),
              _buildDropdown(_installationHeight, _heightOptions, 'At what height is the signage installed?', (v) => setState(() => _installationHeight = v)),
              const SizedBox(height: 24),

              _sectionLabel('Access Equipment'),
              const SizedBox(height: 6),
              _buildNote('Required for cleaning at height — please select one'),
              const SizedBox(height: 10),
              _buildAccessEquipmentSelector(),
              if (_accessEquipment == 'not_needed') ...[
                const SizedBox(height: 10),
                _buildAccessEquipmentDisclaimer(),
              ],
              const SizedBox(height: 24),

              _sectionLabel('5. Signage Photos (3–5 required)'),
              const SizedBox(height: 6),
              _buildNote('Full Signage, Front View, Close-up, Wider Area — minimum 3, maximum 5'),
              const SizedBox(height: 10),
              _buildPhotoGrid(),
              const SizedBox(height: 24),

              _sectionLabel('6. Illumination'),
              const SizedBox(height: 10),
              _buildDropdown(_illumination, _illuminationOptions, 'Is the signage illuminated / lighted?', (v) => setState(() => _illumination = v)),
              const SizedBox(height: 24),

              _sectionLabel('7. Installation Area'),
              const SizedBox(height: 10),
              _buildDropdown(_installationArea, _installationAreas, 'Where is the signage installed?', (v) => setState(() => _installationArea = v)),
              if (_isOther(_installationArea)) _otherField(_installationAreaOtherController, 'Please specify'),
              const SizedBox(height: 24),

              _sectionLabel('8. Service Location'),
              const SizedBox(height: 10),
              _buildLocationSection(),
              const SizedBox(height: 24),

              if (_cityUnavailable) _buildCityUnavailableCard(),
              const SizedBox(height: 12),

              _buildSubmitButton(),
              const SizedBox(height: 8),
              const Text(
                'No payment is required now. Our team will review your request and send a quotation.',
                textAlign: TextAlign.center,
                style: TextStyle(color: AppColors.grey, fontSize: 11.5, height: 1.4),
              ),
              const SizedBox(height: 30),
            ],
          ),
        ),
      ),
    );
  }

  PreferredSizeWidget _buildAppBar() {
    return AppBar(
      backgroundColor: AppColors.serviceAccent,
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
      title: const Text('Signage Cleaning Request', style: TextStyle(color: AppColors.navy, fontSize: 16, fontWeight: FontWeight.w700)),
    );
  }

  Widget _sectionLabel(String label) {
    return Row(
      children: [
        Container(width: 3, height: 16, decoration: BoxDecoration(color: AppColors.serviceAccent, borderRadius: BorderRadius.circular(2))),
        const SizedBox(width: 8),
        Expanded(child: Text(label, style: const TextStyle(color: AppColors.navy, fontSize: 14, fontWeight: FontWeight.w700))),
      ],
    );
  }

  Widget _buildNote(String text) {
    return Row(
      children: [
        const Icon(Icons.info_outline, color: AppColors.grey, size: 13),
        const SizedBox(width: 6),
        Expanded(child: Text(text, style: const TextStyle(color: AppColors.grey, fontSize: 11))),
      ],
    );
  }

  Widget _buildAccessEquipmentSelector() {
    final options = [
      {'value': 'ladder', 'label': 'Ladder', 'icon': Icons.stairs_outlined, 'fee': _ladderFeeDisplay},
      {'value': 'h_frame', 'label': 'H-Frame (Palak)', 'icon': Icons.window_outlined, 'fee': _hFrameFeeDisplay},
      {'value': 'not_needed', 'label': 'Not Needed', 'icon': Icons.block_outlined, 'fee': null},
    ];
    return Column(
      children: options.map((opt) {
        final selected = _accessEquipment == opt['value'];
        final fee = opt['fee'] as double?;
        final label = fee != null ? '${opt['label']} — ₹${fee.toStringAsFixed(0)}' : opt['label'] as String;
        return Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: GestureDetector(
            onTap: () => setState(() => _accessEquipment = opt['value'] as String),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              decoration: BoxDecoration(
                color: selected ? AppColors.serviceAccent.withOpacity(0.12) : AppColors.white,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: selected ? AppColors.serviceAccent : AppColors.cardBorder, width: selected ? 1.5 : 1),
              ),
              child: Row(
                children: [
                  Icon(opt['icon'] as IconData, color: selected ? AppColors.serviceAccent : AppColors.grey, size: 20),
                  const SizedBox(width: 12),
                  Expanded(child: Text(label, style: TextStyle(color: AppColors.navy, fontSize: 14, fontWeight: selected ? FontWeight.w700 : FontWeight.w500))),
                  Icon(selected ? Icons.radio_button_checked : Icons.radio_button_unchecked, color: selected ? AppColors.serviceAccent : AppColors.greyLight, size: 20),
                ],
              ),
            ),
          ),
        );
      }).toList(),
    );
  }

  Widget _buildAccessEquipmentDisclaimer() {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(color: const Color(0xFFFFA500).withOpacity(0.1), borderRadius: BorderRadius.circular(10)),
      child: const Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.info_outline, color: Color(0xFFFFA500), size: 18),
          SizedBox(width: 10),
          Expanded(
            child: Text(
              'If access equipment turns out to be required at site and is unavailable, this will be treated as your responsibility — no refund will apply. Our team will wait up to 30 minutes for you to arrange suitable access.',
              style: TextStyle(color: AppColors.navy, fontSize: 11.5, height: 1.4),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDropdown(String? value, List<String> options, String hint, ValueChanged<String?> onChanged) {
    return Container(
      decoration: BoxDecoration(color: AppColors.white, borderRadius: BorderRadius.circular(12), border: Border.all(color: AppColors.cardBorder, width: 1)),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 2),
      child: DropdownButtonFormField<String>(
        value: value,
        dropdownColor: AppColors.white,
        iconEnabledColor: AppColors.serviceAccent,
        isExpanded: true,
        style: const TextStyle(color: AppColors.navy, fontSize: 14),
        hint: Text(hint, style: const TextStyle(color: AppColors.grey, fontSize: 13)),
        decoration: const InputDecoration(filled: true, fillColor: AppColors.white, border: InputBorder.none, contentPadding: EdgeInsets.zero),
        items: options.map((o) => DropdownMenuItem(value: o, child: Text(o, style: const TextStyle(color: AppColors.navy, fontSize: 14)))).toList(),
        onChanged: onChanged,
      ),
    );
  }

  Widget _otherField(TextEditingController controller, String hint) {
    return Padding(
      padding: const EdgeInsets.only(top: 10),
      child: Container(
        decoration: BoxDecoration(color: AppColors.white, borderRadius: BorderRadius.circular(12), border: Border.all(color: AppColors.cardBorder, width: 1)),
        child: TextFormField(
          controller: controller,
          style: const TextStyle(color: AppColors.navy, fontSize: 13.5),
          decoration: InputDecoration(
            filled: true, fillColor: AppColors.white, hintText: hint,
            hintStyle: const TextStyle(color: AppColors.grey, fontSize: 13),
            prefixIcon: const Icon(Icons.edit_outlined, color: AppColors.serviceAccent, size: 18),
            border: InputBorder.none, contentPadding: const EdgeInsets.symmetric(vertical: 14, horizontal: 16),
          ),
        ),
      ),
    );
  }

  // ── Photo grid: 4 named slots + up to 1 extra (max 5 total) ────────────

  Widget _buildPhotoGrid() {
    return Column(
      children: [
        GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: 4,
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: 3, crossAxisSpacing: 10, mainAxisSpacing: 10, childAspectRatio: 0.85),
          itemBuilder: (_, i) {
            final file = _photoSlots[i];
            return _photoTile(file: file, label: _photoSlotLabels[i], onTap: () => _pickPhoto(i), onRemove: () => _removePhoto(i));
          },
        ),
        if (_extraPhotos.isNotEmpty) ...[
          const SizedBox(height: 10),
          GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: _extraPhotos.length,
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: 3, crossAxisSpacing: 10, mainAxisSpacing: 10, childAspectRatio: 0.85),
            itemBuilder: (_, i) => _photoTile(file: _extraPhotos[i], label: 'Extra ${i + 1}', onTap: () {}, onRemove: () => _removeExtraPhoto(i)),
          ),
        ],
        const SizedBox(height: 10),
        SizedBox(
          width: double.infinity,
          child: OutlinedButton.icon(
            onPressed: _canAddMorePhotos ? _pickExtraPhoto : null,
            icon: Icon(Icons.add_photo_alternate_outlined, color: _canAddMorePhotos ? AppColors.serviceAccent : AppColors.greyLight, size: 18),
            label: Text(
              _canAddMorePhotos ? 'Add More Photos ($_filledPhotoCount/5)' : 'Maximum 5 Photos Reached',
              style: TextStyle(color: _canAddMorePhotos ? AppColors.serviceAccent : AppColors.grey, fontWeight: FontWeight.w600),
            ),
            style: OutlinedButton.styleFrom(
              backgroundColor: AppColors.white,
              side: BorderSide(color: _canAddMorePhotos ? AppColors.serviceAccent : AppColors.greyLight, width: 1),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              padding: const EdgeInsets.symmetric(vertical: 12),
            ),
          ),
        ),
      ],
    );
  }

  Widget _photoTile({required File? file, required String label, required VoidCallback onTap, required VoidCallback onRemove}) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        decoration: BoxDecoration(
          color: AppColors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: file != null ? AppColors.serviceAccent : AppColors.cardBorder, width: file != null ? 1.5 : 1),
          boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 6, offset: const Offset(0, 2))],
        ),
        clipBehavior: Clip.antiAlias,
        child: Stack(
          fit: StackFit.expand,
          children: [
            if (file != null)
              Image.file(file, fit: BoxFit.cover)
            else
              Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.add_a_photo_outlined, color: AppColors.grey, size: 22),
                  const SizedBox(height: 6),
                  Padding(padding: const EdgeInsets.symmetric(horizontal: 4), child: Text(label, textAlign: TextAlign.center, style: const TextStyle(color: AppColors.grey, fontSize: 9))),
                ],
              ),
            if (file != null)
              Positioned(
                top: 4, right: 4,
                child: GestureDetector(
                  onTap: onRemove,
                  child: Container(
                    padding: const EdgeInsets.all(3),
                    decoration: const BoxDecoration(color: Colors.black54, shape: BoxShape.circle),
                    child: const Icon(Icons.close, color: Colors.white, size: 14),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  // ── Location section (identical pattern to the other 3 services) ──────

  Widget _buildLocationSection() {
    return Column(
      children: [
        SizedBox(
          width: double.infinity,
          height: 48,
          child: OutlinedButton.icon(
            onPressed: _fetchingLocation ? null : _useCurrentLocation,
            icon: _fetchingLocation
                ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.serviceAccent))
                : const Icon(Icons.my_location, color: AppColors.serviceAccent, size: 18),
            label: Text(_fetchingLocation ? 'Fetching location...' : 'Use Current Location', style: const TextStyle(color: AppColors.serviceAccent, fontWeight: FontWeight.w600)),
            style: OutlinedButton.styleFrom(backgroundColor: AppColors.white, side: const BorderSide(color: AppColors.serviceAccent, width: 1), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
          ),
        ),
        const SizedBox(height: 10),
        SizedBox(
          width: double.infinity,
          height: 48,
          child: OutlinedButton.icon(
            onPressed: _useSavedAddress,
            icon: const Icon(Icons.bookmark_outline, color: AppColors.serviceAccent, size: 18),
            label: const Text('Use Saved Address', style: TextStyle(color: AppColors.serviceAccent, fontWeight: FontWeight.w600)),
            style: OutlinedButton.styleFrom(backgroundColor: AppColors.white, side: const BorderSide(color: AppColors.serviceAccent, width: 1), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
          ),
        ),
        const SizedBox(height: 14),
        const Align(alignment: Alignment.centerLeft, child: Text('OR SEARCH', style: TextStyle(color: AppColors.grey, fontSize: 11, fontWeight: FontWeight.w600))),
        const SizedBox(height: 10),
        Container(
          decoration: BoxDecoration(color: AppColors.white, borderRadius: BorderRadius.circular(12), border: Border.all(color: AppColors.cardBorder, width: 1)),
          child: TextFormField(
            controller: _searchController,
            style: const TextStyle(color: AppColors.navy, fontSize: 14),
            onChanged: _onSearchChanged,
            decoration: InputDecoration(
              filled: true, fillColor: AppColors.white, hintText: 'Search for your address',
              hintStyle: const TextStyle(color: AppColors.grey, fontSize: 13),
              prefixIcon: const Icon(Icons.search, color: AppColors.serviceAccent, size: 18),
              suffixIcon: _searching ? const Padding(padding: EdgeInsets.all(14), child: SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.serviceAccent))) : null,
              border: InputBorder.none, contentPadding: const EdgeInsets.symmetric(vertical: 14, horizontal: 16),
            ),
          ),
        ),
        if (_suggestions.isNotEmpty)
          Container(
            margin: const EdgeInsets.only(top: 6),
            decoration: BoxDecoration(color: AppColors.white, borderRadius: BorderRadius.circular(12), border: Border.all(color: AppColors.cardBorder, width: 1), boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.06), blurRadius: 8, offset: const Offset(0, 3))]),
            clipBehavior: Clip.antiAlias,
            child: Material(
              color: Colors.transparent,
              child: Column(
                children: _suggestions
                    .map((s) => ListTile(
                          dense: true,
                          leading: const Icon(Icons.location_on_outlined, color: AppColors.serviceAccent, size: 18),
                          title: Text(s['description'] ?? '', style: const TextStyle(color: AppColors.navy, fontSize: 12.5)),
                          onTap: () => _selectSuggestion(s),
                        ))
                    .toList(),
              ),
            ),
          ),

        const SizedBox(height: 16),
        ClipRRect(
          borderRadius: BorderRadius.circular(14),
          child: SizedBox(
            height: 220,
            child: GoogleMap(
              initialCameraPosition: CameraPosition(target: LatLng(_lat ?? _defaultMapLat, _lng ?? _defaultMapLng), zoom: _lat != null ? 16 : 12),
              onMapCreated: (c) => _mapController = c,
              markers: _lat != null && _lng != null ? {Marker(markerId: const MarkerId('selected'), position: LatLng(_lat!, _lng!))} : {},
              zoomControlsEnabled: true, myLocationButtonEnabled: false,
              scrollGesturesEnabled: true, zoomGesturesEnabled: true, rotateGesturesEnabled: true, tiltGesturesEnabled: true,
            ),
          ),
        ),

        const SizedBox(height: 18),
        const Align(alignment: Alignment.centerLeft, child: Text('No saved addresses yet — save one from your Account page for next time.', style: TextStyle(color: AppColors.grey, fontSize: 11))),
        const SizedBox(height: 12),

        _addressField(controller: _houseController, hint: 'House / Shop No. *', icon: Icons.home_outlined),
        const SizedBox(height: 10),
        _addressField(controller: _buildingController, hint: 'Building / Society Name', icon: Icons.apartment_outlined),
        const SizedBox(height: 10),
        _addressField(controller: _areaController, hint: 'Area *', icon: Icons.map_outlined),
        const SizedBox(height: 10),
        _addressField(controller: _landmarkController, hint: 'Landmark (optional)', icon: Icons.flag_outlined),
        const SizedBox(height: 10),
        Row(
          children: [
            Expanded(child: _addressField(
              controller: _cityController, hint: 'City', icon: Icons.location_city_outlined,
              onChanged: (_) {
                _cityDebounce?.cancel();
                _cityDebounce = Timer(const Duration(milliseconds: 700), _checkCityServiceable);
              },
            )),
            const SizedBox(width: 10),
            Expanded(child: _addressField(controller: _pincodeController, hint: 'Pincode', icon: Icons.pin_drop_outlined, keyboardType: TextInputType.number)),
          ],
        ),
      ],
    );
  }

  Widget _addressField({required TextEditingController controller, required String hint, required IconData icon, TextInputType keyboardType = TextInputType.text, ValueChanged<String>? onChanged}) {
    return Container(
      decoration: BoxDecoration(color: AppColors.white, borderRadius: BorderRadius.circular(12), border: Border.all(color: AppColors.cardBorder, width: 1)),
      child: TextFormField(
        controller: controller,
        keyboardType: keyboardType,
        onChanged: (v) {
          setState(() {});
          onChanged?.call(v);
        },
        style: const TextStyle(color: AppColors.navy, fontSize: 13.5),
        decoration: InputDecoration(
          filled: true, fillColor: AppColors.white, hintText: hint,
          hintStyle: const TextStyle(color: AppColors.grey, fontSize: 13),
          prefixIcon: Icon(icon, color: AppColors.serviceAccent, size: 18),
          border: InputBorder.none, contentPadding: const EdgeInsets.symmetric(vertical: 14, horizontal: 16),
        ),
      ),
    );
  }

  Widget _buildCityUnavailableCard() {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(color: AppColors.white, borderRadius: BorderRadius.circular(14), border: Border.all(color: const Color(0xFFFFA500), width: 1)),
      child: Row(
        children: [
          const Icon(Icons.location_off_outlined, color: Color(0xFFFFA500), size: 22),
          const SizedBox(width: 12),
          Expanded(child: Text('We\'re not available in ${_cityController.text.trim().isEmpty ? 'this city' : _cityController.text.trim()} yet — coming soon! Currently serving ${_serviceableCities.join(', ')}.', style: const TextStyle(color: AppColors.navy, fontSize: 12.5, height: 1.4, fontWeight: FontWeight.w600))),
        ],
      ),
    );
  }

  Widget _buildSubmitButton() {
    return SizedBox(
      width: double.infinity,
      height: 54,
      child: ElevatedButton(
        onPressed: (_canSubmit && !_submitting) ? _onSubmitPressed : null,
        style: ElevatedButton.styleFrom(backgroundColor: AppColors.yellow, disabledBackgroundColor: AppColors.greyLight, foregroundColor: AppColors.navy, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)), elevation: 2),
        child: _submitting
            ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.navy))
            : const Text('SUBMIT CLEANING REQUEST', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800, letterSpacing: 0.5)),
      ),
    );
  }
}