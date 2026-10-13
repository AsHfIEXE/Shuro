import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../models/download_state.dart';
import '../../theme/app_theme.dart';

/// "8. Quality selector" — used for streaming quality (Wi-Fi / mobile data,
/// as independent preferences per the request) and download quality.
Future<StreamingQuality?> showQualitySelectorSheet(
  BuildContext context, {
  required String title,
  required StreamingQuality current,
}) {
  return showModalBottomSheet<StreamingQuality>(
    context: context,
    builder: (sheetContext) => _QualitySelectorSheet(title: title, current: current),
  );
}

class _QualitySelectorSheet extends StatelessWidget {
  final String title;
  final StreamingQuality current;
  const _QualitySelectorSheet({required this.title, required this.current});

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(height: 8),
          Container(width: 36, height: 4, decoration: BoxDecoration(color: Colors.white24, borderRadius: BorderRadius.circular(2))),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 4),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(title, style: GoogleFonts.getFont(currentFontFamily, color: Colors.white, fontSize: 16, fontWeight: FontWeight.w600)),
            ),
          ),
          for (final quality in StreamingQuality.values)
            ListTile(
              leading: Icon(
                quality == current ? Icons.radio_button_checked_rounded : Icons.radio_button_off_rounded,
                color: quality == current ? kBrandColor : kMutedTextColor,
              ),
              title: Text(quality.label, style: GoogleFonts.getFont(currentFontFamily, color: Colors.white, fontSize: 14, fontWeight: FontWeight.w500)),
              subtitle: Text(quality.description, style: GoogleFonts.getFont(currentFontFamily, color: kMutedTextColor, fontSize: 12)),
              onTap: () => Navigator.of(context).pop(quality),
            ),
          const SizedBox(height: 8),
        ],
      ),
    );
  }
}
