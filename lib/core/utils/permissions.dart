import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';

import '../theme/app_theme.dart';

/// Explains the notification permission in plain words, then asks — once.
/// The app stays fully usable when the user says no: downloads keep running,
/// and foreground-service progress is exempt from the permission anyway.
Future<void> explainAndRequestNotifications(BuildContext context) async {
  final status = await Permission.notification.status;
  if (!status.isDenied || !context.mounted) return;
  final go = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('Stay in the loop?'),
      content: const Text(
        'ZipClip can show a notification with live download progress, '
        'pause and cancel buttons, and a ping when your video is saved.\n\n'
        'Everything works if you say no — downloads keep running quietly.',
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
              const Text('Not now', style: TextStyle(color: ZipColors.muted)),
        ),
        TextButton(
          onPressed: () => Navigator.of(context).pop(true),
          child: const Text('Allow',
              style: TextStyle(
                  color: ZipColors.accent, fontWeight: FontWeight.w700,),),
        ),
      ],
    ),
  );
  if (go == true) {
    await Permission.notification.request();
  }
}
