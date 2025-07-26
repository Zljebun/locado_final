package com.example.locado_final

import android.content.Context
import android.util.Log
import java.io.File
import java.io.FileWriter
import java.io.IOException
import java.text.SimpleDateFormat
import java.util.*
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch

object DebugLogManager {
    private const val TAG = "DebugLogManager"
    private const val LOG_FILE_NAME = "locado_debug_log.txt"
    private const val MAX_LOG_SIZE = 5 * 1024 * 1024 // 5MB max

    private val dateFormat = SimpleDateFormat("yyyy-MM-dd HH:mm:ss.SSS", Locale.getDefault())
    private var isEnabled = true

    /**
     * 🚀 ZAPISUJE KLJUČNE GEOFENCE EVENTI
     */
    fun logGeofenceEvent(context: Context, event: String, details: String = "") {
        if (!isEnabled) return

        CoroutineScope(Dispatchers.IO).launch {
            try {
                val timestamp = dateFormat.format(Date())
                val logMessage = "[$timestamp] GEOFENCE: $event | $details"

                writeToFile(context, logMessage)
                Log.d(TAG, "📝 Logged: $event")

            } catch (e: Exception) {
                Log.e(TAG, "❌ Failed to log geofence event: ${e.message}")
            }
        }
    }

    /**
     * 🚀 ZAPISUJE SERVICE EVENTI
     */
    fun logServiceEvent(context: Context, event: String, details: String = "") {
        if (!isEnabled) return

        CoroutineScope(Dispatchers.IO).launch {
            try {
                val timestamp = dateFormat.format(Date())
                val logMessage = "[$timestamp] SERVICE: $event | $details"

                writeToFile(context, logMessage)
                Log.d(TAG, "📝 Service logged: $event")

            } catch (e: Exception) {
                Log.e(TAG, "❌ Failed to log service event: ${e.message}")
            }
        }
    }

    /**
     * 🚀 ZAPISUJE NOTIFICATION EVENTI
     */
    fun logNotificationEvent(context: Context, event: String, details: String = "") {
        if (!isEnabled) return

        CoroutineScope(Dispatchers.IO).launch {
            try {
                val timestamp = dateFormat.format(Date())
                val logMessage = "[$timestamp] NOTIFICATION: $event | $details"

                writeToFile(context, logMessage)
                Log.d(TAG, "📝 Notification logged: $event")

            } catch (e: Exception) {
                Log.e(TAG, "❌ Failed to log notification event: ${e.message}")
            }
        }
    }

    /**
     * 🚀 ZAPISUJE SCREEN EVENTI
     */
    fun logScreenEvent(context: Context, event: String, details: String = "") {
        if (!isEnabled) return

        CoroutineScope(Dispatchers.IO).launch {
            try {
                val timestamp = dateFormat.format(Date())
                val logMessage = "[$timestamp] SCREEN: $event | $details"

                writeToFile(context, logMessage)
                Log.d(TAG, "📝 Screen logged: $event")

            } catch (e: Exception) {
                Log.e(TAG, "❌ Failed to log screen event: ${e.message}")
            }
        }
    }

    /**
     * 🚀 ZAPISUJE BOOT/RESTART EVENTI
     */
    fun logBootEvent(context: Context, event: String, details: String = "") {
        if (!isEnabled) return

        CoroutineScope(Dispatchers.IO).launch {
            try {
                val timestamp = dateFormat.format(Date())
                val logMessage = "[$timestamp] BOOT: $event | $details"

                writeToFile(context, logMessage)
                Log.d(TAG, "📝 Boot logged: $event")

            } catch (e: Exception) {
                Log.e(TAG, "❌ Failed to log boot event: ${e.message}")
            }
        }
    }

    /**
     * 🚀 ZAPISUJE SISTEM STATUS
     */
    fun logSystemStatus(context: Context, activeGeofences: Int, serviceRunning: Boolean) {
        if (!isEnabled) return

        CoroutineScope(Dispatchers.IO).launch {
            try {
                val timestamp = dateFormat.format(Date())
                val status = "Geofences: $activeGeofences | Service: $serviceRunning"
                val logMessage = "[$timestamp] STATUS: $status"

                writeToFile(context, logMessage)
                Log.d(TAG, "📝 Status logged: $status")

            } catch (e: Exception) {
                Log.e(TAG, "❌ Failed to log system status: ${e.message}")
            }
        }
    }

    /**
     * 🚀 ZAPISUJE CUSTOM EVENTI
     */
    fun logCustomEvent(context: Context, category: String, event: String, details: String = "") {
        if (!isEnabled) return

        CoroutineScope(Dispatchers.IO).launch {
            try {
                val timestamp = dateFormat.format(Date())
                val logMessage = "[$timestamp] $category: $event | $details"

                writeToFile(context, logMessage)
                Log.d(TAG, "📝 Custom logged: $category - $event")

            } catch (e: Exception) {
                Log.e(TAG, "❌ Failed to log custom event: ${e.message}")
            }
        }
    }

    /**
     * 🚀 KREIRANJE SESSION SEPARATOR
     */
    fun startNewSession(context: Context) {
        CoroutineScope(Dispatchers.IO).launch {
            try {
                val timestamp = dateFormat.format(Date())
                val separator = "\n" + "=".repeat(80) + "\n"
                val sessionStart = "[$timestamp] 🚀 NEW SESSION STARTED - ${android.os.Build.MODEL}\n" + "=".repeat(80) + "\n"

                writeToFile(context, separator + sessionStart)
                Log.d(TAG, "📝 New session started")

            } catch (e: Exception) {
                Log.e(TAG, "❌ Failed to start new session: ${e.message}")
            }
        }
    }

    /**
     * 🚀 PISANJE U FAJL
     */
    private fun writeToFile(context: Context, message: String) {
        try {
            val logFile = getLogFile(context)

            // Proveri veličinu fajla i rotraj ako je potrebno
            if (logFile.exists() && logFile.length() > MAX_LOG_SIZE) {
                rotateLogFile(context)
            }

            // Dodaj u fajl
            FileWriter(logFile, true).use { writer ->
                writer.appendLine(message)
                writer.flush()
            }

        } catch (e: IOException) {
            Log.e(TAG, "❌ Failed to write to log file: ${e.message}")
        }
    }

    /**
     * 🚀 DOBIJANJE LOG FAJLA
     */
    private fun getLogFile(context: Context): File {
        val logsDir = File(context.getExternalFilesDir(null), "logs")
        if (!logsDir.exists()) {
            logsDir.mkdirs()
        }
        return File(logsDir, LOG_FILE_NAME)
    }

    /**
     * 🚀 ROTACIJA LOG FAJLA (kada postane prevelik)
     */
    private fun rotateLogFile(context: Context) {
        try {
            val currentLog = getLogFile(context)
            val backupLog = File(currentLog.parent, "locado_debug_log_backup.txt")

            // Obriši stari backup
            if (backupLog.exists()) {
                backupLog.delete()
            }

            // Preimenuj trenutni u backup
            currentLog.renameTo(backupLog)

            Log.d(TAG, "📝 Log file rotated")

        } catch (e: Exception) {
            Log.e(TAG, "❌ Failed to rotate log file: ${e.message}")
        }
    }

    /**
     * 🚀 ČITANJE LOG FAJLA (za deljenje)
     */
    fun getLogFileContent(context: Context): String {
        return try {
            val logFile = getLogFile(context)
            if (logFile.exists()) {
                logFile.readText()
            } else {
                "No log file found"
            }
        } catch (e: Exception) {
            "Error reading log file: ${e.message}"
        }
    }

    /**
     * 🚀 DOBIJANJE LOG FAJL PATH-a
     */
    fun getLogFilePath(context: Context): String {
        return getLogFile(context).absolutePath
    }

    /**
     * 🚀 ČIŠĆENJE LOGOVA
     */
    fun clearLogs(context: Context) {
        CoroutineScope(Dispatchers.IO).launch {
            try {
                val logFile = getLogFile(context)
                val backupLog = File(logFile.parent, "locado_debug_log_backup.txt")

                logFile.delete()
                backupLog.delete()

                Log.d(TAG, "📝 Logs cleared")

            } catch (e: Exception) {
                Log.e(TAG, "❌ Failed to clear logs: ${e.message}")
            }
        }
    }

    /**
     * 🚀 ENABLE/DISABLE LOGGING
     */
    fun setLoggingEnabled(enabled: Boolean) {
        isEnabled = enabled
        Log.d(TAG, "📝 Logging ${if (enabled) "enabled" else "disabled"}")
    }

    /**
     * 🚀 SUMMARY REPORT
     */
    fun generateSummaryReport(context: Context): String {
        return try {
            val logFile = getLogFile(context)
            if (!logFile.exists()) {
                return "No logs available"
            }

            val content = logFile.readText()
            val lines = content.split('\n')

            val geofenceEvents = lines.count { it.contains("GEOFENCE:") }
            val serviceEvents = lines.count { it.contains("SERVICE:") }
            val notificationEvents = lines.count { it.contains("NOTIFICATION:") }
            val bootEvents = lines.count { it.contains("BOOT:") }

            val summary = """
                📊 LOCADO DEBUG SUMMARY
                ========================
                Total log lines: ${lines.size}
                Geofence events: $geofenceEvents
                Service events: $serviceEvents  
                Notification events: $notificationEvents
                Boot events: $bootEvents
                
                Log file size: ${logFile.length() / 1024} KB
                Log file path: ${logFile.absolutePath}
                
                Last 10 events:
                ${lines.takeLast(10).joinToString("\n")}
            """.trimIndent()

            summary

        } catch (e: Exception) {
            "Error generating summary: ${e.message}"
        }
    }
}