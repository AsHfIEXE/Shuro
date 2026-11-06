import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../models/artwork_style.dart';
import '../../theme/app_theme.dart';
import '../../widgets/sheet_scroll.dart';

/// Artwork-style picker, styled to the boards: raised option rows, the
/// current style marked with a violet fill and a check.
Future<ArtworkStyle?> showArtworkStyleSheet(
    BuildContext context, ArtworkStyle current) {
  return showModalBottomSheet<ArtworkStyle>(
    context: context,
    isScrollControlled: true,
    builder: (sheetContext) => SheetScroll(
        child: SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SizedBox(height: 8),
          Center(
            child: Container(
                width: 36,
                height: 4,
                decoration: BoxDecoration(
                    color: Colors.white24,
                    borderRadius: BorderRadius.circular(2))),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 12),
            child: Text('Artwork style',
                style: GoogleFonts.getFont(currentFontFamily,
                    color: kTextColor,
                    fontSize: 16,
                    fontWeight: FontWeight.w700)),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: kRaisedColor,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: kHairline),
              ),
              child: Column(
                children: [
                  for (var i = 0; i < ArtworkStyle.values.length; i++) ...[
                    if (i > 0)
                      Divider(
                          height: 1,
                          thickness: 1,
                          color: Colors.white.withValues(alpha: 0.06)),
                    _ArtworkStyleRow(
                      style: ArtworkStyle.values[i],
                      selected: ArtworkStyle.values[i] == current,
                      onTap: () =>
                          Navigator.of(context).pop(ArtworkStyle.values[i]),
                    ),
                  ],
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
        ],
      ),
    )),
  );
}

class _ArtworkStyleRow extends StatelessWidget {
  final ArtworkStyle style;
  final bool selected;
  final VoidCallback onTap;

  const _ArtworkStyleRow({
    required this.style,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        decoration: BoxDecoration(
          color: selected
              ? kBrandColor.withValues(alpha: 0.12)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(12),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        child: Row(
          children: [
            Expanded(
              child: Text(style.label,
                  style: GoogleFonts.getFont(currentFontFamily,
                      color: kTextColor,
                      fontSize: 14,
                      fontWeight: FontWeight.w600)),
            ),
            const SizedBox(width: 12),
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                gradient: const LinearGradient(colors: kBrandGradient),
                borderRadius: style == ArtworkStyle.square
                    ? BorderRadius.zero
                    : style == ArtworkStyle.circle
                        ? BorderRadius.circular(999)
                        : BorderRadius.circular(10),
              ),
            ),
            if (selected) ...[
              const SizedBox(width: 12),
              const Icon(Icons.check_rounded, size: 18, color: kVioletLight),
            ],
          ],
        ),
      ),
    );
  }
}
