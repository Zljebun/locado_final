// TaskDetailActivity.kt
package com.example.locado_final

import android.app.Activity
import android.content.Intent
import android.os.Bundle
import android.util.Log

class TaskDetailActivity : Activity() {

    companion object {
        private const val TAG = "TaskDetailActivity"
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)

        Log.d(TAG, "🚀 TaskDetailActivity started")

        // Dobij podatke iz intent-a
        val taskId = intent.getStringExtra("taskId")
        val taskTitle = intent.getStringExtra("taskTitle")
        val fromNotification = intent.getBooleanExtra("fromNotification", false)

        Log.d(TAG, "📝 TaskId: $taskId")
        Log.d(TAG, "📝 TaskTitle: $taskTitle")
        Log.d(TAG, "📝 FromNotification: $fromNotification")

        if (fromNotification && taskId != null) {
            // Pokreni Flutter aplikaciju sa specifičnim task-om
            launchFlutterWithTask(taskId, taskTitle)
        } else {
            Log.w(TAG, "⚠️ Missing required data - taskId: $taskId, fromNotification: $fromNotification")
        }

        // Završi ovu activity odmah
        finish()
    }

    private fun launchFlutterWithTask(taskId: String, taskTitle: String?) {
        try {
            Log.d(TAG, "🎯 Launching Flutter with task: $taskId")

            val flutterIntent = Intent(this, MainActivity::class.java).apply {
                // Dodaj task podatke
                putExtra("openTaskId", taskId)
                putExtra("openTaskDetail", true)
                putExtra("taskTitle", taskTitle ?: "Task")
                putExtra("launchedFromNotification", true)

                // Flags za pokretanje kada je telefon zaključan i app ubijen
                flags = Intent.FLAG_ACTIVITY_NEW_TASK or
                        Intent.FLAG_ACTIVITY_CLEAR_TOP or
                        Intent.FLAG_ACTIVITY_SINGLE_TOP or
                        Intent.FLAG_ACTIVITY_BROUGHT_TO_FRONT
            }

            startActivity(flutterIntent)
            Log.d(TAG, "✅ Flutter launch intent sent successfully")

        } catch (e: Exception) {
            Log.e(TAG, "❌ Error launching Flutter: ${e.message}", e)
        }
    }

    override fun onNewIntent(intent: Intent?) {
        super.onNewIntent(intent)
        Log.d(TAG, "🔄 onNewIntent called")

        // Handle ako se activity pozove ponovo
        if (intent != null) {
            setIntent(intent)
            onCreate(null) // Reprocess intent
        }
    }
}