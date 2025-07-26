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
import kotlinx.coroutines.runBlocking
import kotlin.coroutines.suspendCoroutine
import kotlin.coroutines.resume
import java.util.Locale
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

        // 🏙️ ADAPTIVE RADIUS CONSTANTS
        private const val RURAL_RADIUS_OFFSET_METERS = 100f    // +100m offset for rural areas
        private const val MIN_RADIUS_METERS = 50f              // Minimum radius
        private const val MAX_RADIUS_METERS = 500f             // Maximum radius for safety

        // 🌍 URBAN/RURAL DETECTION CONSTANTS
        private const val URBAN_DENSITY_THRESHOLD = 1000.0     // 1km - if more tasks in this radius, urban area
        private const val URBAN_TASK_COUNT_THRESHOLD = 3       // 3+ tasks = urban area

        // 🚀 ADAPTIVE INTERVAL CONSTANTS (matching LocadoForegroundService)
        private const val LOCATION_UPDATE_INTERVAL_FAST = 1000L     // 1s for fast movement
        private const val LOCATION_UPDATE_INTERVAL_NORMAL = 5000L  // 5s for normal movement
        private const val LOCATION_UPDATE_INTERVAL_SLOW = 300000L   // 5min for stationary

        private const val LOCATION_UPDATE_FASTEST_INTERVAL_FAST = 1000L   // 1s min for fast
        private const val LOCATION_UPDATE_FASTEST_INTERVAL_NORMAL = 30000L // 30s min for normal
        private const val LOCATION_UPDATE_FASTEST_INTERVAL_SLOW = 120000L  // 2min min for stationary

        // 🏃 ENHANCED SPEED THRESHOLDS FOR DYNAMIC RADIUS SCALING
        private const val SPEED_THRESHOLD_SLOW = 0.5    // 0.5 m/s (~2 km/h) - walking slowly
        private const val SPEED_THRESHOLD_WALKING = 2.0  // 2.0 m/s (~7 km/h) - normal walking
        private const val SPEED_THRESHOLD_FAST = 5.0     // 5 m/s (~18 km/h) - cycling/jogging
        private const val SPEED_THRESHOLD_VEHICLE_SLOW = 8.0  // 8 m/s (~29 km/h) - slow vehicle (bus/tram in city)
        private const val SPEED_THRESHOLD_VEHICLE_FAST = 15.0 // 15 m/s (~54 km/h) - fast vehicle (car/train)

        // 🎯 DYNAMIC RADIUS SCALING CONSTANTS
        private const val RADIUS_MULTIPLIER_WALKING = 1.0f      // 1x for walking (100m)
        private const val RADIUS_MULTIPLIER_CYCLING = 1.5f      // 1.5x for cycling (150m)
        private const val RADIUS_MULTIPLIER_VEHICLE_SLOW = 2.5f // 2.5x for slow vehicle (250m)
        private const val RADIUS_MULTIPLIER_VEHICLE_FAST = 4.0f // 4x for fast vehicle (400m)

        // 🔄 RADIUS UPDATE THRESHOLD
        private const val RADIUS_CHANGE_THRESHOLD = 20f // Only update if radius changes by 20m or more

        // 🔮 PREDICTIVE GEOFENCING CONSTANTS
        private const val TRAJECTORY_HISTORY_SIZE = 10          // Keep last 10 locations for trajectory
        private const val MIN_TRAJECTORY_POINTS = 3             // Minimum points needed for prediction
        private const val PREDICTION_TIME_SECONDS = 45          // Predict 45 seconds ahead for vehicles
        private const val PREDICTION_CONFIDENCE_THRESHOLD = 0.7 // 70% confidence needed for predictions
        private const val CLUSTER_DISTANCE_THRESHOLD = 200.0    // 200m - group nearby tasks into clusters
        private const val MIN_CLUSTER_SIZE = 2                  // Minimum 2 tasks to form a cluster

        // 🚄 TRANSPORT MODE DETECTION CONSTANTS
        private const val TRAM_SPEED_MIN = 6.0   // 22 km/h - minimum tram speed
        private const val TRAM_SPEED_MAX = 20.0  // 72 km/h - maximum tram speed
        private const val BUS_SPEED_MIN = 5.0    // 18 km/h - minimum bus speed
        private const val BUS_SPEED_MAX = 18.0   // 65 km/h - maximum bus speed
        private const val TRAIN_SPEED_MIN = 15.0 // 54 km/h - minimum train speed
        private const val CAR_SPEED_MIN = 8.0    // 29 km/h - minimum car speed in city

        // 🔋 BATTERY OPTIMIZATION CONSTANTS
        private const val LOW_BATTERY_THRESHOLD = 20            // 20% battery
        private const val CRITICAL_BATTERY_THRESHOLD = 10      // 10% battery
        private const val BATTERY_SAVE_RADIUS_MULTIPLIER = 1.5f // Increase radius when battery low

        private const val GEOFENCE_EXPIRATION_DURATION = Geofence.NEVER_EXPIRE

        // Hybrid system constants
        private const val GEOFENCE_INACTIVITY_THRESHOLD = 5 * 60 * 1000L // 5 minutes
        private const val MANUAL_CHECK_TRIGGER_DELAY = 3 * 60 * 1000L // 3 minutes
    }

    // 🏃 ENHANCED MOVEMENT STATE TRACKING
    enum class MovementState {
        STATIONARY,      // No movement or very slow movement (0-2 km/h)
        SLOW_MOVING,     // Slow movement (walking) (2-7 km/h)
        FAST_MOVING,     // Fast movement (cycling/jogging) (7-18 km/h)
        VEHICLE_SLOW,    // Slow vehicle (bus/tram in city) (18-29 km/h)
        VEHICLE_FAST     // Fast vehicle (car/train) (29+ km/h)
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
    private var currentSpeed = 0.0 // Current speed in m/s
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
        val priority: Int // Higher number = higher priority
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

            // Trigger radius recalculation with battery optimization
            if (activeGeofences.isNotEmpty()) {
                recalculateAllGeofenceRadii()
            }
        }
    }

    /**
     * 🔮 NEW: Add location point for trajectory tracking
     */
    fun addLocationPoint(latitude: Double, longitude: Double, speed: Double, bearing: Float) {
        val currentTime = System.currentTimeMillis()
        val locationPoint = LocationPoint(latitude, longitude, currentTime, speed, bearing)

        // Add to trajectory history
        trajectoryHistory.add(locationPoint)

        // Keep only recent points
        while (trajectoryHistory.size > TRAJECTORY_HISTORY_SIZE) {
            trajectoryHistory.removeAt(0)
        }

        // Update transport mode detection
        updateTransportModeDetection()

        // Update trajectory if we have enough points
        if (trajectoryHistory.size >= MIN_TRAJECTORY_POINTS) {
            currentTrajectory = calculateTrajectory()

            // Perform predictive analysis for fast movement
            if (isVehicleMovement() && currentTrajectory != null) {
                performPredictiveAnalysis()
            }
        }

        Log.d(TAG, "🔮 Added location point: speed=${"%.1f".format(speed * 3.6)} km/h, bearing=${bearing}°, transport=${currentTransportMode}")
    }

    /**
     * 🚄 NEW: Detect transport mode based on speed patterns and trajectory
     */
    private fun updateTransportModeDetection() {
        if (trajectoryHistory.size < 3) return

        val recentPoints = trajectoryHistory.takeLast(5)
        val averageSpeed = recentPoints.map { it.speed }.average()
        val speedVariance = calculateSpeedVariance(recentPoints)
        val bearingConsistency = calculateBearingConsistency(recentPoints)

        currentTransportMode = when {
            averageSpeed < SPEED_THRESHOLD_WALKING -> TransportMode.WALKING

            averageSpeed >= TRAM_SPEED_MIN && averageSpeed <= TRAM_SPEED_MAX &&
                    bearingConsistency > 0.8 && speedVariance < 2.0 -> TransportMode.TRAM

            averageSpeed >= BUS_SPEED_MIN && averageSpeed <= BUS_SPEED_MAX &&
                    bearingConsistency > 0.6 && speedVariance < 3.0 -> TransportMode.BUS

            averageSpeed >= TRAIN_SPEED_MIN && bearingConsistency > 0.9 -> TransportMode.TRAIN

            averageSpeed >= CAR_SPEED_MIN && speedVariance > 3.0 -> TransportMode.CAR

            averageSpeed >= SPEED_THRESHOLD_FAST && averageSpeed < SPEED_THRESHOLD_VEHICLE_SLOW -> TransportMode.CYCLING

            else -> TransportMode.UNKNOWN
        }

        Log.d(TAG, "🚄 Transport mode: $currentTransportMode (speed: ${"%.1f".format(averageSpeed * 3.6)} km/h, consistency: ${"%.2f".format(bearingConsistency)})")
    }

    /**
     * 🔮 NEW: Calculate trajectory from recent location points
     */
    private fun calculateTrajectory(): Trajectory? {
        if (trajectoryHistory.size < MIN_TRAJECTORY_POINTS) return null

        val recentPoints = trajectoryHistory.takeLast(TRAJECTORY_HISTORY_SIZE)
        val averageSpeed = recentPoints.map { it.speed }.average()
        val averageBearing = calculateAverageBearing(recentPoints)

        // Calculate confidence based on consistency
        val speedConsistency = 1.0 - (calculateSpeedVariance(recentPoints) / averageSpeed).coerceIn(0.0, 1.0)
        val bearingConsistency = calculateBearingConsistency(recentPoints)
        val confidence = (speedConsistency + bearingConsistency) / 2.0

        return Trajectory(recentPoints, averageSpeed, averageBearing, confidence)
    }

    /**
     * 🔮 NEW: Perform predictive analysis for upcoming locations
     */
    private fun performPredictiveAnalysis() {
        val trajectory = currentTrajectory ?: return
        val currentTime = System.currentTimeMillis()

        // Don't predict too often
        if (currentTime - lastPredictiveCheck < 10000L) return // 10 seconds
        lastPredictiveCheck = currentTime

        if (trajectory.confidence < PREDICTION_CONFIDENCE_THRESHOLD) {
            Log.d(TAG, "🔮 Skipping prediction - low confidence: ${"%.2f".format(trajectory.confidence)}")
            return
        }

        // Predict future locations
        val predictions = predictFutureLocations(trajectory, PREDICTION_TIME_SECONDS)

        // Check if any predictions are near our task locations
        val nearbyTasks = findTasksNearPredictions(predictions)

        if (nearbyTasks.isNotEmpty()) {
            Log.d(TAG, "🔮 Predictive analysis found ${nearbyTasks.size} potentially relevant tasks")

            // Enhance geofences for predicted tasks
            enhanceGeofencesForPredictions(nearbyTasks)

            // Notify location service about predictions
            locationServiceListener?.onPredictiveGeofenceRequested(predictions)
        }

        // Check for missed detections
        checkForMissedDetections(predictions)
    }

    /**
     * 🔮 NEW: Predict future locations based on trajectory
     */
    private fun predictFutureLocations(trajectory: Trajectory, secondsAhead: Int): List<LocationPoint> {
        val predictions = mutableListOf<LocationPoint>()
        val lastPoint = trajectory.points.lastOrNull() ?: return predictions

        val timeSteps = listOf(15, 30, 45) // Predict at 15s, 30s, 45s ahead

        for (timeStep in timeSteps) {
            if (timeStep > secondsAhead) break

            val distance = trajectory.averageSpeed * timeStep // meters
            val predictedLocation = calculateLocationFromBearing(
                lastPoint.latitude,
                lastPoint.longitude,
                trajectory.averageBearing.toDouble(),
                distance
            )

            predictions.add(
                LocationPoint(
                    predictedLocation.first,
                    predictedLocation.second,
                    lastPoint.timestamp + (timeStep * 1000L),
                    trajectory.averageSpeed,
                    trajectory.averageBearing
                )
            )
        }

        Log.d(TAG, "🔮 Generated ${predictions.size} location predictions")
        return predictions
    }

    /**
     * 🔮 NEW: Find tasks near predicted locations
     */
    private fun findTasksNearPredictions(predictions: List<LocationPoint>): List<GeofenceData> {
        val nearbyTasks = mutableSetOf<GeofenceData>()
        val enhancedRadius = getCurrentCalculatedRadius() * 2.0 // 2x radius for predictions

        for (prediction in predictions) {
            for (geofence in activeGeofences.values) {
                val distance = calculateDistance(
                    prediction.latitude,
                    prediction.longitude,
                    geofence.latitude,
                    geofence.longitude
                )

                if (distance <= enhancedRadius) {
                    nearbyTasks.add(geofence)
                    Log.d(TAG, "🔮 Prediction near ${geofence.title}: ${distance.toInt()}m")
                }
            }
        }

        return nearbyTasks.toList()
    }

    /**
     * 🔮 NEW: Enhance geofences for predicted nearby tasks
     */
    private fun enhanceGeofencesForPredictions(nearbyTasks: List<GeofenceData>) {
        for (task in nearbyTasks) {
            // Temporarily increase radius for predicted tasks
            val enhancedRadius = task.radius * 1.5f

            Log.d(TAG, "🔮 Enhancing geofence for ${task.title}: ${task.radius}m → ${enhancedRadius}m")

            // This would trigger a temporary geofence update
            // Implementation depends on specific requirements
        }
    }

    /**
     * 🚫 NEW: Check for missed detections and attempt recovery
     */
    private fun checkForMissedDetections(predictions: List<LocationPoint>) {
        val currentTime = System.currentTimeMillis()

        // Check if we passed near any task locations recently without notification
        val recentPoints = trajectoryHistory.takeLast(3)

        for (geofence in activeGeofences.values) {
            val lastMissedCheck = missedDetectionRecovery[geofence.id] ?: 0

            // Don't check too often for the same task
            if (currentTime - lastMissedCheck < 60000L) continue // 1 minute cooldown

            // Check if we passed near this task recently
            var minimumDistance = Double.MAX_VALUE
            for (point in recentPoints) {
                val distance = calculateDistance(
                    point.latitude,
                    point.longitude,
                    geofence.latitude,
                    geofence.longitude
                )
                minimumDistance = minOf(minimumDistance, distance)
            }

            // If we came within enhanced radius but didn't get notification
            val detectionRadius = geofence.radius * 1.5
            if (minimumDistance <= detectionRadius) {
                Log.w(TAG, "🚫 Potential missed detection for ${geofence.title}: min distance ${minimumDistance.toInt()}m")

                // Trigger recovery notification
                triggerMissedDetectionRecovery(geofence, minimumDistance)
                missedDetectionRecovery[geofence.id] = currentTime
            }
        }
    }

    /**
     * 🚫 NEW: Trigger recovery for missed detection
     */
    private fun triggerMissedDetectionRecovery(geofence: GeofenceData, distance: Double) {
        Log.d(TAG, "🚫 Triggering missed detection recovery for ${geofence.title}")

        // This would send a recovery notification
        // Implementation depends on integration with notification system
    }

    /**
     * 🔮 NEW: Create smart clusters of nearby tasks
     */
    fun createSmartClusters() {
        taskClusters.clear()
        val unclustered = activeGeofences.values.toMutableList()
        var clusterId = 0

        while (unclustered.isNotEmpty()) {
            val centerTask = unclustered.removeAt(0)
            val cluster = mutableListOf(centerTask)

            // Find nearby tasks
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

            // Create cluster if we have enough tasks
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
                Log.d(TAG, "🔮 Created cluster ${taskCluster.id} with ${cluster.size} tasks (radius: ${clusterRadius.toInt()}m)")
            }
        }

        Log.d(TAG, "🔮 Created ${taskClusters.size} smart clusters from ${activeGeofences.size} tasks")
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

        // If no geofence events for longer than threshold, consider inactive
        val shouldBeActive = if (lastGeofenceEventTime == 0L) {
            // Just started - consider active initially
            true
        } else {
            timeSinceLastEvent < GEOFENCE_INACTIVITY_THRESHOLD
        }

        // Detect state change
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
     * Get all active geofence locations for manual backup
     */
    fun getActiveGeofenceLocations(): List<GeofenceData> {
        return activeGeofences.values.toList()
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

    /**
     * 🏃 Update movement state and trigger adaptive intervals
     */
    fun updateMovementState(newState: MovementState) {
        if (currentMovementState != newState) {
            val previousState = currentMovementState
            currentMovementState = newState

            Log.d(TAG, "🏃 Movement state changed: $previousState → $newState")

            // Calculate new intervals
            val (interval, fastestInterval) = getAdaptiveLocationIntervals()

            // Notify location service about change
            locationServiceListener?.onAdaptiveIntervalChanged(interval, fastestInterval)

            Log.d(TAG, "🕐 New location intervals: ${interval}ms (fastest: ${fastestInterval}ms)")
        }
    }

    /**
     * 🚀 ENHANCED: Update speed and trigger dynamic radius scaling with predictive features
     */
    fun updateSpeedAndRadius(newSpeed: Double) {
        val speedChanged = abs(currentSpeed - newSpeed) > 1.0 // Only update if speed changes by 1+ m/s
        currentSpeed = newSpeed

        if (speedChanged) {
            Log.d(TAG, "🏃 Speed updated: ${"%.2f".format(newSpeed)} m/s (${"%.1f".format(newSpeed * 3.6)} km/h)")

            // Update movement state based on new speed
            val newMovementState = calculateMovementStateFromSpeed(newSpeed)
            updateMovementState(newMovementState)

            // Calculate new radius based on speed with battery optimization
            val newRadius = calculateEnhancedSpeedBasedRadius(newSpeed, currentBaseRadius)

            if (abs(newRadius - lastCalculatedRadius) >= RADIUS_CHANGE_THRESHOLD) {
                Log.d(TAG, "🎯 Significant radius change detected: ${lastCalculatedRadius}m → ${newRadius}m")
                lastCalculatedRadius = newRadius

                // Notify location service that radius update is needed
                locationServiceListener?.onRadiusUpdateRequested(newRadius)

                // Optionally trigger geofence re-registration with new radius
                if (activeGeofences.isNotEmpty()) {
                    Log.d(TAG, "🔄 Triggering geofence radius update for ${activeGeofences.size} geofences")
                    // This will be handled by the location service
                }
            }
        }
    }

    /**
     * 🚀 NEW: Calculate movement state from current speed
     */
    private fun calculateMovementStateFromSpeed(speed: Double): MovementState {
        return when {
            speed >= SPEED_THRESHOLD_VEHICLE_FAST -> MovementState.VEHICLE_FAST
            speed >= SPEED_THRESHOLD_VEHICLE_SLOW -> MovementState.VEHICLE_SLOW
            speed >= SPEED_THRESHOLD_FAST -> MovementState.FAST_MOVING
            speed >= SPEED_THRESHOLD_WALKING -> MovementState.SLOW_MOVING
            else -> MovementState.STATIONARY
        }
    }

    /**
     * 🔋 ENHANCED: Calculate speed-based radius with battery optimization
     */
    private fun calculateEnhancedSpeedBasedRadius(speed: Double, baseRadius: Float): Float {
        val multiplier = when {
            speed >= SPEED_THRESHOLD_VEHICLE_FAST -> {
                Log.d(TAG, "🚄 Fast vehicle detected (${String.format("%.1f", speed * 3.6)} km/h) - using ${RADIUS_MULTIPLIER_VEHICLE_FAST}x radius")
                RADIUS_MULTIPLIER_VEHICLE_FAST
            }
            speed >= SPEED_THRESHOLD_VEHICLE_SLOW -> {
                Log.d(TAG, "🚌 Slow vehicle detected (${String.format("%.1f", speed * 3.6)} km/h) - using ${RADIUS_MULTIPLIER_VEHICLE_SLOW}x radius")
                RADIUS_MULTIPLIER_VEHICLE_SLOW
            }
            speed >= SPEED_THRESHOLD_FAST -> {
                Log.d(TAG, "🚴 Fast movement detected (${String.format("%.1f", speed * 3.6)} km/h) - using ${RADIUS_MULTIPLIER_CYCLING}x radius")
                RADIUS_MULTIPLIER_CYCLING
            }
            else -> {
                Log.d(TAG, "🚶 Walking/stationary detected (${String.format("%.1f", speed * 3.6)} km/h) - using ${RADIUS_MULTIPLIER_WALKING}x radius")
                RADIUS_MULTIPLIER_WALKING
            }
        }

        var calculatedRadius = baseRadius * multiplier

        // 🔋 Apply battery optimization
        if (isBatteryOptimizationActive) {
            calculatedRadius *= BATTERY_SAVE_RADIUS_MULTIPLIER
            Log.d(TAG, "🔋 Battery optimization applied: radius increased by ${BATTERY_SAVE_RADIUS_MULTIPLIER}x")
        }

        // Ensure radius stays within bounds
        val finalRadius = calculatedRadius.coerceIn(MIN_RADIUS_METERS, MAX_RADIUS_METERS)

        Log.d(TAG, "🎯 Enhanced speed-based radius calculation:")
        Log.d(TAG, "  - Speed: ${"%.2f".format(speed)} m/s (${"%.1f".format(speed * 3.6)} km/h)")
        Log.d(TAG, "  - Transport mode: $currentTransportMode")
        Log.d(TAG, "  - Base radius: ${baseRadius}m")
        Log.d(TAG, "  - Speed multiplier: ${multiplier}x")
        Log.d(TAG, "  - Battery optimization: ${if (isBatteryOptimizationActive) "ON" else "OFF"}")
        Log.d(TAG, "  - Final radius: ${finalRadius}m")

        return finalRadius
    }

    /**
     * 🚀 NEW: Get current calculated radius for external use
     */
    fun getCurrentCalculatedRadius(): Float {
        return lastCalculatedRadius
    }

    /**
     * 🚀 NEW: Get current transport mode
     */
    fun getCurrentTransportMode(): TransportMode {
        return currentTransportMode
    }

    /**
     * 🚀 NEW: Check if current movement is vehicle-based
     */
    fun isVehicleMovement(): Boolean {
        return currentMovementState == MovementState.VEHICLE_SLOW ||
                currentMovementState == MovementState.VEHICLE_FAST
    }

    /**
     * 🚀 ENHANCED: Force recalculate all geofence radii with predictive features
     */
    fun recalculateAllGeofenceRadii(): Boolean {
        if (activeGeofences.isEmpty()) {
            Log.d(TAG, "No active geofences to recalculate")
            return false
        }

        Log.d(TAG, "🔄 Recalculating radii for ${activeGeofences.size} geofences based on current speed: ${"%.2f".format(currentSpeed)} m/s")

        val updatedGeofences = mutableListOf<GeofenceData>()

        for (geofenceData in activeGeofences.values) {
            val newRadius = calculateEnhancedSpeedBasedRadius(currentSpeed, currentBaseRadius)
            val updatedGeofence = geofenceData.copy(radius = newRadius)
            updatedGeofences.add(updatedGeofence)
        }

        // Remove all current geofences and re-add with new radii
        return if (updatedGeofences.isNotEmpty()) {
            Log.d(TAG, "🔄 Re-registering ${updatedGeofences.size} geofences with updated radii")

            // This will trigger async removal and re-addition
            removeAllGeofences().addOnSuccessListener {
                Log.d(TAG, "✅ All geofences removed, re-adding with new radii")
                addGeofences(updatedGeofences)

                // 🔮 Recreate smart clusters after radius update
                createSmartClusters()
            }.addOnFailureListener { exception ->
                Log.e(TAG, "❌ Failed to remove geofences for radius update: ${exception.message}")
            }

            true
        } else {
            false
        }
    }

    /**
     * 🕐 ENHANCED: Calculate adaptive location intervals with predictive optimization
     */
    private fun getAdaptiveLocationIntervals(): Pair<Long, Long> {
        val baseIntervals = when (currentMovementState) {
            MovementState.VEHICLE_FAST -> Pair(250L, 100L)    // Ultra-fast for fast vehicles
            MovementState.VEHICLE_SLOW -> Pair(500L, 250L)    // Fast for slow vehicles (tram/bus)
            MovementState.FAST_MOVING -> Pair(
                LOCATION_UPDATE_INTERVAL_FAST,
                LOCATION_UPDATE_FASTEST_INTERVAL_FAST
            )
            MovementState.SLOW_MOVING -> Pair(
                LOCATION_UPDATE_INTERVAL_NORMAL,
                LOCATION_UPDATE_FASTEST_INTERVAL_NORMAL
            )
            MovementState.STATIONARY -> Pair(
                LOCATION_UPDATE_INTERVAL_SLOW,
                LOCATION_UPDATE_FASTEST_INTERVAL_SLOW
            )
        }

        // 🔋 Apply battery optimization
        return if (isBatteryOptimizationActive && batteryLevel <= CRITICAL_BATTERY_THRESHOLD) {
            Log.d(TAG, "🔋 Critical battery - reducing location frequency")
            Pair(baseIntervals.first * 2, baseIntervals.second * 2)
        } else if (isBatteryOptimizationActive) {
            Log.d(TAG, "🔋 Low battery - slightly reducing location frequency")
            Pair((baseIntervals.first * 1.5).toLong(), (baseIntervals.second * 1.5).toLong())
        } else {
            baseIntervals
        }
    }

    /**
     * 🏃 Get current movement state
     */
    fun getCurrentMovementState(): MovementState {
        return currentMovementState
    }

    /**
     * 🚀 NEW: Get current speed
     */
    fun getCurrentSpeed(): Double {
        return currentSpeed
    }

    /**
     * 🔮 NEW: Get predictive insights for debugging
     */
    fun getPredictiveInsights(): Map<String, Any> {
        return mapOf(
            "trajectoryPoints" to trajectoryHistory.size,
            "currentTrajectory" to (currentTrajectory?.let {
                mapOf(
                    "confidence" to it.confidence,
                    "averageSpeed" to it.averageSpeed,
                    "averageBearing" to it.averageBearing
                )
            } ?: "none"),
            "transportMode" to currentTransportMode.name,
            "clusters" to taskClusters.size,
            "batteryOptimization" to isBatteryOptimizationActive,
            "batteryLevel" to batteryLevel
        )
    }

    // Helper functions for calculations
    private fun calculateSpeedVariance(points: List<LocationPoint>): Double {
        if (points.size < 2) return 0.0
        val averageSpeed = points.map { it.speed }.average()
        return points.map { (it.speed - averageSpeed) * (it.speed - averageSpeed) }.average()
    }

    private fun calculateBearingConsistency(points: List<LocationPoint>): Double {
        if (points.size < 2) return 1.0

        val bearings = points.map { it.bearing }
        val avgBearing = calculateAverageBearing(points)

        val deviations = bearings.map {
            val diff = abs(it - avgBearing)
            minOf(diff, 360f - diff) // Handle circular nature of bearings
        }

        val avgDeviation = deviations.average()
        return (180.0 - avgDeviation) / 180.0 // Convert to 0-1 scale
    }

    private fun calculateAverageBearing(points: List<LocationPoint>): Float {
        if (points.isEmpty()) return 0f

        var x = 0.0
        var y = 0.0

        for (point in points) {
            val radians = Math.toRadians(point.bearing.toDouble())
            x += cos(radians)
            y += sin(radians)
        }

        val avgRadians = atan2(y / points.size, x / points.size)
        var avgDegrees = Math.toDegrees(avgRadians).toFloat()

        if (avgDegrees < 0) avgDegrees += 360f
        return avgDegrees
    }

    private fun calculateLocationFromBearing(
        startLat: Double,
        startLon: Double,
        bearing: Double,
        distance: Double
    ): Pair<Double, Double> {
        val earthRadius = 6371000.0 // meters
        val bearingRad = Math.toRadians(bearing)
        val startLatRad = Math.toRadians(startLat)
        val startLonRad = Math.toRadians(startLon)

        val angularDistance = distance / earthRadius

        val endLatRad = asin(
            sin(startLatRad) * cos(angularDistance) +
                    cos(startLatRad) * sin(angularDistance) * cos(bearingRad)
        )

        val endLonRad = startLonRad + atan2(
            sin(bearingRad) * sin(angularDistance) * cos(startLatRad),
            cos(angularDistance) - sin(startLatRad) * sin(endLatRad)
        )

        return Pair(Math.toDegrees(endLatRad), Math.toDegrees(endLonRad))
    }

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
        return maxDistance + 50.0 // Add 50m buffer
    }

    private fun calculateClusterPriority(tasks: List<GeofenceData>): Int {
        // Priority based on number of tasks and their importance
        return tasks.size * 10 // Simple priority calculation
    }

    /**
     * Add a single geofence
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

        // Update base radius for future calculations
        currentBaseRadius = radius

        val adaptiveRadius = calculateAdaptiveRadius(latitude, longitude, radius)
        val geofenceData = GeofenceData(id, latitude, longitude, adaptiveRadius, title, description)

        val geofence = Geofence.Builder()
            .setRequestId(id)
            .setCircularRegion(latitude, longitude, adaptiveRadius)
            .setExpirationDuration(GEOFENCE_EXPIRATION_DURATION)
            .setTransitionTypes(Geofence.GEOFENCE_TRANSITION_ENTER or Geofence.GEOFENCE_TRANSITION_EXIT)
            .setLoiteringDelay(5000) // 5 seconds
            .setNotificationResponsiveness(0)
            .build()

        val geofencingRequest = GeofencingRequest.Builder()
            .setInitialTrigger(GeofencingRequest.INITIAL_TRIGGER_ENTER)
            .addGeofence(geofence)
            .build()

        Log.d(TAG, "Adding geofence: $id at ($latitude, $longitude) with adaptive radius ${adaptiveRadius}m (original: ${radius}m)")

        val task = geofencingClient.addGeofences(geofencingRequest, geofencePendingIntent)

        task.addOnSuccessListener {
            activeGeofences[id] = geofenceData
            Log.d(TAG, "Geofence $id added successfully. Total active: ${activeGeofences.size}")

            // Reset geofencing status when new geofences are added
            lastGeofenceEventTime = System.currentTimeMillis()
            isGeofencingActive = true

            updateServiceNotification()

            // 🔮 Recreate clusters when new geofence is added
            if (activeGeofences.size >= MIN_CLUSTER_SIZE) {
                createSmartClusters()
            }
        }

        task.addOnFailureListener { exception ->
            Log.e(TAG, "Failed to add geofence $id", exception)
            handleGeofenceError(exception)
        }

        return task
    }

    /**
     * Add multiple geofences at once
     */
    fun addGeofences(geofences: List<GeofenceData>): Task<Void>? {

        if (!checkLocationPermissions()) {
            Log.e(TAG, "Location permissions not granted")
            return null
        }

        if (geofences.isEmpty()) {
            Log.w(TAG, "No geofences to add")
            return null
        }

        val geofenceList = geofences.map { data ->
            // 🎯 ENHANCED LOGIC: Calculate adaptive radius for each geofence including speed-based scaling
            val adaptiveRadius = calculateAdaptiveRadius(data.latitude, data.longitude, data.radius)

            Geofence.Builder()
                .setRequestId(data.id)
                .setCircularRegion(data.latitude, data.longitude, adaptiveRadius)
                .setExpirationDuration(GEOFENCE_EXPIRATION_DURATION)
                .setTransitionTypes(Geofence.GEOFENCE_TRANSITION_ENTER or Geofence.GEOFENCE_TRANSITION_EXIT)
                .setLoiteringDelay(5000)
                .build()
        }

        val geofencingRequest = GeofencingRequest.Builder()
            .setInitialTrigger(GeofencingRequest.INITIAL_TRIGGER_ENTER)
            .addGeofences(geofenceList)
            .build()

        Log.d(TAG, "Adding ${geofences.size} geofences with predictive speed-based adaptive radii")

        val task = geofencingClient.addGeofences(geofencingRequest, geofencePendingIntent)

        task.addOnSuccessListener {
            geofences.forEach { data ->
                // 🎯 ENHANCED LOGIC: Store geofence with adaptive radius including speed-based scaling
                val adaptiveRadius = calculateAdaptiveRadius(data.latitude, data.longitude, data.radius)
                val adaptiveGeofenceData = data.copy(radius = adaptiveRadius)
                activeGeofences[data.id] = adaptiveGeofenceData
            }
            Log.d(TAG, "${geofences.size} geofences added successfully with predictive adaptive radii. Total active: ${activeGeofences.size}")

            // Reset geofencing status when new geofences are added
            lastGeofenceEventTime = System.currentTimeMillis()
            isGeofencingActive = true

            updateServiceNotification()

            // 🔮 Create smart clusters after adding multiple geofences
            createSmartClusters()
        }

        task.addOnFailureListener { exception ->
            Log.e(TAG, "Failed to add geofences", exception)
            handleGeofenceError(exception)
        }

        return task
    }

    /**
     * Remove a single geofence by ID
     */
    fun removeGeofence(id: String): Task<Void> {
        Log.d(TAG, "Removing geofence: $id")

        val task = geofencingClient.removeGeofences(listOf(id))

        task.addOnSuccessListener {
            activeGeofences.remove(id)
            Log.d(TAG, "Geofence $id removed successfully. Total active: ${activeGeofences.size}")
            updateServiceNotification()

            // 🔮 Recreate clusters after removal
            if (activeGeofences.size >= MIN_CLUSTER_SIZE) {
                createSmartClusters()
            }
        }

        task.addOnFailureListener { exception ->
            Log.e(TAG, "Failed to remove geofence $id", exception)
        }

        return task
    }

    /**
     * Remove multiple geofences by IDs
     */
    fun removeGeofences(ids: List<String>): Task<Void> {
        Log.d(TAG, "Removing ${ids.size} geofences")

        val task = geofencingClient.removeGeofences(ids)

        task.addOnSuccessListener {
            ids.forEach { id ->
                activeGeofences.remove(id)
            }
            Log.d(TAG, "${ids.size} geofences removed successfully. Total active: ${activeGeofences.size}")
            updateServiceNotification()

            // 🔮 Recreate clusters after removal
            if (activeGeofences.size >= MIN_CLUSTER_SIZE) {
                createSmartClusters()
            }
        }

        task.addOnFailureListener { exception ->
            Log.e(TAG, "Failed to remove geofences", exception)
        }

        return task
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
            Log.d(TAG, "All $count geofences removed successfully")
            updateServiceNotification()
        }

        task.addOnFailureListener { exception ->
            Log.e(TAG, "Failed to remove all geofences", exception)
        }

        return task
    }

    /**
     * Get list of active geofence IDs
     */
    fun getActiveGeofenceIds(): List<String> {
        return activeGeofences.keys.toList()
    }

    /**
     * Get active geofence count
     */
    fun getActiveGeofenceCount(): Int {
        return activeGeofences.size
    }

    /**
     * Get geofence data by ID
     */
    fun getGeofenceData(id: String): GeofenceData? {
        return activeGeofences[id]
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
            true // Not required for API < 29
        }

        val hasPermissions = fineLocation && coarseLocation && backgroundLocation

        if (!hasPermissions) {
            Log.w(TAG, "Missing permissions - Fine: $fineLocation, Coarse: $coarseLocation, Background: $backgroundLocation")
        }

        return hasPermissions
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
     * 🌍 DETECT IF LOCATION IS IN URBAN OR RURAL AREA USING GOOGLE PLACES API
     */
    private suspend fun isUrbanArea(latitude: Double, longitude: Double): Boolean {
        return try {
            Log.d(TAG, "🌍 Analyzing location using Google Places API: (${"%.4f".format(latitude)}, ${"%.4f".format(longitude)})")

            // Initialize Places client
            if (!::placesClient.isInitialized) {
                val apiKey = getApiKey()
                if (apiKey.isBlank()) {
                    Log.w(TAG, "⚠️ No API key found - using fallback method")
                    return isUrbanAreaFallback(latitude, longitude)
                }
                Places.initialize(context, apiKey)
                placesClient = Places.createClient(context)
            }

            // Reverse geocoding for address components
            val result = withContext(Dispatchers.IO) {
                performReverseGeocoding(latitude, longitude)
            }

            val isUrban = analyzeAddressComponents(result, latitude, longitude)

            Log.d(TAG, "🏙️ Location (${"%.4f".format(latitude)}, ${"%.4f".format(longitude)}) - Urban: $isUrban")
            isUrban

        } catch (e: Exception) {
            Log.e(TAG, "❌ Error detecting urban area with Places API: ${e.message}")
            // Fallback to old algorithm
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
            // Urban indicators
            address.locality != null && address.subLocality != null -> "URBAN_HIGH"
            address.locality != null -> "URBAN_MEDIUM"
            address.subLocality != null -> "URBAN_LOW"
            // Rural indicators
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

            // Count tasks nearby (1km radius) - old algorithm
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
            Log.d(TAG, "🔄 Fallback: Location (${"%.4f".format(latitude)}, ${"%.4f".format(longitude)}) - Nearby tasks: $nearbyTaskCount, Urban: $isUrban")

            isUrban

        } catch (e: Exception) {
            Log.e(TAG, "❌ Even fallback failed: ${e.message}")
            true // Default to urban for safety
        }
    }

    /**
     * 🎯 ENHANCED: Calculate adaptive radius based on user settings, location type, speed, AND battery
     */
    private fun calculateAdaptiveRadius(latitude: Double, longitude: Double, userRadius: Float? = null): Float {
        return try {
            // Read user settings from SharedPreferences
            val prefs = context.getSharedPreferences("locado_settings", Context.MODE_PRIVATE)
            val userSetRadius = userRadius ?: prefs.getFloat("geofence_radius", DEFAULT_RADIUS_METERS)

            Log.d(TAG, "🎯 User set radius: ${userSetRadius}m")

            // 🆕 Use runBlocking for suspend function
            val isUrban = runBlocking {
                isUrbanArea(latitude, longitude)
            }

            // First apply urban/rural adjustment
            val locationAdjustedRadius = if (isUrban) {
                // Urban area - use user set radius
                userSetRadius
            } else {
                // Rural area - add offset to user radius for better coverage
                userSetRadius + RURAL_RADIUS_OFFSET_METERS
            }

            // 🚀 NEW: Then apply speed-based scaling with battery optimization
            val speedAdjustedRadius = calculateEnhancedSpeedBasedRadius(currentSpeed, locationAdjustedRadius)

            // Limit radius to min/max values for safety
            val finalRadius = speedAdjustedRadius.coerceIn(MIN_RADIUS_METERS, MAX_RADIUS_METERS)

            Log.d(TAG, "🎯 FINAL adaptive radius calculation:")
            Log.d(TAG, "  - Location: (${"%.4f".format(latitude)}, ${"%.4f".format(longitude)})")
            Log.d(TAG, "  - Area type: ${if (isUrban) "URBAN" else "RURAL"}")
            Log.d(TAG, "  - Transport: $currentTransportMode")
            Log.d(TAG, "  - User radius: ${userSetRadius}m")
            Log.d(TAG, "  - Location adjusted: ${locationAdjustedRadius}m")
            Log.d(TAG, "  - Current speed: ${"%.2f".format(currentSpeed)} m/s (${"%.1f".format(currentSpeed * 3.6)} km/h)")
            Log.d(TAG, "  - Speed adjusted: ${speedAdjustedRadius}m")
            Log.d(TAG, "  - Battery optimization: ${if (isBatteryOptimizationActive) "ON (${batteryLevel}%)" else "OFF"}")
            Log.d(TAG, "  - FINAL radius: ${finalRadius}m")

            finalRadius

        } catch (e: Exception) {
            Log.e(TAG, "❌ Error calculating FINAL adaptive radius: ${e.message}")
            userRadius ?: DEFAULT_RADIUS_METERS // Fallback to default
        }
    }

    /**
     * 🏃 Calculate distance between two points (helper function)
     */
    private fun calculateDistance(lat1: Double, lon1: Double, lat2: Double, lon2: Double): Double {
        val earthRadius = 6371000.0 // meters

        val dLat = Math.toRadians(lat2 - lat1)
        val dLon = Math.toRadians(lon2 - lon1)

        val a = kotlin.math.sin(dLat / 2) * kotlin.math.sin(dLat / 2) +
                kotlin.math.cos(Math.toRadians(lat1)) * kotlin.math.cos(Math.toRadians(lat2)) *
                kotlin.math.sin(dLon / 2) * kotlin.math.sin(dLon / 2)

        val c = 2 * kotlin.math.atan2(kotlin.math.sqrt(a), kotlin.math.sqrt(1 - a))

        return earthRadius * c
    }
}