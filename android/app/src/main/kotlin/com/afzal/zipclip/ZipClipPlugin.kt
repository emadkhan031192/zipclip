package com.afzal.zipclip

import android.content.ContentValues
import android.content.Context
import android.content.Intent
import android.net.ConnectivityManager
import android.net.NetworkCapabilities
import android.net.Uri
import android.os.Build
import android.os.Environment
import android.os.StatFs
import android.provider.MediaStore
import android.provider.Settings
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.io.FileInputStream

/**
 * Native bridge for ZipClip: MediaStore gallery saves, file open/share/
 * delete, storage & network info, foreground download service control,
 * "saved" notifications and the optional quick-save bubble.
 *
 * Every method degrades gracefully: Dart catches PlatformException /
 * MissingPluginException and keeps the app usable.
 */
class ZipClipPlugin : FlutterPlugin, MethodChannel.MethodCallHandler {

    private lateinit var channel: MethodChannel
    private var context: Context? = null

    /** A link stashed while Dart was not ready yet. */
    private var pendingSharedLink: String? = null

    /** True once Dart has pulled the initial link (init ran). */
    private var dartReady = false

    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        context = binding.applicationContext
        channel = MethodChannel(binding.binaryMessenger, CHANNEL)
        channel.setMethodCallHandler(this)
        instance = this
        // Drain any link that arrived before attach (cold start share).
        SharedLinkHolder.pending?.let {
            SharedLinkHolder.pending = null
            deliverSharedLink(it)
        }
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        channel.setMethodCallHandler(null)
        instance = null
        context = null
    }

    /** Called from MainActivity / BubbleService when a link is shared in. */
    fun deliverSharedLink(url: String) {
        if (dartReady) {
            try {
                channel.invokeMethod("onSharedLink", url)
                return
            } catch (_: Exception) {
                // Fall through and stash.
            }
        }
        pendingSharedLink = url
    }

    /** Called from DownloadActionReceiver for notification actions. */
    fun onNotificationAction(id: String, action: String) {
        try {
            channel.invokeMethod(
                "onNotificationAction",
                mapOf("id" to id, "action" to action),
            )
        } catch (_: Exception) {
        }
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "getInitialSharedLink" -> {
                dartReady = true
                val link = pendingSharedLink
                pendingSharedLink = null
                result.success(link)
            }
            "clearSharedLink" -> {
                pendingSharedLink = null
                result.success(null)
            }
            "saveToGallery" -> saveToGallery(call, result)
            "openMedia" -> openMedia(call, result)
            "shareMedia" -> shareMedia(call, result)
            "deleteMedia" -> deleteMedia(call, result)
            "getFreeSpaceBytes" -> result.success(freeSpaceBytes())
            "getNetworkType" -> result.success(networkType())
            "needsLegacyStoragePermission" ->
                result.success(Build.VERSION.SDK_INT < 29)
            "serviceStart" -> {
                val ctx = context
                if (ctx == null) {
                    result.success(null)
                    return
                }
                DownloadService.start(
                    ctx,
                    call.argument<String>("id") ?: "",
                    call.argument<String>("title") ?: "Downloading",
                )
                result.success(null)
            }
            "serviceUpdate" -> {
                val ctx = context
                if (ctx == null) {
                    result.success(null)
                    return
                }
                DownloadService.update(
                    ctx,
                    call.argument<String>("id") ?: "",
                    call.argument<String>("title") ?: "Downloading",
                    (call.argument<Double>("progress") ?: 0.0),
                    call.argument<String>("statusText") ?: "",
                )
                result.success(null)
            }
            "serviceStop" -> {
                val ctx = context
                if (ctx == null) {
                    result.success(null)
                    return
                }
                DownloadService.stop(ctx, call.argument<String>("id") ?: "")
                result.success(null)
            }
            "notifySaved" -> {
                val ctx = context
                if (ctx == null) {
                    result.success(null)
                    return
                }
                NotificationHelper.notifySaved(
                    ctx,
                    call.argument<String>("title") ?: "Video",
                    call.argument<Boolean>("vibrate") ?: true,
                )
                result.success(null)
            }
            "setBubbleEnabled" -> {
                val ctx = context
                if (ctx == null) {
                    result.success(null)
                    return
                }
                BubbleService.setEnabled(
                    ctx,
                    call.argument<Boolean>("enabled") ?: false,
                )
                result.success(null)
            }
            "hasOverlayPermission" ->
                result.success(
                    context?.let { Settings.canDrawOverlays(it) } ?: false,
                )
            "requestOverlayPermission" -> {
                val ctx = context
                if (ctx != null) {
                    val intent = Intent(
                        Settings.ACTION_MANAGE_OVERLAY_PERMISSION,
                        Uri.parse("package:${ctx.packageName}"),
                    ).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                    ctx.startActivity(intent)
                }
                result.success(null)
            }
            else -> result.notImplemented()
        }
    }

    // ------------------------------------------------------------ MediaStore

    private fun saveToGallery(call: MethodCall, result: MethodChannel.Result) {
        val ctx = context ?: run {
            result.error("NO_CONTEXT", "Plugin not attached", null)
            return
        }
        val path = call.argument<String>("path")
        val displayName = call.argument<String>("displayName")
        val collection = call.argument<String>("collection") ?: "video"
        val subfolder = call.argument<String>("subfolder")?.trim()
            .takeIf { !it.isNullOrEmpty() } ?: "ZipClip"
        if (path == null || displayName == null) {
            result.error("BAD_ARGS", "path and displayName are required", null)
            return
        }
        try {
            val (collectionUri, relativePath, mime) = when (collection) {
                "audio" -> Triple(
                    MediaStore.Audio.Media.EXTERNAL_CONTENT_URI,
                    "Music/$subfolder",
                    "audio/mpeg",
                )
                "image" -> Triple(
                    MediaStore.Images.Media.EXTERNAL_CONTENT_URI,
                    "Pictures/$subfolder",
                    "image/jpeg",
                )
                else -> Triple(
                    MediaStore.Video.Media.EXTERNAL_CONTENT_URI,
                    "Movies/$subfolder",
                    "video/mp4",
                )
            }
            val resolver = ctx.contentResolver
            val values = ContentValues().apply {
                put(MediaStore.MediaColumns.DISPLAY_NAME, displayName)
                put(MediaStore.MediaColumns.MIME_TYPE, mime)
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                    put(MediaStore.MediaColumns.RELATIVE_PATH, relativePath)
                    put(MediaStore.MediaColumns.IS_PENDING, 1)
                }
            }
            val uri = resolver.insert(collectionUri, values)
                ?: throw IllegalStateException("MediaStore insert failed")
            try {
                resolver.openOutputStream(uri)?.use { out ->
                    FileInputStream(File(path)).use { input ->
                        input.copyTo(out)
                    }
                } ?: throw IllegalStateException("openOutputStream failed")
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                    val done = ContentValues().apply {
                        put(MediaStore.MediaColumns.IS_PENDING, 0)
                    }
                    resolver.update(uri, done, null, null)
                }
                result.success(uri.toString())
            } catch (e: Exception) {
                resolver.delete(uri, null, null)
                throw e
            }
        } catch (e: Exception) {
            result.error("SAVE_FAILED", e.message, null)
        }
    }

    private fun openMedia(call: MethodCall, result: MethodChannel.Result) {
        val ctx = context ?: run {
            result.success(false)
            return
        }
        try {
            val uri = Uri.parse(call.argument<String>("uri") ?: "")
            val mime = call.argument<String>("mimeType") ?: "*/*"
            val intent = Intent(Intent.ACTION_VIEW).apply {
                setDataAndType(uri, mime)
                addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
                addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            }
            val resolved = if (Build.VERSION.SDK_INT >= 33) {
                ctx.packageManager.resolveActivity(
                    intent,
                    android.content.pm.PackageManager.ResolveInfoFlags.of(0),
                )
            } else {
                @Suppress("DEPRECATION")
                ctx.packageManager.resolveActivity(intent, 0)
            }
            if (resolved == null) {
                result.success(false)
                return
            }
            ctx.startActivity(intent)
            result.success(true)
        } catch (_: Exception) {
            result.success(false)
        }
    }

    private fun shareMedia(call: MethodCall, result: MethodChannel.Result) {
        val ctx = context ?: run {
            result.success(null)
            return
        }
        try {
            val uri = Uri.parse(call.argument<String>("uri") ?: "")
            val mime = call.argument<String>("mimeType") ?: "*/*"
            val send = Intent(Intent.ACTION_SEND).apply {
                type = mime
                putExtra(Intent.EXTRA_STREAM, uri)
                addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
            }
            val chooser = Intent.createChooser(send, "Share").apply {
                addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            }
            ctx.startActivity(chooser)
            result.success(null)
        } catch (e: Exception) {
            result.error("SHARE_FAILED", e.message, null)
        }
    }

    private fun deleteMedia(call: MethodCall, result: MethodChannel.Result) {
        val ctx = context ?: run {
            result.success(false)
            return
        }
        result.success(
            try {
                val uri = Uri.parse(call.argument<String>("uri") ?: "")
                ctx.contentResolver.delete(uri, null, null) > 0
            } catch (_: Exception) {
                false
            },
        )
    }

    // ---------------------------------------------------------------- info

    private fun freeSpaceBytes(): Long {
        return try {
            @Suppress("DEPRECATION")
            val path = Environment.getExternalStorageDirectory().path
            StatFs(path).availableBytes
        } catch (_: Exception) {
            -1L
        }
    }

    private fun networkType(): String {
        val ctx = context ?: return "unknown"
        return try {
            val cm =
                ctx.getSystemService(Context.CONNECTIVITY_SERVICE) as ConnectivityManager
            val caps = cm.getNetworkCapabilities(cm.activeNetwork)
                ?: return "none"
            when {
                caps.hasTransport(NetworkCapabilities.TRANSPORT_WIFI) -> "wifi"
                caps.hasTransport(NetworkCapabilities.TRANSPORT_CELLULAR) -> "cellular"
                else -> "unknown"
            }
        } catch (_: Exception) {
            "unknown"
        }
    }

    companion object {
        const val CHANNEL = "com.afzal.zipclip/native"

        @Volatile
        var instance: ZipClipPlugin? = null
            private set
    }
}
