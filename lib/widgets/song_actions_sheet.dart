import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import '../models/download_state.dart';
import '../models/song.dart';
import '../backend/subsonic_api.dart';
import '../screens/now_playing/audio_info_sheet.dart';
import '../screens/now_playing/lyrics_screen.dart';
import '../services/download_service.dart';
import '../services/server_link.dart';
import '../state/app_state.dart';
import '../state/player_controller.dart';
import '../theme/app_theme.dart';
import 'add_to_playlist_sheet.dart';
import 'artwork_thumb.dart';
import 'build_from_this_sheet.dart';
import 'shuro_icons.dart';
import 'state_views.dart';

/// The "⋮" menu every song gets, per the spec's "12. Context/action sheet".
void showSongActionsSheet(BuildContext context, Song song) {
  final player = context.read<PlayerController>();
  final appState = context.read<AppState>();
  final downloads = context.read<DownloadService>();

  showModalBottomSheet(
    context: context,
    // Required so the sheet may take up to the 85% height bounded below —
    // without it Flutter caps the sheet lower and the content Column has even
    // less room than the content needs.
    isScrollControlled: true,
    builder: (sheetContext) {
      return SafeArea(
        // The tile list is fixed in count but the window isn't fixed in height
        // (a 1080 px landscape window overflowed this sheet by 192 px), so the
        // content scrolls inside a bounded sheet instead of overflowing.
        child: ConstrainedBox(
          constraints: BoxConstraints(maxHeight: MediaQuery.of(sheetContext).size.height * 0.85),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
            const SizedBox(height: 8),
            Container(width: 36, height: 4, decoration: BoxDecoration(color: Colors.white24, borderRadius: BorderRadius.circular(2))),
            ListTile(
              leading: ArtworkThumb(gradientColors: song.gradientColors, artwork: song.artwork, size: 48, radius: 8),
              title: Text(song.title, maxLines: 1, overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.getFont(currentFontFamily, color: Colors.white, fontSize: 14, fontWeight: FontWeight.w600)),
              subtitle: Text(song.artist, maxLines: 1, overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.getFont(currentFontFamily, color: kMutedTextColor, fontSize: 12)),
            ),
            const Divider(height: 1, color: kDividerColor),
            _ActionTile(
              iconWidget: const ShuroIcon(ShuroGlyph.play, size: 20, color: Colors.white70),
              label: 'Play',
              onTap: () {
                Navigator.of(sheetContext).pop();
                player.playSong(song);
              },
            ),
            _ActionTile(
              icon: Icons.playlist_play_rounded,
              label: 'Play next',
              onTap: () {
                Navigator.of(sheetContext).pop();
                player.playNext(song);
              },
            ),
            _ActionTile(
              iconWidget: const ShuroIcon(ShuroGlyph.queueAdd, size: 20, color: Colors.white70),
              label: 'Add to queue',
              onTap: () {
                Navigator.of(sheetContext).pop();
                player.addToQueue(song);
              },
            ),
            _ActionTile(
              iconWidget: const ShuroIcon(ShuroGlyph.playlistAdd, size: 20, color: Colors.white70),
              label: 'Add to playlist',
              onTap: () {
                Navigator.of(sheetContext).pop();
                showAddToPlaylistSheet(context, song);
              },
            ),
            _ActionTile(
              icon: Icons.auto_awesome_rounded,
              label: 'Build from this',
              onTap: () {
                Navigator.of(sheetContext).pop();
                showBuildFromThisSheet(context, song);
              },
            ),
            AnimatedBuilder(
              animation: appState,
              builder: (context, _) {
                final isFav = appState.isFavoriteSong(song.id);
                return _ActionTile(
                  iconWidget: ShuroIcon(
                    isFav ? ShuroGlyph.heartFilled : ShuroGlyph.heartOutline,
                    size: 20,
                    color: isFav ? song.gradientColors.last : Colors.white70,
                  ),
                  label: isFav ? 'Remove from favorites' : 'Add to favorites',
                  onTap: () => Favorites.toggle(sheetContext, song.id),
                );
              },
            ),
            // Real downloads: the file lands on disk (documents/downloads, or
            // the user's chosen folder) at original quality, and survives app
            // updates. Status comes from the download service, not AppState.
            AnimatedBuilder(
              animation: downloads,
              builder: (context, _) {
                final status = downloads.statusFor(song.id);
                final downloaded = status.stage == DownloadStage.downloaded;
                final downloading = status.stage == DownloadStage.downloading;
                return _ActionTile(
                  iconWidget: downloaded
                      ? const Icon(Icons.delete_outline_rounded, color: Colors.white70)
                      : downloading
                          ? const Icon(Icons.close_rounded, color: Colors.white70)
                          : const ShuroIcon(ShuroGlyph.download, size: 20, color: Colors.white70),
                  label: downloaded ? 'Remove download' : downloading ? 'Cancel download' : 'Download (original quality)',
                  onTap: () async {
                    if (downloaded || downloading) {
                      await downloads.remove(song.id);
                      return;
                    }
                    if (!appState.canDownloadNow) {
                      showErrorSnackBar(context, "You're on mobile data and Downloads → Wi-Fi only is on.");
                      return;
                    }
                    final api = sheetContext.read<ServerSession>().api;
                    if (api == null) {
                      showErrorSnackBar(context, 'Connect to a server to download.');
                      return;
                    }
                    showSuccessSnackBar(context, 'Downloading "${song.title}"…');
                    final ok = await downloads.start(song, api.downloadUrl(song.id));
                    if (!ok) showErrorSnackBar(context, 'Download failed.');
                  },
                );
              },
            ),
            _ActionTile(
              icon: Icons.info_outline_rounded,
              label: 'Audio information',
              onTap: () {
                Navigator.of(sheetContext).pop();
                showAudioInfoSheet(context, song);
              },
            ),
            _ActionTile(
              icon: Icons.mic_external_on_rounded,
              label: 'Lyrics',
              onTap: () {
                Navigator.of(sheetContext).pop();
                openLyricsScreen(context, song);
              },
            ),
            // Server star rating — only when a server is connected. The live
            // value is fetched rather than guessed from the local model, so
            // what the sheet shows is what the server has.
            if (sheetContext.read<ServerSession>().hasServer)
              _RatingRow(songId: song.id, accent: song.gradientColors.last),
            const SizedBox(height: 8),
          ],
            ),
          ),
        ),
      );
    },
  );
}

/// Five-tap star rating backed by the server's setRating. Loads the current
/// rating live (getSong), updates optimistically on tap, and pushes the new
/// value fire-and-forget — a failed submit leaves the optimistic value on
/// screen but the server untouched; the next sheet open shows the truth.
class _RatingRow extends StatefulWidget {
  final String songId;
  final Color accent;

  const _RatingRow({required this.songId, required this.accent});

  @override
  State<_RatingRow> createState() => _RatingRowState();
}

class _RatingRowState extends State<_RatingRow> {
  int? _rating;
  bool _loaded = false;

  @override
  void initState() {
    super.initState();
    final api = context.read<ServerSession>().api;
    api?.getSong(widget.songId).then((song) {
      if (!mounted) return;
      setState(() {
        _rating = (song?['userRating'] as num?)?.toInt();
        _loaded = true;
      });
    }).catchError((_) {
      if (mounted) setState(() => _loaded = true);
    });
  }

  void _set(int value) {
    final api = context.read<ServerSession>().api;
    setState(() => _rating = value == _rating ? 0 : value); // tapping the same star clears
    api?.setRating(widget.songId, _rating!).catchError((_) {});
  }

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: const Icon(Icons.star_outline_rounded, color: Colors.white70),
      title: Row(
        children: [
          for (var i = 1; i <= 5; i++)
            GestureDetector(
              onTap: () => _set(i),
              child: Padding(
                padding: const EdgeInsets.only(right: 4),
                child: Icon(
                  (_rating ?? 0) >= i ? Icons.star_rounded : Icons.star_outline_rounded,
                  size: 22,
                  color: (_rating ?? 0) >= i ? widget.accent : Colors.white38,
                ),
              ),
            ),
          if (!_loaded)
            const Padding(
              padding: EdgeInsets.only(left: 6),
              child: SizedBox(width: 10, height: 10, child: CircularProgressIndicator(strokeWidth: 1.6, color: Colors.white38)),
            ),
        ],
      ),
    );
  }
}

class _ActionTile extends StatelessWidget {
  final IconData? icon;
  final Widget? iconWidget;
  final Color? iconColor;
  final String label;
  final VoidCallback onTap;

  const _ActionTile({this.icon, this.iconWidget, required this.label, required this.onTap, this.iconColor});

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: iconWidget ?? Icon(icon, color: iconColor ?? Colors.white70),
      title: Text(label, style: GoogleFonts.getFont(currentFontFamily, color: Colors.white, fontSize: 14)),
      onTap: onTap,
    );
  }
}
