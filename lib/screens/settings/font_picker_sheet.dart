import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import '../../state/app_state.dart';
import '../../theme/app_theme.dart';

/// Font picker — each option previews live in its own typeface, so the
/// choice is visible before committing to it.
void showFontPickerSheet(BuildContext context) {
  showModalBottomSheet(
    context: context,
    isScrollControlled: true,
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
        padding: const EdgeInsets.only(top: 12, bottom: 8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(width: 36, height: 4, decoration: BoxDecoration(color: Colors.white24, borderRadius: BorderRadius.circular(2))),
            const SizedBox(height: 16),
            Text('App font', style: GoogleFonts.getFont(currentFontFamily, color: Colors.white, fontSize: 15, fontWeight: FontWeight.w600)),
            const SizedBox(height: 4),
            Text('Applies everywhere in the app', style: GoogleFonts.getFont(currentFontFamily, color: kMutedTextColor, fontSize: 12)),
            Flexible(
              child: ListView(
                shrinkWrap: true,
                padding: const EdgeInsets.symmetric(vertical: 8),
                children: [
                  for (final font in kAvailableFonts)
                    ListTile(
                      title: Text(font, style: GoogleFonts.getFont(font, color: Colors.white, fontSize: 16, fontWeight: FontWeight.w500)),
                      subtitle: Text('The quick brown fox jumps', style: GoogleFonts.getFont(font, color: kMutedTextColor, fontSize: 12)),
                      trailing: font == current ? const Icon(Icons.check_circle_rounded, color: kBrandColor) : null,
                      onTap: () {
                        context.read<AppState>().updateFontFamily(font);
                        Navigator.of(context).pop();
                      },
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
