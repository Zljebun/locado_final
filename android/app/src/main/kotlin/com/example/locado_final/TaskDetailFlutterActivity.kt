package com.example.locado_final

import android.content.Context
import android.content.Intent
import android.os.Bundle
import android.util.Log
import android.view.WindowManager
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class TaskDetailFlutterActivity : FlutterActivity() {

    companion object {
        private const val TAG = "TaskDetailFlutter"
        private const val CHANNEL = "com.example.locado_final/task_detail_channel"

        fun createIntent(context: Context, taskId: String, taskTitle: String): Intent {
            return Intent(context, TaskDetailFlutterActivity::class.java).apply {
                putExtra("taskId", taskId)
                putExtra("taskTitle", taskTitle)
                addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or
                        Intent.FLAG_ACTIVITY_CLEAR_TOP or
                        Intent.FLAG_ACTIVITY_SINGLE_TOP)
            }
        }
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        Log.d(TAG, "🚀 TaskDetailFlutterActivity starting")

        // Setup za lock screen prikaz
        setupLockScreenFlags()

        super.onCreate(savedInstanceState)

        Log.d(TAG, "✅ TaskDetailFlutterActivity created successfully")
    }

    private fun setupLockScreenFlags() {
        try {
            // Omogući prikaz na lock screen-u
            setShowWhenLocked(true)
            setTurnScreenOn(true)

            // Dodaj window flags za lock screen
            window.addFlags(
                WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON or
                        WindowManager.LayoutParams.FLAG_SHOW_WHEN_LOCKED or
                        WindowManager.LayoutParams.FLAG_TURN_SCREEN_ON
            )

            Log.d(TAG, "✅ Lock screen flags configured")
        } catch (e: Exception) {
            Log.e(TAG, "❌ Error setting up lock screen flags: ${e.message}")
        }
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        // Pošaljite task podatke u Flutter
        val taskId = intent.getStringExtra("taskId") ?: ""
        val taskTitle = intent.getStringExtra("taskTitle") ?: ""

        Log.d(TAG, "📋 Configuring Flutter engine with taskId: $taskId, taskTitle: $taskTitle")

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "getTaskData" -> {
                        Log.d(TAG, "📤 Sending task data to Flutter")
                        result.success(mapOf(
                            "taskId" to taskId,
                            "taskTitle" to taskTitle,
                            "isLockScreen" to true
                        ))
                    }
                    "closeTaskDetail" -> {
                        Log.d(TAG, "🔙 Flutter requested close")
                        finish()
                        result.success("closed")
                    }
                    else -> {
                        result.notImplemented()
                    }
                }
            }
    }

    override fun shouldAttachEngineToActivity(): Boolean = true
}