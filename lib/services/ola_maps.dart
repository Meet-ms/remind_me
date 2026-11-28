import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// Ola Maps access. The key is supplied at build time and never committed:
/// `flutter run --dart-define-from-file=dart_defines.json`
/// with `{"OLA_MAPS_API_KEY": "..."}` in that (git-ignored) file.
class OlaMaps {
  static const apiKey = String.fromEnvironment('OLA_MAPS_API_KEY');
  static bool get isConfigured => apiKey.isNotEmpty;

  static const host = 'api.olamaps.io';
  static const _styleUrl =
      'https://$host/tiles/vector/v1/styles/default-light-standard/style.json';

  static String? _style;

  /// The map style JSON, rewritten so it works with a key. The renderer
  /// fetches tiles, glyphs and sprites with the URLs exactly as written, so
  /// each Ola URL must carry the key itself.
  static Future<String> loadStyle() async {
    final cached = _style;
    if (cached != null) return cached;

    final res = await _get(_styleUrl);
    if (res.statusCode != 200) {
      throw http.ClientException(
        res.statusCode == 401 || res.statusCode == 403
            ? 'Ola Maps rejected the API key.'
            : 'Map style failed to load (${res.statusCode}).',
      );
    }
    final style = jsonDecode(res.body) as Map<String, dynamic>;

    final sources = style['sources'];
    if (sources is Map) {
      await Future.wait([
        for (final entry in sources.entries)
          if (entry.value is Map)
            _inlineSource(sources, entry.key as String, entry.value as Map),
      ]);
    }
    final glyphs = style['glyphs'];
    if (glyphs is String) style['glyphs'] = withKey(glyphs);

    final sprite = style['sprite'];
    if (sprite is String) {
      final local = await _cacheSprite(sprite);
      if (local == null) {
        style.remove('sprite'); // map still works, only icons are missing
      } else {
        style['sprite'] = local;
      }
    }

    return _style = jsonEncode(style);
  }

  static Future<http.Response> _get(String url) =>
      http.get(Uri.parse(withKey(url))).timeout(const Duration(seconds: 15));

  /// A source given as a TileJSON `url` is replaced by its contents, because
  /// the tile URLs inside it would not carry the key.
  static Future<void> _inlineSource(Map sources, String id, Map source) async {
    final url = source['url'];
    if (url is String) {
      final res = await _get(url);
      if (res.statusCode != 200) {
        throw http.ClientException(
          'Map data failed to load (${res.statusCode}).',
        );
      }
      final json = jsonDecode(res.body) as Map<String, dynamic>;
      sources[id] = {
        'type': source['type'],
        for (final k in const ['minzoom', 'maxzoom', 'attribution', 'bounds'])
          if (json[k] != null) k: json[k],
        'tiles': [for (final t in json['tiles'] as List) withKey(t as String)],
      };
    } else if (source['tiles'] is List) {
      source['tiles'] = [
        for (final t in source['tiles'] as List) withKey(t as String),
      ];
    }
  }

  /// The sprite sheet URL cannot carry a key, since the renderer appends
  /// `.json` / `@2x.png` to it. So the files are downloaded once and the
  /// style points at local copies. Returns null if that fails.
  static Future<String?> _cacheSprite(String sprite) async {
    try {
      final dir = Directory(
        p.join((await getApplicationSupportDirectory()).path, 'ola_sprite'),
      );
      await dir.create(recursive: true);
      for (final name in const ['sprite.json', 'sprite.png']) {
        final file = File(p.join(dir.path, name));
        if (await file.exists()) continue;
        final res = await _get('$sprite${name.substring('sprite'.length)}');
        if (res.statusCode != 200) return null;
        await file.writeAsBytes(res.bodyBytes);
      }
      for (final name in const ['sprite@2x.json', 'sprite@2x.png']) {
        final file = File(p.join(dir.path, name));
        if (await file.exists()) continue;
        final res = await _get('$sprite${name.substring('sprite'.length)}');
        if (res.statusCode == 200) await file.writeAsBytes(res.bodyBytes);
      }
      return Uri.file(p.join(dir.path, 'sprite')).toString();
    } catch (_) {
      return null;
    }
  }

  /// Appends the key to Ola URLs. Plain string handling, because Uri would
  /// percent-encode the `{z}/{x}/{y}` and `{fontstack}` placeholders.
  static String withKey(String url) {
    if (!url.contains(host) || url.contains('api_key=')) return url;
    return '$url${url.contains('?') ? '&' : '?'}api_key=$apiKey';
  }
}
