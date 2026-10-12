package com.afzal.zipclip

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Context
import android.content.Intent
import android.content.pm.ServiceInfo
import android.os.Build
import android.os.IBinder
import androidx.core.app.NotificationCompat
import androidx.core.content.ContextCompat

/**
 * Foreground service (type dataSync) that keeps downloads alive when the
 * app is closed. One notification per active download with live progress,
 * speed text, and Pause / Cancel actions.
 */
class DownloadService : Service() {

    private val active = mutableMapOf<String, TaskInfo>()
    private var inForeground = false

    private data class TaskInfo(
        val title: String,
        var progress: Double,
        var statusText: String,
    )

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onCreate() {
        super.onCreate()
        ensureChannel()
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        if (intent == null) return START_NOT_STICKY
        val id = intent.getStringExtra(EXTRA_ID) ?: return START_NOT_STICKY
        when (intent.getStringExtra(EXTRA_CMD)) {
            CMD_START -> {
                val title = intent.getStringExtra(EXTRA_TITLE) ?: "Downloading"
                active[id] = TaskInfo(title, 0.0, "Starting…")
                post(id)
                ensureForeground(id)
            }
            CMD_UPDATE -> {
                val info = active[id] ?: return START_NOT_STICKY
                info.progress = intent.getDoubleExtra(EXTRA_PROGRESS, 0.0)
                info.statusText = intent.getStringExtra(EXTRA_STATUS) ?: ""
                post(id)
            }
            CMD_STOP -> {
                active.remove(id)
                notificationManager().cancel(notificationId(id))
                if (active.isEmpty()) {
                    stopForeground(STOP_FOREGROUND_REMOVE)
                    inForeground = false
                    stopSelf()
                }
            }
        }
        return START_NOT_STICKY
    }

    private fun ensureForeground(firstId: String) {
        if (inForeground) return
        inForeground = true
        val notification = buildNotification(firstId, active[firstId]!!)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            startForeground(
                FOREGROUND_ID,
                notification,
                ServiceInfo.FOREGROUND_SERVICE_TYPE_DATA_SYNC,
            )
        } else {
            startForeground(FOREGROUND_ID, notification)
        }
    }

    private fun post(id: String) {
        val info = active[id] ?: return
        notificationManager().notify(notificationId(id), buildNotification(id, info))
    }

    private fun buildNotification(id: String, info: TaskInfo): Notification {
        val openApp = PendingIntent.getActivity(
            this,
            1001,
            packageManager.getLaunchIntentForPackage(packageName),
            PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT,
        )
        return NotificationCompat.Builder(this, CHANNEL_ID)
            .setContentTitle(info.title)
            .setContentText(info.statusText)
            .setSmallIcon(R.mipmap.ic_launcher)
            .setContentIntent(openApp)
            .setOngoing(true)
            .setOnlyAlertOnce(true)
            .setProgress(
                100,
                (info.progress * 100).toInt().coerceIn(0, 100),
                info.progress <= 0.0,
            )
            .addAction(
                android.R.drawable.ic_media_pause,
                "Pause",
                actionIntent(id, "pause"),
            )
            .addAction(
                android.R.drawable.ic_menu_close_clear_cancel,
                "Cancel",
                actionIntent(id, "cancel"),
            )
            .build()
    }

    private fun actionIntent(id: String, action: String): PendingIntent {
        val intent = Intent(ACTION_DOWNLOAD).apply {
            putExtra(EXTRA_ID, id)
            putExtra(EXTRA_ACTION, action)
        }
        return PendingIntent.getBroadcast(
            this,
            (id + action).hashCode(),
            intent,
            PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT,
        )
    }

    private fun ensureChannel() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
        val channel = NotificationChannel(
            CHANNEL_ID,
            "Downloads",
            NotificationManager.IMPORTANCE_LOW,
        ).apply {
            description = "Shows download progress with pause and cancel actions."
            setShowBadge(false)
        }
        notificationManager().createNotificationChannel(channel)
    }

    private fun notificationManager() =
        getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager

    companion object {
        const val CHANNEL_ID = "zipclip_downloads"
        const val ACTION_DOWNLOAD = "com.afzal.zipclip.DOWNLOAD_ACTION"
        private const val FOREGROUND_ID = 41
        private const val EXTRA_CMD = "cmd"
        private const val EXTRA_ID = "id"
        private const val EXTRA_TITLE = "title"
        private const val EXTRA_PROGRESS = "progress"
        private const val EXTRA_STATUS = "statusText"
        private const val EXTRA_ACTION = "action"
        private const val CMD_START = "start"
        private const val CMD_UPDATE = "update"
        private const val CMD_STOP = "stop"

        private fun notificationId(id: String) = 10000 + (id.hashCode() and 0x7FFF)

        private fun intent(
            context: Context,
            cmd: String,
            id: String,
            title: String = "",
            progress: Double = 0.0,
            statusText: String = "",
        ) = Intent(context, DownloadService::class.java).apply {
            putExtra(EXTRA_CMD, cmd)
            putExtra(EXTRA_ID, id)
            putExtra(EXTRA_TITLE, title)
            putExtra(EXTRA_PROGRESS, progress)
            putExtra(EXTRA_STATUS, statusText)
        }

        fun start(context: Context, id: String, title: String) {
            ContextCompat.startForegroundService(
                context,
                intent(context, CMD_START, id, title = title),
            )
        }

        fun update(
            context: Context,
            id: String,
            title: String,
            progress: Double,
            statusText: String,
        ) {
            // Plain startService is fine here: the service is already in the
            // foreground once started.
            context.startService(
                intent(
                    context,
                    CMD_UPDATE,
                    id,
                    title = title,
                    progress = progress,
                    statusText = statusText,
                ),
            )
        }

        fun stop(context: Context, id: String) {
            context.startService(intent(context, CMD_STOP, id))
        }
    }
}
