import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import '../models/album.dart';
import '../theme/app_theme.dart';
import 'album_actions_sheet.dart';
import 'desktop_context_menu.dart';
import 'artwork_thumb.dart';

/// Grid/rail card used on Home, Library > Albums, Artist detail, and
/// Search. Sizes itself to whatever its parent gives it — wrap it in a
/// SizedBox(width: ...) for a horizontal rail, or drop it straight into a
/// GridView cell.
class AlbumCard extends StatelessWidget {
  final Album album;
  final VoidCallback onTap;

  const AlbumCard({super.key, required this.album, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return ContextMenuRegion(
      items: albumContextMenuItems(context, album),
      child: Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        onLongPress: () {
          HapticFeedback.mediumImpact();
          showAlbumActionsSheet(context, album);
        },
        child: Semantics(
          button: true,
          label: '${album.title} by ${album.artist}',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              // The cover yields space to the text: in a GridView cell the
              // text's intrinsic height depends on the device's font scale,
              // and a rigid square cover pushed title+artist past the cell —
              // "BOTTOM OVERFLOWED BY 28 PIXELS" on every tile under a larger
              // text scale. Flexible(loose) keeps the square aspect but lets
              // the cover shrink by exactly what the text needs.
              Flexible(
                child: AspectRatio(
                  aspectRatio: 1,
                  child: ArtworkThumb(
                    gradientColors: album.gradientColors,
                    artwork: album.artwork,
                    radius: 12,
                    icon: Icons.album_rounded,
                    iconSize: 32,
                  ),
                ),
              ),
              const SizedBox(height: 8),
              Text(album.title, maxLines: 1, overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.getFont(currentFontFamily, color: Colors.white, fontSize: 13, fontWeight: FontWeight.w500)),
              Text(album.artist, maxLines: 1, overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.getFont(currentFontFamily, color: Colors.white60, fontSize: 11)),
            ],
          ),
        ),
      ),
    ),
    );
  }
}
