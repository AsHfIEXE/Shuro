import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import '../../state/app_state.dart';
import '../../theme/app_theme.dart';

/// Font picker — each option previews live in its own typeface, so the
/// choice is visible before committing to it. Board styling: raised option
/// rows, the current font marked with a violet fill, a check and a green
/// "Current" chip.
void showFontPickerSheet(BuildContext context) {
  showModalBottomSheet(
    isScrollControlled: true,
    backgroundColor: kSurfaceColor,
    context: context,
    builder: (sheetContext) => const _FontPickerSheet(),
  );
}

class _FontPickerSheet extends StatelessWidget {
  const _FontPickerSheet();

  @override
  Widget build(BuildContext context) {
    final current = context.watch<AppState>().fontFamily;
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.only(top: 8, bottom: 8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(
              child: Container(
                  width: 36,
                  height: 4,
                  decoration: BoxDecoration(
                      color: Colors.white24,
                      borderRadius: BorderRadius.circular(2))),
            ),
            const SizedBox(height: 16),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Text('App font',
                  style: GoogleFonts.getFont(currentFontFamily,
                      color: kTextColor,
                      fontSize: 16,
                      fontWeight: FontWeight.w700)),
            ),
            const SizedBox(height: 4),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Text('Applies everywhere in the app',
                  style: GoogleFonts.getFont(currentFontFamily,
                      color: kStatusText, fontSize: 12)),
            ),
            const SizedBox(height: 12),
            Flexible(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: kRaisedColor,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: kHairline),
                  ),
                  child: ListView(
                    shrinkWrap: true,
                    padding: const EdgeInsets.all(4),
                    children: [
                      for (final font in kAvailableFonts)
                        InkWell(
                          borderRadius: BorderRadius.circular(12),
                          onTap: () {
                            context.read<AppState>().updateFontFamily(font);
                            Navigator.of(context).pop();
                          },
                          child: Container(
                            decoration: BoxDecoration(
                              color: font == current
                                  ? kBrandColor.withValues(alpha: 0.12)
                                  : Colors.transparent,
                              borderRadius: BorderRadius.circular(12),
                            ),
                            padding: const EdgeInsets.symmetric(
                                horizontal: 12, vertical: 10),
                            child: Row(
                              children: [
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(font,
                                          style: GoogleFonts.getFont(font,
                                              color: kTextColor,
                                              fontSize: 16,
                                              fontWeight: FontWeight.w600)),
                                      const SizedBox(height: 2),
                                      Text('The quick brown fox jumps',
                                          style: GoogleFonts.getFont(font,
                                              color: kStatusText,
                                              fontSize: 12)),
                                    ],
                                  ),
                                ),
                                if (font == current) ...[
                                  Container(
                                    height: 24,
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 10),
                                    alignment: Alignment.center,
                                    decoration: BoxDecoration(
                                      color: kGreen.withValues(alpha: 0.14),
                                      borderRadius: BorderRadius.circular(999),
                                    ),
                                    child: Text('Current',
                                        style: GoogleFonts.getFont(
                                            currentFontFamily,
                                            color: kGreenLight,
                                            fontSize: 12,
                                            fontWeight: FontWeight.w600)),
                                  ),
                                  const SizedBox(width: 8),
                                  const Icon(Icons.check_rounded,
                                      size: 18, color: kVioletLight),
                                ],
                              ],
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }
}
