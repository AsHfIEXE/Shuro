import 'dart:io';

import 'package:flutter/foundation.dart';

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import '../models/download_state.dart';
import '../models/song.dart';
import '../services/download_service.dart';
import '../theme/app_theme.dart';
import '../theme/desktop_tokens.dart';
import 'artwork_thumb.dart';
import 'desktop_context_menu.dart';
import 'song_actions_sheet.dart';

/// A single row in any song list (Home rails use cards instead — see
/// RecentSongCard — this is for Library/Album/Playlist/Search/Queue lists).
/// Shows a track number instead of artwork when [index] is provided (album
/// detail track lists), a download-progress ring while downloading, and
/// opens the shared "⋮" actions sheet.
class SongTile extends StatelessWidget {
  final Song song;

  /// Anchors the desktop ellipsis menu under the button.
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
    final download = context.select<DownloadService, DownloadStatus>((s) => s.statusFor(song.id));
    final accent = song.gradientColors.last;

    return ContextMenuRegion(
      items: songContextMenuItems(context, song),
      child: ListTile(
        onTap: onTap,
        // Hold-to-open is touch-only now; desktop right-clicks.
        onLongPress: isDesktopPlatform
            ? null
            : () => showSongActionsSheet(context, song),
        contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 2),
        leading: index != null
            ? SizedBox(
                width: 44,
                child: Center(
                  child: Text('$index',
                      style: GoogleFonts.getFont(currentFontFamily,
                          color: kMutedTextColor, fontSize: 13)),
                ),
              )
            : ArtworkThumb(
                gradientColors: song.gradientColors,
                artwork: song.artwork,
                size: 46,
                radius: 8,
              ),
        title: Text(
          song.title,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: GoogleFonts.getFont(
            currentFontFamily,
            color: highlighted ? accent : Colors.white,
            fontSize: 14,
            fontWeight: FontWeight.w500,
          ),
        ),
        subtitle: showArtist
            ? Text(song.artist,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: GoogleFonts.getFont(currentFontFamily,
                    color: kMutedTextColor, fontSize: 12))
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
                  child: CircularProgressIndicator(
                      strokeWidth: 2,
                      value: download.progress,
                      color: accent),
                ),
              )
            else if (download.stage == DownloadStage.downloaded)
              Padding(
                padding: const EdgeInsets.only(right: 4),
                child: Icon(Icons.download_done_rounded,
                    color: accent, size: 18),
              ),
            Builder(
              builder: (buttonContext) => IconButton(
                icon: const Icon(Icons.more_vert_rounded,
                    color: kMutedTextColor, size: 20),
                onPressed: () {
                  // A menu anchored to this button on desktop, the sheet
                  // everywhere else (design doc: "Menus"). Long-press keeps
                  // the sheet on touch.
                  if (!kIsWeb &&
                      (Platform.isWindows ||
                          Platform.isLinux ||
                          Platform.isMacOS)) {
                    showSongMenuAtAnchor(context, song, buttonContext);
                  } else {
                    showSongActionsSheet(context, song);
                  }
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}
