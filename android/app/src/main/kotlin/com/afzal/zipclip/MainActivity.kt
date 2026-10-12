package com.afzal.zipclip

import android.content.Intent
import android.os.Bundle
import android.util.Patterns
import io.flutter.embedding.android.FlutterActivity

class MainActivity : FlutterActivity() {

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        handleIntent(intent)
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        handleIntent(intent)
    }

    private fun handleIntent(intent: Intent?) {
        if (intent == null) return

        // 1. System share sheet: ACTION_SEND with text/plain.
        if (intent.action == Intent.ACTION_SEND && intent.type == "text/plain") {
            val text = intent.getCharSequenceExtra(Intent.EXTRA_TEXT)?.toString()
                ?: intent.getCharSequenceExtra(Intent.EXTRA_SUBJECT)?.toString()
            val url = extractUrl(text)
            if (url != null) deliver(url)
        }

        // 2. Quick-save bubble tap.
        intent.getStringExtra("zipclip_shared_link")?.let { link ->
            intent.removeExtra("zipclip_shared_link")
            deliver(link)
        }
    }

    private fun deliver(url: String) {
        val plugin = ZipClipPlugin.instance
        if (plugin != null) {
            plugin.deliverSharedLink(url)
        } else {
            // Plugin not attached yet (cold start): stash for it.
            SharedLinkHolder.pending = url
        }
    }

    private fun extractUrl(text: String?): String? {
        if (text.isNullOrBlank()) return null
        val trimmed = text.trim()
        if (trimmed.startsWith("http://") || trimmed.startsWith("https://")) {
            // The whole text is the link (may carry trailing whitespace).
            return trimmed.split("\\s".toRegex()).first()
        }
        val matcher = Patterns.WEB_URL.matcher(trimmed)
        return if (matcher.find()) matcher.group() else null
    }
}
