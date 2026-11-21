import 'dart:convert';

import 'package:http/http.dart' as http;

class PlaceResult {
  const PlaceResult(this.name, this.lat, this.lon);
  final String name;
  final double lat;
  final double lon;
}

/// Place-name search backed by OpenStreetMap Nominatim. Its usage policy
/// asks for an identifying User-Agent and at most one request per second, so
/// searches are only made on submit and are rate limited here.
class PlaceSearch {
  static DateTime _last = DateTime.fromMillisecondsSinceEpoch(0);

  static Future<List<PlaceResult>> search(String query) async {
    final wait = const Duration(seconds: 1) - DateTime.now().difference(_last);
    if (wait > Duration.zero) await Future<void>.delayed(wait);
    _last = DateTime.now();

    final uri = Uri.https('nominatim.openstreetmap.org', '/search', {
      'q': query,
      'format': 'jsonv2',
      'limit': '6',
    });
    final res = await http
        .get(uri, headers: {'User-Agent': 'remind_me/1.0 (Flutter app)'})
        .timeout(const Duration(seconds: 15));
    if (res.statusCode != 200) {
      throw http.ClientException('Search failed (${res.statusCode})', uri);
    }
    return (jsonDecode(res.body) as List).map((e) {
      final m = e as Map<String, dynamic>;
      return PlaceResult(
        (m['display_name'] as String?) ?? query,
        double.parse(m['lat'] as String),
        double.parse(m['lon'] as String),
      );
    }).toList();
  }
}
