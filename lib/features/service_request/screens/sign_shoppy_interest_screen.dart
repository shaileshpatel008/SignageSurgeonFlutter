import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:http/http.dart' as http;
import 'package:geolocator/geolocator.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/saved_address_picker.dart';
import '../../../core/constants/app_routes.dart';

class SignShoppyInterestScreen extends StatefulWidget {
  const SignShoppyInterestScreen({super.key});

  @override
  State<SignShoppyInterestScreen> createState() => _SignShoppyInterestScreenState();
}

class _SignShoppyInterestScreenState extends State<SignShoppyInterestScreen> {
  static const String _mapsApiKey = 'AIzaSyD8v_obWHOLaRYIlSL2vlOjlSYFChOEvmE';
  static const Map<String, String> _androidHeaders = {
    'X-Android-Package': 'com.signagesurgeon.app',
    'X-Android-Cert': 'FF441CA235828F075250E7B23268A62CBDD930B2',
  };

  static const List<String> _quantityOptions = ['1', '2–5', '6–10', '11–25', 'More Than 25'];
  static const List<String> _preferenceOptions = ['Plain / Standard Sign', 'Add My Logo / Brand Name'];

  final _formKey = GlobalKey<FormState>();
  String? _quantity;
  String? _preference;

  final _houseController = TextEditingController();
  final _buildingController = TextEditingController();
  final _areaController = TextEditingController();
  final _landmarkController = TextEditingController();
  final _cityController = TextEditingController(text: 'Ahmedabad');
  final _pincodeController = TextEditingController();
  final _searchController = TextEditingController();

  double? _lat;
  double? _lng;
  GoogleMapController? _mapController;
  List<Map<String, String>> _suggestions = [];
  bool _searching = false;
  bool _fetchingLocation = false;
  bool _submitting = false;

  String? _productId;
  String? _productName;
  String? _category;
  bool _initialized = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_initialized) {
      final args = ModalRoute.of(context)?.settings.arguments as Map?;
      _productId = args?['productId'] as String?;
      _productName = args?['productName'] as String?;
      _category = args?['category'] as String?;
      _initialized = true;
    }
  }

  @override
  void dispose() {
    _houseController.dispose();
    _buildingController.dispose();
    _areaController.dispose();
    _landmarkController.dispose();
    _cityController.dispose();
    _pincodeController.dispose();
    _searchController.dispose();
    super.dispose();
  }

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
      setState(() {
        _lat = position.latitude;
        _lng = position.longitude;
        _searchController.clear();
        _suggestions = [];
      });
      _mapController?.animateCamera(CameraUpdate.newLatLng(LatLng(_lat!, _lng!)));
      await _reverseGeocodeAndFill(_lat!, _lng!);
    } catch (e) {
      _showSnack('Could not fetch current location. Please try again.');
    } finally {
      if (mounted) setState(() => _fetchingLocation = false);
    }
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
        setState(() {
          _lat = (loc['latitude'] as num).toDouble();
          _lng = (loc['longitude'] as num).toDouble();
          _searchController.clear();
          _suggestions = [];
        });
        _mapController?.animateCamera(CameraUpdate.newLatLng(LatLng(_lat!, _lng!)));
        _fillFromNewApiAddressComponents(result);
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

  bool get _canSubmit =>
      _quantity != null &&
      _preference != null &&
      _houseController.text.trim().isNotEmpty &&
      _areaController.text.trim().isNotEmpty &&
      _lat != null &&
      _lng != null;

  Future<void> _onSubmitPressed() async {
    if (!_canSubmit) {
      _showSnack('Please complete all required fields.');
      return;
    }
    setState(() => _submitting = true);
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) throw Exception('Not logged in');

      final requestId = FirebaseFirestore.instance.collection('sign_shoppy_interests').doc().id;
      await FirebaseFirestore.instance.collection('sign_shoppy_interests').doc(requestId).set({
        'userId': user.uid,
        'createdAt': FieldValue.serverTimestamp(),
        'productId': _productId,
        'productName': _productName,
        'category': _category,
        'requiredQuantity': _quantity,
        'signPreference': _preference,
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
        'status': 'NEW INTEREST',
        'orderPhase': 'submitted',
      });

      if (mounted) {
        setState(() => _submitting = false);
        Navigator.pushReplacementNamed(context, AppRoutes.signShoppyTracking, arguments: requestId);
      }
    } catch (e) {
      _showSnack('Something went wrong submitting your interest. Please try again.');
      setState(() => _submitting = false);
    }
  }

  void _showSnack(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(backgroundColor: AppColors.red, content: Text(message, style: const TextStyle(color: Colors.white))),
    );
  }

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
              if (_productName != null) ...[
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(color: AppColors.white, borderRadius: BorderRadius.circular(12), border: Border.all(color: AppColors.cardBorder)),
                  child: Row(
                    children: [
                      Container(
                        width: 40, height: 40,
                        decoration: BoxDecoration(color: AppColors.yellow.withOpacity(0.2), borderRadius: BorderRadius.circular(10)),
                        child: const Icon(Icons.storefront_outlined, color: AppColors.yellowDark, size: 20),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(_productName!, style: const TextStyle(color: AppColors.navy, fontSize: 13.5, fontWeight: FontWeight.w700)),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 24),
              ],

              _sectionLabel('1. Required Quantity'),
              const SizedBox(height: 10),
              _buildDropdown(_quantity, _quantityOptions, 'How many signs do you require?', (v) => setState(() => _quantity = v)),
              const SizedBox(height: 24),

              _sectionLabel('2. Sign Preference'),
              const SizedBox(height: 10),
              _buildDropdown(_preference, _preferenceOptions, 'Select your sign preference', (v) => setState(() => _preference = v)),
              const SizedBox(height: 24),

              _sectionLabel('3. Delivery Location'),
              const SizedBox(height: 10),
              _buildLocationSection(),
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
      title: const Text('Product Interest', style: TextStyle(color: AppColors.navy, fontSize: 16, fontWeight: FontWeight.w700)),
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
            height: 200,
            child: GoogleMap(
              initialCameraPosition: CameraPosition(target: LatLng(_lat ?? 23.0225, _lng ?? 72.5714), zoom: _lat != null ? 16 : 12),
              onMapCreated: (c) => _mapController = c,
              markers: _lat != null && _lng != null ? {Marker(markerId: const MarkerId('selected'), position: LatLng(_lat!, _lng!))} : {},
              zoomControlsEnabled: true, myLocationButtonEnabled: false,
              scrollGesturesEnabled: true, zoomGesturesEnabled: true, rotateGesturesEnabled: true, tiltGesturesEnabled: true,
            ),
          ),
        ),
        const SizedBox(height: 18),
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
            Expanded(child: _addressField(controller: _cityController, hint: 'City', icon: Icons.location_city_outlined)),
            const SizedBox(width: 10),
            Expanded(child: _addressField(controller: _pincodeController, hint: 'Pincode', icon: Icons.pin_drop_outlined, keyboardType: TextInputType.number)),
          ],
        ),
      ],
    );
  }

  Widget _addressField({required TextEditingController controller, required String hint, required IconData icon, TextInputType keyboardType = TextInputType.text}) {
    return Container(
      decoration: BoxDecoration(color: AppColors.white, borderRadius: BorderRadius.circular(12), border: Border.all(color: AppColors.cardBorder, width: 1)),
      child: TextFormField(
        controller: controller,
        keyboardType: keyboardType,
        onChanged: (_) => setState(() {}),
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

  Widget _buildSubmitButton() {
    return SizedBox(
      width: double.infinity,
      height: 54,
      child: ElevatedButton(
        onPressed: (_canSubmit && !_submitting) ? _onSubmitPressed : null,
        style: ElevatedButton.styleFrom(backgroundColor: AppColors.yellow, disabledBackgroundColor: AppColors.greyLight, foregroundColor: AppColors.navy, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)), elevation: 2),
        child: _submitting
            ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.navy))
            : const Text('SUBMIT INTEREST', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800, letterSpacing: 0.5)),
      ),
    );
  }
}