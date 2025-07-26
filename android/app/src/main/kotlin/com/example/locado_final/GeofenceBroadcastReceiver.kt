package com.example.locado_final

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.util.Log
import com.google.android.gms.location.Geofence
import com.google.android.gms.location.GeofencingEvent
import android.database.sqlite.SQLiteDatabase
import android.database.Cursor
import android.app.PendingIntent
import androidx.core.app.NotificationCompat
import android.app.NotificationManager
import android.app.NotificationChannel
import android.os.Build
import java.io.File
import java.io.FileWriter
import java.text.SimpleDateFormat
import java.util.*

class GeofenceBroadcastReceiver : BroadcastReceiver() {

    companion object {
        private const val TAG = "GeofenceBroadcastReceiver"
        private const val NOTIFICATION_CHANNEL_ID = "LOCADO_GEOFENCE_ALERTS"
        private const val NOTIFICATION_CHANNEL_NAME = "Locado Geofence Alerts"
    }

    override fun onReceive(context: Context, intent: Intent) {
        val currentTime = System.currentTimeMillis()
        Log.d(TAG, "🚨 GEOFENCE EVENT RECEIVED AT: $currentTime")

        // 🚀 HIBRIDNI SISTEM: Notify GeofenceManager da je geofencing aktivan
        notifyGeofenceManagerActive(context)

        val geofencingEvent = GeofencingEvent.fromIntent(intent)

        if (geofencingEvent == null) {
            Log.e(TAG, "Geofencing event is null")
            return
        }

        if (geofencingEvent.hasError()) {
            Log.e(TAG, "Geofencing error: ${geofencingEvent.errorCode}")
            return
        }

        // Get the transition type
        val geofenceTransition = geofencingEvent.geofenceTransition

        // Get the geofences that were triggered
        val triggeringGeofences = geofencingEvent.triggeringGeofences

        if (triggeringGeofences.isNullOrEmpty()) {
            Log.w(TAG, "No triggering geofences found")
            return
        }

        // Get location that triggered the geofence
        val location = geofencingEvent.triggeringLocation

        Log.d(TAG, "Geofence transition: ${getTransitionString(geofenceTransition)}")

        // Process each triggered geofence
        for (geofence in triggeringGeofences) {
            handleGeofenceTransition(
                context = context,
                geofenceId = geofence.requestId,
                transitionType = geofenceTransition,
                latitude = location?.latitude ?: 0.0,
                longitude = location?.longitude ?: 0.0
            )
        }
    }

    /**
     * 🚀 HIBRIDNI SISTEM: Obavesti GeofenceManager da je geofencing aktivan
     */
    private fun notifyGeofenceManagerActive(context: Context) {
        try {
            // Kreiraj GeofenceManager instancu i pozovi tracking metodu
            val geofenceManager = GeofenceManager(context)
            geofenceManager.onGeofenceEventReceived()
        } catch (e: Exception) {
            Log.w(TAG, "Could not notify GeofenceManager: ${e.message}")
        }
    }

    private fun handleGeofenceTransition(
        context: Context,
        geofenceId: String,
        transitionType: Int,
        latitude: Double,
        longitude: Double
    ) {

        Log.d(TAG, "Processing geofence: $geofenceId, transition: ${getTransitionString(transitionType)}")

        // ✅ GET TASK TITLE FROM DATABASE
        val taskTitle = getTaskTitleFromGeofenceId(context, geofenceId)
        Log.d(TAG, "🔍 DEBUG: geofenceId = '$geofenceId'")
        Log.d(TAG, "🔍 DEBUG: extracted taskTitle = '$taskTitle'")
        Log.d(TAG, "🔍 DEBUG: taskTitle is null? ${taskTitle == null}")
        Log.d(TAG, "🔍 DEBUG: taskTitle is empty? ${taskTitle?.isEmpty()}")

        when (transitionType) {
            Geofence.GEOFENCE_TRANSITION_ENTER -> {
                Log.d(TAG, "🟢 User ENTERED geofence: $geofenceId -> $taskTitle")

                val titleToSend = taskTitle ?: "Task Location"
                Log.d(TAG, "🔍 DEBUG: About to send notification with title: '$titleToSend'")

                // 🚀 PRIORITET: NATIVE NOTIFIKACIJE PRVO
                showReliableNativeNotification(context, taskTitle ?: "Task Location", geofenceId)

                // ✅ OPCIONO: POŠALJI EVENT FLUTTER-U (AKO JE DOSTUPAN)
                sendOptionalEventToFlutter(
                    geofenceId = geofenceId,
                    eventType = "ENTER",
                    latitude = latitude,
                    longitude = longitude,
                    title = taskTitle
                )
            }
            Geofence.GEOFENCE_TRANSITION_EXIT -> {
                Log.d(TAG, "🔴 User EXITED geofence: $geofenceId -> $taskTitle")

                // ✅ OPCIONO: POŠALJI EVENT FLUTTER-U
                sendOptionalEventToFlutter(
                    geofenceId = geofenceId,
                    eventType = "EXIT",
                    latitude = latitude,
                    longitude = longitude,
                    title = taskTitle
                )
            }
            Geofence.GEOFENCE_TRANSITION_DWELL -> {
                Log.d(TAG, "🟡 User is DWELLING in geofence: $geofenceId -> $taskTitle")

                // ✅ OPCIONO: POŠALJI EVENT FLUTTER-U
                sendOptionalEventToFlutter(
                    geofenceId = geofenceId,
                    eventType = "DWELL",
                    latitude = latitude,
                    longitude = longitude,
                    title = taskTitle
                )
            }
            else -> {
                Log.w(TAG, "Unknown geofence transition: $transitionType")
            }
        }
    }

    // 🚀 AŽURIRANA METODA: Koristi postavke iz Settings-a
    private fun showReliableNativeNotification(context: Context, taskTitle: String, geofenceId: String) {
        try {
            Log.d(TAG, "🔔 Showing RELIABLE native notification for: $taskTitle")

            Log.d(TAG, "🔍 DEBUG in showReliableNativeNotification:")
            Log.d(TAG, "🔍 DEBUG: received taskTitle parameter = '$taskTitle'")
            Log.d(TAG, "🔍 DEBUG: received geofenceId parameter = '$geofenceId'")

            // ✅ ČITAJ POSTAVKE IZ SHARED PREFERENCES
            val prefs = context.getSharedPreferences("locado_settings", Context.MODE_PRIVATE)
            val vibrationEnabled = prefs.getBoolean("vibration_enabled", true)
            val wakeScreenEnabled = prefs.getBoolean("wake_screen_enabled", true)
            val soundMode = prefs.getString("sound_mode", "default") ?: "default"
            val priority = prefs.getString("notification_priority", "high") ?: "high"

            Log.d(TAG, "📱 Using settings: vibration=$vibrationEnabled, wake=$wakeScreenEnabled, sound=$soundMode, priority=$priority")

            val notificationManager = context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager

            // ✅ KREIRAJ NOTIFICATION CHANNEL (GARANTOVANO)
            createNotificationChannelIfNeeded(notificationManager)

            // ✅ KREIRAJ LOCK SCREEN INTENT
            val lockScreenIntent = Intent(context, LockScreenTaskActivity::class.java).apply {
                putExtra("taskTitle", taskTitle)
                putExtra("taskMessage", "You are near: $taskTitle")
                putExtra("taskId", geofenceId)
                flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP
            }

            val pendingIntent = PendingIntent.getActivity(
                context,
                geofenceId.hashCode(),
                lockScreenIntent,
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
            )

            // ✅ KONVERTUJ PRIORITY STRING U ANDROID PRIORITY
            val androidPriority = when (priority) {
                "low" -> NotificationCompat.PRIORITY_LOW
                "normal" -> NotificationCompat.PRIORITY_DEFAULT
                "high" -> NotificationCompat.PRIORITY_HIGH
                "max" -> NotificationCompat.PRIORITY_MAX
                else -> NotificationCompat.PRIORITY_HIGH
            }

            // ✅ KREIRAJ NOTIFICATION SA POSTAVKAMA IZ SETTINGS-A
            val notificationBuilder = NotificationCompat.Builder(context, NOTIFICATION_CHANNEL_ID)
                .setSmallIcon(android.R.drawable.ic_dialog_alert)
                .setContentTitle("🚨 LOCADO ALERT")
                .setContentText("📍 You're near: $taskTitle")
                .setPriority(androidPriority)
                .setCategory(NotificationCompat.CATEGORY_ALARM)
                .setVisibility(NotificationCompat.VISIBILITY_PUBLIC)
                .setContentIntent(pendingIntent)
                .setAutoCancel(true)
                .setTimeoutAfter(15000) // 15 sekundi
                .setStyle(NotificationCompat.BigTextStyle()
                    .bigText("📍 You are near your task location: $taskTitle\n\nTap to view details.")
                    .setBigContentTitle("🔔 Locado Task Alert")
                    .setSummaryText("Task Reminder"))

            // ✅ APLIKUJ VIBRATION POSTAVKU
            if (vibrationEnabled) {
                notificationBuilder.setVibrate(longArrayOf(0, 1000, 500, 1000))
            } else {
                notificationBuilder.setVibrate(null)
            }

            // ✅ APLIKUJ SOUND POSTAVKU
            when (soundMode) {
                "default" -> notificationBuilder.setDefaults(NotificationCompat.DEFAULT_SOUND)
                "system_notification" -> notificationBuilder.setSound(android.provider.Settings.System.DEFAULT_NOTIFICATION_URI)
                "system_alert" -> notificationBuilder.setSound(android.provider.Settings.System.DEFAULT_ALARM_ALERT_URI)
                "system_alarm" -> notificationBuilder.setSound(android.provider.Settings.System.DEFAULT_ALARM_ALERT_URI)
                "silent" -> notificationBuilder.setSound(null)
                else -> notificationBuilder.setDefaults(NotificationCompat.DEFAULT_SOUND)
            }

            // ✅ APLIKUJ WAKE SCREEN POSTAVKU
            if (wakeScreenEnabled) {
                notificationBuilder.setFullScreenIntent(pendingIntent, true)
            }

            val notification = notificationBuilder.build()

            // ✅ POŠALJI NOTIFIKACIJU
            val notificationId = geofenceId.hashCode()
            notificationManager.notify(notificationId, notification)

            Log.d(TAG, "✅ RELIABLE native notification sent successfully for: $taskTitle (ID: $notificationId)")
            Log.d(TAG, "📱 Settings applied: vibration=$vibrationEnabled, sound=$soundMode, wake=$wakeScreenEnabled, priority=$priority")

        } catch (e: Exception) {
            Log.e(TAG, "❌ Error showing reliable native notification: ${e.message}", e)

            // ✅ FALLBACK: SIMPLE NOTIFICATION
            showFallbackNotification(context, taskTitle, geofenceId)
        }
    }

    // ✅ GARANTOVANO KREIRANJE NOTIFICATION CHANNEL-A
    private fun createNotificationChannelIfNeeded(notificationManager: NotificationManager) {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val existingChannel = notificationManager.getNotificationChannel(NOTIFICATION_CHANNEL_ID)
            if (existingChannel == null) {
                val channel = NotificationChannel(
                    NOTIFICATION_CHANNEL_ID,
                    NOTIFICATION_CHANNEL_NAME,
                    NotificationManager.IMPORTANCE_HIGH
                ).apply {
                    description = "Critical location-based task alerts"
                    enableVibration(true)
                    enableLights(true)
                    lightColor = android.graphics.Color.GREEN
                    vibrationPattern = longArrayOf(0, 1000, 500, 1000)
                    setBypassDnd(true) // Probiće Do Not Disturb
                    lockscreenVisibility = android.app.Notification.VISIBILITY_PUBLIC
                }
                notificationManager.createNotificationChannel(channel)
                Log.d(TAG, "✅ Created notification channel: $NOTIFICATION_CHANNEL_ID")
            }
        }
    }

    // ✅ FALLBACK NOTIFIKACIJA (AKO GLAVNA NE USPE)
    private fun showFallbackNotification(context: Context, taskTitle: String, geofenceId: String) {
        try {
            Log.d(TAG, "🔄 Showing FALLBACK notification for: $taskTitle")

            val notificationManager = context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager

            val simpleNotification = NotificationCompat.Builder(context, "default")
                .setSmallIcon(android.R.drawable.ic_dialog_info)
                .setContentTitle("Locado Alert")
                .setContentText("Near: $taskTitle")
                .setPriority(NotificationCompat.PRIORITY_HIGH)
                .setAutoCancel(true)
                .build()

            notificationManager.notify(geofenceId.hashCode(), simpleNotification)
            Log.d(TAG, "✅ Fallback notification sent")

        } catch (e: Exception) {
            Log.e(TAG, "❌ Even fallback notification failed: ${e.message}")
        }
    }

    // ✅ OPCIONO SLANJE FLUTTER-U (NEĆE BLOKIRATI AKO FLUTTER NIJE DOSTUPAN)
    private fun sendOptionalEventToFlutter(
        geofenceId: String,
        eventType: String,
        latitude: Double,
        longitude: Double,
        title: String?
    ) {
        try {
            val eventData = mapOf(
                "geofenceId" to geofenceId,
                "eventType" to eventType,
                "latitude" to latitude,
                "longitude" to longitude,
                "timestamp" to System.currentTimeMillis(),
                "title" to (title ?: "Task Location"),
                "description" to "You are near: ${title ?: "a task location"}"
            )

            // ✅ POKUŠAJ SLANJE FLUTTER-U (AKO JE DOSTUPAN)
            MainActivity.eventSink?.success(eventData)
            Log.d(TAG, "📡 Optional event sent to Flutter: $geofenceId - $eventType - $title")

        } catch (e: Exception) {
            Log.d(TAG, "📡 Flutter not available (normal when app is killed): ${e.message}")
            // ✅ OVO NIJE GREŠKA - NORMALNO JE KADA JE APP KILOVAN
        }
    }

    // ✅ ČITA PRAVI NAZIV IZ BAZE PODATAKA
    private fun getTaskTitleFromGeofenceId(context: Context, geofenceId: String): String {
        return when {
            geofenceId.startsWith("task_") -> {
                try {
                    // Izvuci task ID iz geofence ID-ja
                    val taskId = geofenceId.removePrefix("task_").toIntOrNull()

                    if (taskId != null) {
                        // Čitaj iz baze podataka
                        val taskTitle = getTaskTitleFromDatabase(context, taskId)
                        Log.d(TAG, "📝 Database lookup: Task $taskId = '$taskTitle'")
                        return taskTitle ?: "Task Location"
                    } else {
                        Log.w(TAG, "⚠️ Invalid task ID in geofence: $geofenceId")
                        return "Task Location"
                    }
                } catch (e: Exception) {
                    Log.e(TAG, "❌ Error getting task title: ${e.message}")
                    return "Task Location"
                }
            }
            geofenceId.startsWith("test_") -> "Test Task"
            else -> "Location Alert"
        }
    }

    // ✅ ČITA TITLE IZ SQLite BAZE
    private fun getTaskTitleFromDatabase(context: Context, taskId: Int): String? {
        return try {
            val dbPath = context.getDatabasePath("locations.db").absolutePath
            Log.d(TAG, "📂 Database path: $dbPath")

            val db = SQLiteDatabase.openDatabase(dbPath, null, SQLiteDatabase.OPEN_READONLY)

            val cursor: Cursor = db.rawQuery(
                "SELECT title FROM task_locations WHERE id = ?",
                arrayOf(taskId.toString())
            )

            val title = if (cursor.moveToFirst()) {
                val titleFromDb = cursor.getString(0)
                Log.d(TAG, "✅ Found title in database: '$titleFromDb'")
                titleFromDb
            } else {
                Log.w(TAG, "⚠️ No task found in database for ID: $taskId")
                null
            }

            cursor.close()
            db.close()

            title

        } catch (e: Exception) {
            Log.e(TAG, "❌ Database error for task $taskId: ${e.message}")
            e.printStackTrace()
            null
        }
    }

    private fun getTransitionString(transitionType: Int): String {
        return when (transitionType) {
            Geofence.GEOFENCE_TRANSITION_ENTER -> "ENTER"
            Geofence.GEOFENCE_TRANSITION_EXIT -> "EXIT"
            Geofence.GEOFENCE_TRANSITION_DWELL -> "DWELL"
            else -> "UNKNOWN($transitionType)"
        }
    }
}