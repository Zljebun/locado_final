package com.example.locado_final

import android.Manifest
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.util.Log
import androidx.core.app.ActivityCompat
import com.google.android.gms.location.*
import com.google.android.gms.tasks.Task
import com.google.android.gms.common.api.ApiException
import com.google.android.libraries.places.api.Places
import com.google.android.libraries.places.api.net.PlacesClient
import android.location.Geocoder
import android.location.Address
import android.os.Build
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import kotlinx.coroutines.launch
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.async
import kotlinx.coroutines.awaitAll
import kotlinx.coroutines.delay
import kotlin.coroutines.suspendCoroutine
import kotlin.coroutines.resume
import java.util.Locale
import java.util.concurrent.ConcurrentHashMap
import kotlin.math.abs
import kotlin.math.sin
import kotlin.math.cos
import kotlin.math.atan2
import kotlin.math.sqrt
import kotlin.math.asin

class GeofenceManager(private val context: Context) {

    companion object {
        private const val TAG = "GeofenceManager"
        private const val GEOFENCE_REQUEST_CODE = 2001
        private const val DEFAULT_RADIUS_METERS = 100f

        // 🚀 BATCH PROCESSING CONSTANTS
        private const val MAX_BATCH_SIZE = 10           // Process max 10 geofences at once
        private const val MAX_CONCURRENT_API_CALLS = 3  // Max 3 parallel Places API calls
        private const val API_CALL_DELAY_MS = 200L      // 200ms delay between API calls
        private const val BATCH_DELAY_MS = 500L         // 500ms delay between batches

        // 🏙️ ADAPTIVE RADIUS CONSTANTS
        private const val RURAL_RADIUS_OFFSET_METERS = 100f
        private const val MIN_RADIUS_METERS = 50f
        private const val MAX_RADIUS_METERS = 500f

        // 🌍 URBAN/RURAL DETECTION CONSTANTS
        private const val URBAN_DENSITY_THRESHOLD = 1000.0
        private const val URBAN_TASK_COUNT_THRESHOLD = 3

        // 🚀 ADAPTIVE INTERVAL CONSTANTS
        private const val LOCATION_UPDATE_INTERVAL_FAST = 1000L
        private const val LOCATION_UPDATE_INTERVAL_NORMAL = 5000L
        private const val LOCATION_UPDATE_INTERVAL_SLOW = 300000L
        private const val LOCATION_UPDATE_FASTEST_INTERVAL_FAST = 1000L
        private const val LOCATION_UPDATE_FASTEST_INTERVAL_NORMAL = 30000L
        private const val LOCATION_UPDATE_FASTEST_INTERVAL_SLOW = 120000L

        // 🏃 ENHANCED SPEED THRESHOLDS
        private const val SPEED_THRESHOLD_SLOW = 0.5
        private const val SPEED_THRESHOLD_WALKING = 2.0
        private const val SPEED_THRESHOLD_FAST = 5.0
        private const val SPEED_THRESHOLD_VEHICLE_SLOW = 8.0
        private const val SPEED_THRESHOLD_VEHICLE_FAST = 15.0

        // 🎯 DYNAMIC RADIUS SCALING CONSTANTS
        private const val RADIUS_MULTIPLIER_WALKING = 1.0f
        private const val RADIUS_MULTIPLIER_CYCLING = 1.5f
        private const val RADIUS_MULTIPLIER_VEHICLE_SLOW = 2.5f
        private const val RADIUS_MULTIPLIER_VEHICLE_FAST = 4.0f

        // 🔄 RADIUS UPDATE THRESHOLD
        private const val RADIUS_CHANGE_THRESHOLD = 20f

        // 🔮 PREDICTIVE GEOFENCING CONSTANTS
        private const val TRAJECTORY_HISTORY_SIZE = 10
        private const val MIN_TRAJECTORY_POINTS = 3
        private const val PREDICTION_TIME_SECONDS = 45
        private const val PREDICTION_CONFIDENCE_THRESHOLD = 0.7
        private const val CLUSTER_DISTANCE_THRESHOLD = 200.0
        private const val MIN_CLUSTER_SIZE = 2

        // 🚄 TRANSPORT MODE DETECTION CONSTANTS
        private const val TRAM_SPEED_MIN = 6.0
        private const val TRAM_SPEED_MAX = 20.0
        private const val BUS_SPEED_MIN = 5.0
        private const val BUS_SPEED_MAX = 18.0
        private const val TRAIN_SPEED_MIN = 15.0
        private const val CAR_SPEED_MIN = 8.0

        // 🔋 BATTERY OPTIMIZATION CONSTANTS
        private const val LOW_BATTERY_THRESHOLD = 20
        private const val CRITICAL_BATTERY_THRESHOLD = 10
        private const val BATTERY_SAVE_RADIUS_MULTIPLIER = 1.5f

        private const val GEOFENCE_EXPIRATION_DURATION = Geofence.NEVER_EXPIRE
        private const val GEOFENCE_INACTIVITY_THRESHOLD = 5 * 60 * 1000L
        private const val MANUAL_CHECK_TRIGGER_DELAY = 3 * 60 * 1000L
    }

    // 🏃 ENHANCED MOVEMENT STATE TRACKING
    enum class MovementState {
        STATIONARY,
        SLOW_MOVING,
        FAST_MOVING,
        VEHICLE_SLOW,
        VEHICLE_FAST
    }

    // 🚄 TRANSPORT MODE ENUM
    enum class TransportMode {
        WALKING,
        CYCLING,
        BUS,
        TRAM,
        TRAIN,
        CAR,
        UNKNOWN
    }

    private val geofencingClient: GeofencingClient = LocationServices.getGeofencingClient(context)
    private val activeGeofences = mutableMapOf<String, GeofenceData>()
    private val taskClusters = mutableMapOf<String, TaskCluster>()

    // 🚀 BATCH PROCESSING VARIABLES
    private val locationCache = ConcurrentHashMap<String, LocationCacheEntry>()
    private val processingBatches = mutableSetOf<Int>()
    private var batchCounter = 0

    // Hybrid system tracking
    @Volatile
    private var lastGeofenceEventTime = 0L
    @Volatile
    private var isGeofencingActive = true
    private var manualBackupListener: ManualBackupListener? = null

    // 🏃 MOVEMENT STATE TRACKING VARIABLES
    @Volatile
    private var currentMovementState = MovementState.STATIONARY
    @Volatile
    private var currentSpeed = 0.0
    @Volatile
    private var currentTransportMode = TransportMode.WALKING
    private var locationServiceListener: LocationServiceListener? = null

    // 🎯 DYNAMIC RADIUS TRACKING
    @Volatile
    private var currentBaseRadius = DEFAULT_RADIUS_METERS
    @Volatile
    private var lastCalculatedRadius = DEFAULT_RADIUS_METERS

    // 🔮 PREDICTIVE SYSTEM VARIABLES
    private val trajectoryHistory = mutableListOf<LocationPoint>()
    private val missedDetectionRecovery = mutableMapOf<String, Long>()
    private var lastPredictiveCheck = 0L
    private var currentTrajectory: Trajectory? = null

    // 🔋 BATTERY OPTIMIZATION VARIABLES
    @Volatile
    private var batteryLevel = 100
    @Volatile
    private var isBatteryOptimizationActive = false

    // 🆕 PLACES CLIENT VARIABLE
    private lateinit var placesClient: PlacesClient

    // 🚀 COROUTINE SCOPE FOR BATCH PROCESSING
    private val batchProcessingScope = CoroutineScope(Dispatchers.IO)

    // 🚀 LOCATION CACHE DATA CLASS
    data class LocationCacheEntry(
        val isUrban: Boolean,
        val timestamp: Long,
        val confidence: Double
    ) {
        fun isValid(): Boolean {
            return (System.currentTimeMillis() - timestamp) < 300000L // 5 minutes cache
        }
    }

    // 🔮 DATA CLASSES FOR PREDICTIVE SYSTEM
    data class LocationPoint(
        val latitude: Double,
        val longitude: Double,
        val timestamp: Long,
        val speed: Double,
        val bearing: Float
    )

    data class Trajectory(
        val points: List<LocationPoint>,
        val averageSpeed: Double,
        val averageBearing: Float,
        val confidence: Double
    )

    data class TaskCluster(
        val id: String,
        val centerLatitude: Double,
        val centerLongitude: Double,
        val radius: Double,
        val taskIds: List<String>,
        val priority: Int
    )

    // Data class to hold geofence information
    data class GeofenceData(
        val id: String,
        val latitude: Double,
        val longitude: Double,
        val radius: Float,
        val title: String,
        val description: String
    )

    // 🚀 BATCH PROCESSING RESULT CLASS
    data class BatchProcessingResult(
        val successCount: Int,
        val failureCount: Int,
        val totalProcessed: Int,
        val processingTimeMs: Long
    )

    // Data class for batch operation results
    data class BatchResult(
        val successCount: Int,
        val failureCount: Int,
        val totalCount: Int
    ) {
        val isSuccess: Boolean get() = failureCount == 0
    }

    // Interface for communication with manual backup system
    interface ManualBackupListener {
        fun onGeofencingBecameInactive()
        fun onGeofencingRestored()
        fun shouldActivateManualBackup(): Boolean
    }

    // Interface for communication with location service
    interface LocationServiceListener {
        fun onAdaptiveIntervalChanged(interval: Long, fastestInterval: Long)
        fun getCurrentMovementState(): MovementState
        fun onRadiusUpdateRequested(newRadius: Float)
        fun onPredictiveGeofenceRequested(predictions: List<LocationPoint>)
        fun onBatchProcessingProgress(processed: Int, total: Int)
    }

    // PendingIntent for geofence transitions
    private val geofencePendingIntent: PendingIntent by lazy {
        val intent = Intent(context, GeofenceBroadcastReceiver::class.java)
        PendingIntent.getBroadcast(
            context,
            GEOFENCE_REQUEST_CODE,
            intent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_MUTABLE
        )
    }

    /**
     * 🚀 LAZY OPTIMIZATION: Add geofences instantly with default radius,
     * then optimize in background using Google Places API
     */
	fun addGeofencesBatchWithLazyOptimization(geofences: List<GeofenceData>): Task<Void>? {
		if (!checkLocationPermissions()) {
			Log.e(TAG, "LAZY: Location permissions not granted")
			return null
		}
		if (geofences.isEmpty()) {
			Log.w(TAG, "LAZY: No geofences to add")
			return null
		}
		
		Log.d(TAG, "🚀 LAZY: Starting instant geofence addition + background optimization for ${geofences.size} geofences")
		val startTime = System.currentTimeMillis()
		
		// PHASE 1: Process geofences instantly with default urban radius
		batchProcessingScope.launch {
			try {
				// Create instant geofences with 100m radius (urban default)
				val instantGeofences = geofences.map { geofence ->
					GeofenceData(
						id = geofence.id,
						latitude = geofence.latitude,
						longitude = geofence.longitude,
						radius = 100.0f, // Default urban radius for instant addition
						title = geofence.title,
						description = geofence.description
					)
				}
				
				// PHASE 2: Add to Android system instantly (skip Google Places API)
				Log.d(TAG, "⚡ LAZY: Adding ${instantGeofences.size} geofences instantly with 100m radius")
				val instantResult = processBatchedGeofencesInstant(instantGeofences)
				
				val instantTime = System.currentTimeMillis() - startTime
				Log.d(TAG, "✅ LAZY: Instant addition completed in ${instantTime}ms")
				Log.d(TAG, "✅ LAZY: Instant success: ${instantResult.successCount}, Failed: ${instantResult.failureCount}")
				
				// Update service notification immediately
				updateServiceNotification()
				createSmartClusters()
				
				// 🔧 NEW: PHASE 3 - Launch background optimization in SEPARATE scope (truly async)
				launchBackgroundRadiusOptimizationAsync(geofences)
				
			} catch (e: Exception) {
				Log.e(TAG, "❌ LAZY: Instant batch failed: ${e.message}", e)
			}
		}
		
		// Return immediately - user sees geofences right away!
		return com.google.android.gms.tasks.Tasks.forResult(null)
	}
	
	/**
	 * 🔧 NEW: Launch background optimization in completely separate scope
	 */
	private fun launchBackgroundRadiusOptimizationAsync(originalGeofences: List<GeofenceData>) {
		// Use a separate scope with IO dispatcher for true background processing
		CoroutineScope(Dispatchers.IO).launch {
			try {
				// Small delay to ensure instant UI is fully loaded
				delay(2000) // Wait 2 seconds before starting optimization
				
				Log.d(TAG, "🔄 ASYNC: Starting delayed background radius optimization for ${originalGeofences.size} locations")
				var ruralUpdates = 0
				
				originalGeofences.forEach { geofence ->
					try {
						// Check if location is urban or rural using existing method
						val isUrban = getUrbanStatusCached(
							geofence.latitude,
							geofence.longitude
						)
						
						// Only update if rural (needs larger radius)
						if (!isUrban) {
							val optimalRadius = calculateRadius(
								isUrban = false,
								userRadius = 100.0
							)
							
							// Update geofence with optimal radius
							updateSingleGeofenceRadius(geofence, optimalRadius.toFloat())
							
							ruralUpdates++
							Log.d(TAG, "📍 ASYNC: Updated ${geofence.id} to rural radius ${optimalRadius}m")
						}
						
						// Longer delay to be gentle on API and battery
						delay(300) // 300ms between API calls (slower but more battery friendly)
						
					} catch (e: Exception) {
						Log.w(TAG, "⚠️ ASYNC: Background optimization failed for ${geofence.id}: $e")
						// Continue with other geofences - don't fail entire optimization
					}
				}
				
				Log.d(TAG, "✅ ASYNC: Background optimization completed. Updated $ruralUpdates rural locations")
				
				// Update service notification after background optimization
				updateServiceNotification()
				
			} catch (e: Exception) {
				Log.e(TAG, "❌ ASYNC: Background optimization failed: $e")
			}
		}
	}


    /**
     * Instant geofence processing - skips Google Places API for speed
     */
    private suspend fun processBatchedGeofencesInstant(geofences: List<GeofenceData>): BatchResult {
        return withContext(Dispatchers.IO) {
            try {
                val batchSize = 10 // Use hardcoded batch size
                Log.d(TAG, "🚀 INSTANT: Processing ${geofences.size} geofences in batches of $batchSize")
                
                // Create Android geofences directly without urban analysis
                val androidGeofences = geofences.map { geofenceData ->
                    createGeofence(
                        id = geofenceData.id,
                        latitude = geofenceData.latitude,
                        longitude = geofenceData.longitude,
                        radius = geofenceData.radius.toDouble(),
                        title = geofenceData.title,
                        description = geofenceData.description
                    )
                }
                
                // Add to Android system in batches
                var successCount = 0
                var failureCount = 0
                
                androidGeofences.chunked(batchSize).forEachIndexed { batchIndex, batch ->
                    try {
                        Log.d(TAG, "🚀 INSTANT BATCH ${batchIndex + 1}: Processing batch ${batchIndex + 1}/${(androidGeofences.size + batchSize - 1) / batchSize} (${batch.size} geofences)")
                        
                        val geofencingRequest = GeofencingRequest.Builder()
                            .setInitialTrigger(GeofencingRequest.INITIAL_TRIGGER_ENTER)
                            .addGeofences(batch)
                            .build()
                        
                        val result = addGeofencesToSystem(geofencingRequest)
                        
                        if (result) {
                            // 🔧 FIX: Add to activeGeofences tracking immediately
                            val batchStartIndex = batchIndex * batchSize
                            for (i in batch.indices) {
                                val originalIndex = batchStartIndex + i
                                if (originalIndex < geofences.size) {
                                    val geofenceData = geofences[originalIndex]
                                    activeGeofences[geofenceData.id] = geofenceData
                                    Log.d(TAG, "✅ TRACKING: Added ${geofenceData.id} to activeGeofences")
                                }
                            }
                            
                            successCount += batch.size
                            Log.d(TAG, "✅ INSTANT BATCH ${batchIndex + 1}: Android geofences added successfully")
                        } else {
                            failureCount += batch.size
                            Log.w(TAG, "❌ INSTANT BATCH ${batchIndex + 1}: Failed to add Android geofences")
                        }
                        
                    } catch (e: Exception) {
                        failureCount += batch.size
                        Log.e(TAG, "❌ INSTANT BATCH ${batchIndex + 1}: Exception: ${e.message}")
                    }
                }
                
                // 🔧 FIX: Reset geofencing status after successful addition
                if (successCount > 0) {
                    lastGeofenceEventTime = System.currentTimeMillis()
                    isGeofencingActive = true
                    Log.d(TAG, "✅ TRACKING: ${activeGeofences.size} geofences now active")
                }
                
                Log.d(TAG, "✅ INSTANT: Processing completed")
                BatchResult(successCount, failureCount, successCount + failureCount)
                
            } catch (e: Exception) {
                Log.e(TAG, "❌ INSTANT: Failed: ${e.message}", e)
                BatchResult(0, geofences.size, geofences.size)
            }
        }
    }

    /**
     * Background optimization that runs async - doesn't block UI
     */
    private fun launchBackgroundRadiusOptimization(originalGeofences: List<GeofenceData>) {
        CoroutineScope(Dispatchers.IO).launch {
            try {
                Log.d(TAG, "🔄 LAZY: Starting background radius optimization for ${originalGeofences.size} locations")
                var ruralUpdates = 0
                
                originalGeofences.forEach { geofence ->
                    try {
                        // Check if location is urban or rural using existing method
                        val isUrban = getUrbanStatusCached(
                            geofence.latitude,
                            geofence.longitude
                        )
                        
                        // Only update if rural (needs larger radius)
                        if (!isUrban) {
                            val optimalRadius = calculateRadius(
                                isUrban = false,
                                userRadius = 100.0
                            )
                            
                            // Update geofence with optimal radius
                            updateSingleGeofenceRadius(geofence, optimalRadius.toFloat())
                            
                            ruralUpdates++
                            Log.d(TAG, "📍 LAZY: Updated ${geofence.id} to rural radius ${optimalRadius}m")
                        }
                        
                        // Small delay to avoid overwhelming Google Places API
                        delay(100)
                        
                    } catch (e: Exception) {
                        Log.w(TAG, "⚠️ LAZY: Background optimization failed for ${geofence.id}: $e")
                        // Continue with other geofences - don't fail entire batch
                    }
                }
                
                Log.d(TAG, "✅ LAZY: Background optimization completed. Updated $ruralUpdates rural locations")
                
                // Update service notification after background optimization
                updateServiceNotification()
                
            } catch (e: Exception) {
                Log.e(TAG, "❌ LAZY: Background optimization failed: $e")
            }
        }
    }

    /**
     * Updates a single geofence radius by removing old and adding new
     */
    private suspend fun updateSingleGeofenceRadius(
        originalGeofence: GeofenceData,
        newRadius: Float
    ) {
        try {
            // Don't remove from activeGeofences yet - keep tracking
            val wasActive = activeGeofences.containsKey(originalGeofence.id)
            
            // Remove existing geofence from Android system only
            removeGeofenceFromSystem(originalGeofence.id)
            
            // Create updated geofence data
            val updatedGeofence = GeofenceData(
                id = originalGeofence.id,
                latitude = originalGeofence.latitude,
                longitude = originalGeofence.longitude,
                radius = newRadius,
                title = originalGeofence.title,
                description = originalGeofence.description
            )
            
            // Add back to Android system with new radius
            val success = addSingleGeofenceToAndroidSystem(updatedGeofence)
            
            if (success) {
                // Update activeGeofences with new data
                activeGeofences[originalGeofence.id] = updatedGeofence
                Log.d(TAG, "✅ UPDATED: ${originalGeofence.id} radius updated to ${newRadius}m")
            } else if (wasActive) {
                // Restore original if update failed
                activeGeofences[originalGeofence.id] = originalGeofence
                Log.e(TAG, "❌ UPDATE FAILED: Restored original ${originalGeofence.id}")
            }
            
        } catch (e: Exception) {
            Log.e(TAG, "❌ LAZY: Failed to update radius for ${originalGeofence.id}: $e")
            // Ensure original remains in tracking if it was there
            if (!activeGeofences.containsKey(originalGeofence.id)) {
                activeGeofences[originalGeofence.id] = originalGeofence
            }
        }
    }

    /**
     * Add single geofence to Android system only (for background optimization)
     */
    private suspend fun addSingleGeofenceToAndroidSystem(geofence: GeofenceData): Boolean {
        return try {
            val androidGeofence = createGeofence(
                id = geofence.id,
                latitude = geofence.latitude,
                longitude = geofence.longitude, 
                radius = geofence.radius.toDouble(),
                title = geofence.title,
                description = geofence.description
            )
            
            val geofencingRequest = GeofencingRequest.Builder()
                .setInitialTrigger(GeofencingRequest.INITIAL_TRIGGER_ENTER)
                .addGeofence(androidGeofence)
                .build()
                
            addGeofencesToSystem(geofencingRequest)
            
        } catch (e: Exception) {
            Log.e(TAG, "❌ LAZY: Failed to add single geofence ${geofence.id} to system: $e")
            false
        }
    }

    /**
     * Remove single geofence from Android system only
     */
    private suspend fun removeGeofenceFromSystem(geofenceId: String) {
        try {
            // Use suspendCoroutine to convert Task to coroutine
            suspendCoroutine<Boolean> { continuation ->
                val task = geofencingClient.removeGeofences(listOf(geofenceId))
                task.addOnSuccessListener {
                    Log.d(TAG, "✅ REMOVED: $geofenceId from Android system")
                    continuation.resume(true)
                }.addOnFailureListener { exception ->
                    Log.w(TAG, "⚠️ REMOVE FAILED: $geofenceId from Android system: ${exception.message}")
                    continuation.resume(false)
                }
            }
        } catch (e: Exception) {
            Log.e(TAG, "❌ REMOVE ERROR: Failed to remove $geofenceId from system: $e")
        }
    }

    /**
     * Add single geofence - helper for background updates (original method kept)
     */
    private suspend fun addSingleGeofence(geofence: GeofenceData) {
        try {
            val androidGeofence = createGeofence(
                id = geofence.id,
                latitude = geofence.latitude,
                longitude = geofence.longitude, 
                radius = geofence.radius.toDouble(),
                title = geofence.title,
                description = geofence.description
            )
            
            val geofencingRequest = GeofencingRequest.Builder()
                .setInitialTrigger(GeofencingRequest.INITIAL_TRIGGER_ENTER)
                .addGeofence(androidGeofence)
                .build()
                
            addGeofencesToSystem(geofencingRequest)
            
        } catch (e: Exception) {
            Log.e(TAG, "❌ LAZY: Failed to add single geofence ${geofence.id}: $e")
        }
    }

    /**
     * Helper methods for lazy optimization
     */
    private fun calculateRadius(isUrban: Boolean, userRadius: Double): Double {
        return if (isUrban) {
            userRadius // Urban areas use smaller radius
        } else {
            (userRadius * 2.5).coerceAtMost(300.0) // Rural areas get 2.5x radius, max 300m
        }
    }

    /**
     * Helper method to add geofences to Android system
     */
    private suspend fun addGeofencesToSystem(geofencingRequest: GeofencingRequest): Boolean {
        return try {
            // Use suspendCoroutine to convert Task to coroutine
            suspendCoroutine<Boolean> { continuation ->
                val task = geofencingClient.addGeofences(geofencingRequest, geofencePendingIntent)
                task.addOnSuccessListener {
                    continuation.resume(true)
                }.addOnFailureListener {
                    continuation.resume(false)
                }
            }
        } catch (e: Exception) {
            Log.e(TAG, "Failed to add geofences to system: $e")
            false
        }
    }

    /**
     * Helper method to create Android Geofence object
     */
    private fun createGeofence(
        id: String,
        latitude: Double,
        longitude: Double,
        radius: Double,
        title: String,
        description: String
    ): Geofence {
        return Geofence.Builder()
            .setRequestId(id)
            .setCircularRegion(latitude, longitude, radius.toFloat())
            .setExpirationDuration(GEOFENCE_EXPIRATION_DURATION)
            .setTransitionTypes(Geofence.GEOFENCE_TRANSITION_ENTER or Geofence.GEOFENCE_TRANSITION_EXIT)
            .setLoiteringDelay(5000)
            .setNotificationResponsiveness(1000)
            .build()
    }

    /**
     * 🚀 OPTIMIZED: Add multiple geofences with batch processing and caching
     */
    fun addGeofencesBatch(geofences: List<GeofenceData>): Task<Void>? {
        if (!checkLocationPermissions()) {
            Log.e(TAG, "Location permissions not granted")
            return null
        }

        if (geofences.isEmpty()) {
            Log.w(TAG, "No geofences to add")
            return null
        }

        Log.d(TAG, "🚀 BATCH: Starting optimized batch processing for ${geofences.size} geofences")
        val startTime = System.currentTimeMillis()

        // Start batch processing in background
        batchProcessingScope.launch {
            try {
                val result = processBatchedGeofences(geofences)
                val endTime = System.currentTimeMillis()

                Log.d(TAG, "✅ BATCH: Completed in ${endTime - startTime}ms")
                Log.d(TAG, "✅ BATCH: Success: ${result.successCount}, Failed: ${result.failureCount}")

                // Update service notification after batch completion
                updateServiceNotification()
                
                // Create smart clusters
                createSmartClusters()

            } catch (e: Exception) {
                Log.e(TAG, "❌ BATCH: Failed: ${e.message}", e)
            }
        }

        // Return a dummy task that resolves immediately for compatibility
        return com.google.android.gms.tasks.Tasks.forResult(null)
    }

    /**
     * 🚀 NEW: Process geofences in optimized batches
     */
    private suspend fun processBatchedGeofences(geofences: List<GeofenceData>): BatchProcessingResult = withContext(Dispatchers.IO) {
        var successCount = 0
        var failureCount = 0
        val startTime = System.currentTimeMillis()

        Log.d(TAG, "🚀 BATCH: Processing ${geofences.size} geofences in batches of $MAX_BATCH_SIZE")

        // Phase 1: Preprocess locations in parallel (cached + API calls)
        val preprocessedGeofences = preprocessLocationsInParallel(geofences)
        Log.d(TAG, "🚀 BATCH: Preprocessing completed, ${preprocessedGeofences.size} geofences ready")

        // Phase 2: Add geofences in batches to Android system
        val batches = preprocessedGeofences.chunked(MAX_BATCH_SIZE)
        
        for ((batchIndex, batch) in batches.withIndex()) {
            val batchId = ++batchCounter
            processingBatches.add(batchId)

            Log.d(TAG, "🚀 BATCH $batchId: Processing batch ${batchIndex + 1}/${batches.size} (${batch.size} geofences)")

            try {
                val batchResult = processSingleBatch(batch, batchId)
                successCount += batchResult.successCount
                failureCount += batchResult.failureCount

                // Update progress
                val totalProcessed = successCount + failureCount
                locationServiceListener?.onBatchProcessingProgress(totalProcessed, geofences.size)

                Log.d(TAG, "✅ BATCH $batchId: Complete - Success: ${batchResult.successCount}, Failed: ${batchResult.failureCount}")

            } catch (e: Exception) {
                Log.e(TAG, "❌ BATCH $batchId: Failed - ${e.message}")
                failureCount += batch.size
            } finally {
                processingBatches.remove(batchId)
            }

            // Delay between batches to prevent overwhelming the system
            if (batchIndex < batches.size - 1) {
                delay(BATCH_DELAY_MS)
            }
        }

        val endTime = System.currentTimeMillis()
        BatchProcessingResult(successCount, failureCount, geofences.size, endTime - startTime)
    }

    /**
     * 🚀 NEW: Preprocess locations with parallel API calls and caching
     */
    private suspend fun preprocessLocationsInParallel(
        geofences: List<GeofenceData>
    ): List<GeofenceData> = withContext(Dispatchers.IO) {
        
        Log.d(TAG, "🌍 PREPROCESSING: Starting parallel location analysis for ${geofences.size} locations")

        // Group by location to avoid duplicate API calls
        val uniqueLocations = geofences.groupBy { 
            locationCacheKey(it.latitude, it.longitude) 
        }

        Log.d(TAG, "🌍 PREPROCESSING: Found ${uniqueLocations.size} unique locations (reduced from ${geofences.size})")

        // Process unique locations in parallel batches
        val locationBatches = uniqueLocations.keys.chunked(MAX_CONCURRENT_API_CALLS)
        val processedLocations = mutableMapOf<String, Boolean>()

        for (batch in locationBatches) {
            val deferredResults = batch.map { locationKey ->
                async {
                    val geofence = uniqueLocations[locationKey]?.first()
                    if (geofence != null) {
                        val isUrban = getUrbanStatusCached(geofence.latitude, geofence.longitude)
                        locationKey to isUrban
                    } else {
                        locationKey to true // Default to urban
                    }
                }
            }

            // Wait for batch to complete
            val batchResults = deferredResults.awaitAll()
            processedLocations.putAll(batchResults)

            // Small delay between API batches
            if (locationBatches.indexOf(batch) < locationBatches.size - 1) {
                delay(API_CALL_DELAY_MS)
            }
        }

        Log.d(TAG, "🌍 PREPROCESSING: Location analysis complete, creating optimized geofences")

        // Create optimized geofences with calculated radii
        val optimizedGeofences = geofences.map { geofence ->
            val locationKey = locationCacheKey(geofence.latitude, geofence.longitude)
            val isUrban = processedLocations[locationKey] ?: true
            val adaptiveRadius = calculateOptimizedRadius(geofence.latitude, geofence.longitude, geofence.radius, isUrban)
            
            geofence.copy(radius = adaptiveRadius)
        }

        Log.d(TAG, "✅ PREPROCESSING: Created ${optimizedGeofences.size} optimized geofences")
        optimizedGeofences
    }

    /**
     * 🚀 NEW: Process a single batch of geofences
     */
    private suspend fun processSingleBatch(
        batch: List<GeofenceData>,
        batchId: Int
    ): BatchProcessingResult = withContext(Dispatchers.Main) {
        
        val batchStartTime = System.currentTimeMillis()
        
        val geofenceList = batch.map { data ->
            Geofence.Builder()
                .setRequestId(data.id)
                .setCircularRegion(data.latitude, data.longitude, data.radius)
                .setExpirationDuration(GEOFENCE_EXPIRATION_DURATION)
                .setTransitionTypes(Geofence.GEOFENCE_TRANSITION_ENTER or Geofence.GEOFENCE_TRANSITION_EXIT)
                .setLoiteringDelay(5000)
                .setNotificationResponsiveness(1000) // 1 second responsiveness
                .build()
        }

        val geofencingRequest = GeofencingRequest.Builder()
            .setInitialTrigger(GeofencingRequest.INITIAL_TRIGGER_ENTER)
            .addGeofences(geofenceList)
            .build()

        return@withContext try {
            // Use suspendCoroutine to convert Task to coroutine
            val result = suspendCoroutine<Boolean> { continuation ->
                val task = geofencingClient.addGeofences(geofencingRequest, geofencePendingIntent)
                
                task.addOnSuccessListener {
                    Log.d(TAG, "✅ BATCH $batchId: Android geofences added successfully")
                    continuation.resume(true)
                }
                
                task.addOnFailureListener { exception ->
                    Log.e(TAG, "❌ BATCH $batchId: Failed to add Android geofences: ${exception.message}")
                    handleGeofenceError(exception)
                    continuation.resume(false)
                }
            }

            if (result) {
                // Add to active geofences tracking
                batch.forEach { data ->
                    activeGeofences[data.id] = data
                }
                
                // Reset geofencing status
                lastGeofenceEventTime = System.currentTimeMillis()
                isGeofencingActive = true

                val batchEndTime = System.currentTimeMillis()
                BatchProcessingResult(batch.size, 0, batch.size, batchEndTime - batchStartTime)
            } else {
                BatchProcessingResult(0, batch.size, batch.size, System.currentTimeMillis() - batchStartTime)
            }
            
        } catch (e: Exception) {
            Log.e(TAG, "❌ BATCH $batchId: Exception during processing: ${e.message}")
            BatchProcessingResult(0, batch.size, batch.size, System.currentTimeMillis() - batchStartTime)
        }
    }

    /**
     * 🚀 NEW: Get urban status with caching
     */
    private suspend fun getUrbanStatusCached(latitude: Double, longitude: Double): Boolean {
        val cacheKey = locationCacheKey(latitude, longitude)
        val cachedEntry = locationCache[cacheKey]

        if (cachedEntry != null && cachedEntry.isValid()) {
            Log.d(TAG, "💾 CACHE: Using cached urban status for (${"%.4f".format(latitude)}, ${"%.4f".format(longitude)}) = ${cachedEntry.isUrban}")
            return cachedEntry.isUrban
        }

        // Not in cache or expired - fetch from API
        val isUrban = isUrbanArea(latitude, longitude)
        
        // Cache the result
        locationCache[cacheKey] = LocationCacheEntry(
            isUrban = isUrban,
            timestamp = System.currentTimeMillis(),
            confidence = 0.8 // High confidence for API results
        )

        Log.d(TAG, "🌍 API: Fetched and cached urban status for (${"%.4f".format(latitude)}, ${"%.4f".format(longitude)}) = $isUrban")
        return isUrban
    }

    /**
     * 🚀 NEW: Create cache key for location
     */
    private fun locationCacheKey(latitude: Double, longitude: Double): String {
        // Round to ~100m precision to increase cache hits
        val roundedLat = kotlin.math.round(latitude * 1000) / 1000.0
        val roundedLon = kotlin.math.round(longitude * 1000) / 1000.0
        return "${roundedLat}_${roundedLon}"
    }

    /**
     * 🚀 NEW: Calculate optimized radius using cached urban data
     */
    private fun calculateOptimizedRadius(
        latitude: Double, 
        longitude: Double, 
        userRadius: Float,
        isUrban: Boolean
    ): Float {
        
        // Apply urban/rural adjustment
        val locationAdjustedRadius = if (isUrban) {
            userRadius
        } else {
            userRadius + RURAL_RADIUS_OFFSET_METERS
        }

        // Apply speed-based scaling with battery optimization
        val speedAdjustedRadius = calculateEnhancedSpeedBasedRadius(currentSpeed, locationAdjustedRadius)

        // Ensure within bounds
        val finalRadius = speedAdjustedRadius.coerceIn(MIN_RADIUS_METERS, MAX_RADIUS_METERS)

        Log.d(TAG, "🎯 OPTIMIZED radius calculation:")
        Log.d(TAG, "  - Location: (${"%.4f".format(latitude)}, ${"%.4f".format(longitude)})")
        Log.d(TAG, "  - Area type: ${if (isUrban) "URBAN" else "RURAL"}")
        Log.d(TAG, "  - User radius: ${userRadius}m")
        Log.d(TAG, "  - Location adjusted: ${locationAdjustedRadius}m")
        Log.d(TAG, "  - Speed adjusted: ${speedAdjustedRadius}m")
        Log.d(TAG, "  - FINAL radius: ${finalRadius}m")

        return finalRadius
    }

    /**
     * Add a single geofence (compatibility method)
     */
    fun addGeofence(
        id: String,
        latitude: Double,
        longitude: Double,
        radius: Float = DEFAULT_RADIUS_METERS,
        title: String = "",
        description: String = ""
    ): Task<Void>? {

        if (!checkLocationPermissions()) {
            Log.e(TAG, "Location permissions not granted")
            return null
        }

        Log.d(TAG, "🔧 Adding single geofence: $id - converting to batch")

        // Create GeofenceData
        val geofenceData = GeofenceData(id, latitude, longitude, radius, title, description)
        
        // Use batch method for single geofence
        return addGeofencesBatch(listOf(geofenceData))
    }

    /**
     * Remove a single geofence by ID (compatibility method) 
     */
    fun removeGeofence(id: String): Task<Void>? {
        Log.d(TAG, "🔧 Removing single geofence: $id")
        
        if (!activeGeofences.containsKey(id)) {
            Log.w(TAG, "Geofence $id not found in active geofences")
            return com.google.android.gms.tasks.Tasks.forResult(null)
        }
        
        // Remove from activeGeofences tracking
        activeGeofences.remove(id)
        
        // Remove from Android system
        val task = geofencingClient.removeGeofences(listOf(id))
        task.addOnSuccessListener {
            Log.d(TAG, "✅ Geofence $id removed from Android system")
            updateServiceNotification()
        }.addOnFailureListener { exception ->
            Log.e(TAG, "❌ Failed to remove geofence $id from Android system: ${exception.message}")
            // Don't restore to activeGeofences since removal from tracking succeeded
        }
        
        // Update notification immediately with new count
        updateServiceNotification()
        
        Log.d(TAG, "✅ Geofence $id removed from tracking (${activeGeofences.size} remain)")
        return com.google.android.gms.tasks.Tasks.forResult(null)
    }

    /**
     * Set listener for manual backup system
     */
    fun setManualBackupListener(listener: ManualBackupListener) {
        this.manualBackupListener = listener
    }

    /**
     * 🚀 Set listener for location service communication
     */
    fun setLocationServiceListener(listener: LocationServiceListener) {
        this.locationServiceListener = listener
    }

    /**
     * 🔋 NEW: Update battery level for optimization
     */
    fun updateBatteryLevel(level: Int) {
        batteryLevel = level

        val wasBatteryOptimized = isBatteryOptimizationActive
        isBatteryOptimizationActive = level <= LOW_BATTERY_THRESHOLD

        if (isBatteryOptimizationActive != wasBatteryOptimized) {
            Log.d(TAG, "🔋 Battery optimization ${if (isBatteryOptimizationActive) "ACTIVATED" else "DEACTIVATED"} at ${level}%")

            if (activeGeofences.isNotEmpty()) {
                recalculateAllGeofenceRadii()
            }
        }
    }

    private fun calculateEnhancedSpeedBasedRadius(speed: Double, baseRadius: Float): Float {
        val multiplier = when {
            speed >= SPEED_THRESHOLD_VEHICLE_FAST -> RADIUS_MULTIPLIER_VEHICLE_FAST
            speed >= SPEED_THRESHOLD_VEHICLE_SLOW -> RADIUS_MULTIPLIER_VEHICLE_SLOW
            speed >= SPEED_THRESHOLD_FAST -> RADIUS_MULTIPLIER_CYCLING
            else -> RADIUS_MULTIPLIER_WALKING
        }

        var calculatedRadius = baseRadius * multiplier

        if (isBatteryOptimizationActive) {
            calculatedRadius *= BATTERY_SAVE_RADIUS_MULTIPLIER
        }

        return calculatedRadius.coerceIn(MIN_RADIUS_METERS, MAX_RADIUS_METERS)
    }

    /**
     * Get list of active geofence IDs
     */
    fun getActiveGeofenceIds(): List<String> {
        val ids = activeGeofences.keys.toList()
        Log.d(TAG, "📊 ACTIVE IDS: $ids")
        return ids
    }

    /**
     * Get active geofence count
     */
    fun getActiveGeofenceCount(): Int {
        val count = activeGeofences.size
        Log.d(TAG, "📊 ACTIVE COUNT: $count geofences tracked")
        return count
    }

    /**
     * Get all active geofence locations for manual backup
     */
    fun getActiveGeofenceLocations(): List<GeofenceData> {
        return activeGeofences.values.toList()
    }

    /**
     * 🚀 NEW: Get current calculated radius for external use
     */
    fun getCurrentCalculatedRadius(): Float {
        return lastCalculatedRadius
    }

    /**
     * Remove all active geofences
     */
    fun removeAllGeofences(): Task<Void> {
        Log.d(TAG, "Removing all geofences")

        val task = geofencingClient.removeGeofences(geofencePendingIntent)

        task.addOnSuccessListener {
            val count = activeGeofences.size
            activeGeofences.clear()
            taskClusters.clear()
            trajectoryHistory.clear()
            missedDetectionRecovery.clear()
            locationCache.clear()
            Log.d(TAG, "All $count geofences removed successfully")
            updateServiceNotification()
        }

        task.addOnFailureListener { exception ->
            Log.e(TAG, "Failed to remove all geofences", exception)
        }

        return task
    }

    /**
     * Call when geofence event is received (from GeofenceBroadcastReceiver)
     */
    fun onGeofenceEventReceived() {
        val currentTime = System.currentTimeMillis()
        lastGeofenceEventTime = currentTime

        if (!isGeofencingActive) {
            isGeofencingActive = true
            Log.d(TAG, "Geofencing restored - disabling manual backup")
            manualBackupListener?.onGeofencingRestored()
        }
    }

    /**
     * Check if geofencing is active
     */
    fun isGeofencingActive(): Boolean {
        val currentTime = System.currentTimeMillis()
        val timeSinceLastEvent = currentTime - lastGeofenceEventTime

        val shouldBeActive = if (lastGeofenceEventTime == 0L) {
            true
        } else {
            timeSinceLastEvent < GEOFENCE_INACTIVITY_THRESHOLD
        }

        if (isGeofencingActive != shouldBeActive) {
            isGeofencingActive = shouldBeActive

            if (!shouldBeActive && activeGeofences.isNotEmpty()) {
                Log.w(TAG, "Geofencing became inactive - triggering manual backup")
                manualBackupListener?.onGeofencingBecameInactive()
            }
        }

        return isGeofencingActive
    }

    /**
     * Should activate manual backup
     */
    fun shouldActivateManualBackup(): Boolean {
        val hasActiveGeofences = activeGeofences.isNotEmpty()
        val geofencingInactive = !isGeofencingActive()

        return hasActiveGeofences && geofencingInactive &&
                (manualBackupListener?.shouldActivateManualBackup() ?: false)
    }

    /**
     * Get time of last geofence event
     */
    fun getLastGeofenceEventTime(): Long = lastGeofenceEventTime

    // Stub methods for features to be implemented later
    fun addLocationPoint(latitude: Double, longitude: Double, speed: Double, bearing: Float) {
        Log.d(TAG, "🔮 Location point tracking stub - implement later")
    }

    fun updateMovementState(newState: MovementState) {
        currentMovementState = newState
        Log.d(TAG, "🏃 Movement state updated: $newState")
    }

    fun updateSpeedAndRadius(newSpeed: Double) {
        val speedChanged = abs(currentSpeed - newSpeed) > 1.0
        currentSpeed = newSpeed

        if (speedChanged) {
            Log.d(TAG, "🏃 Speed updated: ${"%.2f".format(newSpeed)} m/s (${"%.1f".format(newSpeed * 3.6)} km/h)")

            val newRadius = calculateEnhancedSpeedBasedRadius(newSpeed, currentBaseRadius)

            if (abs(newRadius - lastCalculatedRadius) >= RADIUS_CHANGE_THRESHOLD) {
                Log.d(TAG, "🎯 Significant radius change detected: ${lastCalculatedRadius}m → ${newRadius}m")
                lastCalculatedRadius = newRadius
                locationServiceListener?.onRadiusUpdateRequested(newRadius)

                if (activeGeofences.isNotEmpty()) {
                    Log.d(TAG, "🔄 Triggering geofence radius update for ${activeGeofences.size} geofences")
                }
            }
        }
    }

    fun getCurrentMovementState(): MovementState {
        return currentMovementState
    }

    fun getCurrentSpeed(): Double {
        return currentSpeed
    }

    fun isVehicleMovement(): Boolean {
        return currentMovementState == MovementState.VEHICLE_SLOW ||
                currentMovementState == MovementState.VEHICLE_FAST
    }

    fun recalculateAllGeofenceRadii(): Boolean {
        if (activeGeofences.isEmpty()) {
            Log.d(TAG, "No active geofences to recalculate")
            return false
        }

        Log.d(TAG, "🔄 Recalculating radii for ${activeGeofences.size} geofences")

        val updatedGeofences = mutableListOf<GeofenceData>()

        for (geofenceData in activeGeofences.values) {
            val newRadius = calculateEnhancedSpeedBasedRadius(currentSpeed, currentBaseRadius)
            val updatedGeofence = geofenceData.copy(radius = newRadius)
            updatedGeofences.add(updatedGeofence)
        }

        return if (updatedGeofences.isNotEmpty()) {
            Log.d(TAG, "🔄 Re-registering ${updatedGeofences.size} geofences with updated radii")

            removeAllGeofences().addOnSuccessListener {
                Log.d(TAG, "✅ All geofences removed, re-adding with new radii")
                addGeofencesBatch(updatedGeofences)
                createSmartClusters()
            }.addOnFailureListener { exception ->
                Log.e(TAG, "❌ Failed to remove geofences for radius update: ${exception.message}")
            }

            true
        } else {
            false
        }
    }

    fun createSmartClusters() {
        taskClusters.clear()
        val unclustered = activeGeofences.values.toMutableList()
        var clusterId = 0

        while (unclustered.isNotEmpty()) {
            val centerTask = unclustered.removeAt(0)
            val cluster = mutableListOf(centerTask)

            val iterator = unclustered.iterator()
            while (iterator.hasNext()) {
                val task = iterator.next()
                val distance = calculateDistance(
                    centerTask.latitude,
                    centerTask.longitude,
                    task.latitude,
                    task.longitude
                )

                if (distance <= CLUSTER_DISTANCE_THRESHOLD) {
                    cluster.add(task)
                    iterator.remove()
                }
            }

            if (cluster.size >= MIN_CLUSTER_SIZE) {
                val clusterCenter = calculateClusterCenter(cluster)
                val clusterRadius = calculateClusterRadius(cluster, clusterCenter)
                val priority = calculateClusterPriority(cluster)

                val taskCluster = TaskCluster(
                    id = "cluster_${clusterId++}",
                    centerLatitude = clusterCenter.first,
                    centerLongitude = clusterCenter.second,
                    radius = clusterRadius,
                    taskIds = cluster.map { it.id },
                    priority = priority
                )

                taskClusters[taskCluster.id] = taskCluster
                Log.d(TAG, "🔮 Created cluster ${taskCluster.id} with ${cluster.size} tasks")
            }
        }

        Log.d(TAG, "🔮 Created ${taskClusters.size} smart clusters from ${activeGeofences.size} tasks")
    }

    // Helper calculation methods
    private fun calculateClusterCenter(tasks: List<GeofenceData>): Pair<Double, Double> {
        val avgLat = tasks.map { it.latitude }.average()
        val avgLon = tasks.map { it.longitude }.average()
        return Pair(avgLat, avgLon)
    }

    private fun calculateClusterRadius(tasks: List<GeofenceData>, center: Pair<Double, Double>): Double {
        var maxDistance = 0.0
        for (task in tasks) {
            val distance = calculateDistance(center.first, center.second, task.latitude, task.longitude)
            maxDistance = maxOf(maxDistance, distance)
        }
        return maxDistance + 50.0
    }

    private fun calculateClusterPriority(tasks: List<GeofenceData>): Int {
        return tasks.size * 10
    }

    /**
     * 🌍 DETECT IF LOCATION IS IN URBAN OR RURAL AREA
     */
    private suspend fun isUrbanArea(latitude: Double, longitude: Double): Boolean {
        return try {
            Log.d(TAG, "🌍 Analyzing location: (${"%.4f".format(latitude)}, ${"%.4f".format(longitude)})")

            if (!::placesClient.isInitialized) {
                val apiKey = getApiKey()
                if (apiKey.isBlank()) {
                    Log.w(TAG, "⚠️ No API key found - using fallback method")
                    return isUrbanAreaFallback(latitude, longitude)
                }
                Places.initialize(context, apiKey)
                placesClient = Places.createClient(context)
            }

            val result = withContext(Dispatchers.IO) {
                performReverseGeocoding(latitude, longitude)
            }

            val isUrban = analyzeAddressComponents(result, latitude, longitude)
            Log.d(TAG, "🏙️ Location analysis result: Urban = $isUrban")
            isUrban

        } catch (e: Exception) {
            Log.e(TAG, "❌ Error detecting urban area: ${e.message}")
            isUrbanAreaFallback(latitude, longitude)
        }
    }

    /**
     * 🔧 Helper function for getting API key
     */
    private fun getApiKey(): String {
        return try {
            val appInfo = context.packageManager.getApplicationInfo(
                context.packageName,
                PackageManager.GET_META_DATA
            )
            appInfo.metaData?.getString("com.google.android.geo.API_KEY") ?: ""
        } catch (e: Exception) {
            Log.e(TAG, "Failed to get API key: ${e.message}")
            ""
        }
    }

    /**
     * 🌍 Reverse geocoding implementation
     */
    private suspend fun performReverseGeocoding(
        latitude: Double,
        longitude: Double
    ): String = suspendCoroutine { continuation ->

        try {
            val geocoder = Geocoder(context, Locale.getDefault())

            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
                geocoder.getFromLocation(latitude, longitude, 1) { addresses ->
                    val result = addresses.firstOrNull()?.let { address ->
                        analyzeGeocoderResult(address)
                    } ?: "UNKNOWN"
                    continuation.resume(result)
                }
            } else {
                @Suppress("DEPRECATION")
                val addresses = geocoder.getFromLocation(latitude, longitude, 1)
                val result = addresses?.firstOrNull()?.let { address ->
                    analyzeGeocoderResult(address)
                } ?: "UNKNOWN"
                continuation.resume(result)
            }
        } catch (e: Exception) {
            Log.e(TAG, "Reverse geocoding failed: ${e.message}")
            continuation.resume("ERROR")
        }
    }

    /**
     * 🏛️ Analyze address components
     */
    private fun analyzeGeocoderResult(address: Address): String {
        return when {
            address.locality != null && address.subLocality != null -> "URBAN_HIGH"
            address.locality != null -> "URBAN_MEDIUM"
            address.subLocality != null -> "URBAN_LOW"
            address.locality == null && address.adminArea != null -> "RURAL"
            else -> "UNKNOWN"
        }
    }

    /**
     * 🏙️ Analyze if urban based on geocoder results
     */
    private fun analyzeAddressComponents(
        result: String,
        latitude: Double,
        longitude: Double
    ): Boolean {

        Log.d(TAG, "🏛️ Address analysis result: $result")

        return when (result) {
            "URBAN_HIGH" -> {
                Log.d(TAG, "✅ URBAN detected: City with neighborhood")
                true
            }
            "URBAN_MEDIUM" -> {
                Log.d(TAG, "✅ URBAN detected: City/town")
                true
            }
            "URBAN_LOW" -> {
                Log.d(TAG, "⚠️ SUBURBAN detected: Some urban features")
                true
            }
            "RURAL" -> {
                Log.d(TAG, "🌾 RURAL detected: County-level only")
                false
            }
            else -> {
                Log.d(TAG, "❓ UNKNOWN - using fallback method")
                isUrbanAreaFallback(latitude, longitude)
            }
        }
    }

    /**
     * 🔄 Fallback to old algorithm if Places API doesn't work
     */
    private fun isUrbanAreaFallback(latitude: Double, longitude: Double): Boolean {
        return try {
            var nearbyTaskCount = 0

            for (geofence in activeGeofences.values) {
                val distance = calculateDistance(
                    latitude, longitude,
                    geofence.latitude, geofence.longitude
                )

                if (distance <= URBAN_DENSITY_THRESHOLD) {
                    nearbyTaskCount++
                }
            }

            val isUrban = nearbyTaskCount >= URBAN_TASK_COUNT_THRESHOLD
            Log.d(TAG, "🔄 Fallback: Nearby tasks: $nearbyTaskCount, Urban: $isUrban")

            isUrban

        } catch (e: Exception) {
            Log.e(TAG, "❌ Even fallback failed: ${e.message}")
            true
        }
    }

    /**
     * Check if location permissions are granted
     */
    private fun checkLocationPermissions(): Boolean {
        val fineLocation = ActivityCompat.checkSelfPermission(
            context, Manifest.permission.ACCESS_FINE_LOCATION
        ) == PackageManager.PERMISSION_GRANTED

        val coarseLocation = ActivityCompat.checkSelfPermission(
            context, Manifest.permission.ACCESS_COARSE_LOCATION
        ) == PackageManager.PERMISSION_GRANTED

        val backgroundLocation = if (android.os.Build.VERSION.SDK_INT >= android.os.Build.VERSION_CODES.Q) {
            ActivityCompat.checkSelfPermission(
                context, Manifest.permission.ACCESS_BACKGROUND_LOCATION
            ) == PackageManager.PERMISSION_GRANTED
        } else {
            true
        }

        return fineLocation && coarseLocation && backgroundLocation
    }

    /**
     * Handle geofence API errors
     */
    private fun handleGeofenceError(exception: Exception) {
        when (exception) {
            is ApiException -> {
                when (exception.statusCode) {
                    GeofenceStatusCodes.GEOFENCE_NOT_AVAILABLE -> {
                        Log.e(TAG, "Geofence service is not available")
                    }
                    GeofenceStatusCodes.GEOFENCE_TOO_MANY_GEOFENCES -> {
                        Log.e(TAG, "Too many geofences (limit: 100)")
                    }
                    GeofenceStatusCodes.GEOFENCE_TOO_MANY_PENDING_INTENTS -> {
                        Log.e(TAG, "Too many pending intents")
                    }
                    else -> {
                        Log.e(TAG, "Geofence error: ${exception.statusCode}")
                    }
                }
            }
            else -> {
                Log.e(TAG, "Unknown geofence error", exception)
            }
        }
    }

    /**
     * Update service notification with current geofence count
     */
    private fun updateServiceNotification() {
        if (LocadoForegroundService.isRunning()) {
            val intent = Intent(context, LocadoForegroundService::class.java).apply {
                action = "UPDATE_NOTIFICATION"
                putExtra("geofence_count", activeGeofences.size)
            }
            context.startService(intent)
        }
    }

    /**
     * 🏃 Calculate distance between two points (helper function)
     */
    private fun calculateDistance(lat1: Double, lon1: Double, lat2: Double, lon2: Double): Double {
        val earthRadius = 6371000.0

        val dLat = Math.toRadians(lat2 - lat1)
        val dLon = Math.toRadians(lon2 - lon1)

        val a = sin(dLat / 2) * sin(dLat / 2) +
                cos(Math.toRadians(lat1)) * cos(Math.toRadians(lat2)) *
                sin(dLon / 2) * sin(dLon / 2)

        val c = 2 * atan2(sqrt(a), sqrt(1 - a))

        return earthRadius * c
    }
}