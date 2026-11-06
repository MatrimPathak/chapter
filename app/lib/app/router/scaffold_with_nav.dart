import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/design_system/design_system.dart';
import '../../features/profile/application/account_actions.dart';
import '../../features/reading/application/session_controller.dart';
import '../../features/reading/presentation/active_session_bar.dart';
import '../../l10n/generated/app_localizations.dart';
import '../providers.dart';
import 'routes.dart';

/// Shell for the five primary destinations. Each tab keeps its own
/// navigation stack and scroll state (`StatefulShellRoute.indexedStack`).
///
/// Also hosts the active session bar and opens a recovered session once at
/// launch (docs/02 §6).
class ScaffoldWithNav extends ConsumerStatefulWidget {
  const ScaffoldWithNav({required this.shell, super.key});

  final StatefulNavigationShell shell;

  /// Index of the emphasised Read tab.
  static const readIndex = 2;

  @override
  ConsumerState<ScaffoldWithNav> createState() => _ScaffoldWithNavState();
}

class _ScaffoldWithNavState extends ConsumerState<ScaffoldWithNav> {
  bool _checkedRecovery = false;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final shell = widget.shell;
    final session = ref.watch(sessionControllerProvider);
    ref.watch(importRunnerProvider); // resumes an unfinished import
    ref.watch(accountWatchProvider); // deleted elsewhere? clears this device
    if (!_checkedRecovery && session.hasValue) {
      _checkedRecovery = true;
      // A session survived a restart: take the reader straight back to it.
      if (session.value != null) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) context.push(AppRoutes.session);
        });
      }
    }
    return Scaffold(
      body: shell,
      bottomNavigationBar: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const ActiveSessionBar(),
          ChapterNavBar(
            selectedIndex: shell.currentIndex,
            emphasizedIndex: ScaffoldWithNav.readIndex,
            onSelected: (index) => shell.goBranch(
              index,
              // Re-tapping the active tab returns to its root.
              initialLocation: index == shell.currentIndex,
            ),
            items: [
              ChapterNavItem(
                label: l10n.navHome,
                icon: Icons.home_outlined,
                selectedIcon: Icons.home_rounded,
              ),
              ChapterNavItem(
                label: l10n.navLibrary,
                icon: Icons.auto_stories_outlined,
                selectedIcon: Icons.auto_stories_rounded,
              ),
              ChapterNavItem(
                label: l10n.navRead,
                icon: Icons.timer_outlined,
                selectedIcon: Icons.timer_rounded,
              ),
              ChapterNavItem(
                label: l10n.navSearch,
                icon: Icons.search_rounded,
                selectedIcon: Icons.search_rounded,
              ),
              ChapterNavItem(
                label: l10n.navProfile,
                icon: Icons.person_outline_rounded,
                selectedIcon: Icons.person_rounded,
              ),
            ],
          ),
        ],
      ),
    );
  }
}
