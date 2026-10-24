import 'dart:io';

import 'package:flutter/foundation.dart';

import 'package:flutter/material.dart';

/// The desktop numbers, defined once (design doc: "Design foundations").
///
/// The point of this file is that no screen invents its own breakpoint,
/// gutter or row height again: window chrome, content frames and rows all read
/// from here, so a page cannot drift from the shell.
/// True on native desktop, where long-press sheets are replaced by
/// right-click menus and the shell uses desktop layout rules.
bool get isDesktopPlatform =>
    !kIsWeb &&
    (Platform.isWindows || Platform.isLinux || Platform.isMacOS);

class DesktopTokens {
  const DesktopTokens._();

  // --- Shell chrome -------------------------------------------------------
  /// Title bar height, once the custom bar lands (phase 6).
  static const double titleBarHeight = 40;

  /// Sidebar width, expanded and collapsed.
  static const double sidebarExpanded = 240;
  static const double sidebarCollapsed = 72;

  /// Player bar height (three zones, transport under the seek bar).
  static const double playerBarHeight = 88;

  /// Below this window width the sidebar collapses on its own.
  static const double autoCollapseBelow = 1100;

  // --- Content widths -----------------------------------------------------
  /// Home, Search and detail pages.
  static const double contentStandard = 1280;

  /// Tables get more room so no column is ever clipped.
  static const double contentTable = 1600;

  /// Settings: a label and its control must stay close together.
  static const double contentSettings = 720;

  /// Text lists (Books and podcasts).
  static const double contentText = 960;

  // --- Rhythm -------------------------------------------------------------
  /// 24 px gutter from 1100 px window width, 16 px below it.
  static double gutter(double windowWidth) =>
      windowWidth >= autoCollapseBelow ? 24 : 16;

  /// The only spacing steps allowed.
  static const List<double> spacing = [4, 8, 12, 16, 24, 32];

  /// Row heights: lists, tables, compact.
  static const double rowList = 48;
  static const double rowTable = 44;
  static const double rowCompact = 36;

  /// Focus ring: 2 px brand violet, 2 px offset.
  static const double focusRingWidth = 2;
  static const double focusRingOffset = 2;

  // --- Type scale ---------------------------------------------------------
  /// Page title 28/36 bold.
  static TextStyle pageTitle(TextStyle base) =>
      base.copyWith(fontSize: 28, height: 36 / 28, fontWeight: FontWeight.w700);

  /// Section heading 20/28 bold.
  static TextStyle section(TextStyle base) =>
      base.copyWith(fontSize: 20, height: 28 / 20, fontWeight: FontWeight.w700);

  /// Body 14/20.
  static TextStyle body(TextStyle base) =>
      base.copyWith(fontSize: 14, height: 20 / 14);

  /// Secondary 13/18.
  static TextStyle secondary(TextStyle base) =>
      base.copyWith(fontSize: 13, height: 18 / 13);

  /// Caption 12/16 — nothing in the desktop UI goes below this.
  static TextStyle caption(TextStyle base) =>
      base.copyWith(fontSize: 12, height: 16 / 12);
}

/// Centres a page inside the window at the designed maximum width and keeps
/// the same left edge for titles, tabs and tables.
///
/// Extra window width becomes margin, never wider rows — the single change
/// that stops a 1920 px window from stretching a phone layout.
class DesktopContentFrame extends StatelessWidget {
  final Widget child;
  final double maxWidth;

  const DesktopContentFrame({
    super.key,
    required this.child,
    this.maxWidth = DesktopTokens.contentStandard,
  });

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        final gutter = DesktopTokens.gutter(width);
        final inner = (width - gutter * 2).clamp(0.0, maxWidth);
        final side = ((width - inner) / 2).clamp(0.0, double.infinity);
        return Padding(
          padding: EdgeInsets.symmetric(horizontal: side < gutter ? gutter : side),
          child: SizedBox(width: inner, child: child),
        );
      },
    );
  }
}
