package com.afzal.zipclip

/**
 * Holds a shared link that arrived before the Flutter plugin was attached
 * (cold start from the share sheet). Drained by ZipClipPlugin on attach.
 */
object SharedLinkHolder {
    @Volatile
    var pending: String? = null
}
