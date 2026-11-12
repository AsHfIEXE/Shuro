import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../theme/app_theme.dart';
import '../../widgets/click_region.dart';

/// Shared desktop-board controls for the Library tabs (count, "Filter …"
/// field, "Sort: …" dropdown, grid/list toggle, Play all / Shuffle pills,
/// "Showing N of M …" footer). Every tab composes these so the toolbar looks
/// and behaves the same everywhere.

enum LibraryView { grid, list }

/// h36 pill: violet filled (Play all) or glass (Shuffle / secondary).
class LibraryPill extends StatelessWidget {
  final String label;
  final IconData icon;
  final VoidCallback? onTap;
  final bool glass;

  const LibraryPill({
    super.key,
    required this.label,
    required this.icon,
    required this.onTap,
    this.glass = false,
  });

  @override
  Widget build(BuildContext context) {
    final foreground = glass ? kTextColor : Colors.white;
    final enabled = onTap != null;
    return Semantics(
      button: true,
      enabled: enabled,
      child: Opacity(
        opacity: enabled ? 1 : 0.45,
        child: ClickRegion(
          onTap: onTap,
          child: Container(
            height: 36,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            decoration: BoxDecoration(
              color: glass ? Colors.white.withValues(alpha: 0.06) : kBrandColor,
              borderRadius: BorderRadius.circular(999),
              border: glass
                  ? Border.all(color: Colors.white.withValues(alpha: 0.14))
                  : null,
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(icon, size: 16, color: foreground),
                const SizedBox(width: 6),
                Text(label,
                    style: GoogleFonts.getFont(currentFontFamily,
                        color: foreground,
                        fontSize: 13,
                        fontWeight: FontWeight.w600)),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// "Filter …" text field (h36, raised fill, search icon).
class LibraryFilterField extends StatelessWidget {
  final TextEditingController controller;
  final String hint;
  final VoidCallback onChanged;
  final double? width;

  const LibraryFilterField({
    super.key,
    required this.controller,
    required this.hint,
    required this.onChanged,
    this.width = 260,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: width,
      height: 36,
      child: TextField(
        controller: controller,
        onChanged: (_) => onChanged(),
        style: GoogleFonts.getFont(currentFontFamily,
            color: kTextColor, fontSize: 13),
        decoration: InputDecoration(
          isDense: true,
          hintText: hint,
          hintStyle: GoogleFonts.getFont(currentFontFamily,
              color: kMuted2, fontSize: 13),
          prefixIcon:
              const Icon(Icons.search_rounded, size: 16, color: kMuted2),
          prefixIconConstraints:
              const BoxConstraints(minWidth: 36, minHeight: 36),
          suffixIcon: controller.text.isEmpty
              ? null
              : IconButton(
                  padding: EdgeInsets.zero,
                  constraints:
                      const BoxConstraints(minWidth: 32, minHeight: 32),
                  icon: const Icon(Icons.close_rounded,
                      size: 14, color: kMuted2),
                  onPressed: () {
                    controller.clear();
                    onChanged();
                  },
                ),
          filled: true,
          fillColor: kRaisedColor,
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: BorderSide(color: kGlass),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: const BorderSide(color: kBrandColor),
          ),
        ),
      ),
    );
  }
}

/// "Sort: Name ⌄" dropdown. [options] keeps insertion order; the value shown
/// is `options[value]`, the menu items read "Sort: <label>".
class LibrarySortMenu<T> extends StatelessWidget {
  final T value;
  final Map<T, String> options;
  final ValueChanged<T> onSelected;

  const LibrarySortMenu({
    super.key,
    required this.value,
    required this.options,
    required this.onSelected,
  });

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<T>(
      color: kCardColor,
      initialValue: value,
      onSelected: onSelected,
      position: PopupMenuPosition.under,
      tooltip: 'Sort',
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      itemBuilder: (context) => [
        for (final e in options.entries)
          PopupMenuItem<T>(
            value: e.key,
            child: Text('Sort: ${e.value}',
                style: GoogleFonts.getFont(currentFontFamily,
                    color: Colors.white, fontSize: 13)),
          ),
      ],
      child: Container(
        height: 36,
        padding: const EdgeInsets.only(left: 12, right: 8),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: Colors.white.withValues(alpha: 0.12)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('Sort: ${options[value] ?? ''}',
                style: GoogleFonts.getFont(currentFontFamily,
                    color: kTextColor,
                    fontSize: 13,
                    fontWeight: FontWeight.w500)),
            const SizedBox(width: 4),
            const Icon(Icons.keyboard_arrow_down_rounded,
                size: 14, color: kMuted2),
          ],
        ),
      ),
    );
  }
}

/// Two-button grid / list switch (selected = violet tile).
class LibraryViewToggle extends StatelessWidget {
  final LibraryView value;
  final ValueChanged<LibraryView> onChanged;

  const LibraryViewToggle(
      {super.key, required this.value, required this.onChanged});

  Widget _button(LibraryView view, IconData icon, String tooltip) {
    final selected = value == view;
    return Tooltip(
      message: tooltip,
      child: ClickRegion(
        onTap: () => onChanged(view),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          curve: ShuroMotion.std,
          width: 28,
          height: 28,
          decoration: BoxDecoration(
            color: selected ? kBrandColor : Colors.transparent,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(icon,
              size: 16, color: selected ? Colors.white : kMuted2),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: kRaisedColor,
        borderRadius: BorderRadius.circular(11),
        border: Border.all(color: kGlass),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _button(LibraryView.grid, Icons.grid_view_rounded, 'Grid view'),
          const SizedBox(width: 2),
          _button(LibraryView.list, Icons.view_list_rounded, 'List view'),
        ],
      ),
    );
  }
}

/// Count + filter on the left, [trailing] controls on the right. Collapses
/// below 880 px; the controls stay flush right in both layouts.
class LibraryToolbar extends StatelessWidget {
  final String countLabel;
  final TextEditingController filterController;
  final String filterHint;
  final VoidCallback onFilterChanged;
  final List<Widget> trailing;
  final EdgeInsetsGeometry padding;

  const LibraryToolbar({
    super.key,
    required this.countLabel,
    required this.filterController,
    required this.filterHint,
    required this.onFilterChanged,
    required this.trailing,
    this.padding = const EdgeInsets.fromLTRB(20, 8, 20, 0),
  });

  List<Widget> _spaced(List<Widget> items) => [
        for (var i = 0; i < items.length; i++) ...[
          if (i > 0) const SizedBox(width: 8),
          items[i],
        ],
      ];

  @override
  Widget build(BuildContext context) {
    final count = Text(countLabel,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: GoogleFonts.getFont(currentFontFamily,
            color: kStatusText, fontSize: 14, fontWeight: FontWeight.w600));
    return Padding(
      padding: padding,
      child: LayoutBuilder(builder: (context, constraints) {
        // 880 keeps the widest tab's full row (count + 260 px filter +
        // sort + toggle + two pills) safely clear of overflow; narrower
        // columns fall through to the stacked layout below.
        if (constraints.maxWidth >= 880) {
          return Row(
            children: [
              count,
              const SizedBox(width: 24),
              LibraryFilterField(
                  controller: filterController,
                  hint: filterHint,
                  onChanged: onFilterChanged),
              const Spacer(),
              ..._spaced(trailing),
            ],
          );
        }
        // Narrow columns keep the desktop contract: count first, the
        // filter full width, and the controls flush RIGHT - stacked-left
        // buttons read as a mistake the moment a window is resized.
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            count,
            const SizedBox(height: 8),
            LibraryFilterField(
                controller: filterController,
                hint: filterHint,
                onChanged: onFilterChanged,
                width: null),
            const SizedBox(height: 8),
            Wrap(
                alignment: WrapAlignment.end,
                spacing: 8,
                runSpacing: 8,
                children: trailing),
          ],
        );
      }),
    );
  }
}

/// "Showing 12 of 38 artists" with an optional "Load more" action.
class LibraryFooter extends StatelessWidget {
  final int shown;
  final int total;
  final String noun;
  final VoidCallback? onLoadMore;
  final EdgeInsetsGeometry padding;

  const LibraryFooter({
    super.key,
    required this.shown,
    required this.total,
    required this.noun,
    this.onLoadMore,
    this.padding = const EdgeInsets.fromLTRB(0, 16, 0, 24),
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: padding,
      child: Row(
        children: [
          Text('Showing $shown of $total $noun',
              style: GoogleFonts.getFont(currentFontFamily,
                  color: kStatusText, fontSize: 12)),
          if (onLoadMore != null) ...[
            const SizedBox(width: 12),
            ClickRegion(
              onTap: onLoadMore,
              child: Text('Load more',
                  style: GoogleFonts.getFont(currentFontFamily,
                      color: kVioletLight,
                      fontSize: 12,
                      fontWeight: FontWeight.w600)),
            ),
          ],
        ],
      ),
    );
  }
}

/// Small uppercase section label ("SMART PLAYLISTS", "MOST PLAYED").
class LibrarySectionLabel extends StatelessWidget {
  final String text;
  const LibrarySectionLabel(this.text, {super.key});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Text(text,
          style: GoogleFonts.getFont(currentFontFamily,
              color: kMuted2,
              fontSize: 11,
              fontWeight: FontWeight.w700,
              letterSpacing: 1.1)),
    );
  }
}

/// Column description for [LibraryTableHeader] / [LibraryTableRow].
class LibraryColumn {
  final String label;
  final int flex;

  /// Fixed width instead of flex when non-null.
  final double? width;
  const LibraryColumn(this.label, {this.flex = 1, this.width});
}

Widget _cellBox(LibraryColumn c, Widget child) => c.width != null
    ? SizedBox(width: c.width, child: child)
    : Expanded(flex: c.flex, child: child);

/// Table header: `#` slot, then the columns, then a trailing actions slot.
class LibraryTableHeader extends StatelessWidget {
  final List<LibraryColumn> columns;
  const LibraryTableHeader({super.key, required this.columns});

  @override
  Widget build(BuildContext context) {
    final style = GoogleFonts.getFont(currentFontFamily,
        color: kMuted2,
        fontSize: 11,
        fontWeight: FontWeight.w700,
        letterSpacing: 1.0);
    return Container(
      height: 44,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
          border: Border(bottom: BorderSide(color: kHairline))),
      child: Row(
        children: [
          SizedBox(
              width: 36,
              child: Text('#', textAlign: TextAlign.center, style: style)),
          for (final c in columns)
            _cellBox(
                c,
                Padding(
                  padding: const EdgeInsets.only(right: 12),
                  child: Text(c.label,
                      maxLines: 1, overflow: TextOverflow.ellipsis, style: style),
                )),
          const SizedBox(width: 56),
        ],
      ),
    );
  }
}

/// One table row: index/leading, cells aligned to [columns], trailing action.
class LibraryTableRow extends StatefulWidget {
  final List<LibraryColumn> columns;
  final Widget index;
  final List<Widget> cells;
  final Widget? trailing;
  final VoidCallback onTap;

  const LibraryTableRow({
    super.key,
    required this.columns,
    required this.index,
    required this.cells,
    required this.onTap,
    this.trailing,
  });

  @override
  State<LibraryTableRow> createState() => _LibraryTableRowState();
}

class _LibraryTableRowState extends State<LibraryTableRow> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: ClickRegion(
        behavior: HitTestBehavior.opaque,
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          curve: ShuroMotion.std,
          height: 54,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          decoration: BoxDecoration(
            color: _hover ? Colors.white.withValues(alpha: 0.04) : Colors.transparent,
            border: Border(bottom: BorderSide(color: kHairline)),
          ),
          child: Row(
            children: [
              SizedBox(width: 36, child: Center(child: widget.index)),
              for (var i = 0; i < widget.columns.length; i++)
                _cellBox(
                    widget.columns[i],
                    Padding(
                      padding: const EdgeInsets.only(right: 12),
                      child: Align(
                          alignment: Alignment.centerLeft,
                          child: widget.cells[i]),
                    )),
              SizedBox(
                  width: 56,
                  child: Center(child: widget.trailing ?? const SizedBox())),
            ],
          ),
        ),
      ),
    );
  }
}

/// Standard text cell styles shared by the tables.
TextStyle libraryCellStyle({Color color = kNavText, double size = 13}) =>
    GoogleFonts.getFont(currentFontFamily, color: color, fontSize: size);

/// Raised table-card decoration (#111723 with hairline border).
BoxDecoration libraryTableCardDecoration() => BoxDecoration(
      color: const Color(0xFF111723),
      borderRadius: BorderRadius.circular(16),
      border: Border.all(color: kHairline),
    );

/// Plain `m:ss` duration label.
String libraryDuration(Duration d) {
  final m = d.inMinutes;
  final s = d.inSeconds % 60;
  return '$m:${s.toString().padLeft(2, '0')}';
}

/// "4.8 MB" style size label.
String libraryBytes(int bytes) {
  if (bytes >= 1024 * 1024 * 1024) {
    return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(1)} GB';
  }
  if (bytes >= 1024 * 1024) {
    final mb = bytes / (1024 * 1024);
    return '${mb.toStringAsFixed(mb >= 100 ? 0 : 1)} MB';
  }
  if (bytes >= 1024) return '${(bytes / 1024).toStringAsFixed(0)} KB';
  return '$bytes B';
}

/// "2 h ago" / "Yesterday" / "3 days ago" relative label.
String libraryAgo(DateTime t) {
  final diff = DateTime.now().difference(t);
  if (diff.inMinutes < 1) return 'Just now';
  if (diff.inMinutes < 60) return '${diff.inMinutes} min ago';
  if (diff.inHours < 24) return '${diff.inHours} h ago';
  if (diff.inDays == 1) return 'Yesterday';
  if (diff.inDays < 14) return '${diff.inDays} days ago';
  if (diff.inDays < 60) return '${(diff.inDays / 7).floor()} weeks ago';
  return '${(diff.inDays / 30).floor()} months ago';
}
