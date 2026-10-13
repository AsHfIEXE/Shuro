import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../theme/app_theme.dart';

/// Recurring "Title ... See all" row used to head every horizontal/section
/// list on Home, Library, Album/Artist detail, etc.
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
              style: headingFont(color: kTextColor, fontSize: 18, fontWeight: FontWeight.w600),
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
                      Text('See all', style: GoogleFonts.getFont(currentFontFamily, color: Colors.white70, fontSize: 13)),
                      const Icon(Icons.chevron_right_rounded, color: Colors.white70, size: 18),
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
