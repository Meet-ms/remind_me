import 'dart:convert';

import 'package:http/http.dart' as http;

import 'ola_maps.dart';

class PlaceResult {
  const PlaceResult({
    required this.name,
    required this.placeId,
    this.lat,
    this.lon,
  });
  final String name;
  final String placeId;

  /// Null until [PlaceSearch.resolve] is called, if the search response did
  /// not already include coordinates.
  final double? lat;
  final double? lon;
}

/// Place-name search backed by the Ola Maps Places API.
class PlaceSearch {
  static Future<Map<String, dynamic>> _get(
    String path,
    Map<String, String> query,
  ) async {
    final uri = Uri.https(OlaMaps.host, path, {
      ...query,
      'api_key': OlaMaps.apiKey,
    });
    final res = await http.get(uri).timeout(const Duration(seconds: 15));
    if (res.statusCode != 200) {
      throw http.ClientException('Search failed (${res.statusCode})', uri);
    }
    return jsonDecode(res.body) as Map<String, dynamic>;
  }

  static (double, double)? _location(Map<String, dynamic> m) {
    final loc = (m['geometry'] as Map?)?['location'] as Map?;
    final lat = loc?['lat'];
    final lng = loc?['lng'];
    return lat is num && lng is num ? (lat.toDouble(), lng.toDouble()) : null;
  }

  /// [nearLat]/[nearLon] only bias the ranking towards that point.
  static Future<List<PlaceResult>> search(
    String query, {
    double? nearLat,
    double? nearLon,
  }) async {
    final body = await _get('/places/v1/autocomplete', {
      'input': query,
      if (nearLat != null && nearLon != null) 'location': '$nearLat,$nearLon',
    });
    final results = <PlaceResult>[];
    for (final p in (body['predictions'] as List? ?? const [])) {
      final m = p as Map<String, dynamic>;
      final id = m['place_id'] as String?;
      if (id == null) continue;
      final loc = _location(m);
      results.add(
        PlaceResult(
          name: (m['description'] as String?) ?? query,
          placeId: id,
          lat: loc?.$1,
          lon: loc?.$2,
        ),
      );
    }
    return results;
  }

  /// A short name for the place at the given point, or null if none is found.
  static Future<String?> reverse(double lat, double lon) async {
    final body = await _get('/places/v1/reverse-geocode', {
      'latlng': '$lat,$lon',
    });
    final results = body['results'] as List? ?? const [];
    if (results.isEmpty) return null;
    final first = results.first as Map<String, dynamic>;
    final name = (first['name'] as String?)?.trim() ?? '';
    if (name.isNotEmpty) return name;
    final address = (first['formatted_address'] as String?)?.trim() ?? '';
    return address.isEmpty ? null : address.split(',').first.trim();
  }

  /// Fills in coordinates for a result that has none yet.
  static Future<PlaceResult> resolve(PlaceResult r) async {
    if (r.lat != null && r.lon != null) return r;
    final body = await _get('/places/v1/details', {'place_id': r.placeId});
    final result = (body['result'] as Map?)?.cast<String, dynamic>() ?? {};
    final loc = _location(result);
    if (loc == null) throw const FormatException('Place has no coordinates');
    return PlaceResult(
      name: r.name,
      placeId: r.placeId,
      lat: loc.$1,
      lon: loc.$2,
    );
  }
}
