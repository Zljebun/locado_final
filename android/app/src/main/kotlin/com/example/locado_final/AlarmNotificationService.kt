package com.example.locado_final

import android.app.AlarmManager
import android.app.PendingIntent
import android.app.Service
import android.content.Context
import android.content.Intent
import android.os.IBinder
import android.util.Log
import java.util.*

class AlarmNotificationService : Service() {

    companion object {
        private const val TAG = "AlarmNotificationService"
        
        // Action types for different operations
        const val ACTION_SCHEDULE_ALARM = "com.example.locado_final.SCHEDULE_ALARM"
        const val ACTION_CANCEL_ALARM = "com.example.locado_final.CANCEL_ALARM"
        
        // Extra keys for intent data
        const val EXTRA_ALARM_ID = "alarm_id"
        const val EXTRA_TITLE = "title"
        const val EXTRA_BODY = "body"
        const val EXTRA_TIMESTAMP = "timestamp"
        const val EXTRA_TASK_ID = "task_id"
        const val EXTRA_EVENT_ID = "event_id"
        
        /**
         * Static method to schedule an alarm with task and event IDs for navigation
         * @param context Application context
         * @param alarmId Unique identifier for the alarm
         * @param title Notification title
         * @param body Notification body
         * @param timestampMillis When to trigger the alarm (in milliseconds since epoch)
         * @param taskId Task ID for navigation (nullable)
         * @param eventId Event ID for reference (nullable)
         */
        fun scheduleAlarm(
            context: Context, 
            alarmId: Int, 
            title: String, 
            body: String, 
            timestampMillis: Long,
            taskId: Int? = null,
            eventId: Int? = null
        ) {
            Log.d(TAG, "Scheduling alarm: ID=$alarmId, title=$title, time=$timestampMillis, taskId=$taskId, eventId=$eventId")
            
            val serviceIntent = Intent(context, AlarmNotificationService::class.java).apply {
                action = ACTION_SCHEDULE_ALARM
                putExtra(EXTRA_ALARM_ID, alarmId)
                putExtra(EXTRA_TITLE, title)
                putExtra(EXTRA_BODY, body)
                putExtra(EXTRA_TIMESTAMP, timestampMillis)
                
                // Add task and event IDs if provided
                taskId?.let { putExtra(EXTRA_TASK_ID, it) }
                eventId?.let { putExtra(EXTRA_EVENT_ID, it) }
            }
            
            context.startService(serviceIntent)
        }
        
        /**
         * Static method to cancel a scheduled alarm
         * @param context Application context
         * @param alarmId Unique identifier for the alarm to cancel
         */
        fun cancelAlarm(context: Context, alarmId: Int) {
            Log.d(TAG, "Canceling alarm: ID=$alarmId")
            
            val serviceIntent = Intent(context, AlarmNotificationService::class.java).apply {
                action = ACTION_CANCEL_ALARM
                putExtra(EXTRA_ALARM_ID, alarmId)
            }
            
            context.startService(serviceIntent)
        }
    }

    override fun onCreate() {
        super.onCreate()
        Log.d(TAG, "AlarmNotificationService created")
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        Log.d(TAG, "AlarmNotificationService started with action: ${intent?.action}")
        
        when (intent?.action) {
            ACTION_SCHEDULE_ALARM -> {
                handleScheduleAlarm(intent)
            }
            ACTION_CANCEL_ALARM -> {
                handleCancelAlarm(intent)
            }
            else -> {
                Log.w(TAG, "Unknown action: ${intent?.action}")
            }
        }
        
        // Stop the service after handling the request
        stopSelf(startId)
        
        return START_NOT_STICKY
    }

    override fun onBind(intent: Intent?): IBinder? {
        // This service doesn't support binding
        return null
    }

    /**
     * Handle scheduling a new alarm
     */
    private fun handleScheduleAlarm(intent: Intent) {
        try {
            val alarmId = intent.getIntExtra(EXTRA_ALARM_ID, -1)
            val title = intent.getStringExtra(EXTRA_TITLE) ?: ""
            val body = intent.getStringExtra(EXTRA_BODY) ?: ""
            val timestampMillis = intent.getLongExtra(EXTRA_TIMESTAMP, 0L)
            
            // Extract task and event IDs (may be null)
            val taskId = if (intent.hasExtra(EXTRA_TASK_ID)) {
                intent.getIntExtra(EXTRA_TASK_ID, -1)
            } else null
            
            val eventId = if (intent.hasExtra(EXTRA_EVENT_ID)) {
                intent.getIntExtra(EXTRA_EVENT_ID, -1)
            } else null
            
            Log.d(TAG, "Processing schedule request: alarmId=$alarmId, taskId=$taskId, eventId=$eventId")
            
            if (alarmId == -1 || timestampMillis == 0L) {
                Log.e(TAG, "Invalid alarm parameters: ID=$alarmId, timestamp=$timestampMillis")
                return
            }
            
            val currentTime = System.currentTimeMillis()
            if (timestampMillis <= currentTime) {
                Log.w(TAG, "Alarm time is in the past: $timestampMillis vs current $currentTime")
                return
            }
            
            scheduleAlarmWithManager(alarmId, title, body, timestampMillis, taskId, eventId)
            
            Log.i(TAG, "Successfully scheduled alarm: ID=$alarmId for ${Date(timestampMillis)} with taskId=$taskId, eventId=$eventId")
            
        } catch (e: Exception) {
            Log.e(TAG, "Error scheduling alarm", e)
        }
    }

    /**
     * Handle canceling an existing alarm
     */
    private fun handleCancelAlarm(intent: Intent) {
        try {
            val alarmId = intent.getIntExtra(EXTRA_ALARM_ID, -1)
            
            if (alarmId == -1) {
                Log.e(TAG, "Invalid alarm ID for cancellation: $alarmId")
                return
            }
            
            cancelAlarmWithManager(alarmId)
            
            Log.i(TAG, "Successfully canceled alarm: ID=$alarmId")
            
        } catch (e: Exception) {
            Log.e(TAG, "Error canceling alarm", e)
        }
    }

    /**
     * Use AlarmManager to schedule the actual alarm with task and event IDs
     */
    private fun scheduleAlarmWithManager(
        alarmId: Int, 
        title: String, 
        body: String, 
        timestampMillis: Long, 
        taskId: Int?, 
        eventId: Int?
    ) {
        val alarmManager = getSystemService(Context.ALARM_SERVICE) as AlarmManager
        
        // Create intent for AlarmReceiver with all navigation data
        val alarmIntent = Intent(this, AlarmReceiver::class.java).apply {
            action = "com.example.locado_final.SCHEDULED_NOTIFICATION"
            putExtra("notificationId", alarmId)
            putExtra("title", title)
            putExtra("message", body)
            
            // Add task and event IDs for navigation
            taskId?.let { 
                putExtra("taskId", it)
                Log.d(TAG, "Adding taskId=$it to alarm intent")
            }
            eventId?.let { 
                putExtra("eventId", it)
                Log.d(TAG, "Adding eventId=$it to alarm intent")
            }
        }
        
        // Create PendingIntent
        val pendingIntent = PendingIntent.getBroadcast(
            this,
            alarmId,
            alarmIntent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )
        
        // Schedule the alarm
        try {
            // Use setExactAndAllowWhileIdle for precise timing even in doze mode
            alarmManager.setExactAndAllowWhileIdle(
                AlarmManager.RTC_WAKEUP,
                timestampMillis,
                pendingIntent
            )
            
            Log.d(TAG, "Alarm scheduled with AlarmManager: ID=$alarmId, taskId=$taskId, eventId=$eventId")
            
        } catch (e: SecurityException) {
            Log.e(TAG, "Permission denied for exact alarms", e)
            // Fallback to inexact alarm
            alarmManager.set(
                AlarmManager.RTC_WAKEUP,
                timestampMillis,
                pendingIntent
            )
            Log.w(TAG, "Fallback to inexact alarm: ID=$alarmId, taskId=$taskId, eventId=$eventId")
        }
    }

    /**
     * Cancel an alarm using AlarmManager
     */
    private fun cancelAlarmWithManager(alarmId: Int) {
        val alarmManager = getSystemService(Context.ALARM_SERVICE) as AlarmManager
        
        // Create the same intent used for scheduling
        val alarmIntent = Intent(this, AlarmReceiver::class.java).apply {
            action = "com.example.locado_final.SCHEDULED_NOTIFICATION"
        }
        
        // Create PendingIntent with same parameters as when scheduling
        val pendingIntent = PendingIntent.getBroadcast(
            this,
            alarmId,
            alarmIntent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )
        
        // Cancel the alarm
        alarmManager.cancel(pendingIntent)
        
        // Cancel the PendingIntent as well
        pendingIntent.cancel()
        
        Log.d(TAG, "Alarm canceled with AlarmManager: ID=$alarmId")
    }

    override fun onDestroy() {
        super.onDestroy()
        Log.d(TAG, "AlarmNotificationService destroyed")
    }
}