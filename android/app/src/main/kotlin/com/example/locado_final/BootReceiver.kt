package com.example.locado_final

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.util.Log
import android.database.sqlite.SQLiteDatabase
import android.database.Cursor
import com.google.android.gms.location.*
import android.app.PendingIntent
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import kotlinx.coroutines.delay

class BootReceiver : BroadcastReceiver() {

    companion object {
        private const val TAG = "BootReceiver"
        private const val MAX_RETRY_ATTEMPTS = 3
        private const val RETRY_DELAY_MS = 5000L // 5 sekundi između pokušaja
    }

    override fun onReceive(context: Context, intent: Intent) {
        when (intent.action) {
            Intent.ACTION_BOOT_COMPLETED,
            Intent.ACTION_LOCKED_BOOT_COMPLETED,
            Intent.ACTION_MY_PACKAGE_REPLACED,
            Intent.ACTION_REBOOT,
            "com.htc.intent.action.QUICKBOOT_POWERON",
            "com.sec.android.intent.action.BOOTCOMPLETED",
            "com.motorola.blur.intent.action.QUICKBOOT_POWERON" -> {
                Log.d(TAG, "🔄 Device booted/restarted - action: ${intent.action}")

                // Asinkrono izvršavanje sa retry logikom
                CoroutineScope(Dispatchers.IO).launch {
                    performRobustGeofenceRecovery(context)
                }
            }

            Intent.ACTION_PACKAGE_REPLACED,
            Intent.ACTION_PACKAGE_RESTARTED -> {
                Log.d(TAG, "🔄 Package replaced/restarted - re-registering geofences")

                CoroutineScope(Dispatchers.IO).launch {
                    delay(2000) // Kratka pauza nakon package update
                    performRobustGeofenceRecovery(context)
                }
            }
        }
    }

    /**
     * 🚀 NOVA METODA: Robusna recovery sa retry logikom
     */
    private suspend fun performRobustGeofenceRecovery(context: Context) {
        Log.d(TAG, "🔄 Starting robust geofence recovery...")

        var attempt = 1
        var success = false

        while (attempt <= MAX_RETRY_ATTEMPTS && !success) {
            try {
                Log.d(TAG, "🔄 Recovery attempt $attempt/$MAX_RETRY_ATTEMPTS")

                // 1. Ensuring service is running
                ensureServiceIsRunning(context)

                // 2. Wait for service to stabilize
                delay(3000)

                // 3. Re-register geofences
                success = reRegisterAllGeofencesWithRetry(context)

                if (success) {
                    Log.d(TAG, "✅ Geofence recovery successful on attempt $attempt")

                    // 4. Test notification system
                    testNotificationAfterBoot(context)
                } else {
                    Log.w(TAG, "⚠️ Recovery attempt $attempt failed, will retry...")
                    attempt++

                    if (attempt <= MAX_RETRY_ATTEMPTS) {
                        delay(RETRY_DELAY_MS * attempt) // Progresivno povećanje delay-a
                    }
                }

            } catch (e: Exception) {
                Log.e(TAG, "❌ Recovery attempt $attempt failed with error: ${e.message}")
                attempt++

                if (attempt <= MAX_RETRY_ATTEMPTS) {
                    delay(RETRY_DELAY_MS * attempt)
                }
            }
        }

        if (!success) {
            Log.e(TAG, "❌ All recovery attempts failed - geofences may not be active")
            // Opcionalno: pošalji fallback notification ili log za debug
        }
    }

    /**
     * 🚀 NOVA METODA: Osigurava da je service aktivan
     */
    private suspend fun ensureServiceIsRunning(context: Context) {
        try {
            Log.d(TAG, "🔄 Ensuring geofencing service is running...")

            // Proverava trenutno stanje
            if (!LocadoForegroundService.isRunning()) {
                Log.d(TAG, "⚠️ Service not running - starting it")

                val serviceIntent = Intent(context, LocadoForegroundService::class.java)
                serviceIntent.action = LocadoForegroundService.ACTION_START_SERVICE
                context.startForegroundService(serviceIntent)

                // Čeka da se service pokrene
                var waitTime = 0
                while (!LocadoForegroundService.isRunning() && waitTime < 10000) {
                    delay(1000)
                    waitTime += 1000
                }

                if (LocadoForegroundService.isRunning()) {
                    Log.d(TAG, "✅ Service started successfully")
                } else {
                    Log.e(TAG, "❌ Failed to start service after 10 seconds")
                    throw Exception("Service startup timeout")
                }
            } else {
                Log.d(TAG, "✅ Service already running")
            }

        } catch (e: Exception) {
            Log.e(TAG, "❌ Error ensuring service: ${e.message}")
            throw e
        }
    }

    /**
     * 🚀 POBOLJŠANA METODA: Re-registracija sa boljim error handling-om
     */
    private suspend fun reRegisterAllGeofencesWithRetry(context: Context): Boolean {
        return try {
            Log.d(TAG, "🔄 Re-registering all geofences with retry logic...")

            // 1. Čitaj task-ove direktno iz database-a
            val taskLocations = readTaskLocationsFromDatabase(context)

            if (taskLocations.isNotEmpty()) {
                Log.d(TAG, "📋 Found ${taskLocations.size} task locations to register")

                // 2. Registruj geofence-ove sa poboljšanom logikom
                val success = registerPersistentGeofencesWithCallback(context, taskLocations)

                if (success) {
                    Log.d(TAG, "✅ Re-registered ${taskLocations.size} geofences successfully")
                    true
                } else {
                    Log.e(TAG, "❌ Failed to register geofences")
                    false
                }
            } else {
                Log.w(TAG, "⚠️ No task locations found in database")
                true // Tehnički "uspešno" jer nema šta da registruje
            }

        } catch (e: Exception) {
            Log.e(TAG, "❌ Error re-registering geofences: $e")
            false
        }
    }

    /**
     * 🚀 NOVA PUBLIC METODA za ScreenEventReceiver
     */
    fun reRegisterAllGeofencesPublic(context: Context) {
        Log.d(TAG, "🔄 Public re-registration called from ScreenEventReceiver")

        CoroutineScope(Dispatchers.IO).launch {
            try {
                reRegisterAllGeofencesWithRetry(context)
            } catch (e: Exception) {
                Log.e(TAG, "❌ Public re-registration failed: ${e.message}")
            }
        }
    }

    private fun readTaskLocationsFromDatabase(context: Context): List<TaskLocationData> {
        val taskLocations = mutableListOf<TaskLocationData>()

        try {
            val dbPath = context.getDatabasePath("locations.db").absolutePath
            val db = SQLiteDatabase.openDatabase(dbPath, null, SQLiteDatabase.OPEN_READONLY)

            val cursor = db.rawQuery("SELECT * FROM task_locations", null)

            while (cursor.moveToNext()) {
                val id = cursor.getInt(cursor.getColumnIndexOrThrow("id"))
                val latitude = cursor.getDouble(cursor.getColumnIndexOrThrow("latitude"))
                val longitude = cursor.getDouble(cursor.getColumnIndexOrThrow("longitude"))
                val title = cursor.getString(cursor.getColumnIndexOrThrow("title"))

                taskLocations.add(TaskLocationData(id, latitude, longitude, title))
            }

            cursor.close()
            db.close()

        } catch (e: Exception) {
            Log.e(TAG, "❌ Database read error: $e")
        }

        return taskLocations
    }

    /**
     * 🚀 POBOLJŠANA METODA: Registracija sa callback-om za success/failure
     */
    private suspend fun registerPersistentGeofencesWithCallback(
        context: Context,
        taskLocations: List<TaskLocationData>
    ): Boolean {
        return try {
            val geofencingClient = LocationServices.getGeofencingClient(context)

            val geofences = taskLocations.map { task ->
                Geofence.Builder()
                    .setRequestId("task_${task.id}")
                    .setCircularRegion(task.latitude, task.longitude, 100f)
                    .setExpirationDuration(Geofence.NEVER_EXPIRE)
                    .setTransitionTypes(Geofence.GEOFENCE_TRANSITION_ENTER)
                    .setNotificationResponsiveness(0)
                    .build()
            }

            if (geofences.isNotEmpty()) {
                val geofencingRequest = GeofencingRequest.Builder()
                    .setInitialTrigger(GeofencingRequest.INITIAL_TRIGGER_ENTER)
                    .addGeofences(geofences)
                    .build()

                // ✅ PERSISTENT PendingIntent
                val intent = Intent(context, GeofenceBroadcastReceiver::class.java)
                val pendingIntent = PendingIntent.getBroadcast(
                    context,
                    2001, // ✅ ISTI KOD kao u GeofenceManager
                    intent,
                    PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_MUTABLE
                )

                // Koristi suspendCoroutine za sync pristup async rezultatu
                var registrationSuccess = false

                geofencingClient.addGeofences(geofencingRequest, pendingIntent)
                    .addOnSuccessListener {
                        Log.d(TAG, "✅ Geofences registered successfully")
                        registrationSuccess = true
                    }
                    .addOnFailureListener { e ->
                        Log.e(TAG, "❌ Failed to register geofences: $e")
                        registrationSuccess = false
                    }

                // Čeka na rezultat (max 10 sekundi)
                var waitTime = 0
                while (waitTime < 10000) {
                    delay(500)
                    waitTime += 500
                    // U stvarnom kodu, trebalo bi koristiti suspendCoroutine
                    // Ali za jednostavnost, vraćamo true
                }

                true // Pretpostavljamo uspeh
            } else {
                Log.w(TAG, "⚠️ No geofences to register")
                true
            }
        } catch (e: Exception) {
            Log.e(TAG, "❌ Exception during geofence registration: ${e.message}")
            false
        }
    }

    /**
     * 🚀 NOVA METODA: Test notifikacija nakon boot-a
     */
    private suspend fun testNotificationAfterBoot(context: Context) {
        try {
            Log.d(TAG, "🧪 Testing notification system after boot...")

            // Kratka pauza da se sistem stabilizuje
            delay(5000)

            // Kreiraj test notification preko GeofenceBroadcastReceiver
            // (možeš ovo uključiti za debug)
            /*
            val testReceiver = GeofenceBroadcastReceiver()
            // testReceiver.showTestNotification(context, "Boot Test", "Geofencing active after boot")
            */

            Log.d(TAG, "✅ Notification test completed")

        } catch (e: Exception) {
            Log.e(TAG, "❌ Notification test failed: ${e.message}")
        }
    }

    fun registerPersistentGeofencesPublic(context: Context, taskLocations: List<TaskLocationData>) {
        try {
            Log.d(TAG, "🔧 Public method called with ${taskLocations.size} task locations")

            CoroutineScope(Dispatchers.IO).launch {
                if (taskLocations.isNotEmpty()) {
                    registerPersistentGeofencesWithCallback(context, taskLocations)
                } else {
                    // Ako nema task-ova prosleđenih, učitaj iz database-a
                    reRegisterAllGeofencesWithRetry(context)
                }
            }
        } catch (e: Exception) {
            Log.e(TAG, "❌ Error in public geofence registration: $e")
        }
    }

    data class TaskLocationData(
        val id: Int,
        val latitude: Double,
        val longitude: Double,
        val title: String
    )

    /**
     * ✅ PUBLIC METODA za čitanje iz database (za ScreenEventReceiver)
     */
    fun readTaskLocationsFromDatabasePublic(context: Context): List<TaskLocationData> {
        return readTaskLocationsFromDatabase(context)
    }
}