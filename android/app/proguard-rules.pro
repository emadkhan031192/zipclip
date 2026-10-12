# Keep the MethodChannel surface used by Dart.
-keep class com.afzal.zipclip.ZipClipPlugin { *; }
-keep class com.afzal.zipclip.MainActivity { *; }
-keep class com.afzal.zipclip.DownloadService { *; }
-keep class com.afzal.zipclip.DownloadActionReceiver { *; }
-keep class com.afzal.zipclip.BubbleService { *; }
-keep class com.afzal.zipclip.NotificationHelper { *; }
-keep class com.afzal.zipclip.SharedLinkHolder { *; }

# Flutter plugins: keep generated registrant + plugin entry points.
-keep class io.flutter.plugins.** { *; }

# sqflite / path_provider / permission_handler use reflection lightly.
-keep class com.tekartik.** { *; }
-dontwarn com.tekartik.**

# video_thumbnail JNI entry points.
-keep class xyz.justsoft.video_thumbnail.** { *; }
-dontwarn xyz.justsoft.**

# Dio / OkHttp are used by Flutter plugins through reflection.
-dontwarn okhttp3.**
-dontwarn okio.**
