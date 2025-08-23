package com.example.locado_final

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import androidx.core.app.NotificationCompat
import android.util.Log
import android.os.PowerManager
import android.graphics.Color

/**
 * AlarmReceiver handles scheduled notification alarms
 * This receiver is triggered by AlarmManager when a scheduled notification should be displayed
 */
class AlarmReceiver : BroadcastReceiver() {

    companion object {
        private const val TAG = "AlarmReceiver"
        private const val NOTIFICATION_CHANNEL_ID = "locado_scheduled_reminders"
        private const val NOTIFICATION_CHANNEL_NAME = "Task Reminders"
        
        // Wake lock timeout - 10 seconds should be enough to show notification
        private const val WAKE_LOCK_TIMEOUT = 10000L
        
        // Action constant for scheduled notifications
        const val ACTION_SCHEDULED_NOTIFICATION = "com.example.locado_final.SCHEDULED_NOTIFICATION"
        
        // Extra keys for notification data
        const val EXTRA_NOTIFICATION_ID = "notificationId"
        const val EXTRA_NOTIFICATION_TITLE = "title"
        const val EXTRA_NOTIFICATION_BODY = "message"
        const val EXTRA_TASK_ID = "taskId"
        const val EXTRA_EVENT_ID = "eventId"
    }

    override fun onReceive(context: Context, intent: Intent) {
        Log.d(TAG, "AlarmReceiver triggered: ${intent.action}")
        
        // Log all extras for debugging
        intent.extras?.let { bundle ->
            for (key in bundle.keySet()) {
                Log.d(TAG, "Intent extra: $key = ${bundle.get(key)}")
            }
        }
        
        // Acquire wake lock to ensure notification shows even if device is sleeping
        val powerManager = context.getSystemService(Context.POWER_SERVICE) as PowerManager
        val wakeLock = powerManager.newWakeLock(
            PowerManager.PARTIAL_WAKE_LOCK,
            "Locado::ScheduledNotification"
        )
        
        try {
            wakeLock.acquire(WAKE_LOCK_TIMEOUT)
            Log.d(TAG, "Wake lock acquired for scheduled notification")
            
            // Process the scheduled notification
            when (intent.action) {
                ACTION_SCHEDULED_NOTIFICATION -> {
                    handleScheduledNotification(context, intent)
                }
                else -> {
                    Log.w(TAG, "Unknown alarm action: ${intent.action}")
                }
            }
            
        } catch (e: Exception) {
            Log.e(TAG, "Error processing scheduled notification", e)
            // Log error to debug manager if available
            try {
                DebugLogManager.logCustomEvent(context, "ALARM_ERROR", "Scheduled notification error: ${e.message}")
            } catch (debugError: Exception) {
                Log.w(TAG, "Could not log to DebugLogManager: ${debugError.message}")
            }
        } finally {
            // Always release wake lock
            if (wakeLock.isHeld) {
                wakeLock.release()
                Log.d(TAG, "Wake lock released")
            }
        }
    }
    
    /**
     * Handle scheduled notification display
     */
    private fun handleScheduledNotification(context: Context, intent: Intent) {
        try {
            // Extract notification data from intent
            val notificationId = intent.getIntExtra(EXTRA_NOTIFICATION_ID, -1)
            val title = intent.getStringExtra(EXTRA_NOTIFICATION_TITLE) ?: "Task Reminder"
            val message = intent.getStringExtra(EXTRA_NOTIFICATION_BODY) ?: "You have a scheduled task"
            
            // Extract task and event IDs - handle case where they might not be present
            val taskId = if (intent.hasExtra(EXTRA_TASK_ID)) {
                intent.getIntExtra(EXTRA_TASK_ID, -1).takeIf { it != -1 }
            } else null
            
            val eventId = if (intent.hasExtra(EXTRA_EVENT_ID)) {
                intent.getIntExtra(EXTRA_EVENT_ID, -1).takeIf { it != -1 }
            } else null
            
            Log.d(TAG, "Processing scheduled notification:")
            Log.d(TAG, "  - Notification ID: $notificationId")
            Log.d(TAG, "  - Title: '$title'")
            Log.d(TAG, "  - Task ID: $taskId")
            Log.d(TAG, "  - Event ID: $eventId")
            
            if (notificationId == -1) {
                Log.e(TAG, "Invalid notification ID: $notificationId")
                return
            }
            
            // Create and display the notification
            createNotificationChannel(context)
            showNotification(context, notificationId, title, message, taskId, eventId)
            
            // Log successful notification display
            try {
                DebugLogManager.logCustomEvent(
                    context, 
                    "SCHEDULED_NOTIFICATION_SHOWN", 
                    "Displayed scheduled notification: $title (ID: $notificationId, TaskID: $taskId)"
                )
            } catch (e: Exception) {
                Log.w(TAG, "Could not log notification display: ${e.message}")
            }
            
        } catch (e: Exception) {
            Log.e(TAG, "Error handling scheduled notification", e)
        }
    }
    
    /**
     * Create notification channel for scheduled reminders
     */
    private fun createNotificationChannel(context: Context) {
        try {
            val notificationManager = context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
            
            // Check if channel already exists
            val existingChannel = notificationManager.getNotificationChannel(NOTIFICATION_CHANNEL_ID)
            if (existingChannel != null) {
                return // Channel already exists
            }
            
            // Create new notification channel
            val channel = NotificationChannel(
                NOTIFICATION_CHANNEL_ID,
                NOTIFICATION_CHANNEL_NAME,
                NotificationManager.IMPORTANCE_HIGH
            ).apply {
                description = "Scheduled reminders for tasks and calendar events"
                enableLights(true)
                lightColor = Color.GREEN
                enableVibration(true)
                vibrationPattern = longArrayOf(0, 300, 100, 300)
                setShowBadge(true)
                lockscreenVisibility = android.app.Notification.VISIBILITY_PUBLIC
            }
            
            notificationManager.createNotificationChannel(channel)
            Log.d(TAG, "Created notification channel: $NOTIFICATION_CHANNEL_ID")
            
        } catch (e: Exception) {
            Log.e(TAG, "Error creating notification channel", e)
        }
    }
    
    /**
     * Display the scheduled notification with proper task navigation
     */
    private fun showNotification(
        context: Context, 
        notificationId: Int, 
        title: String, 
        message: String, 
        taskId: Int?,
        eventId: Int?
    ) {
        try {
            val notificationManager = context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
            
            // Create intent for when notification is tapped
            val tapIntent = Intent(context, MainActivity::class.java).apply {
                flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP
                
                // Only add task navigation data if we have a valid task ID
                if (taskId != null && taskId > 0) {
                    Log.d(TAG, "Adding task navigation: taskId=$taskId")
                    putExtra("openTaskDetail", true)
                    putExtra("taskId", taskId.toString()) // MainActivity expects String
                    putExtra("launchedFromNotification", true)
                    
                    // Add event ID if available
                    eventId?.let { 
                        putExtra("eventId", it.toString())
                        Log.d(TAG, "Adding event ID: $it")
                    }
                } else {
                    Log.w(TAG, "No valid task ID available for navigation (taskId=$taskId)")
                    // For notifications without tasks, just open main app
                    putExtra("launchedFromNotification", true)
                }
            }
            
            val pendingIntent = PendingIntent.getActivity(
                context,
                notificationId,
                tapIntent,
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
            )
            
            // Build the notification
            val notification = NotificationCompat.Builder(context, NOTIFICATION_CHANNEL_ID)
                .setContentTitle(title)
                .setContentText(message)
                .setSmallIcon(android.R.drawable.ic_popup_reminder) // Using system reminder icon
                .setContentIntent(pendingIntent)
                .setAutoCancel(true)
                .setPriority(NotificationCompat.PRIORITY_HIGH)
                .setCategory(NotificationCompat.CATEGORY_REMINDER)
                .setVisibility(NotificationCompat.VISIBILITY_PUBLIC)
                .setVibrate(longArrayOf(0, 300, 100, 300))
                .setLights(Color.GREEN, 1000, 500)
                .setWhen(System.currentTimeMillis())
                .setShowWhen(true)
                .setStyle(NotificationCompat.BigTextStyle().bigText(message))
                .build()
            
            // Show the notification
            notificationManager.notify(notificationId, notification)
            
            Log.d(TAG, "Notification displayed successfully: ID=$notificationId, TaskID=$taskId")
            
        } catch (e: Exception) {
            Log.e(TAG, "Error showing notification", e)
        }
    }
}