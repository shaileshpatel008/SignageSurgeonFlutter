import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:http/http.dart' as http;
import 'package:geolocator/geolocator.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:razorpay_flutter/razorpay_flutter.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/constants/app_routes.dart';
import '../../../core/services/distance_fee_service.dart';
import '../../../core/widgets/saved_address_picker.dart';

class AmcRequestScreen extends StatefulWidget {
  const AmcRequestScreen({super.key});

  @override
  State<AmcRequestScreen> createState() => _AmcRequestScreenState();
}

/// Holds all controllers + fee state for ONE location entry. Reused for the
/// single-location path, each of the 2-5 per-location entries, and the
/// Primary/HQ location for 6+ location requests.
class _LocationEntry {
  final houseController = TextEditingController();
  final buildingController = TextEditingController();
  final areaController = TextEditingController();
  final landmarkController = TextEditingController();
  final cityController = TextEditingController(text: 'Ahmedabad');
  final pincodeController = TextEditingController();
  final searchController = TextEditingController();
  GoogleMapController? mapController;

  double? lat;
  double? lng;
  List<Map<String, String>> suggestions = [];
  bool searching = false;
  bool fetchingLocation = false;

  bool calculatingFee = false;
  DistanceFeeResult? feeResult;

  String get mergedAddress {
    final parts = [
      houseController.text.trim(),
      buildingController.text.trim(),
      areaController.text.trim(),
      if (landmarkController.text.trim().isNotEmpty) 'Near ${landmarkController.text.trim()}',
      cityController.text.trim(),
    ].where((e) => e.isNotEmpty).join(', ');
    final pin = pincodeController.text.trim();
    return pin.isNotEmpty ? '$parts - $pin' : parts;
  }

  void dispose() {
    houseController.dispose();
    buildingController.dispose();
    areaController.dispose();
    landmarkController.dispose();
    cityController.dispose();
    pincodeController.dispose();
    searchController.dispose();
  }
}

class _AmcRequestScreenState extends State<AmcRequestScreen> {
  final _razorpay = Razorpay();
  static const String _razorpayKeyId = 'rzp_test_TXYmAiGUXZQb0r';
  static const String _mapsApiKey = 'AIzaSyD8v_obWHOLaRYIlSL2vlOjlSYFChOEvmE';

  static const Map<String, String> _androidHeaders = {
    'X-Android-Package': 'com.signagesurgeon.app',
    'X-Android-Cert': 'FF441CA235828F075250E7B23268A62CBDD930B2',
  };

  // ── Options (from Founder Input Master Doc 05) ───────────────────────────
  static const List<String> _requirementTypes = [
    'Single Location', 'Multiple Location',
  ];

  static const List<String> _locationCountRanges = [
    '2–5 Locations', '6–10 Locations', '11–25 Locations',
    '26–50 Locations', 'More Than 50 Locations',
  ];

  static const List<String> _signageQuantityRanges = [
    '1–10 Signages', '11–25 Signages', '26–50 Signages', '51–100 Signages',
    'More Than 100 Signages', 'Not Sure',
  ];

  static const List<String> _signageTypes = [
    'LED / Illuminated Signage', 'Acrylic Signage', 'Channel Letter Signage',
    'ACP Fascia / Signage', 'Pylon / Totem Sign', 'Directional Signage',
    'Safety Signage', 'Indoor Signage', 'Rooftop Signage',
    'Multiple Signage Types', 'Not Sure / Need Expert Review', 'Other',
  ];

  static const List<String> _coverageItems = [
    'Signage Repair & Maintenance', 'Electrical / Lighting Maintenance',
    'Signage Cleaning', 'Preventive Maintenance', 'Periodic Signage Inspection',
    'Damaged Letter / Logo Maintenance', 'ACP / Fascia Maintenance',
    'Emergency Signage Support', 'Complete Signage Maintenance',
  ];

  // ── Form state ─────────────────────────────────────────────────────────
  final _formKey = GlobalKey<FormState>();
  String? _requirementType;
  String? _locationCountRange;
  int? _exactLocationCount; // only meaningful when range == '2–5 Locations'
  String? _signageQuantityRange;
  String? _signageType;
  String? _accessEquipment; // 'ladder' | 'h_frame' | 'not_needed' — compulsory

  final _requirementTypeOtherController = TextEditingController();
  final _signageTypeOtherController = TextEditingController();
  final _areasCitiesController = TextEditingController();

  // Used when locationCountRange is '1 Location' (size 1) or '2–5 Locations'
  // (size = exactLocationCount) — each entry gets its own fee calculated.
  List<_LocationEntry> _locationEntries = [];
  // Used only for 6+ location ranges (Primary/HQ location, no fee calc).
  final _LocationEntry _hqLocation = _LocationEntry();

  List<String> _serviceableCities = ['Ahmedabad', 'Gandhinagar'];
  bool _submitting = false;

  // Question 2 (Number of Locations) only shows for Multiple Location.
  // This keeps the visible numbering sequential (1,2,3... not 1,3,4...)
  // instead of jumping when that question is hidden for Single Location.
  int _qNum(int nominalNumber) {
    if (_requirementType == 'Multiple Location' || nominalNumber <= 1) return nominalNumber;
    return nominalNumber - 1;
  }

  bool get _isSixPlus => _locationCountRange != null &&
      _locationCountRange != '1 Location' &&
      _locationCountRange != '2–5 Locations';
  bool get _needsExactCount => _locationCountRange == '2–5 Locations';
  bool get _feeCalculable => _locationCountRange == '1 Location' ||
      (_locationCountRange == '2–5 Locations' && _exactLocationCount != null);

  @override
  void initState() {
    super.initState();
    _razorpay.on(Razorpay.EVENT_PAYMENT_SUCCESS, _onPaymentSuccess);
    _razorpay.on(Razorpay.EVENT_PAYMENT_ERROR, _onPaymentError);
    _razorpay.on(Razorpay.EVENT_EXTERNAL_WALLET, (_) {});
    _loadServiceableCities();
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
    _requirementTypeOtherController.dispose();
    _signageTypeOtherController.dispose();
    _areasCitiesController.dispose();
    for (final e in _locationEntries) {
      e.dispose();
    }
    _hqLocation.dispose();
    _razorpay.clear();
    super.dispose();
  }

  bool _isOther(String? value) => value != null && value.toLowerCase().contains('other');

  String? get _effectiveRequirementType =>
      (_isOther(_requirementType) && _requirementTypeOtherController.text.trim().isNotEmpty)
          ? _requirementTypeOtherController.text.trim() : _requirementType;
  String? get _effectiveSignageType =>
      (_isOther(_signageType) && _signageTypeOtherController.text.trim().isNotEmpty)
          ? _signageTypeOtherController.text.trim() : _signageType;

  // ── Requirement type change handling ────────────────────────────────────

  void _onRequirementTypeChanged(String? type) {
    setState(() {
      _requirementType = type;
      for (final e in _locationEntries) {
        e.dispose();
      }
      _locationEntries = [];
      _exactLocationCount = null;

      if (type == 'Single Location') {
        // Skip the "Number of Locations" question entirely — it's obviously 1.
        _locationCountRange = '1 Location';
        _locationEntries = [_LocationEntry()];
      } else {
        _locationCountRange = null;
      }
    });
  }

  // ── Location count range change handling ───────────────────────────────

  void _onLocationCountRangeChanged(String? range) {
    setState(() {
      _locationCountRange = range;
      _exactLocationCount = null;
      for (final e in _locationEntries) {
        e.dispose();
      }
      _locationEntries = [];
      // For '2–5 Locations', entries get created once exact count is picked.
    });
  }

  void _onExactCountChanged(int count) {
    setState(() {
      _exactLocationCount = count;
      for (final e in _locationEntries) {
        e.dispose();
      }
      _locationEntries = List.generate(count, (_) => _LocationEntry());
    });
  }

  // ── Location logic (current-location / search / geocode) — per entry ───

  Future<void> _useSavedAddressFor(_LocationEntry entry) async {
    final saved = await showSavedAddressPicker(context);
    if (saved == null) return;
    setState(() {
      entry.houseController.text = saved['houseNo'] as String? ?? '';
      entry.buildingController.text = saved['building'] as String? ?? '';
      entry.areaController.text = saved['area'] as String? ?? '';
      entry.landmarkController.text = saved['landmark'] as String? ?? '';
      entry.cityController.text = saved['city'] as String? ?? '';
      entry.pincodeController.text = saved['pincode'] as String? ?? '';
      entry.lat = (saved['lat'] as num?)?.toDouble();
      entry.lng = (saved['lng'] as num?)?.toDouble();
      entry.searchController.clear();
      entry.suggestions = [];
    });
    if (entry.lat != null && entry.lng != null) {
      entry.mapController?.animateCamera(CameraUpdate.newLatLng(LatLng(entry.lat!, entry.lng!)));
      if (_locationEntries.contains(entry)) {
        await _calculateFeeFor(entry);
      }
    }
  }

  Future<void> _useCurrentLocationFor(_LocationEntry entry) async {
    setState(() => entry.fetchingLocation = true);
    try {
      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.denied || permission == LocationPermission.deniedForever) {
        _showSnack('Location permission denied. Please enable it in settings.');
        setState(() => entry.fetchingLocation = false);
        return;
      }
      final position = await Geolocator.getCurrentPosition(desiredAccuracy: LocationAccuracy.high);
      await _applyLocation(entry, position.latitude, position.longitude);
    } catch (e) {
      _showSnack('Could not fetch current location. Please try again.');
    } finally {
      if (mounted) setState(() => entry.fetchingLocation = false);
    }
  }

  Future<void> _applyLocation(_LocationEntry entry, double lat, double lng) async {
    setState(() {
      entry.lat = lat;
      entry.lng = lng;
      entry.searchController.clear();
      entry.suggestions = [];
    });
    entry.mapController?.animateCamera(CameraUpdate.newLatLng(LatLng(lat, lng)));
    await _reverseGeocodeAndFill(entry, lat, lng);
    if (_locationEntries.contains(entry)) {
      await _calculateFeeFor(entry);
    }
  }

  Future<void> _reverseGeocodeAndFill(_LocationEntry entry, double lat, double lng) async {
    try {
      final uri = Uri.parse('https://maps.googleapis.com/maps/api/geocode/json?latlng=$lat,$lng&key=$_mapsApiKey');
      final response = await http.get(uri, headers: _androidHeaders);
      if (response.statusCode == 200) {
        final json = jsonDecode(response.body);
        final results = json['results'] as List?;
        if (results != null && results.isNotEmpty) _fillFromAddressComponents(entry, results[0]);
      }
    } catch (_) {}
  }

  void _fillFromAddressComponents(_LocationEntry entry, Map<String, dynamic> result) {
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
      if (buildingText.isNotEmpty) entry.buildingController.text = buildingText;
      if (sublocality.isNotEmpty) entry.areaController.text = sublocality;
      if (locality.isNotEmpty) entry.cityController.text = locality;
      if (postalCode.isNotEmpty) entry.pincodeController.text = postalCode;
    });
  }

  Future<void> _onSearchChangedFor(_LocationEntry entry, String query) async {
    if (query.trim().length < 3) {
      setState(() => entry.suggestions = []);
      return;
    }
    setState(() => entry.searching = true);
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
          entry.suggestions = suggestions
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
      if (mounted) setState(() => entry.searching = false);
    }
  }

  Future<void> _selectSuggestionFor(_LocationEntry entry, Map<String, String> suggestion) async {
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
          entry.lat = lat;
          entry.lng = lng;
          entry.searchController.clear();
          entry.suggestions = [];
        });
        entry.mapController?.animateCamera(CameraUpdate.newLatLng(LatLng(lat, lng)));
        _fillFromNewApiAddressComponents(entry, result);
        if (_locationEntries.contains(entry)) {
          await _calculateFeeFor(entry);
        }
      }
    } catch (_) {
      _showSnack('Could not fetch location details. Please try again.');
    }
  }

  void _fillFromNewApiAddressComponents(_LocationEntry entry, Map<String, dynamic> result) {
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
      if (buildingText.isNotEmpty) entry.buildingController.text = buildingText;
      if (sublocality.isNotEmpty) entry.areaController.text = sublocality;
      if (locality.isNotEmpty) entry.cityController.text = locality;
      if (postalCode.isNotEmpty) entry.pincodeController.text = postalCode;
    });
  }

  Future<void> _calculateFeeFor(_LocationEntry entry) async {
    if (entry.lat == null || entry.lng == null) return;
    setState(() {
      entry.calculatingFee = true;
      entry.feeResult = null;
    });
    try {
      final km = await DistanceFeeService.getRoadDistanceKm(destLat: entry.lat!, destLng: entry.lng!);
      final fee = await DistanceFeeService.calculateFee(km, serviceType: 'amc');
      setState(() => entry.feeResult = fee);
    } catch (_) {
      _showSnack('Could not calculate audit fee for this location. Please try again.');
    } finally {
      if (mounted) setState(() => entry.calculatingFee = false);
    }
  }

  // ── Aggregate fee across all location entries ───────────────────────────

  bool get _allFeesReady => _locationEntries.isNotEmpty &&
      _locationEntries.every((e) => e.feeResult != null && e.feeResult!.status == FeeStatus.ok);
  bool get _anyBeyondRange => _locationEntries.any((e) => e.feeResult?.status == FeeStatus.beyondRange);
  bool get _anyCalculating => _locationEntries.any((e) => e.calculatingFee);

  double get _totalFee => _locationEntries.fold(0.0, (sum, e) => sum + (e.feeResult?.siteVisitFee ?? 0));
  double get _totalGst => _locationEntries.fold(0.0, (sum, e) => sum + (e.feeResult?.gstAmount ?? 0));
  double get _totalPayable => _totalFee + _totalGst;

  // ── Submit / Payment ──────────────────────────────────────────────────

  bool get _canSubmit {
    if (_requirementType == null || _locationCountRange == null ||
        _signageQuantityRange == null || _signageType == null ||
        _accessEquipment == null) return false;

    if (_isSixPlus) {
      return _areasCitiesController.text.trim().isNotEmpty &&
          _hqLocation.houseController.text.trim().isNotEmpty &&
          _hqLocation.lat != null && _hqLocation.lng != null;
    }

    // 1-5 locations: need exact count set (if applicable), all entries with
    // address + successfully calculated fee.
    if (_needsExactCount && _exactLocationCount == null) return false;
    if (_locationEntries.isEmpty) return false;
    for (final e in _locationEntries) {
      if (e.houseController.text.trim().isEmpty || e.areaController.text.trim().isEmpty) return false;
      if (e.lat == null || e.lng == null) return false;
    }
    return _allFeesReady;
  }

  Future<void> _onSubmitPressed() async {
    if (!_canSubmit) {
      _showSnack('Please complete all required fields and location details.');
      return;
    }

    if (_isSixPlus) {
      await _submitInquiryOnly();
      return;
    }

    setState(() => _submitting = true);
    _openRazorpayCheckout();
  }

  Future<void> _submitInquiryOnly() async {
    setState(() => _submitting = true);
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) throw Exception('Not logged in');

      final requestId = FirebaseFirestore.instance.collection('amc_requests').doc().id;
      await FirebaseFirestore.instance.collection('amc_requests').doc(requestId).set({
        'userId': user.uid,
        'createdAt': FieldValue.serverTimestamp(),
        'amcPhase': 'inquiry_submitted',
        'requirementType': _effectiveRequirementType,
        'locationCountRange': _locationCountRange,
        'signageQuantityRange': _signageQuantityRange,
        'signageType': _effectiveSignageType,
        'accessEquipment': _accessEquipment,
        'areasCities': _areasCitiesController.text.trim(),
        'hqLocation': {
          'houseNo': _hqLocation.houseController.text.trim(),
          'building': _hqLocation.buildingController.text.trim(),
          'area': _hqLocation.areaController.text.trim(),
          'landmark': _hqLocation.landmarkController.text.trim(),
          'city': _hqLocation.cityController.text.trim(),
          'pincode': _hqLocation.pincodeController.text.trim(),
          'address': _hqLocation.mergedAddress,
          'lat': _hqLocation.lat,
          'lng': _hqLocation.lng,
        },
      });

      if (mounted) {
        setState(() => _submitting = false);
        Navigator.pushReplacementNamed(context, AppRoutes.amcTracking, arguments: requestId);
      }
    } catch (e) {
      _showSnack('Something went wrong submitting your request. Please try again.');
      setState(() => _submitting = false);
    }
  }

  void _openRazorpayCheckout() {
    final amountPaise = (_totalPayable * 100).round();
    final options = {
      'key': _razorpayKeyId,
      'amount': amountPaise,
      'currency': 'INR',
      'name': 'The Signage Surgeon',
      'description': 'AMC Initial Signage Audit Fee',
      'prefill': {'contact': FirebaseAuth.instance.currentUser?.phoneNumber ?? ''},
      'theme': {'color': '#FEC107'},
    };
    try {
      _razorpay.open(options);
    } catch (e) {
      _showSnack('Could not open payment screen. Please try again.');
      setState(() => _submitting = false);
    }
  }

  void _onPaymentSuccess(PaymentSuccessResponse response) async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) return;
      final requestId = FirebaseFirestore.instance.collection('amc_requests').doc().id;

      await FirebaseFirestore.instance.collection('amc_requests').doc(requestId).set({
        'userId': user.uid,
        'createdAt': FieldValue.serverTimestamp(),
        'amcPhase': 'audit_paid',
        'requirementType': _effectiveRequirementType,
        'locationCountRange': _locationCountRange,
        'exactLocationCount': _exactLocationCount ?? 1,
        'signageQuantityRange': _signageQuantityRange,
        'signageType': _effectiveSignageType,
        'accessEquipment': _accessEquipment,
        'locations': _locationEntries
            .map((e) => {
                  'houseNo': e.houseController.text.trim(),
                  'building': e.buildingController.text.trim(),
                  'area': e.areaController.text.trim(),
                  'landmark': e.landmarkController.text.trim(),
                  'city': e.cityController.text.trim(),
                  'pincode': e.pincodeController.text.trim(),
                  'address': e.mergedAddress,
                  'lat': e.lat,
                  'lng': e.lng,
                  'distanceKm': e.feeResult?.distanceKm,
                  'fee': e.feeResult?.siteVisitFee,
                  'gstAmount': e.feeResult?.gstAmount,
                })
            .toList(),
        'totalAuditFee': _totalFee,
        'totalGst': _totalGst,
        'totalPayable': _totalPayable,
        'auditPaymentId': response.paymentId,
        'auditPaymentStatus': 'paid',
      });

      if (mounted) {
        setState(() => _submitting = false);
        Navigator.pushReplacementNamed(context, AppRoutes.amcTracking, arguments: requestId);
      }
    } catch (e) {
      _showSnack('Payment succeeded but saving your request failed. Contact support with payment ID: ${response.paymentId}');
      setState(() => _submitting = false);
    }
  }

  void _onPaymentError(PaymentFailureResponse response) {
    setState(() => _submitting = false);
    _showSnack('Payment failed or was cancelled. Please try again.');
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
              _sectionLabel('${_qNum(1)}. AMC Requirement Type'),
              const SizedBox(height: 10),
              _buildDropdown(_requirementType, _requirementTypes, 'What type of AMC requirement do you have?', _onRequirementTypeChanged),
              if (_isOther(_requirementType)) _otherField(_requirementTypeOtherController, 'Please specify'),
              const SizedBox(height: 24),

              if (_requirementType == 'Multiple Location') ...[
                _sectionLabel('${_qNum(2)}. Number of Locations'),
                const SizedBox(height: 10),
                _buildDropdown(_locationCountRange, _locationCountRanges, 'How many locations require signage AMC?', _onLocationCountRangeChanged),
                if (_needsExactCount) ...[
                  const SizedBox(height: 12),
                  _buildExactCountStepper(),
                ],
                const SizedBox(height: 24),
              ],

              _sectionLabel('${_qNum(3)}. Approximate Signage Quantity'),
              const SizedBox(height: 10),
              _buildDropdown(_signageQuantityRange, _signageQuantityRanges, 'Approximately how many signages are covered?', (v) => setState(() => _signageQuantityRange = v)),
              const SizedBox(height: 24),

              _sectionLabel('${_qNum(4)}. Signage Types'),
              const SizedBox(height: 10),
              _buildDropdown(_signageType, _signageTypes, 'What type of signages are included?', (v) => setState(() => _signageType = v)),
              if (_isOther(_signageType)) _otherField(_signageTypeOtherController, 'Please specify'),
              const SizedBox(height: 24),

              _sectionLabel('AMC Coverage'),
              const SizedBox(height: 10),
              _buildCoverageInfoBlock(),
              const SizedBox(height: 24),

              _sectionLabel('Access Equipment'),
              const SizedBox(height: 6),
              _buildNote('Required for the audit visit if any signage is at height — please select one'),
              const SizedBox(height: 10),
              _buildAccessEquipmentSelector(),
              if (_accessEquipment == 'not_needed') ...[
                const SizedBox(height: 10),
                _buildAccessEquipmentDisclaimer(),
              ],
              const SizedBox(height: 24),

              if (_locationCountRange != null) ...[
                _sectionLabel(_isSixPlus ? 'Location Details' : (_locationCountRange == '1 Location' ? '${_qNum(5)}. Service Location' : '${_qNum(5)}. Location Details'),),
                const SizedBox(height: 10),
                if (_isSixPlus) _buildMultiAreaSection() else _buildFeeCalculableLocations(),
                const SizedBox(height: 24),
              ],

              if (!_isSixPlus && _locationEntries.isNotEmpty) ...[
                _buildAggregateFeeCard(),
                const SizedBox(height: 24),
              ],

              _buildSubmitButton(),
              const SizedBox(height: 8),
              if (_isSixPlus)
                const Text(
                  'No payment is required now. Our team will review your request and send a custom audit fee proposal.',
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
      title: const Text('AMC Request', style: TextStyle(color: AppColors.navy, fontSize: 17, fontWeight: FontWeight.w700)),
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
      {'value': 'ladder', 'label': 'Ladder', 'icon': Icons.stairs_outlined},
      {'value': 'h_frame', 'label': 'H-Frame (Palak)', 'icon': Icons.window_outlined},
      {'value': 'not_needed', 'label': 'Not Needed', 'icon': Icons.block_outlined},
    ];
    return Column(
      children: options.map((opt) {
        final selected = _accessEquipment == opt['value'];
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
                  Expanded(child: Text(opt['label'] as String, style: TextStyle(color: AppColors.navy, fontSize: 14, fontWeight: selected ? FontWeight.w700 : FontWeight.w500))),
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
              'If access equipment turns out to be required at the audit visit and is unavailable, this will be treated as your responsibility — no refund will apply. Our team will wait up to 30 minutes for you to arrange suitable access.',
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

  Widget _buildExactCountStepper() {
    final count = _exactLocationCount ?? 2;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(color: AppColors.white, borderRadius: BorderRadius.circular(12), border: Border.all(color: AppColors.serviceAccent, width: 1)),
      child: Row(
        children: [
          const Expanded(child: Text('Exact number of locations', style: TextStyle(color: AppColors.navy, fontSize: 13, fontWeight: FontWeight.w600))),
          _stepperButton(Icons.remove, () {
            if (count > 2) _onExactCountChanged(count - 1);
          }),
          Container(
            width: 36,
            alignment: Alignment.center,
            child: Text('$count', style: const TextStyle(color: AppColors.navy, fontSize: 16, fontWeight: FontWeight.w800)),
          ),
          _stepperButton(Icons.add, () {
            if (count < 5) _onExactCountChanged(count + 1);
          }),
        ],
      ),
    );
  }

  Widget _stepperButton(IconData icon, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 32, height: 32,
        decoration: BoxDecoration(color: AppColors.yellow.withOpacity(0.25), borderRadius: BorderRadius.circular(8)),
        child: Icon(icon, color: AppColors.navy, size: 18),
      ),
    );
  }

  Widget _buildCoverageInfoBlock() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(color: AppColors.white, borderRadius: BorderRadius.circular(14), border: Border.all(color: AppColors.cardBorder, width: 1)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Every AMC plan can include:', style: TextStyle(color: AppColors.grey, fontSize: 11.5, fontStyle: FontStyle.italic)),
          const SizedBox(height: 10),
          ..._coverageItems.map((item) => Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Row(
                  children: [
                    const Icon(Icons.check_circle, color: AppColors.serviceAccent, size: 16),
                    const SizedBox(width: 8),
                    Expanded(child: Text(item, style: const TextStyle(color: AppColors.navy, fontSize: 12.5))),
                  ],
                ),
              )),
          const SizedBox(height: 6),
          const Text('Final coverage, visit frequency and service terms will be defined in your approved AMC quotation.',
              style: TextStyle(color: AppColors.grey, fontSize: 10.5, height: 1.4)),
        ],
      ),
    );
  }

  // ── Multi-area (6+ locations) section ───────────────────────────────────

  Widget _buildMultiAreaSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('Which areas / cities are covered?', style: TextStyle(color: AppColors.navy, fontSize: 13, fontWeight: FontWeight.w600)),
        const SizedBox(height: 8),
        Container(
          decoration: BoxDecoration(color: AppColors.white, borderRadius: BorderRadius.circular(12), border: Border.all(color: AppColors.cardBorder, width: 1)),
          child: TextFormField(
            controller: _areasCitiesController,
            maxLines: 2,
            style: const TextStyle(color: AppColors.navy, fontSize: 13.5),
            decoration: const InputDecoration(
              filled: true, fillColor: AppColors.white,
              hintText: 'e.g. Ahmedabad, Gandhinagar, Sanand, Changodar, Vadodara',
              hintStyle: TextStyle(color: AppColors.grey, fontSize: 12.5),
              contentPadding: EdgeInsets.all(14), border: InputBorder.none,
            ),
          ),
        ),
        const SizedBox(height: 20),
        const Text('Primary / Head Office Location', style: TextStyle(color: AppColors.navy, fontSize: 13, fontWeight: FontWeight.w600)),
        const SizedBox(height: 10),
        _buildLocationEntryUI(_hqLocation, showFee: false),
      ],
    );
  }

  // ── Fee-calculable locations (1 or 2-5) ─────────────────────────────────

  Widget _buildFeeCalculableLocations() {
    if (_locationEntries.isEmpty) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 10),
        child: Text('Select the exact number of locations above to continue.', style: TextStyle(color: AppColors.grey, fontSize: 12)),
      );
    }
    return Column(
      children: List.generate(_locationEntries.length, (i) {
        return Padding(
          padding: EdgeInsets.only(bottom: i < _locationEntries.length - 1 ? 24 : 0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (_locationEntries.length > 1) ...[
                Text('Location ${i + 1}', style: const TextStyle(color: AppColors.navy, fontSize: 13, fontWeight: FontWeight.w700)),
                const SizedBox(height: 10),
              ],
              _buildLocationEntryUI(_locationEntries[i], showFee: true),
            ],
          ),
        );
      }),
    );
  }

  Widget _buildLocationEntryUI(_LocationEntry entry, {required bool showFee}) {
    return Column(
      children: [
        SizedBox(
          width: double.infinity,
          height: 48,
          child: OutlinedButton.icon(
            onPressed: entry.fetchingLocation ? null : () => _useCurrentLocationFor(entry),
            icon: entry.fetchingLocation
                ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.serviceAccent))
                : const Icon(Icons.my_location, color: AppColors.serviceAccent, size: 18),
            label: Text(entry.fetchingLocation ? 'Fetching location...' : 'Use Current Location', style: const TextStyle(color: AppColors.serviceAccent, fontWeight: FontWeight.w600)),
            style: OutlinedButton.styleFrom(backgroundColor: AppColors.white, side: const BorderSide(color: AppColors.serviceAccent, width: 1), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
          ),
        ),
        const SizedBox(height: 10),
        SizedBox(
          width: double.infinity,
          height: 48,
          child: OutlinedButton.icon(
            onPressed: () => _useSavedAddressFor(entry),
            icon: const Icon(Icons.bookmark_outline, color: AppColors.serviceAccent, size: 18),
            label: const Text('Use Saved Address', style: TextStyle(color: AppColors.serviceAccent, fontWeight: FontWeight.w600)),
            style: OutlinedButton.styleFrom(backgroundColor: AppColors.white, side: const BorderSide(color: AppColors.serviceAccent, width: 1), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
          ),
        ),
        const SizedBox(height: 10),
        const Align(alignment: Alignment.centerLeft, child: Text('OR SEARCH', style: TextStyle(color: AppColors.grey, fontSize: 11, fontWeight: FontWeight.w600))),
        const SizedBox(height: 8),
        Container(
          decoration: BoxDecoration(color: AppColors.white, borderRadius: BorderRadius.circular(12), border: Border.all(color: AppColors.cardBorder, width: 1)),
          child: TextFormField(
            controller: entry.searchController,
            style: const TextStyle(color: AppColors.navy, fontSize: 14),
            onChanged: (q) => _onSearchChangedFor(entry, q),
            decoration: InputDecoration(
              filled: true, fillColor: AppColors.white, hintText: 'Search for address',
              hintStyle: const TextStyle(color: AppColors.grey, fontSize: 13),
              prefixIcon: const Icon(Icons.search, color: AppColors.serviceAccent, size: 18),
              suffixIcon: entry.searching ? const Padding(padding: EdgeInsets.all(14), child: SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.serviceAccent))) : null,
              border: InputBorder.none, contentPadding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
            ),
          ),
        ),
        if (entry.suggestions.isNotEmpty)
          Container(
            margin: const EdgeInsets.only(top: 6),
            decoration: BoxDecoration(color: AppColors.white, borderRadius: BorderRadius.circular(12), border: Border.all(color: AppColors.cardBorder, width: 1), boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.06), blurRadius: 8, offset: const Offset(0, 3))]),
            clipBehavior: Clip.antiAlias,
            child: Material(
              color: Colors.transparent,
              child: Column(
                children: entry.suggestions
                    .map((s) => ListTile(
                          dense: true,
                          leading: const Icon(Icons.location_on_outlined, color: AppColors.serviceAccent, size: 18),
                          title: Text(s['description'] ?? '', style: const TextStyle(color: AppColors.navy, fontSize: 12.5)),
                          onTap: () => _selectSuggestionFor(entry, s),
                        ))
                    .toList(),
              ),
            ),
          ),
        const SizedBox(height: 14),
        ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: SizedBox(
            height: 160,
            child: GoogleMap(
              initialCameraPosition: CameraPosition(target: LatLng(entry.lat ?? 23.0225, entry.lng ?? 72.5714), zoom: entry.lat != null ? 15 : 11),
              onMapCreated: (c) => entry.mapController = c,
              markers: entry.lat != null && entry.lng != null ? {Marker(markerId: MarkerId('loc_${entry.hashCode}'), position: LatLng(entry.lat!, entry.lng!))} : {},
              zoomControlsEnabled: false, myLocationButtonEnabled: false,
              scrollGesturesEnabled: true, zoomGesturesEnabled: true, rotateGesturesEnabled: false, tiltGesturesEnabled: false,
            ),
          ),
        ),
        const SizedBox(height: 12),
        _addressField(controller: entry.houseController, hint: 'House / Shop No. *', icon: Icons.home_outlined),
        const SizedBox(height: 8),
        _addressField(controller: entry.buildingController, hint: 'Building / Society Name', icon: Icons.apartment_outlined),
        const SizedBox(height: 8),
        _addressField(controller: entry.areaController, hint: 'Area *', icon: Icons.map_outlined),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(child: _addressField(controller: entry.cityController, hint: 'City', icon: Icons.location_city_outlined)),
            const SizedBox(width: 8),
            Expanded(child: _addressField(controller: entry.pincodeController, hint: 'Pincode', icon: Icons.pin_drop_outlined, keyboardType: TextInputType.number)),
          ],
        ),
        if (showFee) ...[
          const SizedBox(height: 12),
          _buildEntryFeeCard(entry),
        ],
      ],
    );
  }

  Widget _addressField({required TextEditingController controller, required String hint, required IconData icon, TextInputType keyboardType = TextInputType.text}) {
    return Container(
      decoration: BoxDecoration(color: AppColors.white, borderRadius: BorderRadius.circular(12), border: Border.all(color: AppColors.cardBorder, width: 1)),
      child: TextFormField(
        controller: controller,
        keyboardType: keyboardType,
        style: const TextStyle(color: AppColors.navy, fontSize: 13.5),
        decoration: InputDecoration(
          filled: true, fillColor: AppColors.white, hintText: hint,
          hintStyle: const TextStyle(color: AppColors.grey, fontSize: 13),
          prefixIcon: Icon(icon, color: AppColors.serviceAccent, size: 18),
          border: InputBorder.none, contentPadding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
        ),
      ),
    );
  }

  Widget _buildEntryFeeCard(_LocationEntry entry) {
    if (entry.calculatingFee) {
      return Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(color: AppColors.offWhite, borderRadius: BorderRadius.circular(10)),
        child: const Row(children: [SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.serviceAccent)), SizedBox(width: 10), Text('Calculating audit fee...', style: TextStyle(color: AppColors.grey, fontSize: 12))]),
      );
    }
    final fee = entry.feeResult;
    if (fee == null) return const SizedBox.shrink();
    if (fee.status == FeeStatus.beyondRange) {
      return Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(color: const Color(0xFFFFA500).withOpacity(0.1), borderRadius: BorderRadius.circular(10)),
        child: Text('${fee.distanceKm.toStringAsFixed(1)} km — outside standard slabs. Team will contact you for this location.',
            style: const TextStyle(color: AppColors.navy, fontSize: 11.5, height: 1.4)),
      );
    }
    if (fee.status == FeeStatus.configMissing) {
      return Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(color: AppColors.red.withOpacity(0.08), borderRadius: BorderRadius.circular(10)),
        child: const Text('Fee configuration missing. Please contact support.', style: TextStyle(color: AppColors.red, fontSize: 11.5)),
      );
    }
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(color: AppColors.yellow.withOpacity(0.12), borderRadius: BorderRadius.circular(10)),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text('${fee.distanceKm.toStringAsFixed(1)} km', style: const TextStyle(color: AppColors.grey, fontSize: 12)),
          Text('₹${fee.siteVisitFee.toStringAsFixed(0)} + ${fee.gstPercent.toStringAsFixed(0)}% GST', style: const TextStyle(color: AppColors.navy, fontSize: 12.5, fontWeight: FontWeight.w700)),
        ],
      ),
    );
  }

  Widget _buildAggregateFeeCard() {
    if (_anyCalculating) {
      return Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(color: AppColors.white, borderRadius: BorderRadius.circular(14), border: Border.all(color: AppColors.cardBorder)),
        child: const Row(children: [SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.serviceAccent)), SizedBox(width: 14), Text('Calculating total audit fee...', style: TextStyle(color: AppColors.grey, fontSize: 13))]),
      );
    }
    if (_anyBeyondRange) {
      return Container(
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(color: AppColors.white, borderRadius: BorderRadius.circular(14), border: Border.all(color: const Color(0xFFFFA500), width: 1)),
        child: const Row(
          children: [
            Icon(Icons.info_outline, color: Color(0xFFFFA500), size: 22),
            SizedBox(width: 12),
            Expanded(child: Text('One or more locations are outside our standard fee slabs. Our team will contact you regarding the audit fee for those locations.', style: TextStyle(color: AppColors.navy, fontSize: 12.5, height: 1.4))),
          ],
        ),
      );
    }
    if (!_allFeesReady) return const SizedBox.shrink();

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(color: AppColors.white, borderRadius: BorderRadius.circular(14), border: Border.all(color: AppColors.serviceAccent.withOpacity(0.5), width: 1), boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 8, offset: const Offset(0, 3))]),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('AMC Initial Signage Audit Fee', style: TextStyle(color: AppColors.navy, fontSize: 14, fontWeight: FontWeight.w700)),
          const SizedBox(height: 10),
          ...List.generate(_locationEntries.length, (i) {
            final e = _locationEntries[i];
            return Padding(
              padding: const EdgeInsets.symmetric(vertical: 3),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(_locationEntries.length > 1 ? 'Location ${i + 1} (${e.feeResult!.distanceKm.toStringAsFixed(1)} km)' : 'Distance', style: const TextStyle(color: AppColors.grey, fontSize: 12)),
                  Text('₹${e.feeResult!.siteVisitFee.toStringAsFixed(0)}', style: const TextStyle(color: AppColors.navy, fontSize: 12.5, fontWeight: FontWeight.w600)),
                ],
              ),
            );
          }),
          const Divider(color: AppColors.cardBorder, height: 20),
          _feeRow('Total Audit Fee', '₹${_totalFee.toStringAsFixed(0)}'),
          _feeRow('GST', '₹${_totalGst.toStringAsFixed(0)}'),
          const Divider(color: AppColors.cardBorder, height: 20),
          _feeRow('Total Payable', '₹${_totalPayable.toStringAsFixed(0)}', bold: true),
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
    final label = _isSixPlus ? 'SUBMIT AMC INQUIRY' : 'PAY & CONFIRM AMC AUDIT';
    return SizedBox(
      width: double.infinity,
      height: 54,
      child: ElevatedButton(
        onPressed: (_canSubmit && !_submitting) ? _onSubmitPressed : null,
        style: ElevatedButton.styleFrom(backgroundColor: AppColors.yellow, disabledBackgroundColor: AppColors.greyLight, foregroundColor: AppColors.navy, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)), elevation: 2),
        child: _submitting
            ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.navy))
            : Text(label, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800, letterSpacing: 0.5)),
      ),
    );
  }
}