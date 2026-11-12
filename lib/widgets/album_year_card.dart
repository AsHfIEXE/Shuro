import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../models/album.dart';
import '../theme/app_theme.dart';
import 'artwork_thumb.dart';
import 'click_region.dart';
import 'desktop_context_menu.dart';
import 'motion.dart';

/// Rail card from the Artist / Album detail boards: square cover, title and
/// release year underneath, with the hover lift and the album context menu.
class AlbumYearCard extends StatelessWidget {
  final Album album;
  final VoidCallback onTap;
  final double size;

  const AlbumYearCard({super.key, required this.album, required this.onTap, this.size = 168});

  @override
  Widget build(BuildContext context) {
    return ContextMenuRegion(
      items: albumContextMenuItems(context, album),
      child: ClickRegion(
        onTap: onTap,
        child: SizedBox(
          width: size,
          child: HoverLift(
            radius: BorderRadius.circular(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                ArtworkThumb(
                  gradientColors: album.gradientColors,
                  artwork: album.artwork,
                  size: size,
                  radius: 12,
                  icon: Icons.album_rounded,
                  iconSize: 32,
                ),
                const SizedBox(height: 8),
                Text(album.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: GoogleFonts.getFont(currentFontFamily,
                        color: kTextColor, fontSize: 13, fontWeight: FontWeight.w600)),
                Text(album.year > 0 ? '${album.year}' : '—',
                    style: GoogleFonts.getFont(currentFontFamily, color: kMuted2, fontSize: 12)),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
