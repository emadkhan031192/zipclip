import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/theme/app_theme.dart';
import 'core/theme/pressable.dart';
import 'features/batch/batch_screen.dart';
import 'features/downloads/downloads_screen.dart';
import 'features/home/home_screen.dart';
import 'features/settings/settings_screen.dart';
import 'providers/bootstrap.dart';

class ZipClipApp extends StatelessWidget {
  const ZipClipApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'ZipClip',
      debugShowCheckedModeBanner: false,
      theme: ZipTheme.dark,
      home: const MainScaffold(),
    );
  }
}

/// Root shell: bottom tab bar (Home / Downloads / Settings) with the violet
/// pill behind the active tab's icon, per the mockup.
class MainScaffold extends ConsumerStatefulWidget {
  const MainScaffold({super.key});

  @override
  ConsumerState<MainScaffold> createState() => _MainScaffoldState();
}

class _MainScaffoldState extends ConsumerState<MainScaffold> {
  int _tab = 0;
  bool _noticeShown = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _maybeFirstRun());
  }

  Future<void> _maybeFirstRun() async {
    if (_noticeShown || !mounted) return;
    _noticeShown = true;
    final repo = await ref.read(settingsRepoProvider.future);
    if (!mounted || repo.current.firstRunDone) return;
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        title: const Text('Before you start'),
        content: const Text(
          'ZipClip saves public videos to your phone.\n\n'
          'Only save videos you made or have permission to keep.',
          style: TextStyle(
            fontFamily: ZipFonts.ui,
            fontSize: 14,
            height: 1.5,
            color: ZipColors.text,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text(
              'Got it',
              style: TextStyle(
                color: ZipColors.accent,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
    await repo.update(repo.current.copyWith(firstRunDone: true));
  }

  void _go(int tab) => setState(() => _tab = tab);

  Future<void> openBatch() async {
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const BatchScreen()),
    );
  }

  @override
  Widget build(BuildContext context) {
    // A shared link arriving on another tab jumps back to Home to handle it.
    ref.listen(incomingLinkProvider, (prev, next) {
      if (next.isNotEmpty && _tab != 0 && mounted) {
        setState(() => _tab = 0);
      }
    });

    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: IndexedStack(
          index: _tab,
          children: [
            HomeScreen(
              onOpenBatch: openBatch,
              onOpenDownloads: () => _go(1),
              onOpenSettings: () => _go(2),
            ),
            const DownloadsScreen(),
            const SettingsScreen(),
          ],
        ),
      ),
      bottomNavigationBar: _BottomBar(tab: _tab, onTap: _go),
    );
  }
}

class _BottomBar extends StatelessWidget {
  const _BottomBar({required this.tab, required this.onTap});

  final int tab;
  final void Function(int) onTap;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: ZipColors.background,
        border: Border(top: BorderSide(color: ZipColors.line, width: 1)),
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Row(
            children: [
              _item(0, Icons.home_outlined, Icons.home_rounded, 'Home'),
              _item(1, Icons.arrow_downward_rounded,
                  Icons.arrow_downward_rounded, 'Downloads',),
              _item(2, Icons.tune_rounded, Icons.tune_rounded, 'Settings'),
            ],
          ),
        ),
      ),
    );
  }

  Widget _item(int index, IconData icon, IconData activeIcon, String label) {
    final active = tab == index;
    return Expanded(
      child: Pressable(
        onTap: () => onTap(index),
        semanticLabel: label,
        borderRadius: BorderRadius.circular(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 18, vertical: 7),
              decoration: BoxDecoration(
                color: active ? ZipColors.accent : Colors.transparent,
                borderRadius: BorderRadius.circular(20),
              ),
              child: Icon(
                active ? activeIcon : icon,
                color: active ? Colors.white : ZipColors.muted,
                size: 24,
              ),
            ),
            const SizedBox(height: 3),
            Text(
              label,
              style: TextStyle(
                fontFamily: ZipFonts.ui,
                fontWeight: FontWeight.w600,
                fontSize: 12,
                color: active ? ZipColors.text : ZipColors.muted,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
