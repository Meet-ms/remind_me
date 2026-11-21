import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:material_ui/material_ui.dart';

import '../models/condition.dart';
import '../services/geofence_service.dart';
import '../services/place_search.dart';
import '../services/sensor_service.dart';

// Shown until the user's own location is known.
const _fallbackCenter = LatLng(19.0760, 72.8777); // Mumbai

/// Full-screen editor for a [LocationCondition]: pick the place on a map,
/// search by name, set the radius and whether to trigger on arrive/leave.
class MapPickerPage extends StatefulWidget {
  const MapPickerPage({super.key, this.initial});
  final LocationCondition? initial;

  @override
  State<MapPickerPage> createState() => _MapPickerPageState();
}

class _MapPickerPageState extends State<MapPickerPage> {
  final _map = MapController();
  final _search = TextEditingController();
  final _label = TextEditingController();
  List<PlaceResult> _results = [];
  bool _searching = false;
  bool _locating = false;
  LatLng? _point;
  late double _radius;
  late LocationTrigger _trigger;

  @override
  void initState() {
    super.initState();
    final i = widget.initial;
    if (i != null) {
      _point = LatLng(i.latitude, i.longitude);
      _label.text = i.label;
    }
    _radius = (i?.radiusMeters ?? 150).clamp(minGeofenceRadius, 2000);
    _trigger = i?.trigger ?? LocationTrigger.arrive;
    if (i == null) _goToMyLocation(select: false);
  }

  @override
  void dispose() {
    _search.dispose();
    _label.dispose();
    _map.dispose();
    super.dispose();
  }

  Future<void> _goToMyLocation({bool select = true}) async {
    setState(() => _locating = true);
    final pos = await SensorService().currentPosition();
    if (!mounted) return;
    setState(() => _locating = false);
    if (pos == null) {
      if (select) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not get your location.')),
        );
      }
      return;
    }
    final here = LatLng(pos.lat, pos.lon);
    // Don't override a place the user already picked while we were locating.
    if (select || _point == null) {
      _map.move(here, 16);
      if (select) setState(() => _point = here);
    }
  }

  Future<void> _runSearch() async {
    final q = _search.text.trim();
    if (q.isEmpty) return;
    FocusScope.of(context).unfocus();
    setState(() => _searching = true);
    try {
      final r = await PlaceSearch.search(q);
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

  void _choose(PlaceResult r) {
    final p = LatLng(r.lat, r.lon);
    setState(() {
      _point = p;
      _results = [];
      if (_label.text.isEmpty) _label.text = r.name.split(',').first.trim();
    });
    _map.move(p, 16);
  }

  void _save() {
    final p = _point!;
    Navigator.pop(
      context,
      LocationCondition(
        latitude: p.latitude,
        longitude: p.longitude,
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
                FlutterMap(
                  mapController: _map,
                  options: MapOptions(
                    initialCenter: point ?? _fallbackCenter,
                    initialZoom: point == null ? 11 : 16,
                    onTap: (_, latLng) => setState(() => _point = latLng),
                  ),
                  children: [
                    TileLayer(
                      urlTemplate:
                          'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                      userAgentPackageName: 'com.example.remind_me',
                    ),
                    if (point != null)
                      CircleLayer(
                        circles: [
                          CircleMarker(
                            point: point,
                            radius: _radius,
                            useRadiusInMeter: true,
                            color: theme.colorScheme.primary.withValues(
                              alpha: 0.18,
                            ),
                            borderColor: theme.colorScheme.primary,
                            borderStrokeWidth: 2,
                          ),
                        ],
                      ),
                    if (point != null)
                      MarkerLayer(
                        markers: [
                          Marker(
                            point: point,
                            width: 44,
                            height: 44,
                            alignment: Alignment.topCenter,
                            child: Icon(
                              Icons.location_on,
                              size: 44,
                              color: theme.colorScheme.error,
                            ),
                          ),
                        ],
                      ),
                    const SimpleAttributionWidget(
                      source: Text('OpenStreetMap contributors'),
                    ),
                  ],
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
                          child: Slider(
                            min: minGeofenceRadius,
                            max: 2000,
                            value: _radius,
                            onChanged: (v) => setState(() => _radius = v),
                          ),
                        ),
                      ],
                    ),
                    TextField(
                      controller: _label,
                      decoration: const InputDecoration(
                        labelText: 'Place name (optional)',
                        isDense: true,
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
