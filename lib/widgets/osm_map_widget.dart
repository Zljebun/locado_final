import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart' as ll;
import 'package:google_maps_flutter/google_maps_flutter.dart' as gmaps;

// Custom marker data class for OSM
class OSMMarker {
  final String markerId;
  final ll.LatLng position;
  final Widget child;
  final VoidCallback? onTap;
  final String? title;
  final String? snippet;

  OSMMarker({
    required this.markerId,
    required this.position,
    required this.child,
    this.onTap,
    this.title,
    this.snippet,
  });
}

// Camera position class compatible with Google Maps
class OSMCameraPosition {
  final ll.LatLng target;
  final double zoom;
  final double bearing;
  final double tilt;

  OSMCameraPosition({
    required this.target,
    this.zoom = 15.0,
    this.bearing = 0.0,
    this.tilt = 0.0,
  });
}

// Camera update class compatible with Google Maps
class OSMCameraUpdate {
  final OSMCameraPosition cameraPosition;

  OSMCameraUpdate._(this.cameraPosition);

  static OSMCameraUpdate newCameraPosition(OSMCameraPosition cameraPosition) {
    return OSMCameraUpdate._(cameraPosition);
  }

  static OSMCameraUpdate newLatLngZoom(ll.LatLng target, double zoom) {
    return OSMCameraUpdate._(OSMCameraPosition(target: target, zoom: zoom));
  }
}

// OpenStreetMap Widget that mimics Google Maps interface
class OSMMapWidget extends StatefulWidget {
  final OSMCameraPosition initialCameraPosition;
  final Set<OSMMarker> markers;
  final Function(MapController)? onMapCreated;
  final bool myLocationEnabled;
  final bool myLocationButtonEnabled;
  final Function(ll.LatLng)? onTap;
  final Function(ll.LatLng)? onLongPress;

  const OSMMapWidget({
    Key? key,
    required this.initialCameraPosition,
    this.markers = const {},
    this.onMapCreated,
    this.myLocationEnabled = false,
    this.myLocationButtonEnabled = false,
    this.onTap,
    this.onLongPress,
  }) : super(key: key);

  @override
  State<OSMMapWidget> createState() => _OSMMapWidgetState();
}

class _OSMMapWidgetState extends State<OSMMapWidget> {
  late MapController _mapController;

  @override
  void initState() {
    super.initState();
    _mapController = MapController();
  }

  @override
  Widget build(BuildContext context) {
    return FlutterMap(
      mapController: _mapController,
      options: MapOptions(
        initialCenter: widget.initialCameraPosition.target,
        initialZoom: widget.initialCameraPosition.zoom,
        onMapReady: () {
          widget.onMapCreated?.call(_mapController);
        },
        onTap: (tapPosition, point) {
          widget.onTap?.call(point);
        },
        onLongPress: (tapPosition, point) {
          widget.onLongPress?.call(point);
        },
      ),
      children: [
        // OpenStreetMap tile layer
        TileLayer(
          urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
          userAgentPackageName: 'com.example.locado_final',
          maxZoom: 19,
        ),
        
        // Markers layer
        if (widget.markers.isNotEmpty)
          MarkerLayer(
            markers: widget.markers.map((osmMarker) {
              return Marker(
                point: osmMarker.position,
                width: 40,
                height: 40,
                child: GestureDetector(
                  onTap: osmMarker.onTap,
                  child: osmMarker.child,
                ),
              );
            }).toList(),
          ),
      ],
    );
  }

  // Method to animate camera (compatible with Google Maps interface)
  Future<void> animateCamera(OSMCameraUpdate cameraUpdate) async {
    _mapController.move(
      cameraUpdate.cameraPosition.target,
      cameraUpdate.cameraPosition.zoom,
    );
  }

  // Method to get screen coordinate (compatible with Google Maps interface)
  Future<gmaps.ScreenCoordinate> getScreenCoordinate(ll.LatLng latLng) async {
    // This is a simplified implementation
    // In a real scenario, you might need more complex calculations
    return gmaps.ScreenCoordinate(x: 0, y: 0);
  }
}

// Utility class to convert between Google Maps and OSM formats
class OSMConverter {
  // Convert Google Maps LatLng to OSM LatLng
  static ll.LatLng gmapsToOSM(gmaps.LatLng gmapsLatLng) {
    return ll.LatLng(gmapsLatLng.latitude, gmapsLatLng.longitude);
  }

  // Convert OSM LatLng to Google Maps LatLng
  static gmaps.LatLng osmToGmaps(ll.LatLng osmLatLng) {
    return gmaps.LatLng(osmLatLng.latitude, osmLatLng.longitude);
  }

  // Convert Google Maps CameraPosition to OSM CameraPosition
  static OSMCameraPosition gmapsCameraToOSM(gmaps.CameraPosition gCameraPosition) {
    return OSMCameraPosition(
      target: ll.LatLng(gCameraPosition.target.latitude, gCameraPosition.target.longitude),
      zoom: gCameraPosition.zoom,
      bearing: gCameraPosition.bearing,
      tilt: gCameraPosition.tilt,
    );
  }

  // Create default marker widget for OSM
  static Widget createDefaultMarker({Color color = Colors.red}) {
    return Container(
      decoration: BoxDecoration(
        color: color,
        shape: BoxShape.circle,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.3),
            blurRadius: 4,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: const Icon(
        Icons.location_on,
        color: Colors.white,
        size: 20,
      ),
    );
  }
}