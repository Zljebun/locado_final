import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/task_location.dart';

/// Hybrid cache system for TaskLocation objects
/// Combines memory cache (instant access) with SharedPreferences (persistent cache)
/// to dramatically speed up app startup and data loading
class TaskLocationCache {
  static TaskLocationCache? _instance;
  static TaskLocationCache get instance => _instance ??= TaskLocationCache._();
  
  TaskLocationCache._();

  // Memory cache for instant access (0ms latency)
  List<TaskLocation>? _memoryCache;
  DateTime? _lastMemoryUpdate;
  
  // SharedPreferences cache keys
  static const String _cacheKey = 'cached_task_locations_v1';
  static const String _cacheTimestampKey = 'cache_timestamp_v1';
  static const String _cacheVersionKey = 'cache_version_v1';
  static const int _currentCacheVersion = 1;
  
  // Cache configuration
  static const Duration _memoryExpiry = Duration(minutes: 10);
  static const Duration _diskExpiry = Duration(hours: 24);

  /// Get tasks instantly from cache (memory first, then SharedPreferences)
  /// Returns empty list if no cache available - UI can show immediately
  Future<List<TaskLocation>> getInstantTasks() async {
    try {
      // Step 1: Try memory cache first (0ms access)
      if (_isMemoryCacheValid()) {
        print('✅ CACHE: Using memory cache (${_memoryCache!.length} tasks)');
        return List.from(_memoryCache!); // Return copy to prevent modifications
      }

      // Step 2: Try SharedPreferences cache (1-5ms access)
      final diskTasks = await _loadFromDisk();
      if (diskTasks.isNotEmpty) {
        _memoryCache = List.from(diskTasks);
        _lastMemoryUpdate = DateTime.now();
        print('✅ CACHE: Loaded from disk cache (${diskTasks.length} tasks)');
        return diskTasks;
      }

      // Step 3: No cache available - return empty list for instant UI
      print('ℹ️ CACHE: No cache available, returning empty list for instant UI');
      return [];
      
    } catch (e) {
      print('❌ CACHE: Error loading cache: $e');
      return []; // Always return empty list, never block UI
    }
  }

  /// Update cache with fresh data from database
  /// This syncs both memory and disk cache - NON-BLOCKING for UI thread
  Future<void> updateCache(List<TaskLocation> tasks) async {
    try {
      // Update memory cache immediately (instant)
      _memoryCache = List.from(tasks);
      _lastMemoryUpdate = DateTime.now();
      
      print('✅ CACHE: Updated memory cache with ${tasks.length} tasks');
      
      // Update disk cache in background - DON'T AWAIT to avoid blocking UI
      _saveToDiskInBackground(tasks);
      
    } catch (e) {
      print('❌ CACHE: Error updating cache: $e');
      // Don't throw error - cache failure shouldn't break app
    }
  }

  /// Add single task to cache (when user creates new task)
  Future<void> addTaskToCache(TaskLocation task) async {
    try {
      if (_memoryCache != null) {
        _memoryCache!.add(task);
        _lastMemoryUpdate = DateTime.now();
        
        // Save to disk in background - non-blocking
        _saveToDiskInBackground(_memoryCache!);
        
        print('✅ CACHE: Added single task to cache: ${task.title}');
      }
    } catch (e) {
      print('❌ CACHE: Error adding task to cache: $e');
    }
  }

  /// Remove task from cache (when user deletes task)
  Future<void> removeTaskFromCache(int taskId) async {
    try {
      if (_memoryCache != null) {
        _memoryCache!.removeWhere((task) => task.id == taskId);
        _lastMemoryUpdate = DateTime.now();
        
        // Save to disk in background - non-blocking
        _saveToDiskInBackground(_memoryCache!);
        
        print('✅ CACHE: Removed task from cache: $taskId');
      }
    } catch (e) {
      print('❌ CACHE: Error removing task from cache: $e');
    }
  }

  /// Update specific task in cache (when user edits task)
  Future<void> updateTaskInCache(TaskLocation updatedTask) async {
    try {
      if (_memoryCache != null) {
        final index = _memoryCache!.indexWhere((task) => task.id == updatedTask.id);
        if (index != -1) {
          _memoryCache![index] = updatedTask;
          _lastMemoryUpdate = DateTime.now();
          
          // Save to disk in background - non-blocking
          _saveToDiskInBackground(_memoryCache!);
          
          print('✅ CACHE: Updated task in cache: ${updatedTask.title}');
        }
      }
    } catch (e) {
      print('❌ CACHE: Error updating task in cache: $e');
    }
  }

  /// Clear all cache (for debugging or reset)
  Future<void> clearCache() async {
    try {
      _memoryCache = null;
      _lastMemoryUpdate = null;
      
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_cacheKey);
      await prefs.remove(_cacheTimestampKey);
      
      print('✅ CACHE: Cache cleared');
    } catch (e) {
      print('❌ CACHE: Error clearing cache: $e');
    }
  }

  /// Get cache statistics for debugging
  Map<String, dynamic> getCacheStats() {
    return {
      'memoryCache': _memoryCache?.length ?? 0,
      'memoryCacheValid': _isMemoryCacheValid(),
      'lastMemoryUpdate': _lastMemoryUpdate?.toIso8601String(),
    };
  }

  // Private helper methods

  /// Check if memory cache is valid and not expired
  bool _isMemoryCacheValid() {
    if (_memoryCache == null || _lastMemoryUpdate == null) {
      return false;
    }
    
    final now = DateTime.now();
    final isExpired = now.difference(_lastMemoryUpdate!) > _memoryExpiry;
    return !isExpired;
  }

  /// Load tasks from SharedPreferences
  Future<List<TaskLocation>> _loadFromDisk() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      
      // Check cache version compatibility
      final cacheVersion = prefs.getInt(_cacheVersionKey) ?? 0;
      if (cacheVersion != _currentCacheVersion) {
        print('ℹ️ CACHE: Cache version mismatch, clearing old cache');
        await _clearDiskCache(prefs);
        return [];
      }
      
      // Check if cache is expired
      final timestampStr = prefs.getString(_cacheTimestampKey);
      if (timestampStr != null) {
        final timestamp = DateTime.parse(timestampStr);
        final isExpired = DateTime.now().difference(timestamp) > _diskExpiry;
        if (isExpired) {
          print('ℹ️ CACHE: Disk cache expired, clearing');
          await _clearDiskCache(prefs);
          return [];
        }
      }
      
      // Load cached tasks
      final jsonString = prefs.getString(_cacheKey);
      if (jsonString == null || jsonString.isEmpty) {
        return [];
      }
      
      final List<dynamic> jsonList = json.decode(jsonString);
      final tasks = jsonList.map((json) => TaskLocation.fromMap(json)).toList();
      
      return tasks;
      
    } catch (e) {
      print('❌ CACHE: Error loading from disk: $e');
      return [];
    }
  }

  /// Save tasks to SharedPreferences in background - NON-BLOCKING
  void _saveToDiskInBackground(List<TaskLocation> tasks) {
    // Execute disk save in background without blocking UI thread
    Future.delayed(const Duration(milliseconds: 50), () async {
      await _saveToDisk(tasks);
    });
  }

  /// Save tasks to SharedPreferences
  Future<void> _saveToDisk(List<TaskLocation> tasks) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      
      // Serialize tasks to JSON
      final jsonList = tasks.map((task) => task.toMap()).toList();
      final jsonString = json.encode(jsonList);
      
      // Save to SharedPreferences
      await prefs.setString(_cacheKey, jsonString);
      await prefs.setString(_cacheTimestampKey, DateTime.now().toIso8601String());
      await prefs.setInt(_cacheVersionKey, _currentCacheVersion);
      
    } catch (e) {
      print('❌ CACHE: Error saving to disk: $e');
      // Don't rethrow - cache save failure shouldn't break app
    }
  }

  /// Clear disk cache
  Future<void> _clearDiskCache(SharedPreferences prefs) async {
    await prefs.remove(_cacheKey);
    await prefs.remove(_cacheTimestampKey);
    await prefs.remove(_cacheVersionKey);
  }
}