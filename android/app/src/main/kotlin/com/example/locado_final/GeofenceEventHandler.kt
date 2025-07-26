package com.example.locado_final

import io.flutter.plugin.common.EventChannel
import android.util.Log

object GeofenceEventHandler : EventChannel.StreamHandler {
    private var eventSink: EventChannel.EventSink? = null

    override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
        eventSink = events
        Log.d("GeofenceEventHandler", "📡 Event channel connected - placeholder")
    }

    override fun onCancel(arguments: Any?) {
        eventSink = null
        Log.d("GeofenceEventHandler", "📡 Event channel disconnected - placeholder")
    }

    fun sendEvent(taskId: String, event: String) {
        Log.d("GeofenceEventHandler", "📤 Event sent - placeholder: $taskId -> $event")
    }
}