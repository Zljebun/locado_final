import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:http/http.dart' as http;
import 'package:location/location.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';

class SearchLocationScreen extends StatefulWidget {
  @override
  _SearchLocationScreenState createState() => _SearchLocationScreenState();
}

class _SearchLocationScreenState extends State<SearchLocationScreen> {
  TextEditingController _searchController = TextEditingController();
  GoogleMapController? _mapController;
  Set<Marker> _markers = {};

  // Default: Vienna
  LatLng _currentCenter = LatLng(48.210033, 16.363449);
  LatLng? _userLatLng;
  bool _isLoading = false;
  bool _isSearching = false;

  static String get googleApiKey => dotenv.env['GOOGLE_MAPS_API_KEY'] ?? '';

  @override
  void initState() {
    super.initState();
    _getUserLocation();
  }

  Future<void> _getUserLocation() async {
    try {
      setState(() => _isLoading = true);

      Location location = Location();
      PermissionStatus permissionGranted = await location.hasPermission();
      if (permissionGranted == PermissionStatus.denied) {
        permissionGranted = await location.requestPermission();
        if (permissionGranted != PermissionStatus.granted) return;
      }
      LocationData locationData = await location.getLocation();
      setState(() {
        _userLatLng = LatLng(locationData.latitude!, locationData.longitude!);
        _currentCenter = _userLatLng!; // pomeri kameru na korisnika
      });
      _updateUserLocationMarker();
    } catch (e) {
      // Ako GPS ne radi, ostaje default centar
    } finally {
      setState(() => _isLoading = false);
    }
  }

  void _updateUserLocationMarker() {
    if (_userLatLng == null) return;
    // Uklanjamo plavi marker - ostaje samo plavi dot
    setState(() {
      _markers.removeWhere((m) => m.markerId.value == 'user_location');
    });
  }

  Future<void> _searchPlaces() async {
    final searchTerm = _searchController.text.trim().toLowerCase();
    if (searchTerm.isEmpty) {
      _showSnackBar('Please enter a search term', Colors.orange);
      return;
    }

    final LatLng searchCenter = _userLatLng ?? _currentCenter;

    setState(() {
      _isSearching = true;
      _markers.clear();
    });

    try {
      final url =
          'https://maps.googleapis.com/maps/api/place/nearbysearch/json'
          '?location=${searchCenter.latitude},${searchCenter.longitude}'
          '&radius=5000'
          '&keyword=${Uri.encodeComponent(searchTerm)}'
          '&key=$googleApiKey';

      final response = await http.get(Uri.parse(url));
      if (response.statusCode == 200) {
        final body = json.decode(response.body);
        final List results = body['results'];
        Set<Marker> foundMarkers = {};

        // User location - samo plavi dot, bez marker-a
        // (myLocationEnabled: true će prikazati plavi dot automatski)

        // Place markers
        for (final place in results) {
          final lat = place['geometry']['location']['lat'];
          final lng = place['geometry']['location']['lng'];
          final name = place['name'];
          foundMarkers.add(
            Marker(
              markerId: MarkerId(place['place_id']),
              position: LatLng(lat, lng),
              infoWindow: InfoWindow(title: name),
              onTap: () {
                Navigator.pop(context, {
                  'latitude': lat,
                  'longitude': lng,
                  'name': name,
                });
              },
            ),
          );
        }

        setState(() {
          _markers = foundMarkers;
        });

        // Focus na search centar
        if (_mapController != null && searchCenter != null) {
          _mapController!.animateCamera(
            CameraUpdate.newLatLngZoom(searchCenter, 14),
          );
        }

        if (results.isEmpty) {
          _showSnackBar('No locations found for "$searchTerm"', Colors.blue);
        } else {
          _showSnackBar('Found ${results.length} locations', Colors.green);
        }
      } else {
        _showSnackBar('Failed to fetch locations', Colors.red);
      }
    } catch (e) {
      _showSnackBar('Search error: ${e.toString()}', Colors.red);
    } finally {
      setState(() => _isSearching = false);
    }
  }

  void _showSnackBar(String message, Color color) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: color,
        duration: Duration(seconds: 3),
      ),
    );
  }

  void _showTips() {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: Row(
            children: [
              Icon(Icons.lightbulb, color: Colors.teal),
              const SizedBox(width: 8),
              const Text('Search Tips'),
            ],
          ),
          content: SizedBox(
            width: 300,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildTipItem(Icons.search, 'Search by name',
                    'Try "Hofer", "Billa", "pharmacy", "restaurant"'),
                const SizedBox(height: 12),
                _buildTipItem(Icons.location_on, 'Tap to select',
                    'Tap any marker on the map to select that location'),
                const SizedBox(height: 12),
                _buildTipItem(Icons.my_location, 'Search nearby',
                    'Results are shown within 5km of your location'),
                const SizedBox(height: 12),
                _buildTipItem(Icons.clear, 'Clear results',
                    'Search again to update results on the map'),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Got it!'),
            ),
          ],
        );
      },
    );
  }

  Widget _buildTipItem(IconData icon, String title, String description) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, color: Colors.teal, size: 20),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
              Text(description, style: TextStyle(color: Colors.grey.shade600, fontSize: 12)),
            ],
          ),
        ),
      ],
    );
  }

  void _clearSearch() {
    _searchController.clear();
    setState(() {
      _markers.clear();
    });
    _updateUserLocationMarker();
    FocusScope.of(context).unfocus();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Search Location'),
        backgroundColor: Colors.teal,
        foregroundColor: Colors.white,
        actions: [
          // Tips button
          IconButton(
            onPressed: _showTips,
            icon: const Icon(Icons.lightbulb_outline),
            tooltip: 'Search Tips',
          ),
        ],
      ),
      resizeToAvoidBottomInset: true,
      body: Column(
        children: [
          // 🎯 MINIMALNI SEARCH BAR - samo text field
          Container(
            margin: const EdgeInsets.all(12),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _searchController,
                    decoration: InputDecoration(
                      hintText: 'Search places (Hofer, pharmacy, restaurant...)',
                      border: const OutlineInputBorder(),
                      prefixIcon: const Icon(Icons.search, size: 20),
                      suffixIcon: _searchController.text.isNotEmpty
                          ? IconButton(
                        icon: const Icon(Icons.clear, size: 20),
                        onPressed: _clearSearch,
                      )
                          : null,
                      filled: true,
                      fillColor: Colors.grey.shade50,
                      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
                    ),
                    onSubmitted: (_) => _searchPlaces(),
                    onChanged: (value) => setState(() {}),
                  ),
                ),
                const SizedBox(width: 8),
                // Search button
                Container(
                  height: 48,
                  child: ElevatedButton(
                    onPressed: _isSearching ? null : _searchPlaces,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.teal,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                    child: _isSearching
                        ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                        : const Icon(Icons.search, size: 20),
                  ),
                ),
              ],
            ),
          ),

          // 🗺️ MAKSIMALNA MAPA sa overlay elementima
          Expanded(
            child: Container(
              margin: const EdgeInsets.symmetric(horizontal: 12),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(12),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black12,
                    blurRadius: 8,
                    offset: Offset(0, 4),
                  ),
                ],
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: Stack(
                  children: [
                    // Glavna mapa
                    GoogleMap(
                      initialCameraPosition: CameraPosition(
                        target: _currentCenter,
                        zoom: 14,
                      ),
                      myLocationEnabled: true, // Plavi dot
                      myLocationButtonEnabled: false,
                      markers: _markers,
                      onMapCreated: (controller) => _mapController = controller,
                      mapToolbarEnabled: false,
                    ),

                    // Veoma diskretna instrukcija na vrhu mape
                    Positioned(
                      top: 16,
                      left: 16,
                      right: 16,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                        decoration: BoxDecoration(
                          color: Colors.black.withOpacity(0.4),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.touch_app, color: Colors.white.withOpacity(0.8), size: 14),
                            const SizedBox(width: 6),
                            Text(
                              'Tap marker to select',
                              style: TextStyle(
                                color: Colors.white.withOpacity(0.8),
                                fontSize: 12,
                                fontWeight: FontWeight.w400,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),

                    // Clear button na mapi (gore desno, ispod tips)
                    if (_markers.isNotEmpty)
                      Positioned(
                        top: 60,
                        right: 16,
                        child: FloatingActionButton.small(
                          onPressed: _clearSearch,
                          backgroundColor: Colors.white,
                          foregroundColor: Colors.grey.shade700,
                          child: const Icon(Icons.clear_all, size: 20),
                        ),
                      ),

                    // My location button (gore levo)
                    Positioned(
                      top: 60,
                      left: 16,
                      child: FloatingActionButton.small(
                        onPressed: _isLoading ? null : () async {
                          await _getUserLocation();
                          if (_userLatLng != null && _mapController != null) {
                            _mapController!.animateCamera(
                              CameraUpdate.newCameraPosition(
                                CameraPosition(
                                  target: _userLatLng!,
                                  zoom: 16,
                                ),
                              ),
                            );
                          }
                        },
                        backgroundColor: Colors.white,
                        foregroundColor: Colors.blue,
                        child: _isLoading
                            ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.blue,
                          ),
                        )
                            : const Icon(Icons.my_location, size: 20),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),

          // Samo mali spacer na dnu
          const SizedBox(height: 12),
        ],
      ),
    );
  }
}