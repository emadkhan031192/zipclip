import 'dart:async';
import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../engine/file_naming.dart';
import '../models/media.dart';

/// All user settings. Persisted with SharedPreferences; streamed to the UI.
class AppSettings {
  const AppSettings({
    required this.saveSubfolder,
    required this.defaultQuality,
    required this.defaultFormat,
    required this.removeWatermarkDefault,
    required this.wifiOnly,
    required this.startSavingRightAway,
    required this.maxParallel,
    required this.fileNameTemplate,
    required this.detectClipboardLinks,
    required this.quickSaveBubble,
    required this.progressNotification,
    required this.vibrateOnSaved,
    required this.keepHistory,
    required this.firstRunDone,
  });

  static const defaults = AppSettings(
    saveSubfolder: 'ZipClip',
    defaultQuality: '1080p',
    defaultFormat: SaveFormat.video,
    removeWatermarkDefault: true,
    wifiOnly: false,
    startSavingRightAway: true,
    maxParallel: 2,
    fileNameTemplate: FileNameTemplate.defaultTemplate,
    detectClipboardLinks: true,
    quickSaveBubble: false,
    progressNotification: true,
    vibrateOnSaved: true,
    keepHistory: true,
    firstRunDone: false,
  );

  final String saveSubfolder;
  final String defaultQuality;
  final SaveFormat defaultFormat;
  final bool removeWatermarkDefault;
  final bool wifiOnly;
  final bool startSavingRightAway;
  final int maxParallel; // 1..5
  final String fileNameTemplate;
  final bool detectClipboardLinks;
  final bool quickSaveBubble;
  final bool progressNotification;
  final bool vibrateOnSaved;
  final bool keepHistory;
  final bool firstRunDone;

  AppSettings copyWith({
    String? saveSubfolder,
    String? defaultQuality,
    SaveFormat? defaultFormat,
    bool? removeWatermarkDefault,
    bool? wifiOnly,
    bool? startSavingRightAway,
    int? maxParallel,
    String? fileNameTemplate,
    bool? detectClipboardLinks,
    bool? quickSaveBubble,
    bool? progressNotification,
    bool? vibrateOnSaved,
    bool? keepHistory,
    bool? firstRunDone,
  }) =>
      AppSettings(
        saveSubfolder: saveSubfolder ?? this.saveSubfolder,
        defaultQuality: defaultQuality ?? this.defaultQuality,
        defaultFormat: defaultFormat ?? this.defaultFormat,
        removeWatermarkDefault:
            removeWatermarkDefault ?? this.removeWatermarkDefault,
        wifiOnly: wifiOnly ?? this.wifiOnly,
        startSavingRightAway:
            startSavingRightAway ?? this.startSavingRightAway,
        maxParallel: maxParallel?.clamp(1, 5) ?? this.maxParallel,
        fileNameTemplate: fileNameTemplate ?? this.fileNameTemplate,
        detectClipboardLinks:
            detectClipboardLinks ?? this.detectClipboardLinks,
        quickSaveBubble: quickSaveBubble ?? this.quickSaveBubble,
        progressNotification:
            progressNotification ?? this.progressNotification,
        vibrateOnSaved: vibrateOnSaved ?? this.vibrateOnSaved,
        keepHistory: keepHistory ?? this.keepHistory,
        firstRunDone: firstRunDone ?? this.firstRunDone,
      );

  Map<String, dynamic> toJson() => {
        'saveSubfolder': saveSubfolder,
        'defaultQuality': defaultQuality,
        'defaultFormat': defaultFormat.name,
        'removeWatermarkDefault': removeWatermarkDefault,
        'wifiOnly': wifiOnly,
        'startSavingRightAway': startSavingRightAway,
        'maxParallel': maxParallel,
        'fileNameTemplate': fileNameTemplate,
        'detectClipboardLinks': detectClipboardLinks,
        'quickSaveBubble': quickSaveBubble,
        'progressNotification': progressNotification,
        'vibrateOnSaved': vibrateOnSaved,
        'keepHistory': keepHistory,
        'firstRunDone': firstRunDone,
      };

  factory AppSettings.fromJson(Map<String, dynamic> json) {
    final d = AppSettings.defaults;
    SaveFormat formatFrom(String? name) {
      if (name == null) return d.defaultFormat;
      return SaveFormat.values.asNameMap()[name] ?? d.defaultFormat;
    }

    return AppSettings(
      saveSubfolder: json['saveSubfolder'] as String? ?? d.saveSubfolder,
      defaultQuality: json['defaultQuality'] as String? ?? d.defaultQuality,
      defaultFormat: formatFrom(json['defaultFormat'] as String?),
      removeWatermarkDefault:
          json['removeWatermarkDefault'] as bool? ?? d.removeWatermarkDefault,
      wifiOnly: json['wifiOnly'] as bool? ?? d.wifiOnly,
      startSavingRightAway:
          json['startSavingRightAway'] as bool? ?? d.startSavingRightAway,
      maxParallel:
          (json['maxParallel'] as num?)?.toInt().clamp(1, 5) ?? d.maxParallel,
      fileNameTemplate:
          json['fileNameTemplate'] as String? ?? d.fileNameTemplate,
      detectClipboardLinks:
          json['detectClipboardLinks'] as bool? ?? d.detectClipboardLinks,
      quickSaveBubble:
          json['quickSaveBubble'] as bool? ?? d.quickSaveBubble,
      progressNotification:
          json['progressNotification'] as bool? ?? d.progressNotification,
      vibrateOnSaved: json['vibrateOnSaved'] as bool? ?? d.vibrateOnSaved,
      keepHistory: json['keepHistory'] as bool? ?? d.keepHistory,
      firstRunDone: json['firstRunDone'] as bool? ?? d.firstRunDone,
    );
  }
}

class SettingsRepository {
  SettingsRepository._(this._prefs, AppSettings initial)
      : _current = initial,
        _controller = StreamController<AppSettings>.broadcast() {
    _controller.add(initial);
  }

  final SharedPreferences _prefs;
  final StreamController<AppSettings> _controller;
  AppSettings _current;

  static const _key = 'zipclip_settings_v1';

  static Future<SettingsRepository> load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_key);
    AppSettings initial = AppSettings.defaults;
    if (raw != null) {
      try {
        initial = AppSettings.fromJson(
            Map<String, dynamic>.from(jsonDecode(raw) as Map),);
      } catch (_) {
        // Corrupt prefs: fall back to defaults.
      }
    }
    return SettingsRepository._(prefs, initial);
  }

  AppSettings get current => _current;
  Stream<AppSettings> get stream => _controller.stream;

  Future<void> update(AppSettings settings) async {
    _current = settings;
    await _prefs.setString(_key, jsonEncode(settings.toJson()));
    _controller.add(settings);
  }

  void dispose() => _controller.close();
}
