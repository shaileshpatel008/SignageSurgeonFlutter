import 'dart:convert';
import 'dart:math' as math;
import 'package:http/http.dart' as http;
import 'package:cloud_firestore/cloud_firestore.dart';

/// Status of a fee calculation attempt.
enum FeeStatus {
  ok, // matched a slab
  beyondRange, // distance exceeds the highest configured slab (genuine)
  configMissing, // no active slabs found in Firestore at all (setup bug)
}

/// Result of a distance + fee calculation.
class DistanceFeeResult {
  final double distanceKm;
  final FeeStatus status;
  final String? slabId;
  final double siteVisitFee;
  final double gstPercent;
  final double gstAmount;
  final double totalPayable;

  bool get beyondServiceRange => status != FeeStatus.ok;

  DistanceFeeResult({
    required this.distanceKm,
    required this.status,
    this.slabId,
    required this.siteVisitFee,
    required this.gstPercent,
    required this.gstAmount,
    required this.totalPayable,
  });
}

class DistanceFeeService {
  // Same restricted Maps API key used elsewhere in the app.
  static const String _mapsApiKey = 'AIzaSyD8v_obWHOLaRYIlSL2vlOjlSYFChOEvmE';

  // Workshop hub — fallback values if Firestore read fails.
  static const double _fallbackHubLat = 23.0505776;
  static const double _fallbackHubLng = 72.5799976;

  /// Fetches the active hub coordinates from Firestore (service_hubs/hub_main).
  static Future<Map<String, double>> getHubLocation() async {
    try {
      final doc = await FirebaseFirestore.instance
          .collection('service_hubs')
          .doc('hub_main')
          .get();
      if (doc.exists) {
        final data = doc.data()!;
        return {
          'lat': (data['lat'] as num).toDouble(),
          'lng': (data['lng'] as num).toDouble(),
        };
      }
    } catch (e) {
      // ignore: avoid_print
      print('getHubLocation error: $e');
    }
    return {'lat': _fallbackHubLat, 'lng': _fallbackHubLng};
  }

  /// Calls the Google Routes API (computeRouteMatrix) to get road distance (in km) from
  /// the hub to the given customer lat/lng. Falls back to straight-line
  /// (haversine) distance if the API call fails for any reason.
  static const Map<String, String> _androidHeaders = {
    'X-Android-Package': 'com.signagesurgeon.app',
    'X-Android-Cert': 'FF441CA235828F075250E7B23268A62CBDD930B2',
  };

  static Future<double> getRoadDistanceKm({
    required double destLat,
    required double destLng,
  }) async {
    final hub = await getHubLocation();

    // Google Routes API — computeRouteMatrix. Replaces the legacy
    // Distance Matrix API, which can no longer be enabled on new projects
    // (it returned REQUEST_DENIED "You're calling a legacy API").
    // Requires "Routes API" to be enabled for the key's Cloud project.
    final uri = Uri.parse(
      'https://routes.googleapis.com/distanceMatrix/v2:computeRouteMatrix',
    );
    final body = jsonEncode({
      'origins': [
        {
          'waypoint': {
            'location': {
              'latLng': {'latitude': hub['lat'], 'longitude': hub['lng']},
            },
          },
        },
      ],
      'destinations': [
        {
          'waypoint': {
            'location': {
              'latLng': {'latitude': destLat, 'longitude': destLng},
            },
          },
        },
      ],
      'travelMode': 'DRIVE',
    });

    try {
      final response = await http.post(
        uri,
        headers: {
          'Content-Type': 'application/json',
          'X-Goog-Api-Key': _mapsApiKey,
          'X-Goog-FieldMask': 'originIndex,destinationIndex,distanceMeters,condition,status',
          ..._androidHeaders,
        },
        body: body,
      );
      // ignore: avoid_print
      print('RouteMatrix status=${response.statusCode} body=${response.body}');
      if (response.statusCode == 200) {
        final decoded = jsonDecode(response.body);
        // The REST response is a JSON array of elements (one per
        // origin/destination pair). We only send one pair.
        final elements = decoded is List ? decoded : [decoded];
        if (elements.isNotEmpty) {
          final element = elements.first as Map<String, dynamic>;
          final condition = element['condition'];
          final meters = element['distanceMeters'];
          if (condition == 'ROUTE_EXISTS' && meters is num) {
            final km = meters / 1000.0;
            // ignore: avoid_print
            print('Road distance from Routes API: ${km}km');
            return km;
          }
          // ignore: avoid_print
          print('RouteMatrix element condition=$condition status=${element['status']}');
        }
      } else {
        // Typical causes: 403 PERMISSION_DENIED = Routes API not enabled
        // or not allowed by the API key's restrictions.
        // ignore: avoid_print
        print('RouteMatrix error ${response.statusCode}: ${response.body}');
      }
    } catch (e) {
      // ignore: avoid_print
      print('RouteMatrix exception: $e');
    }

    final fallback = _haversineKm(hub['lat']!, hub['lng']!, destLat, destLng);
    // ignore: avoid_print
    print('Falling back to haversine estimate: ${fallback}km');
    return fallback;
  }

  /// Straight-line distance fallback (used only if the Routes API call fails).
  /// Multiplied by 1.3 as a rough "road winding factor" so it's not an
  /// unrealistic underestimate compared to actual driving distance.
  static double _haversineKm(
    double lat1,
    double lng1,
    double lat2,
    double lng2,
  ) {
    const double earthRadiusKm = 6371;
    final dLat = _deg2rad(lat2 - lat1);
    final dLng = _deg2rad(lng2 - lng1);
    final a = math.pow(math.sin(dLat / 2), 2) +
        math.cos(_deg2rad(lat1)) *
            math.cos(_deg2rad(lat2)) *
            math.pow(math.sin(dLng / 2), 2);
    final c = 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a));
    final straightLineKm = earthRadiusKm * c;
    return straightLineKm * 1.3;
  }

  static double _deg2rad(double deg) => deg * (math.pi / 180.0);

  /// Looks up the matching fee slab in Firestore for the given distance,
  /// and computes GST + total. Returns beyondServiceRange = true if the
  /// distance exceeds the highest configured slab (typically 21km+).
  static Future<DistanceFeeResult> calculateFee(
    double distanceKm, {
    required String serviceType,
  }) async {
    try {
      final snap = await FirebaseFirestore.instance
          .collection('visit_fee_slabs')
          .get();

      // ignore: avoid_print
      print('visit_fee_slabs total docs in collection: ${snap.docs.length}, checking distanceKm=$distanceKm for serviceType=$serviceType');
      for (final doc in snap.docs) {
        // ignore: avoid_print
        print('  slab ${doc.id}: ${doc.data()}');
      }

      final activeDocs = snap.docs.where((doc) {
        final data = doc.data();
        // Treat missing 'active' field as active=true too, so a typo'd
        // field name doesn't silently exclude a slab.
        final isActive = data['active'] == null || data['active'] == true;
        // Existing repairing slabs predate the serviceType field — treat
        // a missing serviceType as 'repairing' so nothing already
        // configured silently breaks.
        final docServiceType = (data['serviceType'] as String?)?.trim().toLowerCase() ?? 'repairing';
        return isActive && docServiceType == serviceType.toLowerCase();
      }).toList();

      if (activeDocs.isEmpty) {
        // No slabs configured at all — this is a setup issue, not a
        // genuine "customer too far away" case. Surface it distinctly.
        return DistanceFeeResult(
          distanceKm: distanceKm,
          status: FeeStatus.configMissing,
          siteVisitFee: 0,
          gstPercent: 0,
          gstAmount: 0,
          totalPayable: 0,
        );
      }

      Map<String, dynamic>? matchedSlab;
      String? matchedId;
      double highestToKm = 0;

      for (final doc in activeDocs) {
        final rawData = doc.data();
        // Defensive: normalize keys in case a field name has stray
        // leading/trailing whitespace from manual Firestore Console entry
        // (this silently breaks a plain data['fromKm'] lookup).
        final data = <String, dynamic>{
          for (final entry in rawData.entries) entry.key.trim(): entry.value,
        };
        final fromKm = _asDouble(data['fromKm']);
        final toKm = _asDouble(data['toKm']);
        if (fromKm == null || toKm == null) {
          // ignore: avoid_print
          print('Slab ${doc.id} skipped — missing/unparseable fromKm or toKm. Raw keys: ${rawData.keys.map((k) => "\"$k\"").join(", ")}');
          continue;
        }
        if (toKm > highestToKm) highestToKm = toKm;
        if (distanceKm >= fromKm && distanceKm <= toKm) {
          matchedSlab = data;
          matchedId = doc.id;
        }
      }

      // ignore: avoid_print
      print('Matched slab: $matchedId (highestToKm considered: $highestToKm)');

      if (matchedSlab == null) {
        // Genuinely beyond the highest configured slab (e.g. > 21km)
        return DistanceFeeResult(
          distanceKm: distanceKm,
          status: FeeStatus.beyondRange,
          siteVisitFee: 0,
          gstPercent: 0,
          gstAmount: 0,
          totalPayable: 0,
        );
      }

      final fee = _asDouble(matchedSlab['fee']) ?? 0;
      final gstPercent = _asDouble(matchedSlab['gstPercent']) ?? 0;
      final gstAmount = fee * gstPercent / 100;
      final total = fee + gstAmount;

      return DistanceFeeResult(
        distanceKm: distanceKm,
        status: FeeStatus.ok,
        slabId: matchedId,
        siteVisitFee: fee,
        gstPercent: gstPercent,
        gstAmount: gstAmount,
        totalPayable: total,
      );
    } catch (e) {
      // ignore: avoid_print
      print('calculateFee error: $e');
      return DistanceFeeResult(
        distanceKm: distanceKm,
        status: FeeStatus.configMissing,
        siteVisitFee: 0,
        gstPercent: 0,
        gstAmount: 0,
        totalPayable: 0,
      );
    }
  }

  static double? _asDouble(dynamic value) {
    if (value == null) return null;
    if (value is num) return value.toDouble();
    if (value is String) return double.tryParse(value);
    return null;
  }
}