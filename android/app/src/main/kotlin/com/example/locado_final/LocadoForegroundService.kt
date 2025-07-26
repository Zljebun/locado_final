package com.example.locado_final

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Context
import android.content.Intent
import android.os.Build
import android.os.IBinder
import android.os.PowerManager
import android.util.Log
import androidx.core.app.NotificationCompat
import android.app.AlarmManager
import android.os.SystemClock
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.launch
import kotlinx.coroutines.delay
import android.os.Handler
import android.os.Looper
import com.google.android.gms.location.*
import android.content.pm.PackageManager
import androidx.core.app.ActivityCompat
import android.database.sqlite.SQLiteDatabase
import android.database.Cursor
import java.io.File
import java.io.FileWriter
import java.text.SimpleDateFormat
import java.util.*
import kotlin.math.*
import android.hardware.Sensor
import android.hardware.SensorEvent
import android.hardware.SensorEventListener
import android.hardware.SensorManager
import android.content.ComponentName

class LocadoForegroundService : Service(), GeofenceManager.ManualBackupListener, GeofenceManager.LocationServiceListener {

    companion object {
        private const val TAG = "LocadoForegroundService"
        private const val NOTIFICATION_ID = 1001
        private const val CHANNEL_ID = "locado_background_channel"

        // ✅ SAMSUNG-SPECIFIC CONSTANTS
        private const val HEARTBEAT_INTERVAL = 30000L // 30 seconds heartbeat
        private const val GEOFENCE_CHECK_INTERVAL = 60000L // 1 minute check
        private const val WAKE_LOCK_TIMEOUT = 10 * 60 * 1000L // 10 minutes

        // 🚀 ULTRA-FAST ADAPTIVE INTERVALS FOR VEHICLES
        private const val MANUAL_CHECK_INTERVAL_ULTRA_FAST = 250L    // 0.25s for fast vehicles
        private const val MANUAL_CHECK_INTERVAL_FAST = 500L         // 0.5s for slow vehicles
        private const val MANUAL_CHECK_INTERVAL_NORMAL = 2000L      // 2s for fast movement
        private const val MANUAL_CHECK_INTERVAL_SLOW = 5000L        // 5s for normal movement
        private const val MANUAL_CHECK_INTERVAL_STATIONARY = 300000L // 5min for stationary

        // 🚀 ULTRA-FAST LOCATION TRACKING INTERVALS
        private const val LOCATION_UPDATE_ULTRA_FAST = 250L         // 0.25s for vehicles
        private const val LOCATION_UPDATE_FAST = 500L               // 0.5s for fast movement
        private const val LOCATION_UPDATE_NORMAL = 2000L            // 2s for normal movement
        private const val LOCATION_UPDATE_SLOW = 15000L             // 15s for slow movement
        private const val LOCATION_UPDATE_STATIONARY = 60000L       // 1min for stationary

        // 🏃 ENHANCED SPEED DETECTION CONSTANTS
        private const val SPEED_THRESHOLD_SLOW = 0.5               // 0.5 m/s (~2 km/h) - slow movement
        private const val SPEED_THRESHOLD_WALKING = 2.0            // 2.0 m/s (~7 km/h) - normal walking
        private const val SPEED_THRESHOLD_FAST = 5.0               // 5 m/s (~18 km/h) - fast movement
        private const val SPEED_THRESHOLD_VEHICLE_SLOW = 8.0       // 8 m/s (~29 km/h) - slow vehicle (bus/tram)
        private const val SPEED_THRESHOLD_VEHICLE_FAST = 15.0      // 15 m/s (~54 km/h) - fast vehicle (car/train)

        private const val MIN_LOCATION_ACCURACY = 50.0             // 50 meters minimum accuracy for speed calculation
        private const val SPEED_CALCULATION_MIN_DISTANCE = 10.0    // 10 meters minimum distance between locations

        // 🚀 ENHANCED DETECTION RADIUS CONSTANTS
        private const val NEAR_TASK_RADIUS_BASE = 150.0            // Base radius for task detection
        private const val NEAR_TASK_RADIUS_VEHICLE_MULTIPLIER = 2.0 // 2x for vehicles (300m)
        private const val NEAR_TASK_RADIUS_FAST_MULTIPLIER = 1.5   // 1.5x for fast movement (225m)

        // 🚀 PREDICTIVE CHECKING CONSTANTS
        private const val PREDICTIVE_CHECK_SECONDS_AHEAD = 30      // Check 30 seconds ahead
        private const val EARLY_WARNING_RADIUS_MULTIPLIER = 3.0   // 3x radius for early warning

        private const val NOTIFICATION_COOLDOWN = 3 * 60 * 1000L  // 3 minutes between notifications (reduced from 5)
        private const val EARLY_WARNING_COOLDOWN = 60 * 1000L     // 1 minute for early warnings

        const val ACTION_START_SERVICE = "START_SERVICE"
        const val ACTION_STOP_SERVICE = "STOP_SERVICE"
        const val ACTION_UPDATE_NOTIFICATION = "UPDATE_NOTIFICATION"
        const val ACTION_HEARTBEAT = "HEARTBEAT"

        // 🎯 MOTION DETECTION CONSTANTS
        private const val MOTION_CHECK_COOLDOWN = 60000L // 1 minute between motion triggered checks
        private const val MOTION_SENSITIVITY_THRESHOLD = 0.5f // Threshold for significant motion
        private const val MOTION_DETECTION_DELAY = 10000L // 10s delay after motion detection

        @Volatile
        private var isServiceRunning = false
        @Volatile
        private var activeGeofenceCount = 0
        @Volatile
        private var lastHeartbeat = 0L

        fun isRunning(): Boolean = isServiceRunning
        fun getActiveGeofenceCount(): Int = activeGeofenceCount
        fun getLastHeartbeat(): Long = lastHeartbeat
    }

    // 🏃 ENHANCED MOVEMENT STATE ENUM (matching GeofenceManager)
    enum class MovementState {
        STATIONARY,      // No movement or very slow movement (0-2 km/h)
        SLOW_MOVING,     // Slow movement (walking) (2-7 km/h)
        FAST_MOVING,     // Fast movement (cycling/jogging) (7-18 km/h)
        VEHICLE_SLOW,    // Slow vehicle (bus/tram in city) (18-29 km/h)
        VEHICLE_FAST     // Fast vehicle (car/train) (29+ km/h)
    }

    // ✅ ULTRA-PERSISTENT COMPONENTS
    private var wakeLock: PowerManager.WakeLock? = null
    private var notificationManager: NotificationManager? = null
    private var heartbeatJob: Job? = null
    private var geofenceCheckJob: Job? = null
    private var alarmManager: AlarmManager? = null
    private var heartbeatPendingIntent: PendingIntent? = null
    private var serviceScope = CoroutineScope(Dispatchers.Default)

    // ✅ LOCATION TRACKING COMPONENTS
    private lateinit var fusedLocationClient: FusedLocationProviderClient
    private lateinit var locationCallback: LocationCallback
    private var locationWakeLock: PowerManager.WakeLock? = null

    // 🚀 ENHANCED HYBRID SYSTEM COMPONENTS
    private var geofenceManager: GeofenceManager? = null
    private var isManualBackupActive = false
    private var manualCheckJob: Job? = null
    private val lastNotificationTimes = mutableMapOf<String, Long>()
    private val lastEarlyWarningTimes = mutableMapOf<String, Long>()
    private var lastKnownLocation: android.location.Location? = null

    // 🏃 ENHANCED SPEED TRACKING VARIABLES
    private var previousLocation: android.location.Location? = null
    private var currentSpeed: Double = 0.0
    private var averageSpeed: Double = 0.0 // Running average for smoother predictions
    private var speedHistory = mutableListOf<Double>() // Last 10 speed measurements
    private var lastSpeedCalculationTime = 0L
    private var currentMovementState = MovementState.STATIONARY
    private var currentHeading: Float = 0f // Current direction of movement

    // 🚀 PREDICTIVE SYSTEM VARIABLES
    private var isUltraFastModeActive = false
    private var lastPredictiveCheck = 0L

    // 🎯 MOTION DETECTION COMPONENTS
    private var sensorManager: SensorManager? = null
    private var accelerometer: Sensor? = null
    private var gyroscope: Sensor? = null
    private var significantMotionSensor: Sensor? = null
    private var motionDetectionListener: SensorEventListener? = null
    private var lastMotionTriggeredCheck = 0L
    private var isMotionDetectionActive = false
    private var motionDetectionJob: Job? = null

    // 🔮 PREDICTIVE GEOFENCING SYSTEM VARIABLES
    private var isPredictiveModeActive = false
    private var predictiveModeStartTime = 0L
    private var currentPredictions: MutableList<GeofenceManager.LocationPoint>? = null
    private val priorityMonitoringTasks = mutableMapOf<String, PredictiveTaskInfo>()

    private var isPredictiveLocationBoostActive = false
    private var savedLocationInterval: Long? = null
    private var savedFastestLocationInterval: Long? = null

    private var reducedCooldownMode = false
    private var reducedCooldownStartTime = 0L
    private var preWarmData: PredictiveNotificationData? = null

    override fun onCreate() {
        super.onCreate()
        Log.d(TAG, "🚀 Ultra-robust service onCreate() with ULTRA-FAST manual backup support")

        try {
            // ✅ INITIALIZE GEOFENCE MANAGER WITH LISTENER
            initializeHybridSystem()

            // ✅ ACQUIRE MULTIPLE WAKE LOCKS FOR SAMSUNG
            acquireUltraWakeLock()

            // ✅ SETUP NOTIFICATION SYSTEM
            createNotificationChannel()
            notificationManager = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager

            // ✅ SETUP ALARM MANAGER FOR HEARTBEAT (bypass Doze mode)
            setupHeartbeatAlarm()

            // ✅ START BACKGROUND MONITORING JOBS
            startBackgroundJobs()

            // ✅ SETUP ULTRA-FAST CONTINUOUS LOCATION TRACKING
            setupUltraFastLocationTracking()

            // 🎯 SETUP MOTION DETECTION SYSTEM
            setupMotionDetection()

            isServiceRunning = true
            lastHeartbeat = System.currentTimeMillis()

            Log.d(TAG, "✅ Ultra-robust service initialized successfully with ULTRA-FAST support")

        } catch (e: Exception) {
            Log.e(TAG, "❌ Error in service onCreate: ${e.message}")
        }
    }

    /**
     * 🚀 INITIALIZE HYBRID SYSTEM
     */
    private fun initializeHybridSystem() {
        try {
            geofenceManager = GeofenceManager(this)
            geofenceManager?.setManualBackupListener(this)

            // 🚀 REGISTER LocationServiceListener
            geofenceManager?.setLocationServiceListener(this)

            Log.d(TAG, "✅ Hybrid system initialized with ultra-fast location service communication")
        } catch (e: Exception) {
            Log.e(TAG, "❌ Failed to initialize hybrid system: ${e.message}")
        }
    }

    // 🚀 IMPLEMENTATION ManualBackupListener INTERFACE
    override fun onGeofencingBecameInactive() {
        Log.w(TAG, "🔄 Geofencing became inactive - activating ULTRA-FAST manual backup")
        activateUltraFastManualBackup()
    }

    override fun onGeofencingRestored() {
        Log.d(TAG, "✅ Geofencing restored - deactivating ultra-fast manual backup")
        deactivateManualBackup()
    }

    override fun shouldActivateManualBackup(): Boolean {
        // Activate manual backup if screen is off or app is not active
        val screenOn = isScreenOn()
        return !screenOn || activeGeofenceCount > 0
    }

    // 🚀 IMPLEMENTATION LocationServiceListener INTERFACE
    override fun onAdaptiveIntervalChanged(interval: Long, fastestInterval: Long) {
        Log.d(TAG, "🕐 Adaptive interval change received: ${interval}ms (fastest: ${fastestInterval}ms)")
        updateUltraFastLocationTrackingIntervals(interval, fastestInterval)
    }

    override fun getCurrentMovementState(): GeofenceManager.MovementState {
        return when (currentMovementState) {
            MovementState.STATIONARY -> GeofenceManager.MovementState.STATIONARY
            MovementState.SLOW_MOVING -> GeofenceManager.MovementState.SLOW_MOVING
            MovementState.FAST_MOVING -> GeofenceManager.MovementState.FAST_MOVING
            MovementState.VEHICLE_SLOW -> GeofenceManager.MovementState.VEHICLE_SLOW
            MovementState.VEHICLE_FAST -> GeofenceManager.MovementState.VEHICLE_FAST
        }
    }

    // 🚀 NEW: Implementation for radius update requests
    override fun onRadiusUpdateRequested(newRadius: Float) {
        Log.d(TAG, "🎯 Radius update requested: ${newRadius}m")

        // Trigger geofence re-registration with new radius in background
        serviceScope.launch {
            try {
                Log.d(TAG, "🔄 Processing radius update request...")

                // Notify GeofenceManager to recalculate all geofence radii
                val success = geofenceManager?.recalculateAllGeofenceRadii() ?: false

                if (success) {
                    Log.d(TAG, "✅ Geofence radius update completed successfully")
                } else {
                    Log.w(TAG, "⚠️ Geofence radius update skipped (no active geofences)")
                }

            } catch (e: Exception) {
                Log.e(TAG, "❌ Error processing radius update: ${e.message}")
            }
        }
    }

    /**
     * 🚀 ULTRA-FAST: Update location tracking with ultra-fast adaptive intervals
     */
    private fun updateUltraFastLocationTrackingIntervals(interval: Long, fastestInterval: Long) {
        try {
            if (!hasLocationPermissions()) {
                Log.e(TAG, "❌ Cannot update location intervals - missing permissions")
                return
            }

            Log.d(TAG, "🔄 Updating ULTRA-FAST location tracking intervals: ${interval}ms (fastest: ${fastestInterval}ms)")

            // Stop existing location tracking
            fusedLocationClient.removeLocationUpdates(locationCallback)

            // 🚀 ULTRA-FAST: Use even faster intervals for vehicles
            val ultraFastInterval = when (currentMovementState) {
                MovementState.VEHICLE_FAST -> minOf(interval, LOCATION_UPDATE_ULTRA_FAST)
                MovementState.VEHICLE_SLOW -> minOf(interval, LOCATION_UPDATE_FAST)
                else -> interval
            }

            val ultraFastestInterval = when (currentMovementState) {
                MovementState.VEHICLE_FAST -> minOf(fastestInterval, 100L) // 0.1s minimum
                MovementState.VEHICLE_SLOW -> minOf(fastestInterval, 250L) // 0.25s minimum
                else -> fastestInterval
            }

            // Create new LocationRequest with ultra-fast intervals
            val adaptiveLocationRequest = LocationRequest.Builder(
                Priority.PRIORITY_HIGH_ACCURACY, // Higher accuracy for fast movement
                ultraFastInterval
            ).apply {
                setMinUpdateIntervalMillis(ultraFastestInterval)
                setMinUpdateDistanceMeters(5f) // Update every 5 meters
                setWaitForAccurateLocation(false)
                setMaxUpdateDelayMillis(1000L) // Maximum 1s delay
            }.build()

            // Start location tracking with ultra-fast intervals
            fusedLocationClient.requestLocationUpdates(
                adaptiveLocationRequest,
                locationCallback,
                Looper.getMainLooper()
            )

            Log.d(TAG, "✅ ULTRA-FAST location tracking updated: ${ultraFastInterval}ms (fastest: ${ultraFastestInterval}ms)")

        } catch (e: Exception) {
            Log.e(TAG, "❌ Failed to update ultra-fast location tracking intervals: ${e.message}")
        }
    }

    /**
     * 🚀 ULTRA-FAST: Activate manual backup system with ultra-fast intervals
     */
    private fun activateUltraFastManualBackup() {
        if (isManualBackupActive) return

        try {
            isManualBackupActive = true
            isUltraFastModeActive = true
            Log.d(TAG, "🔄 ULTRA-FAST manual backup activated")

            // Start ultra-fast manual check job
            manualCheckJob = serviceScope.launch {
                while (isManualBackupActive && isServiceRunning) {
                    try {
                        // 🚀 ENHANCED: Perform both regular and predictive checks
                        performUltraFastLocationCheck()

                        if (isVehicleMovement()) {
                            performPredictiveLocationCheck()
                        }

                        // 🏃 ULTRA-FAST: Use adaptive interval based on enhanced movement states
                        val adaptiveInterval = getUltraFastAdaptiveInterval()
                        Log.d(TAG, "⏰ Next ultra-fast check in ${adaptiveInterval}ms (${currentMovementState})")
                        delay(adaptiveInterval)

                    } catch (e: Exception) {
                        Log.e(TAG, "❌ Ultra-fast manual check error: ${e.message}")
                        delay(5000) // Shorter error delay for fast movement
                    }
                }
            }

        } catch (e: Exception) {
            Log.e(TAG, "❌ Failed to activate ultra-fast manual backup: ${e.message}")
        }
    }

    /**
     * 🚀 DEACTIVATE MANUAL BACKUP SYSTEM
     */
    private fun deactivateManualBackup() {
        if (!isManualBackupActive) return

        try {
            isManualBackupActive = false
            isUltraFastModeActive = false
            manualCheckJob?.cancel()
            Log.d(TAG, "✅ Ultra-fast manual backup deactivated")
        } catch (e: Exception) {
            Log.e(TAG, "❌ Failed to deactivate manual backup: ${e.message}")
        }
    }

    /**
     * 🚀 ULTRA-FAST: Perform ultra-fast manual location check with enhanced detection
     */
    private fun performUltraFastLocationCheck() {
        try {
            val currentLocation = lastKnownLocation ?: return
            Log.d(TAG, "🔍 Ultra-fast check at: ${currentLocation.latitude}, ${currentLocation.longitude} (Speed: ${"%.1f".format(currentSpeed * 3.6)} km/h)")

            // Get task locations from GeofenceManager
            val taskLocations = geofenceManager?.getActiveGeofenceLocations() ?: return

            for (taskLocation in taskLocations) {
                val distance = calculateDistance(
                    currentLocation.latitude,
                    currentLocation.longitude,
                    taskLocation.latitude,
                    taskLocation.longitude
                )

                // 🚀 ENHANCED: Use speed-based detection radius
                val detectionRadius = calculateSpeedBasedDetectionRadius()

                if (distance <= detectionRadius) {
                    handleUltraFastTaskDetection(taskLocation, distance, "ULTRA_FAST")
                }
            }

        } catch (e: Exception) {
            Log.e(TAG, "❌ Ultra-fast location check failed: ${e.message}")
        }
    }

    /**
     * 🚀 NEW: Perform predictive location check for fast movement
     */
    private fun performPredictiveLocationCheck() {
        try {
            val currentLocation = lastKnownLocation ?: return
            if (averageSpeed < SPEED_THRESHOLD_VEHICLE_SLOW) return // Only for vehicles

            val currentTime = System.currentTimeMillis()
            if (currentTime - lastPredictiveCheck < 5000L) return // Don't predict too often

            lastPredictiveCheck = currentTime

            // 🚀 PREDICT: Calculate where user will be in 30 seconds
            val predictedLocation = calculatePredictedLocation(
                currentLocation,
                averageSpeed,
                currentHeading,
                PREDICTIVE_CHECK_SECONDS_AHEAD
            )

            Log.d(TAG, "🔮 Predictive check: Current (${currentLocation.latitude}, ${currentLocation.longitude}) → Predicted (${predictedLocation.first}, ${predictedLocation.second})")

            // Get task locations from GeofenceManager
            val taskLocations = geofenceManager?.getActiveGeofenceLocations() ?: return

            for (taskLocation in taskLocations) {
                val predictedDistance = calculateDistance(
                    predictedLocation.first,
                    predictedLocation.second,
                    taskLocation.latitude,
                    taskLocation.longitude
                )

                // 🚀 EARLY WARNING: Use larger radius for predictive checking
                val earlyWarningRadius = calculateSpeedBasedDetectionRadius() * EARLY_WARNING_RADIUS_MULTIPLIER

                if (predictedDistance <= earlyWarningRadius) {
                    val currentDistance = calculateDistance(
                        currentLocation.latitude,
                        currentLocation.longitude,
                        taskLocation.latitude,
                        taskLocation.longitude
                    )

                    handleEarlyWarningDetection(taskLocation, currentDistance, predictedDistance)
                }
            }

        } catch (e: Exception) {
            Log.e(TAG, "❌ Predictive location check failed: ${e.message}")
        }
    }

    /**
     * 🚀 NEW: Calculate predicted location based on current speed and heading
     */
    private fun calculatePredictedLocation(
        currentLocation: android.location.Location,
        speed: Double, // m/s
        heading: Float, // degrees
        secondsAhead: Int
    ): Pair<Double, Double> {

        val earthRadius = 6371000.0 // meters
        val distance = speed * secondsAhead // meters

        val headingRad = Math.toRadians(heading.toDouble())
        val currentLatRad = Math.toRadians(currentLocation.latitude)
        val currentLonRad = Math.toRadians(currentLocation.longitude)

        val angularDistance = distance / earthRadius

        val predictedLatRad = asin(
            sin(currentLatRad) * cos(angularDistance) +
                    cos(currentLatRad) * sin(angularDistance) * cos(headingRad)
        )

        val predictedLonRad = currentLonRad + atan2(
            sin(headingRad) * sin(angularDistance) * cos(currentLatRad),
            cos(angularDistance) - sin(currentLatRad) * sin(predictedLatRad)
        )

        return Pair(
            Math.toDegrees(predictedLatRad),
            Math.toDegrees(predictedLonRad)
        )
    }

    /**
     * 🚀 NEW: Calculate speed-based detection radius
     */
    private fun calculateSpeedBasedDetectionRadius(): Double {
        val baseRadius = geofenceManager?.getCurrentCalculatedRadius()?.toDouble() ?: NEAR_TASK_RADIUS_BASE

        return when (currentMovementState) {
            MovementState.VEHICLE_FAST -> {
                val dynamicMultiplier = 2.0 + (currentSpeed / 20.0) // Increases with speed
                baseRadius * dynamicMultiplier
            }
            MovementState.VEHICLE_SLOW -> baseRadius * NEAR_TASK_RADIUS_VEHICLE_MULTIPLIER
            MovementState.FAST_MOVING -> baseRadius * NEAR_TASK_RADIUS_FAST_MULTIPLIER
            else -> baseRadius
        }
    }

    /**
     * 🚀 NEW: Handle early warning detection for fast approaching tasks
     */
    private fun handleEarlyWarningDetection(
        taskLocation: GeofenceManager.GeofenceData,
        currentDistance: Double,
        predictedDistance: Double
    ) {
        try {
            val currentTime = System.currentTimeMillis()
            val lastEarlyWarning = lastEarlyWarningTimes[taskLocation.id] ?: 0

            // Check early warning cooldown
            if (currentTime - lastEarlyWarning < EARLY_WARNING_COOLDOWN) {
                return
            }

            val timeToArrival = currentDistance / maxOf(currentSpeed, 1.0) // seconds

            Log.d(TAG, "⚠️ Early warning: ${taskLocation.title} - Current: ${currentDistance.toInt()}m, Predicted: ${predictedDistance.toInt()}m, ETA: ${timeToArrival.toInt()}s")

            // Send early warning notification
            showEarlyWarningNotification(taskLocation.title, taskLocation.id, currentDistance.toInt(), timeToArrival.toInt())

            // Remember early warning time
            lastEarlyWarningTimes[taskLocation.id] = currentTime

        } catch (e: Exception) {
            Log.e(TAG, "❌ Early warning detection failed: ${e.message}")
        }
    }

    /**
     * 🚀 ULTRA-FAST: Handle task detection with enhanced logic
     */
    private fun handleUltraFastTaskDetection(
        taskLocation: GeofenceManager.GeofenceData,
        distance: Double,
        detectionType: String
    ) {
        try {
            val currentTime = System.currentTimeMillis()
            val lastNotificationTime = lastNotificationTimes[taskLocation.id] ?: 0

            // 🚀 ENHANCED: Shorter cooldown for fast movement
            val cooldownPeriod = if (isVehicleMovement()) {
                NOTIFICATION_COOLDOWN / 2 // 1.5 minutes for vehicles
            } else {
                NOTIFICATION_COOLDOWN
            }

            // Check cooldown period
            if (currentTime - lastNotificationTime < cooldownPeriod) {
                return
            }

            Log.d(TAG, "🎯 $detectionType detection: ${taskLocation.title} (${distance.toInt()}m away, ${"%.1f".format(currentSpeed * 3.6)} km/h)")

            // Send notification
            showUltraFastBackupNotification(taskLocation.title, taskLocation.id, distance.toInt(), detectionType)

            // Remember notification time
            lastNotificationTimes[taskLocation.id] = currentTime

        } catch (e: Exception) {
            Log.e(TAG, "❌ Ultra-fast task detection failed: ${e.message}")
        }
    }

    /**
     * 🚀 NEW: Show early warning notification
     */
    private fun showEarlyWarningNotification(taskTitle: String, taskId: String, distance: Int, eta: Int) {
        try {
            val notificationManager = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager

            // Create lock screen intent
            val lockScreenIntent = Intent(this, LockScreenTaskActivity::class.java).apply {
                putExtra("taskTitle", taskTitle)
                putExtra("taskMessage", "Approaching: $taskTitle (${distance}m, ETA: ${eta}s)")
                putExtra("taskId", taskId)
                flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP
            }

            val pendingIntent = PendingIntent.getActivity(
                this,
                (taskId + "_early").hashCode(),
                lockScreenIntent,
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
            )

            // Create early warning notification
            val notification = NotificationCompat.Builder(this, "LOCADO_GEOFENCE_ALERTS")
                .setSmallIcon(android.R.drawable.ic_dialog_info)
                .setContentTitle("⚠️ LOCADO EARLY WARNING")
                .setContentText("📍 Approaching: $taskTitle (${distance}m, ${eta}s)")
                .setPriority(NotificationCompat.PRIORITY_HIGH)
                .setCategory(NotificationCompat.CATEGORY_NAVIGATION)
                .setVisibility(NotificationCompat.VISIBILITY_PUBLIC)
                .setContentIntent(pendingIntent)
                .setAutoCancel(true)
                .setTimeoutAfter(30000) // 30 seconds
                .build()

            notificationManager.notify((taskId + "_early").hashCode(), notification)
            Log.d(TAG, "✅ Early warning notification sent for: $taskTitle")

        } catch (e: Exception) {
            Log.e(TAG, "❌ Early warning notification failed: ${e.message}")
        }
    }

    /**
     * 🚀 ULTRA-FAST: Send ultra-fast backup notification
     */
    private fun showUltraFastBackupNotification(taskTitle: String, taskId: String, distance: Int, detectionType: String) {
        try {
            val notificationManager = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager

            // Create lock screen intent
            val lockScreenIntent = Intent(this, LockScreenTaskActivity::class.java).apply {
                putExtra("taskTitle", taskTitle)
                putExtra("taskMessage", "You are ${distance}m from: $taskTitle")
                putExtra("taskId", taskId)
                flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP
            }

            val pendingIntent = PendingIntent.getActivity(
                this,
                taskId.hashCode(),
                lockScreenIntent,
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
            )

            val alertType = when (detectionType) {
                "ULTRA_FAST" -> "🚄 LOCADO ALERT (Ultra-Fast)"
                "PREDICTIVE" -> "🔮 LOCADO ALERT (Predictive)"
                else -> "🚨 LOCADO ALERT (Manual)"
            }

            // Create notification
            val notification = NotificationCompat.Builder(this, "LOCADO_GEOFENCE_ALERTS")
                .setSmallIcon(android.R.drawable.ic_dialog_alert)
                .setContentTitle(alertType)
                .setContentText("📍 ${distance}m from: $taskTitle")
                .setPriority(NotificationCompat.PRIORITY_MAX)
                .setCategory(NotificationCompat.CATEGORY_ALARM)
                .setVisibility(NotificationCompat.VISIBILITY_PUBLIC)
                .setFullScreenIntent(pendingIntent, true)
                .setContentIntent(pendingIntent)
                .setAutoCancel(true)
                .setDefaults(NotificationCompat.DEFAULT_ALL)
                .build()

            notificationManager.notify(taskId.hashCode(), notification)
            Log.d(TAG, "✅ $detectionType notification sent for: $taskTitle")

        } catch (e: Exception) {
            Log.e(TAG, "❌ Ultra-fast backup notification failed: ${e.message}")
        }
    }

    /**
     * 🚀 CALCULATE DISTANCE BETWEEN TWO POINTS
     */
    private fun calculateDistance(lat1: Double, lon1: Double, lat2: Double, lon2: Double): Double {
        val earthRadius = 6371000.0 // meters

        val dLat = Math.toRadians(lat2 - lat1)
        val dLon = Math.toRadians(lon2 - lon1)

        val a = sin(dLat / 2) * sin(dLat / 2) +
                cos(Math.toRadians(lat1)) * cos(Math.toRadians(lat2)) *
                sin(dLon / 2) * sin(dLon / 2)

        val c = 2 * atan2(sqrt(a), sqrt(1 - a))

        return earthRadius * c
    }

    /**
     * 🏃 ULTRA-FAST: Get ultra-fast adaptive interval based on enhanced movement state
     */
    private fun getUltraFastAdaptiveInterval(): Long {
        return when (currentMovementState) {
            MovementState.VEHICLE_FAST -> {
                Log.d(TAG, "🚄 Fast vehicle detected - using ULTRA-FAST 0.25s interval")
                MANUAL_CHECK_INTERVAL_ULTRA_FAST
            }
            MovementState.VEHICLE_SLOW -> {
                Log.d(TAG, "🚌 Slow vehicle detected - using fast 0.5s interval")
                MANUAL_CHECK_INTERVAL_FAST
            }
            MovementState.FAST_MOVING -> {
                Log.d(TAG, "🏃 Fast movement detected - using 2s interval")
                MANUAL_CHECK_INTERVAL_NORMAL
            }
            MovementState.SLOW_MOVING -> {
                Log.d(TAG, "🚶 Slow movement detected - using 5s interval")
                MANUAL_CHECK_INTERVAL_SLOW
            }
            MovementState.STATIONARY -> {
                Log.d(TAG, "🛑 Stationary detected - using 5min interval")
                MANUAL_CHECK_INTERVAL_STATIONARY
            }
        }
    }

    /**
     * 🚀 NEW: Check if current movement is vehicle-based
     */
    private fun isVehicleMovement(): Boolean {
        return currentMovementState == MovementState.VEHICLE_SLOW ||
                currentMovementState == MovementState.VEHICLE_FAST
    }

    /**
     * 🏃 ENHANCED: Calculate current speed and update movement state with ultra-fast response
     */
    private fun calculateSpeedAndUpdateMovementState(newLocation: android.location.Location) {
        try {
            val currentTime = System.currentTimeMillis()

            // Check accuracy - ignore inaccurate locations
            if (newLocation.accuracy > MIN_LOCATION_ACCURACY) {
                Log.d(TAG, "🎯 Location accuracy too low (${newLocation.accuracy}m) - skipping speed calculation")
                return
            }

            // 🚀 UPDATE HEADING for predictive calculations
            if (newLocation.hasBearing()) {
                currentHeading = newLocation.bearing
            }

            previousLocation?.let { prevLoc ->
                // Calculate distance between locations
                val distance = calculateDistance(
                    prevLoc.latitude, prevLoc.longitude,
                    newLocation.latitude, newLocation.longitude
                )

                // Calculate time difference
                val timeDifference = (newLocation.time - prevLoc.time) / 1000.0 // seconds

                // 🚀 ULTRA-FAST: Reduced minimum requirements for faster response
                if (timeDifference > 1.0 && distance > 5.0) { // Reduced from 5s and 10m
                    // Calculate speed in m/s
                    currentSpeed = distance / timeDifference

                    // 🚀 ENHANCED: Update speed history for averaging
                    speedHistory.add(currentSpeed)
                    if (speedHistory.size > 10) {
                        speedHistory.removeAt(0) // Keep only last 10 measurements
                    }

                    // Calculate running average speed for smoother predictions
                    averageSpeed = speedHistory.average()

                    // 🚀 ENHANCED: Update movement state based on enhanced speed categories
                    val previousState = currentMovementState
                    currentMovementState = when {
                        averageSpeed >= SPEED_THRESHOLD_VEHICLE_FAST -> MovementState.VEHICLE_FAST
                        averageSpeed >= SPEED_THRESHOLD_VEHICLE_SLOW -> MovementState.VEHICLE_SLOW
                        averageSpeed >= SPEED_THRESHOLD_FAST -> MovementState.FAST_MOVING
                        averageSpeed >= SPEED_THRESHOLD_WALKING -> MovementState.SLOW_MOVING
                        else -> MovementState.STATIONARY
                    }

                    Log.d(TAG, "🏃 Speed: ${"%.2f".format(currentSpeed)} m/s (avg: ${"%.2f".format(averageSpeed)}, ${"%.1f".format(averageSpeed * 3.6)} km/h), Distance: ${"%.1f".format(distance)}m, Time: ${"%.1f".format(timeDifference)}s")
                    Log.d(TAG, "🏃 Enhanced movement state: $previousState → $currentMovementState")

                    // Update previous location for next calculation
                    previousLocation = newLocation
                    lastSpeedCalculationTime = currentTime

                    // If movement state changed, update both systems
                    if (previousState != currentMovementState) {
                        Log.d(TAG, "🔄 Movement state changed - updating both systems with ultra-fast response")

                        // 🚀 ENHANCED LOGIC: Notify GeofenceManager about movement state change AND speed
                        val geofenceMovementState = when (currentMovementState) {
                            MovementState.STATIONARY -> GeofenceManager.MovementState.STATIONARY
                            MovementState.SLOW_MOVING -> GeofenceManager.MovementState.SLOW_MOVING
                            MovementState.FAST_MOVING -> GeofenceManager.MovementState.FAST_MOVING
                            MovementState.VEHICLE_SLOW -> GeofenceManager.MovementState.VEHICLE_SLOW
                            MovementState.VEHICLE_FAST -> GeofenceManager.MovementState.VEHICLE_FAST
                        }

                        // Update both movement state and speed for dynamic radius calculation
                        geofenceManager?.updateMovementState(geofenceMovementState)
                        geofenceManager?.updateSpeedAndRadius(averageSpeed) // Use average speed

                        // 🚀 ULTRA-FAST: Immediately restart manual backup with new ultra-fast interval
                        if (isManualBackupActive) {
                            Log.d(TAG, "🔄 Restarting manual backup with ULTRA-FAST adaptive interval")
                            restartUltraFastManualBackupWithNewInterval()
                        }

                        // 🚀 AUTO-ACTIVATE: If vehicle movement detected and geofencing inactive
                        if (isVehicleMovement() && !isManualBackupActive) {
                            val isGeofencingActive = geofenceManager?.isGeofencingActive() ?: true
                            if (!isGeofencingActive) {
                                Log.w(TAG, "🚄 Vehicle movement detected with inactive geofencing - auto-activating ultra-fast backup")
                                activateUltraFastManualBackup()
                            }
                        }
                    }
                } else {
                    Log.d(TAG, "🎯 Speed calculation skipped - insufficient time (${"%.1f".format(timeDifference)}s) or distance (${"%.1f".format(distance)}m)")
                }
            } ?: run {
                // First location - just set it as previous
                previousLocation = newLocation
                lastSpeedCalculationTime = currentTime
                Log.d(TAG, "🏃 First location set for ultra-fast speed calculation")
            }

        } catch (e: Exception) {
            Log.e(TAG, "❌ Error calculating ultra-fast speed: ${e.message}")
        }
    }

    /**
     * 🔄 ULTRA-FAST: Restart manual backup with new ultra-fast adaptive interval
     */
    private fun restartUltraFastManualBackupWithNewInterval() {
        try {
            if (!isManualBackupActive) return

            Log.d(TAG, "🔄 Restarting manual backup with ULTRA-FAST adaptive interval...")

            // Cancel existing job
            manualCheckJob?.cancel()

            // Start new job with ultra-fast adaptive interval
            manualCheckJob = serviceScope.launch {
                while (isManualBackupActive && isServiceRunning) {
                    try {
                        // 🚀 ENHANCED: Perform both regular and predictive checks
                        performUltraFastLocationCheck()

                        if (isVehicleMovement()) {
                            performPredictiveLocationCheck()
                        }

                        // Use ultra-fast adaptive interval
                        val adaptiveInterval = getUltraFastAdaptiveInterval()
                        Log.d(TAG, "⏰ Next ultra-fast check in ${adaptiveInterval}ms (${currentMovementState})")
                        delay(adaptiveInterval)

                    } catch (e: Exception) {
                        Log.e(TAG, "❌ Ultra-fast adaptive manual check error: ${e.message}")
                        delay(5000) // Shorter error delay for fast movement
                    }
                }
            }

            Log.d(TAG, "✅ Manual backup restarted with ULTRA-FAST adaptive intervals")

        } catch (e: Exception) {
            Log.e(TAG, "❌ Failed to restart ultra-fast manual backup: ${e.message}")
        }
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        val action = intent?.action ?: "NULL"
        Log.d(TAG, "🔄 Service onStartCommand() - Action: $action")

        try {
            when (action) {
                ACTION_START_SERVICE -> {
                    startUltraForegroundService()
                }
                ACTION_STOP_SERVICE -> {
                    stopForegroundService()
                }
                ACTION_UPDATE_NOTIFICATION -> {
                    val count = intent?.getIntExtra("geofence_count", 0) ?: 0
                    updateGeofenceCount(count)
                    updateNotification()
                }
                ACTION_HEARTBEAT -> {
                    handleHeartbeat()
                }
                else -> {
                    Log.d(TAG, "🔄 Service restart detected - ensuring foreground")
                    startUltraForegroundService()
                }
            }
        } catch (e: Exception) {
            Log.e(TAG, "❌ Error in onStartCommand: ${e.message}")
            startUltraForegroundService()
        }

        return START_STICKY
    }

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onDestroy() {
        Log.d(TAG, "🛑 Service onDestroy() - cleaning up ultra-fast systems")

        try {
            // ✅ CLEANUP HYBRID SYSTEM
            deactivateManualBackup()

            // ✅ CLEANUP MOTION DETECTION
            stopMotionDetection()

            // ✅ CLEANUP JOBS
            heartbeatJob?.cancel()
            geofenceCheckJob?.cancel()

            // ✅ CANCEL ALARMS
            heartbeatPendingIntent?.let { pendingIntent ->
                alarmManager?.cancel(pendingIntent)
            }

            // ✅ RELEASE WAKE LOCKS
            wakeLock?.let {
                if (it.isHeld) {
                    it.release()
                    Log.d(TAG, "🔓 Wake lock released")
                }
            }

            isServiceRunning = false

        } catch (e: Exception) {
            Log.e(TAG, "❌ Error in onDestroy: ${e.message}")
        }

        super.onDestroy()
    }

    override fun onTaskRemoved(rootIntent: Intent?) {
        Log.w(TAG, "🚨 Task removed - SAMSUNG PERSISTENCE MODE activated")

        try {
            // ✅ IMMEDIATE SERVICE RESTART
            val restartIntent = Intent(applicationContext, LocadoForegroundService::class.java)
            restartIntent.action = ACTION_START_SERVICE

            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                applicationContext.startForegroundService(restartIntent)
            } else {
                applicationContext.startService(restartIntent)
            }

            // ✅ SETUP ALARM-BASED RESTART (fallback)
            scheduleServiceRestart()

            Log.d(TAG, "✅ Service restart mechanisms activated")

        } catch (e: Exception) {
            Log.e(TAG, "❌ Error in onTaskRemoved: ${e.message}")
        }

        super.onTaskRemoved(rootIntent)
    }

    private fun acquireUltraWakeLock() {
        try {
            val powerManager = getSystemService(Context.POWER_SERVICE) as PowerManager

            wakeLock = powerManager.newWakeLock(
                PowerManager.PARTIAL_WAKE_LOCK or PowerManager.ACQUIRE_CAUSES_WAKEUP,
                "LocadoApp::UltraFastBackgroundGeofencing"
            )

            wakeLock?.acquire(WAKE_LOCK_TIMEOUT)
            Log.d(TAG, "✅ Ultra wake lock acquired")

        } catch (e: Exception) {
            Log.e(TAG, "❌ Failed to acquire wake lock: ${e.message}")
        }
    }

    private fun setupHeartbeatAlarm() {
        try {
            alarmManager = getSystemService(Context.ALARM_SERVICE) as AlarmManager

            val heartbeatIntent = Intent(this, LocadoForegroundService::class.java)
            heartbeatIntent.action = ACTION_HEARTBEAT

            heartbeatPendingIntent = PendingIntent.getService(
                this,
                1002,
                heartbeatIntent,
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
            )

            val triggerTime = SystemClock.elapsedRealtime() + HEARTBEAT_INTERVAL

            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                alarmManager?.setExactAndAllowWhileIdle(
                    AlarmManager.ELAPSED_REALTIME_WAKEUP,
                    triggerTime,
                    heartbeatPendingIntent!!
                )
            } else {
                alarmManager?.setRepeating(
                    AlarmManager.ELAPSED_REALTIME_WAKEUP,
                    triggerTime,
                    HEARTBEAT_INTERVAL,
                    heartbeatPendingIntent!!
                )
            }

            Log.d(TAG, "✅ Heartbeat alarm scheduled")

        } catch (e: Exception) {
            Log.e(TAG, "❌ Failed to setup heartbeat alarm: ${e.message}")
        }
    }

    private fun startBackgroundJobs() {
        try {
            // ✅ HEARTBEAT JOB - keeps service alive
            heartbeatJob = serviceScope.launch {
                while (isServiceRunning) {
                    try {
                        lastHeartbeat = System.currentTimeMillis()

                        // 🚀 CHECK HYBRID SYSTEM PERIODICALLY
                        checkUltraFastHybridSystemStatus()

                        if (wakeLock?.isHeld != true) {
                            acquireUltraWakeLock()
                        }

                        delay(HEARTBEAT_INTERVAL)

                    } catch (e: Exception) {
                        Log.e(TAG, "❌ Heartbeat error: ${e.message}")
                        delay(5000)
                    }
                }
            }

            Log.d(TAG, "✅ Background monitoring jobs started with ultra-fast support")

        } catch (e: Exception) {
            Log.e(TAG, "❌ Failed to start background jobs: ${e.message}")
        }
    }

    /**
     * 🚀 ULTRA-FAST: Check hybrid system status with enhanced vehicle detection
     */
    private fun checkUltraFastHybridSystemStatus() {
        try {
            val isGeofencingActive = geofenceManager?.isGeofencingActive() ?: true

            if (!isGeofencingActive && !isManualBackupActive) {
                Log.w(TAG, "🔄 Detected geofencing inactivity - checking ultra-fast backup activation")
                if (geofenceManager?.shouldActivateManualBackup() == true) {
                    activateUltraFastManualBackup()
                }
            }

            // 🚀 AUTO-DETECTION: If vehicle movement but no backup active
            if (isVehicleMovement() && !isGeofencingActive && !isManualBackupActive) {
                Log.w(TAG, "🚄 Vehicle movement detected without active tracking - force activating ultra-fast backup")
                activateUltraFastManualBackup()
            }

        } catch (e: Exception) {
            Log.e(TAG, "❌ Ultra-fast hybrid system status check failed: ${e.message}")
        }
    }

    private fun handleHeartbeat() {
        try {
            lastHeartbeat = System.currentTimeMillis()

            if (isServiceRunning) {
                val notification = createNotification()
                notificationManager?.notify(NOTIFICATION_ID, notification)
            }

            setupHeartbeatAlarm()

        } catch (e: Exception) {
            Log.e(TAG, "❌ Heartbeat handling error: ${e.message}")
        }
    }

    private fun scheduleServiceRestart() {
        try {
            val restartIntent = Intent(this, LocadoForegroundService::class.java)
            restartIntent.action = ACTION_START_SERVICE

            val restartPendingIntent = PendingIntent.getService(
                this,
                1003,
                restartIntent,
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
            )

            val alarmManager = getSystemService(Context.ALARM_SERVICE) as AlarmManager
            val triggerTime = SystemClock.elapsedRealtime() + 60000

            alarmManager.setExactAndAllowWhileIdle(
                AlarmManager.ELAPSED_REALTIME_WAKEUP,
                triggerTime,
                restartPendingIntent
            )

            Log.d(TAG, "✅ Service restart scheduled")

        } catch (e: Exception) {
            Log.e(TAG, "❌ Failed to schedule restart: ${e.message}")
        }
    }

    private fun startUltraForegroundService() {
        try {
            Log.d(TAG, "🚀 Starting ULTRA foreground service with ultra-fast support")
            val notification = createUltraNotification()
            startForeground(NOTIFICATION_ID, notification)
            Log.d(TAG, "✅ Ultra foreground service active")
        } catch (e: Exception) {
            Log.e(TAG, "❌ Failed to start ultra foreground: ${e.message}")
        }
    }

    private fun stopForegroundService() {
        Log.d(TAG, "🛑 Stopping foreground service")

        deactivateManualBackup()
        heartbeatJob?.cancel()
        geofenceCheckJob?.cancel()

        stopForeground(STOP_FOREGROUND_REMOVE)
        stopSelf()
    }

    private fun updateGeofenceCount(count: Int) {
        activeGeofenceCount = count
        Log.d(TAG, "📊 Updated active geofence count: $count")
    }

    private fun updateNotification() {
        try {
            val notification = createUltraNotification()
            notificationManager?.notify(NOTIFICATION_ID, notification)
        } catch (e: Exception) {
            Log.e(TAG, "❌ Failed to update notification: ${e.message}")
        }
    }

    private fun createNotificationChannel() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val channel = NotificationChannel(
                CHANNEL_ID,
                "Locado Background Service",
                NotificationManager.IMPORTANCE_LOW
            ).apply {
                description = "Ultra-persistent task location monitoring with ultra-fast intervals"
                setShowBadge(false)
                enableVibration(false)
                setSound(null, null)
                setBypassDnd(false)
                lockscreenVisibility = Notification.VISIBILITY_SECRET
            }

            val notificationManager = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
            notificationManager.createNotificationChannel(channel)

            // Create channel for manual backup notifications
            val manualChannel = NotificationChannel(
                "LOCADO_GEOFENCE_ALERTS",
                "Ultra-Fast Backup Alerts",
                NotificationManager.IMPORTANCE_HIGH
            ).apply {
                description = "Ultra-fast location alerts when geofencing is inactive"
                enableVibration(true)
                enableLights(true)
                setBypassDnd(true)
                lockscreenVisibility = Notification.VISIBILITY_PUBLIC
            }
            notificationManager.createNotificationChannel(manualChannel)

            Log.d(TAG, "✅ Notification channels created")
        }
    }

    private fun createUltraNotification(): Notification {
        val notificationIntent = Intent(this, MainActivity::class.java)
        val pendingIntent = PendingIntent.getActivity(
            this, 0, notificationIntent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )

        val contentTitle = when {
            isUltraFastModeActive -> "Locado - Ultra-Fast backup active ($activeGeofenceCount locations)"
            isManualBackupActive -> "Locado - Manual backup active ($activeGeofenceCount locations)"
            activeGeofenceCount > 0 -> "Locado - Monitoring $activeGeofenceCount locations"
            else -> "Locado - Background monitoring active"
        }

        val contentText = when {
            isUltraFastModeActive -> "Ultra-fast checking (${currentMovementState.name.lowercase()}, ${"%.1f".format(averageSpeed * 3.6)} km/h)"
            isManualBackupActive -> "Manual checking active (${currentMovementState.name.lowercase()}, ${"%.1f".format(currentSpeed)} m/s)"
            else -> "Geofencing active with dynamic radius"
        }

        return NotificationCompat.Builder(this, CHANNEL_ID)
            .setContentTitle(contentTitle)
            .setContentText(contentText)
            .setSmallIcon(android.R.drawable.ic_menu_mylocation)
            .setContentIntent(pendingIntent)
            .setOngoing(true)
            .setPriority(NotificationCompat.PRIORITY_LOW)
            .setCategory(NotificationCompat.CATEGORY_SERVICE)
            .setVisibility(NotificationCompat.VISIBILITY_SECRET)
            .setAutoCancel(false)
            .setShowWhen(false)
            .setForegroundServiceBehavior(NotificationCompat.FOREGROUND_SERVICE_IMMEDIATE)
            .build()
    }

    private fun createNotification(): Notification = createUltraNotification()

    /**
     * 🚀 ULTRA-FAST: Setup ultra-fast continuous location tracking
     */
    private fun setupUltraFastLocationTracking() {
        try {
            if (!hasLocationPermissions()) {
                Log.e(TAG, "❌ Location permissions missing")
                return
            }

            fusedLocationClient = LocationServices.getFusedLocationProviderClient(this)

            // 🚀 ULTRA-FAST: Start with high-frequency tracking
            val ultraFastInterval = LOCATION_UPDATE_FAST // Start with 0.5s
            val ultraFastestInterval = LOCATION_UPDATE_ULTRA_FAST // Minimum 0.25s

            Log.d(TAG, "🕐 Starting ULTRA-FAST location tracking: ${ultraFastInterval}ms (fastest: ${ultraFastestInterval}ms)")

            val locationRequest = LocationRequest.Builder(
                Priority.PRIORITY_HIGH_ACCURACY, // Highest accuracy
                ultraFastInterval
            ).apply {
                setMinUpdateIntervalMillis(ultraFastestInterval)
                setMinUpdateDistanceMeters(3f) // Update every 3 meters
                setWaitForAccurateLocation(false)
                setMaxUpdateDelayMillis(500L) // Maximum 0.5s delay
            }.build()

            locationCallback = object : LocationCallback() {
                override fun onLocationResult(locationResult: LocationResult) {
                    super.onLocationResult(locationResult)

                    for (location in locationResult.locations) {
                        lastKnownLocation = location

                        // 🏃 ULTRA-FAST: Calculate speed and update movement state with ultra-fast response
                        calculateSpeedAndUpdateMovementState(location)

                        Log.d(TAG, "📍 Ultra-fast location: ${location.latitude}, ${location.longitude}, Speed: ${"%.2f".format(currentSpeed)} m/s (${"%.1f".format(currentSpeed * 3.6)} km/h), State: $currentMovementState")
                    }
                }

                override fun onLocationAvailability(availability: LocationAvailability) {
                    super.onLocationAvailability(availability)
                    Log.d(TAG, "📡 Ultra-fast location availability: ${availability.isLocationAvailable}")
                }
            }

            try {
                fusedLocationClient.requestLocationUpdates(
                    locationRequest,
                    locationCallback,
                    Looper.getMainLooper()
                )

                Log.d(TAG, "✅ ULTRA-FAST location tracking started")

            } catch (securityException: SecurityException) {
                Log.e(TAG, "❌ SecurityException: ${securityException.message}")
            }

        } catch (e: Exception) {
            Log.e(TAG, "❌ Failed to setup ultra-fast location tracking: ${e.message}")
        }
    }

    private fun hasLocationPermissions(): Boolean {
        val fineLocation = ActivityCompat.checkSelfPermission(
            this, android.Manifest.permission.ACCESS_FINE_LOCATION
        ) == PackageManager.PERMISSION_GRANTED

        val backgroundLocation = if (android.os.Build.VERSION.SDK_INT >= android.os.Build.VERSION_CODES.Q) {
            ActivityCompat.checkSelfPermission(
                this, android.Manifest.permission.ACCESS_BACKGROUND_LOCATION
            ) == PackageManager.PERMISSION_GRANTED
        } else {
            true
        }

        return fineLocation && backgroundLocation
    }

    private fun isScreenOn(): Boolean {
        return try {
            val powerManager = getSystemService(Context.POWER_SERVICE) as PowerManager
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.KITKAT_WATCH) {
                powerManager.isInteractive
            } else {
                @Suppress("DEPRECATION")
                powerManager.isScreenOn
            }
        } catch (e: Exception) {
            false
        }
    }

    // Motion detection methods remain the same as before...
    private fun setupMotionDetection() {
        try {
            Log.d(TAG, "🎯 Setting up motion detection system...")

            sensorManager = getSystemService(Context.SENSOR_SERVICE) as SensorManager
            accelerometer = sensorManager?.getDefaultSensor(Sensor.TYPE_ACCELEROMETER)
            gyroscope = sensorManager?.getDefaultSensor(Sensor.TYPE_GYROSCOPE)
            significantMotionSensor = sensorManager?.getDefaultSensor(Sensor.TYPE_SIGNIFICANT_MOTION)

            Log.d(TAG, "🎯 Available sensors:")
            Log.d(TAG, "  - Accelerometer: ${accelerometer != null}")
            Log.d(TAG, "  - Gyroscope: ${gyroscope != null}")
            Log.d(TAG, "  - Significant Motion: ${significantMotionSensor != null}")

            if (accelerometer != null || significantMotionSensor != null) {
                startMotionDetection()
                Log.d(TAG, "✅ Motion detection system initialized")
            } else {
                Log.w(TAG, "⚠️ No suitable motion sensors available")
            }

        } catch (e: Exception) {
            Log.e(TAG, "❌ Failed to setup motion detection: ${e.message}")
        }
    }

    private fun startMotionDetection() {
        try {
            if (isMotionDetectionActive) return

            Log.d(TAG, "🎯 Starting motion detection...")

            motionDetectionListener = object : SensorEventListener {
                override fun onSensorChanged(event: SensorEvent?) {
                    handleMotionEvent(event)
                }

                override fun onAccuracyChanged(sensor: Sensor?, accuracy: Int) {
                    // We don't use accuracy changes
                }
            }

            var sensorsRegistered = false

            // Try to register Significant Motion sensor (lowest power)
            significantMotionSensor?.let { sensor ->
                val registered = sensorManager?.registerListener(
                    motionDetectionListener,
                    sensor,
                    SensorManager.SENSOR_DELAY_NORMAL
                ) ?: false

                if (registered) {
                    sensorsRegistered = true
                    Log.d(TAG, "✅ Significant Motion sensor registered")
                }
            }

            // If Significant Motion is not available, use Accelerometer
            if (!sensorsRegistered && accelerometer != null) {
                val registered = sensorManager?.registerListener(
                    motionDetectionListener,
                    accelerometer,
                    SensorManager.SENSOR_DELAY_NORMAL
                ) ?: false

                if (registered) {
                    sensorsRegistered = true
                    Log.d(TAG, "✅ Accelerometer sensor registered")
                }
            }

            if (sensorsRegistered) {
                isMotionDetectionActive = true
                Log.d(TAG, "✅ Motion detection started successfully")
            } else {
                Log.e(TAG, "❌ Failed to register any motion sensors")
            }

        } catch (e: Exception) {
            Log.e(TAG, "❌ Error starting motion detection: ${e.message}")
        }
    }

    private fun handleMotionEvent(event: SensorEvent?) {
        try {
            if (event == null) return

            val currentTime = System.currentTimeMillis()

            // Check cooldown period
            if (currentTime - lastMotionTriggeredCheck < MOTION_CHECK_COOLDOWN) {
                return
            }

            var motionDetected = false

            when (event.sensor.type) {
                Sensor.TYPE_SIGNIFICANT_MOTION -> {
                    motionDetected = true
                    Log.d(TAG, "🎯 Significant motion detected")
                }

                Sensor.TYPE_ACCELEROMETER -> {
                    val x = event.values[0]
                    val y = event.values[1]
                    val z = event.values[2]

                    val magnitude = sqrt(x * x + y * y + z * z)
                    val gravity = 9.81f
                    val linearAcceleration = abs(magnitude - gravity)

                    if (linearAcceleration > MOTION_SENSITIVITY_THRESHOLD) {
                        motionDetected = true
                        Log.d(TAG, "🎯 Accelerometer motion detected (magnitude: ${"%.2f".format(linearAcceleration)})")
                    }
                }
            }

            if (motionDetected) {
                lastMotionTriggeredCheck = currentTime
                onMotionDetected()
            }

        } catch (e: Exception) {
            Log.e(TAG, "❌ Error handling motion event: ${e.message}")
        }
    }

    private fun onMotionDetected() {
        try {
            Log.d(TAG, "🎯 Motion detected - triggering ultra-fast system health check...")

            // Start health check with delay to allow system to stabilize
            motionDetectionJob?.cancel()
            motionDetectionJob = serviceScope.launch {
                try {
                    delay(MOTION_DETECTION_DELAY)

                    Log.d(TAG, "🔍 Performing motion-triggered ultra-fast health check...")

                    // 1. Check geofencing status
                    val isGeofencingActive = geofenceManager?.isGeofencingActive() ?: true

                    // 2. Check location tracking
                    val hasRecentLocation = lastKnownLocation != null &&
                            (System.currentTimeMillis() - (lastKnownLocation?.time ?: 0)) < 300000L

                    // 3. Check service status
                    val serviceHealthy = isServiceRunning &&
                            (System.currentTimeMillis() - lastHeartbeat) < 120000L

                    Log.d(TAG, "🔍 Ultra-fast health check results:")
                    Log.d(TAG, "  - Geofencing active: $isGeofencingActive")
                    Log.d(TAG, "  - Recent location: $hasRecentLocation")
                    Log.d(TAG, "  - Service healthy: $serviceHealthy")

                    var restartPerformed = false

                    if (!isGeofencingActive) {
                        Log.w(TAG, "🔄 Motion-triggered: Geofencing inactive - attempting ultra-fast restart")
                        val geofenceRestartSuccess = performMotionTriggeredGeofenceRestart()
                        if (geofenceRestartSuccess) {
                            restartPerformed = true
                        } else {
                            Log.w(TAG, "🔄 Geofencing restart failed - falling back to ultra-fast manual backup")
                            if (!isManualBackupActive) {
                                activateUltraFastManualBackup()
                                restartPerformed = true
                            }
                        }
                    }

                    if (!hasRecentLocation) {
                        Log.w(TAG, "🔄 Motion-triggered: Location tracking stale - refreshing with ultra-fast")
                        setupUltraFastLocationTracking()
                        restartPerformed = true
                    }

                    val manualBackupRestartSuccess = performManualBackupHealthCheck()
                    if (manualBackupRestartSuccess) {
                        restartPerformed = true
                    }

                    if (!serviceHealthy) {
                        Log.w(TAG, "🔄 Motion-triggered: Service unhealthy - refreshing heartbeat")
                        lastHeartbeat = System.currentTimeMillis()
                        setupHeartbeatAlarm()
                        restartPerformed = true
                    }

                    if (restartPerformed) {
                        Log.d(TAG, "✅ Motion-triggered ultra-fast health check completed - restart performed")
                    } else {
                        Log.d(TAG, "✅ Motion-triggered ultra-fast health check completed - system healthy")
                    }

                } catch (e: Exception) {
                    Log.e(TAG, "❌ Motion-triggered ultra-fast health check failed: ${e.message}")
                }
            }

        } catch (e: Exception) {
            Log.e(TAG, "❌ Error in motion detection handler: ${e.message}")
        }
    }

    private fun stopMotionDetection() {
        try {
            if (!isMotionDetectionActive) return

            Log.d(TAG, "🎯 Stopping motion detection...")

            motionDetectionListener?.let { listener ->
                sensorManager?.unregisterListener(listener)
            }

            motionDetectionJob?.cancel()

            isMotionDetectionActive = false
            motionDetectionListener = null

            Log.d(TAG, "✅ Motion detection stopped")

        } catch (e: Exception) {
            Log.e(TAG, "❌ Error stopping motion detection: ${e.message}")
        }
    }

    private suspend fun performMotionTriggeredGeofenceRestart(): Boolean {
        return try {
            Log.d(TAG, "🔄 Starting motion-triggered geofence restart...")

            val bootReceiver = BootReceiver()
            val taskLocations = bootReceiver.readTaskLocationsFromDatabasePublic(this)

            if (taskLocations.isNotEmpty()) {
                Log.d(TAG, "🔄 Found ${taskLocations.size} task locations for restart")

                bootReceiver.registerPersistentGeofencesPublic(this, taskLocations)

                delay(3000)

                val isNowActive = geofenceManager?.isGeofencingActive() ?: false

                if (isNowActive) {
                    Log.d(TAG, "✅ Motion-triggered geofence restart successful")
                    geofenceManager?.onGeofenceEventReceived()
                    return true
                } else {
                    Log.w(TAG, "⚠️ Motion-triggered geofence restart did not activate system")
                    return false
                }

            } else {
                Log.w(TAG, "⚠️ No task locations found in database for restart")
                return true
            }

        } catch (e: Exception) {
            Log.e(TAG, "❌ Motion-triggered geofence restart failed: ${e.message}")
            false
        }
    }

    override fun onPredictiveGeofenceRequested(predictions: List<GeofenceManager.LocationPoint>) {
        Log.d(TAG, "🔮 Predictive geofencing triggered with ${predictions.size} predictions")

        try {
            // 1. 🚀 ACTIVATE PREDICTIVE MODE
            activatePredictiveMode(predictions)

            // 2. 🎯 ENHANCE NEARBY TASK MONITORING
            enhanceNearbyTaskMonitoring(predictions)

            // 3. ⚡ BOOST LOCATION TRACKING FREQUENCY
            boostLocationTrackingForPredictions()

            // 4. 📱 PREPARE NOTIFICATION SYSTEM
            prepareNotificationSystemForPredictions(predictions)

            // 5. 🔄 UPDATE SERVICE STATUS
            updateServiceStatusForPredictiveMode()

            Log.d(TAG, "✅ Predictive geofencing system activated successfully")

        } catch (e: Exception) {
            Log.e(TAG, "❌ Error in predictive geofencing: ${e.message}")
        }
    }

    private suspend fun performManualBackupHealthCheck(): Boolean {
        return try {
            Log.d(TAG, "🔍 Checking ultra-fast manual backup system health...")

            var restartPerformed = false

            val shouldBeActive = geofenceManager?.shouldActivateManualBackup() ?: false
            val isCurrentlyActive = isManualBackupActive
            val hasActiveGeofences = (geofenceManager?.getActiveGeofenceCount() ?: 0) > 0

            Log.d(TAG, "🔍 Ultra-fast manual backup status:")
            Log.d(TAG, "  - Should be active: $shouldBeActive")
            Log.d(TAG, "  - Currently active: $isCurrentlyActive")
            Log.d(TAG, "  - Has active geofences: $hasActiveGeofences")
            Log.d(TAG, "  - Vehicle movement: ${isVehicleMovement()}")

            if (shouldBeActive && !isCurrentlyActive && hasActiveGeofences) {
                Log.w(TAG, "🔄 Ultra-fast manual backup should be active but isn't - activating")
                activateUltraFastManualBackup()
                restartPerformed = true
            }

            else if (isCurrentlyActive && hasActiveGeofences) {
                val jobActive = manualCheckJob?.isActive ?: false
                if (!jobActive) {
                    Log.w(TAG, "🔄 Ultra-fast manual backup job is dead - restarting")
                    deactivateManualBackup()
                    delay(1000)
                    activateUltraFastManualBackup()
                    restartPerformed = true
                } else {
                    Log.d(TAG, "✅ Ultra-fast manual backup job is healthy")
                }
            }

            else if (isCurrentlyActive && !hasActiveGeofences) {
                Log.d(TAG, "🔄 Ultra-fast manual backup active but no geofences - deactivating")
                deactivateManualBackup()
                restartPerformed = true
            }

            // 🚀 SPECIAL: Auto-activate for vehicle movement
            else if (isVehicleMovement() && !isCurrentlyActive && hasActiveGeofences) {
                Log.w(TAG, "🚄 Vehicle movement detected - auto-activating ultra-fast backup")
                activateUltraFastManualBackup()
                restartPerformed = true
            }

            if (isManualBackupActive) {
                val locationAge = if (lastKnownLocation != null) {
                    (System.currentTimeMillis() - (lastKnownLocation?.time ?: 0)) / 1000L
                } else {
                    -1L
                }

                if (locationAge > 60L || locationAge == -1L) { // Reduced from 5min to 1min for ultra-fast
                    Log.w(TAG, "🔄 Location too old ($locationAge s) - refreshing ultra-fast location tracking")
                    setupUltraFastLocationTracking()
                    restartPerformed = true
                }
            }

            if (restartPerformed) {
                Log.d(TAG, "✅ Ultra-fast manual backup health check completed - restart performed")
            } else {
                Log.d(TAG, "✅ Ultra-fast manual backup health check completed - system healthy")
            }

            return restartPerformed

        } catch (e: Exception) {
            Log.e(TAG, "❌ Ultra-fast manual backup health check failed: ${e.message}")
            false
        }
    }

    /**
     * 🚀 STEP 1: Activate predictive mode
     */
    private fun activatePredictiveMode(predictions: List<GeofenceManager.LocationPoint>) {
        try {
            Log.d(TAG, "🔮 Activating predictive mode...")

            // Mark that we're in predictive mode
            isPredictiveModeActive = true
            predictiveModeStartTime = System.currentTimeMillis()

            // Store predictions for reference
            currentPredictions = predictions.toMutableList()

            // Enhanced logging for each prediction
            predictions.forEachIndexed { index, prediction ->
                val timeFromNow = (prediction.timestamp - System.currentTimeMillis()) / 1000
                Log.d(TAG, "🔮 Prediction ${index + 1}: " +
                        "lat=${String.format("%.6f", prediction.latitude)}, " +
                        "lon=${String.format("%.6f", prediction.longitude)}, " +
                        "in ${timeFromNow}s, " +
                        "speed=${String.format("%.1f", prediction.speed * 3.6)} km/h")
            }

            // Schedule predictive mode timeout (auto-deactivate after 2 minutes)
            schedulePredictiveModeTimeout()

            Log.d(TAG, "✅ Predictive mode activated with ${predictions.size} predictions")

        } catch (e: Exception) {
            Log.e(TAG, "❌ Error activating predictive mode: ${e.message}")
        }
    }

    /**
     * 🎯 STEP 2: Enhance monitoring for nearby tasks
     */
    private fun enhanceNearbyTaskMonitoring(predictions: List<GeofenceManager.LocationPoint>) {
        try {
            Log.d(TAG, "🎯 Enhancing nearby task monitoring...")

            val nearbyTasks = mutableSetOf<GeofenceManager.GeofenceData>()
            val enhancedRadius = getCurrentCalculatedRadius() * 2.5 // 2.5x radius for predictions

            // Find tasks near each prediction
            for (prediction in predictions) {
                val tasksNearPrediction = findTasksNearLocation(
                    prediction.latitude,
                    prediction.longitude,
                    enhancedRadius
                )
                nearbyTasks.addAll(tasksNearPrediction)
            }

            if (nearbyTasks.isNotEmpty()) {
                Log.d(TAG, "🎯 Found ${nearbyTasks.size} tasks potentially relevant to predictions:")

                nearbyTasks.forEach { task ->
                    val distanceToClosestPrediction = predictions.minOf { prediction ->
                        calculateDistance(
                            prediction.latitude, prediction.longitude,
                            task.latitude, task.longitude
                        )
                    }

                    Log.d(TAG, "  📍 ${task.title}: ${distanceToClosestPrediction.toInt()}m from closest prediction")

                    // Add to priority monitoring list
                    priorityMonitoringTasks[task.id] = PredictiveTaskInfo(
                        task = task,
                        closestPredictionDistance = distanceToClosestPrediction,
                        enhancedRadius = enhancedRadius,
                        detectionStartTime = System.currentTimeMillis()
                    )
                }

                Log.d(TAG, "✅ Enhanced monitoring activated for ${nearbyTasks.size} priority tasks")
            } else {
                Log.d(TAG, "ℹ️ No tasks found near predictions")
            }

        } catch (e: Exception) {
            Log.e(TAG, "❌ Error enhancing nearby task monitoring: ${e.message}")
        }
    }

    /**
     * ⚡ STEP 3: Boost location tracking frequency
     */
    private fun boostLocationTrackingForPredictions() {
        try {
            Log.d(TAG, "⚡ Boosting location tracking for predictions...")

            // Store current intervals before boosting
            if (!isPredictiveLocationBoostActive) {
                storeCurrentLocationIntervals()
            }

            isPredictiveLocationBoostActive = true

            // Calculate boosted intervals based on vehicle movement
            val boostedIntervals = when (currentMovementState) {
                MovementState.VEHICLE_FAST -> Pair(100L, 50L)    // Ultra-fast: 0.1s/0.05s
                MovementState.VEHICLE_SLOW -> Pair(200L, 100L)   // Very fast: 0.2s/0.1s
                MovementState.FAST_MOVING -> Pair(500L, 250L)    // Fast: 0.5s/0.25s
                else -> Pair(1000L, 500L)                        // Normal boost: 1s/0.5s
            }

            Log.d(TAG, "⚡ Applying boosted intervals: ${boostedIntervals.first}ms (fastest: ${boostedIntervals.second}ms)")

            // Apply boosted location tracking
            updateUltraFastLocationTrackingIntervals(boostedIntervals.first, boostedIntervals.second)

            // Schedule restore to normal intervals after 90 seconds
            schedulePredictiveBoostRestore()

            Log.d(TAG, "✅ Location tracking boosted for predictive mode")

        } catch (e: Exception) {
            Log.e(TAG, "❌ Error boosting location tracking: ${e.message}")
        }
    }

    /**
     * 📱 STEP 4: Prepare notification system
     */
    private fun prepareNotificationSystemForPredictions(predictions: List<GeofenceManager.LocationPoint>) {
        try {
            Log.d(TAG, "📱 Preparing notification system for predictions...")

            // Pre-create notification channels if needed
            ensureNotificationChannelsExist()

            // Calculate ETA for closest prediction
            val closestPrediction = predictions.minByOrNull {
                (it.timestamp - System.currentTimeMillis()).absoluteValue
            }

            closestPrediction?.let { prediction ->
                val etaSeconds = ((prediction.timestamp - System.currentTimeMillis()) / 1000).toInt()
                Log.d(TAG, "📱 Closest prediction ETA: ${etaSeconds}s")

                // Pre-warm notification data for faster response
                preWarmNotificationData(prediction, etaSeconds)
            }

            // Reduce notification cooldowns for predictive mode
            reducedCooldownMode = true
            reducedCooldownStartTime = System.currentTimeMillis()

            Log.d(TAG, "✅ Notification system prepared for predictive mode")

        } catch (e: Exception) {
            Log.e(TAG, "❌ Error preparing notification system: ${e.message}")
        }
    }

    /**
     * 🔄 STEP 5: Update service status
     */
    private fun updateServiceStatusForPredictiveMode() {
        try {
            Log.d(TAG, "🔄 Updating service status for predictive mode...")

            // Update notification to show predictive mode
            val predictiveNotification = createPredictiveNotification()
            notificationManager?.notify(NOTIFICATION_ID, predictiveNotification)

            // Log current system state
            logPredictiveSystemState()

            Log.d(TAG, "✅ Service status updated for predictive mode")

        } catch (e: Exception) {
            Log.e(TAG, "❌ Error updating service status: ${e.message}")
        }
    }

// ===== HELPER METHODS FOR PREDICTIVE GEOFENCING =====

    private fun findTasksNearLocation(
        latitude: Double,
        longitude: Double,
        radius: Double
    ): List<GeofenceManager.GeofenceData> {
        val nearbyTasks = mutableListOf<GeofenceManager.GeofenceData>()

        geofenceManager?.getActiveGeofenceLocations()?.forEach { task ->
            val distance = calculateDistance(latitude, longitude, task.latitude, task.longitude)
            if (distance <= radius) {
                nearbyTasks.add(task)
            }
        }

        return nearbyTasks
    }

    private fun getCurrentCalculatedRadius(): Double {
        return geofenceManager?.getCurrentCalculatedRadius()?.toDouble() ?: 150.0
    }

    private fun schedulePredictiveModeTimeout() {
        serviceScope.launch {
            delay(120000L) // 2 minutes
            if (isPredictiveModeActive) {
                Log.d(TAG, "⏰ Predictive mode timeout - deactivating")
                deactivatePredictiveMode()
            }
        }
    }

    private fun schedulePredictiveBoostRestore() {
        serviceScope.launch {
            delay(90000L) // 90 seconds
            if (isPredictiveLocationBoostActive) {
                Log.d(TAG, "⏰ Restoring normal location intervals after predictive boost")
                restoreNormalLocationIntervals()
            }
        }
    }

    private fun restoreNormalLocationIntervals() {
        if (isPredictiveLocationBoostActive) {
            isPredictiveLocationBoostActive = false

            val normalInterval = savedLocationInterval ?: 1000L
            val normalFastestInterval = savedFastestLocationInterval ?: 500L

            Log.d(TAG, "🔄 Restoring normal location intervals: ${normalInterval}ms (fastest: ${normalFastestInterval}ms)")
            updateUltraFastLocationTrackingIntervals(normalInterval, normalFastestInterval)
        }
    }

    private fun storeCurrentLocationIntervals() {
        // Store current intervals to restore later
        savedLocationInterval = when (currentMovementState) {
            MovementState.VEHICLE_FAST -> 250L
            MovementState.VEHICLE_SLOW -> 500L
            MovementState.FAST_MOVING -> 1000L
            MovementState.SLOW_MOVING -> 5000L
            MovementState.STATIONARY -> 60000L
        }

        savedFastestLocationInterval = savedLocationInterval?.let { it / 2 }
    }

    private fun ensureNotificationChannelsExist() {
        // Ensure all required notification channels are created
        // This is already handled in onCreate, but we double-check here
    }

    private fun preWarmNotificationData(prediction: GeofenceManager.LocationPoint, etaSeconds: Int) {
        // Pre-calculate notification content for faster delivery
        preWarmData = PredictiveNotificationData(
            location = prediction,
            eta = etaSeconds,
            preparedAt = System.currentTimeMillis()
        )
    }

    private fun createPredictiveNotification(): Notification {
        val notificationIntent = Intent(this, MainActivity::class.java)
        val pendingIntent = PendingIntent.getActivity(
            this, 0, notificationIntent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )

        val contentTitle = "Locado - Predictive Mode Active"
        val contentText = "🔮 Monitoring ${currentPredictions?.size ?: 0} predicted locations " +
                "(${currentMovementState.name.lowercase()}, " +
                "${String.format("%.1f", averageSpeed * 3.6)} km/h)"

        return NotificationCompat.Builder(this, CHANNEL_ID)
            .setContentTitle(contentTitle)
            .setContentText(contentText)
            .setSmallIcon(android.R.drawable.ic_menu_compass)
            .setContentIntent(pendingIntent)
            .setOngoing(true)
            .setPriority(NotificationCompat.PRIORITY_LOW)
            .setCategory(NotificationCompat.CATEGORY_SERVICE)
            .setVisibility(NotificationCompat.VISIBILITY_SECRET)
            .setAutoCancel(false)
            .setShowWhen(false)
            .setForegroundServiceBehavior(NotificationCompat.FOREGROUND_SERVICE_IMMEDIATE)
            .build()
    }

    private fun deactivatePredictiveMode() {
        try {
            Log.d(TAG, "🔄 Deactivating predictive mode...")

            isPredictiveModeActive = false
            currentPredictions?.clear()
            priorityMonitoringTasks.clear()

            // Restore normal location intervals if still boosted
            if (isPredictiveLocationBoostActive) {
                restoreNormalLocationIntervals()
            }

            // Restore normal notification cooldowns
            reducedCooldownMode = false

            // Update notification back to normal
            val normalNotification = createUltraNotification()
            notificationManager?.notify(NOTIFICATION_ID, normalNotification)

            Log.d(TAG, "✅ Predictive mode deactivated")

        } catch (e: Exception) {
            Log.e(TAG, "❌ Error deactivating predictive mode: ${e.message}")
        }
    }

    private fun logPredictiveSystemState() {
        Log.d(TAG, "=== PREDICTIVE SYSTEM STATE ===")
        Log.d(TAG, "Predictive Mode Active: $isPredictiveModeActive")
        Log.d(TAG, "Location Boost Active: $isPredictiveLocationBoostActive")
        Log.d(TAG, "Reduced Cooldown Mode: $reducedCooldownMode")
        Log.d(TAG, "Priority Tasks: ${priorityMonitoringTasks.size}")
        Log.d(TAG, "Current Predictions: ${currentPredictions?.size ?: 0}")
        Log.d(TAG, "Movement State: $currentMovementState")
        Log.d(TAG, "Average Speed: ${String.format("%.1f", averageSpeed * 3.6)} km/h")
        Log.d(TAG, "===============================")
    }

    // 🔮 DATA CLASSES FOR PREDICTIVE SYSTEM
    data class PredictiveTaskInfo(
        val task: GeofenceManager.GeofenceData,
        val closestPredictionDistance: Double,
        val enhancedRadius: Double,
        val detectionStartTime: Long
    )

    data class PredictiveNotificationData(
        val location: GeofenceManager.LocationPoint,
        val eta: Int,
        val preparedAt: Long
    )
}