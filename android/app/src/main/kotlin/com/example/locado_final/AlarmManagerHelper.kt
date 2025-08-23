package com.example.locado_final

import android.content.Context
import android.util.Log
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.MethodChannel.MethodCallHandler
import io.flutter.plugin.common.MethodChannel.Result
import java.text.SimpleDateFormat
import java.util.*

class AlarmManagerHelper(private val context: Context) : MethodCallHandler {

    companion object {
        private const val TAG = "AlarmManagerHelper"
        const val CHANNEL_NAME = "com.example.locado_final/alarm_manager"
        
        // Method names that Flutter can call
        const val METHOD_SCHEDULE_NOTIFICATION = "scheduleNotification"
        const val METHOD_CANCEL_NOTIFICATION = "cancelNotification"
        const val METHOD_CANCEL_ALL_NOTIFICATIONS = "cancelAllNotifications"
        const val METHOD_GET_SCHEDULED_NOTIFICATIONS = "getScheduledNotifications"
        
        // For debugging - simple date formatter
        private val dateFormatter = SimpleDateFormat("yyyy-MM-dd HH:mm:ss", Locale.getDefault())
    }

    override fun onMethodCall(call: MethodCall, result: Result) {
        Log.d(TAG, "Method called: ${call.method}")
        
        try {
            when (call.method) {
                METHOD_SCHEDULE_NOTIFICATION -> {
                    handleScheduleNotification(call, result)
                }
                METHOD_CANCEL_NOTIFICATION -> {
                    handleCancelNotification(call, result)
                }
                METHOD_CANCEL_ALL_NOTIFICATIONS -> {
                    handleCancelAllNotifications(call, result)
                }
                METHOD_GET_SCHEDULED_NOTIFICATIONS -> {
                    handleGetScheduledNotifications(call, result)
                }
                else -> {
                    Log.w(TAG, "Unknown method: ${call.method}")
                    result.notImplemented()
                }
            }
        } catch (e: Exception) {
            Log.e(TAG, "Error handling method call: ${call.method}", e)
            result.error("NATIVE_ERROR", "Failed to execute ${call.method}: ${e.message}", null)
        }
    }

    /**
     * Schedule a new notification
     * Expected parameters from Flutter:
     * - id: Int (notification ID)
     * - title: String
     * - body: String
     * - timestamp: Long (milliseconds since epoch)
     * - taskId: Int (optional - for navigation to task)
     * - eventId: Int (optional - for event reference)
     */
    private fun handleScheduleNotification(call: MethodCall, result: Result) {
        try {
            // Extract basic parameters
            val id = call.argument<Int>("id")
            val title = call.argument<String>("title")
            val body = call.argument<String>("body")
            
            if (id == null || title == null || body == null) {
                result.error("INVALID_PARAMETERS", "Missing required parameters: id, title, or body", null)
                return
            }

            // Extract task and event IDs for navigation
            val taskId = call.argument<Int>("taskId")
            val eventId = call.argument<Int>("eventId")
            
            Log.d(TAG, "Scheduling notification: ID=$id, TaskID=$taskId, EventID=$eventId")

            // Get timestamp - try multiple formats for flexibility
            val timestampMillis = when {
                call.hasArgument("timestamp") -> {
                    call.argument<Long>("timestamp")
                }
                call.hasArgument("scheduledDate") -> {
                    val dateString = call.argument<String>("scheduledDate")
                    parseIsoDateString(dateString)
                }
                else -> null
            }

            if (timestampMillis == null || timestampMillis <= 0) {
                result.error("INVALID_TIMESTAMP", "Invalid or missing timestamp/scheduledDate", null)
                return
            }

            // Validate timestamp is in the future
            val currentTime = System.currentTimeMillis()
            if (timestampMillis <= currentTime) {
                val scheduledTime = dateFormatter.format(Date(timestampMillis))
                val currentTimeStr = dateFormatter.format(Date(currentTime))
                result.error("PAST_TIMESTAMP", 
                    "Scheduled time ($scheduledTime) is in the past. Current time: $currentTimeStr", null)
                return
            }

            // Schedule the alarm with task and event IDs
            AlarmNotificationService.scheduleAlarm(
                context = context,
                alarmId = id,
                title = title,
                body = body,
                timestampMillis = timestampMillis,
                taskId = taskId,
                eventId = eventId
            )
            
            val scheduledTimeStr = dateFormatter.format(Date(timestampMillis))
            Log.i(TAG, "Successfully scheduled notification: ID=$id, title='$title', time=$scheduledTimeStr, taskId=$taskId, eventId=$eventId")
            
            // Return success with scheduled time info
            val responseMap = mapOf(
                "success" to true,
                "id" to id,
                "scheduledTime" to scheduledTimeStr,
                "timestamp" to timestampMillis,
                "taskId" to taskId,
                "eventId" to eventId
            )
            
            result.success(responseMap)
            
        } catch (e: Exception) {
            Log.e(TAG, "Error in handleScheduleNotification", e)
            result.error("SCHEDULE_ERROR", "Failed to schedule notification: ${e.message}", null)
        }
    }

    /**
     * Cancel a specific notification
     * Expected parameters:
     * - id: Int
     */
    private fun handleCancelNotification(call: MethodCall, result: Result) {
        try {
            val id = call.argument<Int>("id")
            
            if (id == null) {
                result.error("INVALID_PARAMETERS", "Missing required parameter: id", null)
                return
            }

            // Cancel the alarm
            AlarmNotificationService.cancelAlarm(context, id)
            
            Log.i(TAG, "Successfully canceled notification: ID=$id")
            
            val responseMap = mapOf(
                "success" to true,
                "id" to id
            )
            
            result.success(responseMap)
            
        } catch (e: Exception) {
            Log.e(TAG, "Error in handleCancelNotification", e)
            result.error("CANCEL_ERROR", "Failed to cancel notification: ${e.message}", null)
        }
    }

    /**
     * Cancel all scheduled notifications
     * This is a simplified implementation - in a real app you might want to track all IDs
     */
    private fun handleCancelAllNotifications(call: MethodCall, result: Result) {
        try {
            // For now, we'll return a success response
            // In a production app, you might want to maintain a list of active alarm IDs
            // and cancel them all individually
            
            Log.i(TAG, "Cancel all notifications requested")
            
            val responseMap = mapOf(
                "success" to true,
                "message" to "Cancel all notifications requested - individual cancellations needed for complete removal"
            )
            
            result.success(responseMap)
            
        } catch (e: Exception) {
            Log.e(TAG, "Error in handleCancelAllNotifications", e)
            result.error("CANCEL_ALL_ERROR", "Failed to cancel all notifications: ${e.message}", null)
        }
    }

    /**
     * Get list of scheduled notifications
     * This is a placeholder - AlarmManager doesn't provide direct querying capabilities
     */
    private fun handleGetScheduledNotifications(call: MethodCall, result: Result) {
        try {
            // AlarmManager doesn't provide a way to query scheduled alarms
            // You would need to maintain your own database/storage for this functionality
            
            Log.i(TAG, "Get scheduled notifications requested")
            
            val responseMap = mapOf(
                "success" to true,
                "notifications" to emptyList<Map<String, Any>>(),
                "message" to "Querying scheduled alarms requires additional storage implementation"
            )
            
            result.success(responseMap)
            
        } catch (e: Exception) {
            Log.e(TAG, "Error in handleGetScheduledNotifications", e)
            result.error("QUERY_ERROR", "Failed to get scheduled notifications: ${e.message}", null)
        }
    }

    /**
     * Parse ISO 8601 date string to timestamp
     * Handles formats like: "2024-03-15T14:30:00Z" or "2024-03-15T14:30:00"
     */
    private fun parseIsoDateString(dateString: String?): Long? {
        if (dateString == null) return null
        
        return try {
            // Try different ISO 8601 formats
            val formats = arrayOf(
                SimpleDateFormat("yyyy-MM-dd'T'HH:mm:ss'Z'", Locale.getDefault()),
                SimpleDateFormat("yyyy-MM-dd'T'HH:mm:ss", Locale.getDefault()),
                SimpleDateFormat("yyyy-MM-dd HH:mm:ss", Locale.getDefault()),
                SimpleDateFormat("yyyy-MM-dd'T'HH:mm:ss.SSS'Z'", Locale.getDefault()),
                SimpleDateFormat("yyyy-MM-dd'T'HH:mm:ss.SSS", Locale.getDefault())
            )
            
            for (format in formats) {
                try {
                    // Set UTC timezone for 'Z' suffix formats
                    if (format.toPattern().contains("'Z'")) {
                        format.timeZone = TimeZone.getTimeZone("UTC")
                    }
                    
                    val date = format.parse(dateString)
                    if (date != null) {
                        Log.d(TAG, "Parsed date '$dateString' to ${dateFormatter.format(date)}")
                        return date.time
                    }
                } catch (e: Exception) {
                    // Try next format
                    continue
                }
            }
            
            // If all else fails, try parsing as timestamp
            dateString.toLongOrNull()
            
        } catch (e: Exception) {
            Log.e(TAG, "Failed to parse date string: $dateString", e)
            null
        }
    }

    /**
     * Utility method to register this handler with Flutter
     */
    fun registerWith(methodChannel: MethodChannel) {
        methodChannel.setMethodCallHandler(this)
        Log.d(TAG, "AlarmManagerHelper registered with MethodChannel: $CHANNEL_NAME")
    }
}