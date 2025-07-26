package com.example.locado_final

import android.app.Activity
import android.app.KeyguardManager
import android.app.NotificationManager
import android.content.Context
import android.graphics.Color
import android.graphics.PixelFormat
import android.graphics.Typeface
import android.graphics.drawable.GradientDrawable
import android.os.Build
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import android.os.PowerManager
import android.provider.Settings
import android.util.Log
import android.view.Gravity
import android.view.View
import android.view.ViewGroup
import android.view.WindowManager
import android.widget.Button
import android.widget.LinearLayout
import android.widget.TextView
import androidx.core.view.WindowCompat
import androidx.core.view.WindowInsetsCompat
import androidx.core.view.WindowInsetsControllerCompat

class LockScreenTaskActivity : Activity() {

    companion object {
        private const val TAG = "LockScreenTask"
        private const val AUTO_DISMISS_DELAY = 15000L // 15 sekundi
        private const val WAKE_LOCK_TIMEOUT = 30000L // 30 sekundi
    }

    private var wakeLock: PowerManager.WakeLock? = null
    private var windowManager: WindowManager? = null
    private var overlayView: View? = null
    private var dismissHandler: Handler? = null
    private var dismissRunnable: Runnable? = null

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)

        Log.d(TAG, "🚀 LockScreenTaskActivity started")

        // GET DATA FROM INTENT
        val taskTitle = intent.getStringExtra("taskTitle") ?: "Task Location"
        val taskMessage = intent.getStringExtra("taskMessage") ?: "You are near a task location"
        val taskId = intent.getStringExtra("taskId") ?: "unknown"

        Log.d(TAG, "📍 Showing alert for: $taskTitle")

        try {
            // 🚀 MULTI-LAYER APPROACH ZA MAKSIMALNU KOMPATIBILNOST
            setupWindowFlagsForAllVersions()

            // 🚀 PRIORITET 1: POKUŠAJ SYSTEM OVERLAY (ako je dozvoljen)
            if (canDrawOverlays()) {
                Log.d(TAG, "🔧 Attempting System Alert Window overlay")
                if (showAsSystemOverlay(taskTitle, taskMessage, taskId)) {
                    Log.d(TAG, "✅ System overlay successful")
                } else {
                    Log.d(TAG, "🔄 System overlay failed, using activity approach")
                    showAsRobustActivity(taskTitle, taskMessage, taskId)
                }
            } else {
                Log.d(TAG, "🔧 System overlay not permitted, using robust activity")
                showAsRobustActivity(taskTitle, taskMessage, taskId)
            }

            // 🚀 SETUP AUTO-DISMISS sa proper cleanup
            setupAutoDismiss()

        } catch (e: Exception) {
            Log.e(TAG, "❌ Critical error in onCreate: ${e.message}", e)
            // Fallback: minimalni prikaz
            showMinimalFallback(taskTitle, taskMessage, taskId)
        }
    }

    /**
     * 🚀 NOVA METODA: Setup window flags za sve Android verzije
     */
    private fun setupWindowFlagsForAllVersions() {
        try {
            // 🚀 ANDROID 12+ (API 31+) APPROACH
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
                setShowWhenLocked(true)
                setTurnScreenOn(true)

                // New approach for Android 12+
                WindowCompat.setDecorFitsSystemWindows(window, false)

                val windowInsetsController = WindowCompat.getInsetsController(window, window.decorView)
                windowInsetsController.systemBarsBehavior = WindowInsetsControllerCompat.BEHAVIOR_SHOW_TRANSIENT_BARS_BY_SWIPE
                windowInsetsController.hide(WindowInsetsCompat.Type.systemBars())

            }
            // 🚀 ANDROID 8.0+ (API 27+) APPROACH
            else if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O_MR1) {
                setShowWhenLocked(true)
                setTurnScreenOn(true)

                val keyguardManager = getSystemService(Context.KEYGUARD_SERVICE) as? KeyguardManager
                keyguardManager?.requestDismissKeyguard(this, null)
            }
            // 🚀 LEGACY ANDROID APPROACH (API < 27)
            else {
                @Suppress("DEPRECATION")
                window.addFlags(
                    WindowManager.LayoutParams.FLAG_DISMISS_KEYGUARD or
                            WindowManager.LayoutParams.FLAG_SHOW_WHEN_LOCKED or
                            WindowManager.LayoutParams.FLAG_TURN_SCREEN_ON
                )
            }

            // 🚀 UNIVERSAL FLAGS ZA SVE VERZIJE
            window.addFlags(
                WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON or
                        WindowManager.LayoutParams.FLAG_ALLOW_LOCK_WHILE_SCREEN_ON or
                        WindowManager.LayoutParams.FLAG_FULLSCREEN or
                        WindowManager.LayoutParams.FLAG_LAYOUT_IN_SCREEN or
                        WindowManager.LayoutParams.FLAG_LAYOUT_NO_LIMITS
            )

            Log.d(TAG, "✅ Window flags configured for Android ${Build.VERSION.SDK_INT}")

        } catch (e: Exception) {
            Log.e(TAG, "❌ Error setting up window flags: ${e.message}")
        }
    }

    private fun canDrawOverlays(): Boolean {
        return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
            Settings.canDrawOverlays(this)
        } else {
            true
        }
    }

    /**
     * 🚀 POBOLJŠANA SYSTEM OVERLAY METODA
     */
    private fun showAsSystemOverlay(taskTitle: String, taskMessage: String, taskId: String): Boolean {
        return try {
            wakeUpScreen()

            windowManager = getSystemService(Context.WINDOW_SERVICE) as WindowManager

            // CREATE OVERLAY VIEW
            overlayView = createViberStyleUI(taskTitle, taskMessage, taskId)

            // 🚀 POBOLJŠANI WINDOW LAYOUT PARAMS
            val layoutParams = WindowManager.LayoutParams().apply {
                // 🚀 WINDOW TYPE ZA RAZLIČITE ANDROID VERZIJE
                type = when {
                    Build.VERSION.SDK_INT >= Build.VERSION_CODES.O ->
                        WindowManager.LayoutParams.TYPE_APPLICATION_OVERLAY
                    Build.VERSION.SDK_INT >= Build.VERSION_CODES.N ->
                        WindowManager.LayoutParams.TYPE_PHONE
                    else ->
                        @Suppress("DEPRECATION")
                        WindowManager.LayoutParams.TYPE_SYSTEM_ALERT
                }

                // 🚀 OPTIMIZOVANI FLAGS ZA LOCK SCREEN
                flags = WindowManager.LayoutParams.FLAG_NOT_FOCUSABLE or
                        WindowManager.LayoutParams.FLAG_NOT_TOUCH_MODAL or
                        WindowManager.LayoutParams.FLAG_SHOW_WHEN_LOCKED or
                        WindowManager.LayoutParams.FLAG_DISMISS_KEYGUARD or
                        WindowManager.LayoutParams.FLAG_TURN_SCREEN_ON or
                        WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON or
                        WindowManager.LayoutParams.FLAG_FULLSCREEN or
                        WindowManager.LayoutParams.FLAG_LAYOUT_IN_SCREEN

                // LAYOUT
                width = WindowManager.LayoutParams.MATCH_PARENT
                height = WindowManager.LayoutParams.MATCH_PARENT
                gravity = Gravity.CENTER

                // PIXEL FORMAT
                format = PixelFormat.TRANSLUCENT

                // 🚀 DODATNE PROPERTIES ZA ROBUSNOST
                screenBrightness = WindowManager.LayoutParams.BRIGHTNESS_OVERRIDE_FULL
                buttonBrightness = WindowManager.LayoutParams.BRIGHTNESS_OVERRIDE_FULL
            }

            // ADD TO WINDOW MANAGER
            windowManager?.addView(overlayView, layoutParams)
            Log.d(TAG, "✅ System overlay displayed successfully")

            true
        } catch (e: Exception) {
            Log.e(TAG, "❌ System overlay failed: ${e.message}")
            false
        }
    }

    /**
     * 🚀 NOVA METODA: Robusna activity approach
     */
    private fun showAsRobustActivity(taskTitle: String, taskMessage: String, taskId: String) {
        try {
            Log.d(TAG, "🔧 Using robust activity approach")

            wakeUpScreen()

            // 🚀 MAKSIMALNO AGRESIVNI FLAGS ZA LOCK SCREEN
            window.addFlags(
                WindowManager.LayoutParams.FLAG_SHOW_WHEN_LOCKED or
                        WindowManager.LayoutParams.FLAG_TURN_SCREEN_ON or
                        WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON or
                        WindowManager.LayoutParams.FLAG_DISMISS_KEYGUARD or
                        WindowManager.LayoutParams.FLAG_ALLOW_LOCK_WHILE_SCREEN_ON or
                        WindowManager.LayoutParams.FLAG_FULLSCREEN or
                        WindowManager.LayoutParams.FLAG_LAYOUT_IN_SCREEN or
                        WindowManager.LayoutParams.FLAG_LAYOUT_NO_LIMITS
            )

            // 🚀 FORCE FULL BRIGHTNESS
            val layoutParams = window.attributes
            layoutParams.screenBrightness = 1.0f
            layoutParams.buttonBrightness = 1.0f
            window.attributes = layoutParams

            // SET CONTENT VIEW
            setContentView(createViberStyleUI(taskTitle, taskMessage, taskId))
            Log.d(TAG, "✅ Robust activity displayed successfully")

        } catch (e: Exception) {
            Log.e(TAG, "❌ Robust activity failed: ${e.message}")
            showMinimalFallback(taskTitle, taskMessage, taskId)
        }
    }

    /**
     * 🚀 NOVA METODA: Minimalni fallback ako sve ostalo ne uspe
     */
    private fun showMinimalFallback(taskTitle: String, taskMessage: String, taskId: String) {
        try {
            Log.d(TAG, "🆘 Using minimal fallback approach")

            // Osnovni TextView sa porukom
            val textView = TextView(this).apply {
                text = "🔔 LOCADO ALERT\n\n📍 $taskTitle\n\n$taskMessage"
                textSize = 24f
                setTextColor(Color.WHITE)
                setBackgroundColor(Color.parseColor("#2E7D32"))
                gravity = Gravity.CENTER
                setPadding(40, 40, 40, 40)
            }

            setContentView(textView)
            Log.d(TAG, "✅ Minimal fallback displayed")

        } catch (e: Exception) {
            Log.e(TAG, "❌ Even minimal fallback failed: ${e.message}")
            // U ovom slučaju, samo finish() activity
            finish()
        }
    }

    /**
     * 🚀 POBOLJŠANA WAKE UP SCREEN METODA
     */
    private fun wakeUpScreen() {
        try {
            Log.d(TAG, "💡 Waking up screen with enhanced method")

            val powerManager = getSystemService(Context.POWER_SERVICE) as? PowerManager
            powerManager?.let { pm ->

                // 🚀 RAZLIČITI PRISTUPI ZA RAZLIČITE ANDROID VERZIJE
                wakeLock = when {
                    Build.VERSION.SDK_INT >= Build.VERSION_CODES.LOLLIPOP -> {
                        pm.newWakeLock(
                            PowerManager.SCREEN_BRIGHT_WAKE_LOCK or
                                    PowerManager.ACQUIRE_CAUSES_WAKEUP or
                                    PowerManager.ON_AFTER_RELEASE,
                            "LocadoApp::TaskAlert"
                        )
                    }
                    else -> {
                        @Suppress("DEPRECATION")
                        pm.newWakeLock(
                            PowerManager.SCREEN_BRIGHT_WAKE_LOCK or
                                    PowerManager.ACQUIRE_CAUSES_WAKEUP or
                                    PowerManager.ON_AFTER_RELEASE,
                            "LocadoApp::TaskAlert"
                        )
                    }
                }

                wakeLock?.let { wl ->
                    if (!wl.isHeld) {
                        wl.acquire(WAKE_LOCK_TIMEOUT)
                        Log.d(TAG, "✅ Wake lock acquired with timeout ${WAKE_LOCK_TIMEOUT}ms")
                    }
                }
            }
        } catch (e: Exception) {
            Log.e(TAG, "❌ Error waking up screen: ${e.message}")
        }
    }

    private fun createViberStyleUI(taskTitle: String, taskMessage: String, taskId: String): View {
        Log.d(TAG, "🎨 Creating modernized lock screen UI")

        // MAIN CONTAINER sa gradient background
        val mainLayout = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            gravity = Gravity.CENTER

            // Gradient background umesto solid black
            val gradientDrawable = GradientDrawable(
                GradientDrawable.Orientation.TOP_BOTTOM,
                intArrayOf(
                    Color.parseColor("#B3000000"), // Semi-transparent black top
                    Color.parseColor("#CC000000")  // Slightly more opaque bottom
                )
            )
            background = gradientDrawable
            setPadding(32, 80, 32, 80)
        }

        // LOCADO HEADER CARD
        val headerCard = LinearLayout(this).apply {
            orientation = LinearLayout.HORIZONTAL
            gravity = Gravity.CENTER
            setPadding(24, 16, 24, 16)
            elevation = 8f
        }

        val headerBackground = GradientDrawable().apply {
            shape = GradientDrawable.RECTANGLE
            setColor(Color.parseColor("#EE009688")) // Teal color
            cornerRadius = 20f
        }
        headerCard.background = headerBackground

        val locadoIcon = TextView(this).apply {
            text = "📍"
            textSize = 24f
            setPadding(0, 0, 12, 0)
        }

        val locadoTitle = TextView(this).apply {
            text = "LOCADO ALERT"
            setTextColor(Color.WHITE)
            textSize = 18f
            typeface = Typeface.DEFAULT_BOLD
        }

        headerCard.addView(locadoIcon)
        headerCard.addView(locadoTitle)

        // MAIN TASK CARD
        val taskCard = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            gravity = Gravity.CENTER
            setPadding(32, 40, 32, 40)
            elevation = 20f
        }

        val taskCardBackground = GradientDrawable().apply {
            shape = GradientDrawable.RECTANGLE
            setColor(Color.parseColor("#F0FFFFFF"))
            cornerRadius = 24f
            setStroke(2, Color.parseColor("#E0E0E0"))
        }
        taskCard.background = taskCardBackground

        // TASK ICON CONTAINER
        val iconContainer = LinearLayout(this).apply {
            orientation = LinearLayout.HORIZONTAL
            gravity = Gravity.CENTER
            setPadding(20, 20, 20, 8)
        }

        val iconBackground = GradientDrawable().apply {
            shape = GradientDrawable.OVAL
            setColor(Color.parseColor("#E8F5E8")) // Light green background
        }

        val taskIconView = TextView(this).apply {
            text = "📋"
            textSize = 48f
            gravity = Gravity.CENTER
            setPadding(20, 20, 20, 20)
            background = iconBackground
        }

        iconContainer.addView(taskIconView)

        // TASK TITLE
        val titleView = TextView(this).apply {
            text = taskTitle
            setTextColor(Color.parseColor("#1A1A1A"))
            textSize = 22f
            typeface = Typeface.DEFAULT_BOLD
            gravity = Gravity.CENTER
            setPadding(16, 16, 16, 8)
            maxLines = 2
        }

        // TASK SUBTITLE
        val subtitleView = TextView(this).apply {
            text = "You're near this location!"
            setTextColor(Color.parseColor("#666666"))
            textSize = 16f
            gravity = Gravity.CENTER
            setPadding(16, 0, 16, 32)
        }

        // BUTTONS CONTAINER
        val buttonsContainer = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            gravity = Gravity.CENTER
            setPadding(8, 0, 8, 0)
        }

        // PRIMARY ACTION BUTTON (View Task)
        val viewButton = createModernButton(
            text = "View Task",
            backgroundColor = Color.parseColor("#FF009688"), // Teal
            textColor = Color.WHITE,
            isPrimary = true
        )

        viewButton.setOnClickListener {
            Log.d(TAG, "👆 View Task clicked - launching Flutter")

            try {
                val flutterIntent = TaskDetailFlutterActivity.createIntent(
                    this@LockScreenTaskActivity,
                    taskId.removePrefix("task_"),
                    taskTitle
                )

                startActivity(flutterIntent)
                Log.d(TAG, "✅ TaskDetailFlutterActivity launched")

                dismissNotification(taskId)
                cleanupAndFinish()

            } catch (e: Exception) {
                Log.e(TAG, "❌ Error launching TaskDetailFlutterActivity: ${e.message}")

                // Fallback to MainActivity
                try {
                    val mainIntent = android.content.Intent(this@LockScreenTaskActivity, MainActivity::class.java)
                    mainIntent.putExtra("openTaskDetail", true)
                    mainIntent.putExtra("taskId", taskId.removePrefix("task_"))
                    mainIntent.putExtra("taskTitle", taskTitle)
                    mainIntent.putExtra("launchedFromNotification", true)
                    mainIntent.addFlags(android.content.Intent.FLAG_ACTIVITY_NEW_TASK or android.content.Intent.FLAG_ACTIVITY_CLEAR_TOP)

                    startActivity(mainIntent)
                    Log.d(TAG, "✅ MainActivity fallback launched")

                } catch (fallbackError: Exception) {
                    Log.e(TAG, "❌ MainActivity fallback failed: ${fallbackError.message}")
                }

                dismissNotification(taskId)
                cleanupAndFinish()
            }
        }

        // SECONDARY ACTIONS ROW
        val secondaryRow = LinearLayout(this).apply {
            orientation = LinearLayout.HORIZONTAL
            gravity = Gravity.CENTER
            setPadding(0, 16, 0, 0)
        }

        val dismissButton = createModernButton(
            text = "Dismiss",
            backgroundColor = Color.parseColor("#F5F5F5"),
            textColor = Color.parseColor("#666666"),
            isPrimary = false
        )

        dismissButton.setOnClickListener {
            Log.d(TAG, "👆 Dismiss clicked")
            try {
                dismissNotification(taskId)
                cleanupAndFinish()
            } catch (e: Exception) {
                Log.e(TAG, "❌ Error on dismiss: ${e.message}")
                finish()
            }
        }

        val deleteButton = createModernButton(
            text = "Delete",
            backgroundColor = Color.parseColor("#FFEBEE"),
            textColor = Color.parseColor("#D32F2F"),
            isPrimary = false
        )

        deleteButton.setOnClickListener {
            Log.d(TAG, "👆 Delete Task clicked")
            showModernDeleteConfirmationDialog(taskId, taskTitle)
        }

        // LAYOUT PARAMS FOR SECONDARY BUTTONS
        val secondaryButtonParams = LinearLayout.LayoutParams(
            0,
            ViewGroup.LayoutParams.WRAP_CONTENT,
            1f
        ).apply {
            setMargins(8, 0, 8, 0)
        }

        secondaryRow.addView(dismissButton, secondaryButtonParams)
        secondaryRow.addView(deleteButton, secondaryButtonParams)

        // ASSEMBLE TASK CARD
        taskCard.addView(iconContainer)
        taskCard.addView(titleView)
        taskCard.addView(subtitleView)
        taskCard.addView(viewButton)
        taskCard.addView(secondaryRow)

        // ASSEMBLE MAIN LAYOUT
        mainLayout.addView(headerCard)

        // Spacer
        val spacer = View(this).apply {
            layoutParams = LinearLayout.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT,
                40
            )
        }
        mainLayout.addView(spacer)

        mainLayout.addView(taskCard)

        // CLICK OUTSIDE TO DISMISS
        mainLayout.setOnClickListener {
            Log.d(TAG, "👆 Background clicked - dismissing")
            dismissNotification(taskId)
            cleanupAndFinish()
        }

        Log.d(TAG, "✅ Modern UI created successfully")
        return mainLayout
    }

    private fun createModernButton(
        text: String,
        backgroundColor: Int,
        textColor: Int,
        isPrimary: Boolean
    ): Button {
        return Button(this).apply {
            setText(text)
            setTextColor(textColor)
            textSize = if (isPrimary) 18f else 16f
            typeface = if (isPrimary) Typeface.DEFAULT_BOLD else Typeface.DEFAULT

            val buttonHeight = if (isPrimary) 56 else 48
            val horizontalPadding = if (isPrimary) 48 else 32

            minHeight = buttonHeight
            setPadding(horizontalPadding, 0, horizontalPadding, 0)

            elevation = if (isPrimary) 6f else 2f
            isClickable = true
            isFocusable = true

            // MODERN BUTTON STYLING
            val buttonBackground = GradientDrawable().apply {
                shape = GradientDrawable.RECTANGLE
                setColor(backgroundColor)
                cornerRadius = if (isPrimary) 16f else 12f

                if (!isPrimary) {
                    setStroke(1, Color.parseColor("#E0E0E0"))
                }
            }
            background = buttonBackground

            // SET LAYOUT PARAMS
            if (isPrimary) {
                layoutParams = LinearLayout.LayoutParams(
                    ViewGroup.LayoutParams.MATCH_PARENT,
                    ViewGroup.LayoutParams.WRAP_CONTENT
                ).apply {
                    setMargins(0, 0, 0, 8)
                }
            }

            // RIPPLE EFFECT
            isClickable = true
            isFocusable = true
            foreground = android.graphics.drawable.RippleDrawable(
                android.content.res.ColorStateList.valueOf(
                    if (isPrimary) Color.parseColor("#80FFFFFF")
                    else Color.parseColor("#20000000")
                ),
                null,
                null
            )
        }
    }

    /**
     * 🆕 MODERN DELETE CONFIRMATION DIALOG
     */
    private fun showModernDeleteConfirmationDialog(taskId: String, taskTitle: String) {
        try {
            Log.d(TAG, "🗑️ Showing modern delete confirmation for: $taskTitle")

            // Koristi standardni AlertDialog.Builder umesto nepostojećeg tema
            val dialog = android.app.AlertDialog.Builder(this)
                .create()

            // CUSTOM VIEW FOR DIALOG
            val dialogView = LinearLayout(this).apply {
                orientation = LinearLayout.VERTICAL
                setPadding(32, 32, 32, 24)
                setBackgroundColor(Color.WHITE)
            }

            // HEADER WITH ICON
            val headerLayout = LinearLayout(this).apply {
                orientation = LinearLayout.HORIZONTAL
                gravity = Gravity.CENTER_VERTICAL
                setPadding(0, 0, 0, 24)
            }

            val iconContainer = LinearLayout(this).apply {
                setPadding(12, 12, 12, 12)
                gravity = Gravity.CENTER
            }

            val iconBackground = GradientDrawable().apply {
                shape = GradientDrawable.OVAL
                setColor(Color.parseColor("#FFEBEE"))
            }
            iconContainer.background = iconBackground

            val deleteIcon = TextView(this).apply {
                text = "🗑️"
                textSize = 24f
                gravity = Gravity.CENTER
            }

            iconContainer.addView(deleteIcon)

            val titleText = TextView(this).apply {
                text = "Delete Task"
                textSize = 20f
                typeface = Typeface.DEFAULT_BOLD
                setTextColor(Color.parseColor("#1A1A1A"))
                setPadding(16, 0, 0, 0)
            }

            headerLayout.addView(iconContainer)
            headerLayout.addView(titleText)

            // TASK INFO CARD
            val taskInfoCard = LinearLayout(this).apply {
                orientation = LinearLayout.VERTICAL
                setPadding(20, 16, 20, 16)
            }

            val taskInfoBackground = GradientDrawable().apply {
                shape = GradientDrawable.RECTANGLE
                setColor(Color.parseColor("#E8F5E8"))
                cornerRadius = 12f
                setStroke(1, Color.parseColor("#C8E6C9"))
            }
            taskInfoCard.background = taskInfoBackground

            val taskLabel = TextView(this).apply {
                text = "Task to delete:"
                textSize = 12f
                setTextColor(Color.parseColor("#388E3C"))
                typeface = Typeface.DEFAULT_BOLD
            }

            val taskNameText = TextView(this).apply {
                text = taskTitle
                textSize = 16f
                setTextColor(Color.parseColor("#1B5E20"))
                typeface = Typeface.DEFAULT_BOLD
                setPadding(0, 4, 0, 0)
            }

            taskInfoCard.addView(taskLabel)
            taskInfoCard.addView(taskNameText)

            // WARNING MESSAGE
            val warningCard = LinearLayout(this).apply {
                orientation = LinearLayout.HORIZONTAL
                setPadding(16, 16, 16, 16)
                gravity = Gravity.CENTER_VERTICAL
            }

            val warningBackground = GradientDrawable().apply {
                shape = GradientDrawable.RECTANGLE
                setColor(Color.parseColor("#FFF3E0"))
                cornerRadius = 12f
                setStroke(1, Color.parseColor("#FFE0B2"))
            }
            warningCard.background = warningBackground

            val warningIcon = TextView(this).apply {
                text = "⚠️"
                textSize = 18f
                setPadding(0, 0, 12, 0)
            }

            val warningText = TextView(this).apply {
                text = "This action cannot be undone. All task data will be permanently removed."
                textSize = 14f
                setTextColor(Color.parseColor("#E65100"))
            }

            warningCard.addView(warningIcon)
            warningCard.addView(warningText)

            // BUTTONS
            val buttonsLayout = LinearLayout(this).apply {
                orientation = LinearLayout.HORIZONTAL
                setPadding(0, 24, 0, 0)
            }

            val cancelButton = createModernButton(
                text = "Cancel",
                backgroundColor = Color.parseColor("#F5F5F5"),
                textColor = Color.parseColor("#666666"),
                isPrimary = false
            )

            val confirmButton = createModernButton(
                text = "Delete",
                backgroundColor = Color.parseColor("#D32F2F"),
                textColor = Color.WHITE,
                isPrimary = false
            )

            val buttonParams = LinearLayout.LayoutParams(
                0,
                ViewGroup.LayoutParams.WRAP_CONTENT,
                1f
            ).apply {
                setMargins(4, 0, 4, 0)
            }

            buttonsLayout.addView(cancelButton, buttonParams)
            buttonsLayout.addView(confirmButton, buttonParams)

            // ASSEMBLE DIALOG VIEW
            dialogView.addView(headerLayout)

            // Add spacing between elements
            val spacer1 = View(this).apply {
                layoutParams = LinearLayout.LayoutParams(
                    ViewGroup.LayoutParams.MATCH_PARENT,
                    16
                )
            }
            dialogView.addView(spacer1)

            dialogView.addView(taskInfoCard)

            val spacer2 = View(this).apply {
                layoutParams = LinearLayout.LayoutParams(
                    ViewGroup.LayoutParams.MATCH_PARENT,
                    16
                )
            }
            dialogView.addView(spacer2)

            dialogView.addView(warningCard)
            dialogView.addView(buttonsLayout)

            // SET DIALOG VIEW WITH ROUNDED CORNERS
            val dialogBackground = GradientDrawable().apply {
                shape = GradientDrawable.RECTANGLE
                setColor(Color.WHITE)
                cornerRadius = 20f
            }
            dialogView.background = dialogBackground

            dialog.setView(dialogView)
            dialog.setCancelable(true)

            // BUTTON ACTIONS
            cancelButton.setOnClickListener {
                Log.d(TAG, "❌ User cancelled task deletion")
                dialog.dismiss()
            }

            confirmButton.setOnClickListener {
                Log.d(TAG, "✅ User confirmed task deletion")
                dialog.dismiss()
                executeTaskDeletion(taskId, taskTitle)
            }

            // SHOW DIALOG
            dialog.show()

            // OPTIONAL: Set dialog window properties for better appearance
            try {
                dialog.window?.setBackgroundDrawableResource(android.R.color.transparent)
            } catch (e: Exception) {
                Log.w(TAG, "Could not set transparent background: ${e.message}")
            }

        } catch (e: Exception) {
            Log.e(TAG, "❌ Error showing modern delete confirmation: ${e.message}")
            executeTaskDeletion(taskId, taskTitle)
        }
    }

    private fun createStyledButton(text: String, backgroundColor: Int, textColor: Int, isLarge: Boolean = false): Button {
        return Button(this).apply {
            setText(text)
            setTextColor(textColor)
            textSize = if (isLarge) 20f else 16f
            typeface = Typeface.DEFAULT_BOLD

            // 🆕 RAZLIČITE VELIČINE ZA RAZLIČITA DUGMAD
            if (isLarge) {
                minWidth = 200
                minHeight = 80
                setPadding(40, 25, 40, 25)
            } else {
                minWidth = 120
                minHeight = 60
                setPadding(25, 15, 25, 15)
            }

            elevation = 6f
            isClickable = true
            isFocusable = true

            // CREATE ROUNDED BACKGROUND
            val buttonBackground = GradientDrawable().apply {
                shape = GradientDrawable.RECTANGLE
                setColor(backgroundColor)
                cornerRadius = if (isLarge) 40f else 30f
            }
            background = buttonBackground
        }
    }

    /**
     * 🚀 UKLONI NOTIFICATION IZ PANEL-A
     */
    private fun dismissNotification(taskId: String) {
        try {
            val notificationManager = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
            val notificationId = taskId.hashCode()

            notificationManager.cancel(notificationId)
            Log.d(TAG, "✅ Notification dismissed: ID $notificationId")

        } catch (e: Exception) {
            Log.e(TAG, "❌ Error dismissing notification: ${e.message}")
        }
    }

    /**
     * 🚀 POBOLJŠANA AUTO-DISMISS LOGIKA
     */
    private fun setupAutoDismiss() {
        try {
            dismissHandler = Handler(Looper.getMainLooper())
            dismissRunnable = Runnable {
                Log.d(TAG, "⏰ Auto-dismissing after ${AUTO_DISMISS_DELAY}ms")
                if (!isFinishing && !isDestroyed) {
                    // ✅ AUTO-DISMISS TAKOĐE UKLANJA NOTIFICATION
                    val taskId = intent.getStringExtra("taskId") ?: "unknown"
                    dismissNotification(taskId)
                    cleanupAndFinish()
                }
            }
            dismissHandler?.postDelayed(dismissRunnable!!, AUTO_DISMISS_DELAY)

        } catch (e: Exception) {
            Log.e(TAG, "❌ Error setting up auto-dismiss: ${e.message}")
        }
    }

    /**
     * 🚀 POBOLJŠANA CLEANUP METODA
     */
    private fun cleanupAndFinish() {
        try {
            Log.d(TAG, "🧹 Enhanced cleanup and finishing")

            // Cancel auto-dismiss
            dismissRunnable?.let { runnable ->
                dismissHandler?.removeCallbacks(runnable)
            }

            // REMOVE OVERLAY IF EXISTS
            try {
                if (overlayView != null && windowManager != null) {
                    windowManager?.removeView(overlayView)
                    overlayView = null
                    Log.d(TAG, "✅ Overlay removed")
                }
            } catch (e: Exception) {
                Log.e(TAG, "❌ Error removing overlay: ${e.message}")
            }

            // RELEASE WAKE LOCK
            wakeLock?.let { wl ->
                if (wl.isHeld) {
                    wl.release()
                    Log.d(TAG, "🔓 Wake lock released")
                }
            }
            wakeLock = null

            // FINISH ACTIVITY
            if (!isFinishing) {
                finish()
            }

        } catch (e: Exception) {
            Log.e(TAG, "❌ Error during cleanup: ${e.message}")
            // Force finish even if cleanup fails
            try {
                finish()
            } catch (finishError: Exception) {
                Log.e(TAG, "❌ Even finish() failed: ${finishError.message}")
            }
        }
    }

    override fun onDestroy() {
        Log.d(TAG, "🔄 Activity destroying")
        cleanupAndFinish()
        super.onDestroy()
    }

    override fun onBackPressed() {
        Log.d(TAG, "🔙 Back button pressed - dismissing")

        // ✅ BACK BUTTON TAKOĐE UKLANJA NOTIFICATION
        val taskId = intent.getStringExtra("taskId") ?: "unknown"
        dismissNotification(taskId)
        cleanupAndFinish()
    }

    override fun onPause() {
        super.onPause()
        Log.d(TAG, "⏸️ Activity paused")
    }

    override fun onResume() {
        super.onResume()
        Log.d(TAG, "▶️ Activity resumed")
    }

    /**
     * 🆕 IZVRŠI BRISANJE TASKA
     */
    private fun executeTaskDeletion(taskId: String, taskTitle: String) {
        try {
            Log.d(TAG, "🗑️ Executing task deletion: $taskId - $taskTitle")

            // 🆕 POZOVI FLUTTER/ANDROID ZA BRISANJE TASKA
            val deleteIntent = android.content.Intent(this, MainActivity::class.java)
            deleteIntent.putExtra("deleteTask", true)
            deleteIntent.putExtra("taskId", taskId.removePrefix("task_"))
            deleteIntent.putExtra("taskTitle", taskTitle)
            deleteIntent.addFlags(android.content.Intent.FLAG_ACTIVITY_NEW_TASK or android.content.Intent.FLAG_ACTIVITY_CLEAR_TOP)

            startActivity(deleteIntent)
            Log.d(TAG, "✅ Delete request sent to MainActivity")

            // 🆕 PRIKAŽI POTVRDU KORISNIKU
            android.widget.Toast.makeText(this, "Task '$taskTitle' deleted", android.widget.Toast.LENGTH_SHORT).show()

            // ✅ UKLONI NOTIFICATION I ZATVORI
            dismissNotification(taskId)
            cleanupAndFinish()

        } catch (e: Exception) {
            Log.e(TAG, "❌ Error executing task deletion: ${e.message}")

            // Fallback: samo zatvori bez brisanja
            dismissNotification(taskId)
            cleanupAndFinish()
        }
    }
}