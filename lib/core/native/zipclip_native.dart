import 'dart:io';

import 'package:flutter/services.dart';

import '../engine/download_engine.dart';

/// Bridge to the native Android code (ZipClipPlugin + DownloadService +
/// BubbleService). Everything here degrades gracefully when the platform
/// channel is unavailable (e.g. in tests): callers must catch
/// [MissingPluginException]/[PlatformException].
class ZipClipNative {
  ZipClipNative();

  static const MethodChannel _channel =
      MethodChannel('com.afzal.zipclip/native');

  /// Fired when the user shares a link into ZipClip from another app.
  void Function(String url)? onSharedLink;

  /// Fired when the user taps a notification action (pause/resume/cancel).
  void Function(String id, String action)? onNotificationAction;

  bool _handlerSet = false;

  /// Installs the native->Dart handler and pulls any link that arrived
  /// before Dart was ready (cold start from the share sheet).
  Future<void> init() async {
    if (_handlerSet) return;
    _handlerSet = true;
    _channel.setMethodCallHandler(_handle);
    try {
      final initial =
          await _channel.invokeMethod<String>('getInitialSharedLink');
      if (initial != null && initial.isNotEmpty) {
        await _channel.invokeMethod('clearSharedLink');
        onSharedLink?.call(initial);
      }
    } on PlatformException catch (_) {
      // Not on Android / channel unavailable.
    } on MissingPluginException catch (_) {}
  }

  Future<void> _handle(MethodCall call) async {
    switch (call.method) {
      case 'onSharedLink':
        final url = call.arguments as String?;
        if (url != null && url.isNotEmpty) onSharedLink?.call(url);
      case 'onNotificationAction':
        final args = Map<String, dynamic>.from(call.arguments as Map);
        onNotificationAction
            ?.call(args['id'] as String, args['action'] as String);
    }
  }

  /// Bytes of free space on the primary shared storage, or null if unknown.
  Future<int?> getFreeSpaceBytes() async {
    try {
      return await _channel.invokeMethod<int>('getFreeSpaceBytes');
    } on PlatformException catch (_) {
      return null;
    } on MissingPluginException catch (_) {
      return null;
    }
  }

  /// 'wifi', 'cellular', 'none', or 'unknown'.
  Future<String> getNetworkType() async {
    try {
      final t = await _channel.invokeMethod<String>('getNetworkType');
      return t ?? 'unknown';
    } on PlatformException catch (_) {
      return 'unknown';
    } on MissingPluginException catch (_) {
      return 'unknown';
    }
  }

  /// Opens [uri] (a MediaStore content URI) in the system player/viewer.
  Future<bool> openMedia(String uri, String mimeType) async {
    try {
      final ok = await _channel.invokeMethod<bool>(
        'openMedia',
        {'uri': uri, 'mimeType': mimeType},
      );
      return ok ?? false;
    } on PlatformException catch (_) {
      return false;
    } on MissingPluginException catch (_) {
      return false;
    }
  }

  Future<void> setBubbleEnabled(bool enabled) async {
    try {
      await _channel.invokeMethod('setBubbleEnabled', {'enabled': enabled});
    } on PlatformException catch (_) {} on MissingPluginException catch (_) {}
  }

  Future<bool> hasOverlayPermission() async {
    try {
      return await _channel.invokeMethod<bool>('hasOverlayPermission') ?? false;
    } on PlatformException catch (_) {
      return false;
    } on MissingPluginException catch (_) {
      return false;
    }
  }

  /// Opens the system "Display over other apps" settings page for ZipClip.
  Future<void> requestOverlayPermission() async {
    try {
      await _channel.invokeMethod('requestOverlayPermission');
    } on PlatformException catch (_) {} on MissingPluginException catch (_) {}
  }

  /// Shares a saved file (MediaStore content URI) via the system sheet.
  Future<void> shareMedia(String uri, String mimeType) async {
    try {
      await _channel.invokeMethod('shareMedia', {
        'uri': uri,
        'mimeType': mimeType,
      });
    } on PlatformException catch (_) {} on MissingPluginException catch (_) {}
  }

  /// Deletes a MediaStore entry by content URI.
  Future<bool> deleteMedia(String uri) async {
    try {
      return await _channel.invokeMethod<bool>('deleteMedia', {'uri': uri}) ??
          false;
    } on PlatformException catch (_) {
      return false;
    } on MissingPluginException catch (_) {
      return false;
    }
  }

  /// Renders a video frame to a JPEG at [outPath]; null when unavailable.
  Future<String?> videoThumbnail(String videoPath, String outPath) async {
    try {
      return await _channel.invokeMethod<String>('getVideoThumbnail', {
        'videoPath': videoPath,
        'outPath': outPath,
      });
    } on PlatformException catch (_) {
      return null;
    } on MissingPluginException catch (_) {
      return null;
    }
  }
}

/// Foreground service control backed by the native DownloadService.
class NativeForegroundControl implements ForegroundControl {
  NativeForegroundControl(this._native);

  final ZipClipNative _native;
  static const _ch = ZipClipNative._channel;

  @override
  Future<void> start(String id, String title) async {
    try {
      await _ch.invokeMethod('serviceStart', {'id': id, 'title': title});
    } on PlatformException catch (_) {} on MissingPluginException catch (_) {}
  }

  @override
  Future<void> update(
      String id, String title, double progress, String statusText,) async {
    try {
      await _ch.invokeMethod('serviceUpdate', {
        'id': id,
        'title': title,
        'progress': progress,
        'statusText': statusText,
      });
    } on PlatformException catch (_) {} on MissingPluginException catch (_) {}
  }

  @override
  Future<void> stop(String id) async {
    try {
      await _ch.invokeMethod('serviceStop', {'id': id});
    } on PlatformException catch (_) {} on MissingPluginException catch (_) {}
  }

  @override
  Future<void> notifySaved(String title, {required bool vibrate}) async {
    try {
      await _ch.invokeMethod('notifySaved', {
        'title': title,
        'vibrate': vibrate,
      });
    } on PlatformException catch (_) {} on MissingPluginException catch (_) {}
  }

  ZipClipNative get native => _native;
}

/// Saves finished files into the public gallery via MediaStore.
class NativeFilePlacer implements FinishedFilePlacer {
  NativeFilePlacer();

  static const _ch = ZipClipNative._channel;

  @override
  Future<String> place({
    required File file,
    required String displayName,
    required MediaCollection collection,
    required String subfolder,
  }) async {
    final uri = await _ch.invokeMethod<String>('saveToGallery', {
      'path': file.path,
      'displayName': displayName,
      'collection': collection.name, // video | audio | image
      'subfolder': subfolder,
    });
    if (uri == null || uri.isEmpty) {
      throw const FileSystemException('MediaStore save failed');
    }
    return uri;
  }
}

/// Wi-Fi check backed by ConnectivityManager.
class NativeNetworkChecker implements NetworkChecker {
  NativeNetworkChecker(this._native);

  final ZipClipNative _native;

  @override
  Future<bool> get isWifi async =>
      (await _native.getNetworkType()) == 'wifi';
}

/// Video thumbnails via the platform ThumbnailUtils (no extra plugin).
class NativeThumbnailer implements Thumbnailer {
  NativeThumbnailer(this._native);

  final ZipClipNative _native;

  @override
  Future<String?> videoThumbnail(String videoPath, String outPath) =>
      _native.videoThumbnail(videoPath, outPath);
}
