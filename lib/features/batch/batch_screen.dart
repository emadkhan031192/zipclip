import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/resolver/link_normalizer.dart';
import '../../core/theme/app_theme.dart';
import '../../core/theme/pressable.dart';
import '../../core/utils/format.dart';
import '../../core/utils/permissions.dart';
import '../../core/widgets/zip_widgets.dart';
import 'batch_controller.dart';

/// "Paste many links": one link per line, resolved in parallel (max 4),
/// queued with one tap.
class BatchScreen extends ConsumerStatefulWidget {
  const BatchScreen({super.key});

  @override
  ConsumerState<BatchScreen> createState() => _BatchScreenState();
}

class _BatchScreenState extends ConsumerState<BatchScreen> {
  late final TextEditingController _field;

  @override
  void initState() {
    super.initState();
    _field = TextEditingController();
  }

  @override
  void dispose() {
    _field.dispose();
    super.dispose();
  }

  Future<void> _pasteFromClipboard() async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    final text = data?.text ?? '';
    if (text.isEmpty) return;
    final current = _field.text;
    final joined = current.isEmpty ? text : '$current\n$text';
    _field.text = joined;
    ref.read(batchControllerProvider.notifier).setText(joined);
  }

  Future<void> _downloadAll() async {
    await explainAndRequestNotifications(context);
    if (!mounted) return;
    final queued =
        await ref.read(batchControllerProvider.notifier).downloadAll();
    if (!mounted) return;
    if (queued > 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
              '$queued ${queued == 1 ? 'video' : 'videos'} queued — see Downloads.',),
        ),
      );
      _field.clear();
      ref.read(batchControllerProvider.notifier).clear();
      Navigator.of(context).pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(batchControllerProvider);
    final notifier = ref.read(batchControllerProvider.notifier);

    return Scaffold(
      backgroundColor: ZipColors.background,
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(20, 14, 20, 12),
                children: [
                  Row(
                    children: [
                      Pressable(
                        onTap: () => Navigator.of(context).pop(),
                        semanticLabel: 'Back',
                        borderRadius: BorderRadius.circular(24),
                        child: Container(
                          width: 48,
                          height: 48,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            border: Border.all(
                                color: ZipColors.line, width: 1.5,),
                          ),
                          child: const Icon(Icons.arrow_back_rounded,
                              color: ZipColors.text, size: 22,),
                        ),
                      ),
                      const SizedBox(width: 14),
                      const Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Paste many links',
                              style: TextStyle(
                                fontFamily: ZipFonts.heading,
                                fontWeight: FontWeight.w800,
                                fontSize: 24,
                                color: ZipColors.text,
                              ),
                            ),
                            SizedBox(height: 2),
                            Text(
                              'One link per line. We queue them for you.',
                              style: TextStyle(
                                fontFamily: ZipFonts.ui,
                                fontSize: 13,
                                color: ZipColors.muted,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SectionLabel('LINKS'),
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(14),
                      child: TextField(
                        controller: _field,
                        onChanged: notifier.setText,
                        keyboardType: TextInputType.multiline,
                        maxLines: 7,
                        minLines: 4,
                        style: ZipTheme.mono(size: 13.5),
                        decoration: const InputDecoration(
                          hintText: 'https://…\nhttps://…',
                          hintStyle: TextStyle(
                            fontFamily: ZipFonts.mono,
                            fontSize: 13.5,
                            color: ZipColors.muted,
                          ),
                          border: InputBorder.none,
                          isDense: true,
                          contentPadding: EdgeInsets.zero,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      Text(
                        ZipFormat.linkCount(state.links.length),
                        style: const TextStyle(
                          fontFamily: ZipFonts.heading,
                          fontWeight: FontWeight.w700,
                          fontSize: 18,
                          color: ZipColors.text,
                        ),
                      ),
                      const Spacer(),
                      Pressable(
                        onTap: _pasteFromClipboard,
                        semanticLabel: 'Paste links from clipboard',
                        borderRadius:
                            BorderRadius.circular(ZipRadii.pill),
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 16, vertical: 10,),
                          decoration: BoxDecoration(
                            borderRadius:
                                BorderRadius.circular(ZipRadii.pill),
                            border: Border.all(
                                color: ZipColors.line, width: 1.5,),
                          ),
                          child: const Text(
                            'Paste from clipboard',
                            style: TextStyle(
                              fontFamily: ZipFonts.ui,
                              fontWeight: FontWeight.w600,
                              fontSize: 13,
                              color: ZipColors.text,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  for (final link in state.links) ...[
                    _linkRow(link),
                    const SizedBox(height: 10),
                  ],
                  const SizedBox(height: 8),
                  SettingRow(
                    title: 'Skip duplicates',
                    subtitle: 'Never save the same link twice',
                    trailing: Switch(
                      value: state.skipDuplicates,
                      onChanged: notifier.setSkipDuplicates,
                    ),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
              child: state.enqueuing
                  ? const ZipButton(
                      label: 'Queueing…', onTap: null, enabled: false,)
                  : ZipButton(
                      label: ZipFormat.batchButton(
                          state.readyCount, state.totalBytes,),
                      onTap: state.readyCount == 0 ? null : _downloadAll,
                      enabled: state.readyCount > 0,
                    ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _linkRow(BatchLinkState link) {
    final (icon, iconColor, statusText, statusColor) =
        switch (link.status) {
      BatchLinkStatus.pending => (
          Icons.hourglass_empty_rounded,
          ZipColors.muted,
          'Waiting…',
          ZipColors.muted,
        ),
      BatchLinkStatus.resolving => (
          Icons.hourglass_empty_rounded,
          ZipColors.muted,
          'Reading link…',
          ZipColors.muted,
        ),
      BatchLinkStatus.ready => (
          Icons.check_circle_rounded,
          ZipColors.mint,
          'Ready · ${link.qualityLabel ?? ''} · ${ZipFormat.bytes(link.sizeBytes)}',
          ZipColors.mint,
        ),
      BatchLinkStatus.duplicate => (
          Icons.copy_rounded,
          ZipColors.warning,
          link.message ?? 'Duplicate · skipped',
          ZipColors.warning,
        ),
      BatchLinkStatus.notSupported => (
          Icons.cancel_rounded,
          ZipColors.danger,
          link.message ?? 'Link not supported',
          ZipColors.danger,
        ),
      BatchLinkStatus.failed => (
          Icons.error_outline_rounded,
          ZipColors.danger,
          link.message ?? 'Failed',
          ZipColors.danger,
        ),
    };
    final busy = link.status == BatchLinkStatus.resolving;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Row(
          children: [
            if (busy)
              const SizedBox(
                width: 26,
                height: 26,
                child: CircularProgressIndicator(
                  strokeWidth: 2.5,
                  color: ZipColors.muted,
                ),
              )
            else
              Icon(icon, color: iconColor, size: 26),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    LinkNormalizer.shortForm(link.link.raw),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: ZipTheme.mono(size: 13, color: ZipColors.text),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    statusText,
                    style: ZipTheme.mono(
                        size: 12,
                        weight: FontWeight.w600,
                        color: statusColor,),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
