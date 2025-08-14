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
		  'query': 'nightlife bars nearby',
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
	  if (lowerQuery.contains('coffee') || lowerQuery.contains('espresso')) {
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
	  }
	  
	  // Add Overpass results, merging or replacing where appropriate
	  for (final overpassResult in overpassResults) {
		final key = '${overpassResult.coordinates.latitude.toStringAsFixed(5)}_${overpassResult.coordinates.longitude.toStringAsFixed(5)}';
		
		if (combinedMap.containsKey(key)) {
		  // Merge data - prefer Overpass for detailed information
		  final existing = combinedMap[key]!;
		  
		  // Use Overpass data if it has more detailed task items or better category
		  if (overpassResult.taskItems.length > existing.taskItems.length ||
			  overpassResult.category != 'location') {
			print('🔗 MERGING: Enhancing ${existing.name} with Overpass data');
			combinedMap[key] = AILocationResult(
			  name: existing.name, // Keep original name
			  description: overpassResult.description.isNotEmpty ? overpassResult.description : existing.description,
			  coordinates: existing.coordinates, // Keep original coordinates
			  taskItems: overpassResult.taskItems.isNotEmpty ? overpassResult.taskItems : existing.taskItems,
			  category: overpassResult.category != 'location' ? overpassResult.category : existing.category,
			  distanceFromUser: existing.distanceFromUser,
			  isSelected: existing.isSelected,
			);
		  }
		} else {
		  // Add new Overpass result
		  print('🔗 ADDING: New Overpass result ${overpassResult.name}');
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
	  
	  print('🔗 COMBINED RESULTS: Final count: ${combinedResults.length}');
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
		  'amenity': ['cafe'],
		  'shop': ['coffee'],
		  'cuisine': ['coffee_shop']
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
			'amenity': ['bar', 'pub', 'nightclub', 'biergarten']
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
	Future<List<AILocationResult>> _searchOverpassDirect(
		String category, 
		List<String> localTerms,
		Map<String, List<String>> osmTags
	) async {
	  List<AILocationResult> results = [];
	  
	  if (_currentLatLng == null) return results;
	  
	  try {
		print('🚀 OPTIMIZED SEARCH: Starting for "$category"');
		
		// NOVO: Dobij optimalni redoslijed servera
		final servers = await _getOptimalServerOrder();
		
		if (servers.isEmpty) {
		  print('❌ OVERPASS: No available servers found');
		  return results;
		}
		
		print('🏷️ OSM TAGS: $osmTags');
		print('🌐 LOCAL TERMS: $localTerms');
		
		// Ostatak koda ostaje isti, samo koristi 'servers' umjesto hardcoded liste
		final queryParts = <String>[];
		
		for (final tagType in osmTags.keys) {
		  for (final tagValue in osmTags[tagType]!) {
			if (tagValue == '*') {
			  // Special case for all values
			  queryParts.add('node["$tagType"](around:1500,${_currentLatLng!.latitude},${_currentLatLng!.longitude});');
			  queryParts.add('way["$tagType"](around:1500,${_currentLatLng!.latitude},${_currentLatLng!.longitude});');
			} else {
			  queryParts.add('node["$tagType"="$tagValue"](around:1500,${_currentLatLng!.latitude},${_currentLatLng!.longitude});');
			  queryParts.add('way["$tagType"="$tagValue"](around:1500,${_currentLatLng!.latitude},${_currentLatLng!.longitude});');
			}
		  }
		}

		// ADD NAME SEARCHES WITH LOCAL TERMS
		for (final localTerm in localTerms) {
		  // Parse comma-separated terms if AI returned them as one string
		  final terms = localTerm.contains(',') 
			  ? localTerm.split(',').map((t) => t.trim()).toList()
			  : [localTerm];
			  
			for (final term in terms) {
			  // Clean the term from any quotes
			  final cleanTerm = term.replaceAll('"', '').replaceAll("'", '').trim();
			  
			  if (cleanTerm.isNotEmpty && cleanTerm.length > 2) {
				// Search by name containing local term (case insensitive)
				queryParts.add('node["name"~"$cleanTerm",i](around:1500,${_currentLatLng!.latitude},${_currentLatLng!.longitude});');
				queryParts.add('way["name"~"$cleanTerm",i](around:1500,${_currentLatLng!.latitude},${_currentLatLng!.longitude});');
				
				print('🌐 NAME SEARCH: Adding name search for "$cleanTerm"');
			  }
			}
		}
		
		final overpassQuery = '''
	[out:json][timeout:10];
	(
	  ${queryParts.join('\n  ')}
	);
	out center meta;
	''';

		print('🔍 OVERPASS: Query = $overpassQuery');

		http.Response? response;
		String? usedServer;

		// Koristi optimizovani redoslijed servera
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
			).timeout(Duration(seconds: 8)); // Skraćen timeout jer znamo da server radi
			
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
		  print('❌ ALL OPTIMAL SERVERS FAILED');
		  print('🔄 FALLBACK: Trying original server order...');
		  
		  // FALLBACK: pokušaj sa svim originalnim serverima
		  for (int i = 0; i < _allServers.length; i++) {
			final serverUrl = _allServers[i];
			print('🌐 FALLBACK SERVER ${i + 1}/${_allServers.length}: $serverUrl');
			
			try {
			  response = await http.post(
				Uri.parse(serverUrl),
				headers: {
				  'Content-Type': 'application/x-www-form-urlencoded',
				  'User-Agent': 'LocadoApp/1.0',
				},
				body: 'data=${Uri.encodeComponent(overpassQuery)}',
			  ).timeout(Duration(seconds: 15)); // Duži timeout za fallback
			  
			  if (response.statusCode == 200) {
				print('✅ FALLBACK SUCCESS with: $serverUrl');
				break;
			  } else {
				response = null;
			  }
			} catch (e) {
			  print('❌ Fallback server $serverUrl failed: $e');
			  response = null;
			  continue;
			}
		  }
		  
		  if (response == null) {
			print('❌ ALL SERVERS FAILED (including fallback)');
			return results;
		  }
		}

		// Ostatak processing koda ostaje isti...
		if (response.statusCode == 200) {
		  final data = jsonDecode(response.body);
		  final elements = data['elements'] as List;

		  print('🔍 OVERPASS: Found ${elements.length} raw results');

		  // Use Set to avoid duplicates by coordinates
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

			// Create unique coordinate key to avoid duplicates
			final coordKey = '${lat.toStringAsFixed(6)}_${lng.toStringAsFixed(6)}';
			if (addedCoordinates.contains(coordKey)) {
			  continue;
			}

			// Calculate distance
			final distance = Geolocator.distanceBetween(
			  _currentLatLng!.latitude,
			  _currentLatLng!.longitude,
			  lat,
			  lng,
			);

			// Only include nearby places (1.5km max)
			if (distance <= 1500) {
			  addedCoordinates.add(coordKey);
			  
			  // Generate task items from real OSM tags
			  final taskItems = await _generateTaskItemsFromOSMTags(name, tags, category);

			  results.add(AILocationResult(
				name: name,
				description: _getDescriptionFromOSMTags(tags, category),
				coordinates: UniversalLatLng(lat, lng),
				taskItems: taskItems,
				category: _getCategoryFromOSMTags(tags),
				distanceFromUser: distance,
			  ));
			  
			  print('✅ OVERPASS: Added $name (${(distance / 1000).toStringAsFixed(2)}km)');
			}
		  }
		} else {
		  print('❌ OVERPASS: API returned status code ${response.statusCode}');
		}

		// Sort by distance
		results.sort((a, b) => a.distanceFromUser!.compareTo(b.distanceFromUser!));

		print('✅ OVERPASS: Final results: ${results.length}');
		return results.take(25).toList();
		
	  } catch (e) {
		print('❌ OVERPASS: Error = $e');
		return results;
	  }
	  
	  return results;
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
		
		// Progressive radius search: 3km → 5km → 10km → 15km → 20km
		final List<double> ruralRadiuses = [3000, 5000, 10000, 15000, 20000]; // in meters
		final List<double> ruralDistanceLimits = [3000, 5000, 10000, 15000, 20000]; // in meters
		
		// Use provided servers (already tested)
		final servers = availableServers.isNotEmpty ? availableServers : _allServers;
		
		if (servers.isEmpty) {
		  print('❌ OVERPASS FALLBACK: No available servers');
		  return results;
		}
		
		bool overpassWorking = false;
		
		// Try each radius until we find at least 5 results
		for (int radiusIndex = 0; radiusIndex < ruralRadiuses.length; radiusIndex++) {
		  final radiusMeters = ruralRadiuses[radiusIndex];
		  final distanceLimit = ruralDistanceLimits[radiusIndex];
		  final radiusKm = radiusMeters / 1000;
		  
		  print('🌾 OVERPASS FALLBACK: Trying radius ${radiusKm}km (${distanceLimit/1000}km distance limit)');
		  
		  // OPTIMIZED: Build simplified query for rural search to avoid timeouts
		  final queryParts = <String>[];
		  
		  // Strategy 1: Only primary OSM tags (most reliable)
		  if (osmTags['amenity'] != null) {
			for (final tagValue in osmTags['amenity']!.take(2)) { // Limit to 2 most important tags
			  if (tagValue != '*') {
				queryParts.add('node["amenity"="$tagValue"](around:$radiusMeters,${_currentLatLng!.latitude},${_currentLatLng!.longitude});');
				queryParts.add('way["amenity"="$tagValue"](around:$radiusMeters,${_currentLatLng!.latitude},${_currentLatLng!.longitude});');
			  }
			}
		  }
		  
		  // Strategy 2: Add one primary local term search only (most common term)
		  if (localTerms.isNotEmpty) {
			final primaryTerm = localTerms[0].split(',')[0].trim(); // Get first term only
			final cleanTerm = primaryTerm.replaceAll('"', '').replaceAll("'", '').trim();
			
			if (cleanTerm.isNotEmpty && cleanTerm.length > 2) {
			  queryParts.add('node["name"~"$cleanTerm",i](around:$radiusMeters,${_currentLatLng!.latitude},${_currentLatLng!.longitude});');
			  queryParts.add('way["name"~"$cleanTerm",i](around:$radiusMeters,${_currentLatLng!.latitude},${_currentLatLng!.longitude});');
			  print('🌾 OVERPASS FALLBACK: Using primary term "$cleanTerm" for ${radiusKm}km search');
			}
		  }
		  
		  final overpassQuery = '''
[out:json][timeout:8];
(
  ${queryParts.join('\n  ')}
);
out center meta;
''';

		  print('🌾 OVERPASS FALLBACK: Query for ${radiusKm}km radius');

		  http.Response? response;
		  String? usedServer;

		  // Try servers in optimal order (but with shorter timeout)
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
			  ).timeout(Duration(seconds: 8)); // Short timeout for fallback
			  
			  if (response.statusCode == 200) {
				usedServer = serverUrl;
				overpassWorking = true;
				print('✅ OVERPASS FALLBACK: Success with server: $usedServer');
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

		  // Process results for current radius
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
				final taskItems = await _generateTaskItemsFromOSMTags(name, tags, category);

				currentRadiusResults.add(AILocationResult(
				  name: name,
				  description: _getDescriptionFromOSMTags(tags, category),
				  coordinates: UniversalLatLng(lat, lng),
				  taskItems: taskItems,
				  category: _getCategoryFromOSMTags(tags),
				  distanceFromUser: distance,
				));
				
				print('✅ OVERPASS FALLBACK: Added $name (${(distance/1000).toStringAsFixed(1)}km)');
			  }
			}
			
			// Sort current results by distance
			currentRadiusResults.sort((a, b) => a.distanceFromUser!.compareTo(b.distanceFromUser!));
			results = currentRadiusResults;
			
			print('🌾 OVERPASS FALLBACK: Radius ${radiusKm}km completed with ${results.length} results');
			
			// Check if we have enough results to stop
			if (results.length >= 5) {
			  print('✅ OVERPASS FALLBACK: Found ${results.length} results at ${radiusKm}km radius - stopping search');
			  break; // Stop expanding radius
			}
		  }
		}
		
		if (results.length < 5) {
		  print('🌾 OVERPASS FALLBACK: Completed all radii up to 20km, found ${results.length} results');
		} else {
		  print('✅ OVERPASS FALLBACK: Successfully found ${results.length} results');
		}
		
		// Return up to 25 results (same as other search methods)
		return results.take(25).toList();
		
	  } catch (e) {
		print('❌ OVERPASS FALLBACK: Error = $e');
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
	  } else if (categoryLower.contains('restaurant')) {
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
	  
	  // Accessibility
	  if (wheelchairAccess == 'yes') {
		tasks.add('♿ Wheelchair accessible');
	  }
	  
	  // Brand info
	  if (brand.isNotEmpty && brand != name) {
		tasks.add('Brand: $brand');
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