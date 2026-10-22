import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';

import '../../state/appearance_settings.dart';
import '../../theme/app_theme.dart';

/// Live controls for how the lyrics read (roadmap #27): size, alignment and
/// the accent glow. Everything applies the moment it moves — the lyrics
/// screen listens to the same [AppearanceSettings].
Future<void> showLyricsAppearanceSheet(BuildContext context) {
  return showModalBottomSheet<void>(
    context: context,
    backgroundColor: kSurfaceColor,
    shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(22))),
    builder: (sheetContext) => SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.text_fields_rounded,
                    size: 18, color: kBrandColor),
                const SizedBox(width: 8),
                Text('Lyrics appearance',
                    style: GoogleFonts.getFont(currentFontFamily,
                        color: Colors.white,
                        fontSize: 14.5,
                        fontWeight: FontWeight.w600)),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              'Applies to the lyrics screen on every device and stays saved.',
              style: GoogleFonts.getFont(currentFontFamily,
                  color: Colors.white38, fontSize: 11.5),
            ),
            const SizedBox(height: 14),
            const _FontScaleRow(),
            const SizedBox(height: 6),
            const _AlignRow(),
            const SizedBox(height: 6),
            const _GlowRow(),
          ],
        ),
      ),
    ),
  );
}

class _FontScaleRow extends StatelessWidget {
  const _FontScaleRow();

  @override
  Widget build(BuildContext context) {
    final appearance = context.watch<AppearanceSettings>();
    return Row(
      children: [
        Text('Aa',
            style: GoogleFonts.getFont(currentFontFamily,
                color: Colors.white38, fontSize: 12)),
        Expanded(
          child: Slider(
            value: appearance.lyricsFontScale,
            min: 0.85,
            max: 1.5,
            divisions: 13,
            activeColor: kBrandColor,
            label: '${(appearance.lyricsFontScale * 100).round()}%',
            onChanged: (v) => appearance.setLyricsFontScale(v),
          ),
        ),
        SizedBox(
          width: 44,
          child: Text('${(appearance.lyricsFontScale * 100).round()}%',
              textAlign: TextAlign.end,
              style: GoogleFonts.getFont(currentFontFamily,
                  color: Colors.white60, fontSize: 12)),
        ),
      ],
    );
  }
}

class _AlignRow extends StatelessWidget {
  const _AlignRow();

  @override
  Widget build(BuildContext context) {
    final appearance = context.watch<AppearanceSettings>();
    return Row(
      children: [
        Expanded(
          child: Text('Centre the text',
              style: GoogleFonts.getFont(currentFontFamily,
                  color: Colors.white70, fontSize: 13)),
        ),
        SegmentedButton<bool>(
          segments: const [
            ButtonSegment(value: false, label: Text('Left')),
            ButtonSegment(value: true, label: Text('Centre')),
          ],
          selected: {appearance.lyricsAlignCenter},
          showSelectedIcon: false,
          onSelectionChanged: (set) =>
              appearance.setLyricsAlignCenter(set.first),
        ),
      ],
    );
  }
}

class _GlowRow extends StatelessWidget {
  const _GlowRow();

  @override
  Widget build(BuildContext context) {
    final appearance = context.watch<AppearanceSettings>();
    return Row(
      children: [
        Expanded(
          child: Text('Glow on the sung line',
              style: GoogleFonts.getFont(currentFontFamily,
                  color: Colors.white70, fontSize: 13)),
        ),
        Switch(
          value: appearance.lyricsGlow,
          activeTrackColor: kBrandColor.withValues(alpha: 0.4),
          activeThumbColor: kBrandColor,
          onChanged: (v) => appearance.setLyricsGlow(v),
        ),
      ],
    );
  }
}
