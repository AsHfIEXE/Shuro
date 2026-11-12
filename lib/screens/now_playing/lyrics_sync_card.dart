import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';

import '../../state/app_state.dart';
import '../../theme/app_theme.dart';
import '../../widgets/click_region.dart';
import 'lyrics_appearance_sheet.dart';

/// Board: "Lyrics - tools and states" -> Sync offset card. Nudge in 0.5 s
/// steps; "Only this song" keeps the correction on the current track.
Future<void> showLyricsSyncCard(BuildContext context, {String? songId}) {
  return showDialog<void>(
    context: context,
    barrierColor: Colors.black.withValues(alpha: 0.5),
    builder: (_) => Dialog(
      backgroundColor: Colors.transparent,
      elevation: 0,
      insetPadding: const EdgeInsets.all(16),
      child: _SyncCard(songId: songId),
    ),
  );
}

class _SyncCard extends StatelessWidget {
  const _SyncCard({this.songId});
  final String? songId;

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final ms = app.lyricsOffsetFor(songId);
    final label = ms == 0
        ? '0.0 s'
        : '${ms > 0 ? '+' : '−'}${(ms.abs() / 1000).toStringAsFixed(1)} s';
    TextStyle t(double s, FontWeight w, Color c) =>
        GoogleFonts.getFont(currentFontFamily,
            fontSize: s, fontWeight: w, color: c);

    Widget pill(String text, int delta) => ClickRegion(
          onTap: () => app.nudgeLyricsOffset(songId, ms + delta),
          child: Container(
            width: 70,
            height: 40,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Text(text,
                style: t(12, FontWeight.w600, const Color(0xFFE8E8F0))),
          ),
        );

    return LyricsPanel(
      label: 'SYNC OFFSET',
      width: 420,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Transform.translate(
            offset: const Offset(0, -6),
            child: Text(ms == 0 ? 'Lyrics in sync' : 'Lyrics shifted',
                style: t(16, FontWeight.w700, const Color(0xFFE8E8F0))),
          ),
          const SizedBox(height: 2),
          Text('Nudge if the words land early or late.',
              style: t(12, FontWeight.w400, const Color(0xFF9AA3B5))),
          const SizedBox(height: 18),
          Row(children: [
            pill('−0.5 s', -500),
            Expanded(
              child: Center(
                child: Text(label,
                    style: t(22, FontWeight.w800, const Color(0xFFC4B5FD))),
              ),
            ),
            pill('+0.5 s', 500),
          ]),
          const SizedBox(height: 18),
          Row(children: [
            Text('Only this song',
                style: t(13, FontWeight.w600, const Color(0xFFE8E8F0))),
            const SizedBox(width: 12),
            LyricsSwitch(
                value: app.lyricsOffsetPerSong,
                onChanged: app.setLyricsOffsetPerSong),
            const Spacer(),
            ClickRegion(
              onTap: () => app.nudgeLyricsOffset(songId, 0, reset: true),
              child: Text('Reset',
                  style: t(12, FontWeight.w600, const Color(0xFFA78BFA))),
            ),
          ]),
        ],
      ),
    );
  }
}
