import 'dart:async';

import 'package:http/http.dart' as http;
import 'package:maplibre/maplibre.dart';
import 'package:material_ui/material_ui.dart';

import '../models/condition.dart';
import '../services/geofence_service.dart';
import '../services/ola_maps.dart';
import '../services/place_search.dart';
import '../services/sensor_service.dart';
import '../utils/geo.dart';

// Shown until the user's own location is known.
const _fallbackCenter = Geographic(lon: 72.8777, lat: 19.0760); // Mumbai

/// Full-screen editor for a [LocationCondition]: pick the place on a map,
/// search by name, set the radius and whether to trigger on arrive/leave.
class MapPickerPage extends StatefulWidget {
  const MapPickerPage({super.key, this.initial});
  final LocationCondition? initial;

  @override
  State<MapPickerPage> createState() => _MapPickerPageState();
}

class _MapPickerPageState extends State<MapPickerPage> {
  final _search = TextEditingController();
  final _label = TextEditingController();
  MapController? _map;
  // A camera move requested before the map existed.
  Geographic? _pendingCenter;
  String? _style;
  String? _styleError;
  List<PlaceResult> _results = [];
  bool _searching = false;
  bool _locating = false;
  Geographic? _point;
  late double _radius;
  late LocationTrigger _trigger;
  Timer? _nameTimer;
  bool _naming = false;
  // True while the label holds a looked-up name the user hasn't edited.
  bool _labelAuto = false;

  @override
  void initState() {
    super.initState();
    final i = widget.initial;
    if (i != null) {
      _point = Geographic(lon: i.longitude, lat: i.latitude);
      _label.text = i.label;
      if (i.label.isEmpty) _scheduleNameLookup();
    }
    _radius = (i?.radiusMeters ?? 150).clamp(minGeofenceRadius, 2000);
    _trigger = i?.trigger ?? LocationTrigger.arrive;
    _loadStyle();
    if (i == null) _goToMyLocation(select: false);
  }

  @override
  void dispose() {
    _nameTimer?.cancel();
    _search.dispose();
    _label.dispose();
    super.dispose();
  }

  /// Moves the pin. [lookup] is false when the caller already has a name.
  void _setPoint(Geographic p, {bool lookup = true}) {
    setState(() => _point = p);
    if (lookup) {
      _scheduleNameLookup();
    } else {
      _nameTimer?.cancel();
    }
  }

  // Waits until the pin has stayed put before spending an API request.
  void _scheduleNameLookup() {
    _nameTimer?.cancel();
    _nameTimer = Timer(const Duration(seconds: 3), _lookupName);
  }

  Future<void> _lookupName() async {
    final p = _point;
    if (p == null || !OlaMaps.isConfigured) return;
    if (_label.text.isNotEmpty && !_labelAuto) return;
    setState(() => _naming = true);
    String? name;
    try {
      name = await PlaceSearch.reverse(p.lat, p.lon);
    } catch (_) {}
    if (!mounted) return;
    setState(() => _naming = false);
    // Ignore the answer if the pin moved or the user typed meanwhile.
    final stillHere = _point?.lat == p.lat && _point?.lon == p.lon;
    final editable = _label.text.isEmpty || _labelAuto;
    if (name == null || !stillHere || !editable) return;
    setState(() {
      _label.text = name!;
      _labelAuto = true;
    });
  }

  Future<void> _loadStyle() async {
    if (!OlaMaps.isConfigured) {
      setState(() => _styleError = 'Ola Maps API key is not set.');
      return;
    }
    setState(() => _styleError = null);
    try {
      final style = await OlaMaps.loadStyle();
      if (mounted) setState(() => _style = style);
    } on http.ClientException catch (e) {
      if (mounted) setState(() => _styleError = e.message);
    } catch (_) {
      if (mounted) setState(() => _styleError = 'Could not load the map.');
    }
  }

  void _moveTo(Geographic p) {
    final map = _map;
    if (map == null) {
      _pendingCenter = p;
      return;
    }
    map.animateCamera(CameraUpdate.position(center: p, zoom: 16));
  }

  Future<void> _goToMyLocation({bool select = true}) async {
    setState(() => _locating = true);
    final problem = await SensorService.locationProblem(
      requestPermission: true,
    );
    final pos = problem == null
        ? await SensorService().currentPosition()
        : null;
    if (!mounted) return;
    setState(() => _locating = false);
    if (pos == null) {
      if (select) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(problem ?? 'Could not get your location. Try again.'),
          ),
        );
      }
      return;
    }
    final here = Geographic(lon: pos.lon, lat: pos.lat);
    // Don't override a place the user already picked while we were locating.
    if (select || _point == null) {
      _moveTo(here);
      if (select) _setPoint(here);
    }
  }

  Future<void> _runSearch() async {
    final q = _search.text.trim();
    if (q.isEmpty) return;
    FocusScope.of(context).unfocus();
    setState(() => _searching = true);
    try {
      final near = _point;
      final r = await PlaceSearch.search(
        q,
        nearLat: near?.lat,
        nearLon: near?.lon,
      );
      if (!mounted) return;
      setState(() => _results = r);
      if (r.isEmpty) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('No places found.')));
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Search failed. Check your internet.')),
        );
      }
    } finally {
      if (mounted) setState(() => _searching = false);
    }
  }

  Future<void> _choose(PlaceResult r) async {
    setState(() => _results = []);
    try {
      final place = await PlaceSearch.resolve(r);
      if (!mounted) return;
      final p = Geographic(lon: place.lon!, lat: place.lat!);
      // A name picked from search wins over a looked-up one.
      if (_label.text.isEmpty || _labelAuto) {
        _label.text = r.name.split(',').first.trim();
        _labelAuto = false;
      }
      _setPoint(p, lookup: false);
      _moveTo(p);
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not open that place.')),
      );
    }
  }

  void _save() {
    final p = _point!;
    Navigator.pop(
      context,
      LocationCondition(
        latitude: p.lat,
        longitude: p.lon,
        radiusMeters: _radius,
        trigger: _trigger,
        label: _label.text.trim(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final point = _point;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Choose location'),
        actions: [
          TextButton(
            onPressed: point == null ? null : _save,
            child: const Text('Done'),
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
            child: TextField(
              controller: _search,
              textInputAction: TextInputAction.search,
              onSubmitted: (_) => _runSearch(),
              decoration: InputDecoration(
                hintText: 'Search for a place',
                border: const OutlineInputBorder(),
                prefixIcon: const Icon(Icons.search),
                suffixIcon: _searching
                    ? const Padding(
                        padding: EdgeInsets.all(12),
                        child: SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                      )
                    : IconButton(
                        icon: const Icon(Icons.arrow_forward),
                        onPressed: _runSearch,
                      ),
              ),
            ),
          ),
          if (_results.isNotEmpty)
            ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 200),
              child: ListView(
                shrinkWrap: true,
                children: [
                  for (final r in _results)
                    ListTile(
                      dense: true,
                      leading: const Icon(Icons.place_outlined),
                      title: Text(
                        r.name,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      onTap: () => _choose(r),
                    ),
                ],
              ),
            ),
          Expanded(
            child: Stack(
              children: [
                if (_style != null)
                  MapLibreMap(
                    options: MapOptions(
                      style: MapStyle.json(_style!),
                      initCamera: CameraUpdate.position(
                        center: point ?? _fallbackCenter,
                        zoom: point == null ? 11 : 16,
                      ),
                    ),
                    onMapCreated: (c) {
                      _map = c;
                      final pending = _pendingCenter;
                      if (pending != null) {
                        _pendingCenter = null;
                        _moveTo(pending);
                      }
                    },
                    onClick: (e) => _setPoint(e.point),
                    layers: [
                      if (point != null)
                        PolygonLayer(
                          polygons: [
                            Feature(
                              geometry: Polygon.from([
                                [
                                  for (final (lat, lon) in circleRing(
                                    point.lat,
                                    point.lon,
                                    _radius,
                                  ))
                                    Geographic(lon: lon, lat: lat),
                                ],
                              ]),
                            ),
                          ],
                          color: .literal(
                            theme.colorScheme.primary.withValues(alpha: 0.18),
                          ),
                          outlineColor: .literal(theme.colorScheme.primary),
                        ),
                      if (point != null)
                        MarkerLayer(
                          points: [Feature(geometry: Point(point))],
                          icon: .iconData(
                            Icons.location_on,
                            color: theme.colorScheme.error,
                          ),
                          iconAnchor: const .literal(IconAnchor.bottom),
                          iconAllowOverlap: const .literal(true),
                        ),
                    ],
                  )
                else
                  Center(
                    child: _styleError == null
                        ? const CircularProgressIndicator()
                        : Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(_styleError!),
                              if (OlaMaps.isConfigured)
                                TextButton(
                                  onPressed: _loadStyle,
                                  child: const Text('Retry'),
                                ),
                            ],
                          ),
                  ),
                const Positioned(
                  left: 8,
                  bottom: 4,
                  child: Text(
                    '© Ola Maps © OpenStreetMap contributors',
                    style: TextStyle(fontSize: 10),
                  ),
                ),
                Positioned(
                  right: 12,
                  top: 12,
                  child: FloatingActionButton.small(
                    heroTag: 'my_location',
                    onPressed: _locating ? null : () => _goToMyLocation(),
                    child: _locating
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.my_location),
                  ),
                ),
                if (point == null)
                  const Positioned(
                    left: 0,
                    right: 0,
                    bottom: 12,
                    child: Center(
                      child: Chip(label: Text('Tap the map to drop a pin')),
                    ),
                  ),
              ],
            ),
          ),
          Material(
            elevation: 8,
            child: SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    SegmentedButton<LocationTrigger>(
                      segments: const [
                        ButtonSegment(
                          value: LocationTrigger.arrive,
                          icon: Icon(Icons.login),
                          label: Text('When I arrive'),
                        ),
                        ButtonSegment(
                          value: LocationTrigger.leave,
                          icon: Icon(Icons.logout),
                          label: Text('When I leave'),
                        ),
                      ],
                      selected: {_trigger},
                      onSelectionChanged: (s) =>
                          setState(() => _trigger = s.first),
                    ),
                    Row(
                      children: [
                        Text('Radius ${_radius.round()} m'),
                        Expanded(
                          child: SliderTheme(
                            data: SliderTheme.of(context).copyWith(
                              tickMarkShape: SliderTickMarkShape.noTickMark,
                            ),
                            child: Slider(
                              min: minGeofenceRadius,
                              max: 2000,
                              divisions: 199,
                              value: _radius,
                              onChanged: (v) => setState(() => _radius = v),
                            ),
                          ),
                        ),
                      ],
                    ),
                    if (_radius < reliableGeofenceRadius)
                      Text(
                        'Small radius: alerts may be late or missed.',
                        style: theme.textTheme.bodySmall,
                      ),
                    TextField(
                      controller: _label,
                      onChanged: (_) => _labelAuto = false,
                      decoration: InputDecoration(
                        labelText: 'Place name (optional)',
                        isDense: true,
                        suffixIcon: _naming
                            ? const Padding(
                                padding: EdgeInsets.all(10),
                                child: SizedBox(
                                  width: 16,
                                  height: 16,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                  ),
                                ),
                              )
                            : null,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
