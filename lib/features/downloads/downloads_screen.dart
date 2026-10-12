import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/engine/download_engine.dart';
import '../../core/engine/download_store.dart';
import '../../core/models/media.dart';
import '../../core/theme/app_theme.dart';
import '../../core/theme/pressable.dart';
import '../../core/utils/format.dart';
import '../../core/widgets/zip_widgets.dart';
import '../../providers/bootstrap.dart';
import '../../providers/tasks.dart';
import 'downloads_controller.dart';

class DownloadsScreen extends ConsumerStatefulWidget {
  const DownloadsScreen({super.key});

  @override
  ConsumerState<DownloadsScreen> createState() => _DownloadsScreenState();
}

class _DownloadsScreenState extends ConsumerState<DownloadsScreen> {
  SaveFormat _tab = SaveFormat.video;

  Future<DownloadEngine> _engine() => ref.read(engineProvider.future);

  Future<void> _openItem(SavedItem item) async {
    final native = ref.read(nativeProvider);
    final ok = await native.openMedia(item.fileUri, item.format.mimeType);
    if (!ok && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No app found to open this file.')),
      );
    }
  }

  Future<void> _deleteWithUndo(SavedItem item) async {
    final db = await ref.read(appDbProvider.future);
    final native = ref.read(nativeProvider);
    await db.deleteHistory(item.id);
    if (!mounted) return;
    var undone = false;
    final snack = ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Deleted "${item.title}"'),
        duration: const Duration(seconds: 4),
        action: SnackBarAction(
          label: 'Undo',
          textColor: ZipColors.mint,
          onPressed: () {
            undone = true;
            db.addHistory(item);
          },
        ),
      ),
    );
    await snack.closed;
    // Only remove the actual file once the undo window has passed.
    if (!undone) {
      await native.deleteMedia(item.fileUri);
    }
  }

  @override
  Widget build(BuildContext context) {
    final active = ref.watch(activeTasksProvider);
    final saved = ref.watch(savedItemsProvider(_tab));
    final count = ref.watch(savedCountProvider(_tab));
    final free = ref.watch(freeSpaceLiveProvider);

    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 14, 20, 24),
      children: [
        Row(
          children: [
            const Text(
              'Downloads',
              style: TextStyle(
                fontFamily: ZipFonts.heading,
                fontWeight: FontWeight.w800,
                fontSize: 30,
                color: ZipColors.text,
              ),
            ),
            const Spacer(),
            free.when(
              data: (b) => FreeSpaceChip(bytes: b),
              loading: () => const FreeSpaceChip(bytes: null),
              error: (_, __) => const FreeSpaceChip(bytes: null),
            ),
          ],
        ),
        const SizedBox(height: 14),
        _tabs(),
        const SizedBox(height: 14),
        active.when(
          data: (tasks) =>
              _activeSections(tasks.where((t) => t.format == _tab).toList()),
          loading: () => const SizedBox.shrink(),
          error: (_, __) => const SizedBox.shrink(),
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            const Text(
              'Saved',
              style: TextStyle(
                fontFamily: ZipFonts.heading,
                fontWeight: FontWeight.w700,
                fontSize: 17,
                color: ZipColors.text,
              ),
            ),
            const SizedBox(width: 8),
            count.when(
              data: (n) => Text(
                '$n',
                style: ZipTheme.mono(size: 13, color: ZipColors.muted),
              ),
              loading: () => const SizedBox.shrink(),
              error: (_, __) => const SizedBox.shrink(),
            ),
          ],
        ),
        const SizedBox(height: 10),
        saved.when(
          data: (items) {
            if (items.isEmpty) {
              return const Padding(
                padding: EdgeInsets.symmetric(vertical: 16),
                child: Text(
                  'Nothing here yet. Saved videos, audio and covers will appear here.',
                  style: TextStyle(
                    fontFamily: ZipFonts.ui,
                    fontSize: 13,
                    color: ZipColors.muted,
                    height: 1.5,
                  ),
                ),
              );
            }
            return Column(
              children: [
                for (final item in items) ...[
                  _savedRow(item),
                  const SizedBox(height: 10),
                ],
              ],
            );
          },
          loading: () => const SizedBox.shrink(),
          error: (_, __) => const SizedBox.shrink(),
        ),
      ],
    );
  }

  // ------------------------------------------------------------------ tabs

  Widget _tabs() {
    return Row(
      children: [
        for (final f in SaveFormat.values)
          Expanded(
            child: Pressable(
              onTap: () => setState(() => _tab = f),
              semanticLabel: '${f.tabLabel} tab',
              child: Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 10),
                    child: Text(
                      f.tabLabel,
                      style: TextStyle(
                        fontFamily: ZipFonts.ui,
                        fontWeight: FontWeight.w700,
                        fontSize: 15,
                        color: _tab == f ? ZipColors.text : ZipColors.muted,
                      ),
                    ),
                  ),
                  Container(
                    height: 3,
                    decoration: BoxDecoration(
                      color: _tab == f
                          ? ZipColors.accent
                          : Colors.transparent,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }

  // -------------------------------------------------------- active sections

  Widget _activeSections(List<StoredTask> tasks) {
    if (tasks.isEmpty) return const SizedBox.shrink();
    final downloading =
        tasks.where((t) => t.status == TaskStatus.downloading).toList();
    final queued =
        tasks.where((t) => t.status == TaskStatus.queued).toList();
    final others = tasks
        .where((t) =>
            t.status == TaskStatus.paused ||
            t.status == TaskStatus.waitingForWifi ||
            t.status == TaskStatus.failed,)
        .toList();
    return Column(
      children: [
        for (final t in downloading) ...[
          _SavingNowCard(task: t),
          const SizedBox(height: 10),
        ],
        for (var i = 0; i < queued.length; i++) ...[
          _waitingRow(queued[i], i),
          const SizedBox(height: 10),
        ],
        for (final t in others) ...[
          _stalledRow(t),
          const SizedBox(height: 10),
        ],
      ],
    );
  }

  Widget _waitingRow(StoredTask task, int queueIndex) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          children: [
            ZipThumb(
                source: task.thumbSource, width: 56, height: 56, radius: 12,),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    task.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontFamily: ZipFonts.ui,
                      fontWeight: FontWeight.w600,
                      fontSize: 14,
                      color: ZipColors.text,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Waiting · ${_ordinal(queueIndex + 1)} in queue',
                    style: ZipTheme.mono(
                        size: 12,
                        weight: FontWeight.w600,
                        color: ZipColors.warning,),
                  ),
                ],
              ),
            ),
            Pressable(
              onTap: () async => (await _engine()).cancel(task.id),
              semanticLabel: 'Cancel ${task.title}',
              borderRadius: BorderRadius.circular(18),
              child: const Padding(
                padding: EdgeInsets.all(8),
                child: Icon(Icons.close_rounded,
                    color: ZipColors.muted, size: 20,),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _stalledRow(StoredTask task) {
    final (label, color) = switch (task.status) {
      TaskStatus.paused => ('Paused', ZipColors.muted),
      TaskStatus.waitingForWifi => ('Waiting for Wi-Fi', ZipColors.warning),
      TaskStatus.failed =>
        (task.error ?? 'Failed — tap retry', ZipColors.danger),
      _ => ('', ZipColors.muted),
    };
    final isFailed = task.status == TaskStatus.failed;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          children: [
            ZipThumb(
                source: task.thumbSource, width: 56, height: 56, radius: 12,),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    task.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontFamily: ZipFonts.ui,
                      fontWeight: FontWeight.w600,
                      fontSize: 14,
                      color: ZipColors.text,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: ZipTheme.mono(
                        size: 12, weight: FontWeight.w600, color: color,),
                  ),
                ],
              ),
            ),
            Pressable(
              onTap: () async =>
                  (await _engine()).resume(task.id),
              semanticLabel: isFailed
                  ? 'Retry ${task.title}'
                  : 'Resume ${task.title}',
              borderRadius: BorderRadius.circular(20),
              child: Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(color: ZipColors.line, width: 1.5),
                ),
                child: Icon(
                  isFailed ? Icons.refresh_rounded : Icons.play_arrow_rounded,
                  color: ZipColors.text,
                  size: 20,
                ),
              ),
            ),
            const SizedBox(width: 4),
            Pressable(
              onTap: () async => (await _engine()).cancel(task.id),
              semanticLabel: 'Cancel ${task.title}',
              borderRadius: BorderRadius.circular(18),
              child: const Padding(
                padding: EdgeInsets.all(8),
                child: Icon(Icons.close_rounded,
                    color: ZipColors.muted, size: 20,),
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _ordinal(int n) {
    if (n % 100 >= 11 && n % 100 <= 13) return '${n}th';
    return switch (n % 10) {
      1 => '${n}st',
      2 => '${n}nd',
      3 => '${n}rd',
      _ => '${n}th',
    };
  }

  // ------------------------------------------------------------- saved rows

  Widget _savedRow(SavedItem item) {
    return Dismissible(
      key: ValueKey(item.id),
      direction: DismissDirection.endToStart,
      background: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 20),
        decoration: BoxDecoration(
          color: ZipColors.danger.withValues(alpha: 0.15),
          borderRadius: BorderRadius.circular(ZipRadii.card),
        ),
        child: const Icon(Icons.delete_outline_rounded,
            color: ZipColors.danger, size: 26,),
      ),
      onDismissed: (_) => _deleteWithUndo(item),
      child: Card(
        child: Pressable(
          onTap: () => _openItem(item),
          semanticLabel: 'Open ${item.title}',
          borderRadius: BorderRadius.circular(ZipRadii.card),
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              children: [
                ZipThumb(
                    source: item.thumbPath,
                    width: 64,
                    height: 64,
                    radius: 14,),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        item.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontFamily: ZipFonts.ui,
                          fontWeight: FontWeight.w600,
                          fontSize: 14,
                          color: ZipColors.text,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '${ZipFormat.duration(item.durationMs == null ? null : Duration(milliseconds: item.durationMs!))} · ${item.qualityLabel} · ${ZipFormat.bytes(item.sizeBytes)}',
                        style:
                            ZipTheme.mono(size: 12, color: ZipColors.muted),
                      ),
                    ],
                  ),
                ),
                _rowMenu(item),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _rowMenu(SavedItem item) {
    return PopupMenuButton<String>(
      icon: const Icon(Icons.more_vert_rounded, color: ZipColors.muted),
      tooltip: 'Options for ${item.title}',
      color: ZipColors.surfaceRaised,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: const BorderSide(color: ZipColors.line),
      ),
      onSelected: (value) async {
        switch (value) {
          case 'play':
            await _openItem(item);
          case 'share':
            await ref
                .read(nativeProvider)
                .shareMedia(item.fileUri, item.format.mimeType);
          case 'copy':
            await Clipboard.setData(
                ClipboardData(text: item.originalUrl),);
            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Link copied.')),
              );
            }
          case 'delete':
            await _deleteWithUndo(item);
        }
      },
      itemBuilder: (context) => [
        const PopupMenuItem(
          value: 'play',
          child: _MenuRow(
              icon: Icons.play_arrow_rounded, label: 'Play',),
        ),
        const PopupMenuItem(
          value: 'share',
          child: _MenuRow(icon: Icons.share_rounded, label: 'Share'),
        ),
        const PopupMenuItem(
          value: 'copy',
          child: _MenuRow(icon: Icons.link_rounded, label: 'Copy link'),
        ),
        const PopupMenuItem(
          value: 'delete',
          child: _MenuRow(
            icon: Icons.delete_outline_rounded,
            label: 'Delete file',
            danger: true,
          ),
        ),
      ],
    );
  }
}

class _MenuRow extends StatelessWidget {
  const _MenuRow(
      {required this.icon, required this.label, this.danger = false,});

  final IconData icon;
  final String label;
  final bool danger;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon,
            color: danger ? ZipColors.danger : ZipColors.text, size: 20,),
        const SizedBox(width: 12),
        Text(
          label,
          style: TextStyle(
            fontFamily: ZipFonts.ui,
            fontWeight: FontWeight.w600,
            fontSize: 14,
            color: danger ? ZipColors.danger : ZipColors.text,
          ),
        ),
      ],
    );
  }
}

/// The "Saving now" card with live progress, speed and pause/resume.
class _SavingNowCard extends ConsumerWidget {
  const _SavingNowCard({required this.task});

  final StoredTask task;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final progress = ref.watch(taskProgressProvider(task.id));
    final engineFuture = ref.read(engineProvider.future);

    return progress.when(
      data: (p) {
        final paused = p.status == TaskStatus.paused;
        return Card(
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              children: [
                Row(
                  children: [
                    ZipThumb(
                        source: task.thumbSource,
                        width: 64,
                        height: 64,
                        radius: 14,),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            paused ? 'PAUSED' : 'SAVING NOW',
                            style: const TextStyle(
                              fontFamily: ZipFonts.ui,
                              fontWeight: FontWeight.w700,
                              fontSize: 11,
                              letterSpacing: 1.4,
                              color: ZipColors.mint,
                            ),
                          ),
                          const SizedBox(height: 3),
                          Text(
                            task.title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontFamily: ZipFonts.ui,
                              fontWeight: FontWeight.w700,
                              fontSize: 15,
                              color: ZipColors.text,
                            ),
                          ),
                          const SizedBox(height: 3),
                          Text(
                            // Real measured numbers.
                            '${ZipFormat.bytes(p.bytesDone)} of ${ZipFormat.bytes(p.totalBytes)} · ${ZipFormat.speed(p.speedBps)}',
                            style: ZipTheme.mono(
                                size: 12, color: ZipColors.muted,),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    Pressable(
                      onTap: () async {
                        final engine = await engineFuture;
                        if (paused) {
                          await engine.resume(task.id);
                        } else {
                          await engine.pause(task.id);
                        }
                      },
                      semanticLabel:
                          paused ? 'Resume download' : 'Pause download',
                      borderRadius: BorderRadius.circular(22),
                      child: Container(
                        width: 44,
                        height: 44,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          border:
                              Border.all(color: ZipColors.line, width: 1.5),
                        ),
                        child: Icon(
                          paused
                              ? Icons.play_arrow_rounded
                              : Icons.pause_rounded,
                          color: ZipColors.text,
                          size: 22,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: LinearProgressIndicator(
                    value: (p.fraction ?? 0).clamp(0.0, 1.0),
                    minHeight: 8,
                    backgroundColor: ZipColors.line,
                    valueColor: const AlwaysStoppedAnimation<Color>(
                        ZipColors.mint,),
                  ),
                ),
              ],
            ),
          ),
        );
      },
      loading: () => const SizedBox.shrink(),
      error: (_, __) => const SizedBox.shrink(),
    );
  }
}
