package com.afzal.zipclip

import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.os.Build
import androidx.core.app.NotificationCompat

/**
 * One-shot "Video saved" notification. Shown only when the user enabled
 * alerts; vibrates when "Vibrate when saved" is on. On Android 13+, if the
 * user denied notifications, the system silently drops it — by design.
 */
object NotificationHelper {

    private const val CHANNEL_ID = "zipclip_alerts"

    fun notifySaved(context: Context, title: String, vibrate: Boolean) {
        ensureChannel(context)
        val openApp = PendingIntent.getActivity(
            context,
            2001,
            context.packageManager.getLaunchIntentForPackage(context.packageName),
            PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT,
        )
        val notification = NotificationCompat.Builder(context, CHANNEL_ID)
            .setContentTitle("Video saved")
            .setContentText(title)
            .setSmallIcon(R.mipmap.ic_launcher)
            .setContentIntent(openApp)
            .setAutoCancel(true)
            .apply {
                if (vibrate) setVibrate(longArrayOf(0, 120, 80, 120))
            }
            .build()
        val manager =
            context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        try {
            manager.notify(20000 + (title.hashCode() and 0x7FFF), notification)
        } catch (_: SecurityException) {
            // Notifications not allowed: stay quiet.
        }
    }

    private fun ensureChannel(context: Context) {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
        val channel = NotificationChannel(
            CHANNEL_ID,
            "Alerts",
            NotificationManager.IMPORTANCE_DEFAULT,
        ).apply {
            description = "Tells you when a video has finished saving."
            setShowBadge(false)
        }
        val manager =
            context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        manager.createNotificationChannel(channel)
    }
}
