package com.afzal.zipclip

import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.Service
import android.content.ClipboardManager
import android.content.Context
import android.content.Intent
import android.graphics.PixelFormat
import android.os.Build
import android.os.IBinder
import android.provider.Settings
import android.view.Gravity
import android.view.MotionEvent
import android.view.View
import android.view.WindowManager
import android.widget.FrameLayout
import android.widget.ImageView
import androidx.core.app.NotificationCompat
import androidx.core.content.ContextCompat
import kotlin.math.abs

/**
 * Optional floating quick-save bubble. Watches the clipboard; when a link
 * is copied, a small draggable bubble appears. Tapping it opens ZipClip
 * with the link ready to save.
 *
 * Runs only when the user enables it in Settings (which requests the
 * "Display over other apps" permission first).
 */
class BubbleService : Service() {

    private lateinit var windowManager: WindowManager
    private lateinit var clipboard: ClipboardManager
    private var bubble: View? = null
    private var bubbleLink: String? = null
    private var params: WindowManager.LayoutParams? = null

    private val clipListener =
        ClipboardManager.OnPrimaryClipChangedListener { checkClipboard() }

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onCreate() {
        super.onCreate()
        ensureChannel()
        val notification = NotificationCompat.Builder(this, CHANNEL_ID)
            .setContentTitle("Quick-save bubble is on")
            .setContentText("Copy a video link, then tap the bubble to save it.")
            .setSmallIcon(R.mipmap.ic_launcher)
            .setOngoing(true)
            .setShowWhen(false)
            .build()
        startForeground(FOREGROUND_ID, notification)

        windowManager = getSystemService(WINDOW_SERVICE) as WindowManager
        clipboard =
            getSystemService(Context.CLIPBOARD_SERVICE) as ClipboardManager
        clipboard.addPrimaryClipChangedListener(clipListener)
        checkClipboard()
    }

    override fun onDestroy() {
        clipboard.removePrimaryClipChangedListener(clipListener)
        removeBubble()
        super.onDestroy()
    }

    private fun checkClipboard() {
        if (!Settings.canDrawOverlays(this)) {
            removeBubble()
            return
        }
        val text = clipboard.primaryClip
            ?.takeIf { it.itemCount > 0 }
            ?.getItemAt(0)
            ?.coerceToText(this)
            ?.toString()
            ?.trim()
        if (text != null &&
            (text.startsWith("http://") || text.startsWith("https://"))
        ) {
            showBubble(text)
        } else {
            removeBubble()
        }
    }

    private fun showBubble(link: String) {
        bubbleLink = link
        if (bubble != null) return
        val density = resources.displayMetrics.density
        val size = (60 * density).toInt()

        val icon = ImageView(this).apply {
            setImageResource(R.mipmap.ic_launcher)
            scaleType = ImageView.ScaleType.CENTER_CROP
        }
        val frame = FrameLayout(this).apply {
            addView(
                icon,
                FrameLayout.LayoutParams(
                    FrameLayout.LayoutParams.MATCH_PARENT,
                    FrameLayout.LayoutParams.MATCH_PARENT,
                ),
            )
            // Circular outline so the icon reads as a bubble.
            outlineProvider = object : android.view.ViewOutlineProvider() {
                override fun getOutline(
                    view: View,
                    outline: android.graphics.Outline,
                ) {
                    outline.setOval(0, 0, view.width, view.height)
                }
            }
            clipToOutline = true
            elevation = 8 * density
        }

        val overlayType = if (Build.VERSION.SDK_INT >=
            Build.VERSION_CODES.O
        ) {
            WindowManager.LayoutParams.TYPE_APPLICATION_OVERLAY
        } else {
            // API 24-25: overlay bubbles need the legacy phone-window type
            // (still gated by the "display over other apps" permission).
            @Suppress("DEPRECATION")
            WindowManager.LayoutParams.TYPE_PHONE
        }
        val lp = WindowManager.LayoutParams(
            size,
            size,
            overlayType,
            WindowManager.LayoutParams.FLAG_NOT_FOCUSABLE,
            PixelFormat.TRANSLUCENT,
        ).apply {
            gravity = Gravity.TOP or Gravity.START
            x = (16 * density).toInt()
            y = (320 * density).toInt()
        }
        params = lp

        var downX = 0f
        var downY = 0f
        var startX = 0
        var startY = 0
        frame.setOnTouchListener { v, event ->
            when (event.action) {
                MotionEvent.ACTION_DOWN -> {
                    downX = event.rawX
                    downY = event.rawY
                    startX = lp.x
                    startY = lp.y
                    true
                }
                MotionEvent.ACTION_MOVE -> {
                    lp.x = startX + (event.rawX - downX).toInt()
                    lp.y = startY + (event.rawY - downY).toInt()
                    windowManager.updateViewLayout(v, lp)
                    true
                }
                MotionEvent.ACTION_UP -> {
                    if (abs(event.rawX - downX) < 12 * density &&
                        abs(event.rawY - downY) < 12 * density
                    ) {
                        openAppWithLink()
                    }
                    true
                }
                else -> false
            }
        }

        windowManager.addView(frame, lp)
        bubble = frame
    }

    private fun openAppWithLink() {
        val link = bubbleLink
        removeBubble()
        if (link == null) return
        // Prefer the live plugin so an already-running app handles it.
        val plugin = ZipClipPlugin.instance
        if (plugin != null) {
            plugin.deliverSharedLink(link)
            val launch = packageManager.getLaunchIntentForPackage(packageName)
            if (launch != null) startActivity(launch)
        } else {
            val launch = packageManager.getLaunchIntentForPackage(packageName)
                ?.apply {
                    putExtra("zipclip_shared_link", link)
                    addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                }
            if (launch != null) startActivity(launch)
        }
    }

    private fun removeBubble() {
        bubble?.let {
            try {
                windowManager.removeView(it)
            } catch (_: Exception) {
            }
        }
        bubble = null
        bubbleLink = null
    }

    private fun ensureChannel() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
        val channel = NotificationChannel(
            CHANNEL_ID,
            "Quick-save bubble",
            NotificationManager.IMPORTANCE_MIN,
        ).apply {
            description = "Keeps the optional quick-save bubble running."
            setShowBadge(false)
        }
        val manager =
            getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        manager.createNotificationChannel(channel)
    }

    companion object {
        private const val CHANNEL_ID = "zipclip_bubble"
        private const val FOREGROUND_ID = 42

        fun setEnabled(context: Context, enabled: Boolean) {
            val intent = Intent(context, BubbleService::class.java)
            if (enabled) {
                ContextCompat.startForegroundService(context, intent)
            } else {
                context.stopService(intent)
            }
        }
    }
}
