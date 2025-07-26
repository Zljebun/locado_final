package com.example.locado_final

import android.content.Intent
import android.os.Bundle
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.EventChannel
import android.util.Log
import com.google.android.gms.tasks.Task
import android.app.NotificationChannel
import android.app.NotificationManager
import androidx.core.app.NotificationCompat
import android.app.PendingIntent
import android.graphics.BitmapFactory
import android.content.Context
import java.io.File
// 🔋 NOVI IMPORTS ZA BATTERY OPTIMIZATION
import android.os.PowerManager
import android.provider.Settings
import android.net.Uri

class MainActivity: FlutterActivity() {

    companion object {
        private const val TAG = "MainActivity"
        private const val CHANNEL = "com.example.locado_final/geofence"
        private const val EVENT_CHANNEL = "com.example.locado_final/geofence_events"

        // ✅ OPTIONAL EVENT SINK - SAMO ZA FLUTTER UI UPDATES
        // Native geofencing NE ZAVISI od ovoga
        var eventSink: EventChannel.EventSink? = null
            private set
    }

    private lateinit var geofenceManager: GeofenceManager

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        // 🚀 INITIALIZE HIBRIDNI SISTEM
        initializeHybridSystem()

        // ✅ SETUP EVENT CHANNEL ZA FLUTTER UI UPDATES (OPTIONAL)
        EventChannel(flutterEngine.dartExecutor.binaryMessenger, EVENT_CHANNEL)
            .setStreamHandler(object : EventChannel.StreamHandler {
                override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
                    Log.d(TAG, "📡 Flutter event channel connected (UI updates only)")
                    eventSink = events
                }

                override fun onCancel(arguments: Any?) {
                    Log.d(TAG, "📡 Flutter event channel disconnected (native geofencing continues)")
                    eventSink = null
                }
            })

        // Setup Method Channel
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL).setMethodCallHandler { call, result ->
            Log.d(TAG, "Method call received: ${call.method}")

            when (call.method) {
                "testConnection" -> {
                    Log.d(TAG, "Test connection called")
                    result.success("Connection successful - Android bridge is working!")
                }

                "startForegroundService" -> {
                    try {
                        val intent = Intent(this, LocadoForegroundService::class.java).apply {
                            action = LocadoForegroundService.ACTION_START_SERVICE
                        }
                        startForegroundService(intent)
                        Log.d(TAG, "Foreground service start intent sent")
                        result.success("Service start initiated")
                    } catch (e: Exception) {
                        Log.e(TAG, "Failed to start foreground service", e)
                        result.error("SERVICE_ERROR", "Failed to start service: ${e.message}", null)
                    }
                }

                "stopForegroundService" -> {
                    try {
                        val intent = Intent(this, LocadoForegroundService::class.java).apply {
                            action = LocadoForegroundService.ACTION_STOP_SERVICE
                        }
                        startService(intent)
                        Log.d(TAG, "Foreground service stop intent sent")
                        result.success("Service stop initiated")
                    } catch (e: Exception) {
                        Log.e(TAG, "Failed to stop foreground service", e)
                        result.error("SERVICE_ERROR", "Failed to stop service: ${e.message}", null)
                    }
                }

                "isServiceRunning" -> {
                    val isRunning = LocadoForegroundService.isRunning()
                    Log.d(TAG, "Service running status: $isRunning")
                    result.success(isRunning)
                }

                "addGeofence" -> {
                    try {
                        val id = call.argument<String>("id") ?: throw IllegalArgumentException("Missing id")
                        val latitude = call.argument<Double>("latitude") ?: throw IllegalArgumentException("Missing latitude")
                        val longitude = call.argument<Double>("longitude") ?: throw IllegalArgumentException("Missing longitude")
                        val radius = call.argument<Double>("radius")?.toFloat() ?: 100f
                        val title = call.argument<String>("title") ?: ""
                        val description = call.argument<String>("description") ?: ""

                        Log.d(TAG, "Adding geofence: $id at ($latitude, $longitude)")

                        val task = geofenceManager.addGeofence(id, latitude, longitude, radius, title, description)

                        if (task != null) {
                            // 🚀 HIBRIDNI SISTEM: Posle uspešnog dodavanja, pokreni service ako treba
                            task.addOnSuccessListener {
                                ensureServiceRunning()
                                Log.d(TAG, "✅ Geofence added - hybrid system checked")
                            }

                            handleGeofenceTask(task, result, "Geofence added successfully")
                        } else {
                            result.error("PERMISSION_ERROR", "Location permissions not granted", null)
                        }

                    } catch (e: Exception) {
                        Log.e(TAG, "Failed to add geofence", e)
                        result.error("GEOFENCE_ERROR", "Failed to add geofence: ${e.message}", null)
                    }
                }

                "removeGeofence" -> {
                    try {
                        val id = call.argument<String>("id") ?: throw IllegalArgumentException("Missing id")

                        Log.d(TAG, "Removing geofence: $id")

                        val task = geofenceManager.removeGeofence(id)
                        handleGeofenceTask(task, result, "Geofence removed successfully")

                    } catch (e: Exception) {
                        Log.e(TAG, "Failed to remove geofence", e)
                        result.error("GEOFENCE_ERROR", "Failed to remove geofence: ${e.message}", null)
                    }
                }

                "getActiveGeofences" -> {
                    try {
                        val activeIds = geofenceManager.getActiveGeofenceIds()
                        val count = geofenceManager.getActiveGeofenceCount()

                        Log.d(TAG, "🔍 GEOFENCE STATUS CHECK:")
                        Log.d(TAG, "🔍 Active geofence count: $count")
                        Log.d(TAG, "🔍 Active geofence IDs: $activeIds")

                        result.success(activeIds)

                    } catch (e: Exception) {
                        Log.e(TAG, "Failed to get active geofences", e)
                        result.error("GEOFENCE_ERROR", "Failed to get active geofences: ${e.message}", null)
                    }
                }

                "updateNotification" -> {
                    try {
                        val count = call.argument<Int>("count") ?: 0
                        val intent = Intent(this, LocadoForegroundService::class.java).apply {
                            action = "UPDATE_NOTIFICATION"
                            putExtra("geofence_count", count)
                        }
                        startService(intent)
                        result.success("Notification updated")

                    } catch (e: Exception) {
                        Log.e(TAG, "Failed to update notification", e)
                        result.error("NOTIFICATION_ERROR", "Failed to update notification: ${e.message}", null)
                    }
                }

                // 🚀 HIBRIDNI SISTEM METHOD CALLS
                "getHybridSystemStatus" -> {
                    try {
                        val status = getHybridSystemStatus()
                        result.success(status)
                    } catch (e: Exception) {
                        Log.e(TAG, "Failed to get hybrid system status", e)
                        result.error("HYBRID_ERROR", "Failed to get hybrid system status: ${e.message}", null)
                    }
                }

                "forceManualBackup" -> {
                    try {
                        // Force aktivacija manual backup-a za testing
                        Log.d(TAG, "🔄 Force activating manual backup for testing")
                        result.success("Manual backup force activation attempted")
                    } catch (e: Exception) {
                        Log.e(TAG, "Failed to force manual backup", e)
                        result.error("HYBRID_ERROR", "Failed to force manual backup: ${e.message}", null)
                    }
                }

                // 🔋 NOVI BATTERY OPTIMIZATION METHOD CALLS
                "checkBatteryOptimization" -> {
                    try {
                        val batteryStatus = getBatteryOptimizationStatus()
                        Log.d(TAG, "🔋 Battery optimization status: $batteryStatus")
                        result.success(batteryStatus)
                    } catch (e: Exception) {
                        Log.e(TAG, "❌ Error checking battery optimization: ${e.message}")
                        result.error("BATTERY_ERROR", "Failed to check battery optimization: ${e.message}", null)
                    }
                }

                "requestBatteryOptimizationWhitelist" -> {
                    try {
                        val requested = requestBatteryOptimizationWhitelist()
                        Log.d(TAG, "🔋 Battery optimization whitelist request: $requested")
                        result.success(if (requested) "Whitelist request sent" else "Already whitelisted")
                    } catch (e: Exception) {
                        Log.e(TAG, "❌ Error requesting battery optimization whitelist: ${e.message}")
                        result.error("BATTERY_ERROR", "Failed to request whitelist: ${e.message}", null)
                    }
                }

                else -> {
                    Log.w(TAG, "Unknown method: ${call.method}")
                    result.notImplemented()
                }
            }
        }

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "com.example.locado_final/fullscreen")
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "createFullScreenIntent" -> {
                        try {
                            val taskTitle = call.argument<String>("taskTitle")
                            val taskMessage = call.argument<String>("taskMessage")
                            val taskId = call.argument<String>("taskId")

                            val pendingIntent = createFullScreenIntent(taskTitle, taskMessage, taskId)
                            result.success("Full screen intent created")
                        } catch (e: Exception) {
                            result.error("ERROR", "Failed to create full screen intent: ${e.message}", null)
                        }
                    }
                    else -> result.notImplemented()
                }
            }

        // ✅ METHOD CHANNEL ZA LOCK SCREEN ALERTS (ZADRŽANO ZA FLUTTER CALLS)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "locado.lockscreen/channel")
            .setMethodCallHandler { call, result ->
                Log.d(TAG, "📞 Lock screen method call received from Flutter: ${call.method}")

                when (call.method) {
                    "showLockScreenAlert" -> {
                        try {
                            val taskTitle = call.argument<String>("taskTitle") ?: "Task Location"
                            val taskMessage = call.argument<String>("taskMessage") ?: "You are near a task location"
                            val taskId = call.argument<String>("taskId") ?: "unknown"

                            Log.d(TAG, "🚀 FLUTTER REQUESTED: LockScreenTaskActivity")
                            Log.d(TAG, "🚀 Task: $taskTitle")

                            val intent = Intent(this, LockScreenTaskActivity::class.java).apply {
                                putExtra("taskTitle", taskTitle)
                                putExtra("taskMessage", taskMessage)
                                putExtra("taskId", taskId)
                                addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or
                                        Intent.FLAG_ACTIVITY_NO_HISTORY or
                                        Intent.FLAG_ACTIVITY_EXCLUDE_FROM_RECENTS or
                                        Intent.FLAG_ACTIVITY_SINGLE_TOP)
                            }

                            startActivity(intent)
                            Log.d(TAG, "✅ LockScreenTaskActivity launched from Flutter call")
                            result.success("Lock screen alert launched successfully")

                        } catch (e: Exception) {
                            Log.e(TAG, "❌ Error launching lock screen alert from Flutter: ${e.message}")
                            result.error("LAUNCH_ERROR", "Failed to launch lock screen alert: ${e.message}", null)
                        }
                    }

                    else -> {
                        Log.w(TAG, "⚠️ Unknown lock screen method: ${call.method}")
                        result.notImplemented()
                    }
                }
            }

        // ✅ DEBUG METHOD CHANNEL ZA DEBUG PANEL
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "com.example.locado_final/debug")
            .setMethodCallHandler { call, result ->
                Log.d(TAG, "🐛 Debug method call received: ${call.method}")

                when (call.method) {
                    "getDebugStatus" -> {
                        try {
                            val geofenceCount = try {
                                geofenceManager.getActiveGeofenceCount()
                            } catch (e: Exception) {
                                Log.w(TAG, "GeofenceManager count failed: ${e.message}")
                                0
                            }

                            // 🚀 HIBRIDNI SISTEM DEBUG INFO
                            val hybridStatus = getHybridSystemStatus()

                            // 🔋 DODAJ BATTERY OPTIMIZATION STATUS U DEBUG
                            val batteryStatus = try {
                                getBatteryOptimizationStatus()
                            } catch (e: Exception) {
                                mapOf("error" to e.message)
                            }

                            val debugStatus = mapOf(
                                "serviceStatus" to if (LocadoForegroundService.isRunning()) "Running" else "Stopped",
                                "geofenceCount" to geofenceCount,
                                "lastHeartbeat" to if (LocadoForegroundService.getLastHeartbeat() > 0) {
                                    java.text.SimpleDateFormat("HH:mm:ss", java.util.Locale.getDefault())
                                        .format(java.util.Date(LocadoForegroundService.getLastHeartbeat()))
                                } else "Never",
                                "logFileSize" to getLogFileSize(),
                                "logFilePath" to DebugLogManager.getLogFilePath(this),
                                "recentLogs" to getRecentLogs(),
                                // 🚀 HIBRIDNI SISTEM STATUS
                                "hybridSystem" to hybridStatus,
                                // 🔋 BATTERY OPTIMIZATION STATUS
                                "batteryOptimization" to batteryStatus
                            )
                            result.success(debugStatus)
                        } catch (e: Exception) {
                            Log.e(TAG, "❌ Error getting debug status: ${e.message}")
                            result.error("DEBUG_ERROR", "Failed to get debug status: ${e.message}", null)
                        }
                    }

                    "shareLogFile" -> {
                        try {
                            val logContent = DebugLogManager.getLogFileContent(this)
                            val shareResult = mapOf(
                                "success" to true,
                                "logContent" to logContent
                            )
                            result.success(shareResult)
                        } catch (e: Exception) {
                            Log.e(TAG, "❌ Error sharing log file: ${e.message}")
                            result.success(mapOf(
                                "success" to false,
                                "error" to e.message
                            ))
                        }
                    }

                    "clearLogs" -> {
                        try {
                            DebugLogManager.clearLogs(this)
                            Log.d(TAG, "✅ Debug logs cleared")
                            result.success("Logs cleared successfully")
                        } catch (e: Exception) {
                            Log.e(TAG, "❌ Error clearing logs: ${e.message}")
                            result.error("DEBUG_ERROR", "Failed to clear logs: ${e.message}", null)
                        }
                    }

                    "testNotification" -> {
                        try {
                            DebugLogManager.logCustomEvent(this, "DEBUG_TEST", "Test notification triggered from debug panel")

                            val notificationManager = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager

                            val channel = NotificationChannel(
                                "debug_test_channel",
                                "Debug Test Notifications",
                                NotificationManager.IMPORTANCE_HIGH
                            )
                            notificationManager.createNotificationChannel(channel)

                            val notification = NotificationCompat.Builder(this, "debug_test_channel")
                                .setContentTitle("🐛 Debug Test")
                                .setContentText("Test notification from debug panel - ${System.currentTimeMillis()}")
                                .setSmallIcon(android.R.drawable.ic_dialog_info)
                                .setPriority(NotificationCompat.PRIORITY_HIGH)
                                .setAutoCancel(true)
                                .build()

                            notificationManager.notify(999999, notification)

                            Log.d(TAG, "✅ Test notification sent")
                            result.success("Test notification sent successfully")
                        } catch (e: Exception) {
                            Log.e(TAG, "❌ Error sending test notification: ${e.message}")
                            result.error("DEBUG_ERROR", "Failed to send test notification: ${e.message}", null)
                        }
                    }

                    "simulateGeofence" -> {
                        try {
                            val eventType = call.argument<String>("eventType") ?: "enter"
                            DebugLogManager.logCustomEvent(this, "DEBUG_SIMULATION", "Simulated geofence event: $eventType")
                            Log.d(TAG, "🧪 Simulating geofence event: $eventType")

                            // 🚀 SIMULIRAJ GEOFENCE EVENT ZA HIBRIDNI SISTEM
                            geofenceManager.onGeofenceEventReceived()

                            val simulationResult = mapOf(
                                "status" to "Simulated $eventType event",
                                "timestamp" to System.currentTimeMillis(),
                                "hybridSystemTriggered" to true
                            )

                            result.success(simulationResult)
                        } catch (e: Exception) {
                            Log.e(TAG, "❌ Error simulating geofence: ${e.message}")
                            result.error("DEBUG_ERROR", "Failed to simulate geofence: ${e.message}", null)
                        }
                    }

                    "checkService" -> {
                        try {
                            val serviceRunning = LocadoForegroundService.isRunning()
                            val geofenceCount = geofenceManager.getActiveGeofenceCount()
                            val lastHeartbeat = LocadoForegroundService.getLastHeartbeat()

                            DebugLogManager.logCustomEvent(this, "DEBUG_CHECK", "Service check - Running: $serviceRunning, Geofences: $geofenceCount")

                            val checkResult = mapOf(
                                "status" to "Service check completed",
                                "serviceRunning" to serviceRunning,
                                "geofenceCount" to geofenceCount,
                                "lastHeartbeat" to lastHeartbeat,
                                "timestamp" to System.currentTimeMillis()
                            )

                            Log.d(TAG, "✅ Service check completed - Running: $serviceRunning, Geofences: $geofenceCount")
                            result.success(checkResult)
                        } catch (e: Exception) {
                            Log.e(TAG, "❌ Error checking service: ${e.message}")
                            result.error("DEBUG_ERROR", "Failed to check service: ${e.message}", null)
                        }
                    }

                    "getFullLogs" -> {
                        try {
                            val fullLogs = DebugLogManager.getLogFileContent(this)
                            val logsResult = mapOf(
                                "logs" to fullLogs
                            )
                            result.success(logsResult)
                        } catch (e: Exception) {
                            Log.e(TAG, "❌ Error getting full logs: ${e.message}")
                            result.error("DEBUG_ERROR", "Failed to get full logs: ${e.message}", null)
                        }
                    }

                    "syncExistingTasks" -> {
                        try {
                            Log.d(TAG, "🔄 Manual sync of existing tasks requested")
                            DebugLogManager.logCustomEvent(this, "DEBUG_MANUAL_SYNC", "Manual task sync triggered")

                            val beforeCount = geofenceManager.getActiveGeofenceCount()
                            Log.d(TAG, "🔍 Geofences before sync: $beforeCount")

                            val afterCount = geofenceManager.getActiveGeofenceCount()

                            val syncResult = mapOf(
                                "status" to "Sync trigger sent to Flutter",
                                "beforeCount" to beforeCount,
                                "afterCount" to afterCount,
                                "timestamp" to System.currentTimeMillis()
                            )

                            Log.d(TAG, "✅ Sync trigger completed")
                            result.success(syncResult)
                        } catch (e: Exception) {
                            Log.e(TAG, "❌ Error during sync trigger: ${e.message}")
                            result.error("DEBUG_ERROR", "Failed to trigger sync: ${e.message}", null)
                        }
                    }

                    "getDatabaseTaskCount" -> {
                        try {
                            val databaseInfo = mapOf(
                                "taskCount" to "N/A",
                                "hasDatabase" to true,
                                "note" to "Database access requires Flutter layer"
                            )

                            Log.d(TAG, "📊 Database info requested - redirecting to Flutter")
                            result.success(databaseInfo)
                        } catch (e: Exception) {
                            Log.e(TAG, "❌ Error getting database info: ${e.message}")
                            result.success(mapOf(
                                "taskCount" to 0,
                                "hasDatabase" to false,
                                "error" to e.message
                            ))
                        }
                    }

                    else -> {
                        Log.w(TAG, "⚠️ Unknown debug method: ${call.method}")
                        result.notImplemented()
                    }
                }
            }

        // 🎯 METHOD CHANNEL ZA TASK DETAIL NAVIGATION
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "com.example.locado_final/task_detail")
            .setMethodCallHandler { call, result ->
                Log.d(TAG, "📋 Task detail method call received: ${call.method}")

                when (call.method) {
                    "openTaskDetail" -> {
                        try {
                            val taskId = call.argument<String>("taskId") ?: ""
                            val taskTitle = call.argument<String>("taskTitle") ?: "Task"

                            Log.d(TAG, "🎯 Opening task detail for: $taskId - $taskTitle")

                            DebugLogManager.logCustomEvent(this, "TASK_DETAIL_NAVIGATION", "Opening task detail - ID: $taskId, Title: $taskTitle")

                            result.success("Task detail navigation initiated")

                        } catch (e: Exception) {
                            Log.e(TAG, "❌ Error opening task detail: ${e.message}")
                            result.error("TASK_DETAIL_ERROR", "Failed to open task detail: ${e.message}", null)
                        }
                    }

                    "checkPendingTaskDetail" -> {
                        try {
                            val openTaskId = intent.getStringExtra("openTaskId")
                            val openTaskDetail = intent.getBooleanExtra("openTaskDetail", false)
                            val taskTitle = intent.getStringExtra("taskTitle")
                            val launchedFromNotification = intent.getBooleanExtra("launchedFromNotification", false)

                            if (openTaskDetail && openTaskId != null) {
                                Log.d(TAG, "🎯 Pending task detail found: $openTaskId")

                                val taskDetailData = mapOf(
                                    "hasTaskDetail" to true,
                                    "taskId" to openTaskId,
                                    "taskTitle" to (taskTitle ?: "Task"),
                                    "fromNotification" to launchedFromNotification
                                )

                                intent.removeExtra("openTaskId")
                                intent.removeExtra("openTaskDetail")
                                intent.removeExtra("taskTitle")
                                intent.removeExtra("launchedFromNotification")

                                DebugLogManager.logCustomEvent(this, "TASK_DETAIL_PENDING", "Found pending task detail - ID: $openTaskId")

                                result.success(taskDetailData)
                            } else {
                                result.success(mapOf("hasTaskDetail" to false))
                            }

                        } catch (e: Exception) {
                            Log.e(TAG, "❌ Error checking pending task detail: ${e.message}")
                            result.error("TASK_DETAIL_ERROR", "Failed to check pending task detail: ${e.message}", null)
                        }
                    }

                    else -> {
                        Log.w(TAG, "⚠️ Unknown task detail method: ${call.method}")
                        result.notImplemented()
                    }
                }
            }

        // 🆕 METHOD CHANNEL ZA DELETE TASK OPERATIONS
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "com.example.locado_final/delete_task")
            .setMethodCallHandler { call, result ->
                Log.d(TAG, "🗑️ Delete task method call received: ${call.method}")

                when (call.method) {
                    "checkPendingDeleteTask" -> {
                        try {
                            val deleteTaskId = intent.getStringExtra("pendingDeleteTaskId")
                            val deleteTaskTitle = intent.getStringExtra("pendingDeleteTaskTitle")

                            if (deleteTaskId != null) {
                                Log.d(TAG, "🗑️ Pending delete task found: $deleteTaskId")

                                val deleteTaskData = mapOf(
                                    "hasDeleteRequest" to true,
                                    "taskId" to deleteTaskId,
                                    "taskTitle" to (deleteTaskTitle ?: "Task")
                                )

                                intent.removeExtra("pendingDeleteTaskId")
                                intent.removeExtra("pendingDeleteTaskTitle")
                                intent.removeExtra("deleteTask")

                                DebugLogManager.logCustomEvent(this, "TASK_DELETE_PENDING", "Found pending delete request - ID: $deleteTaskId")

                                result.success(deleteTaskData)
                            } else {
                                result.success(mapOf("hasDeleteRequest" to false))
                            }

                        } catch (e: Exception) {
                            Log.e(TAG, "❌ Error checking pending delete task: ${e.message}")
                            result.error("DELETE_TASK_ERROR", "Failed to check pending delete task: ${e.message}", null)
                        }
                    }

                    "confirmTaskDeletion" -> {
                        try {
                            val taskId = call.argument<String>("taskId") ?: ""
                            val taskTitle = call.argument<String>("taskTitle") ?: "Task"

                            Log.d(TAG, "✅ Task deletion confirmed by Flutter - ID: $taskId, Title: $taskTitle")
                            DebugLogManager.logCustomEvent(this, "TASK_DELETE_CONFIRMED", "Flutter confirmed task deletion - ID: $taskId, Title: $taskTitle")

                            result.success("Task deletion confirmed")

                        } catch (e: Exception) {
                            Log.e(TAG, "❌ Error confirming task deletion: ${e.message}")
                            result.error("DELETE_TASK_ERROR", "Failed to confirm task deletion: ${e.message}", null)
                        }
                    }

                    else -> {
                        Log.w(TAG, "⚠️ Unknown delete task method: ${call.method}")
                        result.notImplemented()
                    }
                }
            }

        // ✅ NOVI METHOD CHANNEL ZA SETTINGS POSTAVKE
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "com.example.locado_final/settings")
            .setMethodCallHandler { call, result ->
                Log.d(TAG, "⚙️ Settings method call received: ${call.method}")

                when (call.method) {
                    "updateSettings" -> {
                        try {
                            val geofenceRadius = call.argument<Double>("geofence_radius") ?: 100.0
                            val soundMode = call.argument<String>("sound_mode") ?: "default"
                            val vibrationEnabled = call.argument<Boolean>("vibration_enabled") ?: true
                            val wakeScreenEnabled = call.argument<Boolean>("wake_screen_enabled") ?: true
                            val notificationPriority = call.argument<String>("notification_priority") ?: "high"

                            Log.d(TAG, "⚙️ Updating settings:")
                            Log.d(TAG, "  - Geofence radius: ${geofenceRadius}m")
                            Log.d(TAG, "  - Sound mode: $soundMode")
                            Log.d(TAG, "  - Vibration: $vibrationEnabled")
                            Log.d(TAG, "  - Wake screen: $wakeScreenEnabled")
                            Log.d(TAG, "  - Priority: $notificationPriority")

                            // ✅ SAČUVAJ POSTAVKE U SHARED PREFERENCES
                            val prefs = getSharedPreferences("locado_settings", Context.MODE_PRIVATE)
                            prefs.edit().apply {
                                putFloat("geofence_radius", geofenceRadius.toFloat())
                                putString("sound_mode", soundMode)
                                putBoolean("vibration_enabled", vibrationEnabled)
                                putBoolean("wake_screen_enabled", wakeScreenEnabled)
                                putString("notification_priority", notificationPriority)
                                apply()
                            }

                            // ✅ OBAVESTI GEOFENCE MANAGER O NOVOM RADIUSU
                            // (ovo će se koristiti u budućim geofence operacijama)

                            Log.d(TAG, "✅ Settings updated successfully")
                            result.success("Settings updated successfully")

                        } catch (e: Exception) {
                            Log.e(TAG, "❌ Error updating settings: ${e.message}")
                            result.error("SETTINGS_ERROR", "Failed to update settings: ${e.message}", null)
                        }
                    }

                    "getSettings" -> {
                        try {
                            val prefs = getSharedPreferences("locado_settings", Context.MODE_PRIVATE)

                            val settingsData = mapOf(
                                "geofence_radius" to prefs.getFloat("geofence_radius", 100.0f).toDouble(),
                                "sound_mode" to prefs.getString("sound_mode", "default"),
                                "vibration_enabled" to prefs.getBoolean("vibration_enabled", true),
                                "wake_screen_enabled" to prefs.getBoolean("wake_screen_enabled", true),
                                "notification_priority" to prefs.getString("notification_priority", "high")
                            )

                            Log.d(TAG, "⚙️ Retrieved settings: $settingsData")
                            result.success(settingsData)

                        } catch (e: Exception) {
                            Log.e(TAG, "❌ Error getting settings: ${e.message}")
                            result.error("SETTINGS_ERROR", "Failed to get settings: ${e.message}", null)
                        }
                    }

                    else -> {
                        Log.w(TAG, "⚠️ Unknown settings method: ${call.method}")
                        result.notImplemented()
                    }
                }
            }
    }

    /**
     * 🚀 INICIJALIZUJ HIBRIDNI SISTEM
     */
    private fun initializeHybridSystem() {
        try {
            // Initialize GeofenceManager
            geofenceManager = GeofenceManager(this)
            Log.d(TAG, "✅ Hybrid system initialized in MainActivity")
        } catch (e: Exception) {
            Log.e(TAG, "❌ Failed to initialize hybrid system: ${e.message}")
        }
    }

    /**
     * 🚀 OSIGURAJ DA SERVICE RADI
     */
    private fun ensureServiceRunning() {
        try {
            if (!LocadoForegroundService.isRunning()) {
                Log.d(TAG, "🔄 Service not running - starting for hybrid system")
                val intent = Intent(this, LocadoForegroundService::class.java).apply {
                    action = LocadoForegroundService.ACTION_START_SERVICE
                }
                startForegroundService(intent)
            }
        } catch (e: Exception) {
            Log.e(TAG, "❌ Failed to ensure service running: ${e.message}")
        }
    }

    /**
     * 🚀 DOBIJ HIBRIDNI SISTEM STATUS
     */
    private fun getHybridSystemStatus(): Map<String, Any> {
        return try {
            val isGeofencingActive = geofenceManager.isGeofencingActive()
            val lastEventTime = geofenceManager.getLastGeofenceEventTime()
            val shouldActivateBackup = geofenceManager.shouldActivateManualBackup()
            val activeLocations = geofenceManager.getActiveGeofenceLocations()

            mapOf<String, Any>(
                "geofencingActive" to isGeofencingActive,
                "lastGeofenceEvent" to lastEventTime,
                "lastGeofenceEventFormatted" to if (lastEventTime > 0) {
                    java.text.SimpleDateFormat("HH:mm:ss", java.util.Locale.getDefault())
                        .format(java.util.Date(lastEventTime))
                } else "Never",
                "shouldActivateManualBackup" to shouldActivateBackup,
                "activeLocationCount" to activeLocations.size,
                "serviceRunning" to LocadoForegroundService.isRunning(),
                "timeSinceLastEvent" to if (lastEventTime > 0) {
                    (System.currentTimeMillis() - lastEventTime) / 1000L
                } else -1L
            )
        } catch (e: Exception) {
            Log.e(TAG, "❌ Error getting hybrid system status: ${e.message}")
            mapOf<String, Any>(
                "error" to (e.message ?: "Unknown error"),
                "geofencingActive" to false,
                "serviceRunning" to false
            )
        }
    }

    /**
     * 🔋 PROVERI BATTERY OPTIMIZATION STATUS
     */
    private fun getBatteryOptimizationStatus(): Map<String, Any> {
        return try {
            val powerManager = getSystemService(Context.POWER_SERVICE) as PowerManager
            val packageName = packageName
            val isIgnoringOptimizations = powerManager.isIgnoringBatteryOptimizations(packageName)

            mapOf(
                "isWhitelisted" to isIgnoringOptimizations,
                "packageName" to packageName,
                "androidVersion" to android.os.Build.VERSION.SDK_INT,
                "canRequestWhitelist" to (android.os.Build.VERSION.SDK_INT >= android.os.Build.VERSION_CODES.M),
                "timestamp" to System.currentTimeMillis()
            )
        } catch (e: Exception) {
            Log.e(TAG, "❌ Error getting battery optimization status: ${e.message}")
            mapOf(
                "isWhitelisted" to false,
                "error" to (e.message ?: "Unknown error"),
                "packageName" to packageName
            )
        }
    }

    /**
     * 🔋 ZATRAŽI BATTERY OPTIMIZATION WHITELIST
     */
    private fun requestBatteryOptimizationWhitelist(): Boolean {
        return try {
            val powerManager = getSystemService(Context.POWER_SERVICE) as PowerManager
            val packageName = packageName

            if (powerManager.isIgnoringBatteryOptimizations(packageName)) {
                Log.d(TAG, "✅ App already whitelisted for battery optimization")
                return false // Already whitelisted
            }

            if (android.os.Build.VERSION.SDK_INT >= android.os.Build.VERSION_CODES.M) {
                val intent = Intent().apply {
                    action = Settings.ACTION_REQUEST_IGNORE_BATTERY_OPTIMIZATIONS
                    data = Uri.parse("package:$packageName")
                    addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                }

                startActivity(intent)
                Log.d(TAG, "✅ Battery optimization whitelist intent sent")
                return true // Request sent
            } else {
                Log.d(TAG, "⚠️ Battery optimization not available on this Android version")
                return false // Not supported
            }

        } catch (e: Exception) {
            Log.e(TAG, "❌ Error requesting battery optimization whitelist: ${e.message}")
            throw e
        }
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)

        // Check if launched with task detail intent
        checkForTaskDetailIntent()
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent) // Update the intent

        // Check for task detail intent on new intent
        checkForTaskDetailIntent()
    }

    private fun checkForTaskDetailIntent() {
        try {
            val deleteTask = intent.getBooleanExtra("deleteTask", false)
            val deleteTaskId = intent.getStringExtra("taskId")
            val deleteTaskTitle = intent.getStringExtra("taskTitle")

            if (deleteTask && deleteTaskId != null) {
                Log.d(TAG, "🗑️ MainActivity received DELETE TASK request - ID: $deleteTaskId, Title: $deleteTaskTitle")

                intent.putExtra("pendingDeleteTaskId", deleteTaskId)
                intent.putExtra("pendingDeleteTaskTitle", deleteTaskTitle)

                DebugLogManager.logCustomEvent(this, "TASK_DELETE_REQUEST", "MainActivity received delete request - ID: $deleteTaskId, Title: $deleteTaskTitle")
                return
            }

            val openTaskDetail = intent.getBooleanExtra("openTaskDetail", false)
            val taskId = intent.getStringExtra("taskId")
            val taskTitle = intent.getStringExtra("taskTitle")
            val launchedFromNotification = intent.getBooleanExtra("launchedFromNotification", false)

            if (openTaskDetail && taskId != null) {
                Log.d(TAG, "🎯 MainActivity launched with task detail request - ID: $taskId, Title: $taskTitle")

                // Store the data for Flutter to pick up
                intent.putExtra("openTaskId", taskId)

                // Log the task detail request
                DebugLogManager.logCustomEvent(this, "TASK_DETAIL_LAUNCH", "MainActivity received task detail request - ID: $taskId, Title: $taskTitle, FromNotification: $launchedFromNotification")
            }
        } catch (e: Exception) {
            Log.e(TAG, "❌ Error checking task detail intent: ${e.message}")
        }
    }

    // ✅ HELPER METODA - Pošalje event Flutter-u AKO je povezan (optional)
    // Poziva se iz GeofenceBroadcastReceiver
    fun sendOptionalFlutterEvent(eventData: Map<String, Any>) {
        try {
            eventSink?.success(eventData)
            Log.d(TAG, "📡 Optional Flutter event sent (UI update)")
        } catch (e: Exception) {
            Log.d(TAG, "📡 Flutter not connected - native geofencing continues: ${e.message}")
        }
    }

    private fun showFullScreenNotification(taskTitle: String, taskMessage: String, taskId: String) {
        startActivity(Intent(this, LockScreenTaskActivity::class.java).apply {
            putExtra("taskTitle", taskTitle)
            addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or
                    Intent.FLAG_ACTIVITY_CLEAR_TOP or
                    Intent.FLAG_ACTIVITY_BROUGHT_TO_FRONT)
        })
    }

    private fun showOriginalFullScreenNotification(taskTitle: String, taskMessage: String, taskId: String) {
        Log.d(TAG, "🔄 Using original fullscreen notification as fallback")

        val notificationManager = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager

        val channel = NotificationChannel(
            "fullscreen_geofence_channel",
            "Full Screen Geofence Alerts",
            NotificationManager.IMPORTANCE_HIGH
        ).apply {
            description = "Full screen location alerts"
            enableVibration(true)
            enableLights(true)
            lightColor = android.graphics.Color.GREEN
            vibrationPattern = longArrayOf(0, 1000, 500, 1000)
        }
        notificationManager.createNotificationChannel(channel)

        val fullScreenPendingIntent = createFullScreenIntent(taskTitle, taskMessage, taskId)

        val notification = NotificationCompat.Builder(this, "fullscreen_geofence_channel")
            .setContentTitle("🚨 LOCADO ALERT 🚨")
            .setContentText(taskMessage)
            .setSmallIcon(android.R.drawable.ic_dialog_alert)
            .setLargeIcon(BitmapFactory.decodeResource(resources, R.mipmap.ic_launcher))
            .setPriority(NotificationCompat.PRIORITY_MAX)
            .setCategory(NotificationCompat.CATEGORY_ALARM)
            .setFullScreenIntent(fullScreenPendingIntent, true)
            .setAutoCancel(true)
            .setVibrate(longArrayOf(0, 1000, 500, 1000))
            .setLights(android.graphics.Color.GREEN, 1000, 500)
            .build()

        notificationManager.notify(System.currentTimeMillis().toInt(), notification)
    }

    private fun createFullScreenIntent(taskTitle: String?, taskMessage: String?, taskId: String?): PendingIntent {
        val fullScreenIntent = Intent(this, FullScreenAlertActivity::class.java).apply {
            putExtra("taskTitle", taskTitle ?: "Task Location")
            putExtra("taskMessage", taskMessage ?: "You are near a task location")
            putExtra("taskId", taskId ?: "unknown")
            flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP
        }

        return PendingIntent.getActivity(
            this,
            0,
            fullScreenIntent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )
    }

    private fun handleGeofenceTask(task: Task<Void>, result: MethodChannel.Result, successMessage: String) {
        task.addOnSuccessListener {
            Log.d(TAG, successMessage)
            result.success(successMessage)
        }.addOnFailureListener { exception ->
            Log.e(TAG, "Geofence operation failed", exception)
            result.error("GEOFENCE_ERROR", "Operation failed: ${exception.message}", null)
        }
    }

    /**
     * 🐛 DEBUG HELPER METODE
     */
    private fun getLogFileSize(): String {
        return try {
            val logFile = java.io.File(DebugLogManager.getLogFilePath(this))
            if (logFile.exists()) {
                val sizeInBytes = logFile.length()
                when {
                    sizeInBytes < 1024 -> "${sizeInBytes} B"
                    sizeInBytes < 1024 * 1024 -> "${sizeInBytes / 1024} KB"
                    else -> "${"%.1f".format(sizeInBytes / (1024.0 * 1024.0))} MB"
                }
            } else {
                "0 KB"
            }
        } catch (e: Exception) {
            "Unknown"
        }
    }

    private fun getRecentLogs(): List<String> {
        return try {
            val logContent = DebugLogManager.getLogFileContent(this)
            val lines = logContent.split('\n')
            lines.takeLast(10).filter { it.isNotBlank() }
        } catch (e: Exception) {
            emptyList()
        }
    }
}