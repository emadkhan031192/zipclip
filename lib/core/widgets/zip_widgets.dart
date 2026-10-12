import 'dart:io';

import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import '../theme/pressable.dart';
import '../utils/format.dart';

/// Violet rounded-square logo tile with a white down arrow.
class LogoTile extends StatelessWidget {
  const LogoTile({super.key, this.size = 46});

  final double size;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: ZipColors.accent,
        borderRadius: BorderRadius.circular(size * 0.3),
      ),
      child: Icon(
        Icons.arrow_downward_rounded,
        color: Colors.white,
        size: size * 0.55,
        semanticLabel: 'ZipClip logo',
      ),
    );
  }
}

/// Selectable pill chip, e.g. quality or "Save as" options.
class ZipChip extends StatelessWidget {
  const ZipChip({
    super.key,
    required this.label,
    required this.selected,
    required this.onTap,
    this.semanticLabel,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) {
    final reduceMotion = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    return Pressable(
      onTap: onTap,
      semanticLabel: semanticLabel ?? label,
      borderRadius: BorderRadius.circular(ZipRadii.pill),
      child: AnimatedContainer(
        duration:
            reduceMotion ? Duration.zero : const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 13),
        decoration: BoxDecoration(
          color: selected ? ZipColors.accent : Colors.transparent,
          borderRadius: BorderRadius.circular(ZipRadii.pill),
          border: Border.all(
            color: selected ? ZipColors.accent : ZipColors.line,
            width: 1.5,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontFamily: ZipFonts.ui,
            fontWeight: FontWeight.w700,
            fontSize: 14,
            color: selected ? Colors.white : ZipColors.muted,
          ),
        ),
      ),
    );
  }
}

/// Small uppercase section label, e.g. "SAVE AS".
class SectionLabel extends StatelessWidget {
  const SectionLabel(this.text, {super.key});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 20, bottom: 10, left: 4),
      child: Text(text, style: ZipTheme.sectionLabel),
    );
  }
}

/// A settings card row: title, optional subtitle, trailing widget.
class SettingRow extends StatelessWidget {
  const SettingRow({
    super.key,
    required this.title,
    this.subtitle,
    this.trailing,
    this.onTap,
    this.danger = false,
    this.semanticLabel,
  });

  final String title;
  final String? subtitle;
  final Widget? trailing;
  final VoidCallback? onTap;
  final bool danger;
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) {
    final content = Padding(
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 15),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    fontFamily: ZipFonts.ui,
                    fontWeight: FontWeight.w600,
                    fontSize: 15,
                    color: danger ? ZipColors.danger : ZipColors.text,
                  ),
                ),
                if (subtitle != null) ...[
                  const SizedBox(height: 3),
                  Text(
                    subtitle!,
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
              ],
            ),
          ),
          if (trailing != null) ...[
            const SizedBox(width: 12),
            trailing!,
          ],
        ],
      ),
    );
    if (onTap == null) {
      return Card(child: content);
    }
    return Card(
      child: Pressable(
        onTap: onTap,
        semanticLabel: semanticLabel ?? title,
        borderRadius: BorderRadius.circular(ZipRadii.card),
        child: content,
      ),
    );
  }
}

/// Big violet pill button, e.g. "Download · 14.2 MB".
class ZipButton extends StatelessWidget {
  const ZipButton({
    super.key,
    required this.label,
    required this.onTap,
    this.icon = Icons.arrow_downward_rounded,
    this.enabled = true,
    this.semanticLabel,
  });

  final String label;
  final VoidCallback? onTap;
  final IconData icon;
  final bool enabled;
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) {
    return Pressable(
      onTap: enabled ? onTap : null,
      enabled: enabled,
      semanticLabel: semanticLabel ?? label,
      borderRadius: BorderRadius.circular(ZipRadii.pill),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 17),
        decoration: BoxDecoration(
          color: enabled ? ZipColors.accent : ZipColors.surfaceRaised,
          borderRadius: BorderRadius.circular(ZipRadii.pill),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon,
                color: enabled ? Colors.white : ZipColors.muted, size: 20,),
            const SizedBox(width: 10),
            Flexible(
              child: Text(
                label,
                style: TextStyle(
                  fontFamily: ZipFonts.ui,
                  fontWeight: FontWeight.w700,
                  fontSize: 16,
                  color: enabled ? Colors.white : ZipColors.muted,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// The downloading state of [ZipButton]: a progress bar with % and speed.
class ZipProgressButton extends StatelessWidget {
  const ZipProgressButton({
    super.key,
    required this.fraction,
    required this.statusText,
    this.semanticLabel,
  });

  final double fraction;
  final String statusText;
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) {
    final pct = (fraction.clamp(0.0, 1.0) * 100).round();
    return Semantics(
      label: semanticLabel ?? 'Saving $pct percent. $statusText',
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 20),
        decoration: BoxDecoration(
          color: ZipColors.surfaceRaised,
          borderRadius: BorderRadius.circular(ZipRadii.pill),
          border: Border.all(color: ZipColors.line),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    'Saving $pct%',
                    style: const TextStyle(
                      fontFamily: ZipFonts.ui,
                      fontWeight: FontWeight.w700,
                      fontSize: 15,
                      color: ZipColors.text,
                    ),
                  ),
                ),
                Text(
                  statusText,
                  style: ZipTheme.mono(size: 12, color: ZipColors.muted),
                ),
              ],
            ),
            const SizedBox(height: 10),
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: fraction.clamp(0.0, 1.0),
                minHeight: 8,
                backgroundColor: ZipColors.line,
                valueColor:
                    const AlwaysStoppedAnimation<Color>(ZipColors.mint),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Thumbnail that understands `asset://`, `http(s)://` and file paths.
class ZipThumb extends StatelessWidget {
  const ZipThumb({
    super.key,
    required this.source,
    this.width = 96,
    this.height = 128,
    this.radius = 14,
    this.semanticLabel,
  });

  final String source;
  final double width;
  final double height;
  final double radius;
  final String? semanticLabel;

  static const _placeholder = _ThumbPlaceholder();

  @override
  Widget build(BuildContext context) {
    Widget image;
    if (source.startsWith('asset://')) {
      final name = source.substring('asset://'.length);
      image = Image.asset(
        'assets/img/$name.jpg',
        width: width,
        height: height,
        fit: BoxFit.cover,
        errorBuilder: (_, __, ___) => _placeholder,
      );
    } else if (source.startsWith('http')) {
      image = Image.network(
        source,
        width: width,
        height: height,
        fit: BoxFit.cover,
        loadingBuilder: (_, child, progress) =>
            progress == null ? child : _placeholder,
        errorBuilder: (_, __, ___) => _placeholder,
      );
    } else if (source.isNotEmpty) {
      image = Image.file(
        File(source),
        width: width,
        height: height,
        fit: BoxFit.cover,
        errorBuilder: (_, __, ___) => _placeholder,
      );
    } else {
      image = _placeholder;
    }
    return Semantics(
      label: semanticLabel,
      image: semanticLabel != null,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(radius),
        child: SizedBox(width: width, height: height, child: image),
      ),
    );
  }
}

class _ThumbPlaceholder extends StatelessWidget {
  const _ThumbPlaceholder();

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF3B2E7A), Color(0xFF1C2542)],
        ),
      ),
      child: const Center(
        child: Icon(
          Icons.play_arrow_rounded,
          color: Colors.white70,
          size: 30,
        ),
      ),
    );
  }
}

/// Small filled stat chip, e.g. "1080p" / "14.2 MB" on the preview card.
class StatChip extends StatelessWidget {
  const StatChip(this.text, {super.key, this.mono = true});

  final String text;
  final bool mono;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: ZipColors.surfaceRaised,
        borderRadius: BorderRadius.circular(9),
      ),
      child: Text(
        text,
        style: mono
            ? ZipTheme.mono(size: 12, weight: FontWeight.w600)
            : const TextStyle(
                fontFamily: ZipFonts.ui,
                fontWeight: FontWeight.w600,
                fontSize: 12,
                color: ZipColors.text,
              ),
      ),
    );
  }
}

/// The permanent legal line shown on Home (and in the first-run notice).
class LegalLine extends StatelessWidget {
  const LegalLine({super.key});

  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.symmetric(vertical: 14),
      child: Text(
        'Only save videos you made or have permission to keep.',
        textAlign: TextAlign.center,
        style: TextStyle(
          fontFamily: ZipFonts.ui,
          fontSize: 12.5,
          color: ZipColors.muted,
          height: 1.5,
        ),
      ),
    );
  }
}

/// "4.2 GB free" chip used in the Downloads header.
class FreeSpaceChip extends StatelessWidget {
  const FreeSpaceChip({super.key, required this.bytes});

  final int? bytes;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      decoration: BoxDecoration(
        color: ZipColors.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: ZipColors.line),
      ),
      child: Text(
        bytes == null ? '— free' : '${ZipFormat.bytes(bytes)} free',
        style: ZipTheme.mono(size: 12.5, color: ZipColors.muted),
      ),
    );
  }
}
