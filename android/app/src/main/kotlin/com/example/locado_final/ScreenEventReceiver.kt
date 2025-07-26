package com.example.locado_final

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.util.Log
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import kotlinx.coroutines.delay

class ScreenEventReceiver : BroadcastReceiver() {

    companion object {
        private const val TAG = "ScreenEventReceiver"
        private var lastScreenOnTime = 0L
        private val SCREEN_ON_DEBOUNCE_MS = 5000L // 5 sekundi debounce
    }

    override fun onReceive(context: Context, intent: Intent) {
        val currentTime = System.currentTimeMillis()

        when (intent.action) {
            Intent.ACTION_SCREEN_ON -> {
                Log.d(TAG, "📱 SCREEN ON detected at ${java.text.SimpleDateFormat("HH:mm:ss").format(java.util.Date())}")
                handleScreenOn(context, currentTime)
            }

            Intent.ACTION_SCREEN_OFF -> {
                Log.d(TAG, "🌙 SCREEN OFF detected at ${java.text.SimpleDateFormat("HH:mm:ss").format(java.util.Date())}")
                handleScreenOff(context)
            }

            Intent.ACTION_USER_PRESENT -> {
                Log.d(TAG, "🔓 USER PRESENT (unlocked) detected at ${java.text.SimpleDateFormat("HH:mm:ss").format(java.util.Date())}")
                handleUserPresent(context, currentTime)
            }
        }
    }

    private fun handleScreenOn(context: Context, currentTime: Long) {
        // Debounce screen on events (izbegni spam)
        if (currentTime - lastScreenOnTime < SCREEN_ON_DEBOUNCE_MS) {
            Log.d(TAG, "⏰ Screen ON event ignored (debounce)")
            return
        }
        lastScreenOnTime = currentTime

        // Asinkrono izvršavanje da ne blokira UI
        CoroutineScope(Dispatchers.IO).launch {
            try {
                // 1. Proveri status geofencing service-a
                checkAndRefreshGeofencingService(context)

                // 2. Opciono: test notification da vidimo da li rade
                // testNotificationSystem(context)

            } catch (e: Exception) {
                Log.e(TAG, "❌ Error in handleScreenOn: ${e.message}")
            }
        }
    }

    private fun handleScreenOff(context: Context) {
        // Screen off - ne radimo ništa posebno, samo logujemo
        Log.d(TAG, "📱 Device screen turned off - geofencing continues in background")
    }

    private fun handleUserPresent(context: Context, currentTime: Long) {
        // User je otključao telefon - ovo je idealno vreme za refresh

        // Debounce user present events
        if (currentTime - lastScreenOnTime < SCREEN_ON_DEBOUNCE_MS) {
            Log.d(TAG, "⏰ User present event ignored (debounce)")
            return
        }
        lastScreenOnTime = currentTime

        // Asinkrono izvršavanje
        CoroutineScope(Dispatchers.IO).launch {
            try {
                // Mala pauza da se sistem stabilizuje nakon unlock-a
                delay(2000)

                // 1. Proveri i refresh geofencing sistem
                checkAndRefreshGeofencingService(context)

                // 2. Provi geofence status i re-sync ako je potrebno
                refreshGeofenceRegistrations(context)

                Log.d(TAG, "✅ User present refresh completed")

            } catch (e: Exception) {
                Log.e(TAG, "❌ Error in handleUserPresent: ${e.message}")
            }
        }
    }

    private suspend fun checkAndRefreshGeofencingService(context: Context) {
        try {
            Log.d(TAG, "🔄 Checking geofencing service status...")

            // Proveri da li je LocadoForegroundService aktivan
            val serviceIntent = Intent(context, LocadoForegroundService::class.java)

            if (!LocadoForegroundService.isRunning()) {
                Log.w(TAG, "⚠️ Geofencing service not running - attempting restart")

                // Pokušaj restart service-a
                serviceIntent.action = LocadoForegroundService.ACTION_START_SERVICE
                context.startForegroundService(serviceIntent)

                // Čekaj da se service pokrene
                delay(3000)

                if (LocadoForegroundService.isRunning()) {
                    Log.d(TAG, "✅ Geofencing service restarted successfully")
                } else {
                    Log.e(TAG, "❌ Failed to restart geofencing service")
                }
            } else {
                Log.d(TAG, "✅ Geofencing service is running")

                // Service radi - refresh notification
                serviceIntent.action = LocadoForegroundService.ACTION_UPDATE_NOTIFICATION
                serviceIntent.putExtra("geofence_count", LocadoForegroundService.getActiveGeofenceCount())
                context.startService(serviceIntent)
            }

        } catch (e: Exception) {
            Log.e(TAG, "❌ Error checking geofencing service: ${e.message}")
        }
    }

    private suspend fun refreshGeofenceRegistrations(context: Context) {
        try {
            Log.d(TAG, "🔄 Refreshing geofence registrations...")

            // Koristi BootReceiver logiku za re-registraciju
            val bootReceiver = BootReceiver()
            bootReceiver.reRegisterAllGeofencesPublic(context)

            Log.d(TAG, "✅ Geofence refresh completed")

        } catch (e: Exception) {
            Log.e(TAG, "❌ Error refreshing geofences: ${e.message}")
        }
    }

    /**
     * Test notification sistem - koristi za debug
     * (trenutno isključeno, ali možeš uključiti za testiranje)
     */
    private suspend fun testNotificationSystem(context: Context) {
        try {
            Log.d(TAG, "🧪 Testing notification system...")

            // Kreiraj test GeofenceBroadcastReceiver
            val testReceiver = GeofenceBroadcastReceiver()

            // Simuliraj test geofence event
            // testReceiver.showTestNotification(context, "Test Notification", "Screen ON test")

            Log.d(TAG, "✅ Notification test completed")

        } catch (e: Exception) {
            Log.e(TAG, "❌ Error testing notifications: ${e.message}")
        }
    }

    /**
     * Log sistem info za debug
     */
    private fun logSystemInfo(context: Context) {
        try {
            val currentTime = java.text.SimpleDateFormat("HH:mm:ss.SSS").format(java.util.Date())
            Log.d(TAG, "=== SCREEN EVENT SYSTEM INFO ===")
            Log.d(TAG, "Time: $currentTime")
            Log.d(TAG, "Service Running: ${LocadoForegroundService.isRunning()}")
            Log.d(TAG, "Active Geofences: ${LocadoForegroundService.getActiveGeofenceCount()}")
            Log.d(TAG, "================================")
        } catch (e: Exception) {
            Log.e(TAG, "❌ Error logging system info: ${e.message}")
        }
    }

    /**
     * Emergency geofence recovery - koristi u ekstremnim slučajevima
     */
    private fun performEmergencyGeofenceRecovery(context: Context) {
        try {
            Log.w(TAG, "🚨 EMERGENCY: Performing geofence recovery")

            // 1. Force restart service
            val serviceIntent = Intent(context, LocadoForegroundService::class.java)
            serviceIntent.action = LocadoForegroundService.ACTION_STOP_SERVICE
            context.startService(serviceIntent)

            // Kratka pauza
            Thread.sleep(1000)

            // 2. Restart service
            serviceIntent.action = LocadoForegroundService.ACTION_START_SERVICE
            context.startForegroundService(serviceIntent)

            // 3. Re-register geofences
            CoroutineScope(Dispatchers.IO).launch {
                delay(5000) // Čekaj da se service stabilizuje

                val bootReceiver = BootReceiver()
                bootReceiver.reRegisterAllGeofencesPublic(context)

                Log.w(TAG, "🚨 Emergency recovery completed")
            }

        } catch (e: Exception) {
            Log.e(TAG, "❌ Emergency recovery failed: ${e.message}")
        }
    }
}

/**
 * Extension za BootReceiver da omogući public pristup
 */
private fun BootReceiver.reRegisterAllGeofencesPublic(context: Context) {
    try {
        // Pozovi postojeću logiku iz BootReceiver-a
        this.registerPersistentGeofencesPublic(context, emptyList())
    } catch (e: Exception) {
        Log.e("ScreenEventReceiver", "❌ Error calling BootReceiver: ${e.message}")
    }
}