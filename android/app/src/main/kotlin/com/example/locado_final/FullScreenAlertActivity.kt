package com.example.locado_final

import android.app.Activity
import android.app.KeyguardManager
import android.content.Context
import android.content.Intent
import android.os.Build
import android.os.Bundle
import android.view.Window
import android.view.WindowManager
import android.widget.Button
import android.widget.TextView

class FullScreenAlertActivity : Activity() {

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)

        // Postavi da se prikaže preko lock screen-a
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O_MR1) {
            setShowWhenLocked(true)
            setTurnScreenOn(true)
            val keyguardManager = getSystemService(Context.KEYGUARD_SERVICE) as KeyguardManager
            keyguardManager.requestDismissKeyguard(this, null)
        } else {
            window.addFlags(
                WindowManager.LayoutParams.FLAG_DISMISS_KEYGUARD or
                        WindowManager.LayoutParams.FLAG_SHOW_WHEN_LOCKED or
                        WindowManager.LayoutParams.FLAG_TURN_SCREEN_ON
            )
        }

        // Full screen
        requestWindowFeature(Window.FEATURE_NO_TITLE)
        window.setFlags(
            WindowManager.LayoutParams.FLAG_FULLSCREEN,
            WindowManager.LayoutParams.FLAG_FULLSCREEN
        )

        // Kreiraće UI programatically
        createFullScreenUI()
    }

    private fun createFullScreenUI() {
        val taskTitle = intent.getStringExtra("taskTitle") ?: "Task Location"
        val taskMessage = intent.getStringExtra("taskMessage") ?: "You are near a task location"

        // Kreiranje layout-a programatically
        val layout = android.widget.LinearLayout(this).apply {
            orientation = android.widget.LinearLayout.VERTICAL
            setBackgroundColor(android.graphics.Color.parseColor("#2E7D32")) // Dark green
            setPadding(60, 120, 60, 120)
            gravity = android.view.Gravity.CENTER
        }

        // Ikona
        val icon = android.widget.TextView(this).apply {
            text = "📍"
            textSize = 80f
            gravity = android.view.Gravity.CENTER
            setPadding(0, 0, 0, 40)
        }

        // Naslov
        val titleView = TextView(this).apply {
            text = "LOCADO ALERT"
            textSize = 32f
            setTextColor(android.graphics.Color.WHITE)
            gravity = android.view.Gravity.CENTER
            setPadding(0, 0, 0, 20)
            typeface = android.graphics.Typeface.DEFAULT_BOLD
        }

        // Task naziv
        val taskTitleView = TextView(this).apply {
            text = taskTitle
            textSize = 24f
            setTextColor(android.graphics.Color.WHITE)
            gravity = android.view.Gravity.CENTER
            setPadding(0, 0, 0, 20)
            typeface = android.graphics.Typeface.DEFAULT_BOLD
        }

        // Poruka
        val messageView = TextView(this).apply {
            text = taskMessage
            textSize = 18f
            setTextColor(android.graphics.Color.parseColor("#E8F5E8"))
            gravity = android.view.Gravity.CENTER
            setPadding(40, 0, 40, 40)
        }

        // Dugmad
        val buttonLayout = android.widget.LinearLayout(this).apply {
            orientation = android.widget.LinearLayout.HORIZONTAL
            gravity = android.view.Gravity.CENTER
        }

        val dismissButton = Button(this).apply {
            text = "DISMISS"
            textSize = 16f
            setBackgroundColor(android.graphics.Color.parseColor("#66BB6A"))
            setTextColor(android.graphics.Color.WHITE)
            setPadding(40, 20, 40, 20)
            setOnClickListener {
                finish()
            }
        }

        val viewButton = Button(this).apply {
            text = "VIEW TASK"
            textSize = 16f
            setBackgroundColor(android.graphics.Color.parseColor("#4CAF50"))
            setTextColor(android.graphics.Color.WHITE)
            setPadding(40, 20, 40, 20)
            val marginParams = android.widget.LinearLayout.LayoutParams(
                android.widget.LinearLayout.LayoutParams.WRAP_CONTENT,
                android.widget.LinearLayout.LayoutParams.WRAP_CONTENT
            ).apply {
                leftMargin = 40
            }
            layoutParams = marginParams
            setOnClickListener {
                // Otvori glavnu aplikaciju
                val mainIntent = Intent(this@FullScreenAlertActivity, MainActivity::class.java).apply {
                    flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TASK
                    putExtra("openTaskId", intent.getStringExtra("taskId"))
                }
                startActivity(mainIntent)
                finish()
            }
        }

        // Dodaj sve u layout
        buttonLayout.addView(dismissButton)
        buttonLayout.addView(viewButton)

        layout.addView(icon)
        layout.addView(titleView)
        layout.addView(taskTitleView)
        layout.addView(messageView)
        layout.addView(buttonLayout)

        setContentView(layout)

        // Auto dismiss nakon 15 sekundi
        android.os.Handler(mainLooper).postDelayed({
            if (!isFinishing) {
                finish()
            }
        }, 15000)
    }
}