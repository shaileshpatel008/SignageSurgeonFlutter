import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';
import 'package:flutter_image_compress/flutter_image_compress.dart';
import 'package:video_compress/video_compress.dart';
import 'package:geolocator/geolocator.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:razorpay_flutter/razorpay_flutter.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/saved_address_picker.dart';
import '../../../core/services/distance_fee_service.dart';

class RebrandingRequestScreen extends StatefulWidget {
  const RebrandingRequestScreen({super.key});

  @override
  State<RebrandingRequestScreen> createState() => _RebrandingRequestScreenState();
}

class _RebrandingRequestScreenState extends State<RebrandingRequestScreen> {
  final _razorpay = Razorpay();
  static const String _razorpayKeyId = 'rzp_test_TXYmAiGUXZQb0r';
  static const String _mapsApiKey = 'AIzaSyD8v_obWHOLaRYIlSL2vlOjlSYFChOEvmE';

  // ── Options (from Founder Input Master Doc 02) ───────────────────────────
  static const List<String> _locationTypes = [
    'Shop / Showroom', 'Corporate Office', 'Commercial Building',
    'Mall / Retail Outlet', 'Hospital / Healthcare', 'Hotel / Restaurant',
    'School / College', 'Factory / Industrial Unit', 'Warehouse',
    'Petrol Pump', 'Bank / Financial Branch', 'Multiple Branches / Locations',
    'Other',
  ];

  static const List<String> _rebrandingRequirements = [
    'Complete Signage', 'Brand Name / Letters', 'Logo', 'Fascia / ACP',
    'Indoor Signage', 'Directional Signage', 'Safety Signage',
    'Reception / Office Branding', 'Multiple Signages',
    'Complete Location / Branch Rebranding', 'Other / Not Sure',
  ];

  static const List<String> _existingAreas = [
    'Building Front / Fascia', 'Main Entrance', 'Reception Area',
    'Indoor Wall', 'Shop / Showroom Front', 'Rooftop', 'Pylon / Totem',
    'Parking Area', 'Directional Area', 'Factory / Industrial Premises',
    'Multiple Areas', 'Other / Not Sure',
  ];

  static const List<String> _existingMaterials = [
    'Acrylic', 'ACP', 'Stainless Steel / SS', 'Metal / MS', 'Aluminium',
    'Flex', 'Vinyl', 'LED / Illuminated Signage', 'Neon / LED Neon',
    'Glass', 'Wood / MDF', 'Multiple Materials', 'Not Sure', 'Other',
  ];

  static const List<String> _illuminationOptions = [
    'Yes — Fully Illuminated', 'Yes — Partially Illuminated',
    'No — Non-Illuminated', 'Multiple Signages with Different Types',
    'Not Sure',
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

  static const List<String> _preferredMaterials = [
    'Acrylic', 'ACP', 'Stainless Steel / SS', 'Metal / MS', 'Aluminium',
    'Flex', 'Vinyl', 'LED / Illuminated Signage', 'Neon / LED Neon',
    'Glass', 'Wood / MDF', 'Multiple Materials', 'Need Expert Recommendation',
    'Not Sure', 'Other',
  ];

  static const List<String> _artworkStatusOptions = [
    'Yes — Logo / Artwork Ready', 'Yes — Brand Guidelines Available',
    'Partially Ready', 'No — Need Design Support',
  ];

  static const List<String> _photoSlotLabels = [
    'Full Signage / Branding Area', 'Front View', 'Close-up View', 'Side / Installation View',
  ];

  // ── Form state ─────────────────────────────────────────────────────────
  final _formKey = GlobalKey<FormState>();
  String? _locationType;
  String? _rebrandingRequirement;
  String? _existingArea;
  String? _existingMaterial;
  String? _illumination;
  String? _existingSize;
  String? _installationHeight;
  String? _accessEquipment; // 'ladder' | 'h_frame' | 'not_needed' — compulsory
  double? _equipmentTransportCharge;
  double? _equipmentFee;
  double? _equipmentTransportGst;
  bool _loadingTransportRate = false;
  String? _transportChargeError;
  String? _preferredMaterial;
  String? _artworkStatus;

  final _locationTypeOtherController = TextEditingController();
  final _rebrandingRequirementOtherController = TextEditingController();
  final _existingAreaOtherController = TextEditingController();
  final _existingMaterialOtherController = TextEditingController();
  final _preferredMaterialOtherController = TextEditingController();

  final Map<int, File?> _photoSlots = {0: null, 1: null, 2: null, 3: null};
  final List<File> _extraPhotos = [];
  File? _videoFile;

  // Location — broken-out editable fields (same pattern as Repairing)
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

  // Fee
  bool _calculatingFee = false;
  DistanceFeeResult? _feeResult;
  bool _cityUnavailable = false;
  List<String> _serviceableCities = ['Ahmedabad', 'Gandhinagar'];
  Timer? _cityDebounce;

  // Submission
  bool _submitting = false;
  List<String> _uploadedPhotoUrls = [];
  String? _uploadedVideoUrl;
  String? _pendingRequestId;

  @override
  void initState() {
    super.initState();
    _razorpay.on(Razorpay.EVENT_PAYMENT_SUCCESS, _onPaymentSuccess);
    _razorpay.on(Razorpay.EVENT_PAYMENT_ERROR, _onPaymentError);
    _razorpay.on(Razorpay.EVENT_EXTERNAL_WALLET, (_) {});
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
    _locationTypeOtherController.dispose();
    _rebrandingRequirementOtherController.dispose();
    _existingAreaOtherController.dispose();
    _existingMaterialOtherController.dispose();
    _preferredMaterialOtherController.dispose();
    _houseController.dispose();
    _buildingController.dispose();
    _areaController.dispose();
    _landmarkController.dispose();
    _cityController.dispose();
    _pincodeController.dispose();
    _searchController.dispose();
    _razorpay.clear();
    super.dispose();
  }

  bool _isOther(String? value) => value != null && value.toLowerCase().contains('other');

  String? get _effectiveLocationType =>
      (_isOther(_locationType) && _locationTypeOtherController.text.trim().isNotEmpty)
          ? _locationTypeOtherController.text.trim() : _locationType;
  String? get _effectiveRebrandingRequirement =>
      (_isOther(_rebrandingRequirement) && _rebrandingRequirementOtherController.text.trim().isNotEmpty)
          ? _rebrandingRequirementOtherController.text.trim() : _rebrandingRequirement;
  String? get _effectiveExistingArea =>
      (_isOther(_existingArea) && _existingAreaOtherController.text.trim().isNotEmpty)
          ? _existingAreaOtherController.text.trim() : _existingArea;
  String? get _effectiveExistingMaterial =>
      (_isOther(_existingMaterial) && _existingMaterialOtherController.text.trim().isNotEmpty)
          ? _existingMaterialOtherController.text.trim() : _existingMaterial;
  String? get _effectivePreferredMaterial =>
      (_isOther(_preferredMaterial) && _preferredMaterialOtherController.text.trim().isNotEmpty)
          ? _preferredMaterialOtherController.text.trim() : _preferredMaterial;

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

  // ── Photo picking ─────────────────────────────────────────────────────

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
    final file = await _pickImage();
    if (file == null) return;
    setState(() => _extraPhotos.add(file));
  }

  void _removePhoto(int slotIndex) => setState(() => _photoSlots[slotIndex] = null);
  void _removeExtraPhoto(int index) => setState(() => _extraPhotos.removeAt(index));

  int get _filledPhotoCount => _photoSlots.values.where((f) => f != null).length + _extraPhotos.length;

  // ── Video picking (optional) ────────────────────────────────────────

  Future<void> _pickVideo() async {
    final picker = ImagePicker();
    final picked = await picker.pickVideo(source: ImageSource.gallery, maxDuration: const Duration(minutes: 3));
    if (picked == null) return;
    setState(() => _videoFile = File(picked.path));
  }

  void _removeVideo() => setState(() => _videoFile = null);

  static const int _maxVideoBytes = 10 * 1024 * 1024;

  Future<File> _compressVideoIfNeeded(File file) async {
    final size = await file.length();
    if (size <= _maxVideoBytes) return file;
    final info = await VideoCompress.compressVideo(file.path, quality: VideoQuality.LowQuality, deleteOrigin: false, includeAudio: true);
    if (info?.file != null) {
      final compressedSize = await info!.file!.length();
      if (compressedSize <= _maxVideoBytes) return info.file!;
    }
    return info?.file ?? file;
  }

  // ── Compression ────────────────────────────────────────────────────────

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

  // ── Location: current position ───────────────────────────────────────

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
      await _calculateFee();
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
    await _calculateFee();
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

  // ── Location: search / autocomplete (Places API New) ──────────────────

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
        await _calculateFee();
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

  // ── Fee calculation ──────────────────────────────────────────────────

  bool _isCityServiceable(String city) {
    final normalized = city.trim().toLowerCase();
    if (normalized.isEmpty) return false;
    return _serviceableCities.any((c) => c.trim().toLowerCase() == normalized);
  }

  Future<void> _calculateFee() async {
    if (_lat == null || _lng == null) return;

    final city = _cityController.text;
    if (!_isCityServiceable(city)) {
      setState(() {
        _cityUnavailable = true;
        _feeResult = null;
        _calculatingFee = false;
      });
      return;
    }

    setState(() {
      _cityUnavailable = false;
      _calculatingFee = true;
      _feeResult = null;
    });
    try {
      final km = await DistanceFeeService.getRoadDistanceKm(destLat: _lat!, destLng: _lng!);
      final fee = await DistanceFeeService.calculateFee(km, serviceType: 'rebranding');
      setState(() => _feeResult = fee);
      await _updateEquipmentTransportCharge();
    } catch (_) {
      _showSnack('Could not calculate site visit fee. Please try again.');
    } finally {
      if (mounted) setState(() => _calculatingFee = false);
    }
  }

  /// Recomputes the equipment transport charge (Ladder/H-Frame) using the
  /// global per-km rate multiplied by the distance already calculated above.
  Future<void> _updateEquipmentTransportCharge() async {
    if (_feeResult == null || (_accessEquipment != 'ladder' && _accessEquipment != 'h_frame')) {
      setState(() {
        _equipmentTransportCharge = null;
        _equipmentTransportGst = null;
        _equipmentFee = null;
        _transportChargeError = null;
      });
      return;
    }
    setState(() => _loadingTransportRate = true);
    try {
      final doc = await FirebaseFirestore.instance
          .collection('app_settings')
          .doc('pricing_config')
          .get()
          .timeout(const Duration(seconds: 12));
      final rate = (doc.data()?['transportPerKmRate'] as num?)?.toDouble();
      final equipmentFee = _accessEquipment == 'h_frame'
          ? (doc.data()?['hFrameEquipmentFee'] as num?)?.toDouble()
          : (doc.data()?['ladderEquipmentFee'] as num?)?.toDouble();
      if ((rate == null || rate <= 0) && equipmentFee == null) {
        setState(() {
          _equipmentTransportCharge = null;
          _equipmentTransportGst = null;
          _equipmentFee = null;
          _transportChargeError = 'No equipment pricing configured (app_settings/pricing_config missing ladderEquipmentFee/hFrameEquipmentFee/transportPerKmRate)';
        });
        return;
      }
      final charge = (rate != null && rate > 0) ? rate * _feeResult!.distanceKm : null;
      setState(() {
        _equipmentFee = equipmentFee;
        if (charge != null) {
          _equipmentTransportCharge = charge;
          _equipmentTransportGst = charge * 0.18;
        }
        _transportChargeError = null;
      });
    } catch (e) {
      setState(() {
        _equipmentTransportCharge = null;
        _equipmentTransportGst = null;
        _equipmentFee = null;
        _transportChargeError = 'Transport charge failed: $e';
      });
    } finally {
      if (mounted) setState(() => _loadingTransportRate = false);
    }
  }

  double get _equipmentTransportTotal {
    final base = (_equipmentFee ?? 0) + (_equipmentTransportCharge ?? 0);
    if (base <= 0) return 0;
    return base + (base * 0.18);
  }

  // ── Submit / Payment ──────────────────────────────────────────────────

  bool get _canSubmit =>
      !_cityUnavailable &&
      _locationType != null &&
      _rebrandingRequirement != null &&
      _existingArea != null &&
      _existingMaterial != null &&
      _illumination != null &&
      _existingSize != null &&
      _installationHeight != null &&
      _accessEquipment != null &&
      _filledPhotoCount >= 2 &&
      _preferredMaterial != null &&
      _artworkStatus != null &&
      _houseController.text.trim().isNotEmpty &&
      _areaController.text.trim().isNotEmpty &&
      _lat != null &&
      _lng != null &&
      _feeResult != null &&
      _feeResult!.status != FeeStatus.configMissing;

  Future<void> _onSubmitPressed() async {
    if (!_canSubmit) {
      _showSnack('Please complete all required fields and select at least 2 photos.');
      return;
    }
    if (_feeResult!.status == FeeStatus.beyondRange) {
      await _saveInquiryOnly();
      return;
    }
    setState(() => _submitting = true);
    try {
      if (_uploadedPhotoUrls.isEmpty) await _uploadMedia();
      _openRazorpayCheckout();
    } catch (e, st) {
      // ignore: avoid_print
      print('Submit preparation error: $e');
      // ignore: avoid_print
      print(st);
      _showSnack('Something went wrong preparing your request. Please try again.');
      setState(() => _submitting = false);
    }
  }

  Future<void> _uploadMedia() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) throw Exception('Not logged in');
    _pendingRequestId ??= FirebaseFirestore.instance.collection('rebranding_requests').doc().id;
    final requestId = _pendingRequestId!;
    final List<String> urls = [];

    for (int i = 0; i < 4; i++) {
      final file = _photoSlots[i];
      if (file == null) continue;
      final compressed = await _compressImageIfNeeded(file);
      final ref = FirebaseStorage.instance.ref('rebranding_requests/$requestId/photo_$i.jpg');
      await ref.putFile(compressed);
      urls.add(await ref.getDownloadURL());
    }
    for (int i = 0; i < _extraPhotos.length; i++) {
      final compressed = await _compressImageIfNeeded(_extraPhotos[i]);
      final ref = FirebaseStorage.instance.ref('rebranding_requests/$requestId/extra_$i.jpg');
      await ref.putFile(compressed);
      urls.add(await ref.getDownloadURL());
    }
    _uploadedPhotoUrls = urls;

    if (_videoFile != null) {
      final compressedVideo = await _compressVideoIfNeeded(_videoFile!);
      final ref = FirebaseStorage.instance.ref('rebranding_requests/$requestId/video.mp4');
      await ref.putFile(compressedVideo);
      _uploadedVideoUrl = await ref.getDownloadURL();
    }
  }

  void _openRazorpayCheckout() {
    final combinedSubtotal = _feeResult!.siteVisitFee + (_equipmentFee ?? 0) + (_equipmentTransportCharge ?? 0);
    final amountPaise = ((combinedSubtotal + combinedSubtotal * (_feeResult!.gstPercent / 100)) * 100).round();
    final options = {
      'key': _razorpayKeyId,
      'amount': amountPaise,
      'currency': 'INR',
      'name': 'The Signage Surgeon',
      'description': 'Site Visit & Assessment Fee - Rebranding Request',
      'prefill': {'contact': FirebaseAuth.instance.currentUser?.phoneNumber ?? ''},
      'theme': {'color': '#F5C300'},
    };
    try {
      _razorpay.open(options);
    } catch (e) {
      _showSnack('Could not open payment screen. Please try again.');
      setState(() => _submitting = false);
    }
  }

  String _generateOtp() {
    final rand = Random();
    return (1000 + rand.nextInt(9000)).toString();
  }

  Map<String, dynamic> _baseRequestData() {
    return {
      'signageType': _effectiveRebrandingRequirement, // used generically by My Requests / tracking card
      'locationType': _effectiveLocationType,
      'rebrandingRequirement': _effectiveRebrandingRequirement,
      'existingArea': _effectiveExistingArea,
      'existingMaterial': _effectiveExistingMaterial,
      'illumination': _illumination,
      'existingSize': _existingSize,
      'installationHeight': _installationHeight,
        'accessEquipment': _accessEquipment,
      'preferredMaterial': _effectivePreferredMaterial,
      'artworkStatus': _artworkStatus,
      'photoUrls': _uploadedPhotoUrls,
      'videoUrl': _uploadedVideoUrl,
      'issueDescription': '', // kept for cross-service card compatibility
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
    };
  }

  void _onPaymentSuccess(PaymentSuccessResponse response) async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) return;
      final requestId = _pendingRequestId ?? FirebaseFirestore.instance.collection('rebranding_requests').doc().id;
      await FirebaseFirestore.instance.collection('rebranding_requests').doc(requestId).set({
        'userId': user.uid,
        'createdAt': FieldValue.serverTimestamp(),
        'status': 'confirmed',
        'trackingStage': 'submitted',
        'siteVisitArrivalOtp': _generateOtp(),
        'siteVisitCompletionOtp': _generateOtp(),
        'workArrivalOtp': _generateOtp(),
        'workCompletionOtp': _generateOtp(),
        'techName': null, 'visitDate': null, 'visitTimeStart': null, 'visitTimeEnd': null,
        'techName2': null, 'visitDate2': null, 'visitTimeStart2': null, 'visitTimeEnd2': null,
        'completedAt': null,
        ..._baseRequestData(),
        'distanceKm': _feeResult!.distanceKm,
        'appliedSlabId': _feeResult!.slabId,
        'siteVisitFee': _feeResult!.siteVisitFee,
        'gstAmount': _feeResult!.gstAmount,
        'totalPayable': _feeResult!.totalPayable,
        'equipmentTransportCharge': _equipmentTransportCharge,
        'equipmentTransportGst': _equipmentTransportGst,
        'equipmentFee': _equipmentFee,
        'paymentId': response.paymentId,
        'paymentStatus': 'paid',
      });
      if (mounted) {
        setState(() => _submitting = false);
        Navigator.pushReplacementNamed(context, '/request-tracking',
            arguments: {'collection': 'rebranding_requests', 'requestId': requestId});
      }
    } catch (e) {
      _showSnack('Payment succeeded but saving your request failed. Contact support with payment ID: ${response.paymentId}');
      setState(() => _submitting = false);
    }
  }

  void _onPaymentError(PaymentFailureResponse response) {
    setState(() => _submitting = false);
    _showSnack('Payment failed or was cancelled. Your details are saved — tap Pay to retry.');
  }

  Future<void> _saveInquiryOnly() async {
    setState(() => _submitting = true);
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) return;
      await _uploadMedia();
      final requestId = _pendingRequestId ?? FirebaseFirestore.instance.collection('rebranding_requests').doc().id;
      await FirebaseFirestore.instance.collection('rebranding_requests').doc(requestId).set({
        'userId': user.uid,
        'createdAt': FieldValue.serverTimestamp(),
        'status': 'inquiry_pending_contact',
        'trackingStage': 'submitted',
        'siteVisitArrivalOtp': _generateOtp(),
        'siteVisitCompletionOtp': _generateOtp(),
        'workArrivalOtp': _generateOtp(),
        'workCompletionOtp': _generateOtp(),
        'techName': null, 'visitDate': null, 'visitTimeStart': null, 'visitTimeEnd': null,
        'techName2': null, 'visitDate2': null, 'visitTimeStart2': null, 'visitTimeEnd2': null,
        'completedAt': null,
        ..._baseRequestData(),
        'distanceKm': _feeResult!.distanceKm,
        'beyondServiceRange': true,
      });
      if (mounted) {
        setState(() => _submitting = false);
        Navigator.pushReplacementNamed(context, '/request-tracking',
            arguments: {'collection': 'rebranding_requests', 'requestId': requestId});
      }
    } catch (e) {
      _showSnack('Something went wrong. Please try again.');
      setState(() => _submitting = false);
    }
  }

  void _showSnack(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(backgroundColor: AppColors.red, content: Text(message, style: const TextStyle(color: Colors.white))),
    );
  }

  // ── Rate chart ─────────────────────────────────────────────────────────

  Future<void> _showRateChart() async {
    showDialog(
      context: context,
      builder: (_) => Dialog(
        backgroundColor: AppColors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Icon(Icons.receipt_long_outlined, color: AppColors.serviceAccent, size: 22),
                  const SizedBox(width: 10),
                  const Expanded(child: Text('Rebranding Rate Chart', style: TextStyle(color: AppColors.navy, fontSize: 16, fontWeight: FontWeight.w800))),
                  GestureDetector(onTap: () => Navigator.pop(context), child: const Icon(Icons.close, color: AppColors.grey, size: 20)),
                ],
              ),
              const SizedBox(height: 4),
              Text('Serving: ${_serviceableCities.join(', ')}', style: const TextStyle(color: AppColors.grey, fontSize: 11.5)),
              const SizedBox(height: 16),
              FutureBuilder<List<Map<String, dynamic>>>(
                future: _fetchRateChartSlabs(),
                builder: (context, snapshot) {
                  if (snapshot.connectionState == ConnectionState.waiting) {
                    return const Padding(padding: EdgeInsets.symmetric(vertical: 30), child: Center(child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.serviceAccent)));
                  }
                  final slabs = snapshot.data ?? [];
                  if (slabs.isEmpty) {
                    return const Padding(padding: EdgeInsets.symmetric(vertical: 20), child: Text('Rate chart is being updated. Please check back shortly.', style: TextStyle(color: AppColors.grey, fontSize: 12.5)));
                  }
                  return Column(
                    children: [
                      ...slabs.map((s) => _rateChartRow('${s['fromKm']} - ${s['toKm']} km', '₹${s['fee']} + ${s['gstPercent']}% GST')),
                      const Divider(color: AppColors.cardBorder, height: 20),
                      _rateChartRow('Beyond ${slabs.last['toKm']} km (within service city)', 'Team will contact you', highlight: true),
                    ],
                  );
                },
              ),
              const SizedBox(height: 8),
              const Text('Final rebranding cost is quoted separately after assessment. This chart covers the site visit & assessment fee only.',
                  style: TextStyle(color: AppColors.grey, fontSize: 10.5, height: 1.4)),
            ],
          ),
        ),
      ),
    );
  }

  Future<List<Map<String, dynamic>>> _fetchRateChartSlabs() async {
    try {
      final snap = await FirebaseFirestore.instance.collection('visit_fee_slabs').get();
      final rows = snap.docs
          .map((doc) {
            final raw = doc.data();
            final data = <String, dynamic>{for (final e in raw.entries) e.key.trim(): e.value};
            return data;
          })
          .where((d) => d['active'] == null || d['active'] == true)
          .where((d) => (d['serviceType'] as String?)?.trim().toLowerCase() == 'rebranding')
          .where((d) => d['fromKm'] != null && d['toKm'] != null && d['fee'] != null)
          .toList();
      rows.sort((a, b) => (a['fromKm'] as num).compareTo(b['fromKm'] as num));
      return rows;
    } catch (_) {
      return [];
    }
  }

  Widget _rateChartRow(String range, String priceLabel, {bool highlight = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(child: Text(range, style: TextStyle(color: AppColors.navy, fontSize: 13, fontWeight: highlight ? FontWeight.w600 : FontWeight.w500))),
          const SizedBox(width: 10),
          Text(priceLabel, style: TextStyle(color: highlight ? const Color(0xFFFFA500) : AppColors.navy, fontSize: 13, fontWeight: FontWeight.w700)),
        ],
      ),
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
              _sectionLabel('1. Location Type'),
              const SizedBox(height: 10),
              _buildDropdown(_locationType, _locationTypes, 'What type of location requires rebranding?', (v) => setState(() => _locationType = v)),
              if (_isOther(_locationType)) _otherField(_locationTypeOtherController, 'Please specify location type'),
              const SizedBox(height: 24),

              _sectionLabel('2. Rebranding Requirement'),
              const SizedBox(height: 10),
              _buildDropdown(_rebrandingRequirement, _rebrandingRequirements, 'What do you want to rebrand?', (v) => setState(() => _rebrandingRequirement = v)),
              if (_isOther(_rebrandingRequirement)) _otherField(_rebrandingRequirementOtherController, 'Please specify'),
              const SizedBox(height: 24),

              _sectionLabel('3. Existing Signage Installation Area'),
              const SizedBox(height: 10),
              _buildDropdown(_existingArea, _existingAreas, 'Where is the existing signage installed?', (v) => setState(() => _existingArea = v)),
              if (_isOther(_existingArea)) _otherField(_existingAreaOtherController, 'Please specify'),
              const SizedBox(height: 24),

              _sectionLabel('4. Existing Signage Material'),
              const SizedBox(height: 10),
              _buildDropdown(_existingMaterial, _existingMaterials, 'What material is the existing signage made of?', (v) => setState(() => _existingMaterial = v)),
              if (_isOther(_existingMaterial)) _otherField(_existingMaterialOtherController, 'Please specify'),
              const SizedBox(height: 24),

              _sectionLabel('5. Existing Signage Illumination'),
              const SizedBox(height: 10),
              _buildDropdown(_illumination, _illuminationOptions, 'Is the existing signage illuminated?', (v) => setState(() => _illumination = v)),
              const SizedBox(height: 24),

              _sectionLabel('6. Existing Signage Size'),
              const SizedBox(height: 10),
              _buildDropdown(_existingSize, _sizeOptions, 'Approximate size of the existing signage', (v) => setState(() => _existingSize = v)),
              const SizedBox(height: 24),

              _sectionLabel('7. Installation Height'),
              const SizedBox(height: 10),
              _buildDropdown(_installationHeight, _heightOptions, 'At what height is it installed?', (v) => setState(() => _installationHeight = v)),
              const SizedBox(height: 24),

              _sectionLabel('Access Equipment'),
              const SizedBox(height: 6),
              _buildNote('Required for site work at height — please select one'),
              const SizedBox(height: 10),
              _buildAccessEquipmentSelector(),
              if (_accessEquipment == 'not_needed') ...[
                const SizedBox(height: 10),
                _buildAccessEquipmentDisclaimer(),
              ],
              const SizedBox(height: 24),

              _sectionLabel('8. Existing Signage Photos (min. 2 required)'),
              const SizedBox(height: 6),
              _buildNote('Full Signage, Front View, Close-up, Side/Installation — any 2 or more'),
              const SizedBox(height: 10),
              _buildPhotoGrid(),
              const SizedBox(height: 24),

              _sectionLabel('Video (optional)'),
              const SizedBox(height: 10),
              _buildVideoPicker(),
              const SizedBox(height: 24),

              _sectionLabel('9. Preferred New Material'),
              const SizedBox(height: 10),
              _buildDropdown(_preferredMaterial, _preferredMaterials, 'Preferred material for new signage', (v) => setState(() => _preferredMaterial = v)),
              if (_isOther(_preferredMaterial)) _otherField(_preferredMaterialOtherController, 'Please specify'),
              const SizedBox(height: 24),

              _sectionLabel('10. Brand Logo / Artwork Status'),
              const SizedBox(height: 10),
              _buildDropdown(_artworkStatus, _artworkStatusOptions, 'Do you have the new brand logo / artwork ready?', (v) => setState(() => _artworkStatus = v)),
              const SizedBox(height: 24),

              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Expanded(child: _sectionLabel('11. Service Location')),
                  GestureDetector(
                    onTap: _showRateChart,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                      decoration: BoxDecoration(
                        color: AppColors.yellow.withOpacity(0.25),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(color: AppColors.serviceAccent, width: 1),
                      ),
                      child: const Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.receipt_long_outlined, color: AppColors.serviceAccent, size: 14),
                          SizedBox(width: 4),
                          Text('Rate Chart', style: TextStyle(color: AppColors.navy, fontSize: 11, fontWeight: FontWeight.w700)),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              _buildLocationSection(),
              const SizedBox(height: 24),

              if (_calculatingFee || _feeResult != null || _cityUnavailable) _buildFeeCard(),
              const SizedBox(height: 28),

              _buildSubmitButton(),
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
      title: const Text('Rebranding Request', style: TextStyle(color: AppColors.navy, fontSize: 17, fontWeight: FontWeight.w700)),
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
            onTap: () {
              setState(() => _accessEquipment = opt['value'] as String);
              _updateEquipmentTransportCharge();
            },
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

  // ── Photo grid: 4 named slots + Add More ────────────────────────────────

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
            return _photoTile(
              file: file,
              label: _photoSlotLabels[i],
              onTap: () => _pickPhoto(i),
              onRemove: () => _removePhoto(i),
            );
          },
        ),
        if (_extraPhotos.isNotEmpty) ...[
          const SizedBox(height: 10),
          GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: _extraPhotos.length,
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: 3, crossAxisSpacing: 10, mainAxisSpacing: 10, childAspectRatio: 0.85),
            itemBuilder: (_, i) => _photoTile(
              file: _extraPhotos[i],
              label: 'Extra ${i + 1}',
              onTap: () {},
              onRemove: () => _removeExtraPhoto(i),
            ),
          ),
        ],
        const SizedBox(height: 10),
        SizedBox(
          width: double.infinity,
          child: OutlinedButton.icon(
            onPressed: _pickExtraPhoto,
            icon: const Icon(Icons.add_photo_alternate_outlined, color: AppColors.serviceAccent, size: 18),
            label: const Text('Add More Photos', style: TextStyle(color: AppColors.serviceAccent, fontWeight: FontWeight.w600)),
            style: OutlinedButton.styleFrom(
              backgroundColor: AppColors.white,
              side: const BorderSide(color: AppColors.serviceAccent, width: 1),
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

  Widget _buildVideoPicker() {
    if (_videoFile != null) {
      return Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: AppColors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppColors.serviceAccent, width: 1.5),
        ),
        child: Row(
          children: [
            const Icon(Icons.videocam, color: AppColors.serviceAccent, size: 22),
            const SizedBox(width: 10),
            const Expanded(child: Text('Video attached', style: TextStyle(color: AppColors.navy, fontSize: 13))),
            GestureDetector(onTap: _removeVideo, child: const Icon(Icons.close, color: AppColors.grey, size: 18)),
          ],
        ),
      );
    }
    return GestureDetector(
      onTap: _pickVideo,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 16),
        decoration: BoxDecoration(
          color: AppColors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppColors.cardBorder, width: 1),
        ),
        child: const Center(
          child: Column(
            children: [
              Icon(Icons.videocam_outlined, color: AppColors.grey, size: 22),
              SizedBox(height: 6),
              Text('Tap to add a video (optional)', style: TextStyle(color: AppColors.grey, fontSize: 12)),
            ],
          ),
        ),
      ),
    );
  }

  // ── Location section (identical pattern to Repairing) ──────────────────

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
                _cityDebounce = Timer(const Duration(milliseconds: 700), () {
                  if (_lat != null && _lng != null) _calculateFee();
                });
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

  // ── Fee card (identical pattern to Repairing) ───────────────────────────

  Widget _buildFeeCard() {
    if (_cityUnavailable) {
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
    if (_calculatingFee) {
      return Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(color: AppColors.white, borderRadius: BorderRadius.circular(14), border: Border.all(color: AppColors.cardBorder)),
        child: const Row(children: [SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.serviceAccent)), SizedBox(width: 14), Text('Calculating site visit & assessment fee...', style: TextStyle(color: AppColors.grey, fontSize: 13))]),
      );
    }
    final fee = _feeResult!;
    if (fee.status == FeeStatus.configMissing) {
      return Container(
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(color: AppColors.white, borderRadius: BorderRadius.circular(14), border: Border.all(color: AppColors.red, width: 1)),
        child: const Row(children: [Icon(Icons.error_outline, color: AppColors.red, size: 22), SizedBox(width: 12), Expanded(child: Text('Fee configuration is missing on our end. Please contact support — this is not a distance issue.', style: TextStyle(color: AppColors.navy, fontSize: 12.5, height: 1.4)))]),
      );
    }
    if (fee.status == FeeStatus.beyondRange) {
      return Container(
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(color: AppColors.white, borderRadius: BorderRadius.circular(14), border: Border.all(color: const Color(0xFFFFA500), width: 1)),
        child: Row(children: [const Icon(Icons.info_outline, color: Color(0xFFFFA500), size: 22), const SizedBox(width: 12), Expanded(child: Text('Your location is ${fee.distanceKm.toStringAsFixed(1)} km away. This is outside our standard fee slabs, but we still service your area — our team will contact you regarding site visit charges after you submit.', style: const TextStyle(color: AppColors.navy, fontSize: 12.5, height: 1.4)))]),
      );
    }
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(color: AppColors.white, borderRadius: BorderRadius.circular(14), border: Border.all(color: AppColors.serviceAccent.withOpacity(0.5), width: 1), boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 8, offset: const Offset(0, 3))]),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Site Visit & Assessment Fee', style: TextStyle(color: AppColors.navy, fontSize: 14, fontWeight: FontWeight.w700)),
          const SizedBox(height: 6),
          const Text('Our signage expert will visit to assess the existing signage and evaluate the rebranding approach.', style: TextStyle(color: AppColors.grey, fontSize: 11, height: 1.4)),
          const SizedBox(height: 12),
          _feeRow('Distance', '${fee.distanceKm.toStringAsFixed(2)} km'),
          _feeRow('Assessment Fee', '₹${fee.siteVisitFee.toStringAsFixed(2)}'),
          if (_loadingTransportRate) ...[
            const SizedBox(height: 6),
            const Text('Calculating equipment transport charge...', style: TextStyle(color: AppColors.grey, fontSize: 10.5)),
          ],
          if (!_loadingTransportRate && _transportChargeError != null) ...[
            const SizedBox(height: 6),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(color: AppColors.red.withOpacity(0.08), borderRadius: BorderRadius.circular(8)),
              child: Text(_transportChargeError!, style: const TextStyle(color: AppColors.red, fontSize: 10.5)),
            ),
          ],
          if (_equipmentFee != null)
            _feeRow(_accessEquipment == 'h_frame' ? 'H-Frame Equipment Fee' : 'Ladder Equipment Fee', '₹${_equipmentFee!.toStringAsFixed(2)}'),
          if (_equipmentTransportCharge != null)
            _feeRow('Equipment Transport', '₹${_equipmentTransportCharge!.toStringAsFixed(2)}'),
          Builder(builder: (context) {
            final combinedSubtotal = fee.siteVisitFee + (_equipmentFee ?? 0) + (_equipmentTransportCharge ?? 0);
            final combinedGst = combinedSubtotal * (fee.gstPercent / 100);
            final combinedTotal = combinedSubtotal + combinedGst;
            return Column(
              children: [
                _feeRow('GST (${fee.gstPercent.toStringAsFixed(0)}%)', '₹${combinedGst.toStringAsFixed(2)}'),
                const Divider(color: AppColors.cardBorder, height: 20),
                _feeRow('Total Payable', '₹${combinedTotal.toStringAsFixed(2)}', bold: true),
              ],
            );
          }),
          const SizedBox(height: 10),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(color: AppColors.greyLight.withOpacity(0.3), borderRadius: BorderRadius.circular(8)),
            child: const Text(
              'Cancellation Policy: This request can be cancelled only before a technician is assigned to it. '
              'A cancellation charge (a percentage of the site visit fee) will apply, and the remaining amount will '
              'be refunded after review. Once a technician is assigned, the request can no longer be cancelled.',
              style: TextStyle(color: AppColors.grey, fontSize: 10.5, height: 1.4),
            ),
          ),
        ],
      ),
    );
  }

  Widget _feeRow(String label, String value, {bool bold = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: TextStyle(color: bold ? AppColors.navy : AppColors.grey, fontSize: bold ? 14 : 12.5, fontWeight: bold ? FontWeight.w700 : FontWeight.w400)),
          Text(value, style: TextStyle(color: bold ? AppColors.serviceAccent : AppColors.navy, fontSize: bold ? 16 : 12.5, fontWeight: bold ? FontWeight.w800 : FontWeight.w600)),
        ],
      ),
    );
  }

  Widget _buildSubmitButton() {
    final beyondRange = _feeResult?.status == FeeStatus.beyondRange;
    return SizedBox(
      width: double.infinity,
      height: 54,
      child: ElevatedButton(
        onPressed: (_canSubmit && !_submitting) ? _onSubmitPressed : null,
        style: ElevatedButton.styleFrom(backgroundColor: AppColors.yellow, disabledBackgroundColor: AppColors.greyLight, foregroundColor: AppColors.navy, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)), elevation: 2),
        child: _submitting
            ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.navy))
            : Text(beyondRange ? 'SUBMIT REQUEST' : 'PAY & CONFIRM REQUEST', style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800, letterSpacing: 0.5)),
      ),
    );
  }
}