import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../models/artwork_style.dart';
import '../../theme/app_theme.dart';
import '../../widgets/sheet_scroll.dart';

Future<ArtworkStyle?> showArtworkStyleSheet(BuildContext context, ArtworkStyle current) {
  return showModalBottomSheet<ArtworkStyle>(
    context: context,
    isScrollControlled: true,
    builder: (sheetContext) => SheetScroll(child: SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(height: 8),
          Container(width: 36, height: 4, decoration: BoxDecoration(color: Colors.white24, borderRadius: BorderRadius.circular(2))),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 4),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text('Artwork style', style: headingFont(color: kTextColor, fontSize: 16, fontWeight: FontWeight.w600)),
            ),
          ),
          for (final style in ArtworkStyle.values)
            ListTile(
              leading: Icon(
                style == current ? Icons.radio_button_checked_rounded : Icons.radio_button_off_rounded,
                color: style == current ? kBrandColor : kMutedTextColor,
              ),
              title: Text(style.label, style: GoogleFonts.getFont(currentFontFamily, color: Colors.white, fontSize: 14, fontWeight: FontWeight.w500)),
              trailing: Container(
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
              onTap: () => Navigator.of(context).pop(style),
            ),
          const SizedBox(height: 8),
        ],
      ),
    )),
  );
}
