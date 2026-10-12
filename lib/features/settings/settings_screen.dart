import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:permission_handler/permission_handler.dart';

import '../../core/engine/file_naming.dart';
import '../../core/models/media.dart';
import '../../core/storage/settings.dart';
import '../../core/theme/app_theme.dart';
import '../../core/theme/pressable.dart';
import '../../core/widgets/zip_widgets.dart';
import '../../providers/bootstrap.dart';

class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key});

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  bool _overlayGranted = false;
  PermissionStatus _notifStatus = PermissionStatus.denied;

  @override
  void initState() {
    super.initState();
    _refreshPermissionStates();
  }

  Future<void> _refreshPermissionStates() async {
    final native = ref.read(nativeProvider);
    final overlay = await native.hasOverlayPermission();
    final notif = await Permission.notification.status;
    if (mounted) {
      setState(() {
        _overlayGranted = overlay;
        _notifStatus = notif;
      });
    }
  }

  Future<void> _update(AppSettings Function(AppSettings) fn) async {
    final repo = await ref.read(settingsRepoProvider.future);
    await repo.update(fn(repo.current));
  }

  @override
  Widget build(BuildContext context) {
    final settings = ref.watch(settingsProvider);

    return settings.when(
      data: (s) => ListView(
        padding: const EdgeInsets.fromLTRB(20, 14, 20, 24),
        children: [
          const Text(
            'Settings',
            style: TextStyle(
              fontFamily: ZipFonts.heading,
              fontWeight: FontWeight.w800,
              fontSize: 30,
              color: ZipColors.text,
            ),
          ),
          const SectionLabel('DOWNLOADS'),
          SettingRow(
            title: 'Save folder',
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'Movies/${s.saveSubfolder}',
                  style: ZipTheme.mono(size: 13, color: ZipColors.muted),
                ),
                const SizedBox(width: 6),
                const Icon(Icons.chevron_right_rounded,
                    color: ZipColors.muted,),
              ],
            ),
            onTap: () => _editSaveFolder(s),
            semanticLabel: 'Change save folder',
          ),
          const SizedBox(height: 10),
          SettingRow(
            title: 'Default quality',
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  s.defaultQuality,
                  style: ZipTheme.mono(size: 13, color: ZipColors.muted),
                ),
                const SizedBox(width: 6),
                const Icon(Icons.chevron_right_rounded,
                    color: ZipColors.muted,),
              ],
            ),
            onTap: () => _pickQuality(s),
            semanticLabel: 'Change default quality',
          ),
          const SizedBox(height: 10),
          SettingRow(
            title: 'Default format',
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  s.defaultFormat.label,
                  style: const TextStyle(
                    fontFamily: ZipFonts.ui,
                    fontSize: 13,
                    color: ZipColors.muted,
                  ),
                ),
                const SizedBox(width: 6),
                const Icon(Icons.chevron_right_rounded,
                    color: ZipColors.muted,),
              ],
            ),
            onTap: () => _pickFormat(s),
            semanticLabel: 'Change default format',
          ),
          const SizedBox(height: 10),
          SettingRow(
            title: 'Remove watermark by default',
            trailing: Switch(
              value: s.removeWatermarkDefault,
              onChanged: (v) =>
                  _update((s) => s.copyWith(removeWatermarkDefault: v)),
            ),
          ),
          const SizedBox(height: 10),
          SettingRow(
            title: 'Wi-Fi only',
            subtitle: 'Pause downloads on mobile data',
            trailing: Switch(
              value: s.wifiOnly,
              onChanged: (v) async {
                await _update((s) => s.copyWith(wifiOnly: v));
                final engine =
                    await ref.read(engineProvider.future);
                await engine.recheckNetwork();
              },
            ),
          ),
          const SizedBox(height: 10),
          SettingRow(
            title: 'Start saving right away',
            subtitle: 'Shared links begin downloading immediately',
            trailing: Switch(
              value: s.startSavingRightAway,
              onChanged: (v) =>
                  _update((s) => s.copyWith(startSavingRightAway: v)),
            ),
          ),
          const SizedBox(height: 10),
          SettingRow(
            title: 'Max parallel downloads',
            trailing: _stepper(s),
          ),
          const SizedBox(height: 10),
          SettingRow(
            title: 'File name template',
            subtitle: s.fileNameTemplate,
            trailing: const Icon(Icons.chevron_right_rounded,
                color: ZipColors.muted,),
            onTap: () => _editTemplate(s),
            semanticLabel: 'Change file name template',
          ),
          const SectionLabel('CLIPBOARD'),
          SettingRow(
            title: 'Detect copied links',
            subtitle: 'Offer a one-tap download card',
            trailing: Switch(
              value: s.detectClipboardLinks,
              onChanged: (v) =>
                  _update((s) => s.copyWith(detectClipboardLinks: v)),
            ),
          ),
          const SizedBox(height: 10),
          SettingRow(
            title: 'Quick-save bubble',
            subtitle:
                'Floating button when you copy a link (needs "Display over other apps")',
            trailing: Switch(
              value: s.quickSaveBubble,
              onChanged: _toggleBubble,
            ),
          ),
          const SectionLabel('ALERTS'),
          SettingRow(
            title: 'Progress notification',
            subtitle: 'Live progress while saving',
            trailing: Switch(
              value: s.progressNotification,
              onChanged: (v) =>
                  _update((s) => s.copyWith(progressNotification: v)),
            ),
          ),
          const SizedBox(height: 10),
          SettingRow(
            title: 'Vibrate when saved',
            trailing: Switch(
              value: s.vibrateOnSaved,
              onChanged: (v) =>
                  _update((s) => s.copyWith(vibrateOnSaved: v)),
            ),
          ),
          const SectionLabel('PRIVACY'),
          SettingRow(
            title: 'Keep download history',
            subtitle: 'Powers duplicate detection and Recent',
            trailing: Switch(
              value: s.keepHistory,
              onChanged: (v) =>
                  _update((s) => s.copyWith(keepHistory: v)),
            ),
          ),
          const SizedBox(height: 10),
          SettingRow(
            title: 'Clear history',
            danger: true,
            onTap: _confirmClearHistory,
            semanticLabel: 'Clear download history',
          ),
          const SizedBox(height: 10),
          SettingRow(
            title: 'Clear cache',
            subtitle: 'Thumbnails and temporary files',
            onTap: _clearCache,
            semanticLabel: 'Clear cache',
          ),
          const SectionLabel('PERMISSIONS'),
          _permissionRow(
            title: 'Notifications',
            subtitle:
                'Progress and "saved" pings. The app works fine without it.',
            granted: _notifStatus.isGranted,
            onRequest: () async {
              await Permission.notification.request();
              await _refreshPermissionStates();
            },
          ),
          const SizedBox(height: 10),
          _permissionRow(
            title: 'Display over other apps',
            subtitle: 'Only used for the optional quick-save bubble.',
            granted: _overlayGranted,
            onRequest: () async {
              await ref
                  .read(nativeProvider)
                  .requestOverlayPermission();
              await _refreshPermissionStates();
            },
          ),
          const SizedBox(height: 26),
          const Text(
            'ZipClip 1.0 · everything stays on your phone',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontFamily: ZipFonts.mono,
              fontSize: 12,
              color: ZipColors.muted,
            ),
          ),
        ],
      ),
      loading: () => const SizedBox.shrink(),
      error: (_, __) => const Center(
        child: Text('Could not load settings.',
            style: TextStyle(color: ZipColors.danger),),
      ),
    );
  }

  // ------------------------------------------------------------ downloads UI

  Widget _stepper(AppSettings s) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        _stepButton(Icons.remove_rounded, 'Decrease', () {
          if (s.maxParallel > 1) {
            _update((s) => s.copyWith(maxParallel: s.maxParallel - 1));
          }
        }),
        SizedBox(
          width: 34,
          child: Center(
            child: Text(
              '${s.maxParallel}',
              style: ZipTheme.mono(
                  size: 15,
                  weight: FontWeight.w600,
                  color: ZipColors.text,),
            ),
          ),
        ),
        _stepButton(Icons.add_rounded, 'Increase', () {
          if (s.maxParallel < 5) {
            _update((s) => s.copyWith(maxParallel: s.maxParallel + 1));
          }
        }),
      ],
    );
  }

  Widget _stepButton(IconData icon, String label, VoidCallback onTap) {
    return Pressable(
      onTap: onTap,
      semanticLabel: label,
      borderRadius: BorderRadius.circular(18),
      child: Container(
        width: 36,
        height: 36,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          border: Border.all(color: ZipColors.line, width: 1.5),
        ),
        child: Icon(icon, color: ZipColors.text, size: 18),
      ),
    );
  }

  Future<void> _editSaveFolder(AppSettings s) async {
    final controller = TextEditingController(text: s.saveSubfolder);
    final result = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Save folder'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Videos go to Movies/<name>, audio to Music/<name>, covers to Pictures/<name>.',
              style: TextStyle(
                  fontFamily: ZipFonts.ui,
                  fontSize: 13,
                  color: ZipColors.muted,
                  height: 1.5,),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: controller,
              style: ZipTheme.mono(size: 14),
              decoration: const InputDecoration(
                border: OutlineInputBorder(),
                isDense: true,
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child:
                const Text('Cancel', style: TextStyle(color: ZipColors.muted)),
          ),
          TextButton(
            onPressed: () =>
                Navigator.of(context).pop(controller.text.trim()),
            child: const Text('Save',
                style: TextStyle(
                    color: ZipColors.accent, fontWeight: FontWeight.w700,),),
          ),
        ],
      ),
    );
    if (result != null && result.isNotEmpty && mounted) {
      final clean = result.replaceAll(RegExp(r'[\\/:*?"<>|]'), '');
      if (clean.isNotEmpty) {
        await _update((s) => s.copyWith(saveSubfolder: clean));
      }
    }
  }

  Future<void> _pickQuality(AppSettings s) async {
    const options = ['1080p', '720p', '480p'];
    final picked = await showDialog<String>(
      context: context,
      builder: (context) => SimpleDialog(
        title: const Text('Default quality'),
        children: [
          for (final q in options)
            SimpleDialogOption(
              onPressed: () => Navigator.of(context).pop(q),
              child: Row(
                children: [
                  Text(q,
                      style: ZipTheme.mono(size: 14, color: ZipColors.text),),
                  const Spacer(),
                  if (q == s.defaultQuality)
                    const Icon(Icons.check_rounded,
                        color: ZipColors.mint, size: 20,),
                ],
              ),
            ),
        ],
      ),
    );
    if (picked != null) {
      await _update((s) => s.copyWith(defaultQuality: picked));
    }
  }

  Future<void> _pickFormat(AppSettings s) async {
    final picked = await showDialog<SaveFormat>(
      context: context,
      builder: (context) => SimpleDialog(
        title: const Text('Default format'),
        children: [
          for (final f in SaveFormat.values)
            SimpleDialogOption(
              onPressed: () => Navigator.of(context).pop(f),
              child: Row(
                children: [
                  Text(f.label,
                      style: const TextStyle(
                          fontFamily: ZipFonts.ui,
                          fontSize: 14,
                          color: ZipColors.text,),),
                  const Spacer(),
                  if (f == s.defaultFormat)
                    const Icon(Icons.check_rounded,
                        color: ZipColors.mint, size: 20,),
                ],
              ),
            ),
        ],
      ),
    );
    if (picked != null) {
      await _update((s) => s.copyWith(defaultFormat: picked));
    }
  }

  Future<void> _editTemplate(AppSettings s) async {
    final controller = TextEditingController(text: s.fileNameTemplate);
    String preview = '';
    final result = await showDialog<String>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) {
          preview = FileNameTemplate.render(
            controller.text,
            author: '@creator_name',
            title: 'Sample clip',
            date: DateTime(2026, 10, 11, 13, 30),
            quality: '1080p',
          );
          return AlertDialog(
            title: const Text('File name template'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Tokens: {author} {title} {date} {quality}',
                  style: TextStyle(
                      fontFamily: ZipFonts.mono,
                      fontSize: 12,
                      color: ZipColors.muted,),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: controller,
                  onChanged: (_) => setState(() {}),
                  style: ZipTheme.mono(size: 14),
                  decoration: const InputDecoration(
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                ),
                const SizedBox(height: 10),
                Text(
                  '$preview.mp4',
                  style: ZipTheme.mono(size: 12, color: ZipColors.mint),
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('Cancel',
                    style: TextStyle(color: ZipColors.muted),),
              ),
              TextButton(
                onPressed: () =>
                    Navigator.of(context).pop(controller.text.trim()),
                child: const Text('Save',
                    style: TextStyle(
                        color: ZipColors.accent,
                        fontWeight: FontWeight.w700,),),
              ),
            ],
          );
        },
      ),
    );
    if (result != null && result.isNotEmpty) {
      await _update((s) => s.copyWith(fileNameTemplate: result));
    }
  }

  // ------------------------------------------------------------- clipboard

  Future<void> _toggleBubble(bool value) async {
    final native = ref.read(nativeProvider);
    if (!value) {
      await native.setBubbleEnabled(false);
      await _update((s) => s.copyWith(quickSaveBubble: false));
      return;
    }
    final granted = await native.hasOverlayPermission();
    if (!mounted) return;
    if (!granted) {
      final go = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Allow display over other apps?'),
          content: const Text(
            'The quick-save bubble is a small floating button that appears '
            'when you copy a video link, so you can save it without opening '
            'the app first.\n\nIt needs the "Display over other apps" '
            'permission. Nothing else changes.',
            style: TextStyle(
              fontFamily: ZipFonts.ui,
              fontSize: 14,
              height: 1.5,
              color: ZipColors.text,
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Not now',
                  style: TextStyle(color: ZipColors.muted),),
            ),
            TextButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('Continue',
                  style: TextStyle(
                      color: ZipColors.accent,
                      fontWeight: FontWeight.w700,),),
            ),
          ],
        ),
      );
      if (go != true) return;
      await native.requestOverlayPermission();
      await _refreshPermissionStates();
      if (!mounted) return;
      if (!await native.hasOverlayPermission()) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
                content: Text(
                    'Permission not granted — the bubble stays off.',),),
          );
        }
        return;
      }
    }
    await native.setBubbleEnabled(true);
    await _update((s) => s.copyWith(quickSaveBubble: true));
    await _refreshPermissionStates();
  }

  // --------------------------------------------------------------- privacy

  Future<void> _confirmClearHistory() async {
    final go = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Clear history?'),
        content: const Text(
          'This removes the download history inside ZipClip. '
          'Saved files stay on your phone.',
          style: TextStyle(
            fontFamily: ZipFonts.ui,
            fontSize: 14,
            height: 1.5,
            color: ZipColors.text,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child:
                const Text('Cancel', style: TextStyle(color: ZipColors.muted)),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Clear',
                style: TextStyle(
                    color: ZipColors.danger, fontWeight: FontWeight.w700,),),
          ),
        ],
      ),
    );
    if (go == true) {
      final db = await ref.read(appDbProvider.future);
      await db.clearHistory();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('History cleared.')),
        );
      }
    }
  }

  Future<void> _clearCache() async {
    try {
      final workDir = await ref.read(workDirProvider.future);
      final thumbs = Directory('${workDir.path}/thumbs');
      if (await thumbs.exists()) {
        await thumbs.delete(recursive: true);
        await thumbs.create();
      }
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Cache cleared.')),
        );
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not clear the cache.')),
        );
      }
    }
  }

  // ------------------------------------------------------------ permissions

  Widget _permissionRow({
    required String title,
    required String subtitle,
    required bool granted,
    required VoidCallback onRequest,
  }) {
    return SettingRow(
      title: title,
      subtitle: subtitle,
      trailing: granted
          ? const Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.check_circle_rounded,
                    color: ZipColors.mint, size: 20,),
                SizedBox(width: 6),
                Text('On',
                    style: TextStyle(
                        fontFamily: ZipFonts.ui,
                        fontSize: 13,
                        color: ZipColors.mint,
                        fontWeight: FontWeight.w600,),),
              ],
            )
          : Pressable(
              onTap: onRequest,
              semanticLabel: 'Grant $title permission',
              borderRadius: BorderRadius.circular(ZipRadii.pill),
              child: Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 16, vertical: 9,),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(ZipRadii.pill),
                  border:
                      Border.all(color: ZipColors.accent, width: 1.5),
                ),
                child: const Text(
                  'Grant',
                  style: TextStyle(
                    fontFamily: ZipFonts.ui,
                    fontWeight: FontWeight.w700,
                    fontSize: 13,
                    color: ZipColors.accent,
                  ),
                ),
              ),
            ),
    );
  }
}
