import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:http/http.dart' as http;
import 'package:google_maps_flutter/google_maps_flutter.dart' as gmaps;
import 'package:flutter_map/flutter_map.dart' as osm;
import 'package:latlong2/latlong.dart' as ll;
import 'package:geolocator/geolocator.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/task_location.dart';
import '../helpers/database_helper.dart';
import '../location_service.dart';
import '../widgets/osm_map_widget.dart';
import 'dart:math';

// Enum for map provider selection
enum MapProvider { googleMaps, openStreetMap }

// Universal coordinate class
class UniversalLatLng {
  final double latitude;
  final double longitude;

  UniversalLatLng(this.latitude, this.longitude);

  // Convert to Google Maps LatLng
  gmaps.LatLng toGoogleMaps() => gmaps.LatLng(latitude, longitude);
  
  // Convert to OpenStreetMap LatLng
  ll.LatLng toOpenStreetMap() => ll.LatLng(latitude, longitude);

  // Create from Google Maps LatLng
  factory UniversalLatLng.fromGoogleMaps(gmaps.LatLng gLatLng) {
    return UniversalLatLng(gLatLng.latitude, gLatLng.longitude);
  }

  // Create from OpenStreetMap LatLng
  factory UniversalLatLng.fromOpenStreetMap(ll.LatLng osmLatLng) {
    return UniversalLatLng(osmLatLng.latitude, osmLatLng.longitude);
  }

  @override
  String toString() => 'UniversalLatLng($latitude, $longitude)';
}

class SearchIntent {
  final bool isLocalSearch;
  final String? targetLocation;
  final String cleanQuery;
  final String originalQuery;

  SearchIntent({
    required this.isLocalSearch,
    this.targetLocation,
    required this.cleanQuery,
    required this.originalQuery,
  });
}

class AILocationResult {
  final String name;
  final String description;
  final UniversalLatLng coordinates;
  final List<String> taskItems;
  final String category;
  final double? distanceFromUser;
  bool isSelected;

  AILocationResult({
    required this.name,
    required this.description,
    required this.coordinates,
    required this.taskItems,
    required this.category,
    this.distanceFromUser,
    this.isSelected = false,
  });
}

class AILocationSearchScreen extends StatefulWidget {
  final VoidCallback? onTasksCreated;

  const AILocationSearchScreen({Key? key, this.onTasksCreated}) : super(key: key);

  @override
  State<AILocationSearchScreen> createState() => _AILocationSearchScreenState();
}

class _AILocationSearchScreenState extends State<AILocationSearchScreen> {
  final TextEditingController _searchController = TextEditingController();
  List<AILocationResult> _searchResults = [];
  bool _isLoading = false;
  bool _hasSearched = false;
  bool _isLoadingLocation = false;

  // Map provider selection
  MapProvider _currentMapProvider = MapProvider.googleMaps;

  // GPS and location
  Position? _currentPosition;
  String _currentLocationDisplay = "Getting location...";
  UniversalLatLng? _currentLatLng;

  static String get _openAIApiKey => dotenv.env['OPENAI_API_KEY'] ?? '';

  @override
  void initState() {
    super.initState();
    _loadMapProviderSetting();
    _getCurrentLocationPrecise();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  // Load map provider setting
  Future<void> _loadMapProviderSetting() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final useOSM = prefs.getBool('use_openstreetmap') ?? false;
      
      setState(() {
        _currentMapProvider = useOSM ? MapProvider.openStreetMap : MapProvider.googleMaps;
      });

      print('🗺️ AI SEARCH: Loaded map provider: ${_currentMapProvider.name}');
    } catch (e) {
      print('Error loading map provider setting: $e');
      _currentMapProvider = MapProvider.googleMaps;
    }
  }

  List<Map<String, dynamic>> _getSearchHints() {
    return [
      {
        'text': 'Restaurants nearby',
        'icon': Icons.restaurant,
        'color': Colors.orange,
        'query': 'restaurants nearby',
      },
      {
        'text': 'Coffee shops',
        'icon': Icons.local_cafe,
        'color': Colors.brown,
        'query': 'coffee shops nearby',
      },
      {
        'text': 'Pharmacies',
        'icon': Icons.local_pharmacy,
        'color': Colors.green,
        'query': 'pharmacies nearby',
      },
      {
        'text': 'Gas stations',
        'icon': Icons.local_gas_station,
        'color': Colors.blue,
        'query': 'gas stations nearby',
      },
      {
        'text': 'Supermarkets',
        'icon': Icons.local_grocery_store,
        'color': Colors.purple,
        'query': 'supermarkets nearby',
      },
      {
        'text': 'Banks & ATMs',
        'icon': Icons.account_balance,
        'color': Colors.indigo,
        'query': 'banks and ATMs nearby',
      },
      {
        'text': 'Hospitals',
        'icon': Icons.local_hospital,
        'color': Colors.red,
        'query': 'hospitals nearby',
      },
      {
        'text': 'Shopping',
        'icon': Icons.shopping_bag,
        'color': Colors.pink,
        'query': 'shopping centers nearby',
      },
    ];
  }

  // Method for quick search with hint
  Future<void> _performQuickSearch(String query) async {
    _searchController.text = query;
    await _performAISearch();
  }

  // ENHANCED - uses same LocationService as HomeMapScreen
  Future<void> _getCurrentLocationPrecise() async {
    setState(() {
      _isLoadingLocation = true;
      _currentLocationDisplay = "Getting location...";
    });

    try {
      // USE SAME SERVICE as HomeMapScreen
      final position = await LocationService.getCurrentLocation();

      if (position != null) {
        setState(() {
          _currentPosition = position;
          _currentLatLng = UniversalLatLng(position.latitude, position.longitude);
        });

        // Get location name for display using Nominatim (no Google API)
        await _getLocationNameForDisplayNominatim(position.latitude, position.longitude);

        print('✅ AI SEARCH: Got precise location: ${position.latitude}, ${position.longitude}');
      } else {
        await _getFallbackLocation();
      }

    } catch (e) {
      print('❌ AI SEARCH: Error getting location: $e');
      await _getFallbackLocation();
    } finally {
      setState(() {
        _isLoadingLocation = false;
      });
    }
  }

  // Fallback method if LocationService doesn't work
  Future<void> _getFallbackLocation() async {
    try {
      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) {
          _setFallbackLocation();
          return;
        }
      }

      if (permission == LocationPermission.deniedForever) {
        _setFallbackLocation();
        return;
      }

      Position position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
        timeLimit: const Duration(seconds: 15),
      );

      setState(() {
        _currentPosition = position;
        _currentLatLng = UniversalLatLng(position.latitude, position.longitude);
      });

      await _getLocationNameForDisplayNominatim(position.latitude, position.longitude);

    } catch (e) {
      print('❌ AI SEARCH: Fallback failed: $e');
      _setFallbackLocation();
    }
  }

  void _setFallbackLocation() {
    setState(() {
      _currentPosition = null;
      _currentLatLng = UniversalLatLng(48.2082, 16.3738); // Vienna as fallback
      _currentLocationDisplay = "Vienna, Austria (default)";
    });
  }

  // NEW METHOD: Get location name using Nominatim (no Google API)
  Future<void> _getLocationNameForDisplayNominatim(double lat, double lng) async {
    try {
      final url = 'https://nominatim.openstreetmap.org/reverse'
          '?format=json'
          '&lat=$lat'
          '&lon=$lng'
          '&zoom=18'
          '&addressdetails=1';

      final response = await http.get(
        Uri.parse(url),
        headers: {
          'User-Agent': 'LocadoApp/1.0', // Required by Nominatim
        },
      ).timeout(Duration(seconds: 10));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final address = data['address'] as Map<String, dynamic>?;

        if (address != null) {
          String? city = address['city'] ?? 
                        address['town'] ?? 
                        address['village'] ?? 
                        address['municipality'];
          String? country = address['country'];

          String displayName;
          if (city != null && country != null) {
            displayName = '$city, $country';
          } else {
            displayName = data['display_name'] ?? 'Location found';
            // Shorten if too long
            if (displayName.length > 50) {
              displayName = displayName.substring(0, 47) + '...';
            }
          }

          setState(() {
            _currentLocationDisplay = displayName;
          });
        } else {
          setState(() {
            _currentLocationDisplay = 'Location found (${lat.toStringAsFixed(4)}, ${lng.toStringAsFixed(4)})';
          });
        }
      }
    } catch (e) {
      print('❌ Error getting location name with Nominatim: $e');
      setState(() {
        _currentLocationDisplay = 'Location found (no internet)';
      });
    }
  }

  // HYBRID STRATEGY - combines AI + Nominatim search (no Google Places API)
  Future<List<AILocationResult>> _performHybridNearbySearch(String query) async {
    final isLocalSearch = query.toLowerCase().contains('nearby') ||
        query.toLowerCase().contains('around') ||
        query.toLowerCase().contains('close') ||
        query.toLowerCase().contains('near me') ||
        query.toLowerCase().contains('in the area');

    if (!isLocalSearch || _currentLatLng == null) {
      // Normal AI search for non-local searches
      final aiResponse = await _getAILocationSuggestionsWithCoordinates(query);
      return await _enrichWithRealCoordinates(aiResponse, query);
    }

    print('🔍 HYBRID: Starting nearby search for "$query"');
    print('🔍 HYBRID: User location = ${_currentLatLng!.latitude}, ${_currentLatLng!.longitude}');

    // STRATEGY 1: Nominatim search (primary)
    List<AILocationResult> nominatimResults = await _searchNominatimDirectly(query);

    // STRATEGY 2: AI search (secondary, for additional ideas)
    List<AILocationResult> aiResults = [];
    try {
      final aiResponse = await _getImprovedAINearbySearch(query);
      aiResults = await _enrichWithRealCoordinates(aiResponse, query);
    } catch (e) {
      print('⚠️ HYBRID: AI search failed, using Nominatim only: $e');
    }

    // Combine results
    Set<String> seenNames = {};
    List<AILocationResult> combinedResults = [];

    // Add Nominatim results (priority)
    for (final result in nominatimResults) {
      if (!seenNames.contains(result.name.toLowerCase())) {
        seenNames.add(result.name.toLowerCase());
        combinedResults.add(result);
      }
    }

    // Add AI results (if not duplicates)
    for (final result in aiResults) {
      if (!seenNames.contains(result.name.toLowerCase())) {
        seenNames.add(result.name.toLowerCase());
        combinedResults.add(result);
      }
    }

    // Sort by distance
    combinedResults.sort((a, b) {
      if (a.distanceFromUser == null && b.distanceFromUser == null) return 0;
      if (a.distanceFromUser == null) return 1;
      if (b.distanceFromUser == null) return -1;
      return a.distanceFromUser!.compareTo(b.distanceFromUser!);
    });

    print('✅ HYBRID: Final combined results: ${combinedResults.length}');
    return combinedResults.take(8).toList();
  }

	  // NEW METHOD: Search using Nominatim (OpenStreetMap) instead of Google Places - ENHANCED
	Future<List<AILocationResult>> _searchNominatimDirectly(String query) async {
	  List<AILocationResult> results = [];

	  if (_currentLatLng == null) return results;

	  try {
		print('🔍 NOMINATIM ENHANCED: Starting search for "$query"');

		// Clean query for Nominatim
		String cleanQuery = query.toLowerCase()
			.replaceAll('nearby', '')
			.replaceAll('around', '')
			.replaceAll('close', '')
			.replaceAll('near me', '')
			.replaceAll('in the area', '')
			.trim();

		// STRATEGY 1: Search with specific amenity tags (more precise)
		results.addAll(await _searchNominatimWithAmenity(cleanQuery));

		// STRATEGY 2: If not enough results, try general search
		if (results.length < 3) {
		  final generalResults = await _searchNominatimGeneral(cleanQuery);
		  
		  // Add non-duplicate results
		  Set<String> existingNames = results.map((r) => r.name.toLowerCase()).toSet();
		  for (final result in generalResults) {
			if (!existingNames.contains(result.name.toLowerCase()) && results.length < 8) {
			  results.add(result);
			  existingNames.add(result.name.toLowerCase());
			}
		  }
		}

		// STRATEGY 3: Sort by distance and filter to very close places only
		results = results.where((result) => 
		  result.distanceFromUser != null && result.distanceFromUser! <= 2000 // 2km max
		).toList();

		results.sort((a, b) => a.distanceFromUser!.compareTo(b.distanceFromUser!));

		print('✅ NOMINATIM ENHANCED: Final results: ${results.length}');
		return results.take(6).toList(); // Limit to 6 closest results

	  } catch (e) {
		print('❌ NOMINATIM ENHANCED: Error = $e');
		return results;
	  }
	}

	// NEW METHOD: Search with specific amenity tags
	Future<List<AILocationResult>> _searchNominatimWithAmenity(String query) async {
	  List<AILocationResult> results = [];

	  if (_currentLatLng == null) return results;

	  // Map queries to specific amenity types
	  List<String> amenityTypes = _getAmenityTypesForQuery(query);
	  
	  print('🏷️ AMENITY SEARCH: Using amenity types: $amenityTypes');

	  for (String amenityType in amenityTypes) {
		try {
		  // Search with amenity tag - more precise than general search
		  final url = 'https://overpass-api.de/api/interpreter';
		  
		  // Use Overpass API for precise amenity search
		  final overpassQuery = '''
	[out:json][timeout:10];
	(
	  node["amenity"="$amenityType"](around:1500,${_currentLatLng!.latitude},${_currentLatLng!.longitude});
	  way["amenity"="$amenityType"](around:1500,${_currentLatLng!.latitude},${_currentLatLng!.longitude});
	);
	out center meta;
	''';

		  final response = await http.post(
			Uri.parse(url),
			headers: {
			  'Content-Type': 'application/x-www-form-urlencoded',
			  'User-Agent': 'LocadoApp/1.0',
			},
			body: 'data=${Uri.encodeComponent(overpassQuery)}',
		  ).timeout(Duration(seconds: 8));

		  if (response.statusCode == 200) {
			final data = jsonDecode(response.body);
			final elements = data['elements'] as List;

			print('🏷️ AMENITY SEARCH: Found ${elements.length} $amenityType places');

			for (final element in elements.take(5)) { // Max 5 per type
			  final tags = element['tags'] as Map<String, dynamic>?;
			  if (tags == null) continue;

			  final name = tags['name'] ?? 'Unnamed $amenityType';
			  
			  // Get coordinates
			  double lat, lng;
			  if (element['lat'] != null && element['lon'] != null) {
				lat = element['lat'].toDouble();
				lng = element['lon'].toDouble();
			  } else if (element['center'] != null) {
				lat = element['center']['lat'].toDouble();
				lng = element['center']['lon'].toDouble();
			  } else {
				continue; // Skip if no coordinates
			  }

			  // Calculate distance
			  final distance = Geolocator.distanceBetween(
				_currentLatLng!.latitude,
				_currentLatLng!.longitude,
				lat,
				lng,
			  );

			  // Only include very close places (1.5km max for amenity search)
			  if (distance <= 1500) {
				print('🏷️ AMENITY: Adding $name = ${(distance / 1000).toStringAsFixed(2)}km');

				// Generate task items based on amenity type and real tags
				final taskItems = await _generateTaskItemsFromAmenityTags(name, amenityType, tags);

				results.add(AILocationResult(
				  name: name,
				  description: _getAmenityDescription(amenityType, tags),
				  coordinates: UniversalLatLng(lat, lng),
				  taskItems: taskItems,
				  category: amenityType,
				  distanceFromUser: distance,
				));
			  }
			}
		  }
		} catch (e) {
		  print('❌ AMENITY SEARCH: Error with $amenityType: $e');
		  continue; // Try next amenity type
		}
	  }

	  return results;
	}

	// NEW METHOD: Fallback general search
	Future<List<AILocationResult>> _searchNominatimGeneral(String cleanQuery) async {
	  List<AILocationResult> results = [];

	  try {
		// Smaller search radius for better local results
		final url = 'https://nominatim.openstreetmap.org/search'
			'?q=${Uri.encodeComponent(cleanQuery)}'
			'&format=json'
			'&addressdetails=1'
			'&limit=10'
			'&lat=${_currentLatLng!.latitude}'
			'&lon=${_currentLatLng!.longitude}'
			'&bounded=1'
			'&viewbox=${_currentLatLng!.longitude - 0.02},${_currentLatLng!.latitude + 0.02},${_currentLatLng!.longitude + 0.02},${_currentLatLng!.latitude - 0.02}'; // Smaller viewbox

		final response = await http.get(
		  Uri.parse(url),
		  headers: {'User-Agent': 'LocadoApp/1.0'},
		).timeout(Duration(seconds: 8));

		if (response.statusCode == 200) {
		  final List<dynamic> places = jsonDecode(response.body);
		  
		  for (final place in places.take(8)) { // Limit results
			final lat = double.parse(place['lat']);
			final lng = double.parse(place['lon']);
			final name = place['display_name'] ?? 'Unknown Place';
			final type = place['type'] ?? 'location';
			
			// Calculate distance
			final distance = Geolocator.distanceBetween(
			  _currentLatLng!.latitude,
			  _currentLatLng!.longitude,
			  lat,
			  lng,
			);

			// Only very close places for general search (1km max)
			if (distance <= 1000) {
			  final taskItems = await _generateTaskItemsFromType(name, type);

			  results.add(AILocationResult(
				name: _cleanDisplayName(name),
				description: 'Local $type nearby',
				coordinates: UniversalLatLng(lat, lng),
				taskItems: taskItems,
				category: type,
				distanceFromUser: distance,
			  ));
			}
		  }
		}
	  } catch (e) {
		print('❌ GENERAL SEARCH: Error = $e');
	  }

	  return results;
	}

	// NEW METHOD: Map queries to specific amenity types
	List<String> _getAmenityTypesForQuery(String query) {
	  final lowerQuery = query.toLowerCase();
	  
	  // Restaurant types
	  if (lowerQuery.contains('restaurant') || lowerQuery.contains('food') || 
		  lowerQuery.contains('eat') || lowerQuery.contains('dining')) {
		return ['restaurant', 'fast_food', 'cafe'];
	  }
	  
	  // Coffee and cafes
	  if (lowerQuery.contains('coffee') || lowerQuery.contains('cafe') || 
		  lowerQuery.contains('espresso') || lowerQuery.contains('cappuccino')) {
		return ['cafe', 'restaurant'];
	  }
	  
	  // Pharmacy
	  if (lowerQuery.contains('pharmacy') || lowerQuery.contains('medicine') || 
		  lowerQuery.contains('drug')) {
		return ['pharmacy'];
	  }
	  
	  // Gas stations
	  if (lowerQuery.contains('gas') || lowerQuery.contains('fuel') || 
		  lowerQuery.contains('petrol') || lowerQuery.contains('station')) {
		return ['fuel'];
	  }
	  
	  // Shopping
	  if (lowerQuery.contains('shop') || lowerQuery.contains('store') || 
		  lowerQuery.contains('supermarket') || lowerQuery.contains('market')) {
		return ['marketplace', 'supermarket'];
	  }
	  
	  // Banks and ATMs
	  if (lowerQuery.contains('bank') || lowerQuery.contains('atm')) {
		return ['bank', 'atm'];
	  }
	  
	  // Medical
	  if (lowerQuery.contains('hospital') || lowerQuery.contains('doctor') || 
		  lowerQuery.contains('medical') || lowerQuery.contains('clinic')) {
		return ['hospital', 'clinic', 'doctors'];
	  }
	  
	  // Default - try restaurant (most common search)
	  return ['restaurant', 'cafe', 'fast_food'];
	}

	// NEW METHOD: Get description based on amenity type
	String _getAmenityDescription(String amenityType, Map<String, dynamic> tags) {
	  final cuisine = tags['cuisine'] ?? '';
	  final openingHours = tags['opening_hours'] ?? '';
	  
	  switch (amenityType) {
		case 'restaurant':
		  if (cuisine.isNotEmpty) {
			return 'Restaurant serving $cuisine cuisine';
		  }
		  return 'Local restaurant with good food';
		case 'cafe':
		  return 'Coffee shop and cafe';
		case 'fast_food':
		  if (cuisine.isNotEmpty) {
			return 'Fast food - $cuisine';
		  }
		  return 'Quick dining option';
		case 'pharmacy':
		  return 'Pharmacy for medicines and health products';
		case 'fuel':
		  return 'Gas station for fuel and car services';
		case 'bank':
		  return 'Banking services and ATM';
		case 'hospital':
		  return 'Medical services and healthcare';
		default:
		  return 'Local $amenityType nearby';
	  }
	}

	// NEW METHOD: Generate task items from real amenity tags
	Future<List<String>> _generateTaskItemsFromAmenityTags(
		String name, 
		String amenityType, 
		Map<String, dynamic> tags
	) async {
	  List<String> tasks = [];
	  
	  // Extract useful information from tags
	  final openingHours = tags['opening_hours'] ?? '';
	  final phone = tags['phone'] ?? '';
	  final website = tags['website'] ?? '';
	  final cuisine = tags['cuisine'] ?? '';
	  final wheelchairAccess = tags['wheelchair'] ?? '';
	  
	  // Opening hours
	  if (openingHours.isNotEmpty && openingHours != '24/7' && !openingHours.contains('off')) {
		tasks.add('Hours: $openingHours');
	  } else if (amenityType == 'fuel') {
		tasks.add('Usually open 24/7');
	  } else {
		tasks.add('Check opening hours before visiting');
	  }
	  
	  // Phone
	  if (phone.isNotEmpty) {
		tasks.add('Call: $phone');
	  }
	  
	  // Type-specific tasks with real data
	  switch (amenityType) {
		case 'restaurant':
		  if (cuisine.isNotEmpty) {
			tasks.add('Specializes in $cuisine cuisine');
		  } else {
			tasks.add('Try their daily specials');
		  }
		  tasks.add('Perfect for dining with friends');
		  break;
		  
		case 'cafe':
		  tasks.add('Great for coffee and light meals');
		  tasks.add('Good spot for working with laptop');
		  break;
		  
		case 'pharmacy':
		  tasks.add('Prescription refills available');
		  tasks.add('Health products and consultation');
		  break;
		  
		case 'fuel':
		  tasks.add('Fill up tank and check tire pressure');
		  tasks.add('Car wash services may be available');
		  break;
		  
		case 'bank':
		  tasks.add('ATM available for cash withdrawal');
		  if (openingHours.isNotEmpty) {
			tasks.add('Banking services during business hours');
		  }
		  break;
	  }
	  
	  // Accessibility
	  if (wheelchairAccess == 'yes') {
		tasks.add('♿ Wheelchair accessible');
	  }
	  
	  // Website
	  if (website.isNotEmpty) {
		tasks.add('More info: ${_shortenUrl(website)}');
	  }
	  
	  return tasks.take(5).toList();
	}

	// Helper method to shorten URLs
	String _shortenUrl(String url) {
	  try {
		final uri = Uri.parse(url);
		return uri.host;
	  } catch (e) {
		return url.length > 30 ? '${url.substring(0, 27)}...' : url;
	  }
	}

  // Helper method to clean display names from Nominatim
  String _cleanDisplayName(String displayName) {
    // Extract just the main name before first comma
    final parts = displayName.split(',');
    if (parts.isNotEmpty) {
      String mainName = parts[0].trim();
      // Remove house numbers and extra info
      mainName = mainName.replaceAll(RegExp(r'^\d+\s*'), '');
      return mainName;
    }
    return displayName;
  }

  // Generate task items based on place type
  Future<List<String>> _generateTaskItemsFromType(String name, String type) async {
    List<String> tasks = [];

    switch (type.toLowerCase()) {
      case 'restaurant':
      case 'cafe':
        tasks.add('Check opening hours before visiting');
        tasks.add('Try their specialties and local dishes');
        tasks.add('Ask about daily specials');
        tasks.add('Perfect for dining with friends');
        break;
      case 'pharmacy':
        tasks.add('Open during regular business hours');
        tasks.add('Prescription refills and consultations');
        tasks.add('Health products and medical supplies');
        tasks.add('Bring ID and prescription if needed');
        break;
      case 'fuel':
      case 'gas_station':
        tasks.add('Usually open 24/7 for fuel');
        tasks.add('Self-service pumps available');
        tasks.add('Check tire pressure and car wash');
        tasks.add('Accepts cards and contactless payment');
        break;
      case 'supermarket':
      case 'marketplace':
        tasks.add('Fresh groceries and daily essentials');
        tasks.add('Compare prices for best deals');
        tasks.add('Check weekly specials and offers');
        tasks.add('Self-checkout available');
        break;
      case 'bank':
      case 'atm':
        tasks.add('ATM available for cash withdrawal');
        tasks.add('Banking services during business hours');
        tasks.add('Bring ID for banking services');
        break;
      case 'hospital':
      case 'clinic':
        tasks.add('Emergency services if available');
        tasks.add('Call ahead for appointments');
        tasks.add('Bring insurance card and ID');
        break;
      default:
        tasks.add('Visit and explore this location');
        tasks.add('Check opening hours before going');
        tasks.add('Ask staff for more information');
        break;
    }

    return tasks.take(4).toList();
  }

  // ENHANCED AI nearby search with stricter instructions
  Future<List<Map<String, dynamic>>> _getImprovedAINearbySearch(String query) async {
    final prompt = '''You are a local area expert. The user is at EXACT coordinates ${_currentLatLng!.latitude}, ${_currentLatLng!.longitude} in Vienna, Austria.

CRITICAL REQUIREMENTS:
- Suggest ONLY places within 1-2 kilometers walking distance
- Focus on small, local, neighborhood places
- NO tourist attractions or city center locations
- Think like a local resident looking for nearby convenience

Suggest 2-3 small local places with:
- name: Real local place name (not famous chains)
- description: Brief description (max 60 characters)
- category: restaurant/cafe/shop/pharmacy/etc
- taskItems: 3-4 simple tasks
- city: "${_currentLatLng!.latitude}, ${_currentLatLng!.longitude} (Wien, Austria)"

User query: "$query"

Return only a JSON array, no other text.''';

    print('🔍 AI IMPROVED: Sending focused nearby prompt...');

    final response = await http.post(
      Uri.parse('https://api.openai.com/v1/chat/completions'),
      headers: {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $_openAIApiKey',
      },
      body: jsonEncode({
        'model': 'gpt-3.5-turbo',
        'messages': [
          {'role': 'system', 'content': prompt},
          {'role': 'user', 'content': query}
        ],
        'max_tokens': 1500,
        'temperature': 0.2,
      }),
    );

    if (response.statusCode != 200) {
      throw Exception('OpenAI API Error: ${response.statusCode}');
    }

    final data = jsonDecode(response.body);
    final content = data['choices'][0]['message']['content'];

    print('🔍 AI IMPROVED: Response received');

    final List<dynamic> aiResults = jsonDecode(content);
    return aiResults.cast<Map<String, dynamic>>();
  }

  Future<void> _performAISearch() async {
    final query = _searchController.text.trim();
    if (query.isEmpty) {
      _showSnackBar('Please enter a search query', Colors.orange);
      return;
    }

    if (_openAIApiKey == 'YOUR_OPENAI_API_KEY_HERE') {
      _showSnackBar('Please add your OpenAI API key', Colors.red);
      return;
    }

    // CHECK NETWORK FIRST
    try {
      await http.get(Uri.parse('https://www.google.com')).timeout(Duration(seconds: 3));
    } catch (e) {
      _showSnackBar('No internet connection. Please check your network.', Colors.red);
      return;
    }

    // ENSURE WE HAVE USER LOCATION
    if (_currentLatLng == null) {
      _showSnackBar('Getting your location, please wait...', Colors.orange);
      await _getCurrentLocationPrecise();
      if (_currentLatLng == null) {
        _showSnackBar('Could not get your location. Using default location.', Colors.orange);
      }
    }

    setState(() {
      _isLoading = true;
      _searchResults.clear();
      _hasSearched = false;
    });

    try {
      // STEP 1: DETECT SEARCH INTENT
      print('🎯 SEARCH INTENT: Starting intent detection for "$query"');
      final searchIntent = await _detectSearchIntent(query);

      print('🎯 SEARCH INTENT: Result = isLocal: ${searchIntent.isLocalSearch}, targetLocation: ${searchIntent.targetLocation}');

      List<AILocationResult> results = [];

      if (searchIntent.isLocalSearch) {
        // NEARBY SEARCH - use hybrid approach with Nominatim
        print('📍 NEARBY SEARCH: Using current location');
        results = await _performHybridNearbySearch(searchIntent.cleanQuery);
        _showSnackBar('Found ${results.length} nearby locations', Colors.green);

      } else {
        // SPECIFIC LOCATION SEARCH
        print('🌍 LOCATION SEARCH: Searching in ${searchIntent.targetLocation}');
        results = await _performSpecificLocationSearch(
            searchIntent.cleanQuery,
            searchIntent.targetLocation!
        );
        _showSnackBar('Found ${results.length} locations in ${searchIntent.targetLocation}', Colors.green);
      }

      setState(() {
        _searchResults = results;
        _hasSearched = true;
        _isLoading = false;
      });

      if (_searchResults.isEmpty) {
        final locationMsg = searchIntent.isLocalSearch ? 'nearby' : 'in ${searchIntent.targetLocation}';
        _showSnackBar('No locations found $locationMsg. Try a broader search.', Colors.blue);
      }

    } catch (e, stackTrace) {
      print('❌ AI SEARCH: ERROR = $e');
      print('❌ AI SEARCH: STACK TRACE = $stackTrace');

      setState(() {
        _isLoading = false;
        _hasSearched = true;
      });
      _showSnackBar('Search error: ${e.toString()}', Colors.red);
    }
  }

  // Search for locations in a specific city/location
  Future<List<AILocationResult>> _performSpecificLocationSearch(String query, String targetLocation) async {
    print('🏙️ SPECIFIC LOCATION SEARCH: "$query" in "$targetLocation"');

    try {
      // STEP 1: Get coordinates of the target location using Nominatim
      final targetCoordinates = await _getTargetLocationCoordinatesNominatim(targetLocation);

      if (targetCoordinates == null) {
        throw Exception('Could not find coordinates for $targetLocation');
      }

      print('✅ TARGET LOCATION: $targetLocation = ${targetCoordinates.latitude}, ${targetCoordinates.longitude}');

      // STEP 2: Search using AI with target location context
      final aiResults = await _getAILocationSuggestionsForSpecificLocation(query, targetLocation, targetCoordinates);

      // STEP 3: Enrich with real coordinates using Nominatim
      final enrichedResults = await _enrichWithRealCoordinatesForLocation(aiResults, query, targetCoordinates);

      print('✅ SPECIFIC LOCATION SEARCH: Found ${enrichedResults.length} results in $targetLocation');
      return enrichedResults;

    } catch (e) {
      print('❌ SPECIFIC LOCATION SEARCH: Error = $e');
      throw Exception('Failed to search in $targetLocation: $e');
    }
  }

  // NEW METHOD: Get coordinates for target location using Nominatim
  Future<UniversalLatLng?> _getTargetLocationCoordinatesNominatim(String locationName) async {
    try {
      final query = Uri.encodeComponent(locationName);
      final url = 'https://nominatim.openstreetmap.org/search'
          '?q=$query'
          '&format=json'
          '&limit=1';

      final response = await http.get(
        Uri.parse(url),
        headers: {
          'User-Agent': 'LocadoApp/1.0',
        },
      );

      if (response.statusCode == 200) {
        final List<dynamic> results = jsonDecode(response.body);

        if (results.isNotEmpty) {
          final result = results[0];
          final lat = double.parse(result['lat']);
          final lng = double.parse(result['lon']);
          final displayName = result['display_name'];

          print('✅ NOMINATIM GEOCODING: $locationName → $displayName');
          return UniversalLatLng(lat, lng);
        }
      }
    } catch (e) {
      print('❌ NOMINATIM GEOCODING ERROR: $e');
    }

    return null;
  }

  // Get AI suggestions for specific location
  Future<List<Map<String, dynamic>>> _getAILocationSuggestionsForSpecificLocation(
      String query,
      String targetLocation,
      UniversalLatLng targetCoordinates
      ) async {

    final prompt = '''You are a travel expert specializing in $targetLocation.

The user wants to find: "$query" in $targetLocation
Target location coordinates: ${targetCoordinates.latitude}, ${targetCoordinates.longitude}

Provide 5-8 top recommendations with:
- name: Real place name (famous attractions, well-known establishments)
- description: Brief description (max 100 characters)
- category: Type (museum, restaurant, tourist_attraction, etc.)
- taskItems: Array of 3-5 specific things to do/see
- city: Use "$targetLocation" for all results

IMPORTANT:
- Focus on REAL, FAMOUS, and POPULAR places in $targetLocation
- Include major tourist attractions, renowned restaurants, famous landmarks
- Provide authentic, well-known locations that visitors actually seek
- Make descriptions appealing and informative

User query: "$query"
Target location: $targetLocation

Return only a JSON array, no other text.''';

    print('🤖 AI SPECIFIC LOCATION: Sending request for $targetLocation...');

    final response = await http.post(
      Uri.parse('https://api.openai.com/v1/chat/completions'),
      headers: {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $_openAIApiKey',
      },
      body: jsonEncode({
        'model': 'gpt-3.5-turbo',
        'messages': [
          {'role': 'system', 'content': prompt},
          {'role': 'user', 'content': query}
        ],
        'max_tokens': 3500,
        'temperature': 0.4,
      }),
    );

    if (response.statusCode != 200) {
      throw Exception('OpenAI API Error: ${response.statusCode}');
    }

    final data = jsonDecode(response.body);
    final content = data['choices'][0]['message']['content'];

    print('🤖 AI SPECIFIC LOCATION: Response received');

    try {
      final List<dynamic> aiResults = jsonDecode(content);
      print('✅ AI SPECIFIC LOCATION: Parsed ${aiResults.length} results');
      return aiResults.cast<Map<String, dynamic>>();
    } catch (e) {
      print('❌ AI SPECIFIC LOCATION: Parse error = $e');
      throw Exception('Failed to parse AI response: $e');
    }
  }

  // Enrich coordinates for specific location using Nominatim (no distance filtering)
  Future<List<AILocationResult>> _enrichWithRealCoordinatesForLocation(
      List<Map<String, dynamic>> aiResults,
      String originalQuery,
      UniversalLatLng targetLocationCoords
      ) async {

    List<AILocationResult> enrichedResults = [];

    print('🔍 ENRICH LOCATION: Processing ${aiResults.length} results for specific location...');

    for (int i = 0; i < aiResults.length; i++) {
      final aiResult = aiResults[i];
      print('🔍 ENRICH LOCATION: Processing ${aiResult['name']}');

      try {
        // Search for real coordinates using Nominatim
        final coordinates = await _getCoordinatesFromNominatim(
            aiResult['name'],
            aiResult['city'] ?? 'Unknown Location'
        );

        if (coordinates != null) {
          print('✅ ENRICH LOCATION: Found coordinates for ${aiResult['name']}');

          // Calculate distance from user (not target location)
          double? distanceFromUser;
          if (_currentLatLng != null) {
            distanceFromUser = Geolocator.distanceBetween(
              _currentLatLng!.latitude,
			  _currentLatLng!.longitude,
             coordinates.latitude,
             coordinates.longitude,
           );
         }

         enrichedResults.add(
           AILocationResult(
             name: aiResult['name'],
             description: aiResult['description'] ?? 'Popular location',
             coordinates: coordinates,
             taskItems: List<String>.from(aiResult['taskItems'] ?? []),
             category: aiResult['category'] ?? 'location',
             distanceFromUser: distanceFromUser,
           ),
         );

         print('✅ ENRICH LOCATION: Added ${aiResult['name']} to results');
       } else {
         print('❌ ENRICH LOCATION: No coordinates found for ${aiResult['name']}');
       }
     } catch (e) {
       print('❌ ENRICH LOCATION: Error processing ${aiResult['name']}: $e');
       continue;
     }
   }

   print('✅ ENRICH LOCATION: Final results count: ${enrichedResults.length}');
   return enrichedResults;
 }

 // Get AI location suggestions with coordinates
 Future<List<Map<String, dynamic>>> _getAILocationSuggestionsWithCoordinates(String query) async {
   String locationContext;
   String searchArea = "Vienna, Austria"; // Fallback

   print('🔍 AI DEBUG: _currentLatLng = $_currentLatLng');
   print('🔍 AI DEBUG: _currentPosition = $_currentPosition');
   print('🔍 AI DEBUG: _currentLocationDisplay = "$_currentLocationDisplay"');

   if (_currentLatLng != null) {
     print('✅ AI DEBUG: Using PRECISE coordinates: ${_currentLatLng!.latitude}, ${_currentLatLng!.longitude}');

     locationContext = '''The user is currently located at EXACT coordinates: ${_currentLatLng!.latitude}, ${_currentLatLng!.longitude}.
This corresponds approximately to: $_currentLocationDisplay.

CRITICAL INSTRUCTIONS:
- When user asks for "nearby", "around me", "close by", use ONLY locations within 2km radius of coordinates ${_currentLatLng!.latitude}, ${_currentLatLng!.longitude}
- For nearby searches, suggest locations that are actually walking distance (under 2km)
- Use the EXACT coordinates ${_currentLatLng!.latitude}, ${_currentLatLng!.longitude} as the center point for all distance calculations
- Do not suggest locations more than 2 kilometers away from these coordinates''';

     searchArea = '${_currentLatLng!.latitude}, ${_currentLatLng!.longitude} (${_currentLocationDisplay})';
   } else {
     print('❌ AI DEBUG: NO PRECISE COORDINATES! Using fallback Vienna');
     locationContext = '''The user's location is not available. Use Vienna, Austria (48.2082, 16.3738) as default.''';
   }

   final prompt = '''You are a travel and location expert. $locationContext

When given a location query, respond with a JSON array of location suggestions. Each location should have:
- name: The location name
- description: A brief description (max 100 characters)
- category: Type of location (tourist_attraction, restaurant, museum, etc.)
- taskItems: Array of 3-5 specific things to do/see at that location
- city: The city name for coordinate lookup (use "$searchArea" for nearby searches)

IMPORTANT RULES FOR NEARBY SEARCHES:
1. If the user asks for locations "nearby", "around me", "in the area", "close by", use ONLY the user's current coordinates area
2. For nearby searches, suggest only locations within 1-2km radius (walking distance)
3. If user specifies a different city/country, use that instead
4. Always provide realistic, existing locations that are actually close to the user
5. NEVER suggest locations that are 5+ kilometers away for "nearby" searches

User query: "$query"

Format your response as a valid JSON array only, no additional text.''';

   print('🔍 AI DEBUG: Sending prompt to OpenAI...');

   final response = await http.post(
     Uri.parse('https://api.openai.com/v1/chat/completions'),
     headers: {
       'Content-Type': 'application/json',
       'Authorization': 'Bearer $_openAIApiKey',
     },
     body: jsonEncode({
       'model': 'gpt-3.5-turbo',
       'messages': [
         {'role': 'system', 'content': prompt},
         {'role': 'user', 'content': query}
       ],
       'max_tokens': 3500,
       'temperature': 0.3,
     }),
   );

   if (response.statusCode != 200) {
     print('❌ AI DEBUG: OpenAI API Error: ${response.statusCode}');
     throw Exception('OpenAI API Error: ${response.statusCode}');
   }

   final data = jsonDecode(response.body);
   final content = data['choices'][0]['message']['content'];

   print('🔍 AI DEBUG: Raw AI response received');

   try {
     final List<dynamic> aiResults = jsonDecode(content);
     print('✅ AI DEBUG: Successfully parsed ${aiResults.length} results from AI');
     return aiResults.cast<Map<String, dynamic>>();
   } catch (e) {
     print('❌ AI DEBUG: Error parsing AI response: $e');
     throw Exception('Failed to parse AI response: $e');
   }
 }

 Future<List<AILocationResult>> _enrichWithRealCoordinates(List<Map<String, dynamic>> aiResults, String originalQuery) async {
   List<AILocationResult> enrichedResults = [];

   // Check if user asked for local results
   final isLocalSearch = originalQuery.toLowerCase().contains('nearby') ||
       originalQuery.toLowerCase().contains('around') ||
       originalQuery.toLowerCase().contains('close') ||
       originalQuery.toLowerCase().contains('near me') ||
       originalQuery.toLowerCase().contains('in the area');

   print('🔍 ENRICH DEBUG: isLocalSearch = $isLocalSearch');
   print('🔍 ENRICH DEBUG: User coordinates = $_currentLatLng');
   print('🔍 ENRICH DEBUG: Processing ${aiResults.length} AI results...');

   for (int i = 0; i < aiResults.length; i++) {
     final aiResult = aiResults[i];
     print('🔍 ENRICH DEBUG: Processing result $i: ${aiResult['name']}');

     try {
       // Search for real coordinates using Nominatim
       final coordinates = await _getCoordinatesFromNominatim(
           aiResult['name'],
           aiResult['city'] ?? _currentLocationDisplay
       );

       if (coordinates != null) {
         print('✅ ENRICH DEBUG: Found coordinates for ${aiResult['name']}: ${coordinates.latitude}, ${coordinates.longitude}');

         double? distanceFromUser;
         bool shouldInclude = true;

         // Calculate distance if we have GPS location
         if (_currentLatLng != null) {
           distanceFromUser = Geolocator.distanceBetween(
             _currentLatLng!.latitude,
             _currentLatLng!.longitude,
             coordinates.latitude,
             coordinates.longitude,
           );

           print('🔍 ENRICH DEBUG: Distance calculated: ${aiResult['name']} = ${(distanceFromUser! / 1000).toStringAsFixed(2)}km away');

           // Filter by distance if it's a local search
           if (isLocalSearch) {
             shouldInclude = distanceFromUser <= 3000; // 3km in meters
             print('🔍 ENRICH DEBUG: Local search filter: ${aiResult['name']} ${shouldInclude ? "INCLUDED" : "EXCLUDED"} (${(distanceFromUser / 1000).toStringAsFixed(2)}km)');
           }
         }

         if (shouldInclude) {
           print('✅ ENRICH DEBUG: Adding ${aiResult['name']} to results');

           enrichedResults.add(
             AILocationResult(
               name: aiResult['name'],
               description: aiResult['description'],
               coordinates: coordinates,
               taskItems: List<String>.from(aiResult['taskItems'] ?? []),
               category: aiResult['category'] ?? 'location',
               distanceFromUser: distanceFromUser,
             ),
           );
         } else {
           print('❌ ENRICH DEBUG: Excluding ${aiResult['name']} - too far away');
         }
       } else {
         print('❌ ENRICH DEBUG: No coordinates found for ${aiResult['name']}');
       }
     } catch (e) {
       print('❌ ENRICH DEBUG: Error enriching location ${aiResult['name']}: $e');
       continue;
     }
   }

   // Sort by distance if it's a local search and we have user position
   if (isLocalSearch && _currentLatLng != null) {
     enrichedResults.sort((a, b) {
       if (a.distanceFromUser == null && b.distanceFromUser == null) return 0;
       if (a.distanceFromUser == null) return 1;
       if (b.distanceFromUser == null) return -1;
       return a.distanceFromUser!.compareTo(b.distanceFromUser!);
     });
     print('✅ ENRICH DEBUG: Results sorted by distance, closest first');
   }

   print('✅ ENRICH DEBUG: Final results count: ${enrichedResults.length}');
   return enrichedResults;
 }

 // NEW METHOD: Get coordinates using Nominatim instead of Google
 Future<UniversalLatLng?> _getCoordinatesFromNominatim(String locationName, String city) async {
   try {
     final query = Uri.encodeComponent('$locationName $city');
     final url = 'https://nominatim.openstreetmap.org/search'
         '?q=$query'
         '&format=json'
         '&limit=1';

     final response = await http.get(
       Uri.parse(url),
       headers: {
         'User-Agent': 'LocadoApp/1.0',
       },
     );

     if (response.statusCode == 200) {
       final List<dynamic> results = jsonDecode(response.body);

       if (results.isNotEmpty) {
         final result = results[0];
         final lat = double.parse(result['lat']);
         final lng = double.parse(result['lon']);
         return UniversalLatLng(lat, lng);
       }
     }
   } catch (e) {
     print('❌ Error getting coordinates from Nominatim: $e');
   }

   return null;
 }

 Future<void> _createSelectedTasks() async {
   final selectedResults = _searchResults.where((result) => result.isSelected).toList();

   if (selectedResults.isEmpty) {
     _showSnackBar('Please select at least one location', Colors.orange);
     return;
   }

   setState(() {
     _isLoading = true;
   });

   try {
     int createdCount = 0;

     for (final result in selectedResults) {
       // Create TaskLocation object - convert UniversalLatLng to Google Maps format for compatibility
       final taskLocation = TaskLocation(
         latitude: result.coordinates.latitude,
         longitude: result.coordinates.longitude,
         title: result.name,
         taskItems: result.taskItems,
         colorHex: _getRandomColor(),
         scheduledDateTime: null,
         linkedCalendarEventId: null,
       );

       // Save to database
       await DatabaseHelper.instance.addTaskLocation(taskLocation);
       createdCount++;
     }

     setState(() {
       _isLoading = false;
     });

     _showSnackBar('Created $createdCount task(s) successfully!', Colors.green);

     if (widget.onTasksCreated != null) {
       widget.onTasksCreated!();
     } else {
       Navigator.pop(context, true);
     }

   } catch (e) {
     setState(() {
       _isLoading = false;
     });
     _showSnackBar('Error creating tasks: ${e.toString()}', Colors.red);
   }
 }

 String _getRandomColor() {
   final colors = [
     '#FF5722', '#FF9800', '#FFC107', '#FFEB3B', '#CDDC39',
     '#8BC34A', '#4CAF50', '#009688', '#00BCD4', '#03A9F4',
     '#2196F3', '#3F51B5', '#673AB7', '#9C27B0', '#E91E63'
   ];
   return colors[Random().nextInt(colors.length)];
 }

 void _showSnackBar(String message, Color color) {
   ScaffoldMessenger.of(context).showSnackBar(
     SnackBar(
       content: Text(message),
       backgroundColor: color,
       duration: const Duration(seconds: 3),
     ),
   );
 }

 String _formatDistance(double? distanceInMeters) {
   if (distanceInMeters == null) return '';

   if (distanceInMeters < 1000) {
     return '${distanceInMeters.round()}m';
   } else {
     return '${(distanceInMeters / 1000).toStringAsFixed(1)}km';
   }
 }

 // Detect search intent
 Future<SearchIntent> _detectSearchIntent(String originalQuery) async {
   print('🔍 INTENT DETECTION: Analyzing query: "$originalQuery"');

   final lowerQuery = originalQuery.toLowerCase().trim();

   // Check for explicit nearby indicators
   final nearbyIndicators = [
     'nearby', 'around', 'close', 'near me', 'in the area', 'walking distance',
     'u blizini', 'blizu', 'okolina', 'u krugu', // Serbian
     'in der nähe', 'nahe', 'umgebung', 'in der umgebung', // German
     'près de', 'proche', 'aux alentours', 'dans le coin', // French
     'cerca', 'vicino', 'nei dintorni', 'in zona', // Italian
     'cerca de', 'próximo', 'en la zona', 'alrededor', // Spanish
   ];

   final hasNearbyIndicator = nearbyIndicators.any((indicator) =>
       lowerQuery.contains(indicator.toLowerCase()));

   if (hasNearbyIndicator) {
     print('✅ INTENT: Nearby search detected (explicit indicator)');
     return SearchIntent(
       isLocalSearch: true,
       targetLocation: null,
       cleanQuery: originalQuery,
       originalQuery: originalQuery,
     );
   }

   // Use AI to detect location intent
   try {
     final aiDetection = await _detectLocationWithAI(originalQuery);

     if (aiDetection['hasSpecificLocation'] == true) {
       final targetLocation = aiDetection['location'] as String;
       final cleanQuery = aiDetection['cleanQuery'] as String;

       print('✅ INTENT: Specific location detected: "$targetLocation"');

       return SearchIntent(
         isLocalSearch: false,
         targetLocation: targetLocation,
         cleanQuery: cleanQuery,
         originalQuery: originalQuery,
       );
     }
   } catch (e) {
     print('❌ INTENT: AI detection failed: $e');
   }

   // Fallback - assume nearby search
   print('✅ INTENT: Defaulting to nearby search');
   return SearchIntent(
     isLocalSearch: true,
     targetLocation: null,
     cleanQuery: originalQuery,
     originalQuery: originalQuery,
   );
 }

 Future<Map<String, dynamic>> _detectLocationWithAI(String query) async {
   final prompt = '''You are a search intent analyzer. Analyze the user's search query and determine:

1. Does the user want to search for places in a SPECIFIC LOCATION (city, country, etc.)?
2. If yes, what is that location?
3. What is the clean search query without the location?

Examples:
- "museums in Paris" → location: "Paris", clean: "museums"
- "best restaurants in Tokyo" → location: "Tokyo", clean: "best restaurants"  
- "coffee shops" → no specific location, clean: "coffee shops"
- "nearby pharmacies" → no specific location, clean: "nearby pharmacies"

User query: "$query"

Respond with ONLY this JSON format:
{
 "hasSpecificLocation": true/false,
 "location": "City, Country" or null,
 "cleanQuery": "search terms without location"
}''';

   final response = await http.post(
     Uri.parse('https://api.openai.com/v1/chat/completions'),
     headers: {
       'Content-Type': 'application/json',
       'Authorization': 'Bearer $_openAIApiKey',
     },
     body: jsonEncode({
       'model': 'gpt-3.5-turbo',
       'messages': [
         {'role': 'system', 'content': prompt},
       ],
       'max_tokens': 200,
       'temperature': 0.1,
     }),
   );

   if (response.statusCode == 200) {
     final data = jsonDecode(response.body);
     final content = data['choices'][0]['message']['content'];

     final result = jsonDecode(content);
     return result;
   }

   throw Exception('AI intent detection failed');
 }

 @override
 Widget build(BuildContext context) {
   return Scaffold(
     backgroundColor: Colors.grey.shade50,
     appBar: AppBar(
       elevation: 0,
       backgroundColor: Colors.teal,
       foregroundColor: Colors.white,
       title: Column(
         crossAxisAlignment: CrossAxisAlignment.start,
         children: [
           Row(
             children: [
               const Icon(Icons.smart_toy, size: 24),
               const SizedBox(width: 8),
               Expanded(
                 child: Text(
                   'AI Location Search (${_currentMapProvider.name})',
                   style: const TextStyle(
                     fontSize: 18,
                     fontWeight: FontWeight.bold,
                   ),
                   overflow: TextOverflow.ellipsis,
                 ),
               ),
             ],
           ),
           Row(
             children: [
               Icon(
                 Icons.location_on,
                 size: 12,
                 color: Colors.white.withOpacity(0.8),
               ),
               const SizedBox(width: 4),
               Expanded(
                 child: Text(
                   _isLoadingLocation ? 'Getting location...' : _currentLocationDisplay,
                   style: TextStyle(
                     fontSize: 12,
                     color: Colors.white.withOpacity(0.8),
                   ),
                   overflow: TextOverflow.ellipsis,
                 ),
               ),
               Icon(
                 Icons.translate,
                 size: 16,
                 color: Colors.white.withOpacity(0.7),
               ),
             ],
           ),
         ],
       ),
       actions: [
         IconButton(
           icon: _isLoadingLocation
               ? const SizedBox(
             width: 20,
             height: 20,
             child: CircularProgressIndicator(
               strokeWidth: 2,
               color: Colors.white,
             ),
           )
               : const Icon(Icons.my_location),
           onPressed: _isLoadingLocation ? null : _getCurrentLocationPrecise,
           tooltip: 'Refresh location',
         ),
       ],
     ),
     body: Stack(
       children: [
         // Main content
         Column(
           children: [
             // Search Section
             Container(
               padding: const EdgeInsets.all(16),
               decoration: BoxDecoration(
                 color: Colors.white,
                 boxShadow: [
                   BoxShadow(
                     color: Colors.grey.shade200,
                     blurRadius: 4,
                     offset: const Offset(0, 2),
                   ),
                 ],
               ),
               child: Column(
                 crossAxisAlignment: CrossAxisAlignment.start,
                 children: [
                   // Search Input
                   TextField(
                     controller: _searchController,
                     decoration: InputDecoration(
                       hintText: 'Search in any language! (No Google API needed)',
                       hintStyle: TextStyle(color: Colors.grey.shade500, fontSize: 14),
                       prefixIcon: const Icon(Icons.smart_toy, color: Colors.teal, size: 20),
                       suffixIcon: Row(
                         mainAxisSize: MainAxisSize.min,
                         children: [
                           Icon(Icons.translate, color: Colors.grey.shade400, size: 16),
                           const SizedBox(width: 4),
                           if (_searchController.text.isNotEmpty)
                             IconButton(
                               icon: const Icon(Icons.clear, size: 20),
                               onPressed: () {
                                 _searchController.clear();
                                 setState(() {});
                               },
                             ),
                         ],
                       ),
                       border: OutlineInputBorder(
                         borderRadius: BorderRadius.circular(8),
                         borderSide: BorderSide(color: Colors.grey.shade300),
                       ),
                       focusedBorder: OutlineInputBorder(
                         borderRadius: BorderRadius.circular(8),
                         borderSide: const BorderSide(color: Colors.teal, width: 2),
                       ),
                       filled: true,
                       fillColor: Colors.grey.shade50,
                       contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                       isDense: true,
                     ),
                     onSubmitted: (_) => _performAISearch(),
                     onChanged: (value) => setState(() {}),
                   ),

                   const SizedBox(height: 12),

                   // Search Button
                   Row(
                     children: [
                       Expanded(
                         child: SizedBox(
                           height: 40,
                           child: ElevatedButton.icon(
                             onPressed: _isLoading ? null : _performAISearch,
                             icon: _isLoading
                                 ? const SizedBox(
                               width: 16,
                               height: 16,
                               child: CircularProgressIndicator(
                                 strokeWidth: 2,
                                 color: Colors.white,
                               ),
                             )
                                 : const Icon(Icons.search, size: 18),
                             label: Text(
                               _isLoading ? 'Searching...' : 'Search with AI (OpenStreetMap)',
                               style: const TextStyle(
                                 fontSize: 14,
                                 fontWeight: FontWeight.bold,
                               ),
                             ),
                             style: ElevatedButton.styleFrom(
                               backgroundColor: Colors.teal,
                               foregroundColor: Colors.white,
                               shape: RoundedRectangleBorder(
                                 borderRadius: BorderRadius.circular(8),
                               ),
                               elevation: 2,
                             ),
                           ),
                         ),
                       ),
                     ],
                   ),
                 ],
               ),
             ),

             // Results Section
             Expanded(
               child: _buildResultsSection(),
             ),
           ],
         ),

         // Floating Create Tasks Button
         if (_hasSearched && _searchResults.isNotEmpty && _searchResults.any((r) => r.isSelected))
           Positioned(
             bottom: 16,
             left: 16,
             right: 16,
             child: Container(
               decoration: BoxDecoration(
                 borderRadius: BorderRadius.circular(12),
                 boxShadow: [
                   BoxShadow(
                     color: Colors.black.withOpacity(0.3),
                     blurRadius: 8,
                     offset: const Offset(0, 4),
                   ),
                 ],
               ),
               child: SizedBox(
                 width: double.infinity,
                 height: 56,
                 child: ElevatedButton.icon(
                   onPressed: _isLoading ? null : _createSelectedTasks,
                   icon: _isLoading
                       ? const SizedBox(
                     width: 20,
                     height: 20,
                     child: CircularProgressIndicator(
                       strokeWidth: 2,
                       color: Colors.white,
                     ),
                   )
                       : const Icon(Icons.check_circle, size: 24),
                   label: Text(
                     _isLoading
                         ? 'Creating tasks...'
                         : 'Create ${_searchResults.where((r) => r.isSelected).length} task(s)',
                     style: const TextStyle(
                       fontSize: 16,
                       fontWeight: FontWeight.bold,
                       color: Colors.white,
                     ),
                   ),
                   style: ElevatedButton.styleFrom(
                     backgroundColor: Colors.green,
                     foregroundColor: Colors.white,
                     shape: RoundedRectangleBorder(
                       borderRadius: BorderRadius.circular(12),
                     ),
                     elevation: 0,
                   ),
                 ),
               ),
             ),
           ),
       ],
     ),
   );
 }

 Widget _buildResultsSection() {
   if (_isLoading) {
     return const Center(
       child: Column(
         mainAxisAlignment: MainAxisAlignment.center,
         children: [
           CircularProgressIndicator(color: Colors.teal),
           SizedBox(height: 16),
           Text(
             'AI is searching for locations...',
             style: TextStyle(
               fontSize: 16,
               color: Colors.grey,
             ),
           ),
         ],
       ),
     );
   }

   // Show hints when no search has been performed
   if (!_hasSearched) {
     return Column(
       children: [
         Expanded(
           child: SingleChildScrollView(
             padding: const EdgeInsets.all(16),
             child: Column(
               crossAxisAlignment: CrossAxisAlignment.start,
               children: [
                 // Quick Search header
                 Row(
                   children: [
                     Icon(
                       Icons.lightbulb_outline,
                       color: Colors.amber.shade600,
                       size: 20,
                     ),
                     const SizedBox(width: 8),
                     Text(
                       'Quick Search',
                       style: TextStyle(
                         fontSize: 16,
                         fontWeight: FontWeight.bold,
                         color: Colors.grey.shade800,
                       ),
                     ),
                   ],
                 ),
                 const SizedBox(height: 8),
                 Text(
                   'Tap any category to search nearby locations:',
                   style: TextStyle(
                     fontSize: 13,
                     color: Colors.grey.shade600,
                   ),
                 ),
                 const SizedBox(height: 16),

                 // Grid with hint buttons
                 GridView.builder(
                   shrinkWrap: true,
                   physics: const NeverScrollableScrollPhysics(),
                   gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                     crossAxisCount: 2,
                     childAspectRatio: 3.0,
                     crossAxisSpacing: 10,
                     mainAxisSpacing: 10,
                   ),
                   itemCount: _getSearchHints().length,
                   itemBuilder: (context, index) {
                     final hint = _getSearchHints()[index];
                     return _buildCompactHintButton(hint);
                   },
                 ),

                 const SizedBox(height: 20),

                 // OpenStreetMap info
                 Container(
                   padding: const EdgeInsets.all(12),
                   decoration: BoxDecoration(
                     color: Colors.green.shade50,
                     borderRadius: BorderRadius.circular(8),
                     border: Border.all(color: Colors.green.shade200, width: 1),
                   ),
                   child: Row(
                     children: [
                       Icon(Icons.layers, color: Colors.green.shade600, size: 18),
                       const SizedBox(width: 10),
                       Expanded(
                         child: Column(
                           crossAxisAlignment: CrossAxisAlignment.start,
                           children: [
                             Text(
                               'OpenStreetMap Integration',
                               style: TextStyle(
                                 fontWeight: FontWeight.bold,
                                 color: Colors.green.shade700,
                                 fontSize: 12,
                               ),
                             ),
                             const SizedBox(height: 2),
                             Text(
                               'No Google API required - using free OpenStreetMap data',
                               style: TextStyle(
                                 fontSize: 10,
                                 color: Colors.green.shade600,
                                 height: 1.2,
                               ),
                             ),
                           ],
                         ),
                       ),
                     ],
                   ),
                 ),

                 const SizedBox(height: 16),

                 // Multilingual info
                 Container(
                   padding: const EdgeInsets.all(12),
                   decoration: BoxDecoration(
                     color: Colors.blue.shade50,
                     borderRadius: BorderRadius.circular(8),
                     border: Border.all(color: Colors.blue.shade200, width: 1),
                   ),
                   child: Row(
                     children: [
                       Icon(Icons.translate, color: Colors.blue.shade600, size: 18),
                       const SizedBox(width: 10),
                       Expanded(
                         child: Column(
                           crossAxisAlignment: CrossAxisAlignment.start,
                           children: [
                             Text(
                               'Multilingual Search',
                               style: TextStyle(
                                 fontWeight: FontWeight.bold,
                                 color: Colors.blue.shade700,
                                 fontSize: 12,
                               ),
                             ),
                             const SizedBox(height: 2),
                             Text(
                               'Search in any language: English, Deutsch, Français, Español, etc.',
                               style: TextStyle(
                                 fontSize: 10,
                                 color: Colors.blue.shade600,
                                 height: 1.2,
                               ),
                             ),
                           ],
                         ),
                       ),
                     ],
                   ),
                 ),
               ],
             ),
           ),
         ),
       ],
     );
   }

   // Show empty results
   if (_searchResults.isEmpty) {
     return Center(
       child: Column(
         mainAxisAlignment: MainAxisAlignment.center,
         children: [
           Icon(
             Icons.search_off,
             size: 80,
             color: Colors.grey.shade300,
           ),
           const SizedBox(height: 16),
           Text(
             'No locations found',
             style: TextStyle(
               fontSize: 18,
               color: Colors.grey.shade600,
               fontWeight: FontWeight.w500,
             ),
           ),
           const SizedBox(height: 8),
           Text(
             'Try a different search query',
             style: TextStyle(
               fontSize: 14,
               color: Colors.grey.shade500,
             ),
           ),
           const SizedBox(height: 20),

           ElevatedButton.icon(
             onPressed: () {
               setState(() {
                 _hasSearched = false;
                 _searchResults.clear();
                 _searchController.clear();
               });
             },
             icon: const Icon(Icons.refresh, size: 18),
             label: const Text('Try Quick Search'),
             style: ElevatedButton.styleFrom(
               backgroundColor: Colors.teal,
               foregroundColor: Colors.white,
               padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
               shape: RoundedRectangleBorder(
                 borderRadius: BorderRadius.circular(8),
               ),
             ),
           ),
         ],
       ),
     );
   }

   // Show results
   return Column(
     children: [
       // Header with selection info + back button
       Container(
         padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
         decoration: BoxDecoration(
           color: Colors.white,
           border: Border(
             bottom: BorderSide(color: Colors.grey.shade200),
           ),
         ),
         child: Row(
           children: [
             // Back to hints button
             InkWell(
               onTap: () {
                 setState(() {
                   _hasSearched = false;
                   _searchResults.clear();
                   _searchController.clear();
                 });
               },
               borderRadius: BorderRadius.circular(6),
               child: Container(
                 padding: const EdgeInsets.all(6),
                 child: Icon(
                   Icons.arrow_back,
                   color: Colors.grey.shade600,
                   size: 20,
                 ),
               ),
             ),
             const SizedBox(width: 12),

             Icon(Icons.location_on, color: Colors.teal.shade600, size: 20),
             const SizedBox(width: 8),
             Expanded(
               child: Text(
                 'Found ${_searchResults.length} locations',
                 style: TextStyle(
                   fontSize: 16,
                   fontWeight: FontWeight.bold,
                   color: Colors.teal.shade700,
                 ),
               ),
             ),
             Text(
               '${_searchResults.where((r) => r.isSelected).length} selected',
               style: TextStyle(
                 fontSize: 14,
                 color: Colors.grey.shade600,
               ),
             ),
           ],
         ),
       ),

       // Results List
       Expanded(
         child: ListView.separated(
           padding: const EdgeInsets.fromLTRB(16, 8, 16, 100),
           itemCount: _searchResults.length,
           separatorBuilder: (context, index) => const SizedBox(height: 8),
           itemBuilder: (context, index) {
             final result = _searchResults[index];
             return _buildResultCard(result, index);
           },
         ),
       ),
     ],
   );
 }

 Widget _buildCompactHintButton(Map<String, dynamic> hint) {
   return Material(
     color: Colors.transparent,
     child: InkWell(
       borderRadius: BorderRadius.circular(10),
       onTap: () => _performQuickSearch(hint['query']),
       child: Container(
         decoration: BoxDecoration(
           color: Colors.white,
           borderRadius: BorderRadius.circular(10),
           boxShadow: [
             BoxShadow(
               color: Colors.grey.shade200,
               blurRadius: 3,
               offset: const Offset(0, 1),
             ),
           ],
           border: Border.all(color: Colors.grey.shade200),
         ),
         child: Padding(
           padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
           child: Row(
             children: [
               Container(
                 padding: const EdgeInsets.all(6),
                 decoration: BoxDecoration(
                   color: hint['color'].withOpacity(0.1),
                   borderRadius: BorderRadius.circular(6),
                 ),
                 child: Icon(
                   hint['icon'],
                   color: hint['color'],
                   size: 16,
                 ),
               ),
               const SizedBox(width: 8),
               Expanded(
                 child: Text(
                   hint['text'],
                   style: TextStyle(
                     fontSize: 11,
                     fontWeight: FontWeight.w600,
                     color: Colors.grey.shade800,
                   ),
                   overflow: TextOverflow.ellipsis,
                 ),
               ),
               Icon(
                 Icons.arrow_forward_ios,
                 color: Colors.grey.shade400,
                 size: 10,
               ),
             ],
           ),
         ),
       ),
     ),
   );
 }

 Widget _buildResultCard(AILocationResult result, int index) {
   return Container(
     decoration: BoxDecoration(
       color: Colors.white,
       borderRadius: BorderRadius.circular(12),
       boxShadow: [
         BoxShadow(
           color: Colors.grey.shade200,
           blurRadius: 4,
           offset: const Offset(0, 2),
         ),
       ],
       border: result.isSelected
           ? Border.all(color: Colors.green, width: 2)
           : Border.all(color: Colors.grey.shade200),
     ),
     child: Material(
       color: Colors.transparent,
       child: InkWell(
         borderRadius: BorderRadius.circular(12),
         onTap: () {
           setState(() {
             result.isSelected = !result.isSelected;
           });
         },
         child: Padding(
           padding: const EdgeInsets.all(12),
           child: Column(
             crossAxisAlignment: CrossAxisAlignment.start,
             children: [
               // Header with checkbox
               Row(
                 children: [
                   Container(
                     width: 20,
                     height: 20,
                     decoration: BoxDecoration(
                       color: result.isSelected ? Colors.green : Colors.transparent,
                       border: Border.all(
                         color: result.isSelected ? Colors.green : Colors.grey.shade400,
                         width: 2,
                       ),
                       borderRadius: BorderRadius.circular(4),
                     ),
                     child: result.isSelected
                         ? const Icon(Icons.check, color: Colors.white, size: 14)
                         : null,
                   ),
                   const SizedBox(width: 10),
                   Expanded(
                     child: Column(
                       crossAxisAlignment: CrossAxisAlignment.start,
                       children: [
                         Row(
                           children: [
                             Expanded(
                               child: Text(
                                 result.name,
                                 style: const TextStyle(
                                   fontSize: 16,
                                   fontWeight: FontWeight.bold,
                                   color: Colors.black87,
                                 ),
                               ),
                             ),
                             if (result.distanceFromUser != null) ...[
                               const SizedBox(width: 8),
                               Container(
                                 padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                 decoration: BoxDecoration(
                                   color: Colors.blue.shade50,
                                   borderRadius: BorderRadius.circular(8),
                                   border: Border.all(color: Colors.blue.shade200),
                                 ),
                                 child: Text(
                                   _formatDistance(result.distanceFromUser),
                                   style: TextStyle(
                                     fontSize: 10,
                                     fontWeight: FontWeight.bold,
                                     color: Colors.blue.shade700,
                                   ),
                                 ),
                               ),
                             ],
                           ],
                         ),
                         const SizedBox(height: 2),
                         Text(
                           result.description,
                           style: TextStyle(
                             fontSize: 12,
                             color: Colors.grey.shade600,
                           ),
                           maxLines: 2,
                           overflow: TextOverflow.ellipsis,
                         ),
                       ],
                     ),
                   ),
                   Container(
                     padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                     decoration: BoxDecoration(
                       color: Colors.teal.shade50,
                       borderRadius: BorderRadius.circular(8),
                     ),
                     child: Text(
                       result.category.replaceAll('_', ' ').toUpperCase(),
                       style: TextStyle(
                         fontSize: 8,
                         fontWeight: FontWeight.bold,
                         color: Colors.teal.shade700,
                       ),
                     ),
                   ),
                 ],
               ),

               // Task items
               if (result.taskItems.isNotEmpty) ...[
                 const SizedBox(height: 10),
                 Text(
                   'Things to do:',
                   style: TextStyle(
                     fontSize: 12,
                     fontWeight: FontWeight.bold,
                     color: Colors.grey.shade700,
                   ),
                 ),
                 const SizedBox(height: 6),
                 ...result.taskItems.take(3).map((item) => Padding(
                   padding: const EdgeInsets.only(bottom: 3),
                   child: Row(
                     crossAxisAlignment: CrossAxisAlignment.start,
                     children: [
                       Container(
                         width: 4,
                         height: 4,
                         margin: const EdgeInsets.only(top: 6),
                         decoration: BoxDecoration(
                           color: Colors.teal.shade400,
                           shape: BoxShape.circle,
                         ),
                       ),
                       const SizedBox(width: 8),
                       Expanded(
                         child: Text(
                           item,
                           style: TextStyle(
                             fontSize: 11,
                             color: Colors.grey.shade700,
                             height: 1.2,
                           ),
                           maxLines: 1,
                           overflow: TextOverflow.ellipsis,
                         ),
                       ),
                     ],
                   ),
                 )),
                 if (result.taskItems.length > 3)
                   Padding(
                     padding: const EdgeInsets.only(top: 4),
                     child: Text(
                       '+${result.taskItems.length - 3} more items',
                       style: TextStyle(
                         fontSize: 10,
                         color: Colors.teal.shade600,
                         fontStyle: FontStyle.italic,
                       ),
                     ),
                   ),
               ],
             ],
           ),
         ),
       ),
     ),
   );
 }
}