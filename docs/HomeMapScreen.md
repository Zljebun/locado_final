# 🗺️ Locado - HomeMapScreen Documentation

[![Flutter](https://img.shields.io/badge/Flutter-02569B?style=for-the-badge&logo=flutter&logoColor=white)](https://flutter.dev)
[![Dart](https://img.shields.io/badge/Dart-0175C2?style=for-the-badge&logo=dart&logoColor=white)](https://dart.dev)
[![Google Maps](https://img.shields.io/badge/Google%20Maps-4285F4?style=for-the-badge&logo=googlemaps&logoColor=white)](https://developers.google.com/maps)

> **Smart location-based task management with intelligent geofencing**

## 📋 Overview

The `HomeMapScreen` is the core component of the Locado application - a sophisticated location-based task management system with intelligent geofencing capabilities. This screen provides users with an interactive Google Maps interface where they can view, create, and manage location-based tasks with real-time notifications.

## ✨ Key Features

| Feature | Description | Status |
|---------|-------------|--------|
| 🗺️ **Interactive Map** | Google Maps with custom markers & real-time tracking | ✅ Active |
| 📍 **Smart Geofencing** | Location-based notifications & background processing | ✅ Active |
| 🔍 **Places Search** | Google Places API integration for location discovery | ✅ Active |
| 🔋 **Battery Optimization** | Intelligent power management with user education | ✅ Active |
| 📱 **Wake Screen Alerts** | Full-screen notifications that wake the device | ✅ Active |
| 🎯 **Auto-Focus Camera** | Optional camera tracking following user movement | ✅ Active |

### 🗺️ Interactive Map Interface
- ✅ **Google Maps Integration** - Full-featured map with custom markers
- ✅ **Location-Based Tasks** - Create, view, and edit tasks directly on map
- ✅ **Real-Time Tracking** - Automatic camera following (optional)
- ✅ **Custom Markers** - Color-coded task markers with titles

### 📍 Geofencing System
- ⚡ **Smart Notifications** - Automated alerts when approaching tasks
- 🔄 **Background Processing** - Continues working when app is closed
- 🔋 **Battery Optimization** - Intelligent power management
- 📢 **Wake Screen Alerts** - Full-screen notifications

### 🔍 Search & Navigation
- 🌐 **Google Places** - Search locations using Google Places API
- 📏 **Proximity Sorting** - Tasks sorted by distance from current location
- 🎯 **Auto-Focus** - Camera tracking that follows user movement
- 👆 **Manual Focus** - Focus on specific tasks from external triggers

## 🏗️ Architecture

### Class Structure

```mermaid
classDiagram
    class HomeMapScreen {
        +GoogleMapController _mapController
        +Set~Marker~ _markers
        +List~TaskLocation~ _savedLocations
        +LatLng _currentLocation
        +performSearch(String searchTerm)
        +focusOnTaskLocation(TaskLocation task)
        +_handleGeofenceEvent(GeofenceEvent event)
    }
    
    class TaskWithDistance {
        +TaskLocation task
        +double distance
    }
    
    HomeMapScreen --> TaskWithDistance
    HomeMapScreen --> GeofencingScreenMixin
    HomeMapScreen --> TickerProviderStateMixin
```

### 🧩 Core Components

<details>
<summary><b>📱 State Management Variables</b></summary>

#### Map & Location Management
- `GoogleMapController _mapController` - Controls map operations
- `Set<Marker> _markers` - All map markers (tasks, locations, search results)  
- `LatLng? _currentLocation` - User's current position
- `bool _isMapReady` - Map initialization status
- `bool _autoFocusEnabled` - Auto-camera following toggle

#### Task & Location Data  
- `List<TaskLocation> _savedLocations` - All user tasks
- `List<TaskLocation> _nearbyTasks` - Tasks within notification range
- `Set<Marker> _searchMarkers` - Search result markers
- `TaskLocation? _lastAddedTask` - Recently created task for focus

#### Geofencing & Notifications
- `FlutterLocalNotificationsPlugin _flutterLocalNotificationsPlugin`
- `int _notificationDistance` - Geofence radius (default: 100m)
- `bool _isAppInForeground` - App lifecycle state

</details>

## 🚀 Key Methods

### 🎯 Initialization & Performance

<table>
<tr>
<td width="50%">

#### Two-Phase Loading Strategy
```dart
// Phase 1: Immediate UI ⚡
void _setupImmediateUI() {
  // Remove loading spinner instantly
  // Setup essential listeners  
  // Initialize animations
  setState(() => _isLoading = false);
}

// Phase 2: Background Loading 🔄
Future<void> _initializeEverythingAsync() {
  // Parallel execution of heavy operations
  // Permissions, notifications, data loading
}
```

</td>
<td width="50%">

#### Optimized Data Loading
```dart
Future<void> _fastLoadBasicLocations() {
  // 1. Load basic markers first (faster)
  await _createBasicMarkers();
  
  // 2. Upgrade to custom markers later
  _upgradeToCustomMarkersLater();
  
  // 3. Sync geofencing in background
  syncTaskLocationsFromScreen();
}
```

</td>
</tr>
</table>

### 🗺️ Map Operations

<details>
<summary><b>🎨 Custom Marker Creation</b></summary>

```dart
Future<BitmapDescriptor> createCustomMarker(String title, Color color) async {
  final ui.PictureRecorder recorder = ui.PictureRecorder();
  final Canvas canvas = Canvas(recorder);
  
  // Create circular marker with:
  // ✅ Custom color
  // ✅ Text overlay  
  // ✅ Drop shadow
  // ✅ Triangular pointer
  
  return BitmapDescriptor.fromBytes(byteData.buffer.asUint8List());
}
```

**Visual Result:**
```
    ┌─────────────┐
    │   📍 Task   │  ← Custom colored circle with title
    │   Title     │
    └──────┬──────┘
           ▼            ← Triangular pointer
```

</details>

<details>
<summary><b>🎯 Smart Focus Management</b></summary>

```dart
// External focus requests (from other screens)
Future<void> focusOnTaskLocation(TaskLocation task) async {
  _isManuallyFocusing = true;  // Prevent auto-focus interference
  
  await _mapController.animateCamera(/* smooth animation */);
  
  // Clear flag after 5 seconds
  Future.delayed(Duration(seconds: 5), () => _isManuallyFocusing = false);
}

// Auto-focus following user movement  
void _handleLocationUpdate(Position position) {
  if (_isManuallyFocusing) return;  // Respect manual override
  
  // Update camera only on significant movement (>20m)
  if (distance > 20) {
    _mapController.animateCamera(/* follow user */);
  }
}
```

</details>

### 📍 Geofencing & Notifications

<details>
<summary><b>⚡ Smart Geofence Events</b></summary>

```dart
void _handleGeofenceEvent(GeofenceEvent event) {
  if (event.eventType == GeofenceEventType.enter) {
    _showViberStyleAlert(event);  // Wake screen alert
  }
}

// Advanced notification system
Future<void> _showViberStyleAlert(GeofenceEvent event) async {
  try {
    // Try platform-specific lock screen alert
    await platformLockScreen.invokeMethod('showLockScreenAlert', {
      'taskTitle': event.title,
      'taskMessage': 'You are near: ${event.title}',
    });
  } catch (e) {
    // Fallback to regular notification
    await _showRegularWakeNotification(event);
  }
}
```

</details>

### 🔋 Battery Optimization

<details>
<summary><b>🧠 Intelligent Battery Management</b></summary>

```dart
Future<void> _checkBatteryOptimizationSmart() async {
  // Smart timing - max once per 3 days
  if (!_shouldShowBatteryWarning()) return;
  
  // Check if app needs whitelist
  final result = await _geofenceChannel.invokeMethod('checkBatteryOptimization');
  final needsWhitelist = !(result['isWhitelisted'] ?? false);
  
  if (!needsWhitelist || !isGeofencingEnabled) return;
  
  // Show educational dialog
  _showBatteryOptimizationWarning();
}
```

**User Education Dialog:**
- 📊 Current optimization status
- ✅ Benefits of whitelist (24/7 notifications)  
- ⚠️ Consequences of not optimizing
- 🎯 Clear action buttons

</details>

### 🔍 Search Integration

<details>
<summary><b>🌐 Google Places Search</b></summary>

```dart
Future<void> performSearch(String searchTerm) async {
  final url = 'https://maps.googleapis.com/maps/api/place/nearbysearch/json'
      '?location=${searchCenter.latitude},${searchCenter.longitude}'
      '&radius=5000'
      '&keyword=${Uri.encodeComponent(searchTerm)}'
      '&key=$googleApiKey';

  // Create interactive markers for results
  for (final place in results) {
    searchMarkers.add(Marker(
      onTap: () => _createTaskAtLocation(place),
      // ... marker configuration
    ));
  }
}
```

**Search Flow:**
1. 🔍 User enters search term
2. 🌐 Query Google Places API (5km radius)
3. 📍 Display results as red markers  
4. 👆 Tap marker → Create task at location

</details>

## 🔧 Configuration & Dependencies

### 📊 Constants & API Keys

```dart
// Google Services
static const String googleApiKey = 'AIzaSyBdJmp8SVJTnDBgfYW8fXXErbW1HevZ2q4';

// Platform Channels
static const platformLockScreen = MethodChannel('locado.lockscreen/channel');
static const MethodChannel _geofenceChannel = MethodChannel('com.example.locado_final/geofence');
```

### 📦 Dependencies

<table>
<tr>
<th>Category</th>
<th>Package</th>
<th>Purpose</th>
</tr>
<tr>
<td rowspan="4"><b>🗺️ Maps & Location</b></td>
<td><code>google_maps_flutter</code></td>
<td>Interactive map interface</td>
</tr>
<tr>
<td><code>geolocator</code></td>
<td>Location services & positioning</td>
</tr>
<tr>
<td><code>permission_handler</code></td>
<td>Runtime permission management</td>
</tr>
<tr>
<td><code>http</code></td>
<td>Google Places API communication</td>
</tr>
<tr>
<td rowspan="2"><b>🔔 Notifications</b></td>
<td><code>flutter_local_notifications</code></td>
<td>Local notification system</td>
</tr>
<tr>
<td><code>shared_preferences</code></td>
<td>Settings & user preferences</td>
</tr>
<tr>
<td rowspan="4"><b>🏗️ Custom Services</b></td>
<td><code>GeofencingIntegrationHelper</code></td>
<td>Geofencing management</td>
</tr>
<tr>
<td><code>LocationService</code></td>
<td>Location utilities & caching</td>
</tr>
<tr>
<td><code>DatabaseHelper</code></td>
<td>SQLite data persistence</td>
</tr>
<tr>
<td><code>LocadoBackgroundService</code></td>
<td>Background task processing</td>
</tr>
</table>

## ⚡ Performance Optimizations

### 🚀 Loading Strategy

```mermaid
graph LR
    A[App Start] --> B[Immediate UI]
    B --> C[Remove Loading Spinner]
    C --> D[Background Loading]
    D --> E[Basic Markers]
    E --> F[Custom Markers]
    F --> G[Geofencing Sync]
    
    style A fill:#e1f5fe
    style C fill:#c8e6c9
    style G fill:#fff3e0
```

### 🎯 Marker Optimization

| Phase | Type | Performance | Visual Quality |
|-------|------|-------------|----------------|
| **Phase 1** | Basic Markers | ⚡ **Instant** | 📊 Standard |
| **Phase 2** | Custom Markers | 🔄 Background | 🎨 **Premium** |

```dart
// Phase 1: Immediate display
Marker(markerId: MarkerId('task_${task.id}'), /* basic config */);

// Phase 2: Enhanced visuals (background)
Future.delayed(Duration(milliseconds: 300), () async {
  final customIcon = await createCustomMarker(task.title, color);
  // Update marker with custom icon
});
```

### 📍 Location Tracking Efficiency

<details>
<summary><b>🎛️ Intelligent Filtering</b></summary>

```dart
// Location Stream Configuration
const LocationSettings locationSettings = LocationSettings(
  accuracy: LocationAccuracy.high,
  distanceFilter: 10,  // Update every 10 meters only
);

// Camera Update Logic  
void _handleLocationUpdate(Position position) {
  // Only update camera on significant movement
  final distance = _calculateDistance(/*...*/);
  
  if (distance > 20) {  // 20m threshold
    _mapController.animateCamera(/*...*/);
  }
}
```

**Benefits:**
- 🔋 **Battery Efficient** - Reduces unnecessary updates
- 📱 **Performance** - Prevents UI stuttering  
- 🎯 **Smart Tracking** - Updates only when meaningful

</details>

### 🧠 Battery Intelligence

<details>
<summary><b>⚡ Smart Battery Management</b></summary>

```dart
// Intelligent Warning System
bool _shouldShowBatteryWarning() {
  // Show max once per 3 days
  if (_hasShownBatteryWarning) return false;
  
  final daysSinceLastShown = DateTime.now()
      .difference(_lastBatteryCheck ?? DateTime.now())
      .inDays;
      
  return daysSinceLastShown >= 3;
}
```

**Strategy:**
- ⏰ **Timing-Based** - Prevents warning spam
- 🎯 **Context-Aware** - Only when geofencing is active
- 🔕 **Silent Failures** - Never interrupts startup
- 📚 **Educational** - Explains benefits, not just requests

</details>

## 💡 Usage Patterns & Best Practices

### 🎯 Creating Tasks

```mermaid
flowchart TD
    A[User Action] --> B{Method}
    B -->|Long Press| C[Map Location]
    B -->|Search| D[Places API]
    B -->|External| E[Navigation]
    
    C --> F[TaskInputScreen]
    D --> G[Tap Result] --> F
    E --> H[Location Data] --> F
    
    F --> I[Save Task] --> J[Focus on New Task]
    
    style A fill:#e3f2fd
    style J fill:#c8e6c9
```

### 📱 Managing Tasks

<table>
<tr>
<td width="50%">

#### 👆 **Task Interaction**
```dart
// Tap task marker
onTap: () => _handleTaskTap(task)

// Results handling
if (result == true) {
  await _loadSavedLocationsWithRefresh();
} else if (result is Map && result['refresh']) {
  await _loadSavedLocationsWithRefresh();
  await _focusOnNewLocation(result['focusLocation']);
}
```

</td>
<td width="50%">

#### 🔍 **Location Search Flow**
```dart
// From TaskDetail: Edit location
result['action'] == 'openLocationSearchForEdit'

// Set search mode
_isSearchingForTaskInput = true;
_pendingTaskState = result['taskState'];

// User selects new location
_returnToTaskDetailWithLocation(location, name);
```

</td>
</tr>
</table>

### 📍 **Geofencing Lifecycle**

```dart
// 1. Task Creation
Task created → Geofence registered → Background monitoring starts

// 2. Location Approach  
User enters radius → GeofenceEvent.enter → Wake screen alert

// 3. Task Completion
Task completed → Geofence removed → Resources freed
```

## 🔗 Integration Points

### 🌐 **External Communication**

| Source | Data | Action |
|--------|------|--------|
| **TaskInputScreen** | `location: LatLng` | Create new task |
| **TaskDetailScreen** | `refresh: true` | Reload and focus |
| **MainNavigationScreen** | `searchTerm: String` | Perform places search |
| **NotificationSystem** | `taskId: String` | Navigate to task |

### 🗄️ **Database Operations**

```dart
// Real-time synchronization
await DatabaseHelper.instance.getAllTaskLocations()  // Load tasks
await syncTaskLocationsFromScreen(_savedLocations)   // Sync geofences  
await _checkBatteryOptimizationForFAB()             // Update UI state
```

### 🔔 **Background Services**

```dart
// Service integration
LocadoBackgroundService.setGeofenceEventListener(_handleGeofenceEvent);
GeofencingIntegrationHelper.instance.initializeGeofencing(
  onGeofenceEvent: _handleGeofenceEvent,
);
```

---

## 🚀 Quick Start

### 📋 Prerequisites
- Flutter SDK 3.0+
- Google Maps API key
- Android/iOS location permissions
- Firebase (for notifications)

### ⚙️ Setup
1. **Configure API key** in `google_api_key` constant
2. **Set platform channels** for native functionality  
3. **Initialize permissions** in app startup
4. **Configure notification channels** for geofencing

### 🎯 Key Integration
```dart
// In your main navigation
HomeMapScreen(selectedLocation: coordinates)

// For search functionality  
homeMapScreen.performSearch("coffee shop")

// For task focus
homeMapScreen.focusOnTaskLocation(task)
```

---

<div align="center">

**Built with ❤️ for smart location management**

[![Flutter](https://img.shields.io/badge/Made%20with-Flutter-blue?logo=flutter)](https://flutter.dev)
[![Dart](https://img.shields.io/badge/Language-Dart-blue?logo=dart)](https://dart.dev)

</div>