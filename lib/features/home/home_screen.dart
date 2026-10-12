import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/engine/download_store.dart';
import '../../core/models/media.dart';
import '../../core/resolver/link_normalizer.dart';
import '../../core/theme/app_theme.dart';
import '../../core/theme/pressable.dart';
import '../../core/utils/format.dart';
import '../../core/utils/permissions.dart';
import '../../core/widgets/zip_widgets.dart';
import '../../providers/bootstrap.dart';
import '../../providers/tasks.dart';
import 'home_controller.dart';

class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({
    super.key,
    required this.onOpenBatch,
    required this.onOpenSettings,
    required this.onOpenDownloads,
  });

  final VoidCallback onOpenBatch;
  final VoidCallback onOpenSettings;
  final VoidCallback onOpenDownloads;

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen>
    with WidgetsBindingObserver {
  late final TextEditingController _field;

  @override
  void initState() {
    super.initState();
    _field = TextEditingController();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final notifier = ref.read(homeControllerProvider.notifier);
      notifier.refreshClipboard();
      _consumeIncoming();
      _field.text = ref.read(homeControllerProvider).linkText;
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _field.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && mounted) {
      ref.read(homeControllerProvider.notifier).refreshClipboard();
      _consumeIncoming();
    }
  }

  void _consumeIncoming() {
    final url = ref.read(incomingLinkProvider.notifier).take();
    if (url != null && mounted) {
      ref.read(homeControllerProvider.notifier).consumeSharedLink(url);
    }
  }

  Future<void> _onDownloadTap() async {
    await explainAndRequestNotifications(context);
    if (!mounted) return;
    await ref.read(homeControllerProvider.notifier).startDownload();
  }

  Future<void> _openSavedItem(SavedItem item) async {
    final native = ref.read(nativeProvider);
    final mime = switch (item.format) {
      SaveFormat.video => 'video/mp4',
      SaveFormat.audio => 'audio/mpeg',
      SaveFormat.cover => 'image/jpeg',
    };
    final ok = await native.openMedia(item.fileUri, mime);
    if (!ok && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No app found to open this file.')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(homeControllerProvider);
    final notifier = ref.read(homeControllerProvider.notifier);

    ref.listen<HomeState>(homeControllerProvider, (prev, next) {
      if (next.linkText != _field.text) {
        _field.value = _field.value.copyWith(
          text: next.linkText,
          selection: TextSelection.collapsed(offset: next.linkText.length),
        );
      }
      final thumb = next.media?.thumbnailUrl;
      if (thumb != null &&
          thumb.startsWith('http') &&
          thumb != prev?.media?.thumbnailUrl) {
        // Prefetch so the preview card never pops in late.
        precacheImage(NetworkImage(thumb), context);
      }
    });
    ref.listen(incomingLinkProvider, (prev, next) {
      if (next.isNotEmpty) _consumeIncoming();
    });

    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 14, 20, 24),
      children: [
        _header(),
        const SizedBox(height: 18),
        _pasteCard(state, notifier),
        if (state.clipboardLink != null) ...[
          const SizedBox(height: 12),
          _clipboardCard(state, notifier),
        ],
        if (state.media == null && !state.isDone) ...[
          const SizedBox(height: 26),
          _idleBody(state),
        ] else if (state.media != null) ...[
          const SizedBox(height: 14),
          _fetchedBody(state, notifier),
        ],
        if (state.isDone) ...[
          const SizedBox(height: 14),
          _doneCard(state, notifier),
        ],
        const LegalLine(),
      ],
    );
  }

  // ---------------------------------------------------------------- header

  Widget _header() {
    return Row(
      children: [
        const LogoTile(),
        const SizedBox(width: 12),
        const Text(
          'ZipClip',
          style: TextStyle(
            fontFamily: ZipFonts.heading,
            fontWeight: FontWeight.w800,
            fontSize: 24,
            color: ZipColors.text,
          ),
        ),
        const Spacer(),
        Pressable(
          onTap: widget.onOpenSettings,
          semanticLabel: 'Open settings',
          borderRadius: BorderRadius.circular(24),
          child: Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(color: ZipColors.line, width: 1.5),
            ),
            child: const Icon(
              Icons.tune_rounded,
              color: ZipColors.text,
              size: 22,
            ),
          ),
        ),
      ],
    );
  }

  // -------------------------------------------------------------- paste card

  Widget _pasteCard(HomeState state, HomeController notifier) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                const Icon(Icons.link_rounded,
                    color: ZipColors.muted, size: 20,),
                const SizedBox(width: 10),
                Expanded(
                  child: TextField(
                    controller: _field,
                    onChanged: notifier.setLink,
                    keyboardType: TextInputType.url,
                    autocorrect: false,
                    style: ZipTheme.mono(size: 14),
                    decoration: const InputDecoration(
                      hintText: 'Paste a video link…',
                      hintStyle: TextStyle(
                        fontFamily: ZipFonts.mono,
                        fontSize: 14,
                        color: ZipColors.muted,
                      ),
                      border: InputBorder.none,
                      isDense: true,
                      contentPadding: EdgeInsets.zero,
                    ),
                  ),
                ),
                ValueListenableBuilder<TextEditingValue>(
                  valueListenable: _field,
                  builder: (_, value, __) {
                    if (value.text.isEmpty) {
                      return const SizedBox.shrink();
                    }
                    return Pressable(
                      onTap: notifier.clearLink,
                      semanticLabel: 'Clear link',
                      borderRadius: BorderRadius.circular(18),
                      child: Container(
                        width: 36,
                        height: 36,
                        decoration: const BoxDecoration(
                          color: ZipColors.surfaceRaised,
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(Icons.close_rounded,
                            color: ZipColors.muted, size: 18,),
                      ),
                    );
                  },
                ),
              ],
            ),
            const SizedBox(height: 12),
            _PasteButton(
              loading: state.resolving,
              onTap: notifier.pasteFromClipboard,
            ),
          ],
        ),
      ),
    );
  }

  Widget _clipboardCard(HomeState state, HomeController notifier) {
    final link = state.clipboardLink!;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Container(
              width: 42,
              height: 42,
              decoration: BoxDecoration(
                color: ZipColors.surfaceRaised,
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Icon(Icons.content_paste_rounded,
                  color: ZipColors.mint, size: 20,),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Link in clipboard',
                    style: TextStyle(
                      fontFamily: ZipFonts.ui,
                      fontWeight: FontWeight.w700,
                      fontSize: 14,
                      color: ZipColors.text,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    LinkNormalizer.shortForm(link),
                    style: ZipTheme.mono(size: 12, color: ZipColors.muted),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Pressable(
              onTap: notifier.downloadClipboardLink,
              semanticLabel: 'Download link from clipboard',
              borderRadius: BorderRadius.circular(ZipRadii.pill),
              child: Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 18, vertical: 11,),
                decoration: BoxDecoration(
                  color: ZipColors.accent,
                  borderRadius: BorderRadius.circular(ZipRadii.pill),
                ),
                child: const Text(
                  'Download',
                  style: TextStyle(
                    fontFamily: ZipFonts.ui,
                    fontWeight: FontWeight.w700,
                    fontSize: 13,
                    color: Colors.white,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // --------------------------------------------------------------- idle body

  Widget _idleBody(HomeState state) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text(
          'Paste. Tap. Saved.',
          style: TextStyle(
            fontFamily: ZipFonts.heading,
            fontWeight: FontWeight.w800,
            fontSize: 30,
            height: 1.15,
            color: ZipColors.text,
          ),
        ),
        const SizedBox(height: 4),
        const Text(
          'Short videos, straight to your phone.',
          style: TextStyle(
            fontFamily: ZipFonts.ui,
            fontSize: 14,
            color: ZipColors.muted,
          ),
        ),
        const SizedBox(height: 22),
        Row(
          children: [
            const Text(
              'Recent',
              style: TextStyle(
                fontFamily: ZipFonts.heading,
                fontWeight: FontWeight.w700,
                fontSize: 17,
                color: ZipColors.text,
              ),
            ),
            const Spacer(),
            Pressable(
              onTap: widget.onOpenDownloads,
              semanticLabel: 'See all downloads',
              child: const Padding(
                padding: EdgeInsets.all(6),
                child: Text(
                  'See all',
                  style: TextStyle(
                    fontFamily: ZipFonts.ui,
                    fontWeight: FontWeight.w600,
                    fontSize: 13,
                    color: ZipColors.accent,
                  ),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        _recentList(),
        const SizedBox(height: 18),
        _OutlinedButton(
          label: 'Paste many links at once',
          icon: Icons.playlist_add_rounded,
          onTap: widget.onOpenBatch,
          semanticLabel: 'Paste many links at once',
        ),
      ],
    );
  }

  Widget _recentList() {
    final recent = ref.watch(recentItemsProvider);
    return recent.when(
      data: (items) {
        if (items.isEmpty) {
          return const Padding(
            padding: EdgeInsets.symmetric(vertical: 8),
            child: Text(
              'Nothing saved yet — your last downloads will show up here.',
              style: TextStyle(
                fontFamily: ZipFonts.ui,
                fontSize: 13,
                color: ZipColors.muted,
              ),
            ),
          );
        }
        return Column(
          children: [
            for (final item in items) ...[
              _recentRow(item),
              const SizedBox(height: 10),
            ],
          ],
        );
      },
      loading: () => const SizedBox.shrink(),
      error: (_, __) => const SizedBox.shrink(),
    );
  }

  Widget _recentRow(SavedItem item) {
    return Card(
      child: Pressable(
        onTap: () => _openSavedItem(item),
        semanticLabel: 'Open ${item.title}',
        borderRadius: BorderRadius.circular(ZipRadii.card),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              ZipThumb(
                source: item.thumbPath,
                width: 56,
                height: 72,
                radius: 12,
              ),
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
                      style: ZipTheme.mono(size: 12, color: ZipColors.muted),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              const Icon(Icons.check_circle_rounded,
                  color: ZipColors.mint, size: 22,
                  semanticLabel: 'Saved',),
            ],
          ),
        ),
      ),
    );
  }

  // ------------------------------------------------------------ fetched body

  Widget _fetchedBody(HomeState state, HomeController notifier) {
    final media = state.media!;
    final picked = notifier.pickedStream;
    final pickedQuality = state.format == SaveFormat.audio
        ? 'Audio'
        : state.format == SaveFormat.cover
            ? 'JPG'
            : (picked?.label ?? state.quality);
    final pickedSize =
        state.format == SaveFormat.cover ? null : picked?.sizeBytes;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _previewCard(media, pickedQuality, pickedSize),
        const SizedBox(height: 12),
        _watermarkRow(media, state, notifier),
        const SectionLabel('SAVE AS'),
        Wrap(
          spacing: 10,
          runSpacing: 10,
          children: [
            for (final f in SaveFormat.values)
              ZipChip(
                label: f.label,
                selected: state.format == f,
                onTap: () => notifier.setFormat(f),
              ),
          ],
        ),
        if (state.format == SaveFormat.video) ...[
          const SectionLabel('QUALITY'),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              for (final s in media.videoStreams)
                ZipChip(
                  label: s.label,
                  selected: state.quality == s.label,
                  onTap: () => notifier.setQuality(s.label),
                ),
            ],
          ),
        ],
        if (state.resolveError != null) ...[
          const SizedBox(height: 12),
          Text(
            state.resolveError!,
            style: const TextStyle(
              fontFamily: ZipFonts.ui,
              fontSize: 13,
              color: ZipColors.danger,
              height: 1.4,
            ),
          ),
        ],
        if (state.duplicateOf != null) ...[
          const SizedBox(height: 12),
          _duplicateCard(state, notifier),
        ],
        const SizedBox(height: 20),
        _downloadArea(state, notifier),
      ],
    );
  }

  Widget _previewCard(ResolvedMedia media, String qualityLabel, int? sizeBytes) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Stack(
              children: [
                ZipThumb(
                  source: media.thumbnailUrl,
                  width: 96,
                  height: 128,
                  radius: 14,
                  semanticLabel: 'Video thumbnail',
                ),
                Positioned(
                  bottom: 8,
                  left: 0,
                  right: 0,
                  child: Center(
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 3,),
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.65),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        ZipFormat.duration(media.duration),
                        style: ZipTheme.mono(
                            size: 11,
                            weight: FontWeight.w600,
                            color: Colors.white,),
                      ),
                    ),
                  ),
                ),
                Positioned.fill(
                  child: Center(
                    child: Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.92),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(Icons.play_arrow_rounded,
                          color: ZipColors.background, size: 26,),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    media.title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontFamily: ZipFonts.heading,
                      fontWeight: FontWeight.w700,
                      fontSize: 16,
                      height: 1.3,
                      color: ZipColors.text,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    media.author,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontFamily: ZipFonts.ui,
                      fontSize: 13,
                      color: ZipColors.muted,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    LinkNormalizer.shortForm(media.sourceUrl),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: ZipTheme.mono(size: 12, color: ZipColors.muted),
                  ),
                  const SizedBox(height: 10),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      StatChip(qualityLabel),
                      StatChip(ZipFormat.bytes(sizeBytes)),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _watermarkRow(
      ResolvedMedia media, HomeState state, HomeController notifier,) {
    final offers = media.offersWatermarkFree;
    return SettingRow(
      title: 'Remove watermark',
      subtitle: offers
          ? 'Clean video, no logo overlay'
          : "This source doesn't offer a watermark-free version.",
      trailing: Switch(
        value: offers && state.removeWatermark,
        onChanged: offers ? notifier.toggleWatermark : null,
      ),
    );
  }

  Widget _duplicateCard(HomeState state, HomeController notifier) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Row(
          children: [
            const Icon(Icons.info_rounded,
                color: ZipColors.warning, size: 24,),
            const SizedBox(width: 12),
            const Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Saved already',
                    style: TextStyle(
                      fontFamily: ZipFonts.ui,
                      fontWeight: FontWeight.w700,
                      fontSize: 14,
                      color: ZipColors.text,
                    ),
                  ),
                  SizedBox(height: 2),
                  Text(
                    'This link is already in your downloads.',
                    style: TextStyle(
                      fontFamily: ZipFonts.ui,
                      fontSize: 12.5,
                      color: ZipColors.muted,
                    ),
                  ),
                ],
              ),
            ),
            Pressable(
              onTap: () async {
                final ok = await notifier.openDuplicate();
                if (!ok && mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                        content: Text('No app found to open this file.'),),
                  );
                }
              },
              semanticLabel: 'Open saved file',
              borderRadius: BorderRadius.circular(ZipRadii.pill),
              child: Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 18, vertical: 10,),
                decoration: BoxDecoration(
                  color: ZipColors.accent,
                  borderRadius: BorderRadius.circular(ZipRadii.pill),
                ),
                child: const Text(
                  'Open',
                  style: TextStyle(
                    fontFamily: ZipFonts.ui,
                    fontWeight: FontWeight.w700,
                    fontSize: 13,
                    color: Colors.white,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _downloadArea(HomeState state, HomeController notifier) {
    if (state.isDownloading) {
      final progress =
          ref.watch(taskProgressProvider(state.activeTaskId!));
      return progress.when(
        data: (p) => switch (p.status) {
          TaskStatus.waitingForWifi => _waitingForWifiCard(state),
          TaskStatus.paused => _pausedCard(state),
          _ => ZipProgressButton(
              fraction: p.fraction ?? 0,
              statusText: ZipFormat.speed(p.speedBps),
              semanticLabel:
                  'Saving ${((p.fraction ?? 0) * 100).round()} percent at ${ZipFormat.speed(p.speedBps)}',
            ),
        },
        loading: () => const ZipProgressButton(
          fraction: 0,
          statusText: 'Starting…',
        ),
        error: (_, __) => ZipButton(
          label: 'Download',
          onTap: _onDownloadTap,
        ),
      );
    }
    if (state.startingDownload || state.resolving) {
      return const ZipButton(label: 'Preparing…', onTap: null, enabled: false);
    }
    final label = _downloadLabel(state, notifier);
    return ZipButton(label: label, onTap: _onDownloadTap);
  }

  Widget _waitingForWifiCard(HomeState state) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            const Icon(Icons.wifi_off_rounded,
                color: ZipColors.warning, size: 24,),
            const SizedBox(width: 12),
            const Expanded(
              child: Text(
                'Waiting for Wi-Fi — the download starts automatically when you\u2019re back on Wi-Fi.',
                style: TextStyle(
                  fontFamily: ZipFonts.ui,
                  fontSize: 13,
                  color: ZipColors.text,
                  height: 1.45,
                ),
              ),
            ),
            Pressable(
              onTap: () async {
                final engine =
                    await ref.read(engineProvider.future);
                await engine.cancel(state.activeTaskId!);
                ref
                    .read(homeControllerProvider.notifier)
                    .clearLink();
              },
              semanticLabel: 'Cancel download',
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

  Widget _pausedCard(HomeState state) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            const Icon(Icons.pause_circle_outline_rounded,
                color: ZipColors.muted, size: 24,),
            const SizedBox(width: 12),
            const Expanded(
              child: Text(
                'Download paused.',
                style: TextStyle(
                  fontFamily: ZipFonts.ui,
                  fontSize: 13,
                  color: ZipColors.text,
                ),
              ),
            ),
            Pressable(
              onTap: () async {
                final engine =
                    await ref.read(engineProvider.future);
                await engine.resume(state.activeTaskId!);
              },
              semanticLabel: 'Resume download',
              borderRadius: BorderRadius.circular(ZipRadii.pill),
              child: Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 18, vertical: 10,),
                decoration: BoxDecoration(
                  color: ZipColors.accent,
                  borderRadius: BorderRadius.circular(ZipRadii.pill),
                ),
                child: const Text(
                  'Resume',
                  style: TextStyle(
                    fontFamily: ZipFonts.ui,
                    fontWeight: FontWeight.w700,
                    fontSize: 13,
                    color: Colors.white,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _downloadLabel(HomeState state, HomeController notifier) {
    if (state.format == SaveFormat.cover) return 'Download cover';
    final size = notifier.pickedStream?.sizeBytes;
    if (size == null) return 'Download';
    return 'Download · ${ZipFormat.bytes(size)}';
  }

  // --------------------------------------------------------------- done card

  Widget _doneCard(HomeState state, HomeController notifier) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          children: [
            Row(
              children: [
                Container(
                  width: 46,
                  height: 46,
                  decoration: const BoxDecoration(
                    color: ZipColors.mint,
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.check_rounded,
                      color: ZipColors.background, size: 28,),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
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
                      const SizedBox(height: 2),
                      Text(
                        // Real measured elapsed time, never fake.
                        'Saved in ${ZipFormat.elapsed(state.doneElapsedMs ?? 0)}',
                        style: ZipTheme.mono(
                            size: 13,
                            weight: FontWeight.w600,
                            color: ZipColors.mint,),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: _SmallPillButton(
                    label: 'Open',
                    filled: true,
                    onTap: () async {
                      final ok = await notifier.openDone();
                      if (!ok && mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                              content:
                                  Text('No app found to open this file.'),),
                        );
                      }
                    },
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: _SmallPillButton(
                    label: 'Share',
                    filled: false,
                    onTap: notifier.shareDone,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: _SmallPillButton(
                    label: 'Next',
                    filled: false,
                    onTap: notifier.next,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _PasteButton extends StatelessWidget {
  const _PasteButton({required this.loading, required this.onTap});

  final bool loading;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Pressable(
      onTap: onTap,
      semanticLabel: 'Paste link from clipboard',
      borderRadius: BorderRadius.circular(ZipRadii.pill),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 13),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(ZipRadii.pill),
          border: Border.all(color: ZipColors.accent, width: 1.5),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            if (loading)
              const SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(
                  strokeWidth: 2.5,
                  color: ZipColors.accent,
                ),
              )
            else
              const Icon(Icons.content_paste_rounded,
                  color: ZipColors.accent, size: 18,),
            const SizedBox(width: 8),
            const Text(
              'Paste',
              style: TextStyle(
                fontFamily: ZipFonts.ui,
                fontWeight: FontWeight.w700,
                fontSize: 14,
                color: ZipColors.accent,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _OutlinedButton extends StatelessWidget {
  const _OutlinedButton({
    required this.label,
    required this.icon,
    required this.onTap,
    required this.semanticLabel,
  });

  final String label;
  final IconData icon;
  final VoidCallback onTap;
  final String semanticLabel;

  @override
  Widget build(BuildContext context) {
    return Pressable(
      onTap: onTap,
      semanticLabel: semanticLabel,
      borderRadius: BorderRadius.circular(ZipRadii.pill),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 15),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(ZipRadii.pill),
          border: Border.all(color: ZipColors.line, width: 1.5),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, color: ZipColors.text, size: 18),
            const SizedBox(width: 8),
            Text(
              label,
              style: const TextStyle(
                fontFamily: ZipFonts.ui,
                fontWeight: FontWeight.w600,
                fontSize: 14,
                color: ZipColors.text,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SmallPillButton extends StatelessWidget {
  const _SmallPillButton({
    required this.label,
    required this.filled,
    required this.onTap,
  });

  final String label;
  final bool filled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Pressable(
      onTap: onTap,
      semanticLabel: label,
      borderRadius: BorderRadius.circular(ZipRadii.pill),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12),
        decoration: BoxDecoration(
          color: filled ? ZipColors.accent : Colors.transparent,
          borderRadius: BorderRadius.circular(ZipRadii.pill),
          border: Border.all(
            color: filled ? ZipColors.accent : ZipColors.line,
            width: 1.5,
          ),
        ),
        child: Center(
          child: Text(
            label,
            style: TextStyle(
              fontFamily: ZipFonts.ui,
              fontWeight: FontWeight.w700,
              fontSize: 14,
              color: filled ? Colors.white : ZipColors.text,
            ),
          ),
        ),
      ),
    );
  }
}
