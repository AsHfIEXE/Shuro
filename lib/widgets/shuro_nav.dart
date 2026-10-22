import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../theme/app_theme.dart';
import 'app_logo.dart';

/// Shuro's navigation, shared by every form factor.
///
/// Designed after the owner's reference: a compact floating bar — a rounded
/// *rectangle* (16 px corners, not a capsule), icon-only, active item white and
/// inactive items quiet grey. The single state signal beyond white/grey is a
/// 4 px dot under the active icon, so the active tab is still identifiable for
/// colour-blind users and on dim screens.
///
/// Phones get the floating bar centred above the bottom edge; wide screens get
/// the same items in a slim rail with the app mark on top and labels kept
/// (at rail width there is space, and labels help D-pad navigation).
class ShuroNavBar extends StatelessWidget {
  final int currentIndex;
  final ValueChanged<int> onTap;

  /// Optional content rendered inside the same rounded block, above the nav
  /// items — the Now Playing mini player lives here, so the player and the
  /// navigation form ONE continuous surface instead of two stacked shapes
  /// with mismatched corners.
  final Widget? header;

  const ShuroNavBar(
      {super.key,
      required this.currentIndex,
      required this.onTap,
      this.header});

  static const List<_ShuroNavDestination> destinations = [
    _ShuroNavDestination(
        icon: Icons.home_outlined,
        activeIcon: Icons.home_rounded,
        label: 'Home'),
    _ShuroNavDestination(
        icon: Icons.library_music_outlined,
        activeIcon: Icons.library_music_rounded,
        label: 'Library'),
    _ShuroNavDestination(
        icon: Icons.search_outlined,
        activeIcon: Icons.search_rounded,
        label: 'Search'),
    _ShuroNavDestination(
        icon: Icons.auto_awesome_outlined,
        activeIcon: Icons.auto_awesome_rounded,
        label: 'Shuro Pulse'),
    _ShuroNavDestination(
        icon: Icons.favorite_outlined,
        activeIcon: Icons.favorite_rounded,
        label: 'Favorites'),
  ];

  @override
  Widget build(BuildContext context) {
    // Full-width bottom bar: edge to edge, rounded top corners, and the mini
    // player merged into the same block — one surface, one set of corners.
    return Container(
      decoration: BoxDecoration(
        color: kCardColor,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
        border: const Border(top: BorderSide(color: Color(0x14FFFFFF))),
        boxShadow: [
          BoxShadow(
              color: Colors.black.withValues(alpha: 0.45),
              blurRadius: 22,
              offset: const Offset(0, -8))
        ],
      ),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (header != null) header!,
            SizedBox(
              height: 74,
              child: Row(
                children: [
                  for (var i = 0; i < destinations.length; i++)
                    Expanded(
                      child: _ShuroNavItem(
                        destination: destinations[i],
                        selected: currentIndex == i,
                        showLabel: true,
                        onTap: () => onTap(i),
                      ),
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

/// The wide-screen companion: the same destinations, stacked, with the app mark
/// on top. Fixed width on purpose — a rail that resizes with content is a rail
/// that jitters.
class ShuroRail extends StatelessWidget {
  final int currentIndex;
  final ValueChanged<int> onTap;

  const ShuroRail({super.key, required this.currentIndex, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    // Width scales with the window (phones 86, tablets 104, desktop/TV 116)
    // and the rail gets denser when the height is tight — a 320 dp-tall
    // landscape window must fit five destinations without clipping.
    final railWidth =
        size.width >= 1200 ? 116.0 : (size.width >= 900 ? 104.0 : 86.0);
    final compact = size.height < 420;
    return Container(
      width: railWidth,
      decoration: const BoxDecoration(
        color: kCardColor,
        border: Border(right: BorderSide(color: kDividerColor)),
      ),
      child: SafeArea(
        right: false,
        // Scrolls on a short landscape phone, where the logo plus five
        // labelled items is taller than the ~360 dp screen (that overflow was
        // the yellow/black stripes on every landscape screen).
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (MediaQuery.sizeOf(context).height >= 480) ...[
                const Padding(
                  padding: EdgeInsets.only(top: 20, bottom: 10),
                  child: Center(child: AppLogo(size: 38)),
                ),
                const SizedBox(height: 8),
              ] else
                const SizedBox(height: 8),
              for (var i = 0; i < ShuroNavBar.destinations.length; i++)
                Padding(
                  padding: EdgeInsets.symmetric(vertical: compact ? 0 : 2),
                  child: _ShuroNavItem(
                    destination: ShuroNavBar.destinations[i],
                    selected: currentIndex == i,
                    // Labels stay on phones/tablets; on a very wide rail they
                    // are unmissable either way, and on a 320 dp-tall window
                    // the icons alone keep every destination on screen.
                    showLabel: !compact,
                    onTap: () => onTap(i),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ShuroNavDestination {
  final IconData icon;
  final IconData activeIcon;
  final String label;

  const _ShuroNavDestination(
      {required this.icon, required this.activeIcon, required this.label});
}

class _ShuroNavItem extends StatelessWidget {
  final _ShuroNavDestination destination;
  final bool selected;
  final bool showLabel;
  final VoidCallback onTap;

  const _ShuroNavItem({
    required this.destination,
    required this.selected,
    required this.showLabel,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final iconColumn = Column(
      mainAxisSize: MainAxisSize.min,
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        AnimatedSwitcher(
          duration: const Duration(milliseconds: 180),
          switchInCurve: Curves.easeOut,
          switchOutCurve: Curves.easeIn,
          transitionBuilder: (child, animation) => FadeTransition(
            opacity: animation,
            child: ScaleTransition(
                scale: Tween(begin: 0.85, end: 1.0).animate(animation),
                child: child),
          ),
          child: Icon(
            selected ? destination.activeIcon : destination.icon,
            key: ValueKey(selected),
            size: 23,
            color: selected ? Colors.white : kMutedTextColor,
          ),
        ),
        const SizedBox(height: 5),
        // The active-state dot: small, brand-coloured, and the only chrome —
        // no pill, no background, matching the reference's minimal look while
        // keeping the selected tab unambiguous.
        AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          width: selected ? 4 : 0,
          height: 4,
          decoration: BoxDecoration(
            color: selected ? kBrandColor : Colors.transparent,
            borderRadius: BorderRadius.circular(2),
          ),
        ),
      ],
    );

    final item = showLabel
        ? Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              iconColumn,
              const SizedBox(height: 4),
              Text(
                destination.label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: GoogleFonts.getFont(
                  currentFontFamily,
                  fontSize: 11,
                  fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                  color: selected ? Colors.white : kMutedTextColor,
                  height: 1.1,
                ),
              ),
            ],
          )
        : iconColumn;

    return Semantics(
      button: true,
      selected: selected,
      label: destination.label,
      child: Tooltip(
        message: destination.label,
        waitDuration: const Duration(milliseconds: 450),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(12),
          child: Padding(
            padding: showLabel
                ? const EdgeInsets.symmetric(vertical: 8, horizontal: 4)
                : const EdgeInsets.all(12),
            child: item,
          ),
        ),
      ),
    );
  }
}
