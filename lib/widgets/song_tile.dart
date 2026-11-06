import 'dart:io';

import 'package:flutter/foundation.dart';

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import '../models/download_state.dart';
import '../models/song.dart';
import '../services/download_service.dart';
import '../state/player_controller.dart';
import '../theme/app_theme.dart';
import '../theme/desktop_tokens.dart';
import 'artwork_thumb.dart';
import 'desktop_context_menu.dart';
import 'motion.dart';
import 'page_transitions.dart' show reduceMotionEnabled;
import 'song_actions_sheet.dart';

/// A single row in any song list (Home rails use cards instead — see
/// RecentSongCard — this is for Library/Album/Playlist/Search/Queue lists).
/// Shows a track number instead of artwork when [index] is provided (album
/// detail track lists), a download-progress ring while downloading, and
/// opens the shared "⋮" actions sheet.
///
/// Row states follow the "Menus and states" board: hover = white 5% wash
/// with a play glyph over the number; playing = violet 14% wash, 3 px left
/// bar, violet title and the animated EQ bars (which hold still under
/// reduced motion — the state signal stays).
class SongTile extends StatefulWidget {
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
  State<SongTile> createState() => _SongTileState();
}

class _SongTileState extends State<SongTile> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final song = widget.song;
    final download =
        context.select<DownloadService, DownloadStatus>((s) => s.statusFor(song.id));
    final accent = song.gradientColors.last;
    // The board's Playing state: violet title + animated bars + violet wash
    // (highlighted is the caller's signal; the live player id confirms).
    final playing = widget.highlighted ||
        context.select<PlayerController, bool>((p) => p.currentSong?.id == song.id);

    return MouseRegion(
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: Stack(
        children: [
          // State wash behind the row (Rest = transparent).
          Positioned.fill(
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 120),
              decoration: BoxDecoration(
                color: playing
                    ? kBrandColor.withValues(alpha: 0.14)
                    : (_hover ? Colors.white.withValues(alpha: 0.05) : Colors.transparent),
                borderRadius: BorderRadius.circular(8),
              ),
            ),
          ),
          if (playing)
            const Positioned(left: 0, top: 10, bottom: 10, child: _RailBar()),
          ContextMenuRegion(
            items: songContextMenuItems(context, song),
            child: ListTile(
              onTap: widget.onTap,
              // Hold-to-open is touch-only now; desktop right-clicks.
              onLongPress: isDesktopPlatform
                  ? null
                  : () => showSongActionsSheet(context, song),
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 20, vertical: 2),
              leading: widget.index != null
                  ? SizedBox(
                      width: 44,
                      child: Center(
                        child: playing
                            ? const PlayingBars(size: 14)
                            : (_hover && !reduceMotionEnabled)
                                ? const Icon(Icons.play_arrow_rounded,
                                    color: Colors.white, size: 20)
                                : Text('${widget.index}',
                                    style: GoogleFonts.getFont(
                                        currentFontFamily,
                                        color: kMutedTextColor,
                                        fontSize: 13)),
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
                  color: playing ? kVioletPale : Colors.white,
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                ),
              ),
              subtitle: widget.showArtist
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
                        // A menu anchored to this button on desktop, the
                        // sheet everywhere else (design doc: "Menus").
                        // Long-press keeps the sheet on touch.
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
          ),
        ],
      ),
    );
  }
}

/// The 3px violet left bar for the playing row (mirrors the sidebar's).
class _RailBar extends StatelessWidget {
  const _RailBar();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 3,
      decoration: BoxDecoration(
        color: kBrandColor,
        borderRadius: BorderRadius.circular(1.5),
      ),
    );
  }
}
