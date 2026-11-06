import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../models/download_state.dart';
import '../../theme/app_theme.dart';
import '../../widgets/sheet_scroll.dart';

/// "8. Quality selector" — used for streaming quality (Wi-Fi / mobile data,
/// as independent preferences per the request) and download quality.
/// Restyled to the boards: glass sheet, raised option rows, the current
/// choice marked with a violet fill, a check and a green "Current" chip.
Future<StreamingQuality?> showQualitySelectorSheet(
  BuildContext context, {
  required String title,
  required StreamingQuality current,
}) {
  return showModalBottomSheet<StreamingQuality>(
    context: context,
    isScrollControlled: true,
    builder: (sheetContext) => SheetScroll(
        child: _QualitySelectorSheet(title: title, current: current)),
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
            child: Text(title,
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
                  for (var i = 0; i < StreamingQuality.values.length; i++) ...[
                    if (i > 0)
                      Divider(
                          height: 1,
                          thickness: 1,
                          color: Colors.white.withValues(alpha: 0.06)),
                    _QualityRow(
                      quality: StreamingQuality.values[i],
                      selected: StreamingQuality.values[i] == current,
                      onTap: () =>
                          Navigator.of(context).pop(StreamingQuality.values[i]),
                    ),
                  ],
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
        ],
      ),
    );
  }
}

class _QualityRow extends StatelessWidget {
  final StreamingQuality quality;
  final bool selected;
  final VoidCallback onTap;

  const _QualityRow({
    required this.quality,
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
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(quality.label,
                      style: GoogleFonts.getFont(currentFontFamily,
                          color: kTextColor,
                          fontSize: 14,
                          fontWeight: FontWeight.w600)),
                  const SizedBox(height: 2),
                  Text(quality.description,
                      style: GoogleFonts.getFont(currentFontFamily,
                          color: kStatusText, fontSize: 12, height: 16 / 12)),
                ],
              ),
            ),
            const SizedBox(width: 12),
            if (selected) ...[
              Container(
                height: 24,
                padding: const EdgeInsets.symmetric(horizontal: 10),
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: kGreen.withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text('Current',
                    style: GoogleFonts.getFont(currentFontFamily,
                        color: kGreenLight,
                        fontSize: 12,
                        fontWeight: FontWeight.w600)),
              ),
              const SizedBox(width: 8),
              const Icon(Icons.check_rounded, size: 18, color: kVioletLight),
            ],
          ],
        ),
      ),
    );
  }
}
