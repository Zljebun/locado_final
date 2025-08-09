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

// OPTIMIZED: OpenStreetMap Widget with instant UI and lazy loading
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
  bool _showPlaceholder = true;
  bool _mapInitialized = false;

  @override
  void initState() {
    super.initState();
    _mapController = MapController();
    
    // 🚀 INSTANT UI: Show placeholder first, load map after delay
    _initializeMapWithDelay();
  }

  /// Initialize map with delay to prevent blocking UI
  void _initializeMapWithDelay() {
    print('🗺️ OSM WIDGET: Showing placeholder, will load map in background...');
    
    // Wait for UI to render, then load map
    Future.delayed(const Duration(milliseconds: 200), () {
      if (mounted) {
        setState(() {
          _showPlaceholder = false;
        });
        
        // Give map controller another moment to initialize
        Future.delayed(const Duration(milliseconds: 100), () {
          if (mounted) {
            _mapInitialized = true;
            widget.onMapCreated?.call(_mapController);
            print('✅ OSM WIDGET: Map initialized and ready');
          }
        });
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    // 🚀 INSTANT UI: Show placeholder while map loads
    if (_showPlaceholder) {
      return _buildMapPlaceholder();
    }

    // 🗺️ ACTUAL MAP: Show only after delay
    return _buildActualMap();
  }

  /// Build instant placeholder that looks like a map
  Widget _buildMapPlaceholder() {
    return Container(
      width: double.infinity,
      height: double.infinity,
      color: Colors.grey.shade100,
      child: Stack(
        children: [
          // Map-like background pattern
          Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  Colors.blue.shade50,
                  Colors.green.shade50,
                  Colors.grey.shade100,
                ],
                stops: const [0.0, 0.6, 1.0],
              ),
            ),
          ),
          
          // Grid pattern to look like map tiles
          CustomPaint(
            size: Size.infinite,
            painter: MapGridPainter(),
          ),
          
          // Loading indicator
          Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.9),
                    borderRadius: BorderRadius.circular(12),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.1),
                        blurRadius: 8,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(
                        Icons.map,
                        color: Colors.teal,
                        size: 32,
                      ),
                      const SizedBox(height: 8),
                      const Text(
                        'Loading Map...',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w500,
                          color: Colors.teal,
                        ),
                      ),
                      const SizedBox(height: 8),
                      SizedBox(
                        width: 100,
                        child: LinearProgressIndicator(
                          backgroundColor: Colors.grey.shade300,
                          valueColor: const AlwaysStoppedAnimation<Color>(Colors.teal),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          
          // Show cached markers on placeholder if available
          if (widget.markers.isNotEmpty)
            ...widget.markers.take(5).map((marker) => 
              Positioned(
                left: 200 + (widget.markers.toList().indexOf(marker) * 20),
                top: 300 + (widget.markers.toList().indexOf(marker) * 15),
                child: Container(
                  width: 24,
                  height: 24,
                  decoration: BoxDecoration(
                    color: Colors.red.withOpacity(0.7),
                    shape: BoxShape.circle,
                    border: Border.all(color: Colors.white, width: 2),
                  ),
                  child: const Icon(
                    Icons.location_on,
                    color: Colors.white,
                    size: 12,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  /// Build the actual OSM map
  Widget _buildActualMap() {
    return FlutterMap(
      mapController: _mapController,
      options: MapOptions(
        initialCenter: widget.initialCameraPosition.target,
        initialZoom: widget.initialCameraPosition.zoom,
        onMapReady: () {
          if (!_mapInitialized) {
            _mapInitialized = true;
            widget.onMapCreated?.call(_mapController);
            print('✅ OSM WIDGET: Map ready callback triggered');
          }
        },
        onTap: (tapPosition, point) {
          widget.onTap?.call(point);
        },
        onLongPress: (tapPosition, point) {
          widget.onLongPress?.call(point);
        },
      ),
      children: [
        // OPTIMIZED: OpenStreetMap tile layer with faster tile server
        TileLayer(
          urlTemplate: 'https://tile.openstreetmap.de/{z}/{x}/{y}.png',
          userAgentPackageName: 'com.example.locado_final',
          maxZoom: 18,
          additionalOptions: {
            'cache': 'force-cache',
          },
        ),
        
        // Markers layer - load with delay
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
    if (_mapInitialized) {
      _mapController.move(
        cameraUpdate.cameraPosition.target,
        cameraUpdate.cameraPosition.zoom,
      );
    }
  }

  // Method to get screen coordinate (compatible with Google Maps interface)
  Future<gmaps.ScreenCoordinate> getScreenCoordinate(ll.LatLng latLng) async {
    return gmaps.ScreenCoordinate(x: 0, y: 0);
  }
}

/// Custom painter for map-like grid background
class MapGridPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.grey.withOpacity(0.1)
      ..strokeWidth = 1;

    // Draw vertical lines
    for (int i = 0; i < size.width; i += 50) {
      canvas.drawLine(
        Offset(i.toDouble(), 0),
        Offset(i.toDouble(), size.height),
        paint,
      );
    }

    // Draw horizontal lines
    for (int i = 0; i < size.height; i += 50) {
      canvas.drawLine(
        Offset(0, i.toDouble()),
        Offset(size.width, i.toDouble()),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(CustomPainter oldDelegate) => false;
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