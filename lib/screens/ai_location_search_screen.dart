import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:http/http.dart' as http;
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:geolocator/geolocator.dart';
import '../models/task_location.dart';
import '../helpers/database_helper.dart';
import '../location_service.dart'; // Koristi isti servis kao HomeMapScreen
import 'dart:math';

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
  final LatLng coordinates;
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
  final VoidCallback? onTasksCreated; // Add this line

  const AILocationSearchScreen({Key? key, this.onTasksCreated}) : super(key: key); // Add the parameter

  @override
  State<AILocationSearchScreen> createState() => _AILocationSearchScreenState();
}

class _AILocationSearchScreenState extends State<AILocationSearchScreen> {
  final TextEditingController _searchController = TextEditingController();
  List<AILocationResult> _searchResults = [];
  bool _isLoading = false;
  bool _hasSearched = false;
  bool _isLoadingLocation = false;

  // GPS and location - POBOLJŠANO
  Position? _currentPosition;
  String _currentLocationDisplay = "Getting location..."; // Samo za prikaz
  LatLng? _currentLatLng; // DODANO - prave koordinate za AI

  static String get _openAIApiKey => dotenv.env['OPENAI_API_KEY'] ?? '';
  static String get _googleMapsApiKey => dotenv.env['GOOGLE_MAPS_API_KEY'] ?? '';

  @override
  void initState() {
    super.initState();
    _getCurrentLocationPrecise(); // POBOLJŠANO
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
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

  // Metoda za quick search sa hint-om
  Future<void> _performQuickSearch(String query) async {
    // Postavi query u search field
    _searchController.text = query;

    // Pokreni pretragu
    await _performAISearch();
  }

// Widget za hint dugmad
  Widget _buildSearchHints() {
    final hints = _getSearchHints();

    return Container(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          Row(
            children: [
              Icon(
                Icons.lightbulb_outline,
                color: Colors.amber.shade600,
                size: 24,
              ),
              const SizedBox(width: 8),
              Text(
                'Quick Search',
                style: TextStyle(
                  fontSize: 18,
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
              fontSize: 14,
              color: Colors.grey.shade600,
            ),
          ),
          const SizedBox(height: 20),

          // Grid sa hint dugmadima
          GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 2,
              childAspectRatio: 2.5,
              crossAxisSpacing: 12,
              mainAxisSpacing: 12,
            ),
            itemCount: hints.length,
            itemBuilder: (context, index) {
              final hint = hints[index];
              return _buildHintButton(hint);
            },
          ),

          const SizedBox(height: 20),

          // Multilingual info
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.blue.shade50,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.blue.shade200, width: 1),
            ),
            child: Row(
              children: [
                Icon(Icons.translate, color: Colors.blue.shade600, size: 20),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Multilingual Search',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          color: Colors.blue.shade700,
                          fontSize: 13,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'Search in any language: English, Deutsch, Français, Español, Italiano, etc.',
                        style: TextStyle(
                          fontSize: 11,
                          color: Colors.blue.shade600,
                          height: 1.3,
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
    );
  }

// Widget za pojedinačno hint dugme
  Widget _buildHintButton(Map<String, dynamic> hint) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => _performQuickSearch(hint['query']),
        child: Container(
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
            border: Border.all(color: Colors.grey.shade200),
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: hint['color'].withOpacity(0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(
                    hint['icon'],
                    color: hint['color'],
                    size: 20,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    hint['text'],
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: Colors.grey.shade800,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                Icon(
                  Icons.arrow_forward_ios,
                  color: Colors.grey.shade400,
                  size: 12,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }


  // NOVA METODA - koristi isti LocationService kao HomeMapScreen
  Future<void> _getCurrentLocationPrecise() async {
    setState(() {
      _isLoadingLocation = true;
      _currentLocationDisplay = "Getting location...";
    });

    try {
      // KORISTI ISTI SERVIS kao HomeMapScreen
      final position = await LocationService.getCurrentLocation();

      if (position != null) {
        setState(() {
          _currentPosition = position;
          _currentLatLng = LatLng(position.latitude, position.longitude);
        });

        // Dobij ime lokacije za prikaz (ali ne za AI)
        await _getLocationNameForDisplay(position.latitude, position.longitude);

        print('✅ AI SEARCH: Dobio preciznu lokaciju: ${position.latitude}, ${position.longitude}');
      } else {
        // Fallback ako LocationService ne radi
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

  // Fallback metoda ako LocationService ne radi
  Future<void> _getFallbackLocation() async {
    try {
      // Direktan poziv kao backup
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
        timeLimit: const Duration(seconds: 15), // Povećano sa 10
      );

      setState(() {
        _currentPosition = position;
        _currentLatLng = LatLng(position.latitude, position.longitude);
      });

      await _getLocationNameForDisplay(position.latitude, position.longitude);

    } catch (e) {
      print('❌ AI SEARCH: Fallback failed: $e');
      _setFallbackLocation();
    }
  }

  void _setFallbackLocation() {
    setState(() {
      _currentPosition = null;
      _currentLatLng = LatLng(48.2082, 16.3738); // Vienna kao fallback za koordinate
      _currentLocationDisplay = "Vienna, Austria (default)";
    });
  }

  // POBOLJŠANO - samo za prikaz, ne utiče na AI
  Future<void> _getLocationNameForDisplay(double lat, double lng) async {
    try {
      // Proveri network konekciju prvo
      final response = await http.get(
        Uri.parse('https://www.google.com'),
        headers: {'Accept': 'text/html'},
      ).timeout(Duration(seconds: 5));

      if (response.statusCode != 200) {
        throw Exception('Network not available');
      }

      // Ako je network OK, nastavi sa geocoding
      final url = 'https://maps.googleapis.com/maps/api/geocode/json'
          '?latlng=$lat,$lng'
          '&key=$_googleMapsApiKey';

      final geocodeResponse = await http.get(Uri.parse(url))
          .timeout(Duration(seconds: 10));

      if (geocodeResponse.statusCode == 200) {
        final data = jsonDecode(geocodeResponse.body);
        final results = data['results'] as List;

        if (results.isNotEmpty) {
          final result = results[0];
          final components = result['address_components'] as List;

          String? city;
          String? country;

          for (final component in components) {
            final types = component['types'] as List;
            if (types.contains('locality')) {
              city = component['long_name'];
            }
            if (types.contains('country')) {
              country = component['long_name'];
            }
          }

          String displayName;
          if (city != null && country != null) {
            displayName = '$city, $country';
          } else {
            displayName = result['formatted_address'] ?? 'Location found';
          }

          setState(() {
            _currentLocationDisplay = displayName;
          });
        } else {
          setState(() {
            _currentLocationDisplay = 'Location found (coordinates: ${lat.toStringAsFixed(4)}, ${lng.toStringAsFixed(4)})';
          });
        }
      }
    } catch (e) {
      print('❌ Error getting location name for display: $e');
      setState(() {
        _currentLocationDisplay = 'Location found (no internet)';
      });
    }
  }

  // HIBRIDNA STRATEGIJA - kombinuje AI + Google Places direktno
  Future<List<AILocationResult>> _performHybridNearbySearch(String query) async {
    final isLocalSearch = query.toLowerCase().contains('nearby') ||
        query.toLowerCase().contains('around') ||
        query.toLowerCase().contains('close') ||
        query.toLowerCase().contains('near me') ||
        query.toLowerCase().contains('in the area');

    if (!isLocalSearch || _currentLatLng == null) {
      // Normalna AI pretraga za ne-lokalne pretrage
      final aiResponse = await _getAILocationSuggestionsWithCoordinates(query);
      return await _enrichWithRealCoordinates(aiResponse, query);
    }

    print('🔍 HYBRID: Starting nearby search for "$query"');
    print('🔍 HYBRID: User location = ${_currentLatLng!.latitude}, ${_currentLatLng!.longitude}');

    // STRATEGIJA 1: Google Places direktna pretraga (primarno)
    List<AILocationResult> googleResults = await _searchGooglePlacesDirectly(query);

    // STRATEGIJA 2: AI pretraga (sekundarno, za dodatne ideje)
    List<AILocationResult> aiResults = [];
    try {
      final aiResponse = await _getImprovedAINearbySearch(query);
      aiResults = await _enrichWithRealCoordinates(aiResponse, query);
    } catch (e) {
      print('⚠️ HYBRID: AI search failed, using Google only: $e');
    }

    // Kombiniraj rezultate
    Set<String> seenNames = {};
    List<AILocationResult> combinedResults = [];

    // Dodaj Google rezultate (prioritet)
    for (final result in googleResults) {
      if (!seenNames.contains(result.name.toLowerCase())) {
        seenNames.add(result.name.toLowerCase());
        combinedResults.add(result);
      }
    }

    // Dodaj AI rezultate (ako nisu duplikati)
    for (final result in aiResults) {
      if (!seenNames.contains(result.name.toLowerCase())) {
        seenNames.add(result.name.toLowerCase());
        combinedResults.add(result);
      }
    }

    // Sortiraj po udaljenosti
    combinedResults.sort((a, b) {
      if (a.distanceFromUser == null && b.distanceFromUser == null) return 0;
      if (a.distanceFromUser == null) return 1;
      if (b.distanceFromUser == null) return -1;
      return a.distanceFromUser!.compareTo(b.distanceFromUser!);
    });

    print('✅ HYBRID: Final combined results: ${combinedResults.length}');
    return combinedResults.take(8).toList(); // Ograniči na 8 najbližih
  }

  // NEW METHOD: Use AI to optimize search query for Google Places API
  Future<Map<String, dynamic>> _optimizeSearchWithAI(String userQuery, String localLanguage) async {
    final locationInfo = _currentLatLng != null
        ? 'at coordinates ${_currentLatLng!.latitude}, ${_currentLatLng!.longitude} (${_currentLocationDisplay})'
        : 'location unknown';

    final prompt = '''You are a Google Places API optimization expert. 
The user is $locationInfo.

User searched for: "$userQuery"
Local language: $localLanguage

Your task: Convert this to optimal Google Places API parameters.

RULES:
1. Return the best "type" parameter for Google Places API (e.g., restaurant, gas_station, pharmacy, atm, grocery_or_supermarket, etc.)
2. Generate optimized search keywords in English AND local language
3. If user wants multiple things (like "banks and ATMs"), choose the MOST SPECIFIC type
4. For vague queries, choose the most likely type based on context

Available Google Places types: restaurant, cafe, gas_station, pharmacy, atm, bank, grocery_or_supermarket, store, hospital, movie_theater, gym, beauty_salon, shopping_mall

Return ONLY this JSON format:
{
  "type": "gas_station",
  "englishKeywords": ["gas station", "fuel", "petrol"],
  "localKeywords": ["tankstelle", "benzin", "diesel"],
  "startRadius": 300
}

User query: "$userQuery"''';

    try {
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
          'max_tokens': 300,
          'temperature': 0.1,
        }),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final content = data['choices'][0]['message']['content'];

        print('🤖 AI OPTIMIZATION: $content');

        final aiOptimization = jsonDecode(content);
        return aiOptimization;
      }
    } catch (e) {
      print('❌ AI optimization failed: $e');
    }

    // Fallback to current detection
    return {
      'type': _detectSearchType(userQuery),
      'englishKeywords': [userQuery],
      'localKeywords': [userQuery],
      'startRadius': 300
    };
  }

  // NEW METHOD: Progressive radius search until we get enough results
  Future<List<AILocationResult>> _searchWithProgressiveRadius(String searchType, Map<String, dynamic> aiOptimization) async {
    if (_currentLatLng == null) return [];

    List<AILocationResult> allResults = [];
    final targetResultCount = 5;
    final radiusSteps = [300, 500, 800, 1200, 2000]; // Progressive radius in meters

    print('🔍 PROGRESSIVE SEARCH: Starting for type "$searchType"');

    for (int i = 0; i < radiusSteps.length; i++) {
      final radius = radiusSteps[i];
      print('🔍 PROGRESSIVE SEARCH: Trying radius ${radius}m (step ${i + 1}/${radiusSteps.length})');

      try {
        final url = 'https://maps.googleapis.com/maps/api/place/nearbysearch/json'
            '?location=${_currentLatLng!.latitude},${_currentLatLng!.longitude}'
            '&radius=$radius'
            '&type=$searchType'
            '&rankby=prominence'
            '&key=$_googleMapsApiKey';

        final response = await http.get(Uri.parse(url));

        if (response.statusCode == 200) {
          final data = jsonDecode(response.body);
          final List places = data['results'];

          print('🔍 PROGRESSIVE SEARCH: Found ${places.length} places at ${radius}m radius');

          // Process places for this radius
          Set<String> seenPlaceIds = allResults.map((r) => r.name.toLowerCase()).toSet();

          for (final place in places) {
            final lat = place['geometry']['location']['lat'];
            final lng = place['geometry']['location']['lng'];
            final name = place['name'];
            final types = List<String>.from(place['types'] ?? []);
            final placeId = place['place_id'];

            // Skip duplicates
            if (seenPlaceIds.contains(name.toLowerCase())) continue;

            // Check if it's relevant type
            if (_isRelevantPlaceType(types, searchType)) {
              // Calculate actual distance
              final distance = Geolocator.distanceBetween(
                _currentLatLng!.latitude,
                _currentLatLng!.longitude,
                lat,
                lng,
              );

              print('🔍 PROGRESSIVE SEARCH: Adding ${name} = ${(distance / 1000).toStringAsFixed(2)}km');

              // Generate specific task items using real data
              final specificTaskItems = await _generateSpecificTaskItems(
                name,
                searchType,
                LatLng(lat, lng),
                placeId: placeId,
              );

              allResults.add(AILocationResult(
                name: name,
                description: 'Local ${searchType.replaceAll('_', ' ')} with great reviews',
                coordinates: LatLng(lat, lng),
                taskItems: specificTaskItems,
                category: searchType,
                distanceFromUser: distance,
              ));

              seenPlaceIds.add(name.toLowerCase());
            }
          }

          // Check if we have enough results
          if (allResults.length >= targetResultCount) {
            print('✅ PROGRESSIVE SEARCH: Found ${allResults.length} results, stopping at ${radius}m radius');
            break;
          }
        }
      } catch (e) {
        print('❌ PROGRESSIVE SEARCH: Error at radius ${radius}m: $e');
        continue; // Try next radius
      }
    }

    // Sort by distance
    allResults.sort((a, b) {
      if (a.distanceFromUser == null && b.distanceFromUser == null) return 0;
      if (a.distanceFromUser == null) return 1;
      if (b.distanceFromUser == null) return -1;
      return a.distanceFromUser!.compareTo(b.distanceFromUser!);
    });

    print('✅ PROGRESSIVE SEARCH: Final results: ${allResults.length} places found');
    return allResults.take(8).toList(); // Limit to 8 best results
  }

  Future<List<AILocationResult>> _searchGooglePlacesDirectly(String query) async {
    List<AILocationResult> results = [];

    try {
      print('🔍 GOOGLE DIRECT: Starting optimized search for "$query"');

      // STEP 1: Get current country language
      final locationInfo = await _detectLanguageAndCountry();
      final localLanguage = locationInfo['countryLanguage']!;

      // STEP 2: Use AI to optimize the search query
      final aiOptimization = await _optimizeSearchWithAI(query, localLanguage);
      final searchType = aiOptimization['type'] as String;

      print('🔍 GOOGLE DIRECT: AI optimized search type = "$searchType"');

      // STEP 3: Skip establishment searches (too generic)
      if (searchType == 'establishment') {
        print('⏭️ GOOGLE DIRECT: Skipping establishment search, too generic');
        return results;
      }

      // STEP 4: Use progressive radius search
      results = await _searchWithProgressiveRadius(searchType, aiOptimization);

    } catch (e) {
      print('❌ GOOGLE DIRECT: Error = $e');
    }

    print('✅ GOOGLE DIRECT: Returning ${results.length} optimized results');
    return results;
  }

  bool _isRelevantPlaceType(List<String> placeTypes, String requestedType) {
    // Definiši relevantne tipove za svaki zahtev
    final Map<String, List<String>> relevantTypes = {
      'gas_station': ['gas_station', 'fuel'],
      'pharmacy': ['pharmacy', 'drugstore'],
      'cafe': ['cafe', 'coffee_shop'],
      'restaurant': ['restaurant', 'meal_takeaway', 'meal_delivery', 'food'],
      'bank': ['bank', 'atm', 'finance'],
      'atm': ['atm', 'bank', 'finance'],
      'hospital': ['hospital', 'doctor', 'health', 'medical_care'],
      'store': ['store', 'supermarket', 'grocery_or_supermarket', 'shopping_mall'],
      'grocery_or_supermarket': ['grocery_or_supermarket', 'supermarket', 'store', 'food'],
      'movie_theater': ['movie_theater', 'cinema'],
      'gym': ['gym', 'fitness_center', 'spa'],
      'beauty_salon': ['beauty_salon', 'hair_care', 'barber_shop'],
    };

    // Dobij relevantne tipove za zahtevani tip
    final expectedTypes = relevantTypes[requestedType] ?? [requestedType];

    // Proveri da li mesto ima bar jedan od očekivanih tipova
    for (final expectedType in expectedTypes) {
      if (placeTypes.contains(expectedType)) {
        return true;
      }
    }

    // Dodatna provera - isključi očigledno nebitne tipove
    final irrelevantTypes = [
      'lodging', 'hotel', 'motel', // Smeštaj
      'tourist_attraction', 'museum', 'park', // Turizam (osim ako nije traženo)
      'church', 'place_of_worship', // Religija
      'school', 'university', // Obrazovanje
      'courthouse', 'government', // Vlada
    ];

    // Ako ima irelevantne tipove, a nema relevantne - isključi
    for (final irrelevantType in irrelevantTypes) {
      if (placeTypes.contains(irrelevantType)) {
        return false;
      }
    }

    return false; // Ako ništa nije relevantno, isključi
  }

  String _detectSearchType(String query) {
    final lowerQuery = query.toLowerCase();

    // GASOLINE / FUEL
    if (lowerQuery.contains('gas') ||
        lowerQuery.contains('fuel') ||
        lowerQuery.contains('petrol') ||
        lowerQuery.contains('benzin') ||
        lowerQuery.contains('tanken') ||
        lowerQuery.contains('tankstelle') ||
        lowerQuery.contains('pumpa')) {
      return 'gas_station';
    }

    // PHARMACY / MEDICINE
    if (lowerQuery.contains('pharmacy') ||
        lowerQuery.contains('medicine') ||
        lowerQuery.contains('drug') ||
        lowerQuery.contains('apotheke') ||
        lowerQuery.contains('ljekarna') ||
        lowerQuery.contains('apteka')) {
      return 'pharmacy';
    }

    // COFFEE / CAFE
    if (lowerQuery.contains('coffee') ||
        lowerQuery.contains('cafe') ||
        lowerQuery.contains('caffè') ||
        lowerQuery.contains('kafe') ||
        lowerQuery.contains('kaffee') ||
        lowerQuery.contains('espresso') ||
        lowerQuery.contains('cappuccino')) {
      return 'cafe';
    }

// SHOPPING / STORES
    if (lowerQuery.contains('supermarket') ||
        lowerQuery.contains('grocery') ||
        lowerQuery.contains('market') ||
        lowerQuery.contains('shop') ||
        lowerQuery.contains('store') ||
        lowerQuery.contains('trgovina') ||
        lowerQuery.contains('geschäft') ||
        lowerQuery.contains('laden') ||
        lowerQuery.contains('mall') ||
        lowerQuery.contains('lidl') ||
        lowerQuery.contains('billa') ||
        lowerQuery.contains('hofer') ||
        lowerQuery.contains('spar')) {
      return 'grocery_or_supermarket'; // More specific type
    }

    // ATM FIRST (more specific)
    if (lowerQuery.contains('atm') ||
        lowerQuery.contains('bankomat') ||
        lowerQuery.contains('geldautomat')) {
      return 'atm';
    }

    // BANK / BANKING
    if (lowerQuery.contains('bank') ||
        lowerQuery.contains('banka') ||
        lowerQuery.contains('money') ||
        lowerQuery.contains('banking')) {
      return 'bank';
    }

    // HOSPITAL / MEDICAL
    if (lowerQuery.contains('hospital') ||
        lowerQuery.contains('doctor') ||
        lowerQuery.contains('medical') ||
        lowerQuery.contains('health') ||
        lowerQuery.contains('clinic') ||
        lowerQuery.contains('krankenhaus') ||
        lowerQuery.contains('bolnica') ||
        lowerQuery.contains('doktor')) {
      return 'hospital';
    }

    // RESTAURANT / FOOD
    if (lowerQuery.contains('restaurant') ||
        lowerQuery.contains('food') ||
        lowerQuery.contains('eat') ||
        lowerQuery.contains('dine') ||
        lowerQuery.contains('meal') ||
        lowerQuery.contains('pizza') ||
        lowerQuery.contains('burger') ||
        lowerQuery.contains('restoran') ||
        lowerQuery.contains('essen') ||
        lowerQuery.contains('gastronomie')) {
      return 'restaurant';
    }

    // ENTERTAINMENT
    if (lowerQuery.contains('cinema') ||
        lowerQuery.contains('movie') ||
        lowerQuery.contains('theater') ||
        lowerQuery.contains('entertainment') ||
        lowerQuery.contains('kino')) {
      return 'movie_theater';
    }

    // GYM / FITNESS
    if (lowerQuery.contains('gym') ||
        lowerQuery.contains('fitness') ||
        lowerQuery.contains('sport') ||
        lowerQuery.contains('workout')) {
      return 'gym';
    }

    // BEAUTY / SALON
    if (lowerQuery.contains('salon') ||
        lowerQuery.contains('barber') ||
        lowerQuery.contains('beauty') ||
        lowerQuery.contains('hair') ||
        lowerQuery.contains('friseur')) {
      return 'beauty_salon';
    }

    // UMESTO establishment, vrati null da označiš da nema Google pretragu
    print('⚠️ SEARCH TYPE: No specific type detected for "$query", skipping Google Places');
    return 'establishment'; // Ovo će biti preskočeno u _searchGooglePlacesDirectly
  }

  // POBOLJŠANA AI nearby pretraga sa strožijim instrukcijama
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
        'temperature': 0.2, // Vrlo precizno
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

    // ENSURE WE HAVE USER LOCATION (needed for nearby searches)
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
        // NEARBY SEARCH - use existing multilingual hybrid approach
        print('📍 NEARBY SEARCH: Using current location');

        final translations = await _prepareTranslatedQueries(searchIntent.cleanQuery);
        results = await _performMultilingualHybridSearch(translations);

        _showSnackBar('Found ${results.length} nearby locations', Colors.green);

      } else {
        // SPECIFIC LOCATION SEARCH - new approach
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

// NEW METHOD: Search for locations in a specific city/location
  Future<List<AILocationResult>> _performSpecificLocationSearch(String query, String targetLocation) async {
    print('🏙️ SPECIFIC LOCATION SEARCH: "$query" in "$targetLocation"');

    try {
      // STEP 1: Get coordinates of the target location
      final targetCoordinates = await _getTargetLocationCoordinates(targetLocation);

      if (targetCoordinates == null) {
        throw Exception('Could not find coordinates for $targetLocation');
      }

      print('✅ TARGET LOCATION: $targetLocation = ${targetCoordinates.latitude}, ${targetCoordinates.longitude}');

      // STEP 2: Search using AI with target location context
      final aiResults = await _getAILocationSuggestionsForSpecificLocation(query, targetLocation, targetCoordinates);

      // STEP 3: Enrich with real coordinates (without distance filtering)
      final enrichedResults = await _enrichWithRealCoordinatesForLocation(aiResults, query, targetCoordinates);

      print('✅ SPECIFIC LOCATION SEARCH: Found ${enrichedResults.length} results in $targetLocation');
      return enrichedResults;

    } catch (e) {
      print('❌ SPECIFIC LOCATION SEARCH: Error = $e');
      throw Exception('Failed to search in $targetLocation: $e');
    }
  }

// NEW METHOD: Get coordinates for target location
  Future<LatLng?> _getTargetLocationCoordinates(String locationName) async {
    try {
      final query = Uri.encodeComponent(locationName);
      final url = 'https://maps.googleapis.com/maps/api/geocode/json'
          '?address=$query'
          '&key=$_googleMapsApiKey';

      final response = await http.get(Uri.parse(url));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final results = data['results'] as List;

        if (results.isNotEmpty) {
          final location = results[0]['geometry']['location'];
          final formattedAddress = results[0]['formatted_address'];

          print('✅ GEOCODING: $locationName → $formattedAddress');
          return LatLng(location['lat'], location['lng']);
        }
      }
    } catch (e) {
      print('❌ GEOCODING ERROR: $e');
    }

    return null;
  }

// NEW METHOD: Get AI suggestions for specific location
  Future<List<Map<String, dynamic>>> _getAILocationSuggestionsForSpecificLocation(
      String query,
      String targetLocation,
      LatLng targetCoordinates
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
        'temperature': 0.4, // Slightly more creative for tourist suggestions
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

// NEW METHOD: Enrich coordinates for specific location (no distance filtering)
  Future<List<AILocationResult>> _enrichWithRealCoordinatesForLocation(
      List<Map<String, dynamic>> aiResults,
      String originalQuery,
      LatLng targetLocationCoords
      ) async {

    List<AILocationResult> enrichedResults = [];

    print('🔍 ENRICH LOCATION: Processing ${aiResults.length} results for specific location...');

    for (int i = 0; i < aiResults.length; i++) {
      final aiResult = aiResults[i];
      print('🔍 ENRICH LOCATION: Processing ${aiResult['name']}');

      try {
        // Search for real coordinates
        final coordinates = await _getCoordinatesFromGoogle(
            aiResult['name'],
            aiResult['city'] ?? 'Unknown Location'
        );

        if (coordinates != null) {
          print('✅ ENRICH LOCATION: Found coordinates for ${aiResult['name']}');

          // Calculate distance from target location (not user location)
          double? distanceFromTarget;
          if (_currentLatLng != null) {
            distanceFromTarget = Geolocator.distanceBetween(
              _currentLatLng!.latitude,
              _currentLatLng!.longitude,
              coordinates.latitude,
              coordinates.longitude,
            );
          }

          // Generate specific task items
          final specificTaskItems = await _generateSpecificTaskItems(
            aiResult['name'],
            aiResult['category'] ?? 'location',
            coordinates,
          );

          enrichedResults.add(
            AILocationResult(
              name: aiResult['name'],
              description: aiResult['description'] ?? 'Popular location',
              coordinates: coordinates,
              taskItems: specificTaskItems,
              category: aiResult['category'] ?? 'location',
              distanceFromUser: distanceFromTarget, // Distance from user, not target
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

    // Sort by relevance/popularity (no distance sorting for specific locations)
    print('✅ ENRICH LOCATION: Final results count: ${enrichedResults.length}');
    return enrichedResults;
  }

  Future<List<AILocationResult>> _performMultilingualHybridSearch(Map<String, String> translations) async {
    final originalQuery = translations['original']!;
    final englishQuery = translations['english']!;
    final localQuery = translations['local']!;

    final isLocalSearch = originalQuery.toLowerCase().contains('nearby') ||
        originalQuery.toLowerCase().contains('around') ||
        originalQuery.toLowerCase().contains('close') ||
        originalQuery.toLowerCase().contains('near me') ||
        originalQuery.toLowerCase().contains('in the area') ||
        // Dodaj i prevode "nearby" termina
        englishQuery.toLowerCase().contains('nearby') ||
        localQuery.toLowerCase().contains('nearby');

    if (!isLocalSearch || _currentLatLng == null) {
      // Normalna AI pretraga sa engleskim query-jem
      final aiResponse = await _getAILocationSuggestionsWithCoordinates(englishQuery);
      return await _enrichWithRealCoordinates(aiResponse, englishQuery);
    }

    print('🌍 MULTILINGUAL HYBRID: Starting nearby search');
    print('🌍 Queries: Original="$originalQuery", English="$englishQuery", Local="$localQuery"');

    Set<String> seenNames = {};
    List<AILocationResult> allResults = [];

    // STRATEGIJA 1: Google Places sa lokalnim jezikom (primarno)
    print('🔍 Step 1: Google Places with local language');
    try {
      final localGoogleResults = await _searchGooglePlacesDirectly(localQuery);
      for (final result in localGoogleResults) {
        if (!seenNames.contains(result.name.toLowerCase())) {
          seenNames.add(result.name.toLowerCase());
          allResults.add(result);
        }
      }
      print('✅ Local Google results: ${localGoogleResults.length}');
    } catch (e) {
      print('❌ Local Google search failed: $e');
    }

    // STRATEGIJA 2: Google Places sa engleskim (sekundarno)
    if (englishQuery != localQuery) {
      print('🔍 Step 2: Google Places with English');
      try {
        final englishGoogleResults = await _searchGooglePlacesDirectly(englishQuery);
        for (final result in englishGoogleResults) {
          if (!seenNames.contains(result.name.toLowerCase())) {
            seenNames.add(result.name.toLowerCase());
            allResults.add(result);
          }
        }
        print('✅ English Google results: ${englishGoogleResults.length}');
      } catch (e) {
        print('❌ English Google search failed: $e');
      }
    }

    // STRATEGIJA 3: AI pretraga sa engleskim (tercijarno, za dodatne ideje)
    /*print('🔍 Step 3: AI search with English');
    try {
      final aiResponse = await _getImprovedAINearbySearch(englishQuery);
      final aiResults = await _enrichWithRealCoordinates(aiResponse, englishQuery);
      for (final result in aiResults) {
        if (!seenNames.contains(result.name.toLowerCase())) {
          seenNames.add(result.name.toLowerCase());
          allResults.add(result);
        }
      }
      print('✅ AI results: ${aiResults.length}');
    } catch (e) {
      print('❌ AI search failed: $e');
    }

    // STRATEGIJA 4: AI pretraga sa lokalnim jezikom (bonus)
    if (localQuery != englishQuery) {
      print('🔍 Step 4: AI search with local language');
      try {
        final localAiResponse = await _getImprovedAINearbySearch(localQuery);
        final localAiResults = await _enrichWithRealCoordinates(localAiResponse, localQuery);
        for (final result in localAiResults) {
          if (!seenNames.contains(result.name.toLowerCase())) {
            seenNames.add(result.name.toLowerCase());
            allResults.add(result);
          }
        }
        print('✅ Local AI results: ${localAiResults.length}');
      } catch (e) {
        print('❌ Local AI search failed: $e');
      }
    }*/

    // Sortiraj po udaljenosti
    allResults.sort((a, b) {
      if (a.distanceFromUser == null && b.distanceFromUser == null) return 0;
      if (a.distanceFromUser == null) return 1;
      if (b.distanceFromUser == null) return -1;
      return a.distanceFromUser!.compareTo(b.distanceFromUser!);
    });

    print('🌍 MULTILINGUAL HYBRID: Final combined results: ${allResults.length}');
    return allResults.take(10).toList(); // Povećano na 10 zbog više izvora
  }


  // POTPUNO NOVA METODA - šalje koordinate umesto imena AI-u
  Future<List<Map<String, dynamic>>> _getAILocationSuggestionsWithCoordinates(String query) async {

    // Pripremi lokaciju za AI
    String locationContext;
    String searchArea = "Vienna, Austria"; // Fallback za human-readable

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

      // Za AI search, koristi koordinate + ime grada
      searchArea = '${_currentLatLng!.latitude}, ${_currentLatLng!.longitude} (${_currentLocationDisplay})';
    } else {
      print('❌ AI DEBUG: NO PRECISE COORDINATES! Using fallback Vienna');
      locationContext = '''The user's location is not available. Use Vienna, Austria (48.2082, 16.3738) as default.''';
    }

    print('🔍 AI DEBUG: Search area = "$searchArea"');
    print('🔍 AI DEBUG: Location context length = ${locationContext.length} chars');

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
    print('🔍 AI DEBUG: Query = "$query"');

    final response = await http.post(
      Uri.parse('https://api.openai.com/v1/chat/completions'),
      headers: {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $_openAIApiKey',
      },
      body: jsonEncode({
        'model': 'gpt-3.5-turbo',
        'messages': [
          {
            'role': 'system',
            'content': prompt
          },
          {
            'role': 'user',
            'content': query
          }
        ],
        'max_tokens': 3500,
        'temperature': 0.3, // SMANJENO sa 0.7 za preciznije rezultate
      }),
    );

    if (response.statusCode != 200) {
      print('❌ AI DEBUG: OpenAI API Error: ${response.statusCode}');
      print('❌ AI DEBUG: Response body: ${response.body}');
      throw Exception('OpenAI API Error: ${response.statusCode}');
    }

    final data = jsonDecode(response.body);
    final content = data['choices'][0]['message']['content'];

    print('🔍 AI DEBUG: Raw AI response:');
    print(content);

    try {
      final List<dynamic> aiResults = jsonDecode(content);
      print('✅ AI DEBUG: Successfully parsed ${aiResults.length} results from AI');

      // Debug prvi rezultat
      if (aiResults.isNotEmpty) {
        print('🔍 AI DEBUG: First result = ${aiResults[0]}');
      }

      return aiResults.cast<Map<String, dynamic>>();
    } catch (e) {
      print('❌ AI DEBUG: Error parsing AI response: $e');
      print('❌ AI DEBUG: AI Response was: $content');
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
        // Search for real coordinates using Google Places API
        final coordinates = await _getCoordinatesFromGoogle(
            aiResult['name'],
            aiResult['city'] ?? _currentLocationDisplay
        );

        if (coordinates != null) {
          print('✅ ENRICH DEBUG: Found coordinates for ${aiResult['name']}: ${coordinates.latitude}, ${coordinates.longitude}');

          double? distanceFromUser;
          bool shouldInclude = true;

          // Calculate distance if we have GPS location - KORISTI PRECIZNE KOORDINATE
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
              // STROŽIJI FILTER - 3km umesto 50km
              shouldInclude = distanceFromUser <= 3000; // 3km u metrima
              print('🔍 ENRICH DEBUG: Local search filter: ${aiResult['name']} ${shouldInclude ? "INCLUDED" : "EXCLUDED"} (${(distanceFromUser / 1000).toStringAsFixed(2)}km)');
            }
          } else {
            print('⚠️ ENRICH DEBUG: No user coordinates for distance calculation');
          }

          if (shouldInclude) {
            print('✅ ENRICH DEBUG: Adding ${aiResult['name']} to results');
            // Generate specific task items for AI results too
            final specificTaskItems = await _generateSpecificTaskItems(
              aiResult['name'],
              aiResult['category'] ?? 'location',
              coordinates,
              // No place_id available for AI results, will use generic data
            );

            enrichedResults.add(
              AILocationResult(
                name: aiResult['name'],
                description: aiResult['description'],
                coordinates: coordinates,
                taskItems: specificTaskItems, // <- NOVA LINIJA
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
        // Continue with next location
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

      // Debug najbliže rezultate
      for (int i = 0; i < enrichedResults.length && i < 3; i++) {
        final result = enrichedResults[i];
        print('🔍 ENRICH DEBUG: Result #${i+1}: ${result.name} - ${(result.distanceFromUser! / 1000).toStringAsFixed(2)}km');
      }
    }

    print('✅ ENRICH DEBUG: Final results count: ${enrichedResults.length}');
    return enrichedResults;
  }

  Future<LatLng?> _getCoordinatesFromGoogle(String locationName, String city) async {
    final query = Uri.encodeComponent('$locationName $city');
    final url = 'https://maps.googleapis.com/maps/api/place/findplacefromtext/json'
        '?input=$query'
        '&inputtype=textquery'
        '&fields=geometry,place_id'
        '&key=$_googleMapsApiKey';

    final response = await http.get(Uri.parse(url));

    if (response.statusCode == 200) {
      final data = jsonDecode(response.body);
      final candidates = data['candidates'] as List;

      if (candidates.isNotEmpty) {
        final location = candidates[0]['geometry']['location'];
        return LatLng(location['lat'], location['lng']);
// Note: place_id will be handled separately in the calling method
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
        // Create TaskLocation object
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
        // If callback is provided (when used as tab), call it
        widget.onTasksCreated!();
      } else {
        // If no callback (when used with Navigator.push), use Navigator.pop
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
            // SKRAĆENO - ukloni translate ikonu iz naslova
            const Row(
              children: [
                Icon(Icons.smart_toy, size: 24),
                SizedBox(width: 8),
                Expanded( // DODANO Expanded da spreči overflow
                  child: Text(
                    'AI Location Search',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                    overflow: TextOverflow.ellipsis, // DODANO
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
                    _isLoadingLocation ? 'Getting location...' : _currentLocationDisplay, // SKRAĆENO
                    style: TextStyle(
                      fontSize: 12,
                      color: Colors.white.withOpacity(0.8),
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                // PREMESTI translate ikonu ovde
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
              // Search Section - sa multilingual hint
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
                    // Search Input sa multilingual hint
                    TextField(
                      controller: _searchController,
                      decoration: InputDecoration(
                        hintText: 'Search in any language! (English, Deutsch, Français, etc.)',
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
                                _isLoading ? 'Searching...' : 'Search with AI (Multilingual)',
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

          // Floating Create Tasks Button (isti kao pre)
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

    // NOVA LOGIKA: Hint dugmad ODMAH ispod search dugmeta
    if (!_hasSearched) {
      return Column(
        children: [
          // HINT DUGMAD - odmah na vrhu
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Quick Search header - kompaktno
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

                  // Grid sa hint dugmadima - kompaktno
                  GridView.builder(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: 2,
                      childAspectRatio: 3.0, // Povećano sa 2.5 na 3.0 (niži dugmad)
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

                  // AI Location Search info - kompaktno
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.teal.shade50,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.teal.shade200, width: 1),
                    ),
                    child: Row(
                      children: [
                        Icon(Icons.smart_toy, color: Colors.teal.shade600, size: 18),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'AI Location Search',
                                style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  color: Colors.teal.shade700,
                                  fontSize: 12,
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                'Find nearby places with intelligent multilingual search',
                                style: TextStyle(
                                  fontSize: 10,
                                  color: Colors.teal.shade600,
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

                  // Multilingual info - kompaktno
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

    // Postojeća logika za rezultate pretrage
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

            // Dugme za povratak na hint-ove
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
                      size: 16, // Smanjeno sa 20
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      hint['text'],
                      style: TextStyle(
                        fontSize: 11, // Smanjeno sa 13
                        fontWeight: FontWeight.w600,
                        color: Colors.grey.shade800,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  Icon(
                    Icons.arrow_forward_ios,
                    color: Colors.grey.shade400,
                    size: 10, // Smanjeno sa 12
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    }

  // NOVA METODA: Detektuje jezik i lokaciju zemlje
  Future<Map<String, String>> _detectLanguageAndCountry() async {
    String countryCode = 'AT'; // Default Austria
    String countryLanguage = 'German'; // Default German

    try {
      if (_currentLatLng != null) {
        // Dobij informacije o zemlji iz koordinata
        final url = 'https://maps.googleapis.com/maps/api/geocode/json'
            '?latlng=${_currentLatLng!.latitude},${_currentLatLng!.longitude}'
            '&key=$_googleMapsApiKey';

        final response = await http.get(Uri.parse(url));

        if (response.statusCode == 200) {
          final data = jsonDecode(response.body);
          final results = data['results'] as List;

          if (results.isNotEmpty) {
            final components = results[0]['address_components'] as List;

            for (final component in components) {
              final types = component['types'] as List;
              if (types.contains('country')) {
                countryCode = component['short_name'] ?? 'AT';
                break;
              }
            }
          }
        }
      }

      // Mapiranje zemlje na jezik
      countryLanguage = _getCountryLanguage(countryCode);

      print('🌍 LOCATION: Country = $countryCode, Language = $countryLanguage');

    } catch (e) {
      print('❌ Error detecting country: $e');
    }

    return {
      'countryCode': countryCode,
      'countryLanguage': countryLanguage,
    };
  }

// Helper metoda za mapiranje zemlje na jezik
  String _getCountryLanguage(String countryCode) {
    const Map<String, String> countryLanguages = {
      'AT': 'German',       // Austria
      'DE': 'German',       // Germany
      'CH': 'German',       // Switzerland
      'FR': 'French',       // France
      'IT': 'Italian',      // Italy
      'ES': 'Spanish',      // Spain
      'PT': 'Portuguese',   // Portugal
      'NL': 'Dutch',        // Netherlands
      'BE': 'Dutch',        // Belgium
      'PL': 'Polish',       // Poland
      'CZ': 'Czech',        // Czech Republic
      'SK': 'Slovak',       // Slovakia
      'HU': 'Hungarian',    // Hungary
      'SI': 'Slovenian',    // Slovenia
      'HR': 'Croatian',     // Croatia
      'RS': 'Serbian',      // Serbia
      'BA': 'Bosnian',      // Bosnia
      'RO': 'Romanian',     // Romania
      'BG': 'Bulgarian',    // Bulgaria
      'GR': 'Greek',        // Greece
      'TR': 'Turkish',      // Turkey
      'RU': 'Russian',      // Russia
      'UA': 'Ukrainian',    // Ukraine
      'GB': 'English',      // UK
      'IE': 'English',      // Ireland
      'US': 'English',      // USA
      'CA': 'English',      // Canada
      'AU': 'English',      // Australia
      'NZ': 'English',      // New Zealand
      'ZA': 'English',      // South Africa
      'IN': 'English',      // India
      'JP': 'Japanese',     // Japan
      'KR': 'Korean',       // South Korea
      'CN': 'Chinese',      // China
      'TW': 'Chinese',      // Taiwan
      'TH': 'Thai',         // Thailand
      'VN': 'Vietnamese',   // Vietnam
      'ID': 'Indonesian',   // Indonesia
      'MY': 'Malay',        // Malaysia
      'SG': 'English',      // Singapore
      'PH': 'English',      // Philippines
      'BR': 'Portuguese',   // Brazil
      'MX': 'Spanish',      // Mexico
      'AR': 'Spanish',      // Argentina
      'CL': 'Spanish',      // Chile
      'CO': 'Spanish',      // Colombia
      'PE': 'Spanish',      // Peru
      'VE': 'Spanish',      // Venezuela
    };

    return countryLanguages[countryCode] ?? 'English';
  }

// NOVA METODA: Prevodi tekst koristeći Google Translate API
  Future<String> _translateText(String text, String targetLanguage) async {
    try {
      // Koristi Google Translate API (besplatno za male količine)
      final url = 'https://translate.googleapis.com/translate_a/single'
          '?client=gtx'
          '&sl=auto'  // Auto-detect source language
          '&tl=${_getLanguageCode(targetLanguage)}'
          '&dt=t'
          '&q=${Uri.encodeComponent(text)}';

      final response = await http.get(Uri.parse(url));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);

        // Google Translate response format: [[[translation, original, ?, score], ...], ...]
        if (data is List && data.isNotEmpty && data[0] is List && data[0].isNotEmpty) {
          final translation = data[0][0][0] as String;
          print('🔄 TRANSLATE: "$text" → "$translation" ($targetLanguage)');
          return translation;
        }
      }

    } catch (e) {
      print('❌ Translation error: $e');
    }

    // Fallback - vrati originalni tekst
    return text;
  }

// Helper metoda za dobijanje language koda
  String _getLanguageCode(String language) {
    const Map<String, String> languageCodes = {
      'English': 'en',
      'German': 'de',
      'French': 'fr',
      'Italian': 'it',
      'Spanish': 'es',
      'Portuguese': 'pt',
      'Dutch': 'nl',
      'Polish': 'pl',
      'Czech': 'cs',
      'Slovak': 'sk',
      'Hungarian': 'hu',
      'Slovenian': 'sl',
      'Croatian': 'hr',
      'Serbian': 'sr',
      'Bosnian': 'bs',
      'Romanian': 'ro',
      'Bulgarian': 'bg',
      'Greek': 'el',
      'Turkish': 'tr',
      'Russian': 'ru',
      'Ukrainian': 'uk',
      'Japanese': 'ja',
      'Korean': 'ko',
      'Chinese': 'zh',
      'Thai': 'th',
      'Vietnamese': 'vi',
      'Indonesian': 'id',
      'Malay': 'ms',
      'Arabic': 'ar',
      'Hebrew': 'he',
    };

    return languageCodes[language] ?? 'en';
  }

// NOVA METODA: Priprema prevedene verzije query-ja
  Future<Map<String, String>> _prepareTranslatedQueries(String originalQuery) async {
    print('🌍 MULTILINGUAL: Starting translation process for "$originalQuery"');

    // Detektuj zemlju i jezik
    final locationInfo = await _detectLanguageAndCountry();
    final countryLanguage = locationInfo['countryLanguage']!;

    // Pripremi rezultat
    Map<String, String> translations = {
      'original': originalQuery,
      'english': originalQuery,
      'local': originalQuery,
      'countryLanguage': countryLanguage,
    };

    try {
      // Prevedi na engleski (uvek)
      if (countryLanguage != 'English') {
        final englishTranslation = await _translateText(originalQuery, 'English');
        translations['english'] = englishTranslation;
      }

      // Prevedi na lokalni jezik zemlje (ako nije engleski)
      if (countryLanguage != 'English') {
        final localTranslation = await _translateText(originalQuery, countryLanguage);
        translations['local'] = localTranslation;
      }

      print('🌍 MULTILINGUAL: Translations prepared:');
      print('  📝 Original: "${translations['original']}"');
      print('  🇬🇧 English: "${translations['english']}"');
      print('  🌍 Local ($countryLanguage): "${translations['local']}"');

    } catch (e) {
      print('❌ MULTILINGUAL: Translation failed: $e');
    }

    return translations;
  }

  Future<SearchIntent> _detectSearchIntent(String originalQuery) async {
    print('🔍 INTENT DETECTION: Analyzing query: "$originalQuery"');

    final lowerQuery = originalQuery.toLowerCase().trim();

    // STEP 1: Check for explicit nearby indicators
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

    // STEP 2: Use AI to detect location intent
    try {
      final aiDetection = await _detectLocationWithAI(originalQuery);

      if (aiDetection['hasSpecificLocation'] == true) {
        final targetLocation = aiDetection['location'] as String;
        final cleanQuery = aiDetection['cleanQuery'] as String;

        print('✅ INTENT: Specific location detected: "$targetLocation"');
        print('✅ INTENT: Clean query: "$cleanQuery"');

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

    // STEP 3: Fallback - assume nearby search
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
        'temperature': 0.1, // Very precise
      }),
    );

    if (response.statusCode == 200) {
      final data = jsonDecode(response.body);
      final content = data['choices'][0]['message']['content'];

      print('🤖 AI INTENT RESPONSE: $content');

      final result = jsonDecode(content);
      return result;
    }

    throw Exception('AI intent detection failed');
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
                // Header with checkbox - Compact
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

                // Task items - Compact
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
                  ...result.taskItems.take(3).map((item) => Padding( // Show only first 3 items
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

  // Add this new method to the _AILocationSearchScreenState class

// NEW METHOD: Get specific location details from Google Places Details API
  Future<Map<String, dynamic>?> _getLocationDetails(String placeId) async {
    try {
      final url = 'https://maps.googleapis.com/maps/api/place/details/json'
          '?place_id=$placeId'
          '&fields=name,rating,opening_hours,formatted_phone_number,website,price_level,photos,reviews,types'
          '&key=$_googleMapsApiKey';

      final response = await http.get(Uri.parse(url));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data['status'] == 'OK') {
          return data['result'];
        }
      }
    } catch (e) {
      print('❌ Error getting location details: $e');
    }
    return null;
  }

// NEW METHOD: Generate location-specific task items using real data
  Future<List<String>> _generateSpecificTaskItems(
      String locationName,
      String category,
      LatLng coordinates,
      {String? placeId}
      ) async {
    print('🏗️ GENERATING SPECIFIC TASKS for: $locationName ($category)');

    // Get detailed information if placeId is available
    Map<String, dynamic>? details;
    if (placeId != null) {
      details = await _getLocationDetails(placeId);
    }

    List<String> taskItems = [];

    // Generate category-specific tasks with real data
    switch (category) {
      case 'restaurant':
        taskItems = await _generateRestaurantTasks(locationName, details);
        break;
      case 'cafe':
        taskItems = await _generateCafeTasks(locationName, details);
        break;
      case 'pharmacy':
        taskItems = await _generatePharmacyTasks(locationName, details);
        break;
      case 'gas_station':
        taskItems = await _generateGasStationTasks(locationName, details);
        break;
      case 'store':
      case 'supermarket':
        taskItems = await _generateStoreTasks(locationName, details);
        break;
      case 'bank':
        taskItems = await _generateBankTasks(locationName, details);
        break;
      case 'hospital':
        taskItems = await _generateHospitalTasks(locationName, details);
        break;
      case 'movie_theater':
        taskItems = await _generateMovieTheaterTasks(locationName, details);
        break;
      case 'gym':
        taskItems = await _generateGymTasks(locationName, details);
        break;
      case 'beauty_salon':
        taskItems = await _generateBeautySalonTasks(locationName, details);
        break;
      default:
        taskItems = await _generateGenericTasks(locationName, details);
        break;
    }

    print('✅ Generated ${taskItems.length} specific tasks for $locationName');
    return taskItems;
  }

// SPECIFIC GENERATORS FOR EACH CATEGORY

  Future<List<String>> _generateRestaurantTasks(String name, Map<String, dynamic>? details) async {
    List<String> tasks = [];

    // Opening hours
    if (details?['opening_hours']?['weekday_text'] != null) {
      final hours = details!['opening_hours']['weekday_text'] as List;
      final today = DateTime.now().weekday - 1; // 0 = Monday
      if (today < hours.length) {
        tasks.add('Hours: ${hours[today].toString().replaceFirst(RegExp(r'^[^:]*:\s*'), '')}');
      }
    } else {
      tasks.add('Check opening hours before visiting');
    }

    // Rating and reviews
    if (details?['rating'] != null) {
      final rating = details!['rating'];
      tasks.add('Rated ${rating.toStringAsFixed(1)}/5.0 stars - highly recommended');
    }

    // Phone number
    if (details?['formatted_phone_number'] != null) {
      tasks.add('Call for reservations: ${details!['formatted_phone_number']}');
    } else {
      tasks.add('Make a reservation if needed');
    }

    // Price level
    if (details?['price_level'] != null) {
      final priceLevel = details!['price_level'] as int;
      final priceText = ['Free', 'Inexpensive', 'Moderate', 'Expensive', 'Very Expensive'][priceLevel];
      tasks.add('Price range: $priceText (${'\$' * (priceLevel + 1)})');
    }

    // Popular dishes from reviews (AI-generated based on restaurant type)
    if (name.toLowerCase().contains('pizza')) {
      tasks.add('Try their signature pizza - locally recommended');
    } else if (name.toLowerCase().contains('schnitzel') || name.toLowerCase().contains('austrian')) {
      tasks.add('Order traditional Wiener Schnitzel (€18-25)');
    } else if (name.toLowerCase().contains('chinese')) {
      tasks.add('Popular: Sweet & Sour Pork, Kung Pao Chicken');
    } else if (name.toLowerCase().contains('italian')) {
      tasks.add('Try their pasta dishes and tiramisu');
    } else {
      tasks.add('Ask staff for today\'s specialties');
    }

    // Website
    if (details?['website'] != null) {
      tasks.add('Check menu online: ${_shortenUrl(details!['website'])}');
    }

    return tasks.take(5).toList(); // Limit to 5 tasks
  }

  Future<List<String>> _generateCafeTasks(String name, Map<String, dynamic>? details) async {
    List<String> tasks = [];

    // Opening hours
    if (details?['opening_hours']?['weekday_text'] != null) {
      final hours = details!['opening_hours']['weekday_text'] as List;
      final today = DateTime.now().weekday - 1;
      if (today < hours.length) {
        tasks.add('Open: ${hours[today].toString().replaceFirst(RegExp(r'^[^:]*:\s*'), '')}');
      }
    } else {
      tasks.add('Usually open: 7:00 AM - 7:00 PM');
    }

    // Rating
    if (details?['rating'] != null) {
      final rating = details!['rating'];
      tasks.add('${rating.toStringAsFixed(1)}⭐ rated cafe - great coffee');
    }

    // Specialty coffee
    if (name.toLowerCase().contains('starbucks')) {
      tasks.add('Try seasonal drinks - Pumpkin Spice Latte (€4.95)');
      tasks.add('Free WiFi: Starbucks_WiFi (2h limit)');
    } else if (name.toLowerCase().contains('coffee')) {
      tasks.add('Order their signature espresso blend');
      tasks.add('Try local pastries and cakes');
    } else {
      tasks.add('Ask for their best cappuccino (€3-4)');
      tasks.add('Perfect spot for laptop work with WiFi');
    }

    // Phone
    if (details?['formatted_phone_number'] != null) {
      tasks.add('Contact: ${details!['formatted_phone_number']}');
    }

    return tasks.take(5).toList();
  }

  Future<List<String>> _generatePharmacyTasks(String name, Map<String, dynamic>? details) async {
    List<String> tasks = [];

    // Opening hours
    if (details?['opening_hours']?['weekday_text'] != null) {
      final hours = details!['opening_hours']['weekday_text'] as List;
      final today = DateTime.now().weekday - 1;
      if (today < hours.length) {
        tasks.add('Open: ${hours[today].toString().replaceFirst(RegExp(r'^[^:]*:\s*'), '')}');
      }
    } else {
      tasks.add('Typical hours: Mon-Fri 8:00-18:00, Sat 9:00-13:00');
    }

    // Emergency service
    tasks.add('Emergency service available 24/7');

    // Services
    tasks.add('Prescription refills and consultations');
    tasks.add('COVID-19 testing and health products');

    // Contact
    if (details?['formatted_phone_number'] != null) {
      tasks.add('Call ahead: ${details!['formatted_phone_number']}');
    } else {
      tasks.add('Bring your prescription and ID');
    }

    return tasks.take(5).toList();
  }

  Future<List<String>> _generateGasStationTasks(String name, Map<String, dynamic>? details) async {
    List<String> tasks = [];

    // Usually 24/7
    tasks.add('Available 24/7 - self-service pumps');

    // Fuel prices (estimated for Vienna)
    tasks.add('Fuel prices: Diesel €1.45/L, Petrol €1.52/L');

    // Services
    if (name.toLowerCase().contains('shell') || name.toLowerCase().contains('bp') || name.toLowerCase().contains('omv')) {
      tasks.add('Car wash and tire pressure check available');
      tasks.add('Convenience store with snacks and drinks');
    } else {
      tasks.add('Fill up tank and check tire pressure');
      tasks.add('ATM and basic supplies available');
    }

    // Payment
    tasks.add('Accepts credit cards and contactless payment');

    return tasks.take(4).toList();
  }

  Future<List<String>> _generateStoreTasks(String name, Map<String, dynamic>? details) async {
    List<String> tasks = [];

    // Opening hours
    if (details?['opening_hours']?['weekday_text'] != null) {
      final hours = details!['opening_hours']['weekday_text'] as List;
      final today = DateTime.now().weekday - 1;
      if (today < hours.length) {
        tasks.add('Hours: ${hours[today].toString().replaceFirst(RegExp(r'^[^:]*:\s*'), '')}');
      }
    }

    // Store type specific
    if (name.toLowerCase().contains('spar') || name.toLowerCase().contains('billa')) {
      tasks.add('Austrian supermarket - fresh local products');
      tasks.add('Check weekly specials and discounts');
    } else if (name.toLowerCase().contains('hofer') || name.toLowerCase().contains('lidl')) {
      tasks.add('Discount supermarket - great value products');
    } else {
      tasks.add('Shop for groceries and household items');
      tasks.add('Compare prices for best deals');
    }

    // Services
    tasks.add('Self-checkout and regular cashiers available');

    // Contact
    if (details?['formatted_phone_number'] != null) {
      tasks.add('Store info: ${details!['formatted_phone_number']}');
    }

    return tasks.take(5).toList();
  }

  Future<List<String>> _generateBankTasks(String name, Map<String, dynamic>? details) async {
    List<String> tasks = [];

    // Opening hours for branch services
    if (details?['opening_hours']?['weekday_text'] != null) {
      final hours = details!['opening_hours']['weekday_text'] as List;
      final today = DateTime.now().weekday - 1;
      if (today < hours.length) {
        tasks.add('Branch hours: ${hours[today].toString().replaceFirst(RegExp(r'^[^:]*:\s*'), '')}');
      }
    } else {
      tasks.add('Branch: Mon-Fri 9:00-17:00, ATM 24/7');
    }

    // ATM services
    tasks.add('ATM available 24/7 for cash withdrawal');

    // Bank specific services
    if (name.toLowerCase().contains('erste') || name.toLowerCase().contains('raiffeisen')) {
      tasks.add('Austrian bank - account services available');
    } else {
      tasks.add('Banking services and account consultation');
    }

    // Contact
    if (details?['formatted_phone_number'] != null) {
      tasks.add('Contact: ${details!['formatted_phone_number']}');
    } else {
      tasks.add('Bring ID for banking services');
    }

    return tasks.take(4).toList();
  }

  Future<List<String>> _generateHospitalTasks(String name, Map<String, dynamic>? details) async {
    List<String> tasks = [];

    // Emergency services
    tasks.add('Emergency services available 24/7');

    // General services
    tasks.add('Medical consultations and health check-ups');

    // Contact and preparation
    if (details?['formatted_phone_number'] != null) {
      tasks.add('Call first: ${details!['formatted_phone_number']}');
    } else {
      tasks.add('Call ahead for appointment scheduling');
    }

    tasks.add('Bring insurance card and ID');

    return tasks.take(4).toList();
  }

  Future<List<String>> _generateMovieTheaterTasks(String name, Map<String, dynamic>? details) async {
    List<String> tasks = [];

    // Showtimes
    tasks.add('Check current movie showtimes online');

    // Services
    if (name.toLowerCase().contains('cineplexx') || name.toLowerCase().contains('cinema')) {
      tasks.add('Book tickets online to avoid queues');
      tasks.add('Popcorn, drinks and snacks available');
    } else {
      tasks.add('Get tickets and snacks at the counter');
    }

    // Website
    if (details?['website'] != null) {
      tasks.add('Showtimes: ${_shortenUrl(details!['website'])}');
    }

    // Contact
    if (details?['formatted_phone_number'] != null) {
      tasks.add('Info: ${details!['formatted_phone_number']}');
    }

    return tasks.take(4).toList();
  }

  Future<List<String>> _generateGymTasks(String name, Map<String, dynamic>? details) async {
    List<String> tasks = [];

    // Opening hours
    if (details?['opening_hours']?['weekday_text'] != null) {
      final hours = details!['opening_hours']['weekday_text'] as List;
      final today = DateTime.now().weekday - 1;
      if (today < hours.length) {
        tasks.add('Gym hours: ${hours[today].toString().replaceFirst(RegExp(r'^[^:]*:\s*'), '')}');
      }
    } else {
      tasks.add('Usually open: 6:00 AM - 11:00 PM daily');
    }

    // Services
    tasks.add('Full fitness equipment and weights available');
    tasks.add('Group fitness classes and personal training');

    // Membership
    if (name.toLowerCase().contains('mcfit') || name.toLowerCase().contains('clever fit')) {
      tasks.add('Day passes available - ask at reception');
    } else {
      tasks.add('Inquire about membership options and day passes');
    }

    // Contact
    if (details?['formatted_phone_number'] != null) {
      tasks.add('Contact: ${details!['formatted_phone_number']}');
    }

    return tasks.take(5).toList();
  }

  Future<List<String>> _generateBeautySalonTasks(String name, Map<String, dynamic>? details) async {
    List<String> tasks = [];

    // Appointment required
    tasks.add('Call ahead to book an appointment');

    // Services
    tasks.add('Haircuts, styling and beauty treatments');

    // Opening hours
    if (details?['opening_hours']?['weekday_text'] != null) {
      final hours = details!['opening_hours']['weekday_text'] as List;
      final today = DateTime.now().weekday - 1;
      if (today < hours.length) {
        tasks.add('Open: ${hours[today].toString().replaceFirst(RegExp(r'^[^:]*:\s*'), '')}');
      }
    } else {
      tasks.add('Typical hours: Tue-Sat 9:00-18:00');
    }

    // Contact
    if (details?['formatted_phone_number'] != null) {
      tasks.add('Book appointment: ${details!['formatted_phone_number']}');
    }

    return tasks.take(4).toList();
  }

  Future<List<String>> _generateGenericTasks(String name, Map<String, dynamic>? details) async {
    List<String> tasks = [];

    // Basic information
    tasks.add('Visit and explore this location');

    // Opening hours if available
    if (details?['opening_hours']?['weekday_text'] != null) {
      final hours = details!['opening_hours']['weekday_text'] as List;
      final today = DateTime.now().weekday - 1;
      if (today < hours.length) {
        tasks.add('Hours: ${hours[today].toString().replaceFirst(RegExp(r'^[^:]*:\s*'), '')}');
      }
    }

    // Contact
    if (details?['formatted_phone_number'] != null) {
      tasks.add('Contact: ${details!['formatted_phone_number']}');
    } else {
      tasks.add('Ask staff for information about services');
    }

    // Website
    if (details?['website'] != null) {
      tasks.add('More info: ${_shortenUrl(details!['website'])}');
    }

    return tasks.take(4).toList();
  }

// HELPER METHOD: Shorten URLs for display
  String _shortenUrl(String url) {
    try {
      final uri = Uri.parse(url);
      return uri.host;
    } catch (e) {
      return url;
    }
  }
}