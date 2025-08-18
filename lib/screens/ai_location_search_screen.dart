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
import 'dart:math' as math;
import 'package:webview_flutter/webview_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

// Server health check result
class ServerHealth {
  final String url;
  final bool isAvailable;
  final int responseTimeMs;
  final DateTime checkedAt;

  ServerHealth({
	required this.url,
	required this.isAvailable,
	required this.responseTimeMs,
	required this.checkedAt,
  });
}

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
  final String? imageUrl;
  bool isSelected;

  AILocationResult({
    required this.name,
    required this.description,
    required this.coordinates,
    required this.taskItems,
    required this.category,
    this.distanceFromUser,
    this.imageUrl,
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
  bool _isEnhancing = false;

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
		{
		  'text': 'Nightlife & Bars',
		  'icon': Icons.local_bar,
		  'color': Colors.purple,
		  'query': 'bars nearby',
		},
		{
		  'text': 'Museums & Culture',
		  'icon': Icons.museum,
		  'color': Colors.indigo,
		  'query': 'museums culture nearby',
		},
		{
		  'text': 'Parks & Recreation',
		  'icon': Icons.park,
		  'color': Colors.green,
		  'query': 'parks recreation nearby',
		},
		{
		  'text': 'Entertainment',
		  'icon': Icons.movie,
		  'color': Colors.red,
		  'query': 'entertainment cinema nearby',
		},
		{
		  'text': 'Tourist Attractions',
		  'icon': Icons.place,
		  'color': Colors.orange,
		  'query': 'tourist attractions nearby',
		},
		{
		  'text': 'Kids Attractions',
		  'icon': Icons.child_friendly,
		  'color': Colors.pink,
		  'query': 'kids attractions children nearby',
		},
    ];
  }

	  // Method for quick search with hint
	Future<void> _performQuickSearch(String query) async {
		  _searchController.text = query;
		  await _performOptimizedQuickSearchProgressive(query); // Changed from _performOptimizedQuickSearch
		}

		/// UPDATED METHOD: Replace existing _performAISearch call  
		Future<void> _performAISearch() async {
		  final query = _searchController.text.trim();
		  if (query.isEmpty) {
			_showSnackBar('Please enter a search query', Colors.orange);
			return;
		  }

		  await _performOptimizedQuickSearchProgressive(query); // Changed from _performOptimizedQuickSearch
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
    return combinedResults.take(20).toList();
  }
  
	// NEW METHOD: Expanded nearby search with translation
	Future<List<AILocationResult>> _performExpandedNearbySearch(String query) async {
	  if (_currentLatLng == null) return [];

	  print('🔍 EXPANDED SEARCH: Starting for "$query"');
	  
	  // Use the new expanded search directly with Nominatim
	  return await _searchNominatimDirectly(query);
	}
  
	// NEW METHOD: Get country code from current location for language detection
	Future<String> _getCurrentCountryCode() async {
	  if (_currentLatLng == null) return 'AT'; // Default to Austria
	  
	  try {
		final url = 'https://nominatim.openstreetmap.org/reverse'
			'?format=json'
			'&lat=${_currentLatLng!.latitude}'
			'&lon=${_currentLatLng!.longitude}'
			'&zoom=18'
			'&addressdetails=1';

		final response = await http.get(
		  Uri.parse(url),
		  headers: {'User-Agent': 'LocadoApp/1.0'},
		).timeout(Duration(seconds: 5));

		if (response.statusCode == 200) {
		  final data = jsonDecode(response.body);
		  final address = data['address'] as Map<String, dynamic>?;
		  final countryCode = address?['country_code']?.toString().toUpperCase();
		  
		  print('🌍 COUNTRY DETECTION: Detected country code: $countryCode');
		  return countryCode ?? 'AT';
		}
	  } catch (e) {
		print('❌ COUNTRY DETECTION: Error = $e');
	  }
	  
	  return 'AT'; // Fallback to Austria
	}

	// NEW METHOD: Basic translation mapping for major countries
	Map<String, Map<String, List<String>>> get _basicTranslations => {
	  'AT': { // Austria - German
		'pharmacy': ['apotheke', 'pharmazie'],
		'restaurant': ['restaurant', 'gasthof', 'gasthaus', 'wirtshaus'],
		'coffee': ['kaffeehaus', 'cafe', 'konditorei'],
		'gas': ['tankstelle'],
		'supermarket': ['supermarkt', 'lebensmittel', 'spar', 'billa', 'hofer'],
		'bank': ['bank', 'sparkasse', 'raiffeisen'],
		'hospital': ['krankenhaus', 'spital'],
	  },
	  'DE': { // Germany - German
		'pharmacy': ['apotheke', 'pharmazie'],
		'restaurant': ['restaurant', 'gaststätte', 'gasthof'],
		'coffee': ['kaffeehaus', 'cafe', 'konditorei'],
		'gas': ['tankstelle'],
		'supermarket': ['supermarkt', 'edeka', 'rewe', 'aldi', 'lidl'],
		'bank': ['bank', 'sparkasse'],
		'hospital': ['krankenhaus'],
	  },
	  'IT': { // Italy - Italian
		'pharmacy': ['farmacia'],
		'restaurant': ['ristorante', 'trattoria', 'osteria', 'pizzeria'],
		'coffee': ['bar', 'caffe', 'pasticceria'],
		'gas': ['distributore', 'benzina'],
		'supermarket': ['supermercato', 'alimentari'],
		'bank': ['banca'],
		'hospital': ['ospedale'],
	  },
	  'FR': { // France - French
		'pharmacy': ['pharmacie'],
		'restaurant': ['restaurant', 'brasserie', 'bistrot'],
		'coffee': ['cafe', 'salon de the'],
		'gas': ['station service', 'essence'],
		'supermarket': ['supermarche', 'epicerie'],
		'bank': ['banque'],
		'hospital': ['hopital'],
	  },
	  'ES': { // Spain - Spanish
		'pharmacy': ['farmacia'],
		'restaurant': ['restaurante', 'taberna', 'mesón'],
		'coffee': ['cafeteria', 'bar'],
		'gas': ['gasolinera'],
		'supermarket': ['supermercado'],
		'bank': ['banco'],
		'hospital': ['hospital'],
	  },
	  'HR': { // Croatia - Croatian
		'pharmacy': ['ljekarna', 'apoteka'],
		'restaurant': ['restoran', 'konoba', 'gostiona'],
		'coffee': ['kavana', 'caffe bar'],
		'gas': ['benzinska postaja'],
		'supermarket': ['supermarket', 'trgovina'],
		'bank': ['banka'],
		'hospital': ['bolnica'],
	  },
	};

	// NEW METHOD: Generate multi-language search terms
	Future<List<String>> _getMultiLanguageSearchTerms(String query) async {
	  List<String> searchTerms = [query]; // Always include English
	  
	  try {
		final countryCode = await _getCurrentCountryCode();
		final translations = _basicTranslations[countryCode];
		
		if (translations != null) {
		  // Find matching category and add local terms
		  for (final category in translations.keys) {
			if (query.toLowerCase().contains(category)) {
			  searchTerms.addAll(translations[category]!);
			  print('🌐 TRANSLATION: "$query" + local terms for $countryCode: ${translations[category]}');
			  break;
			}
		  }
		}
		
		// Remove duplicates and empty strings
		searchTerms = searchTerms.where((term) => term.trim().isNotEmpty).toSet().toList();
		
		print('✅ MULTI-LANGUAGE: Final search terms: $searchTerms');
		return searchTerms;
		
	  } catch (e) {
		print('❌ MULTI-LANGUAGE: Error = $e, using English only');
		return [query];
	  }
	}
	
	// NEW METHOD: Get local language terms for target location
		Future<List<String>> _getLocalTermsForTargetLocation(String query, String targetLocation) async {
		  try {
			final prompt = '''You are a local language expert.

		The user is searching for: "$query"
		In this location: $targetLocation

		Provide search terms that locals would actually use in $targetLocation for this type of business/service.

		For "$query" in $targetLocation, what terms do locals use?

		Respond with ONLY a comma-separated list of local terms, no other text.''';

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
				'max_tokens': 100,
				'temperature': 0.2,
			  }),
			);

			if (response.statusCode == 200) {
			  final data = jsonDecode(response.body);
			  final localTerms = data['choices'][0]['message']['content'].trim();
			  
			  // SIGURNO PARSIRANJE
			  final termsList = <String>[];
			  for (final term in localTerms.split(',')) {
				final cleanTerm = term.trim();
				if (cleanTerm.isNotEmpty) {
				  termsList.add(cleanTerm);
				}
			  }
			  
			  print('🌐 LOCAL TERMS for $targetLocation: "$query" → $termsList');
			  return termsList;
			}
		  } catch (e) {
			print('❌ LOCAL TERMS: Error = $e');
		  }
		  
		  return <String>[];
		}
	
	// NEW METHOD: AI-powered query translation and expansion
	Future<List<String>> _getExpandedSearchTerms(String originalQuery) async {
	  List<String> expandedTerms = [originalQuery]; // Always include original
	  
	  try {
		final countryCode = await _getCurrentCountryCode();
		
		// STEP 1: Optimize query for OSM search - UNIVERSAL
		if (!_isEnglishQuery(originalQuery)) {
		  final optimizedQuery = await _optimizeQueryForOSM(originalQuery);  // ← NOVO
		  if (optimizedQuery != originalQuery) {
			expandedTerms.add(optimizedQuery);
			print('🔧 QUERY OPTIMIZATION: "$originalQuery" → "$optimizedQuery"');
		  }
		}
		
		// STEP 2: For each term, get local language versions
		for (String term in List.from(expandedTerms)) {
		  final localTerms = await _getLocalTermsForQuery(term, countryCode);
		  expandedTerms.addAll(localTerms);
		}
		
		// Remove duplicates
		expandedTerms = expandedTerms.toSet().toList();
		
		print('✅ EXPANDED SEARCH: Final terms: $expandedTerms');
		return expandedTerms;
		
	  } catch (e) {
		print('❌ EXPANDED SEARCH: Error = $e');
		return [originalQuery];
	  }
	}

	// NEW METHOD: Check if query is in English
	bool _isEnglishQuery(String query) {
	  final lowerQuery = query.toLowerCase();
	  
	  // Check for English keywords
	  final englishKeywords = [
		'find', 'search', 'nearby', 'near me', 'around', 'close',
		'restaurant', 'pharmacy', 'coffee', 'gas', 'bank', 'hospital',
		'hairdresser', 'barber', 'salon', 'shop', 'store'
	  ];
	  
	  return englishKeywords.any((keyword) => lowerQuery.contains(keyword));
	}

	// NEW METHOD: AI-powered OSM query optimization - UNIVERSAL
	Future<String> _optimizeQueryForOSM(String query) async {
	  try {
		final prompt = '''You are an OpenStreetMap search optimization expert.

	Your task: Take any search query in ANY language and expand it with the BEST possible search terms that will help find relevant locations in OpenStreetMap/Nominatim.

	Rules:
	1. Understand what type of business/service the user wants (regardless of language)
	2. Generate search terms that businesses actually use in their names
	3. Include synonyms and alternative terms for that business type
	4. Add both English and local language variations when helpful
	5. Think globally - what would this business be called in different countries?

	User query: "$query"

	Respond with ONLY the optimized search terms, no other text.''';

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
			'max_tokens': 100,
			'temperature': 0.2,
		  }),
		);

		if (response.statusCode == 200) {
		  final data = jsonDecode(response.body);
		  final optimizedQuery = data['choices'][0]['message']['content'].trim();
		  
		  print('🔧 OSM OPTIMIZATION: "$query" → "$optimizedQuery"');
		  return optimizedQuery;
		}
	  } catch (e) {
		print('❌ OSM OPTIMIZATION: Error = $e');
	  }
	  
	  return query; // Fallback to original
	}

	
	// NEW METHOD: Get local terms for a query
	Future<List<String>> _getLocalTermsForQuery(String query, String countryCode) async {
	  List<String> localTerms = [];
	  
	  final translations = _basicTranslations[countryCode];
	  if (translations == null) return localTerms;
	  
	  final lowerQuery = query.toLowerCase();
	  
	  // Enhanced mapping with more specific terms
	  final enhancedMapping = {
		'hairdresser': ['friseur', 'friseursalon', 'coiffeur'],
		'barber': ['barbier', 'herrenfriseur'],
		'salon': ['salon', 'schönheitssalon'],
		'bakery': ['bäckerei', 'backhaus'],
		'butcher': ['fleischerei', 'metzgerei', 'fleischhauer'],
		'dentist': ['zahnarzt', 'dental'],
		'optician': ['optiker', 'brille'],
		'jewelry': ['juwelier', 'schmuck'],
		'bookstore': ['buchhandlung', 'bücher'],
		'electronics': ['elektronik', 'elektro'],
		'clothing': ['kleidung', 'mode', 'bekleidung'],
		'shoes': ['schuhe', 'schuhgeschäft'],
	  };
	  
	  // Check for specific terms
	  for (final english in enhancedMapping.keys) {
		if (lowerQuery.contains(english)) {
		  localTerms.addAll(enhancedMapping[english]!);
		  break;
		}
	  }
	  
	  // Check existing translation mapping
	  for (final category in translations.keys) {
		if (lowerQuery.contains(category)) {
		  localTerms.addAll(translations[category]!);
		  break;
		}
	  }
	  
	  return localTerms;
	}

	// UPDATED METHOD: Search using Nominatim with multi-language support
		Future<List<AILocationResult>> _searchNominatimDirectly(String query) async {
		  List<AILocationResult> results = [];

		  if (_currentLatLng == null) return results;

		  try {
			print('🔍 NOMINATIM ENHANCED: Starting multi-language search for "$query"');

			// Clean query for Nominatim
			String cleanQuery = query.toLowerCase()
				.replaceAll('nearby', '')
				.replaceAll('around', '')
				.replaceAll('close', '')
				.replaceAll('near me', '')
				.replaceAll('in the area', '')
				.trim();

			// STEP 1: Get multi-language search terms
			final searchTerms = await _getExpandedSearchTerms(cleanQuery);
			
			// STEP 2: Search with each term using DIRECT Nominatim search
			for (String searchTerm in searchTerms) {
			  print('🌐 DIRECT SEARCH: "$searchTerm" (${searchTerms.indexOf(searchTerm) + 1}/${searchTerms.length})');
			  
			  // Use direct Nominatim search without OSM tag filtering
			  final directResults = await _searchNominatimGeneral(searchTerm);
			  results.addAll(directResults);
			  
			  // If we have enough results from this term, continue to next
			  if (results.length >= 20) break;
			}

			// STEP 3: If still not enough results, try general search with all terms
			/*if (results.length < 3) {
			  for (String searchTerm in searchTerms) {
				final generalResults = await _searchNominatimGeneral(searchTerm);
				
				// Add non-duplicate results
				Set<String> existingNames = results.map((r) => r.name.toLowerCase()).toSet();
				for (final result in generalResults) {
				  if (!existingNames.contains(result.name.toLowerCase()) && results.length < 20) {
					results.add(result);
					existingNames.add(result.name.toLowerCase());
				  }
				}
				
				if (results.length >= 20) break;
			  }
			}*/

			// STEP 4: Remove duplicates by coordinates (in case same place has multiple names)
			results = _removeDuplicatesByCoordinates(results);

			// STEP 5: Sort by distance and filter to close places only
			results = results.where((result) => 
			  result.distanceFromUser != null && result.distanceFromUser! <= 2000 // 2km max
			).toList();

			results.sort((a, b) => a.distanceFromUser!.compareTo(b.distanceFromUser!));

			print('✅ NOMINATIM ENHANCED: Final results: ${results.length}');
			return results.take(20).toList(); // Limit to 20 closest results

		  } catch (e) {
			print('❌ NOMINATIM ENHANCED: Error = $e');
			return results;
		  }
		}

		// NEW HELPER METHOD: Remove duplicate locations by coordinates
		List<AILocationResult> _removeDuplicatesByCoordinates(List<AILocationResult> results) {
		  Map<String, AILocationResult> uniqueLocations = {};
		  
		  for (final result in results) {
			// Create key based on coordinates (rounded to avoid floating point issues)
			final key = '${result.coordinates.latitude.toStringAsFixed(6)}_${result.coordinates.longitude.toStringAsFixed(6)}';
			
			// Keep the result with more task items or better name
			if (!uniqueLocations.containsKey(key) || 
				result.taskItems.length > uniqueLocations[key]!.taskItems.length) {
			  uniqueLocations[key] = result;
			}
		  }
		  
		  return uniqueLocations.values.toList();
		}

	// NEW METHOD: Search with specific amenity tags
	Future<List<AILocationResult>> _searchNominatimWithAmenity(String query) async {
	  List<AILocationResult> results = [];

	  if (_currentLatLng == null) return results;

	  // Map queries to specific amenity types
	  List<String> amenityTypes = await _getAmenityTypesForQuery(query);
	  
	  print('🏷️ AMENITY SEARCH: Using amenity types: $amenityTypes');

	  for (String amenityType in amenityTypes) {
		try {
		  // Search with amenity tag - more precise than general search
		  final url = 'https://overpass-api.de/api/interpreter';
		  
		  // Use Overpass API for comprehensive tag search - ENHANCED
			final overpassQuery = '''
			[out:json][timeout:10];
			(
			  node["amenity"="$amenityType"](around:1500,${_currentLatLng!.latitude},${_currentLatLng!.longitude});
			  way["amenity"="$amenityType"](around:1500,${_currentLatLng!.latitude},${_currentLatLng!.longitude});
			  node["shop"="$amenityType"](around:1500,${_currentLatLng!.latitude},${_currentLatLng!.longitude});
			  way["shop"="$amenityType"](around:1500,${_currentLatLng!.latitude},${_currentLatLng!.longitude});
			  node["healthcare"="$amenityType"](around:1500,${_currentLatLng!.latitude},${_currentLatLng!.longitude});
			  way["healthcare"="$amenityType"](around:1500,${_currentLatLng!.latitude},${_currentLatLng!.longitude});
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

			for (final element in elements.take(20)) { // Max 20 per type
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
				  imageUrl: null,
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
		  
		  for (final place in places.take(20)) { // Limit results
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
				imageUrl: null,
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
	// UPDATED METHOD: Dynamic amenity mapping using multi-language support
	Future<List<String>> _getAmenityTypesForQuery(String query) async {
	  final lowerQuery = query.toLowerCase();
	  
	  print('🏷️ DYNAMIC TAG MAPPING: Analyzing "$query"');
	  
	  try {
		// Get current country and its translations
		final countryCode = await _getCurrentCountryCode();
		final translations = _basicTranslations[countryCode] ?? {};
		
		// Check each category in translations
		for (final category in translations.keys) {
		  final localTerms = translations[category]!;
		  
		  // Check if query contains English category name
		  if (lowerQuery.contains(category)) {
			final amenityTags = _getCategoryAmenityTags(category);
			print('🏷️ MATCH: "$query" → category: $category → tags: $amenityTags');
			return amenityTags;
		  }
		  
		        if (lowerQuery.contains('${category}s') || lowerQuery.contains('${category}ies')) {
					final amenityTags = _getCategoryAmenityTags(category);
					print('🏷️ PLURAL MATCH: "$query" → category: $category → tags: $amenityTags');
					return amenityTags;
				  }
		  
		  // Check if query contains any local language terms
		  for (final localTerm in localTerms) {
			if (lowerQuery.contains(localTerm.toLowerCase())) {
			  final amenityTags = _getCategoryAmenityTags(category);
			  print('🏷️ LOCAL MATCH: "$query" contains "$localTerm" → category: $category → tags: $amenityTags');
			  return amenityTags;
			}
		  }
		}
		
		// Fallback: try to detect category from common English terms
		final fallbackCategory = _detectCategoryFallback(lowerQuery);
		final amenityTags = _getCategoryAmenityTags(fallbackCategory);
		print('🏷️ FALLBACK: "$query" → category: $fallbackCategory → tags: $amenityTags');
		return amenityTags;
		
	  } catch (e) {
		print('❌ DYNAMIC TAG MAPPING: Error = $e');
		// Ultimate fallback
		return ['restaurant', 'cafe', 'fast_food'];
	  }
	}

	// NEW HELPER METHOD: Map category to OSM amenity tags
	List<String> _getCategoryAmenityTags(String category) {
	  switch (category) {
		case 'pharmacy':
		  return ['pharmacy', 'chemist', 'healthcare'];
		case 'restaurant':
		  return ['restaurant', 'fast_food', 'cafe', 'bar', 'pub'];
		case 'coffee':
		  return ['cafe', 'restaurant'];
		case 'gas':
		  return ['fuel'];
		case 'supermarket':
		  return ['marketplace', 'supermarket'];
		case 'bank':
		  return ['bank', 'atm'];
		case 'hospital':
		  return ['hospital', 'clinic', 'doctors'];
		case 'nightlife': 
			  return ['bar', 'pub', 'nightclub', 'biergarten', 'casino', 'stripclub', 'social_club'];
		default:
		  return ['restaurant', 'cafe', 'fast_food']; // Default fallback
	  }
	}

	// NEW HELPER METHOD: Fallback category detection for unknown terms
	String _detectCategoryFallback(String lowerQuery) {
	  if (lowerQuery.contains('restaurant') || lowerQuery.contains('restaurants') ||
		  lowerQuery.contains('food') || lowerQuery.contains('eat') || lowerQuery.contains('dining')) {
		return 'restaurant';
	  }
		if (lowerQuery.contains('coffee') || lowerQuery.contains('espresso') || 
			lowerQuery.contains('cafe') || lowerQuery.contains('kaffee')) {
		  return 'coffee';
		}
	  if (lowerQuery.contains('pharmacy') || lowerQuery.contains('pharmacies') || 
		  lowerQuery.contains('medicine') || lowerQuery.contains('drug')) {
		return 'pharmacy';
	  }
	  if (lowerQuery.contains('fuel') || lowerQuery.contains('petrol') || lowerQuery.contains('station')) {
		return 'gas';
	  }
	  if (lowerQuery.contains('shop') || lowerQuery.contains('store') || lowerQuery.contains('market')) {
		return 'supermarket';
	  }
	  if (lowerQuery.contains('bank') || lowerQuery.contains('atm')) {
		return 'bank';
	  }
	  if (lowerQuery.contains('hospital') || lowerQuery.contains('doctor') || lowerQuery.contains('medical')) {
		return 'hospital';
	  }
	  
	  if (lowerQuery.contains('nightlife') || lowerQuery.contains('bar') || lowerQuery.contains('bars') ||
		  lowerQuery.contains('pub') || lowerQuery.contains('pubs') || lowerQuery.contains('club') ||
		  lowerQuery.contains('clubs') || lowerQuery.contains('nightclub') || lowerQuery.contains('disco') ||
		  lowerQuery.contains('cocktail') || lowerQuery.contains('lounge') || lowerQuery.contains('casino') ||
		  lowerQuery.contains('night') || lowerQuery.contains('drink') || lowerQuery.contains('drinks')) {
		return 'nightlife';
	  }
	  
	  return 'restaurant'; // Ultimate fallback
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
	
    /// UPDATED METHOD: Extract image URL with Google Places API fallback
	/// UPDATED METHOD: Enhanced image extraction with Street View integration
	Future<String?> _extractImageFromOSMTags(Map<String, dynamic> tags, String locationName, double lat, double lng) async {
	  try {
		// Strategy 1: Direct image tag (EXISTING - UNCHANGED)
		if (tags['image'] != null && tags['image'].toString().isNotEmpty) {
		  final imageUrl = tags['image'].toString();
		  if (_isValidImageUrl(imageUrl)) {
			print('🖼️ OSM IMAGE: Found direct image: $imageUrl');
			return imageUrl;
		  }
		}

		// Strategy 2: Wikimedia Commons tag (EXISTING - UNCHANGED)
		if (tags['wikimedia_commons'] != null && tags['wikimedia_commons'].toString().isNotEmpty) {
		  final wikimediaUrl = _convertWikimediaToImageUrl(tags['wikimedia_commons'].toString());
		  if (wikimediaUrl != null) {
			print('🖼️ OSM IMAGE: Found Wikimedia image: $wikimediaUrl');
			return wikimediaUrl;
		  }
		}

		// Strategy 3: Wikipedia API integration (EXISTING - UNCHANGED)
		if (tags['wikipedia'] != null && tags['wikipedia'].toString().isNotEmpty) {
		  print('🖼️ WIKIPEDIA: Found Wikipedia reference: ${tags['wikipedia']}');
		  final wikipediaImageUrl = await _getImageFromWikipediaAPI(tags['wikipedia'].toString());
		  if (wikipediaImageUrl != null) {
			print('🖼️ WIKIPEDIA: Found Wikipedia image: $wikipediaImageUrl');
			return wikipediaImageUrl;
		  }
		}

		// Strategy 4: Google Street View Static API (NEW)
		print('🏠 STREET VIEW: Trying Street View for "$locationName"');
		final streetViewImageUrl = await _getStreetViewImage(locationName, lat, lng);
		if (streetViewImageUrl != null) {
		  print('🖼️ STREET VIEW: Found Street View image: $streetViewImageUrl');
		  return streetViewImageUrl;
		}

		// Strategy 5: Google Places API fallback (EXISTING - UNCHANGED)
		print('🔍 GOOGLE PLACES: No OSM/Wikipedia/Street View images, trying Google Places for "$locationName"');
		final googlePlacesImageUrl = await _getImageFromGooglePlaces(locationName, lat, lng);
		if (googlePlacesImageUrl != null) {
		  print('🖼️ GOOGLE PLACES: Found image: $googlePlacesImageUrl');
		  return googlePlacesImageUrl;
		}

		// Strategy 6: Website tag (EXISTING - UNCHANGED)
		if (tags['website'] != null && tags['website'].toString().isNotEmpty) {
		  print('🖼️ OSM IMAGE: Found website: ${tags['website']} (potential image source)');
		}

		print('🖼️ NO IMAGE: No images found for "$locationName"');
		return null;
	  } catch (e) {
		print('❌ OSM IMAGE: Error extracting image from tags: $e');
		return null;
	  }
	}

	/// NEW METHOD: Get image from Google Places API
	Future<String?> _getImageFromGooglePlaces(String locationName, double lat, double lng) async {
	  try {
		final googlePlacesApiKey = dotenv.env['GOOGLE_PLACES_API_KEY'] ?? '';
		
		if (googlePlacesApiKey.isEmpty || googlePlacesApiKey == 'your_api_key_here') {
		  print('❌ GOOGLE PLACES: API key not configured');
		  return null;
		}

		// Step 1: Find Place using Nearby Search
		final placeId = await _findGooglePlace(locationName, lat, lng, googlePlacesApiKey);
		if (placeId == null) {
		  print('🔍 GOOGLE PLACES: Place not found for "$locationName"');
		  return null;
		}

		// Step 2: Get Place Photos
		final photoReference = await _getGooglePlacePhoto(placeId, googlePlacesApiKey);
		if (photoReference == null) {
		  print('🔍 GOOGLE PLACES: No photos found for "$locationName"');
		  return null;
		}

		// Step 3: Generate Photo URL
		final photoUrl = _buildGooglePlacePhotoUrl(photoReference, googlePlacesApiKey);
		print('🖼️ GOOGLE PLACES: Generated photo URL for "$locationName"');
		return photoUrl;

	  } catch (e) {
		print('❌ GOOGLE PLACES: Error getting image: $e');
		return null;
	  }
	}
	
	/// NEW METHOD: Get image using Google Street View Static API
	Future<String?> _getStreetViewImage(String locationName, double lat, double lng) async {
	  try {
		// Check if Google API key is configured
		final googleApiKey = dotenv.env['GOOGLE_API_KEY'] ?? dotenv.env['GOOGLE_PLACES_API_KEY'] ?? '';
		
		if (googleApiKey.isEmpty || googleApiKey == 'your_api_key_here') {
		  print('🏠 STREET VIEW: API key not configured');
		  return null;
		}

		// Build Street View Static API URL
		final streetViewUrl = _buildStreetViewStaticUrl(lat, lng, googleApiKey);
		
		// Test if Street View image is available by making a HEAD request
		final isAvailable = await _testStreetViewAvailability(streetViewUrl);
		
		if (isAvailable) {
		  print('🏠 STREET VIEW: Image available for "$locationName" at $lat,$lng');
		  return streetViewUrl;
		} else {
		  print('🏠 STREET VIEW: No image available for "$locationName" at $lat,$lng');
		  return null;
		}
		
	  } catch (e) {
		print('❌ STREET VIEW: Error getting image: $e');
		return null;
	  }
	}

	/// NEW METHOD: Build Google Street View Static API URL
	String _buildStreetViewStaticUrl(double lat, double lng, String apiKey) {
	  // Optimized parameters for best results
	  return 'https://maps.googleapis.com/maps/api/streetview'
		  '?size=400x300'              // Good balance of quality and cost
		  '&location=$lat,$lng'        // Use exact coordinates
		  '&heading=235'               // Slightly angled view
		  '&pitch=10'                  // Slight downward angle
		  '&fov=75'                    // Field of view
		  '&key=$apiKey';
	}

	/// NEW METHOD: Test if Street View image is available
	Future<bool> _testStreetViewAvailability(String streetViewUrl) async {
	  try {
		// Make a HEAD request to check if image exists
		final response = await http.head(Uri.parse(streetViewUrl))
			.timeout(Duration(seconds: 5));
		
		// Street View returns 200 even for "no image" locations,
		// but we can check content-length or make a quick GET request
		if (response.statusCode == 200) {
		  // For Street View, we assume it's available since it almost always has some image
		  return true;
		}
		
		return false;
	  } catch (e) {
		print('❌ STREET VIEW: Availability test failed: $e');
		return false;
	  }
	}


	/// NEW METHOD: Find Google Place using Nearby Search
	Future<String?> _findGooglePlace(String locationName, double lat, double lng, String apiKey) async {
	  try {
		// Clean location name for search
		String searchName = locationName.toLowerCase();
		
		// Remove common prefixes/suffixes that might confuse search
		final cleanPatterns = [
		  RegExp(r'^(restaurant|cafe|bar|shop|store|museum|gallery)\s+', caseSensitive: false),
		  RegExp(r'\s+(vienna|wien|austria|österreich).*$', caseSensitive: false),
		  RegExp(r'\s+\(\d+.*?\)$'), // Remove distance info like (1.2km)
		];
		
		for (final pattern in cleanPatterns) {
		  searchName = searchName.replaceAll(pattern, '').trim();
		}

		print('🔍 GOOGLE PLACES: Searching for "$searchName" near $lat,$lng');

		// Google Places Nearby Search API
		final url = 'https://maps.googleapis.com/maps/api/place/nearbysearch/json'
			'?location=$lat,$lng'
			'&radius=200' // Small radius since we have exact coordinates
			'&keyword=${Uri.encodeComponent(searchName)}'
			'&key=$apiKey';

		final response = await http.get(Uri.parse(url)).timeout(Duration(seconds: 10));

		if (response.statusCode == 200) {
		  final data = jsonDecode(response.body);
		  
		  if (data['status'] == 'OK' && data['results'] != null) {
			final results = data['results'] as List;
			
			if (results.isNotEmpty) {
			  // Find best matching result
			  for (final result in results.take(3)) { // Check first 3 results
				final placeName = result['name']?.toString().toLowerCase() ?? '';
				final placeId = result['place_id']?.toString();
				
				if (placeId != null && _isNameMatch(searchName, placeName)) {
				  print('🔍 GOOGLE PLACES: Found matching place "$placeName" with ID: $placeId');
				  return placeId;
				}
			  }
			  
			  // If no exact match, use first result
			  final firstResult = results[0];
			  final placeId = firstResult['place_id']?.toString();
			  final placeName = firstResult['name']?.toString() ?? 'Unknown';
			  
			  if (placeId != null) {
				print('🔍 GOOGLE PLACES: Using first result "$placeName" with ID: $placeId');
				return placeId;
			  }
			}
		  } else {
			print('🔍 GOOGLE PLACES: API status: ${data['status']}');
		  }
		} else {
		  print('❌ GOOGLE PLACES: HTTP ${response.statusCode}');
		}

		return null;
	  } catch (e) {
		print('❌ GOOGLE PLACES: Error finding place: $e');
		return null;
	  }
	}

	/// NEW METHOD: Check if place names match
	bool _isNameMatch(String searchName, String placeName) {
	  // Remove common words and normalize
	  final normalizeString = (String str) => str
		  .toLowerCase()
		  .replaceAll(RegExp(r'[^\w\s]'), '') // Remove punctuation
		  .replaceAll(RegExp(r'\s+'), ' ') // Normalize spaces
		  .trim();

	  final normalizedSearch = normalizeString(searchName);
	  final normalizedPlace = normalizeString(placeName);

	  // Check for exact match
	  if (normalizedSearch == normalizedPlace) return true;

	  // Check if one contains the other (for partial matches)
	  if (normalizedPlace.contains(normalizedSearch) || normalizedSearch.contains(normalizedPlace)) {
		return true;
	  }

	  // Check for word overlap (at least 60% of words match)
	  final searchWords = normalizedSearch.split(' ').where((w) => w.length > 2).toSet();
	  final placeWords = normalizedPlace.split(' ').where((w) => w.length > 2).toSet();
	  
	  if (searchWords.isNotEmpty && placeWords.isNotEmpty) {
		final overlap = searchWords.intersection(placeWords).length;
		final similarity = overlap / math.max(searchWords.length, placeWords.length);
		return similarity >= 0.6;
	  }

	  return false;
	}

	/// NEW METHOD: Get photo reference from Google Place
	Future<String?> _getGooglePlacePhoto(String placeId, String apiKey) async {
	  try {
		// Google Places Details API to get photos
		final url = 'https://maps.googleapis.com/maps/api/place/details/json'
			'?place_id=$placeId'
			'&fields=photos'
			'&key=$apiKey';

		final response = await http.get(Uri.parse(url)).timeout(Duration(seconds: 8));

		if (response.statusCode == 200) {
		  final data = jsonDecode(response.body);
		  
		  if (data['status'] == 'OK' && data['result'] != null) {
			final result = data['result'];
			final photos = result['photos'] as List?;
			
			if (photos != null && photos.isNotEmpty) {
			  final photoReference = photos[0]['photo_reference']?.toString();
			  if (photoReference != null) {
				print('🖼️ GOOGLE PLACES: Found photo reference');
				return photoReference;
			  }
			}
		  }
		}

		return null;
	  } catch (e) {
		print('❌ GOOGLE PLACES: Error getting photo reference: $e');
		return null;
	  }
	}

	/// NEW METHOD: Build Google Place Photo URL
	String _buildGooglePlacePhotoUrl(String photoReference, String apiKey) {
	  // Google Places Photo API with optimized parameters
	  return 'https://maps.googleapis.com/maps/api/place/photo'
		  '?maxwidth=400' // Good balance between quality and cost
		  '&maxheight=300'
		  '&photo_reference=$photoReference'
		  '&key=$apiKey';
	}
	
	/// NEW METHOD: Get image from Wikipedia API
	Future<String?> _getImageFromWikipediaAPI(String wikipediaRef) async {
	  try {
		// Parse Wikipedia reference format: "en:Article Name" or "de:Article Name" or just "Article Name"
		String language = 'en'; // Default to English
		String articleTitle = wikipediaRef;
		
		if (wikipediaRef.contains(':')) {
		  final parts = wikipediaRef.split(':');
		  if (parts.length >= 2) {
			language = parts[0];
			articleTitle = parts.sublist(1).join(':');
		  }
		}
		
		print('📚 WIKIPEDIA API: Searching for "$articleTitle" in $language');
		
		// Step 1: Get page info and main image
		final pageImageUrl = await _getWikipediaPageImage(language, articleTitle);
		if (pageImageUrl != null) {
		  return pageImageUrl;
		}
		
		// Step 2: If no main image, try to get first image from page content
		final contentImageUrl = await _getWikipediaContentImage(language, articleTitle);
		if (contentImageUrl != null) {
		  return contentImageUrl;
		}
		
		print('📚 WIKIPEDIA API: No images found for "$articleTitle"');
		return null;
		
	  } catch (e) {
		print('❌ WIKIPEDIA API: Error getting image: $e');
		return null;
	  }
	}

	/// NEW METHOD: Get main image from Wikipedia page
	Future<String?> _getWikipediaPageImage(String language, String articleTitle) async {
	  try {
		// Wikipedia API endpoint for page info with main image
		final encodedTitle = Uri.encodeComponent(articleTitle);
		final url = 'https://$language.wikipedia.org/api/rest_v1/page/summary/$encodedTitle';
		
		print('📚 WIKIPEDIA: Getting page summary for $url');
		
		final response = await http.get(
		  Uri.parse(url),
		  headers: {
			'User-Agent': 'LocadoApp/1.0 (contact@locado.app)',
			'Accept': 'application/json',
		  },
		).timeout(Duration(seconds: 8));
		
		if (response.statusCode == 200) {
		  final data = jsonDecode(response.body);
		  
		  // Try to get thumbnail or originalimage
		  String? imageUrl;
		  
		  if (data['thumbnail'] != null && data['thumbnail']['source'] != null) {
			imageUrl = data['thumbnail']['source'].toString();
			print('📚 WIKIPEDIA: Found thumbnail image');
		  } else if (data['originalimage'] != null && data['originalimage']['source'] != null) {
			imageUrl = data['originalimage']['source'].toString();
			print('📚 WIKIPEDIA: Found original image');
		  }
		  
		  if (imageUrl != null && _isValidImageUrl(imageUrl)) {
			// Convert thumbnail to higher resolution if possible
			final highResImageUrl = _enhanceWikipediaImageResolution(imageUrl);
			print('📚 WIKIPEDIA: Enhanced image resolution: $highResImageUrl');
			return highResImageUrl;
		  }
		} else if (response.statusCode == 404) {
		  print('📚 WIKIPEDIA: Article "$articleTitle" not found in $language');
		} else {
		  print('📚 WIKIPEDIA: API returned status ${response.statusCode}');
		}
		
		return null;
	  } catch (e) {
		print('❌ WIKIPEDIA: Error getting page image: $e');
		return null;
	  }
	}

	/// NEW METHOD: Get first image from Wikipedia page content
	Future<String?> _getWikipediaContentImage(String language, String articleTitle) async {
	  try {
		// Wikipedia API endpoint for page content
		final encodedTitle = Uri.encodeComponent(articleTitle);
		final url = 'https://$language.wikipedia.org/w/api.php'
			'?action=query'
			'&format=json'
			'&titles=$encodedTitle'
			'&prop=images'
			'&imlimit=5'; // Get first 5 images
		
		print('📚 WIKIPEDIA: Getting page images for $url');
		
		final response = await http.get(
		  Uri.parse(url),
		  headers: {
			'User-Agent': 'LocadoApp/1.0 (contact@locado.app)',
			'Accept': 'application/json',
		  },
		).timeout(Duration(seconds: 8));
		
		if (response.statusCode == 200) {
		  final data = jsonDecode(response.body);
		  final pages = data['query']?['pages'] as Map<String, dynamic>?;
		  
		  if (pages != null) {
			for (final pageData in pages.values) {
			  final images = pageData['images'] as List<dynamic>?;
			  if (images != null && images.isNotEmpty) {
				
				// Filter out common non-content images
				for (final image in images) {
				  final imageTitle = image['title']?.toString() ?? '';
				  
				  // Skip common Wikipedia UI images
				  if (_isContentImage(imageTitle)) {
					final imageUrl = await _getWikipediaImageUrl(language, imageTitle);
					if (imageUrl != null) {
					  print('📚 WIKIPEDIA: Found content image: $imageUrl');
					  return imageUrl;
					}
				  }
				}
			  }
			}
		  }
		}
		
		return null;
	  } catch (e) {
		print('❌ WIKIPEDIA: Error getting content images: $e');
		return null;
	  }
	}

	/// NEW METHOD: Get actual URL for Wikipedia image file
	Future<String?> _getWikipediaImageUrl(String language, String imageTitle) async {
	  try {
		// Remove "File:" prefix if present
		String filename = imageTitle;
		if (filename.startsWith('File:')) {
		  filename = filename.substring(5);
		}
		
		// Wikipedia API to get image URL
		final encodedFilename = Uri.encodeComponent('File:$filename');
		final url = 'https://$language.wikipedia.org/w/api.php'
			'?action=query'
			'&format=json'
			'&titles=$encodedFilename'
			'&prop=imageinfo'
			'&iiprop=url'
			'&iiurlwidth=400'; // Request 400px width
		
		final response = await http.get(
		  Uri.parse(url),
		  headers: {
			'User-Agent': 'LocadoApp/1.0 (contact@locado.app)',
		  },
		).timeout(Duration(seconds: 6));
		
		if (response.statusCode == 200) {
		  final data = jsonDecode(response.body);
		  final pages = data['query']?['pages'] as Map<String, dynamic>?;
		  
		  if (pages != null) {
			for (final pageData in pages.values) {
			  final imageInfo = pageData['imageinfo'] as List<dynamic>?;
			  if (imageInfo != null && imageInfo.isNotEmpty) {
				final imageUrl = imageInfo[0]['thumburl'] ?? imageInfo[0]['url'];
				if (imageUrl != null && _isValidImageUrl(imageUrl.toString())) {
				  return imageUrl.toString();
				}
			  }
			}
		  }
		}
		
		return null;
	  } catch (e) {
		print('❌ WIKIPEDIA: Error getting image URL: $e');
		return null;
	  }
	}

	/// NEW METHOD: Check if image is content image (not UI/navigation image)
	bool _isContentImage(String imageTitle) {
	  final lowerTitle = imageTitle.toLowerCase();
	  
	  // Skip common Wikipedia UI and navigation images
	  final skipImages = [
		'commons-logo',
		'wikimedia',
		'edit-icon',
		'ambox',
		'question_book',
		'crystal_clear',
		'nuvola',
		'folder_home',
		'searchtool',
		'wiki.png',
		'symbol_support',
		'symbol_oppose',
		'crystal_128',
		'emblem-important',
		'dialog-information',
		'gtk-dialog-info',
	  ];
	  
	  // Skip images that are clearly UI elements
	  if (skipImages.any((skip) => lowerTitle.contains(skip))) {
		return false;
	  }
	  
	  // Skip very small images (usually icons)
	  if (lowerTitle.contains('icon') && lowerTitle.contains('16') || 
		  lowerTitle.contains('icon') && lowerTitle.contains('24')) {
		return false;
	  }
	  
	  // Prefer actual photographs and illustrations
	  final goodImages = ['.jpg', '.jpeg', '.png', '.gif', '.webp'];
	  return goodImages.any((ext) => lowerTitle.contains(ext));
	}

	/// NEW METHOD: Enhance Wikipedia image resolution
	String _enhanceWikipediaImageResolution(String imageUrl) {
	  try {
		// Wikipedia thumbnail URLs can be enhanced by changing the resolution
		// Example: /thumb/a/ab/Example.jpg/200px-Example.jpg -> /thumb/a/ab/Example.jpg/400px-Example.jpg
		
		final RegExp thumbnailRegex = RegExp(r'/(\d+)px-([^/]+)$');
		final match = thumbnailRegex.firstMatch(imageUrl);
		
		if (match != null) {
		  final currentWidth = int.tryParse(match.group(1) ?? '');
		  final filename = match.group(2);
		  
		  if (currentWidth != null && currentWidth < 400 && filename != null) {
			// Enhance to 400px width for better quality
			final enhancedUrl = imageUrl.replaceFirst(
			  '/${currentWidth}px-$filename',
			  '/400px-$filename'
			);
			print('📚 WIKIPEDIA: Enhanced resolution from ${currentWidth}px to 400px');
			return enhancedUrl;
		  }
		}
		
		return imageUrl;
	  } catch (e) {
		print('❌ WIKIPEDIA: Error enhancing resolution: $e');
		return imageUrl;
	  }
	}

	/// NEW METHOD: Validate if URL is a valid image URL
	bool _isValidImageUrl(String url) {
	  try {
		final uri = Uri.parse(url);
		
		// Check if URL is valid
		if (!uri.hasScheme || (!uri.scheme.startsWith('http'))) {
		  return false;
		}

		// Check if URL ends with image extension
		final imageExtensions = ['.jpg', '.jpeg', '.png', '.gif', '.webp', '.bmp', '.svg'];
		final lowerUrl = url.toLowerCase();
		
		return imageExtensions.any((ext) => lowerUrl.contains(ext));
	  } catch (e) {
		return false;
	  }
	}

	/// NEW METHOD: Convert Wikimedia Commons reference to image URL
	String? _convertWikimediaToImageUrl(String wikimediaRef) {
	  try {
		// Wikimedia Commons format: "File:Example.jpg" or "Category:Example" or just "Example.jpg"
		String filename = wikimediaRef;
		
		// Remove "File:" prefix if present
		if (filename.startsWith('File:')) {
		  filename = filename.substring(5);
		}
		
		// Skip categories
		if (filename.startsWith('Category:')) {
		  return null;
		}
		
		// Check if it's an image file
		if (!_isValidImageUrl(filename)) {
		  return null;
		}
		
		// Convert to Wikimedia Commons URL
		// Format: https://commons.wikimedia.org/wiki/Special:FilePath/FILENAME
		final encodedFilename = Uri.encodeComponent(filename);
		final wikimediaUrl = 'https://commons.wikimedia.org/wiki/Special:FilePath/$encodedFilename';
		
		print('🖼️ WIKIMEDIA: Converted "$wikimediaRef" to "$wikimediaUrl"');
		return wikimediaUrl;
	  } catch (e) {
		print('❌ WIKIMEDIA: Error converting reference: $e');
		return null;
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

		// STEP 2: DIRECT OSM search with AI-optimized terms
		final directOSMResults = await _searchDirectlyInTargetLocation(query, targetCoordinates, targetLocation);

		print('✅ SPECIFIC LOCATION SEARCH: Found ${directOSMResults.length} results in $targetLocation');
		return directOSMResults;

	  } catch (e) {
		print('❌ SPECIFIC LOCATION SEARCH: Error = $e');
		throw Exception('Failed to search in $targetLocation: $e');
	  }
	}
  
	// ENHANCED METHOD: Direct OSM search with dynamic radius and more results
	Future<List<AILocationResult>> _searchDirectlyInTargetLocation(
		String query, 
		UniversalLatLng targetCoords, 
		String locationName
	) async {
	  List<AILocationResult> results = [];
	  
	  try {
		// Get AI-optimized terms directly (no country detection)
		final optimizedQuery = await _optimizeQueryForOSM(query);
		final searchTerms = [query, ...optimizedQuery.split(',').map((t) => t.trim())];
		
		// Add local language terms for target location
		final localTerms = await _getLocalTermsForTargetLocation(query, locationName);
		searchTerms.addAll(localTerms);
		
		// Remove duplicates
		final uniqueTerms = searchTerms.toSet().toList();
		
		print('🗺️ ENHANCED SEARCH TERMS for $locationName: $uniqueTerms');
		
		// DYNAMIC RADIUS SEARCH - start small and increase until we find enough results
		final List<double> radiusList = [0.02, 0.05, 0.1, 0.2, 0.5]; // km equivalent
		final List<double> distanceLimits = [5000, 10000, 20000, 50000, 100000]; // meters
		
		for (int radiusIndex = 0; radiusIndex < radiusList.length; radiusIndex++) {
		  final radius = radiusList[radiusIndex];
		  final distanceLimit = distanceLimits[radiusIndex];
		  
		  print('🔍 TRYING RADIUS: ${(radius * 111).toStringAsFixed(1)}km (${distanceLimit/1000}km distance limit)');
		  
		  for (String term in uniqueTerms.take(8)) { // Search with up to 8 terms
			final url = 'https://nominatim.openstreetmap.org/search'
				'?q=${Uri.encodeComponent(term)}'
				'&format=json'
				'&addressdetails=1'
				'&limit=20' // Increased limit
				'&lat=${targetCoords.latitude}'
				'&lon=${targetCoords.longitude}'
				'&bounded=1'
				'&viewbox=${targetCoords.longitude - radius},${targetCoords.latitude + radius},${targetCoords.longitude + radius},${targetCoords.latitude - radius}';

			final response = await http.get(
			  Uri.parse(url),
			  headers: {'User-Agent': 'LocadoApp/1.0'},
			).timeout(Duration(seconds: 8));

			if (response.statusCode == 200) {
			  final List<dynamic> places = jsonDecode(response.body);
			  
			  for (final place in places.take(10)) { // Process up to 10 per term
				final lat = double.parse(place['lat']);
				final lng = double.parse(place['lon']);
				final name = place['display_name'] ?? 'Unknown Place';
				final type = place['type'] ?? 'location';
				
				// Calculate distance from target
				final distance = Geolocator.distanceBetween(
				  targetCoords.latitude,
				  targetCoords.longitude,
				  lat,
				  lng,
				);

				// Check if within distance limit and not already added
				if (distance <= distanceLimit) {
				  final cleanName = _cleanDisplayName(name);
				  
				  // Avoid duplicates by coordinates
				  final isDuplicate = results.any((existing) => 
					Geolocator.distanceBetween(
					  existing.coordinates.latitude,
					  existing.coordinates.longitude,
					  lat,
					  lng,
					) < 100); // 100m tolerance
				  
				  if (!isDuplicate) {
					final taskItems = await _generateTaskItemsFromType(cleanName, type);
					
					results.add(AILocationResult(
					  name: cleanName,
					  description: 'Local $type in $locationName (${(distance/1000).toStringAsFixed(1)}km away)',
					  coordinates: UniversalLatLng(lat, lng),
					  taskItems: taskItems,
					  category: type,
					  distanceFromUser: _currentLatLng != null 
						  ? Geolocator.distanceBetween(_currentLatLng!.latitude, _currentLatLng!.longitude, lat, lng)
						  : null,
					  imageUrl: null,
					));
					
					print('🗺️ DIRECT OSM: Found ${cleanName} in $locationName (${(distance/1000).toStringAsFixed(1)}km)');
				  }
				}
			  }
			}
		  }
		  
		  // Check if we have enough results
		  if (results.length >= 5) {
			print('✅ FOUND ENOUGH RESULTS: ${results.length} locations within ${(radius * 111).toStringAsFixed(1)}km');
			break;
		  }
		}
		
		// Sort by distance from target location
		results.sort((a, b) {
		  final distanceA = Geolocator.distanceBetween(
			targetCoords.latitude, targetCoords.longitude,
			a.coordinates.latitude, a.coordinates.longitude
		  );
		  final distanceB = Geolocator.distanceBetween(
			targetCoords.latitude, targetCoords.longitude,
			b.coordinates.latitude, b.coordinates.longitude
		  );
		  return distanceA.compareTo(distanceB);
		});
		
	  } catch (e) {
		print('❌ DIRECT OSM: Error = $e');
	  }
	  
	  // Return up to 15 results
	  return results.take(15).toList();
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

	// IMPROVED METHOD: Enhanced coordinate search for specific locations
	Future<UniversalLatLng?> _getCoordinatesFromNominatim(String locationName, String city) async {
	  try {
		// STRATEGY 1: Search with full name + city
		final query1 = Uri.encodeComponent('$locationName $city');
		var coordinates = await _tryNominatimSearch(query1);
		if (coordinates != null) return coordinates;
		
		// STRATEGY 2: Search with just location name in the target city area
		final query2 = Uri.encodeComponent(locationName);
		coordinates = await _tryNominatimSearchWithBounds(query2, city);
		if (coordinates != null) return coordinates;
		
		// STRATEGY 3: Search for general category in city (fallback)
		final query3 = Uri.encodeComponent('hair salon $city');
		coordinates = await _tryNominatimSearch(query3);
		if (coordinates != null) return coordinates;
		
		print('❌ No coordinates found for "$locationName" in "$city"');
		return null;
		
	  } catch (e) {
		print('❌ Error getting coordinates from Nominatim: $e');
		return null;
	  }
	}

	// Helper method for basic Nominatim search
	Future<UniversalLatLng?> _tryNominatimSearch(String query) async {
	  final url = 'https://nominatim.openstreetmap.org/search'
		  '?q=$query'
		  '&format=json'
		  '&limit=1';

	  final response = await http.get(
		Uri.parse(url),
		headers: {'User-Agent': 'LocadoApp/1.0'},
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
	  return null;
	}

	// Helper method for bounded search
	Future<UniversalLatLng?> _tryNominatimSearchWithBounds(String query, String city) async {
	  // First get city bounds
	  final cityCoords = await _getTargetLocationCoordinatesNominatim(city);
	  if (cityCoords == null) return null;
	  
	  // Search within city bounds
	  final bound = 0.05; // ~5km radius
	  final url = 'https://nominatim.openstreetmap.org/search'
		  '?q=$query'
		  '&format=json'
		  '&limit=3'
		  '&bounded=1'
		  '&viewbox=${cityCoords.longitude - bound},${cityCoords.latitude + bound},${cityCoords.longitude + bound},${cityCoords.latitude - bound}';

	  final response = await http.get(
		Uri.parse(url),
		headers: {'User-Agent': 'LocadoApp/1.0'},
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
   return colors[math.Random().nextInt(colors.length)];
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

// UPDATED METHOD: AI-powered search intent detection
Future<SearchIntent> _detectSearchIntent(String originalQuery) async {
  print('🔍 INTENT DETECTION: Analyzing query: "$originalQuery"');

  try {
    // Use AI to detect intent instead of hardcoded keywords
    final aiIntentDetection = await _detectIntentWithAI(originalQuery);
    
	if (aiIntentDetection['hasSpecificLocation'] == true) {
	  final targetLocation = aiIntentDetection['location'] as String;
	  final cleanQuery = aiIntentDetection['cleanQuery'] as String;
	  
	  print('✅ INTENT: AI detected specific location: "$targetLocation"');
	  return SearchIntent(
		isLocalSearch: false,
		targetLocation: targetLocation,
		cleanQuery: cleanQuery,
		originalQuery: originalQuery,
	  );
	}

	if (aiIntentDetection['isLocalSearch'] == true) {
	  print('✅ INTENT: AI detected nearby search');
	  return SearchIntent(
		isLocalSearch: true,
		targetLocation: null,
		cleanQuery: aiIntentDetection['cleanQuery'] ?? originalQuery,
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

/// UPDATED METHOD: Progressive search with immediate Nominatim + background Overpass
	Future<void> _performOptimizedQuickSearchProgressive(String query) async {
	  if (_openAIApiKey == 'YOUR_OPENAI_API_KEY_HERE') {
		_showSnackBar('Please add your OpenAI API key', Colors.red);
		return;
	  }

	  // Check network
	  try {
		await http.get(Uri.parse('https://www.google.com')).timeout(Duration(seconds: 3));
	  } catch (e) {
		_showSnackBar('No internet connection. Please check your network.', Colors.red);
		return;
	  }

	  // Ensure we have location
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
		_isEnhancing = false;
	  });

	  try {
		print('🚀 PROGRESSIVE SEARCH: Starting for "$query"');
		
		// Step 1: Get category-specific data
		final osmTags = _getCategoryOSMTags(query);
		final countryCode = await _getCurrentCountryCode();
		final category = query.split(' ')[0];
		final localTerms = await _translateCategoryToLocal(category, countryCode);
		
		print('🏷️ OSM TAGS: $osmTags');
		print('🌍 LOCAL TERMS: $localTerms');
		
		// Step 2: PHASE 1 - Quick Nominatim search for immediate results
		print('⚡ PHASE 1: Quick Nominatim search for immediate results');
		List<AILocationResult> nominatimResults = await _searchNominatimQuick(category, localTerms, query);
		
		// Step 3: Show immediate results to user
		setState(() {
		  _searchResults = nominatimResults;
		  _hasSearched = true;
		  _isLoading = false;
		  _isEnhancing = nominatimResults.isNotEmpty; // Show enhancement indicator if we have results
		});

		if (nominatimResults.isNotEmpty) {
		  _showSnackBar('Found ${nominatimResults.length} locations, enhancing with detailed data...', Colors.blue);
		} else {
		  _showSnackBar('No locations found nearby', Colors.orange);
		}
		
		// Step 4: PHASE 2 - Background Overpass enhancement (don't await - runs in background)
		if (nominatimResults.isNotEmpty) {
		  _enhanceWithOverpassInBackground(category, localTerms, osmTags, nominatimResults);
		} else {
		  // If Nominatim found nothing, try rural search as fallback
		  _tryRuralSearchFallback(category, localTerms, osmTags);
		}

	  } catch (e, stackTrace) {
		print('❌ PROGRESSIVE SEARCH: ERROR = $e');
		print('❌ PROGRESSIVE SEARCH: STACK TRACE = $stackTrace');

		setState(() {
		  _isLoading = false;
		  _hasSearched = true;
		  _isEnhancing = false;
		});
		_showSnackBar('Search error: ${e.toString()}', Colors.red);
	  }
	}

	/// NEW METHOD: Quick Nominatim search for both urban and rural areas
	Future<List<AILocationResult>> _searchNominatimQuick(String category, List<String> localTerms, String originalQuery) async {
	  if (_currentLatLng == null) return [];
	  
	  try {
		print('⚡ NOMINATIM QUICK: Starting fast search for "$category"');
		
		// Determine if it's a local search
		final isLocalSearch = originalQuery.toLowerCase().contains('nearby') ||
			originalQuery.toLowerCase().contains('around') ||
			originalQuery.toLowerCase().contains('close') ||
			originalQuery.toLowerCase().contains('near me') ||
			originalQuery.toLowerCase().contains('in the area');
		
		// Start with small radius and expand if needed
		final radiusList = isLocalSearch 
			? [0.02, 0.05, 0.1] // Urban focus: 2km, 5km, 10km
			: [0.05, 0.1, 0.2]; // Broader search: 5km, 10km, 20km
		
		final distanceLimits = isLocalSearch
			? [2000, 5000, 10000] // meters
			: [5000, 10000, 20000]; // meters
		
		// Prepare search terms
		final searchTerms = <String>[category];
		for (final localTerm in localTerms) {
		  final terms = localTerm.contains(',') 
			  ? localTerm.split(',').map((t) => t.trim()).toList()
			  : [localTerm];
		  
		  for (final term in terms) {
			final cleanTerm = term.replaceAll('"', '').replaceAll("'", '').trim();
			if (cleanTerm.isNotEmpty && cleanTerm.length > 2) {
			  searchTerms.add(cleanTerm);
			}
		  }
		}
		
		final uniqueSearchTerms = searchTerms.toSet().take(4).toList(); // Limit to 4 terms for speed
		print('⚡ NOMINATIM QUICK: Search terms: $uniqueSearchTerms');
		
		List<AILocationResult> results = [];
		final Set<String> addedCoordinates = {};
		
		// Try each radius until we find enough results
		for (int radiusIndex = 0; radiusIndex < radiusList.length; radiusIndex++) {
		  final radiusDegrees = radiusList[radiusIndex];
		  final distanceLimit = distanceLimits[radiusIndex];
		  final radiusKm = distanceLimit / 1000;
		  
		  print('⚡ NOMINATIM QUICK: Trying radius ${radiusKm}km');
		  
		  // Search with each term
		  for (final searchTerm in uniqueSearchTerms) {
			try {
			  final url = 'https://nominatim.openstreetmap.org/search'
				  '?q=${Uri.encodeComponent(searchTerm)}'
				  '&format=json'
				  '&addressdetails=1'
				  '&limit=15'
				  '&lat=${_currentLatLng!.latitude}'
				  '&lon=${_currentLatLng!.longitude}'
				  '&bounded=1'
				  '&viewbox=${_currentLatLng!.longitude - radiusDegrees},${_currentLatLng!.latitude + radiusDegrees},${_currentLatLng!.longitude + radiusDegrees},${_currentLatLng!.latitude - radiusDegrees}';

			  final response = await http.get(
				Uri.parse(url),
				headers: {'User-Agent': 'LocadoApp/1.0'},
			  ).timeout(Duration(seconds: 6)); // Quick timeout for immediate results

			  if (response.statusCode == 200) {
				final List<dynamic> places = jsonDecode(response.body);
				
				for (final place in places.take(10)) {
				  final lat = double.parse(place['lat']);
				  final lng = double.parse(place['lon']);
				  final name = place['display_name'] ?? 'Unknown Place';
				  final type = place['type'] ?? 'location';
				  
				  final coordKey = '${lat.toStringAsFixed(6)}_${lng.toStringAsFixed(6)}';
				  if (addedCoordinates.contains(coordKey)) continue;
				  
				  final distance = Geolocator.distanceBetween(
					_currentLatLng!.latitude,
					_currentLatLng!.longitude,
					lat,
					lng,
				  );

				  if (distance <= distanceLimit) {
					addedCoordinates.add(coordKey);
					
					final cleanName = _cleanDisplayName(name);
					final taskItems = await _generateTaskItemsFromType(cleanName, type);
					

					results.add(AILocationResult(
					  name: cleanName,
					  description: 'Local $type (${(distance/1000).toStringAsFixed(1)}km away)',
					  coordinates: UniversalLatLng(lat, lng),
					  taskItems: taskItems,
					  category: type,
					  distanceFromUser: distance,
					  imageUrl: null,
					));
					
					print('⚡ NOMINATIM QUICK: Added $cleanName (${(distance/1000).toStringAsFixed(1)}km)');
				  }
				}
			  }
			  
			  // Small delay between requests
			  await Future.delayed(Duration(milliseconds: 150));
			  
			} catch (e) {
			  print('❌ NOMINATIM QUICK: Error searching "$searchTerm": $e');
			  continue;
			}
		  }
		  
		  // Stop if we have enough results for quick display
		  if (results.length >= 5) {
			print('⚡ NOMINATIM QUICK: Found ${results.length} results at ${radiusKm}km - sufficient for quick display');
			break;
		  }
		}
		
		// Sort by distance
		results.sort((a, b) => a.distanceFromUser!.compareTo(b.distanceFromUser!));
		
		print('⚡ NOMINATIM QUICK: Final quick results: ${results.length}');
		return results.take(20).toList();
		
	  } catch (e) {
		print('❌ NOMINATIM QUICK: Error = $e');
		return [];
	  }
	}

	/// NEW METHOD: Background Overpass enhancement
	/// FIXED METHOD: Background Overpass enhancement with null safety
		Future<void> _enhanceWithOverpassInBackground(
			String category, 
			List<String> localTerms,
			Map<String, List<String>> osmTags,
			List<AILocationResult> nominatimResults
		) async {
		  try {
			print('🔄 BACKGROUND ENHANCEMENT: Starting Overpass enhancement');
			
			// Get available servers
			final availableServers = await _getOptimalServerOrder();
			
			// Try urban search first (1.5km radius)
			List<AILocationResult> overpassResults = await _searchOverpassDirect(category, localTerms, osmTags);
			
			// If urban didn't find much, try rural
			if (overpassResults.length < 3) {
			  print('🔄 BACKGROUND ENHANCEMENT: Urban Overpass found only ${overpassResults.length}, trying rural');
			  final ruralOverpassResults = await _searchOverpassRuralFallback(category, localTerms, osmTags, availableServers);
			  if (ruralOverpassResults.length > overpassResults.length) {
				overpassResults = ruralOverpassResults;
			  }
			}
			
			// Combine and deduplicate results
			final combinedResults = _combineAndDeduplicateResults(nominatimResults, overpassResults);
			
			// SAFETY CHECK: Only update UI if widget is still mounted
			if (!mounted) {
			  print('🔄 BACKGROUND ENHANCEMENT: Widget unmounted, skipping UI update');
			  return;
			}
			
			// Update UI with enhanced results
			setState(() {
			  _searchResults = combinedResults;
			  _isEnhancing = false;
			});
			
			if (combinedResults.length > nominatimResults.length) {
			  _showSnackBar('Enhanced with ${combinedResults.length - nominatimResults.length} additional detailed locations', Colors.green);
			} else {
			  _showSnackBar('Search completed with detailed information', Colors.green);
			}
			
			print('✅ BACKGROUND ENHANCEMENT: Completed - ${nominatimResults.length} → ${combinedResults.length} results');
			
		  } catch (e) {
			print('❌ BACKGROUND ENHANCEMENT: Error = $e');
			
			// SAFETY CHECK: Only update UI if widget is still mounted
			if (mounted) {
			  setState(() {
				_isEnhancing = false;
			  });
			  _showSnackBar('Background enhancement completed', Colors.blue);
			}
		  }
		}
	/// NEW METHOD: Combine and deduplicate results from different sources
	/// UPDATED METHOD: Combine and deduplicate results with proper image URL preservation
	List<AILocationResult> _combineAndDeduplicateResults(
	  List<AILocationResult> nominatimResults, 
	  List<AILocationResult> overpassResults
	) {
	  print('🔗 COMBINING RESULTS: Nominatim: ${nominatimResults.length}, Overpass: ${overpassResults.length}');
	  
	  final Map<String, AILocationResult> combinedMap = {};
	  
	  // Add Nominatim results first
	  for (final result in nominatimResults) {
		final key = '${result.coordinates.latitude.toStringAsFixed(5)}_${result.coordinates.longitude.toStringAsFixed(5)}';
		combinedMap[key] = result;
		
		// DEBUG: Log image URL status for Nominatim results
		if (result.imageUrl != null) {
		  print('🔗 NOMINATIM: ${result.name} HAS image URL');
		} else {
		  print('🔗 NOMINATIM: ${result.name} NO image URL');
		}
	  }
	  
	  // Add Overpass results, merging or replacing where appropriate
	  for (final overpassResult in overpassResults) {
		final key = '${overpassResult.coordinates.latitude.toStringAsFixed(5)}_${overpassResult.coordinates.longitude.toStringAsFixed(5)}';
		
		if (combinedMap.containsKey(key)) {
		  // MERGE data - PRESERVE image URLs from both sources
		  final existing = combinedMap[key]!;
		  
		  // DEBUG: Log what we're merging
		  print('🔗 MERGING: ${existing.name}');
		  print('   - Existing image: ${existing.imageUrl != null ? "YES" : "NO"}');
		  print('   - Overpass image: ${overpassResult.imageUrl != null ? "YES" : "NO"}');
		  
		  // Use Overpass data if it has more detailed task items or better category
		  // BUT PRESERVE IMAGE URL FROM EITHER SOURCE
		  String? mergedImageUrl;
		  if (overpassResult.imageUrl != null) {
			mergedImageUrl = overpassResult.imageUrl; // Prefer Overpass image (Street View)
			print('   - Using Overpass image URL');
		  } else if (existing.imageUrl != null) {
			mergedImageUrl = existing.imageUrl; // Keep existing image if Overpass has none
			print('   - Keeping existing image URL');
		  } else {
			mergedImageUrl = null;
			print('   - No image URL available');
		  }
		  
		  combinedMap[key] = AILocationResult(
			name: existing.name, // Keep original name
			description: overpassResult.description.isNotEmpty ? overpassResult.description : existing.description,
			coordinates: existing.coordinates, // Keep original coordinates
			taskItems: overpassResult.taskItems.isNotEmpty ? overpassResult.taskItems : existing.taskItems,
			category: overpassResult.category != 'location' ? overpassResult.category : existing.category,
			distanceFromUser: existing.distanceFromUser,
			isSelected: existing.isSelected,
			imageUrl: mergedImageUrl, // ✅ PRESERVE IMAGE URL!
		  );
		  
		  print('   - Final merged result has image: ${mergedImageUrl != null ? "YES" : "NO"}');
		  
		} else {
		  // Add new Overpass result
		  print('🔗 ADDING: New Overpass result ${overpassResult.name}');
		  print('   - Has image: ${overpassResult.imageUrl != null ? "YES" : "NO"}');
		  combinedMap[key] = overpassResult;
		}
	  }
	  
	  // Convert back to list and sort by distance
	  final combinedResults = combinedMap.values.toList();
	  combinedResults.sort((a, b) {
		if (a.distanceFromUser == null && b.distanceFromUser == null) return 0;
		if (a.distanceFromUser == null) return 1;
		if (b.distanceFromUser == null) return -1;
		return a.distanceFromUser!.compareTo(b.distanceFromUser!);
	  });
	  
	  // DEBUG: Final image URL count
	  final imagesCount = combinedResults.where((r) => r.imageUrl != null).length;
	  print('🔗 COMBINED RESULTS: Final count: ${combinedResults.length}, Images: $imagesCount');
	  
	  // DEBUG: List all results with image status
	  for (int i = 0; i < combinedResults.length && i < 10; i++) {
		final result = combinedResults[i];
		print('🔗 FINAL [$i]: ${result.name} - Image: ${result.imageUrl != null ? "YES" : "NO"}');
	  }
	  
	  return combinedResults.take(25).toList();
	}

	/// NEW METHOD: Rural search fallback when Nominatim finds nothing
	Future<void> _tryRuralSearchFallback(String category, List<String> localTerms, Map<String, List<String>> osmTags) async {
	  try {
		print('🌾 RURAL FALLBACK: Nominatim found nothing, trying rural search');
		
		setState(() {
		  _isEnhancing = true;
		});
		
		final availableServers = await _getOptimalServerOrder();
		final ruralResults = await _searchRuralWithNominatimPrimary(category, localTerms, osmTags, availableServers);
		
		setState(() {
		  _searchResults = ruralResults;
		  _isEnhancing = false;
		});
		
		if (ruralResults.isNotEmpty) {
		  final searchType = ruralResults.any((r) => r.distanceFromUser != null && r.distanceFromUser! > 2000) 
			  ? 'expanded area' : 'nearby';
		  _showSnackBar('Found ${ruralResults.length} locations in $searchType', Colors.green);
		} else {
		  _showSnackBar('No locations found in the area', Colors.orange);
		}
		
	  } catch (e) {
		print('❌ RURAL FALLBACK: Error = $e');
		setState(() {
		  _isEnhancing = false;
		});
		_showSnackBar('No locations found in the area', Colors.orange);
	  }
	}

	// NEW METHOD: AI-powered intent detection
	Future<Map<String, dynamic>> _detectIntentWithAI(String query) async {
		final prompt = '''Analyze this search query and determine the search intent:

		1. Is this a LOCAL/NEARBY search? (user wants places near their current location)
		2. Is this a SPECIFIC LOCATION search? (user specifies a city/country)
		3. What is the clean search query without location indicators?

		Examples:
		"pharmacy nearby" → local: true, clean: "pharmacy"
		"nadji frizere u blizini" → local: true, clean: "frizere" 
		"restaurants in Paris" → location: "Paris", clean: "restaurants"
		"nadji frizere u Banja Luci" → location: "Banja Luka", clean: "frizere"
		"wo ist apotheke in Berlin" → location: "Berlin", clean: "apotheke"
		"ristorante a Roma" → location: "Roma", clean: "ristorante"
		"mjesta za provod u Zagrebu" → location: "Zagreb", clean: "mjesta za provod"
		"coffee shops in London" → location: "London", clean: "coffee shops"
		"coffee shops" → local: true, clean: "coffee shops" (assume nearby)

		IMPORTANT: If query contains "u [City]", "in [City]", "a [City]", "en [City]" - it's a specific location search!

	User query: "$query"

	Respond with ONLY this JSON format:
	{
	  "isLocalSearch": true/false,
	  "hasSpecificLocation": true/false,
	  "location": "City, Country" or null,
	  "cleanQuery": "search terms without location words"
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
		  
		  // DEBUG: Print raw AI response
		  print('🤖 AI INTENT RAW RESPONSE: "$content"');
		  
		  try {
			final result = jsonDecode(content);
			print('🤖 AI INTENT PARSED: $result');
			return result;
		  } catch (e) {
			print('❌ AI INTENT PARSE ERROR: $e');
			throw Exception('Failed to parse AI intent response: $e');
		  }
		}

	  throw Exception('AI intent detection failed');
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
 
	// ==================== OPTIMIZED QUICK SEARCH METHODS ====================

	/// Get OSM tags for specific category
	Map<String, List<String>> _getCategoryOSMTags(String category) {
	  final categoryLower = category.toLowerCase();
	  
	  if (categoryLower.contains('pharmacy') || categoryLower.contains('pharmacies')) {
		return {
		  'amenity': ['pharmacy'],
		  'healthcare': ['pharmacy'],
		  'shop': ['pharmacy']
		};
	  }
	  
	  if (categoryLower.contains('restaurant') || categoryLower.contains('restaurants')) {
		return {
		  'amenity': ['restaurant', 'fast_food'],
		  'cuisine': ['*'] // All cuisine types
		};
	  }
	  
		if (categoryLower.contains('coffee')) {
		  return {
			'amenity': ['cafe', 'fast_food', 'restaurant', 'bar', 'biergarten'],
			'shop': ['coffee', 'bakery', 'confectionery', 'pastry', 'tea'],
			'cuisine': ['coffee_shop', 'cafe', 'coffee', 'tea', 'breakfast', 'brunch'],
			'leisure': ['garden'], // Za outdoor coffee gardens
			'tourism': ['attraction'], // Za famous coffee spots
			'building': ['commercial'], // Sometimes coffee shops are tagged as commercial buildings
		  };
		}
	  
	  if (categoryLower.contains('gas') || categoryLower.contains('fuel')) {
		return {
		  'amenity': ['fuel']
		};
	  }
	  
	  if (categoryLower.contains('supermarket') || categoryLower.contains('market')) {
		return {
		  'shop': ['supermarket', 'convenience', 'grocery']
		};
	  }
	  
	  if (categoryLower.contains('bank')) {
		return {
		  'amenity': ['bank', 'atm']
		};
	  }
	  
	  if (categoryLower.contains('hospital')) {
		return {
		  'amenity': ['hospital', 'clinic'],
		  'healthcare': ['hospital', 'clinic', 'doctor']
		};
	  }
	  
	  if (categoryLower.contains('shop')) {
		return {
		  'shop': ['mall', 'department_store', 'clothes', 'shoes']
		};
	  }
	  
		if (categoryLower.contains('nightlife') || categoryLower.contains('bar')) {
		  return {
			'amenity': ['bar', 'pub', 'nightclub', 'biergarten', 'casino', 'stripclub', 'social_club'],
			'leisure': ['adult_gaming_centre', 'dance', 'bowling_alley', 'amusement_arcade'],
			'shop': ['alcohol', 'wine', 'beverages'],
			'tourism': ['attraction'], // For famous nightlife spots
			'building': ['commercial'], // Sometimes nightlife venues are tagged as commercial buildings
		  };
		}

		if (categoryLower.contains('museum') || categoryLower.contains('culture')) {
		  return {
			'tourism': ['museum'],
			'amenity': ['theatre', 'cinema']
		  };
		}

		if (categoryLower.contains('park') || categoryLower.contains('recreation')) {
		  return {
			'leisure': ['park', 'playground', 'garden'],
			'tourism': ['attraction']
		  };
		}

		if (categoryLower.contains('entertainment') || categoryLower.contains('cinema')) {
		  return {
			'amenity': ['cinema', 'theatre'],
			'leisure': ['bowling_alley', 'amusement_arcade']
		  };
		}

		if (categoryLower.contains('tourist') || categoryLower.contains('attraction')) {
		  return {
			'tourism': ['attraction', 'viewpoint', 'monument', 'artwork']
		  };
		}
		
		if (categoryLower.contains('kids') || categoryLower.contains('children') || categoryLower.contains('child')) {
		  return {
			'leisure': ['playground', 'water_park', 'amusement_arcade'],
			'tourism': ['zoo', 'theme_park'],
			'amenity': ['kindergarten'],
			'shop': ['toys']
		  };
		}
	  
	  // Default fallback
	  return {
		'amenity': ['restaurant', 'cafe']
	  };
	}

	/// Translate category to local language using AI
	Future<List<String>> _translateCategoryToLocal(String category, String countryCode) async {
	  try {
		final cacheKey = 'translation_${category}_$countryCode';
		final prefs = await SharedPreferences.getInstance();
		final cachedTranslation = prefs.getStringList(cacheKey);
		
		if (cachedTranslation != null && cachedTranslation.isNotEmpty) {
		  print('✅ TRANSLATION: Using cached translation for $category in $countryCode');
		  return cachedTranslation;
		}
		
		final prompt = '''Translate the business category "$category" into the local language of country code "$countryCode".

	Rules:
	1. Provide 3-5 most common local terms that people actually use
	2. Include both formal and informal/colloquial terms
	3. Include plural forms if different
	4. Only return terms that locals would search for

	Examples:
	- "pharmacy" in "DE" → "apotheke, pharmazie, medikamente"
	- "restaurant" in "IT" → "ristorante, trattoria, osteria, pizzeria"
	- "coffee" in "FR" → "cafe, cafeteria, salon de the"

	Country: $countryCode
	Category: $category

	Return ONLY comma-separated terms, no other text.''';

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
			'max_tokens': 100,
			'temperature': 0.2,
		  }),
		);

		if (response.statusCode == 200) {
		  final data = jsonDecode(response.body);
		  final content = data['choices'][0]['message']['content'].trim();
		  
		  // Parse terms with explicit type handling
		  final rawTerms = content.split(',');
		  final List<String> terms = <String>[];
		  
		  for (int i = 0; i < rawTerms.length; i++) {
			final String trimmed = rawTerms[i].toString().trim();
			if (trimmed.isNotEmpty && trimmed.length > 1) {
			  terms.add(trimmed);
			}
		  }
		  
		  // Ensure we have at least the original category
		  if (terms.isEmpty) {
			terms.add(category);
		  }
		  
		  // Cache translation for future use
		  try {
			await prefs.setStringList(cacheKey, terms);
		  } catch (cacheError) {
			print('⚠️ TRANSLATION: Cache save failed: $cacheError');
		  }
		  
		  print('✅ TRANSLATION: AI translated "$category" to local terms: $terms');
		  return terms;
		} else {
		  print('❌ TRANSLATION: API returned status ${response.statusCode}');
		}
		
	  } catch (e) {
		print('❌ TRANSLATION: Error translating category: $e');
		
		// Return fallback terms based on category
		final List<String> fallbackTerms = [category];
		
		// Add basic fallback translations for common categories
		final categoryLower = category.toLowerCase();
		if (categoryLower.contains('pharmacy') && countryCode == 'AT') {
		  fallbackTerms.addAll(['apotheke', 'pharmazie']);
		} else if (categoryLower.contains('restaurant') && countryCode == 'AT') {
		  fallbackTerms.addAll(['restaurant', 'gasthof']);
		} else if (categoryLower.contains('coffee') && countryCode == 'AT') {
		  fallbackTerms.addAll(['kaffeehaus', 'cafe']);
		} else if (categoryLower.contains('supermarket') && countryCode == 'AT') {
		  fallbackTerms.addAll(['supermarkt', 'spar', 'billa']);
		}
		
		return fallbackTerms;
	  }
	  
	  // Final fallback - return original category
	  return [category];
	}


	// Lista svih servera
	List<String> get _allServers => [
	  'https://overpass-api.de/api/interpreter',
	  'https://overpass.kumi.systems/api/interpreter', 
	  'https://overpass.openstreetmap.ru/api/interpreter',
	  'https://overpass.openstreetmap.fr/api/interpreter',
	  'https://z.overpass-api.de/api/interpreter',
	  'https://lz4.overpass-api.de/api/interpreter',
	  'https://maps.mail.ru/osm/tools/overpass/api/interpreter'
	];

	// Testira jedan server
	Future<ServerHealth> _testSingleServer(String serverUrl) async {
	  final stopwatch = Stopwatch()..start();
	  
	  try {
		// Pošalji minimalni test query
		const testQuery = '''
		[out:json][timeout:3];
		(
		  node["amenity"="restaurant"](around:100,48.2082,16.3738);
		);
		out center 1;
		''';

		final response = await http.post(
		  Uri.parse(serverUrl),
		  headers: {
			'Content-Type': 'application/x-www-form-urlencoded',
			'User-Agent': 'LocadoApp/1.0',
		  },
		  body: 'data=${Uri.encodeComponent(testQuery)}',
		).timeout(Duration(seconds: 3)); // Kratak timeout za test
		
		stopwatch.stop();
		
		if (response.statusCode == 200) {
		  print('✅ SERVER TEST: $serverUrl - ${stopwatch.elapsedMilliseconds}ms');
		  return ServerHealth(
			url: serverUrl,
			isAvailable: true,
			responseTimeMs: stopwatch.elapsedMilliseconds,
			checkedAt: DateTime.now(),
		  );
		} else {
		  print('❌ SERVER TEST: $serverUrl - Status ${response.statusCode}');
		  return ServerHealth(
			url: serverUrl,
			isAvailable: false,
			responseTimeMs: -1,
			checkedAt: DateTime.now(),
		  );
		}
	  } catch (e) {
		stopwatch.stop();
		print('❌ SERVER TEST: $serverUrl - Error: $e');
		return ServerHealth(
		  url: serverUrl,
		  isAvailable: false,
		  responseTimeMs: -1,
		  checkedAt: DateTime.now(),
		);
	  }
	}

	// Testira sve servere paralelno
	Future<List<String>> _getOptimalServerOrder() async {
	  print('🔍 HEALTH CHECK: Testing all servers...');
	  
	  // Testiraj sve servere paralelno
	  final futures = _allServers.map(_testSingleServer).toList();
	  
	  try {
		// Čekaj maximum 4 sekunde za sve testove
		final results = await Future.wait(futures).timeout(Duration(seconds: 4));
		
		// Sortiraj po brzini - dostupni serveri prvo
		final availableServers = results
			.where((health) => health.isAvailable)
			.toList()
		  ..sort((a, b) => a.responseTimeMs.compareTo(b.responseTimeMs));
		
		final serverOrder = availableServers.map((health) => health.url).toList();
		
		print('🚀 HEALTH CHECK: Optimal order: ${availableServers.map((s) => "${s.url.split('/')[2]} (${s.responseTimeMs}ms)").join(", ")}');
		
		return serverOrder;
		
	  } catch (e) {
		print('❌ HEALTH CHECK: Failed, using default order: $e');
		return _allServers; // Fallback na originalni redoslijed
	  }
	}

	/// Search using Overpass API directly with OSM tags and AI-translated local terms
	/// UPDATED METHOD: Search Overpass with image extraction
    /// UPDATED METHOD: Update calls to include location data
	Future<List<AILocationResult>> _searchOverpassDirect(
		String category, 
		List<String> localTerms,
		Map<String, List<String>> osmTags
	) async {
	  List<AILocationResult> results = [];
	  
	  if (_currentLatLng == null) return results;
	  
	  try {
		print('🚀 OPTIMIZED SEARCH: Starting for "$category"');
		
		// Get optimal server order
		final servers = await _getOptimalServerOrder();
		
		if (servers.isEmpty) {
		  print('❌ OVERPASS: No available servers found');
		  return results;
		}
		
		print('🏷️ OSM TAGS: $osmTags');
		print('🌐 LOCAL TERMS: $localTerms');
		
		// OPTIMIZED: Limit query complexity for better performance
		final queryParts = <String>[];
		
		// Add OSM tag searches (LIMIT TO MOST IMPORTANT TAGS)
		for (final tagType in osmTags.keys.take(3)) { // MAX 3 tag types
		  for (final tagValue in osmTags[tagType]!.take(2)) { // MAX 2 values per type
			if (tagValue == '*') {
			  queryParts.add('node["$tagType"](around:1500,${_currentLatLng!.latitude},${_currentLatLng!.longitude});');
			  queryParts.add('way["$tagType"](around:1500,${_currentLatLng!.latitude},${_currentLatLng!.longitude});');
			} else {
			  queryParts.add('node["$tagType"="$tagValue"](around:1500,${_currentLatLng!.latitude},${_currentLatLng!.longitude});');
			  queryParts.add('way["$tagType"="$tagValue"](around:1500,${_currentLatLng!.latitude},${_currentLatLng!.longitude});');
			}
		  }
		}

		// Add name searches with local terms (LIMIT TO TOP 2 TERMS)
		for (final localTerm in localTerms.take(2)) { // REDUCED FROM ALL TO 2
		  final terms = localTerm.contains(',') 
			  ? localTerm.split(',').map((t) => t.trim()).take(2).toList() // MAX 2 per term
			  : [localTerm];
			  
		  for (final term in terms) {
			final cleanTerm = term.replaceAll('"', '').replaceAll("'", '').trim();
			
			if (cleanTerm.isNotEmpty && cleanTerm.length > 2) {
			  queryParts.add('node["name"~"$cleanTerm",i](around:1500,${_currentLatLng!.latitude},${_currentLatLng!.longitude});');
			  queryParts.add('way["name"~"$cleanTerm",i](around:1500,${_currentLatLng!.latitude},${_currentLatLng!.longitude});');
			  
			  print('🌐 NAME SEARCH: Adding name search for "$cleanTerm"');
			}
		  }
		}
		
		// OPTIMIZED: Shorter timeout for urban search
		final overpassQuery = '''
	[out:json][timeout:12];
	(
	  ${queryParts.join('\n  ')}
	);
	out center meta;
	''';

		print('🔍 OVERPASS: Optimized query with 12s timeout');

		http.Response? response;
		String? usedServer;

		// Try servers in optimal order with EXTENDED TIMEOUT
		for (int i = 0; i < servers.length; i++) {
		  final serverUrl = servers[i];
		  print('🌐 TRYING OPTIMAL SERVER ${i + 1}/${servers.length}: $serverUrl');
		  
		  try {
			response = await http.post(
			  Uri.parse(serverUrl),
			  headers: {
				'Content-Type': 'application/x-www-form-urlencoded',
				'User-Agent': 'LocadoApp/1.0',
			  },
			  body: 'data=${Uri.encodeComponent(overpassQuery)}',
			).timeout(Duration(seconds: 15)); // INCREASED FROM 8 TO 15
			
			if (response.statusCode == 200) {
			  usedServer = serverUrl;
			  print('✅ SUCCESS with optimal server: $usedServer');
			  break;
			} else {
			  print('❌ Server returned status ${response.statusCode}, trying next...');
			  response = null;
			}
		  } catch (e) {
			print('❌ Server $serverUrl failed: $e, trying next...');
			response = null;
			continue;
		  }
		}

		if (response == null) {
		  print('❌ ALL SERVERS FAILED');
		  return results;
		}

		// Process results (existing logic remains the same)
		if (response.statusCode == 200) {
		  final data = jsonDecode(response.body);
		  final elements = data['elements'] as List;

		  print('🔍 OVERPASS: Found ${elements.length} raw results');

		  final Set<String> addedCoordinates = {};

		  for (final element in elements.take(50)) {
			final tags = element['tags'] as Map<String, dynamic>?;
			if (tags == null) continue;

			final name = tags['name'] ?? tags['brand'] ?? 'Unnamed ${category.toLowerCase()}';
			
			// Get coordinates
			double lat, lng;
			if (element['lat'] != null && element['lon'] != null) {
			  lat = element['lat'].toDouble();
			  lng = element['lon'].toDouble();
			} else if (element['center'] != null) {
			  lat = element['center']['lat'].toDouble();
			  lng = element['center']['lon'].toDouble();
			} else {
			  continue;
			}

			final coordKey = '${lat.toStringAsFixed(6)}_${lng.toStringAsFixed(6)}';
			if (addedCoordinates.contains(coordKey)) {
			  continue;
			}

			final distance = Geolocator.distanceBetween(
			  _currentLatLng!.latitude,
			  _currentLatLng!.longitude,
			  lat,
			  lng,
			);

			if (distance <= 1500) {
			  addedCoordinates.add(coordKey);
			  
			  // Generate task items from real OSM tags
			  final taskItems = await _generateTaskItemsFromOSMTags(name, tags, category);
			  
			  // Extract image URL from OSM tags with Google Places fallback
			  final imageUrl = await _extractImageFromOSMTags(tags, name, lat, lng);

			  results.add(AILocationResult(
				name: name,
				description: _getDescriptionFromOSMTags(tags, category),
				coordinates: UniversalLatLng(lat, lng),
				taskItems: taskItems,
				category: _getCategoryFromOSMTags(tags),
				distanceFromUser: distance,
				imageUrl: imageUrl,
			  ));
			  
			  if (imageUrl != null) {
				print('✅ OVERPASS: Added $name with image (${(distance / 1000).toStringAsFixed(2)}km)');
			  } else {
				print('✅ OVERPASS: Added $name (${(distance / 1000).toStringAsFixed(2)}km)');
			  }
			}
		  }
		}

		results.sort((a, b) => a.distanceFromUser!.compareTo(b.distanceFromUser!));

		print('✅ OVERPASS: Final results: ${results.length}');
		return results.take(25).toList();
		
	  } catch (e) {
		print('❌ OVERPASS: Error = $e');
		return results;
	  }
	}
	
	/// NEW METHOD: Enhanced rural search with Nominatim primary and Overpass fallback
	Future<List<AILocationResult>> _searchRuralWithNominatimPrimary(
		String category, 
		List<String> localTerms,
		Map<String, List<String>> osmTags,
		List<String> availableServers
	) async {
	  List<AILocationResult> results = [];
	  
	  if (_currentLatLng == null) return results;
	  
	  try {
		print('🌾 RURAL SEARCH: Starting with Nominatim primary for "$category"');
		
		// STEP 1: Try Nominatim first (primary method)
		print('🏥 RURAL SEARCH: Primary - Nominatim search');
		results = await _searchNominatimRural(category, localTerms);
		
		// STEP 2: If Nominatim found enough results, return them
		if (results.length >= 5) {
		  print('✅ RURAL SEARCH: Nominatim found ${results.length} results - using Nominatim results');
		  return results;
		}
		
		// STEP 3: If Nominatim didn't find enough, try Overpass as fallback
		print('🌾 RURAL SEARCH: Nominatim found only ${results.length} results, trying Overpass fallback');
		final overpassResults = await _searchOverpassRuralFallback(category, localTerms, osmTags, availableServers);
		
		// STEP 4: Compare results and use the better one
		if (overpassResults.length > results.length) {
		  print('✅ RURAL SEARCH: Overpass found more results (${overpassResults.length}), using Overpass results');
		  results = overpassResults;
		} else {
		  print('✅ RURAL SEARCH: Keeping Nominatim results (${results.length} vs ${overpassResults.length})');
		}
		
		// NEW STEP 5: If still no results, try expanded Nominatim search
		if (results.isEmpty) {
		  print('🏥 RURAL SEARCH: No results found, trying EXPANDED Nominatim fallback');
		  results = await _searchNominatimWithExpandedRadius(category, localTerms);
		  
		  if (results.isNotEmpty) {
			print('✅ RURAL SEARCH: Expanded Nominatim found ${results.length} distant results');
		  }
		}
		
		return results;
		
	  } catch (e) {
		print('❌ RURAL SEARCH: Error = $e');
		return results;
	  }
	}

	/// NEW METHOD: Overpass as fallback for rural search
	Future<List<AILocationResult>> _searchOverpassRuralFallback(
		String category, 
		List<String> localTerms,
		Map<String, List<String>> osmTags,
		List<String> availableServers
	) async {
	  List<AILocationResult> results = [];
	  
	  if (_currentLatLng == null) return results;
	  
	  try {
		print('🌾 OVERPASS FALLBACK: Starting progressive radius search for "$category"');
		
		// Progressive radius search with DYNAMIC TIMEOUTS
		final List<double> ruralRadiuses = [3000, 5000, 10000, 15000, 20000]; // in meters
		final List<double> ruralDistanceLimits = [3000, 5000, 10000, 15000, 20000]; // in meters
		final List<int> timeoutSeconds = [12, 15, 18, 22, 25]; // Progressive timeouts
		
		// Use provided servers (already tested)
		final servers = availableServers.isNotEmpty ? availableServers : _allServers;
		
		if (servers.isEmpty) {
		  print('❌ OVERPASS FALLBACK: No available servers');
		  return results;
		}
		
		// Try each radius until we find at least 5 results
		for (int radiusIndex = 0; radiusIndex < ruralRadiuses.length; radiusIndex++) {
		  final radiusMeters = ruralRadiuses[radiusIndex];
		  final distanceLimit = ruralDistanceLimits[radiusIndex];
		  final timeoutSec = timeoutSeconds[radiusIndex];
		  final radiusKm = radiusMeters / 1000;
		  
		  print('🌾 OVERPASS FALLBACK: Trying radius ${radiusKm}km with ${timeoutSec}s timeout');
		  
		  // OPTIMIZED: Build simplified query for rural search to avoid timeouts
		  final queryParts = <String>[];
		  
		  // Strategy 1: Only primary OSM tags (most reliable) - LIMIT TO 1 TAG TYPE
		  if (osmTags['amenity'] != null) {
			for (final tagValue in osmTags['amenity']!.take(1)) { // ONLY 1 most important tag
			  if (tagValue != '*') {
				queryParts.add('node["amenity"="$tagValue"](around:$radiusMeters,${_currentLatLng!.latitude},${_currentLatLng!.longitude});');
				queryParts.add('way["amenity"="$tagValue"](around:$radiusMeters,${_currentLatLng!.latitude},${_currentLatLng!.longitude});');
			  }
			}
		  }
		  
		  // Strategy 2: Add ONLY one primary local term search
		  if (localTerms.isNotEmpty) {
			final primaryTerm = localTerms[0].split(',')[0].trim(); // Get ONLY first term
			final cleanTerm = primaryTerm.replaceAll('"', '').replaceAll("'", '').trim();
			
			if (cleanTerm.isNotEmpty && cleanTerm.length > 2) {
			  queryParts.add('node["name"~"$cleanTerm",i](around:$radiusMeters,${_currentLatLng!.latitude},${_currentLatLng!.longitude});');
			  queryParts.add('way["name"~"$cleanTerm",i](around:$radiusMeters,${_currentLatLng!.latitude},${_currentLatLng!.longitude});');
			  print('🌾 OVERPASS FALLBACK: Using primary term "$cleanTerm" for ${radiusKm}km search');
			}
		  }
		  
		  final overpassQuery = '''
	[out:json][timeout:$timeoutSec];
	(
	  ${queryParts.join('\n  ')}
	);
	out center meta;
	''';

		  print('🌾 OVERPASS FALLBACK: Query for ${radiusKm}km radius with ${timeoutSec}s timeout');

		  http.Response? response;
		  String? usedServer;

		  // Try servers in optimal order with PROGRESSIVE TIMEOUT
		  for (int i = 0; i < servers.length; i++) {
			final serverUrl = servers[i];
			print('🌐 OVERPASS FALLBACK: Trying server ${i + 1}/${servers.length}: $serverUrl');
			
			try {
			  response = await http.post(
				Uri.parse(serverUrl),
				headers: {
				  'Content-Type': 'application/x-www-form-urlencoded',
				  'User-Agent': 'LocadoApp/1.0',
				},
				body: 'data=${Uri.encodeComponent(overpassQuery)}',
			  ).timeout(Duration(seconds: timeoutSec + 5)); // Server timeout + 5s buffer
			  
			  if (response.statusCode == 200) {
				usedServer = serverUrl;
				print('✅ OVERPASS FALLBACK: Success with server: $usedServer in ${timeoutSec}s');
				break;
			  } else {
				print('❌ OVERPASS FALLBACK: Server returned status ${response.statusCode}, trying next...');
				response = null;
			  }
			} catch (e) {
			  print('❌ OVERPASS FALLBACK: Server $serverUrl failed: $e, trying next...');
			  response = null;
			  continue;
			}
		  }

		  if (response == null) {
			print('❌ OVERPASS FALLBACK: All servers failed for radius ${radiusKm}km');
			continue; // Try next radius
		  }

		  // Process results for current radius (existing logic remains)
		  if (response.statusCode == 200) {
			final data = jsonDecode(response.body);
			final elements = data['elements'] as List;

			print('🌾 OVERPASS FALLBACK: Found ${elements.length} raw results for ${radiusKm}km radius');

			// Use Set to avoid duplicates by coordinates
			final Set<String> addedCoordinates = {};
			List<AILocationResult> currentRadiusResults = [];

			for (final element in elements.take(100)) { // Process more elements for rural search
			  final tags = element['tags'] as Map<String, dynamic>?;
			  if (tags == null) continue;

			  final name = tags['name'] ?? tags['brand'] ?? 'Unnamed ${category.toLowerCase()}';
			  
			  // Get coordinates
			  double lat, lng;
			  if (element['lat'] != null && element['lon'] != null) {
				lat = element['lat'].toDouble();
				lng = element['lon'].toDouble();
			  } else if (element['center'] != null) {
				lat = element['center']['lat'].toDouble();
				lng = element['center']['lon'].toDouble();
			  } else {
				continue;
			  }

			  // Create unique coordinate key to avoid duplicates
			  final coordKey = '${lat.toStringAsFixed(6)}_${lng.toStringAsFixed(6)}';
			  if (addedCoordinates.contains(coordKey)) {
				continue;
			  }

			  // Calculate distance from user
			  final distance = Geolocator.distanceBetween(
				_currentLatLng!.latitude,
				_currentLatLng!.longitude,
				lat,
				lng,
			  );

			  // Check if within current distance limit
			  if (distance <= distanceLimit) {
				addedCoordinates.add(coordKey);
				
				// Generate task items from real OSM tags
				final imageUrl = await _extractImageFromOSMTags(tags, name, lat, lng);
				final taskItems = await _generateTaskItemsFromOSMTags(name, tags, category);

				currentRadiusResults.add(AILocationResult(
				  name: name,
				  description: _getDescriptionFromOSMTags(tags, category),
				  coordinates: UniversalLatLng(lat, lng),
				  taskItems: taskItems,
				  category: _getCategoryFromOSMTags(tags),
				  distanceFromUser: distance,
				  imageUrl: imageUrl,
				));
				
				print('✅ OVERPASS FALLBACK: Added $name (${(distance/1000).toStringAsFixed(1)}km)');
			  }
			}
			
			// Sort current results by distance
			currentRadiusResults.sort((a, b) => a.distanceFromUser!.compareTo(b.distanceFromUser!));
			results = currentRadiusResults;
			
			print('🌾 OVERPASS FALLBACK: Radius ${radiusKm}km completed with ${results.length} results');
			
			// Check if we have enough results to stop
			if (results.length >= 3) { // REDUCED from 5 to 3 for faster results
			  print('✅ OVERPASS FALLBACK: Found ${results.length} results at ${radiusKm}km radius - stopping search');
			  break; // Stop expanding radius
			}
		  }
		}
		
		return results.take(25).toList();
		
	  } catch (e) {
		print('❌ OVERPASS FALLBACK: Error = $e');
		return results;
	  }
	}

	// 5. NOVI FALLBACK ZA NOMINATIM SA PROŠIRENIM RADIUSOM
	/// NEW METHOD: Expanded Nominatim search when Overpass fails completely
	Future<List<AILocationResult>> _searchNominatimWithExpandedRadius(
		String category, 
		List<String> localTerms
	) async {
	  List<AILocationResult> results = [];
	  
	  if (_currentLatLng == null) return results;
	  
	  try {
		print('🏥 NOMINATIM EXPANDED: Emergency fallback search for "$category"');
		
		// VERY LARGE radius search as last resort
		final List<double> expandedRadiuses = [0.3, 0.5, 1.0]; // 30km, 50km, 100km
		final List<double> expandedDistanceLimits = [30000, 50000, 100000]; // meters
		
		// Prepare search terms
		final searchTerms = <String>[category];
		searchTerms.addAll(localTerms.take(3)); // Only top 3 local terms
		
		// Remove duplicates
		final uniqueSearchTerms = searchTerms.toSet().toList();
		print('🏥 NOMINATIM EXPANDED: Search terms: $uniqueSearchTerms');
		
		// Try each expanded radius
		for (int radiusIndex = 0; radiusIndex < expandedRadiuses.length; radiusIndex++) {
		  final radiusDegrees = expandedRadiuses[radiusIndex];
		  final distanceLimit = expandedDistanceLimits[radiusIndex];
		  final radiusKm = distanceLimit / 1000;
		  
		  print('🏥 NOMINATIM EXPANDED: Trying LARGE radius ${radiusKm}km');
		  
		  List<AILocationResult> currentRadiusResults = [];
		  final Set<String> addedCoordinates = {};
		  
		  // Search with each term
		  for (final searchTerm in uniqueSearchTerms.take(3)) { // MAX 3 terms
			try {
			  final url = 'https://nominatim.openstreetmap.org/search'
				  '?q=${Uri.encodeComponent(searchTerm)}'
				  '&format=json'
				  '&addressdetails=1'
				  '&limit=30' // More results for expanded search
				  '&lat=${_currentLatLng!.latitude}'
				  '&lon=${_currentLatLng!.longitude}'
				  '&bounded=1'
				  '&viewbox=${_currentLatLng!.longitude - radiusDegrees},${_currentLatLng!.latitude + radiusDegrees},${_currentLatLng!.longitude + radiusDegrees},${_currentLatLng!.latitude - radiusDegrees}';

			  print('🏥 NOMINATIM EXPANDED: Searching "$searchTerm" in ${radiusKm}km radius');

			  final response = await http.get(
				Uri.parse(url),
				headers: {'User-Agent': 'LocadoApp/1.0'},
			  ).timeout(Duration(seconds: 12)); // Longer timeout for expanded search

			  if (response.statusCode == 200) {
				final List<dynamic> places = jsonDecode(response.body);
				
				for (final place in places.take(20)) { // Process up to 20 per term
				  final lat = double.parse(place['lat']);
				  final lng = double.parse(place['lon']);
				  final name = place['display_name'] ?? 'Unknown Place';
				  final type = place['type'] ?? 'location';
				  
				  final coordKey = '${lat.toStringAsFixed(6)}_${lng.toStringAsFixed(6)}';
				  if (addedCoordinates.contains(coordKey)) {
					continue;
				  }
				  
				  final distance = Geolocator.distanceBetween(
					_currentLatLng!.latitude,
					_currentLatLng!.longitude,
					lat,
					lng,
				  );

				  if (distance <= distanceLimit) {
					addedCoordinates.add(coordKey);
					
					final cleanName = _cleanDisplayName(name);
					final taskItems = await _generateTaskItemsFromType(cleanName, type);

					currentRadiusResults.add(AILocationResult(
					  name: cleanName,
					  description: 'Distant $type in wider area (${(distance/1000).toStringAsFixed(1)}km away)',
					  coordinates: UniversalLatLng(lat, lng),
					  taskItems: taskItems,
					  category: type,
					  distanceFromUser: distance,
					  imageUrl: null,
					));
					
					print('✅ NOMINATIM EXPANDED: Added $cleanName (${(distance/1000).toStringAsFixed(1)}km)');
				  }
				}
			  }
			  
			  // Delay between requests
			  await Future.delayed(Duration(milliseconds: 300));
			  
			} catch (e) {
			  print('❌ NOMINATIM EXPANDED: Error searching "$searchTerm": $e');
			  continue;
			}
		  }
		  
		  // Sort and update results
		  currentRadiusResults.sort((a, b) => a.distanceFromUser!.compareTo(b.distanceFromUser!));
		  results = currentRadiusResults;
		  
		  print('🏥 NOMINATIM EXPANDED: Radius ${radiusKm}km completed with ${results.length} results');
		  
		  // Stop if we found anything
		  if (results.length >= 1) {
			print('✅ NOMINATIM EXPANDED: Found ${results.length} results at ${radiusKm}km radius');
			break;
		  }
		}
		
		return results.take(15).toList(); // Return top 15 results
		
	  } catch (e) {
		print('❌ NOMINATIM EXPANDED: Error = $e');
		return results;
	  }
	}

	
    /// NEW METHOD: Rural search using Nominatim as fallback when Overpass fails
	Future<List<AILocationResult>> _searchNominatimRural(
		String category, 
		List<String> localTerms
	) async {
	  List<AILocationResult> results = [];
	  
	  if (_currentLatLng == null) return results;
	  
	  try {
		print('🏥 NOMINATIM RURAL: Starting fallback search for "$category"');
		
		// Progressive radius search: 3km → 5km → 10km → 15km → 20km
		final List<double> ruralRadiuses = [0.03, 0.05, 0.1, 0.15, 0.2]; // in decimal degrees (approx km)
		final List<double> ruralDistanceLimits = [3000, 5000, 10000, 15000, 20000]; // in meters
		
		// Prepare search terms
		final searchTerms = <String>[category]; // Start with English term
		
		// Add local terms
		for (final localTerm in localTerms) {
		  final terms = localTerm.contains(',') 
			  ? localTerm.split(',').map((t) => t.trim()).toList()
			  : [localTerm];
		  
		  for (final term in terms) {
			final cleanTerm = term.replaceAll('"', '').replaceAll("'", '').trim();
			if (cleanTerm.isNotEmpty && cleanTerm.length > 2) {
			  searchTerms.add(cleanTerm);
			}
		  }
		}
		
		// Remove duplicates
		final uniqueSearchTerms = searchTerms.toSet().toList();
		print('🏥 NOMINATIM RURAL: Search terms: $uniqueSearchTerms');
		
		// Try each radius until we find at least 5 results
		for (int radiusIndex = 0; radiusIndex < ruralRadiuses.length; radiusIndex++) {
		  final radiusDegrees = ruralRadiuses[radiusIndex];
		  final distanceLimit = ruralDistanceLimits[radiusIndex];
		  final radiusKm = distanceLimit / 1000;
		  
		  print('🏥 NOMINATIM RURAL: Trying radius ${radiusKm}km');
		  
		  List<AILocationResult> currentRadiusResults = [];
		  final Set<String> addedCoordinates = {};
		  
		  // Search with each term
		  for (final searchTerm in uniqueSearchTerms.take(5)) { // Limit to 5 terms to avoid too many requests
			try {
			  // Build Nominatim query with viewbox
			  final url = 'https://nominatim.openstreetmap.org/search'
				  '?q=${Uri.encodeComponent(searchTerm)}'
				  '&format=json'
				  '&addressdetails=1'
				  '&limit=20' // More results for rural search
				  '&lat=${_currentLatLng!.latitude}'
				  '&lon=${_currentLatLng!.longitude}'
				  '&bounded=1'
				  '&viewbox=${_currentLatLng!.longitude - radiusDegrees},${_currentLatLng!.latitude + radiusDegrees},${_currentLatLng!.longitude + radiusDegrees},${_currentLatLng!.latitude - radiusDegrees}';

			  print('🏥 NOMINATIM RURAL: Searching "$searchTerm" in ${radiusKm}km radius');

			  final response = await http.get(
				Uri.parse(url),
				headers: {'User-Agent': 'LocadoApp/1.0'},
			  ).timeout(Duration(seconds: 8));

			  if (response.statusCode == 200) {
				final List<dynamic> places = jsonDecode(response.body);
				
				for (final place in places.take(15)) { // Process up to 15 per term
				  final lat = double.parse(place['lat']);
				  final lng = double.parse(place['lon']);
				  final name = place['display_name'] ?? 'Unknown Place';
				  final type = place['type'] ?? 'location';
				  
				  // Create unique coordinate key to avoid duplicates
				  final coordKey = '${lat.toStringAsFixed(6)}_${lng.toStringAsFixed(6)}';
				  if (addedCoordinates.contains(coordKey)) {
					continue;
				  }
				  
				  // Calculate distance from user
				  final distance = Geolocator.distanceBetween(
					_currentLatLng!.latitude,
					_currentLatLng!.longitude,
					lat,
					lng,
				  );

				  // Check if within distance limit
				  if (distance <= distanceLimit) {
					addedCoordinates.add(coordKey);
					
					final cleanName = _cleanDisplayName(name);
					final taskItems = await _generateTaskItemsFromType(cleanName, type);

					currentRadiusResults.add(AILocationResult(
					  name: cleanName,
					  description: 'Local $type in the area (${(distance/1000).toStringAsFixed(1)}km away)',
					  coordinates: UniversalLatLng(lat, lng),
					  taskItems: taskItems,
					  category: type,
					  distanceFromUser: distance,
					  imageUrl: null,
					));
					
					print('✅ NOMINATIM RURAL: Added $cleanName (${(distance/1000).toStringAsFixed(1)}km)');
				  }
				}
			  } else {
				print('❌ NOMINATIM RURAL: HTTP ${response.statusCode} for term "$searchTerm"');
			  }
			  
			  // Small delay between requests to be respectful to Nominatim
			  await Future.delayed(Duration(milliseconds: 200));
			  
			} catch (e) {
			  print('❌ NOMINATIM RURAL: Error searching "$searchTerm": $e');
			  continue;
			}
		  }
		  
		  // Sort current results by distance
		  currentRadiusResults.sort((a, b) => a.distanceFromUser!.compareTo(b.distanceFromUser!));
		  results = currentRadiusResults;
		  
		  print('🏥 NOMINATIM RURAL: Radius ${radiusKm}km completed with ${results.length} results');
		  
		  // Check if we have enough results to stop
		  if (results.length >= 5) {
			print('✅ NOMINATIM RURAL: Found ${results.length} results at ${radiusKm}km radius - stopping search');
			break; // Stop expanding radius
		  }
		}
		
		if (results.length < 5) {
		  print('🏥 NOMINATIM RURAL: Completed all radii up to 20km, found ${results.length} results');
		} else {
		  print('✅ NOMINATIM RURAL: Successfully found ${results.length} results');
		}
		
		// Return up to 25 results (same as other search methods)
		return results.take(25).toList();
		
	  } catch (e) {
		print('❌ NOMINATIM RURAL: Error = $e');
		return results;
	  }
	}


	/// Generate task items from OSM tags
    /// UPDATED METHOD: Generate task items with Wikipedia info
	Future<List<String>> _generateTaskItemsFromOSMTags(
		String name, 
		Map<String, dynamic> tags,
		String category
	) async {
	  List<String> tasks = [];
	  
	  // Extract useful info from OSM tags
	  final openingHours = tags['opening_hours'] ?? '';
	  final phone = tags['phone'] ?? '';
	  final website = tags['website'] ?? '';
	  final wheelchairAccess = tags['wheelchair'] ?? '';
	  final brand = tags['brand'] ?? '';
	  final email = tags['email'] ?? '';
	  final wikipedia = tags['wikipedia'] ?? '';
	  
	  // Category-specific tasks
	  final categoryLower = category.toLowerCase();
	  
	  if (categoryLower.contains('pharmacy')) {
		tasks.add('Get prescription medications');
		tasks.add('Ask pharmacist for health advice');
		if (openingHours.isNotEmpty) {
		  tasks.add('Hours: $openingHours');
		} else {
		  tasks.add('Check opening hours before visiting');
		}
		tasks.add('Bring prescription and ID');
	  } else if (categoryLower.contains('restaurant') || categoryLower.contains('cafe')) {
		final cuisine = tags['cuisine'] ?? '';
		if (cuisine.isNotEmpty) {
		  tasks.add('Try their $cuisine specialties');
		} else {
		  tasks.add('Check menu and daily specials');
		}
		tasks.add('Make reservation if needed');
		if (openingHours.isNotEmpty) {
		  tasks.add('Hours: $openingHours');
		}
	  } else {
		// Generic tasks
		tasks.add('Visit and explore this location');
		if (openingHours.isNotEmpty) {
		  tasks.add('Hours: $openingHours');
		} else {
		  tasks.add('Check opening hours before visiting');
		}
	  }
	  
	  // Contact info
	  if (phone.isNotEmpty) {
		tasks.add('Call: $phone');
	  }
	  
	  if (email.isNotEmpty) {
		tasks.add('Email: $email');
	  }
	  
	  // Wikipedia info
	  if (wikipedia.isNotEmpty) {
		tasks.add('📚 Read more on Wikipedia');
	  }
	  
	  // Accessibility
	  if (wheelchairAccess == 'yes') {
		tasks.add('♿ Wheelchair accessible');
	  }
	  
	  // Brand info
	  if (brand.isNotEmpty && brand != name) {
		tasks.add('Brand: $brand');
	  }
	  
	  // Website info
	  if (website.isNotEmpty) {
		tasks.add('More info: ${_shortenUrl(website)}');
	  }
	  
	  return tasks.take(5).toList();
	}

	/// Get description from OSM tags
	String _getDescriptionFromOSMTags(Map<String, dynamic> tags, String category) {
	  final brand = tags['brand'] ?? '';
	  final cuisine = tags['cuisine'] ?? '';
	  final openingHours = tags['opening_hours'] ?? '';
	  
	  if (category.toLowerCase().contains('pharmacy')) {
		if (brand.isNotEmpty) {
		  return '$brand pharmacy with medications and health products';
		}
		return 'Local pharmacy for medications and health advice';
	  }
	  
	  if (category.toLowerCase().contains('restaurant')) {
		if (cuisine.isNotEmpty && brand.isNotEmpty) {
		  return '$brand restaurant serving $cuisine cuisine';
		} else if (cuisine.isNotEmpty) {
		  return 'Restaurant specializing in $cuisine cuisine';
		} else if (brand.isNotEmpty) {
		  return '$brand restaurant with quality food';
		}
		return 'Local restaurant with good food';
	  }
	  
	  return 'Local ${category.toLowerCase()} nearby';
	}

	/// Get category from OSM tags
	String _getCategoryFromOSMTags(Map<String, dynamic> tags) {
	  if (tags['amenity'] != null) {
		return tags['amenity'];
	  }
	  if (tags['shop'] != null) {
		return tags['shop'];
	  }
	  if (tags['healthcare'] != null) {
		return 'healthcare';
	  }
	  return 'location';
	}


	// ==================== END OPTIMIZED QUICK SEARCH METHODS ====================
	
	
	/// Open Google Maps with marker (app or web) - SIMPLE AND FREE
	Future<void> _openInGoogleMaps(AILocationResult result) async {
	  try {
		final lat = result.coordinates.latitude;
		final lng = result.coordinates.longitude;
		final locationName = Uri.encodeComponent(result.name);
		
		print('🗺️ FINAL: Opening Google Maps with marker for ${result.name}');
		
		// Try Google Maps app first
		final googleMapsAppUrl = 'comgooglemaps://?q=$locationName&center=$lat,$lng&zoom=18';
		
		if (await canLaunchUrl(Uri.parse(googleMapsAppUrl))) {
		  print('📱 FINAL: Opening Google Maps app with marker');
		  await launchUrl(
			Uri.parse(googleMapsAppUrl),
			mode: LaunchMode.externalApplication,
		  );
		  _showSnackBar('Opened ${result.name} in Google Maps. Tap marker for Street View!', Colors.green);
		  return;
		}
		
		// Fallback to web Google Maps with marker
		//final webMapsUrl = 'https://www.google.com/maps/search/$lat,$lng?query=$lat,$lng';
		final webMapsUrl = 'https://www.google.com/maps/search/${Uri.decodeComponent(locationName)}+$lat,$lng';
		
		
		print('🌐 FINAL: Opening Google Maps web with marker');
		await launchUrl(
		  Uri.parse(webMapsUrl),
		  mode: LaunchMode.externalApplication,
		);
		
		_showSnackBar('Opened ${result.name} in Maps. Tap marker for Street View!', Colors.green);
		
	  } catch (e) {
		print('❌ FINAL: Error opening Google Maps: $e');
		_showSnackBar('Could not open location in Maps', Colors.red);
	  }
	}

	/// Alternative method with more detailed URL schemes for different platforms
	Future<void> _openInGoogleMapsAdvanced(AILocationResult result) async {
	  try {
		final lat = result.coordinates.latitude;
		final lng = result.coordinates.longitude;
		final locationName = Uri.encodeComponent(result.name);
		
		print('🗺️ NAVIGATION ADVANCED: Opening ${result.name} at $lat,$lng');
		
		// Platform-specific URLs in order of preference
		final List<String> urlsToTry = [
		  // Google Maps app with place name and coordinates
		  'google.navigation:q=$lat,$lng&navigate=yes',
		  'google.navigation:q=$lat,$lng',
		  'comgooglemaps://?q=$lat,$lng&navigate=yes',
		  'comgooglemaps://?q=$lat,$lng',
		  
		  // Generic maps schemes
		  'maps:$lat,$lng',
		  'maps://maps.apple.com/?q=$lat,$lng',
		  
		  // Web fallback
		  'https://www.google.com/maps/search/?api=1&query=$lat,$lng',
		];
		
		// Try each URL until one works
		for (final url in urlsToTry) {
		  try {
			if (await canLaunchUrl(Uri.parse(url))) {
			  print('📱 NAVIGATION: Successfully opening with URL: $url');
			  await launchUrl(
				Uri.parse(url),
				mode: LaunchMode.externalApplication,
			  );
			  
			  _showSnackBar('Opened ${result.name} in Maps', Colors.green);
			  return;
			}
		  } catch (e) {
			print('⚠️ NAVIGATION: Failed URL $url: $e');
			continue;
		  }
		}
		
		// If all failed, show error
		throw Exception('No suitable maps application found');
		
	  } catch (e) {
		print('❌ NAVIGATION: Error opening maps: $e');
		_showSnackBar('Could not open location in Maps. Please install Google Maps app.', Colors.red);
	  }
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
	 
    /// UPDATED METHOD: Empty results section (extracted for better organization)
	Widget _buildEmptyResultsSection() {
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
			  'Try a different search query or expand the search area',
			  style: TextStyle(
				fontSize: 14,
				color: Colors.grey.shade500,
			  ),
			  textAlign: TextAlign.center,
			),
			const SizedBox(height: 20),

			ElevatedButton.icon(
			  onPressed: () {
				setState(() {
				  _hasSearched = false;
				  _searchResults.clear();
				  _searchController.clear();
				  _isEnhancing = false;
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


	  // Show hints when no search has been performed
	  if (!_hasSearched) {
		return _buildSearchHintsSection(); // Keep existing hints logic
	  }

	  // Show empty results
	  if (_searchResults.isEmpty) {
		return _buildEmptyResultsSection(); // Keep existing empty results logic
	  }

	  // Show results with enhancement indicator
	  return Column(
		children: [
		  // Header with selection info + enhancement indicator
		  Container(
			padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
			decoration: BoxDecoration(
			  color: Colors.white,
			  border: Border(
				bottom: BorderSide(color: Colors.grey.shade200),
			  ),
			),
			child: Column(
			  children: [
				// Main header row
				Row(
				  children: [
					// Back to hints button
					InkWell(
					  onTap: () {
						setState(() {
						  _hasSearched = false;
						  _searchResults.clear();
						  _searchController.clear();
						  _isEnhancing = false;
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

				// Enhancement indicator (show only when enhancing)
				if (_isEnhancing) ...[
				  const SizedBox(height: 8),
				  _buildEnhancementIndicator(),
				],
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
	
	/// NEW METHOD: Enhancement progress indicator
	Widget _buildEnhancementIndicator() {
	  return Container(
		padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
		decoration: BoxDecoration(
		  color: Colors.blue.shade50,
		  borderRadius: BorderRadius.circular(8),
		  border: Border.all(color: Colors.blue.shade200, width: 1),
		),
		child: Row(
		  children: [
			// Animated loading indicator
			SizedBox(
			  width: 16,
			  height: 16,
			  child: CircularProgressIndicator(
				strokeWidth: 2,
				color: Colors.blue.shade600,
			  ),
			),
			const SizedBox(width: 10),
			Expanded(
			  child: Column(
				crossAxisAlignment: CrossAxisAlignment.start,
				children: [
				  Text(
					'Enhancing with detailed data...',
					style: TextStyle(
					  fontSize: 12,
					  fontWeight: FontWeight.w600,
					  color: Colors.blue.shade700,
					),
				  ),
				  const SizedBox(height: 2),
				  Text(
					'Searching for opening hours, contact info, and more',
					style: TextStyle(
					  fontSize: 10,
					  color: Colors.blue.shade600,
					  height: 1.2,
					),
				  ),
				],
			  ),
			),
			// Enhancement icon
			Container(
			  padding: const EdgeInsets.all(4),
			  decoration: BoxDecoration(
				color: Colors.blue.shade100,
				borderRadius: BorderRadius.circular(4),
			  ),
			  child: Icon(
				Icons.auto_awesome,
				size: 14,
				color: Colors.blue.shade600,
			  ),
			),
		  ],
		),
	  );
	}

/// UPDATED METHOD: Search hints section (extracted for better organization)
	Widget _buildSearchHintsSection() {
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

				  // Progressive Enhancement info
				  Container(
					padding: const EdgeInsets.all(12),
					decoration: BoxDecoration(
					  color: Colors.purple.shade50,
					  borderRadius: BorderRadius.circular(8),
					  border: Border.all(color: Colors.purple.shade200, width: 1),
					),
					child: Row(
					  children: [
						Icon(Icons.speed, color: Colors.purple.shade600, size: 18),
						const SizedBox(width: 10),
						Expanded(
						  child: Column(
							crossAxisAlignment: CrossAxisAlignment.start,
							children: [
							  Text(
								'Smart Progressive Search',
								style: TextStyle(
								  fontWeight: FontWeight.bold,
								  color: Colors.purple.shade700,
								  fontSize: 12,
								),
							  ),
							  const SizedBox(height: 2),
							  Text(
								'Instant results + background enhancement for detailed info',
								style: TextStyle(
								  fontSize: 10,
								  color: Colors.purple.shade600,
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

				  // OpenStreetMap info (keep existing)
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

				  // Multilingual info (keep existing)
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

	/// UPDATED METHOD: Result card with image display and fixed click handling
	/// UPDATED METHOD: Result card with enhanced border and visual separation
	Widget _buildResultCard(AILocationResult result, int index) {
	  return Container(
		decoration: BoxDecoration(
		  color: Colors.white,
		  borderRadius: BorderRadius.circular(12),
		  boxShadow: [
			BoxShadow(
			  color: Colors.grey.shade200,
			  blurRadius: 6, // Increased from 4
			  offset: const Offset(0, 3), // Increased from 2
			  spreadRadius: 1, // Added spread for more prominent shadow
			),
		  ],
		  // ENHANCED BORDER SYSTEM
		  border: result.isSelected
			  ? Border.all(
				  color: Colors.green.shade400, 
				  width: 3, // Increased thickness for selected
				)
			  : Border.all(
				  color: Colors.grey.shade300, 
				  width: 2, // Prominent border for all cards
				),
		),
		child: Material(
		  color: Colors.transparent,
		  child: Column(
			crossAxisAlignment: CrossAxisAlignment.start,
			children: [
			  // Image section with border integration
			  Builder(
				builder: (context) {
				  try {
					print('🔍 CONDITION CHECK: ${result.name} - imageUrl: "${result.imageUrl}" - isNull: ${result.imageUrl == null}');
					
					Widget imageWidget;
					if (result.imageUrl != null) {
					  print('🖼️ BUILDING: Real image for ${result.name}');
					  imageWidget = _buildLocationImageWithBorder(result);
					} else {
					  print('🎨 BUILDING: Placeholder for ${result.name}');
					  imageWidget = _buildLocationPlaceholderWithBorder(result);
					}
					
					return GestureDetector(
					  onTap: () => _openInGoogleMaps(result),
					  child: imageWidget,
					);
					
				  } catch (e, stackTrace) {
					print('❌ ERROR building image for ${result.name}: $e');
					print('❌ STACK TRACE: $stackTrace');
					return Container(
					  height: 160,
					  decoration: BoxDecoration(
						color: Colors.red.shade100,
						borderRadius: const BorderRadius.only(
						  topLeft: Radius.circular(10), // Slightly smaller to fit within border
						  topRight: Radius.circular(10),
						),
						border: Border.all(color: Colors.red, width: 2),
					  ),
					  child: Center(
						child: Column(
						  mainAxisAlignment: MainAxisAlignment.center,
						  children: [
							Icon(Icons.error_outline, color: Colors.red, size: 32),
							SizedBox(height: 8),
							Text('ERROR', style: TextStyle(color: Colors.red, fontWeight: FontWeight.bold)),
						  ],
						),
					  ),
					);
				  }
				},
			  ),
			  
			  // Content section with enhanced padding and visual separation
			  InkWell(
				borderRadius: const BorderRadius.only(
				  bottomLeft: Radius.circular(10), // Adjusted to match container border radius
				  bottomRight: Radius.circular(10),
				),
				onTap: () {
				  setState(() {
					result.isSelected = !result.isSelected;
				  });
				},
				child: Container(
				  // VISUAL SEPARATOR between image and content
				  decoration: BoxDecoration(
					border: Border(
					  top: BorderSide(
						color: Colors.grey.shade200, 
						width: 1,
					  ),
					),
				  ),
				  child: Padding(
					padding: const EdgeInsets.all(14), // Increased padding from 12
					child: Column(
					  crossAxisAlignment: CrossAxisAlignment.start,
					  children: [
						// Header with checkbox - ENHANCED STYLING
						Row(
						  children: [
							Container(
							  width: 22, // Slightly larger
							  height: 22,
							  decoration: BoxDecoration(
								color: result.isSelected ? Colors.green.shade400 : Colors.transparent,
								border: Border.all(
								  color: result.isSelected ? Colors.green.shade400 : Colors.grey.shade400,
								  width: 2.5, // Thicker border
								),
								borderRadius: BorderRadius.circular(5), // Slightly more rounded
								// ADD SUBTLE SHADOW to checkbox
								boxShadow: result.isSelected ? [
								  BoxShadow(
									color: Colors.green.shade200,
									blurRadius: 3,
									offset: Offset(0, 1),
								  ),
								] : null,
							  ),
							  child: result.isSelected
								  ? const Icon(Icons.check, color: Colors.white, size: 16)
								  : null,
							),
							const SizedBox(width: 12), // Increased spacing
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
										  padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3), // Slightly larger
										  decoration: BoxDecoration(
											color: Colors.blue.shade50,
											borderRadius: BorderRadius.circular(10), // More rounded
											border: Border.all(color: Colors.blue.shade200, width: 1.5), // Thicker border
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
								  const SizedBox(height: 3), // Increased spacing
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
							// Category and image indicator - ENHANCED STYLING
							Column(
							  children: [
								Container(
								  padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3), // Slightly larger
								  decoration: BoxDecoration(
									color: Colors.teal.shade50,
									borderRadius: BorderRadius.circular(10), // More rounded
									border: Border.all(color: Colors.teal.shade200, width: 1.5), // Added border
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
								if (result.imageUrl != null) ...[
								  const SizedBox(height: 6), // Increased spacing
								  Container(
									padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 3), // Slightly larger
									decoration: BoxDecoration(
									  color: Colors.green.shade50,
									  borderRadius: BorderRadius.circular(8), // More rounded
									  border: Border.all(color: Colors.green.shade200, width: 1.5), // Added border
									),
									child: Row(
									  mainAxisSize: MainAxisSize.min,
									  children: [
										Icon(
										  Icons.photo_camera,
										  size: 9, // Slightly larger
										  color: Colors.green.shade600,
										),
										const SizedBox(width: 3),
										Text(
										  'PHOTO',
										  style: TextStyle(
											fontSize: 7, // Slightly larger
											fontWeight: FontWeight.bold,
											color: Colors.green.shade600,
										  ),
										),
									  ],
									),
								  ),
								],
							  ],
							),
						  ],
						),

						// Task items with enhanced styling
						if (result.taskItems.isNotEmpty) ...[
						  const SizedBox(height: 12), // Increased spacing
						  // ENHANCED: Add subtle background for task section
						  Container(
							padding: const EdgeInsets.all(10),
							decoration: BoxDecoration(
							  color: Colors.grey.shade50, // Very subtle background
							  borderRadius: BorderRadius.circular(8),
							  border: Border.all(color: Colors.grey.shade100, width: 1),
							),
							child: Column(
							  crossAxisAlignment: CrossAxisAlignment.start,
							  children: [
								Text(
								  'Things to do:',
								  style: TextStyle(
									fontSize: 12,
									fontWeight: FontWeight.bold,
									color: Colors.grey.shade700,
								  ),
								),
								const SizedBox(height: 8),
								...result.taskItems.take(3).map((item) => Padding(
								  padding: const EdgeInsets.only(bottom: 4), // Increased spacing
								  child: Row(
									crossAxisAlignment: CrossAxisAlignment.start,
									children: [
									  Container(
										width: 5, // Slightly larger bullet
										height: 5,
										margin: const EdgeInsets.only(top: 7), // Adjusted for better alignment
										decoration: BoxDecoration(
										  color: Colors.teal.shade400,
										  shape: BoxShape.circle,
										),
									  ),
									  const SizedBox(width: 10), // Increased spacing
									  Expanded(
										child: Text(
										  item,
										  style: TextStyle(
											fontSize: 11,
											color: Colors.grey.shade700,
											height: 1.3, // Improved line height
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
									padding: const EdgeInsets.only(top: 6), // Increased spacing
									child: Text(
									  '+${result.taskItems.length - 3} more items',
									  style: TextStyle(
										fontSize: 10,
										color: Colors.teal.shade600,
										fontStyle: FontStyle.italic,
										fontWeight: FontWeight.w500, // Slightly bolder
									  ),
									),
								  ),
							  ],
							),
						  ),
						],
					  ],
					),
				  ),
				),
			  ),
			],
		  ),
		),
	  );
	}
	
	Widget _buildLocationPlaceholderWithBorder(AILocationResult result) {
	  return ClipRRect(
		borderRadius: const BorderRadius.only(
		  topLeft: Radius.circular(10), // Fits within card border
		  topRight: Radius.circular(10),
		),
		child: Container(
		  height: 160,
		  width: double.infinity,
		  decoration: BoxDecoration(
			gradient: LinearGradient(
			  begin: Alignment.topLeft,
			  end: Alignment.bottomRight,
			  colors: [
				_getCategoryColor(result.category).withOpacity(0.15), // Slightly more opaque
				_getCategoryColor(result.category).withOpacity(0.35),
			  ],
			),
			// ADD SUBTLE INNER BORDER to placeholder
			border: Border.all(
			  color: _getCategoryColor(result.category).withOpacity(0.3),
			  width: 1,
			),
		  ),
		  child: Stack(
			children: [
			  // Main content
			  Center(
				child: Column(
				  mainAxisAlignment: MainAxisAlignment.center,
				  children: [
					// Enhanced category icon container
					Container(
					  padding: const EdgeInsets.all(18), // Slightly larger
					  decoration: BoxDecoration(
						color: _getCategoryColor(result.category).withOpacity(0.25), // More opaque
						borderRadius: BorderRadius.circular(22), // More rounded
						border: Border.all(
						  color: _getCategoryColor(result.category).withOpacity(0.4),
						  width: 2,
						),
						boxShadow: [
						  BoxShadow(
							color: _getCategoryColor(result.category).withOpacity(0.2),
							blurRadius: 8,
							offset: Offset(0, 3),
						  ),
						],
					  ),
					  child: Icon(
						_getCategoryIcon(result.category),
						size: 42, // Slightly larger
						color: _getCategoryColor(result.category),
					  ),
					),
					const SizedBox(height: 14), // Increased spacing
					// Enhanced category text container
					Container(
					  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7), // Larger padding
					  decoration: BoxDecoration(
						color: Colors.white.withOpacity(0.95), // More opaque
						borderRadius: BorderRadius.circular(10), // More rounded
						border: Border.all(
						  color: _getCategoryColor(result.category).withOpacity(0.3),
						  width: 1.5,
						),
						boxShadow: [
						  BoxShadow(
							color: Colors.black.withOpacity(0.1),
							blurRadius: 4,
							offset: Offset(0, 2),
						  ),
						],
					  ),
					  child: Text(
						result.category.replaceAll('_', ' ').toUpperCase(),
						style: TextStyle(
						  fontSize: 13, // Slightly larger
						  fontWeight: FontWeight.bold,
						  color: _getCategoryColor(result.category),
						),
					  ),
					),
				  ],
				),
			  ),
			  
			  // Enhanced click hint overlay
			  Positioned(
				top: 10,
				right: 10,
				child: Container(
				  padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5), // Larger padding
				  decoration: BoxDecoration(
					color: Colors.black.withOpacity(0.75), // More opaque
					borderRadius: BorderRadius.circular(10), // More rounded
					border: Border.all(color: Colors.white.withOpacity(0.3), width: 1),
				  ),
				  child: Row(
					mainAxisSize: MainAxisSize.min,
					children: [
					  Icon(
						Icons.map,
						size: 13, // Slightly larger
						color: Colors.white,
					  ),
					  const SizedBox(width: 5),
					  Text(
						'TAP TO OPEN',
						style: TextStyle(
						  fontSize: 9, // Slightly larger
						  color: Colors.white,
						  fontWeight: FontWeight.bold,
						),
					  ),
					],
				  ),
				),
			  ),
			  
			  // Enhanced selection overlay
			  if (result.isSelected)
				Positioned.fill(
				  child: Container(
					decoration: BoxDecoration(
					  color: Colors.green.withOpacity(0.25),
					  border: Border.all(color: Colors.green.shade400, width: 3),
					  borderRadius: const BorderRadius.only(
						topLeft: Radius.circular(10),
						topRight: Radius.circular(10),
					  ),
					),
					child: Center(
					  child: Container(
						padding: const EdgeInsets.all(8),
						decoration: BoxDecoration(
						  color: Colors.green.shade400,
						  borderRadius: BorderRadius.circular(25),
						  boxShadow: [
							BoxShadow(
							  color: Colors.green.shade200,
							  blurRadius: 6,
							  offset: Offset(0, 2),
							),
						  ],
						),
						child: const Icon(
						  Icons.check_circle,
						  color: Colors.white,
						  size: 24,
						),
					  ),
					),
				  ),
				),
			],
		  ),
		),
	  );
	}
	
	Widget _buildLocationImageWithBorder(AILocationResult result) {
	  return ClipRRect(
		borderRadius: const BorderRadius.only(
		  topLeft: Radius.circular(10), // Slightly smaller to fit within card border
		  topRight: Radius.circular(10),
		),
		child: Container(
		  height: 160,
		  width: double.infinity,
		  decoration: BoxDecoration(
			color: Colors.grey.shade200,
		  ),
		  child: Stack(
			children: [
			  // Main image
			  Positioned.fill(
				child: Image.network(
				  result.imageUrl!,
				  fit: BoxFit.cover,
				  headers: {
					'Cache-Control': 'max-age=86400',
				  },
				  loadingBuilder: (context, child, loadingProgress) {
					if (loadingProgress == null) {
					  return child;
					}
					return _buildImageLoadingPlaceholder(
					  loadingProgress.expectedTotalBytes != null
						  ? loadingProgress.cumulativeBytesLoaded / loadingProgress.expectedTotalBytes!
						  : null,
					);
				  },
				  errorBuilder: (context, error, stackTrace) {
					print('🖼️ IMAGE ERROR: Failed to load ${result.imageUrl}');
					
					if (result.imageUrl!.contains('maps.googleapis.com/maps/api/streetview')) {
					  return _buildStreetViewErrorPlaceholder(result);
					}
					
					return _buildImageErrorPlaceholder(result);
				  },
				  frameBuilder: (context, child, frame, wasSynchronouslyLoaded) {
					if (wasSynchronouslyLoaded) {
					  return child;
					}
					
					if (frame != null) {
					  WidgetsBinding.instance.addPostFrameCallback((_) {
						print('🖼️ IMAGE SUCCESS: Loaded ${result.name} image');
					  });
					}
					
					return AnimatedOpacity(
					  opacity: frame == null ? 0 : 1,
					  duration: const Duration(milliseconds: 300),
					  curve: Curves.easeOut,
					  child: child,
					);
				  },
				),
			  ),
			  
			  // Enhanced gradient overlay
			  Positioned.fill(
				child: Container(
				  decoration: BoxDecoration(
					gradient: LinearGradient(
					  begin: Alignment.topCenter,
					  end: Alignment.bottomCenter,
					  colors: [
						Colors.transparent,
						Colors.black.withOpacity(0.4), // Slightly stronger gradient
					  ],
					),
				  ),
				),
			  ),
			  
			  // Enhanced image source indicator
			  Positioned(
				top: 10, // Adjusted for card border
				right: 10,
				child: Container(
				  padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 4), // Slightly larger
				  decoration: BoxDecoration(
					color: Colors.black.withOpacity(0.7), // Slightly more opaque
					borderRadius: BorderRadius.circular(10), // More rounded
					border: Border.all(color: Colors.white.withOpacity(0.3), width: 1), // Added subtle border
				  ),
				  child: Row(
					mainAxisSize: MainAxisSize.min,
					children: [
					  Icon(
						_getImageSourceIcon(result.imageUrl!),
						size: 11, // Slightly larger
						color: Colors.white,
					  ),
					  const SizedBox(width: 4),
					  Text(
						_getImageSourceText(result.imageUrl!),
						style: const TextStyle(
						  fontSize: 9, // Slightly larger
						  color: Colors.white,
						  fontWeight: FontWeight.bold,
						),
					  ),
					],
				  ),
				),
			  ),
			  
			  // Enhanced selection overlay
			  if (result.isSelected)
				Positioned.fill(
				  child: Container(
					decoration: BoxDecoration(
					  color: Colors.green.withOpacity(0.25), // Slightly more opaque
					  border: Border.all(color: Colors.green.shade400, width: 3), // Thicker inner border
					  borderRadius: const BorderRadius.only(
						topLeft: Radius.circular(10),
						topRight: Radius.circular(10),
					  ),
					),
					child: Center(
					  child: Container(
						padding: const EdgeInsets.all(8),
						decoration: BoxDecoration(
						  color: Colors.green.shade400,
						  borderRadius: BorderRadius.circular(25),
						  boxShadow: [
							BoxShadow(
							  color: Colors.green.shade200,
							  blurRadius: 6,
							  offset: Offset(0, 2),
							),
						  ],
						),
						child: const Icon(
						  Icons.check_circle,
						  color: Colors.white,
						  size: 24,
						),
					  ),
					),
				  ),
				),
			],
		  ),
		),
	  );
	}
	
	/// NEW METHOD: Build location placeholder for results without images
	Widget _buildLocationPlaceholder(AILocationResult result) {
	  return ClipRRect(
		borderRadius: const BorderRadius.only(
		  topLeft: Radius.circular(12),
		  topRight: Radius.circular(12),
		),
		child: Container(
		  height: 160,
		  width: double.infinity,
		  decoration: BoxDecoration(
			gradient: LinearGradient(
			  begin: Alignment.topLeft,
			  end: Alignment.bottomRight,
			  colors: [
				_getCategoryColor(result.category).withOpacity(0.1),
				_getCategoryColor(result.category).withOpacity(0.3),
			  ],
			),
		  ),
		  child: Stack(
			children: [
			  // Main content
			  Center(
				child: Column(
				  mainAxisAlignment: MainAxisAlignment.center,
				  children: [
					// Category icon
					Container(
					  padding: const EdgeInsets.all(16),
					  decoration: BoxDecoration(
						color: _getCategoryColor(result.category).withOpacity(0.2),
						borderRadius: BorderRadius.circular(20),
					  ),
					  child: Icon(
						_getCategoryIcon(result.category),
						size: 40,
						color: _getCategoryColor(result.category),
					  ),
					),
					const SizedBox(height: 12),
					// Category text
					Container(
					  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
					  decoration: BoxDecoration(
						color: Colors.white.withOpacity(0.9),
						borderRadius: BorderRadius.circular(8),
					  ),
					  child: Text(
						result.category.replaceAll('_', ' ').toUpperCase(),
						style: TextStyle(
						  fontSize: 12,
						  fontWeight: FontWeight.bold,
						  color: _getCategoryColor(result.category),
						),
					  ),
					),
				  ],
				),
			  ),
			  
			  // Click hint overlay
			  Positioned(
				top: 8,
				right: 8,
				child: Container(
				  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
				  decoration: BoxDecoration(
					color: Colors.black.withOpacity(0.7),
					borderRadius: BorderRadius.circular(8),
				  ),
				  child: Row(
					mainAxisSize: MainAxisSize.min,
					children: [
					  Icon(
						Icons.map,
						size: 12,
						color: Colors.white,
					  ),
					  const SizedBox(width: 4),
					  Text(
						'TAP TO OPEN',
						style: TextStyle(
						  fontSize: 8,
						  color: Colors.white,
						  fontWeight: FontWeight.bold,
						),
					  ),
					],
				  ),
				),
			  ),
			  
			  // Selection overlay
			  if (result.isSelected)
				Positioned.fill(
				  child: Container(
					decoration: BoxDecoration(
					  color: Colors.green.withOpacity(0.2),
					  border: Border.all(color: Colors.green, width: 2),
					),
					child: const Center(
					  child: Icon(
						Icons.check_circle,
						color: Colors.green,
						size: 40,
					  ),
					),
				  ),
				),
			],
		  ),
		),
	  );
	}	
	
	/// NEW METHOD: Get color for category
	Color _getCategoryColor(String category) {
	  final categoryLower = category.toLowerCase();
	  
	  if (categoryLower.contains('restaurant') || categoryLower.contains('food')) {
		return Colors.orange;
	  } else if (categoryLower.contains('cafe') || categoryLower.contains('coffee')) {
		return Colors.brown;
	  } else if (categoryLower.contains('bar') || categoryLower.contains('pub') || categoryLower.contains('nightlife')) {
		return Colors.purple;
	  } else if (categoryLower.contains('nightclub') || categoryLower.contains('club')) {
		return Colors.deepPurple;
	  } else if (categoryLower.contains('museum') || categoryLower.contains('gallery')) {
		return Colors.indigo;
	  } else if (categoryLower.contains('pharmacy')) {
		return Colors.green;
	  } else if (categoryLower.contains('hospital') || categoryLower.contains('clinic')) {
		return Colors.red;
	  } else if (categoryLower.contains('bank') || categoryLower.contains('atm')) {
		return Colors.blue;
	  } else if (categoryLower.contains('fuel') || categoryLower.contains('gas')) {
		return Colors.amber;
	  } else if (categoryLower.contains('shop') || categoryLower.contains('store')) {
		return Colors.teal;
	  } else if (categoryLower.contains('theatre') || categoryLower.contains('cinema')) {
		return Colors.pink;
	  } else if (categoryLower.contains('tourism') || categoryLower.contains('attraction')) {
		return Colors.cyan;
	  } else {
		return Colors.blueGrey;
	  }
	}

	/// NEW METHOD: Build location image widget
	/// UPDATED METHOD: Build location image widget with improved loading
	Widget _buildLocationImage(AILocationResult result) {
	  return ClipRRect(
		borderRadius: const BorderRadius.only(
		  topLeft: Radius.circular(12),
		  topRight: Radius.circular(12),
		),
		child: Container(
		  height: 160,
		  width: double.infinity,
		  decoration: BoxDecoration(
			color: Colors.grey.shade200,
		  ),
		  child: Stack(
			children: [
			  // Main image with click handler  
			  Positioned.fill(
				child: GestureDetector(
				  onTap: () {
					if (result.imageUrl != null && 
						result.imageUrl!.contains('maps.googleapis.com/maps/api/streetview')) {
					  _openStreetViewPanorama(result);
					} else {
					  _showSnackBar('360° view available only for Street View images', Colors.orange);
					}
				  },
				  child: Image.network(
					result.imageUrl!,
					fit: BoxFit.cover,
					// IMPROVED: Add cache headers and error recovery
					headers: {
					  'Cache-Control': 'max-age=86400', // Cache for 24 hours
					},
					loadingBuilder: (context, child, loadingProgress) {
					  if (loadingProgress == null) {
						return child;
					  }
					  return _buildImageLoadingPlaceholder(
						loadingProgress.expectedTotalBytes != null
							? loadingProgress.cumulativeBytesLoaded / loadingProgress.expectedTotalBytes!
							: null,
					  );
					},
					errorBuilder: (context, error, stackTrace) {
					  // IMPROVED: More detailed error logging
					  print('🖼️ IMAGE ERROR: Failed to load ${result.imageUrl}');
					  print('🖼️ IMAGE ERROR: Error = $error');
					  
					  // Try to detect if it's a Street View URL and show specific fallback
					  if (result.imageUrl!.contains('maps.googleapis.com/maps/api/streetview')) {
						print('🏠 STREET VIEW ERROR: URL failed to load, showing fallback');
						return _buildStreetViewErrorPlaceholder(result);
					  }
					  
					  return _buildImageErrorPlaceholder(result);
					},
					// IMPROVED: Add frame callback to debug loading
					frameBuilder: (context, child, frame, wasSynchronouslyLoaded) {
					  if (wasSynchronouslyLoaded) {
						return child;
					  }
					  
					  // Log successful image loading
					  if (frame != null) {
						WidgetsBinding.instance.addPostFrameCallback((_) {
						  print('🖼️ IMAGE SUCCESS: Loaded ${result.name} image');
						});
					  }
					  
					  return AnimatedOpacity(
						opacity: frame == null ? 0 : 1,
						duration: const Duration(milliseconds: 300),
						curve: Curves.easeOut,
						child: child,
					  );
					},
				  ),
				),
			  ),
			  
			  // Gradient overlay for better text readability
			  Positioned.fill(
				child: Container(
				  decoration: BoxDecoration(
					gradient: LinearGradient(
					  begin: Alignment.topCenter,
					  end: Alignment.bottomCenter,
					  colors: [
						Colors.transparent,
						Colors.black.withOpacity(0.3),
					  ],
					),
				  ),
				),
			  ),
			  
			  // Image source indicator
			  Positioned(
				top: 8,
				right: 8,
				child: Container(
				  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
				  decoration: BoxDecoration(
					color: Colors.black.withOpacity(0.6),
					borderRadius: BorderRadius.circular(8),
				  ),
				  child: Row(
					mainAxisSize: MainAxisSize.min,
					children: [
					  Icon(
						_getImageSourceIcon(result.imageUrl!),
						size: 10,
						color: Colors.white,
					  ),
					  const SizedBox(width: 3),
					  Text(
						_getImageSourceText(result.imageUrl!),
						style: const TextStyle(
						  fontSize: 8,
						  color: Colors.white,
						  fontWeight: FontWeight.bold,
						),
					  ),
					],
				  ),
				),
			  ),
			  
			  // Selection overlay
			  if (result.isSelected)
				Positioned.fill(
				  child: Container(
					decoration: BoxDecoration(
					  color: Colors.green.withOpacity(0.2),
					  border: Border.all(color: Colors.green, width: 2),
					),
					child: const Center(
					  child: Icon(
						Icons.check_circle,
						color: Colors.green,
						size: 40,
					  ),
					),
				  ),
				),
			],
		  ),
		),
	  );
	}

	/// NEW METHOD: Image loading placeholder
	/// UPDATED METHOD: Image loading placeholder with progress
	Widget _buildImageLoadingPlaceholder([double? progress]) {
	  return Container(
		color: Colors.grey.shade200,
		child: Center(
		  child: Column(
			mainAxisAlignment: MainAxisAlignment.center,
			children: [
			  SizedBox(
				width: 32,
				height: 32,
				child: CircularProgressIndicator(
				  strokeWidth: 3,
				  color: Colors.grey.shade400,
				  value: progress, // Show actual progress if available
				),
			  ),
			  const SizedBox(height: 12),
			  Text(
				progress != null 
					? 'Loading ${(progress * 100).round()}%'
					: 'Loading image...',
				style: TextStyle(
				  fontSize: 11,
				  color: Colors.grey.shade500,
				  fontWeight: FontWeight.w500,
				),
			  ),
			  if (progress != null && progress > 0.5) ...[
				const SizedBox(height: 4),
				Text(
				  'Almost ready...',
				  style: TextStyle(
					fontSize: 9,
					color: Colors.grey.shade400,
				  ),
				),
			  ],
			],
		  ),
		),
	  );
	}
	
	/// NEW METHOD: Street View specific error placeholder
	Widget _buildStreetViewErrorPlaceholder(AILocationResult result) {
	  return Container(
		color: Colors.blue.shade50,
		child: Center(
		  child: Column(
			mainAxisAlignment: MainAxisAlignment.center,
			children: [
			  Icon(
				Icons.streetview,
				size: 32,
				color: Colors.blue.shade300,
			  ),
			  const SizedBox(height: 8),
			  Text(
				'STREET VIEW',
				style: TextStyle(
				  fontSize: 10,
				  fontWeight: FontWeight.bold,
				  color: Colors.blue.shade600,
				),
			  ),
			  const SizedBox(height: 4),
			  Text(
				'Image temporarily unavailable',
				style: TextStyle(
				  fontSize: 9,
				  color: Colors.blue.shade400,
				),
				textAlign: TextAlign.center,
			  ),
			  const SizedBox(height: 8),
			  Container(
				padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
				decoration: BoxDecoration(
				  color: Colors.blue.shade100,
				  borderRadius: BorderRadius.circular(6),
				),
				child: Text(
				  result.category.replaceAll('_', ' ').toUpperCase(),
				  style: TextStyle(
					fontSize: 8,
					fontWeight: FontWeight.bold,
					color: Colors.blue.shade700,
				  ),
				),
			  ),
			],
		  ),
		),
	  );
	}

	/// NEW METHOD: Image error placeholder
	Widget _buildImageErrorPlaceholder(AILocationResult result) {
	  return Container(
		color: Colors.grey.shade100,
		child: Center(
		  child: Column(
			mainAxisAlignment: MainAxisAlignment.center,
			children: [
			  Icon(
				_getCategoryIcon(result.category),
				size: 32,
				color: Colors.grey.shade400,
			  ),
			  const SizedBox(height: 8),
			  Text(
				result.category.replaceAll('_', ' ').toUpperCase(),
				style: TextStyle(
				  fontSize: 10,
				  fontWeight: FontWeight.bold,
				  color: Colors.grey.shade500,
				),
			  ),
			  const SizedBox(height: 4),
			  Text(
				'Image unavailable',
				style: TextStyle(
				  fontSize: 9,
				  color: Colors.grey.shade400,
				),
			  ),
			],
		  ),
		),
	  );
	}

	/// NEW METHOD: Get category icon for fallback
	IconData _getCategoryIcon(String category) {
	  final categoryLower = category.toLowerCase();
	  
	  if (categoryLower.contains('restaurant') || categoryLower.contains('food')) {
		return Icons.restaurant;
	  } else if (categoryLower.contains('cafe') || categoryLower.contains('coffee')) {
		return Icons.local_cafe;
	  } else if (categoryLower.contains('museum') || categoryLower.contains('gallery')) {
		return Icons.museum;
	  } else if (categoryLower.contains('pharmacy')) {
		return Icons.local_pharmacy;
	  } else if (categoryLower.contains('hospital') || categoryLower.contains('clinic')) {
		return Icons.local_hospital;
	  } else if (categoryLower.contains('bank') || categoryLower.contains('atm')) {
		return Icons.account_balance;
	  } else if (categoryLower.contains('fuel') || categoryLower.contains('gas')) {
		return Icons.local_gas_station;
	  } else if (categoryLower.contains('shop') || categoryLower.contains('store')) {
		return Icons.shopping_bag;
	  } else if (categoryLower.contains('theatre') || categoryLower.contains('cinema')) {
		return Icons.movie;
	  } else if (categoryLower.contains('tourism') || categoryLower.contains('attraction')) {
		return Icons.place;
	  } else {
		return Icons.location_on;
	  }
	}

	/// NEW METHOD: Get image source icon
	/// UPDATED METHOD: Get image source icon (ENHANCED)
	IconData _getImageSourceIcon(String imageUrl) {
	  if (imageUrl.contains('maps.googleapis.com/maps/api/streetview')) {
		return Icons.streetview; // New icon for Street View
	  } else if (imageUrl.contains('googleapis.com')) {
		return Icons.business;
	  } else if (imageUrl.contains('wikimedia') || imageUrl.contains('wikipedia')) {
		return Icons.article;
	  } else if (imageUrl.contains('commons.wikimedia.org')) {
		return Icons.public;
	  } else {
		return Icons.photo;
	  }
	}

	/// NEW METHOD: Get image source text
	/// UPDATED METHOD: Get image source text (ENHANCED)
	String _getImageSourceText(String imageUrl) {
	  if (imageUrl.contains('maps.googleapis.com/maps/api/streetview')) {
		return 'STREET VIEW'; // New text for Street View
	  } else if (imageUrl.contains('googleapis.com')) {
		return 'GOOGLE';
	  } else if (imageUrl.contains('wikimedia') || imageUrl.contains('wikipedia')) {
		return 'WIKI';
	  } else if (imageUrl.contains('commons.wikimedia.org')) {
		return 'COMMONS';
	  } else {
		return 'PHOTO';
	  }
	}
	
	/// NEW METHOD: Open Street View with hybrid approach (OpenStreetView + Google fallback)
	void _openStreetViewPanorama(AILocationResult result) {
	  // Check if location has coordinates
	  if (result.coordinates == null) {
		_showSnackBar('Location coordinates not available', Colors.orange);
		return;
	  }

	  print('🌍 HYBRID PANORAMA: Starting for ${result.name} at ${result.coordinates.latitude}, ${result.coordinates.longitude}');

	  // First try OpenStreetView (free)
	  _tryOpenStreetView(result);
	}

	/// NEW METHOD: Try OpenStreetView first (free option)
	Future<void> _tryOpenStreetView(AILocationResult result) async {
	  try {
		print('🆓 OPENSTREETVIEW: Checking coverage for ${result.name}');
		
		// Show loading dialog
		showDialog(
		  context: context,
		  barrierDismissible: false,
		  builder: (context) => AlertDialog(
			content: Column(
			  mainAxisSize: MainAxisSize.min,
			  children: [
				CircularProgressIndicator(color: Colors.green),
				SizedBox(height: 16),
				Text('Checking for free 360° images...'),
			  ],
			),
		  ),
		);

		// Check OpenStreetView API for nearby photos
		final openStreetViewData = await _checkOpenStreetViewCoverage(
		  result.coordinates.latitude, 
		  result.coordinates.longitude
		);

		// Close loading dialog
		Navigator.of(context).pop();

		if (openStreetViewData != null && openStreetViewData.isNotEmpty) {
		  print('✅ OPENSTREETVIEW: Found ${openStreetViewData.length} photos, opening free viewer');
		  
		  // Open OpenStreetView panorama
		  Navigator.of(context).push(
			MaterialPageRoute(
			  builder: (context) => OpenStreetViewPanoramaScreen(
				locationName: result.name,
				latitude: result.coordinates.latitude,
				longitude: result.coordinates.longitude,
				category: result.category,
				photos: openStreetViewData,
			  ),
			  fullscreenDialog: true,
			),
		  );
		} else {
		  print('❌ OPENSTREETVIEW: No coverage, offering Google Street View fallback');
		  _showGoogleStreetViewOption(result);
		}

	  } catch (e) {
		// Close loading dialog if still open
		Navigator.of(context).pop();
		print('❌ OPENSTREETVIEW: Error checking coverage: $e');
		_showGoogleStreetViewOption(result);
	  }
	}

	/// NEW METHOD: Check OpenStreetView API for photo coverage
	Future<List<OpenStreetViewPhoto>?> _checkOpenStreetViewCoverage(double lat, double lng) async {
	  try {
		final url = 'https://api.openstreetview.org/1.0/list/nearby-photos/'
			'?lat=$lat'
			'&lng=$lng'
			'&radius=150' // 150 meters radius
			'&ipp=10'; // Items per page

		print('🆓 OPENSTREETVIEW API: $url');

		final response = await http.get(
		  Uri.parse(url),
		  headers: {
			'User-Agent': 'LocadoApp/1.0',
			'Accept': 'application/json',
		  },
		).timeout(Duration(seconds: 8));

		if (response.statusCode == 200) {
		  final data = jsonDecode(response.body);
		  
		  if (data['result'] != null && data['result']['data'] != null) {
			final List<dynamic> photos = data['result']['data'];
			
			print('🆓 OPENSTREETVIEW: Found ${photos.length} photos in API response');
			
			if (photos.isNotEmpty) {
			  // Convert to OpenStreetViewPhoto objects
			  return photos.map((photo) => OpenStreetViewPhoto.fromJson(photo)).toList();
			}
		  }
		} else {
		  print('❌ OPENSTREETVIEW API: HTTP ${response.statusCode}');
		}

		return null;
	  } catch (e) {
		print('❌ OPENSTREETVIEW API: Error = $e');
		return null;
	  }
	}

	/// NEW METHOD: Show Google Street View option with cost warning
	void _showGoogleStreetViewOption(AILocationResult result) {
	  showDialog(
		context: context,
		builder: (context) => AlertDialog(
		  title: Row(
			children: [
			  Icon(Icons.streetview, color: Colors.blue),
			  SizedBox(width: 8),
			  Text('360° Street View'),
			],
		  ),
		  content: Column(
			mainAxisSize: MainAxisSize.min,
			crossAxisAlignment: CrossAxisAlignment.start,
			children: [
			  Text(
				'Free 360° images not available for this location.',
				style: TextStyle(fontWeight: FontWeight.w500),
			  ),
			  SizedBox(height: 12),
			  Container(
				padding: EdgeInsets.all(12),
				decoration: BoxDecoration(
				  color: Colors.blue.shade50,
				  borderRadius: BorderRadius.circular(8),
				  border: Border.all(color: Colors.blue.shade200),
				),
				child: Column(
				  crossAxisAlignment: CrossAxisAlignment.start,
				  children: [
					Row(
					  children: [
						Icon(Icons.info_outline, size: 16, color: Colors.blue.shade700),
						SizedBox(width: 6),
						Text(
						  'Google Street View Available',
						  style: TextStyle(
							fontWeight: FontWeight.bold,
							color: Colors.blue.shade700,
							fontSize: 13,
						  ),
						),
					  ],
					),
					SizedBox(height: 6),
					Text(
					  '• Interactive 360° panorama\n• High-quality imagery\n• Small usage cost applies',
					  style: TextStyle(
						fontSize: 12,
						color: Colors.blue.shade600,
					  ),
					),
				  ],
				),
			  ),
			],
		  ),
		  actions: [
			TextButton(
			  onPressed: () => Navigator.of(context).pop(),
			  child: Text('Cancel'),
			),
			ElevatedButton.icon(
			  onPressed: () {
				Navigator.of(context).pop();
				_openGoogleStreetView(result);
			  },
			  icon: Icon(Icons.streetview, size: 18),
			  label: Text('Open Google Street View'),
			  style: ElevatedButton.styleFrom(
				backgroundColor: Colors.blue,
				foregroundColor: Colors.white,
			  ),
			),
		  ],
		),
	  );
	}

	/// NEW METHOD: Open Google Street View (with cost)
	void _openGoogleStreetView(AILocationResult result) {
	  final googleApiKey = dotenv.env['GOOGLE_API_KEY'] ?? dotenv.env['GOOGLE_PLACES_API_KEY'] ?? '';
	  
	  if (googleApiKey.isEmpty || googleApiKey == 'your_api_key_here') {
		_showSnackBar('Google API key not configured for Street View', Colors.red);
		return;
	  }

	  print('💰 GOOGLE STREET VIEW: Opening paid panorama for ${result.name}');

	  Navigator.of(context).push(
		MaterialPageRoute(
		  builder: (context) => GoogleStreetViewPanoramaScreen(
			locationName: result.name,
			latitude: result.coordinates.latitude,
			longitude: result.coordinates.longitude,
			category: result.category,
			apiKey: googleApiKey,
		  ),
		  fullscreenDialog: true,
		),
	  );
	}
}

	/// NEW CLASS: OpenStreetView photo data model
	class OpenStreetViewPhoto {
	  final String id;
	  final double latitude;
	  final double longitude;
	  final String? imageUrl;
	  final String? thumbnailUrl;
	  final DateTime? dateCreated;
	  final double? heading;

	  OpenStreetViewPhoto({
		required this.id,
		required this.latitude,
		required this.longitude,
		this.imageUrl,
		this.thumbnailUrl,
		this.dateCreated,
		this.heading,
	  });

	  factory OpenStreetViewPhoto.fromJson(Map<String, dynamic> json) {
		return OpenStreetViewPhoto(
		  id: json['id']?.toString() ?? '',
		  latitude: (json['lat'] ?? json['latitude'] ?? 0.0).toDouble(),
		  longitude: (json['lng'] ?? json['longitude'] ?? 0.0).toDouble(),
		  imageUrl: json['lth_name'] ?? json['image_url'],
		  thumbnailUrl: json['th_name'] ?? json['thumbnail_url'],
		  dateCreated: json['date_added'] != null ? 
			  DateTime.tryParse(json['date_added'].toString()) : null,
		  heading: (json['heading'] ?? 0.0).toDouble(),
		);
	  }
	}

	/// NEW SCREEN: OpenStreetView panorama viewer (free)
	class OpenStreetViewPanoramaScreen extends StatefulWidget {
	  final String locationName;
	  final double latitude;
	  final double longitude;
	  final String category;
	  final List<OpenStreetViewPhoto> photos;

	  const OpenStreetViewPanoramaScreen({
		Key? key,
		required this.locationName,
		required this.latitude,
		required this.longitude,
		required this.category,
		required this.photos,
	  }) : super(key: key);

	  @override
	  State<OpenStreetViewPanoramaScreen> createState() => _OpenStreetViewPanoramaScreenState();
	}

	class _OpenStreetViewPanoramaScreenState extends State<OpenStreetViewPanoramaScreen> {
	  int _currentPhotoIndex = 0;
	  bool _isLoading = true;

	  @override
	  Widget build(BuildContext context) {
		final currentPhoto = widget.photos[_currentPhotoIndex];
		
		return Scaffold(
		  backgroundColor: Colors.black,
		  extendBodyBehindAppBar: true,
		  appBar: AppBar(
			backgroundColor: Colors.transparent,
			elevation: 0,
			leading: Container(
			  margin: const EdgeInsets.all(8),
			  decoration: BoxDecoration(
				color: Colors.black.withOpacity(0.8),
				borderRadius: BorderRadius.circular(8),
			  ),
			  child: IconButton(
				icon: const Icon(Icons.close, color: Colors.white),
				onPressed: () => Navigator.of(context).pop(),
			  ),
			),
			title: Container(
			  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
			  decoration: BoxDecoration(
				color: Colors.green.withOpacity(0.9),
				borderRadius: BorderRadius.circular(16),
			  ),
			  child: Row(
				mainAxisSize: MainAxisSize.min,
				children: [
				  Icon(Icons.eco, size: 16, color: Colors.white),
				  SizedBox(width: 6),
				  Text(
					'FREE',
					style: TextStyle(
					  fontSize: 12,
					  fontWeight: FontWeight.bold,
					  color: Colors.white,
					),
				  ),
				],
			  ),
			),
			centerTitle: true,
		  ),
		  body: Stack(
			children: [
			  // Main photo viewer
			  PageView.builder(
				itemCount: widget.photos.length,
				onPageChanged: (index) {
				  setState(() {
					_currentPhotoIndex = index;
					_isLoading = true;
				  });
				},
				itemBuilder: (context, index) {
				  final photo = widget.photos[index];
				  return Container(
					width: double.infinity,
					height: double.infinity,
					child: Image.network(
					  photo.imageUrl ?? photo.thumbnailUrl ?? '',
					  fit: BoxFit.cover,
					  loadingBuilder: (context, child, loadingProgress) {
						if (loadingProgress == null) {
						  WidgetsBinding.instance.addPostFrameCallback((_) {
							if (mounted) {
							  setState(() {
								_isLoading = false;
							  });
							}
						  });
						  return child;
						}
						return Center(
						  child: CircularProgressIndicator(
							color: Colors.white,
							value: loadingProgress.expectedTotalBytes != null
								? loadingProgress.cumulativeBytesLoaded / loadingProgress.expectedTotalBytes!
								: null,
						  ),
						);
					  },
					  errorBuilder: (context, error, stackTrace) {
						return Center(
						  child: Column(
							mainAxisAlignment: MainAxisAlignment.center,
							children: [
							  Icon(Icons.error_outline, color: Colors.white, size: 48),
							  SizedBox(height: 16),
							  Text(
								'Failed to load image',
								style: TextStyle(color: Colors.white),
							  ),
							],
						  ),
						);
					  },
					),
				  );
				},
			  ),
			  
			  // Loading overlay
			  if (_isLoading)
				Container(
				  color: Colors.black.withOpacity(0.7),
				  child: Center(
					child: Column(
					  mainAxisAlignment: MainAxisAlignment.center,
					  children: [
						CircularProgressIndicator(color: Colors.white),
						SizedBox(height: 16),
						Text(
						  'Loading street view...',
						  style: TextStyle(color: Colors.white),
						),
					  ],
					),
				  ),
				),
			  
			  // Info overlay
			  Positioned(
				top: 100,
				left: 20,
				right: 20,
				child: Container(
				  padding: EdgeInsets.all(16),
				  decoration: BoxDecoration(
					color: Colors.black.withOpacity(0.8),
					borderRadius: BorderRadius.circular(12),
					border: Border.all(color: Colors.green.withOpacity(0.3)),
				  ),
				  child: Column(
					crossAxisAlignment: CrossAxisAlignment.start,
					children: [
					  Text(
						widget.locationName,
						style: TextStyle(
						  color: Colors.white,
						  fontSize: 18,
						  fontWeight: FontWeight.bold,
						),
					  ),
					  SizedBox(height: 4),
					  Text(
						'${widget.category.replaceAll('_', ' ').toUpperCase()} • OpenStreetView',
						style: TextStyle(
						  color: Colors.white70,
						  fontSize: 12,
						),
					  ),
					],
				  ),
				),
			  ),
			  
			  // Photo navigation
			  if (widget.photos.length > 1)
				Positioned(
				  bottom: 30,
				  left: 20,
				  right: 20,
				  child: Container(
					padding: EdgeInsets.all(12),
					decoration: BoxDecoration(
					  color: Colors.black.withOpacity(0.8),
					  borderRadius: BorderRadius.circular(8),
					),
					child: Row(
					  mainAxisAlignment: MainAxisAlignment.spaceBetween,
					  children: [
						Text(
						  'Photo ${_currentPhotoIndex + 1} of ${widget.photos.length}',
						  style: TextStyle(color: Colors.white, fontSize: 14),
						),
						Row(
						  children: [
							IconButton(
							  onPressed: _currentPhotoIndex > 0 ? () {
								setState(() {
								  _currentPhotoIndex--;
								});
							  } : null,
							  icon: Icon(Icons.arrow_back_ios, color: Colors.white),
							),
							IconButton(
							  onPressed: _currentPhotoIndex < widget.photos.length - 1 ? () {
								setState(() {
								  _currentPhotoIndex++;
								});
							  } : null,
							  icon: Icon(Icons.arrow_forward_ios, color: Colors.white),
							),
						  ],
						),
					  ],
					),
				  ),
				),
			],
		  ),
		);
	  }
	}

	/// EXISTING SCREEN: Google Street View panorama (renamed for clarity)
	class GoogleStreetViewPanoramaScreen extends StatefulWidget {
	  final String locationName;
	  final double latitude;
	  final double longitude;
	  final String category;
	  final String apiKey;

	  const GoogleStreetViewPanoramaScreen({
		Key? key,
		required this.locationName,
		required this.latitude,
		required this.longitude,
		required this.category,
		required this.apiKey,
	  }) : super(key: key);

	  @override
	  State<GoogleStreetViewPanoramaScreen> createState() => _GoogleStreetViewPanoramaScreenState();
	}

	class _GoogleStreetViewPanoramaScreenState extends State<GoogleStreetViewPanoramaScreen> {
	  late WebViewController _webViewController;
	  bool _isLoading = true;
	  bool _hasError = false;
	  String? _errorMessage;

	  @override
	  void initState() {
		super.initState();
		_initializeWebView();
	  }

	  void _initializeWebView() {
		final streetViewHtml = _buildStreetViewPanoramaHtml();
		
		_webViewController = WebViewController()
		  ..setJavaScriptMode(JavaScriptMode.unrestricted)
		  ..setBackgroundColor(Colors.black)
		  ..setNavigationDelegate(
			NavigationDelegate(
			  onPageStarted: (String url) {
				setState(() {
				  _isLoading = true;
				  _hasError = false;
				});
			  },
			  onPageFinished: (String url) {
				setState(() {
				  _isLoading = false;
				});
				print('💰 GOOGLE STREET VIEW: Panorama loaded for ${widget.locationName}');
			  },
			  onWebResourceError: (WebResourceError error) {
				setState(() {
				  _isLoading = false;
				  _hasError = true;
				  _errorMessage = error.description;
				});
				print('❌ GOOGLE STREET VIEW: Error loading: ${error.description}');
			  },
			),
		  )
		  ..loadHtmlString(streetViewHtml);
	  }

	  String _buildStreetViewPanoramaHtml() {
		return '''
	<!DOCTYPE html>
	<html>
	<head>
		<meta charset="utf-8">
		<meta name="viewport" content="width=device-width, initial-scale=1.0, user-scalable=no">
		<title>Google Street View - ${widget.locationName}</title>
		<style>
			* { margin: 0; padding: 0; box-sizing: border-box; }
			html, body { height: 100%; font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif; background: #000; overflow: hidden; }
			#map { height: 100vh; width: 100vw; }
			.info-overlay { position: absolute; top: 20px; left: 20px; right: 20px; background: rgba(0, 0, 0, 0.8); color: white; padding: 12px 16px; border-radius: 12px; backdrop-filter: blur(10px); z-index: 1000; pointer-events: none; }
			.paid-badge { position: absolute; top: 20px; right: 20px; background: rgba(255, 152, 0, 0.9); color: white; padding: 6px 12px; border-radius: 16px; font-size: 12px; font-weight: bold; z-index: 1001; }
			.location-name { font-size: 18px; font-weight: bold; margin-bottom: 4px; }
			.location-details { font-size: 14px; opacity: 0.8; }
			.controls-overlay { position: absolute; bottom: 20px; right: 20px; background: rgba(0, 0, 0, 0.8); color: white; padding: 8px 12px; border-radius: 8px; font-size: 12px; z-index: 1000; pointer-events: none; }
			.loading-overlay { position: absolute; top: 0; left: 0; right: 0; bottom: 0; background: #000; display: flex; align-items: center; justify-content: center; z-index: 2000; color: white; flex-direction: column; }
			.spinner { width: 40px; height: 40px; border: 3px solid rgba(255, 255, 255, 0.3); border-radius: 50%; border-top-color: #fff; animation: spin 1s ease-in-out infinite; margin-bottom: 16px; }
			@keyframes spin { to { transform: rotate(360deg); } }
		</style>
	</head>
	<body>
		<div id="loading" class="loading-overlay">
			<div class="spinner"></div>
			<div>Loading Google Street View...</div>
		</div>
		
		<div class="paid-badge">💰 PAID</div>
		
		<div class="info-overlay">
			<div class="location-name">${widget.locationName}</div>
			<div class="location-details">
				${widget.category.replaceAll('_', ' ').toUpperCase()} • Google Street View
			</div>
		</div>
		
		<div class="controls-overlay">
			Drag to look around • Pinch to zoom
		</div>
		
		<div id="map"></div>

		<script async defer src="https://maps.googleapis.com/maps/api/js?key=${widget.apiKey}&callback=initStreetView"></script>
		
		<script>
			let panorama;
			let isLoaded = false;
			
			function initStreetView() {
				console.log('💰 Initializing Google Street View panorama...');
				
				const mapDiv = document.getElementById('map');
				const loadingDiv = document.getElementById('loading');
				
				try {
					const streetViewService = new google.maps.StreetViewService();
					const location = { lat: ${widget.latitude}, lng: ${widget.longitude} };
					
					streetViewService.getPanorama({
						location: location,
						radius: 100,
						preference: google.maps.StreetViewPreference.NEAREST
					}, function(data, status) {
						if (status === 'OK') {
							console.log('✅ Google Street View panorama found');
							
							panorama = new google.maps.StreetViewPanorama(mapDiv, {
								position: location,
								pov: { heading: 235, pitch: 10 },
								zoom: 1,
								addressControl: false,
								linksControl: true,
								panControl: true,
								enableCloseButton: false,
								showRoadLabels: false,
								motionTracking: false,
								motionTrackingControl: false
							});
							
							google.maps.event.addListener(panorama, 'pano_changed', function() {
								if (!isLoaded) {
									loadingDiv.style.display = 'none';
									isLoaded = true;
									console.log('💰 Google Street View panorama loaded successfully');
								}
							});
							
							google.maps.event.addListener(panorama, 'error', function(error) {
								console.error('❌ Google Street View error:', error);
								showError('Street View not available at this location');
							});
							
						} else {
							console.warn('⚠️ Google Street View not available:', status);
							showError('Street View not available at this location');
						}
					});
					
				} catch (error) {
					console.error('❌ Google Street View initialization error:', error);
					showError('Failed to load Street View');
				}
			}
			
			function showError(message) {
				const loadingDiv = document.getElementById('loading');
				loadingDiv.innerHTML = '<div style="color: #ff6b6b; text-align: center;">' + 
									 '<div style="font-size: 18px; margin-bottom: 8px;">⚠️</div>' +
									 '<div>' + message + '</div>' +
									 '<div style="margin-top: 12px; font-size: 12px; opacity: 0.7;">Tap back to return</div>' +
									 '</div>';
			}
			
			document.addEventListener('contextmenu', e => e.preventDefault());
			document.addEventListener('selectstart', e => e.preventDefault());
			
			window.addEventListener('orientationchange', function() {
				if (panorama) {
					google.maps.event.trigger(panorama, 'resize');
				}
			});
		</script>
	</body>
	</html>
		''';
	  }

	  @override
	  Widget build(BuildContext context) {
		return Scaffold(
		  backgroundColor: Colors.black,
		  extendBodyBehindAppBar: true,
		  appBar: AppBar(
			backgroundColor: Colors.transparent,
			elevation: 0,
			leading: Container(
			  margin: const EdgeInsets.all(8),
			  decoration: BoxDecoration(
				color: Colors.black.withOpacity(0.8),
				borderRadius: BorderRadius.circular(8),
			  ),
			  child: IconButton(
				icon: const Icon(Icons.close, color: Colors.white),
				onPressed: () => Navigator.of(context).pop(),
			  ),
			),
			title: Container(
			  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
			  decoration: BoxDecoration(
				color: Colors.orange.withOpacity(0.9),
				borderRadius: BorderRadius.circular(16),
			  ),
			  child: Row(
				mainAxisSize: MainAxisSize.min,
				children: [
				  Icon(Icons.monetization_on, size: 16, color: Colors.white),
				  SizedBox(width: 6),
				  Text(
					'PAID',
					style: TextStyle(
					  fontSize: 12,
					  fontWeight: FontWeight.bold,
					  color: Colors.white,
					),
				  ),
				],
			  ),
			),
			centerTitle: true,
			actions: [
			  Container(
				margin: const EdgeInsets.all(8),
				decoration: BoxDecoration(
				  color: Colors.black.withOpacity(0.8),
				  borderRadius: BorderRadius.circular(8),
				),
				child: IconButton(
				  icon: const Icon(Icons.refresh, color: Colors.white),
				  onPressed: () {
					setState(() {
					  _isLoading = true;
					  _hasError = false;
					});
					_initializeWebView();
				  },
				),
			  ),
			],
		  ),
		  body: Stack(
			children: [
			  if (!_hasError)
				WebViewWidget(controller: _webViewController),
			  
			  if (_hasError)
				Container(
				  color: Colors.black,
				  child: Center(
					child: Column(
					  mainAxisAlignment: MainAxisAlignment.center,
					  children: [
						const Icon(Icons.error_outline, color: Colors.red, size: 64),
						const SizedBox(height: 16),
						const Text('Street View Error', style: TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold)),
						const SizedBox(height: 8),
						Text(_errorMessage ?? 'Failed to load Street View panorama', style: const TextStyle(color: Colors.white70, fontSize: 14), textAlign: TextAlign.center),
						const SizedBox(height: 24),
						ElevatedButton.icon(
						  onPressed: () {
							setState(() {
							  _isLoading = true;
							  _hasError = false;
							});
							_initializeWebView();
						  },
						  icon: const Icon(Icons.refresh),
						  label: const Text('Try Again'),
						  style: ElevatedButton.styleFrom(backgroundColor: Colors.blue, foregroundColor: Colors.white),
						),
					  ],
					),
				  ),
				),
			  
			  if (_isLoading && !_hasError)
				Container(
				  color: Colors.black,
				  child: const Center(
					child: Column(
					  mainAxisAlignment: MainAxisAlignment.center,
					  children: [
						CircularProgressIndicator(color: Colors.white, strokeWidth: 3),
						SizedBox(height: 16),
						Text('Loading Google Street View...', style: TextStyle(color: Colors.white, fontSize: 16)),
					  ],
					),
				  ),
				),
			],
		  ),
		);
	  }
	}
