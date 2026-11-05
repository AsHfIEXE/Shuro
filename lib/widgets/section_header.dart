import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../theme/app_theme.dart';
import '../theme/desktop_tokens.dart';

/// Recurring "Title ... See all" row used to head every horizontal/section
/// list on Home, Library, Album/Artist detail, etc.
///
/// Title type is responsive per the redesign boards: 24/ExtraBold shelf
/// titles on desktop-width windows ([DesktopTokens.section]), ~20/700 on
/// phones. "See all" is brand violet with a chevron.
class SectionHeader extends StatelessWidget {
  final String title;
  final VoidCallback? onSeeAll;
  final EdgeInsetsGeometry padding;

  const SectionHeader({
    super.key,
    required this.title,
    this.onSeeAll,
    this.padding = const EdgeInsets.fromLTRB(20, 0, 20, 12),
  });

  @override
  Widget build(BuildContext context) {
    // Phones keep ~20/700; desktop-width windows get the boards' 24/800
    // shelf title straight from the shared token, so no screen can drift.
    final mobileTitle = headingFont(
        color: kTextColor, fontSize: 20, fontWeight: FontWeight.w700);
    final titleStyle = MediaQuery.sizeOf(context).width >= 800
        ? DesktopTokens.section(mobileTitle)
        : mobileTitle;
    return Padding(
      padding: padding,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Expanded(
            child: Text(
              title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: titleStyle,
            ),
          ),
          if (onSeeAll != null)
            // A real tap target (~44px tall) with a chevron, instead of a bare
            // 13px text run: "See all" is the only way deeper into a section,
            // and it used to be the smallest thing on the row.
            InkWell(
              onTap: onSeeAll,
              borderRadius: BorderRadius.circular(16),
              child: Semantics(
                button: true,
                label: 'See all $title',
                child: Container(
                  constraints: const BoxConstraints(minHeight: 44),
                  padding: const EdgeInsets.symmetric(horizontal: 10),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        'See all',
                        style: GoogleFonts.getFont(currentFontFamily,
                            color: kVioletLight,
                            fontSize: 13,
                            fontWeight: FontWeight.w600),
                      ),
                      const Icon(Icons.chevron_right_rounded,
                          color: kVioletLight, size: 18),
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
