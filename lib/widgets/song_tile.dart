import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import '../models/download_state.dart';
import '../models/song.dart';
import '../state/app_state.dart';
import '../theme/app_theme.dart';
import 'artwork_thumb.dart';
import 'song_actions_sheet.dart';

/// A single row in any song list (Home rails use cards instead — see
/// RecentSongCard — this is for Library/Album/Playlist/Search/Queue lists).
/// Shows a track number instead of artwork when [index] is provided (album
/// detail track lists), a download-progress ring while downloading, and
/// opens the shared "⋮" actions sheet.
class SongTile extends StatelessWidget {
  final Song song;
  final VoidCallback onTap;
  final int? index;
  final bool showArtist;
  final bool highlighted;

  const SongTile({
    super.key,
    required this.song,
    required this.onTap,
    this.index,
    this.showArtist = true,
    this.highlighted = false,
  });

  @override
  Widget build(BuildContext context) {
    final download = context.select<AppState, DownloadStatus>((s) => s.downloadStatusFor(song.id));
    final accent = song.gradientColors.last;

    return ListTile(
      onTap: onTap,
      onLongPress: () => showSongActionsSheet(context, song),
      contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 2),
      leading: index != null
          ? SizedBox(
              width: 44,
              child: Center(
                child: Text('$index', style: GoogleFonts.getFont(currentFontFamily, color: kMutedTextColor, fontSize: 13)),
              ),
            )
          : ArtworkThumb(gradientColors: song.gradientColors, artwork: song.artwork, size: 46, radius: 8),
      title: Text(
        song.title,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: GoogleFonts.getFont(currentFontFamily, 
          color: highlighted ? accent : Colors.white,
          fontSize: 14,
          fontWeight: FontWeight.w500,
        ),
      ),
      subtitle: showArtist
          ? Text(song.artist, maxLines: 1, overflow: TextOverflow.ellipsis,
              style: GoogleFonts.getFont(currentFontFamily, color: kMutedTextColor, fontSize: 12))
          : null,
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (download.stage == DownloadStage.downloading)
            Padding(
              padding: const EdgeInsets.only(right: 4),
              child: SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(strokeWidth: 2, value: download.progress, color: accent),
              ),
            )
          else if (download.stage == DownloadStage.downloaded)
            Padding(
              padding: const EdgeInsets.only(right: 4),
              child: Icon(Icons.download_done_rounded, color: accent, size: 18),
            ),
          IconButton(
            icon: const Icon(Icons.more_vert_rounded, color: kMutedTextColor, size: 20),
            onPressed: () => showSongActionsSheet(context, song),
          ),
        ],
      ),
    );
  }
}
