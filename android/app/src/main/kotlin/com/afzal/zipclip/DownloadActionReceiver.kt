package com.afzal.zipclip

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent

/**
 * Handles Pause / Cancel taps on the download notification and forwards
 * them to Dart, which owns the download engine.
 */
class DownloadActionReceiver : BroadcastReceiver() {

    override fun onReceive(context: Context, intent: Intent) {
        val id = intent.getStringExtra("id") ?: return
        val action = intent.getStringExtra("action") ?: return
        ZipClipPlugin.instance?.onNotificationAction(id, action)
    }
}
